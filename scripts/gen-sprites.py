#!/usr/bin/env python3
"""Draw the buddy sprites with Nano Banana (Gemini image generation), then clean them into crisp pixel sprites.

  python3 scripts/gen-sprites.py --test            # just Scout's base drawing, to check the style
  python3 scripts/gen-sprites.py                   # every buddy and expression
  python3 scripts/gen-sprites.py --only dog,owl    # some buddies

Each buddy's base drawing is generated first; every expression is then an edit of that image ("same
character, eyes closed"), so the frames stay consistent. Gemini can't return transparency, so it draws on
solid magenta, which is keyed out. Each drawn block becomes one real pixel, keeping the exact colors.

Needs GEMINI_API_KEY in the environment or in ~/.config/lookout/secrets.env. The key is never printed.
Raw images go to build/sprites-raw/; finished sprites to Resources/sprites/<buddy>-<face>.png.
"""
import argparse, base64, json, os, ssl, sys, urllib.error, urllib.request
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "build" / "sprites-raw"
OUT = ROOT / "Resources" / "sprites"
MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-3-pro-image")
GRID = 32  # fallback when the block size can't be found

STYLE = ("Cute 8-bit pixel-art game sprite, about 32 by 32 pixels, chunky square pixels, bold black outline, "
         "flat bright colors, no gradients, no shading noise. Just the character's head, front-facing, centered, "
         "completely inside the frame with a clear margin on every side (nothing cut off), friendly and gentle for "
         "an older adult. The background is one flat pure magenta (#FF00FF) color filling the entire square image "
         "edge to edge, with no other background, frame, border, text or ground shadow.")

BUDDIES = {
    "dog": "Scout, a friendly beagle puppy: floppy brown ears, tan face, white muzzle, black nose, small pink tongue",
    "owl": "Hoot, a round gray owl: big white eyes with black pupils, ear tufts, orange beak and feet, light gray belly",
    "mouse": "Mouse, a small gray mouse: big round ears with pink insides, black eyes, pink nose, whiskers",
    "chick": "Clicken, a round yellow baby chick: orange beak and feet, little wings, black eyes",
}

FACES = {
    "blink": "the eyes are closed (a short horizontal line for each eye)",
    "talk": "the mouth (or beak) is open as if talking",
    "look": "the eyes look upward, attentive, as if listening",
    "happy": "a big happy smile with closed, curved happy eyes",
    "alarmed": "wide surprised eyes and a small open 'o' mouth, worried",
}


def api_key():
    k = os.environ.get("GEMINI_API_KEY")
    if not k:
        f = Path.home() / ".config" / "lookout" / "secrets.env"
        if f.exists():
            for line in f.read_text().splitlines():
                if line.strip().startswith("GEMINI_API_KEY="):
                    k = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not k:
        sys.exit("No GEMINI_API_KEY (set it, or add GEMINI_API_KEY=... to ~/.config/lookout/secrets.env).")
    return k


def generate(prompt, ref=None):
    parts = [{"text": prompt}]
    if ref is not None:
        parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(ref.read_bytes()).decode()}})
    body = {"contents": [{"parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "1:1"}}}
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
        data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key()})
    # python.org builds ship without CA certificates; use the system bundle.
    ctx = ssl.create_default_context(cafile="/etc/ssl/cert.pem") if Path("/etc/ssl/cert.pem").exists() else None
    try:
        with urllib.request.urlopen(req, timeout=120, context=ctx) as r:
            resp = json.load(r)
    except urllib.error.HTTPError as e:
        msg = json.loads(e.read().decode() or "{}").get("error", {}).get("message", "")
        sys.exit(f"Gemini said no (HTTP {e.code}): {msg.splitlines()[0] if msg else ''}"
                 + ("\nImage generation needs billing turned on for this key's project in AI Studio." if e.code == 429 else ""))
    for cand in resp.get("candidates", []):
        for p in cand.get("content", {}).get("parts", []):
            data = p.get("inline_data") or p.get("inlineData")
            if data:
                return base64.b64decode(data["data"])
    raise RuntimeError("no image in response: " + json.dumps(resp)[:300])


def clean(raw_path, out_path, size=None):
    """Key out the background, crop to the character, and turn each drawn block into one real pixel."""
    im = Image.open(raw_path).convert("RGBA")
    px = im.load()
    # Background: background-colored pixels reachable from the image edge. That removes the magenta and any
    # smudges or canvas the model adds, while pinks inside the outline (a tongue, ears) are left alone.
    W, H = im.size
    corners = [px[0, 0], px[W - 1, 0], px[0, H - 1], px[W - 1, H - 1]]
    clear = bytearray(W * H)
    stack = [(x, y) for x in range(W) for y in (0, H - 1)] + [(x, y) for y in range(H) for x in (0, W - 1)]
    while stack:
        x, y = stack.pop()
        i = y * W + x
        if clear[i]:
            continue
        c = px[x, y]
        r, g, b, _ = c
        # Only background-looking colors: magenta, the corner color, or a pinkish smudge. The outline stops it.
        magenta = r > 90 and b > 90 and g < min(r, b) - 30
        if not (magenta or any(all(abs(c[i] - k[i]) <= 40 for i in range(3)) for k in corners)):
            continue
        clear[i] = 1
        if x > 0: stack.append((x - 1, y))
        if x < W - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < H - 1: stack.append((x, y + 1))
    for y in range(H):
        for x in range(W):
            if clear[y * W + x]:
                px[x, y] = (0, 0, 0, 0)
    drop_specks(im)
    box = im.getbbox()
    if box:
        im = im.crop(box)
    # The drawing is made of big square "pixels". Find their size from the most common run length of
    # one color along rows, then take one sample from the middle of each block: exact colors, no blur.
    if size:
        w, h = size  # match the buddy's base drawing, so expressions never change size
    else:
        block = pixel_size(im)
        w, h = max(1, round(im.width / block)), max(1, round(im.height / block))
    src = im.load()
    small = Image.new("RGBA", (w, h))
    dst = small.load()
    for y in range(h):
        for x in range(w):
            c = src[min(im.width - 1, int((x + 0.5) * im.width / w)), min(im.height - 1, int((y + 0.5) * im.height / h))]
            dst[x, y] = c if c[3] > 0 else (0, 0, 0, 0)
    side = max(w, h)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(small, ((side - w) // 2, (side - h) // 2))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sq.save(out_path)
    sq.resize((side * 8, side * 8), Image.Resampling.NEAREST).save(out_path.with_name(out_path.stem + "@preview.png"))
    return (w, h)


def drop_specks(im):
    """Clear little leftover islands (stray background specks), keeping the character itself."""
    a = im.getchannel("A")
    small = a.resize((a.width // 4, a.height // 4), Image.Resampling.NEAREST)
    W, H = small.size
    m = small.load()
    seen = [[False] * W for _ in range(H)]
    comps = []
    for y in range(H):
        for x in range(W):
            if m[x, y] and not seen[y][x]:
                stack, pts = [(x, y)], []
                seen[y][x] = True
                while stack:
                    cx, cy = stack.pop()
                    pts.append((cx, cy))
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < W and 0 <= ny < H and m[nx, ny] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
                comps.append(pts)
    if not comps:
        return
    biggest = max(len(c) for c in comps)
    px = im.load()
    for c in comps:
        if len(c) < biggest * 0.02:
            for (x, y) in c:
                for yy in range(y * 4, min(im.height, y * 4 + 4)):
                    for xx in range(x * 4, min(im.width, x * 4 + 4)):
                        px[xx, yy] = (0, 0, 0, 0)


def pixel_size(im):
    px = im.load()
    runs = {}
    for y in range(0, im.height, 3):
        run, prev = 0, None
        for x in range(im.width):
            c = px[x, y]
            same = prev is not None and all(abs(c[i] - prev[i]) <= 24 for i in range(4))
            if same:
                run += 1
            else:
                if run >= 6:
                    runs[run] = runs.get(run, 0) + 1
                run, prev = 1, c
    if not runs:
        return max(1, im.width // GRID)
    # The block size is the smallest run length that shows up a lot (longer runs are several blocks in a row).
    top = max(runs.values())
    common = sorted(r for r, n in runs.items() if n >= top * 0.35)
    base = common[0]
    # Average the neighbours of that length, since edges make runs off by a pixel or two.
    near = [(r, n) for r, n in runs.items() if abs(r - base) <= 2]
    return sum(r * n for r, n in near) / sum(n for _, n in near)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="only Scout's base drawing")
    ap.add_argument("--only", help="comma-separated buddies (dog,owl,mouse,chick)")
    ap.add_argument("--faces", action="store_true", help="only redo expressions, reusing existing base drawings")
    ap.add_argument("--reclean", action="store_true", help="no new drawings: just re-clean the saved raw images")
    args = ap.parse_args()
    names = ["dog"] if args.test else (args.only.split(",") if args.only else list(BUDDIES))
    RAW.mkdir(parents=True, exist_ok=True)
    if args.reclean:
        for n in names:
            size = clean(RAW / f"{n}-base.png", OUT / f"{n}-base.png")
            for f in FACES:
                if (RAW / f"{n}-{f}.png").exists():
                    clean(RAW / f"{n}-{f}.png", OUT / f"{n}-{f}.png", size)
        print(f"re-cleaned. sprites in {OUT}")
        return
    for n in names:
        base = RAW / f"{n}-base.png"
        if not (args.faces and base.exists()):
            print(f"drawing {n}…", flush=True)
            base.write_bytes(generate(f"{STYLE} The character: {BUDDIES[n]}."))
        size = clean(base, OUT / f"{n}-base.png")
        if args.test:
            continue
        for f, change in FACES.items():
            print(f"  {n} {f}…", flush=True)
            raw = RAW / f"{n}-{f}.png"
            raw.write_bytes(generate(
                "Redraw this exact same pixel-art character: same size, same position, same pose, same colors, "
                f"same outline and the same magenta background. Change only this: {change}.", ref=base))
            clean(raw, OUT / f"{n}-{f}.png", size)
    print(f"done. sprites in {OUT}")


if __name__ == "__main__":
    main()
