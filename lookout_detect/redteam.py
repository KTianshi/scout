"""Red-team sessions written by Claude, for held-out evaluation.

Claude writes what an older adult's Mac would show, screen by screen, during a scam (or a benign look-alike).
We never hand Claude our event list or model; screens go through the app's real extractor like any other.
The session label comes from the kind we asked for, not from Claude.

    .venv/bin/python -m lookout_detect.redteam --per-kind 10 --out eval/sessions_redteam.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import anthropic

MODEL = "claude-sonnet-5-5"

SCAM_KINDS = {
    "tech_support": ("a fake tech-support scam", ["popup", "call", "remote", "banking", "payment"]),
    "refund": ("a refund / overpayment scam that starts with a fake invoice or renewal notice", ["invoice", "call", "remote", "overpay", "payment"]),
    "grandparent": ("a grandparent emergency scam (someone pretending to be a grandchild in trouble)", ["contact", "story", "secrecy", "payment"]),
    "government": ("a government impersonation scam (IRS, Social Security, Medicare, police)", ["notice", "threat", "payment"]),
}
BENIGN_KINDS = {
    "remote_help": "a grandchild or adult child helping over AnyDesk, TeamViewer or macOS Screen Sharing (fixing the printer, updating software, sometimes looking at the bank site together)",
    "gift_shopping": "buying a gift card as a birthday present on a normal retail site",
    "banking": "ordinary online banking: checking a statement, paying a utility bill",
    "reading_about_scams": "reading news articles, AARP alerts or bank fraud tips about scams",
    "legit_notices": "real notices: a genuine subscription renewal email with no phone number, a real IRS or SSA web page, a real delivery notification",
    "family_money": "a real grandchild casually asking for a little money (e.g. $20 on Venmo for a movie), with no pressure or secrecy",
}

SCHEMA = {
    "type": "object",
    "properties": {
        "screens": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "app": {"type": "string", "description": "frontmost app, e.g. Safari, Mail, Messages, AnyDesk"},
                    "url": {"type": "string", "description": "address bar URL, or empty"},
                    "text": {"type": "string", "description": "the visible text as an accessibility reader would read it, 30-160 words"},
                    "remote_app_running": {"type": "string", "description": "name of a running remote-control app (AnyDesk, TeamViewer, Screen Sharing...) or empty"},
                    "sensitive_fields": {"type": "array", "items": {"type": "string", "enum": ["card", "gift-card", "ssn", "bank", "password"]}},
                    "seconds_since_previous": {"type": "integer"},
                    "stage": {"type": "string"},
                },
                "required": ["app", "url", "text", "remote_app_running", "sensitive_fields", "seconds_since_previous", "stage"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["screens"],
    "additionalProperties": False,
}

SYSTEM = (
    "You write realistic test data for Lookout, a program that protects older adults from scams on their Mac. "
    "Write one session: the sequence of screens the person's Mac shows, in order. Make it realistic and varied, "
    "like real cases reported to the FTC and AARP: real tactics, plausible wording, and some ordinary screens in between "
    "(email, news, photos). Not every step has to be visible: phone calls happen off-screen. "
    "Use only fake phone numbers in the 555-01xx range and made-up domains for scammers; real company domains are fine "
    "for genuine sites. 6 to 14 screens."
)


def prompt(kind: str, variant: int) -> tuple[str, str, str]:
    r = random.Random(variant * 7919 + hash(kind) % 1000)
    style = r.choice(["subtle and polite", "aggressive and urgent", "slow, over two hours", "with a typo-ridden scammer",
                      "very professional", "mixing email and text messages", "starting from a web search"])
    if kind in SCAM_KINDS:
        desc, stages = SCAM_KINDS[kind]
        return ("scam", kind, f"Session type: {desc}. Style: {style}. Label each screen's stage with one of {stages} or 'neutral'. "
                f"The scam may skip steps or end before money is sent. Variant #{variant}.")
    return ("benign", kind, f"Session type: {BENIGN_KINDS[kind]}. This is NOT a scam. Style: {style}. "
            f"Label screens 'benign' or 'neutral'. Variant #{variant}.")


def generate_one(client, kind: str, variant: int) -> dict | None:
    label, kind, user = prompt(kind, variant)
    try:
        resp = client.messages.create(
            model=MODEL, max_tokens=8000, system=SYSTEM,
            messages=[{"role": "user", "content": user}],
            output_config={"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
            extra_headers={"anthropic-beta": "server-side-fallback-2026-07-01"},
            extra_body={"fallbacks": "default"},
        )
    except anthropic.APIStatusError as e:
        print(f"[{kind} {variant}] API error {e.status_code}", file=sys.stderr)
        return None
    except anthropic.APIConnectionError as e:
        print(f"[{kind} {variant}] connection error {e}", file=sys.stderr)
        return None
    if resp.stop_reason == "refusal":
        print(f"[{kind} {variant}] refused", file=sys.stderr)
        return None
    text = next((b.text for b in resp.content if b.type == "text"), "")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        print(f"[{kind} {variant}] bad JSON", file=sys.stderr)
        return None
    t = 1000.0
    screens = []
    for s in data["screens"]:
        t += max(5, int(s.get("seconds_since_previous", 60)))
        apps = ["Safari", "Mail", "Messages"] + ([s["remote_app_running"]] if s.get("remote_app_running") else [])
        stage = s.get("stage", "neutral")
        stage = f"{kind}:{stage}" if label == "scam" and stage != "neutral" else ("neutral" if stage == "neutral" else f"benign:{kind}")
        screens.append(dict(t=t, text=s["text"], url=s.get("url") or None, app=s.get("app") or "Safari", apps=sorted(set(apps)),
                            sensitive=s.get("sensitive_fields", []), stage=stage))
    return dict(id=f"redteam-{kind}-{variant:02d}", label=label, kind=kind, abandoned=False, source="redteam", screens=screens)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-kind", type=int, default=10)
    ap.add_argument("--out", default="eval/sessions_redteam.jsonl")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--offset", type=int, default=0, help="variant number offset, for a fresh set (e.g. 100)")
    ap.add_argument("--tag", default="", help="id prefix tag, e.g. B")
    a = ap.parse_args()
    client = anthropic.Anthropic(max_retries=3)
    jobs = [(k, v + a.offset) for k in list(SCAM_KINDS) + list(BENIGN_KINDS) for v in range(a.per_kind)]
    out = []
    with ThreadPoolExecutor(a.workers) as ex:
        futs = {ex.submit(generate_one, client, k, v): (k, v) for k, v in jobs}
        for f in as_completed(futs):
            s = f.result()
            if s:
                if a.tag:
                    s["id"] = s["id"].replace("redteam-", f"redteam{a.tag}-")
                    s["source"] = f"redteam{a.tag}"
                out.append(s)
    out.sort(key=lambda s: s["id"])
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    with open(a.out, "w") as f:
        for s in out:
            f.write(json.dumps(s) + "\n")
    print(f"wrote {len(out)}/{len(jobs)} sessions to {a.out}")


if __name__ == "__main__":
    main()
