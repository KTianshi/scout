import AppKit
import CoreGraphics
import Foundation
import ScoutCore

/// "Make your own buddy": draws a custom buddy with Nano Banana (Gemini's image model) from a short
/// description and, optionally, a photo (a pet, say). Same recipe as scripts/gen-sprites.py: one base
/// drawing, then each expression as an edit of it, each cleaned into a crisp pixel sprite.
/// Opt-in only; the description and photo go to Google. Needs GEMINI_API_KEY in secrets.env.
@MainActor
final class BuddyMaker: ObservableObject {
    static let shared = BuddyMaker()

    @Published var working = false
    @Published var progress = ""
    @Published var error: String?
    /// Bumped whenever a new custom buddy is saved, so views reload its pictures.
    @Published var version = 0

    static let model = ProcessInfo.processInfo.environment["GEMINI_IMAGE_MODEL"] ?? "gemini-3-pro-image"
    static var hasKey: Bool { !(Secrets.shared["GEMINI_API_KEY"] ?? "").isEmpty }
    nonisolated static let dir = Log.dir.appendingPathComponent("buddies", isDirectory: true)

    nonisolated static var customName: String {
        get { UserDefaults.standard.string(forKey: "customBuddyName") ?? "My buddy" }
        set { UserDefaults.standard.set(newValue, forKey: "customBuddyName") }
    }
    nonisolated static var hasCustom: Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent("custom-base.png").path) }

    static let style = "Cute 8-bit pixel-art game sprite, about 32 by 32 pixels, chunky square pixels, bold black outline, "
        + "flat bright colors, no gradients, no shading noise. Just the character's head, front-facing, centered, "
        + "completely inside the frame with a clear margin on every side (nothing cut off), friendly and gentle for "
        + "an older adult. Eyes are black with a small white shine. The background is one flat pure magenta (#FF00FF) "
        + "color filling the entire square image edge to edge, with no other background, frame, border, text or ground shadow."

    static let faces: [(SpriteFace, String)] = [
        (.blink, "the eyes are closed (a short horizontal line for each eye)"),
        (.talk, "the mouth (or beak) is open as if talking"),
        (.look, "the eyes look upward, attentive, as if listening"),
        (.happy, "closed, curved happy eyes; keep the mouth or beak as it is, don't add a separate smile"),
        (.alarmed, "wide surprised eyes and a small open mouth, worried"),
    ]

    /// Draws the buddy: the base first (so it shows up quickly), then the five expressions.
    func make(name: String, description: String, photo: URL?) async {
        guard !working else { return }
        guard Self.hasKey else { error = "Add a Gemini key (GEMINI_API_KEY) to secrets.env to make a buddy."; return }
        working = true
        error = nil
        defer { working = false; progress = "" }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("buddy-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let what = description.trimmingCharacters(in: .whitespacesAndNewlines)
            var prompt = Self.style + " The character: \(what.isEmpty ? name : what)."
            var ref: Data?
            if let photo {
                ref = Self.photoJPEG(photo)
                prompt += " Base the character on the animal or person in this photo: its colors and markings, as a cute pixel sprite."
            }
            progress = "Drawing \(name)…"
            let raw = try await Self.generate(prompt, image: ref)
            guard let base = SpriteCleaner.clean(raw) else { throw MakerError("That drawing didn't come out clearly. Try again.") }
            try base.png.write(to: tmp.appendingPathComponent("custom-base.png"))

            for (i, (face, change)) in Self.faces.enumerated() {
                progress = "Adding expressions (\(i + 1) of \(Self.faces.count))…"
                let edit = try await Self.generate(
                    "Redraw this exact same pixel-art character: same size, same position, same pose, same colors, "
                        + "same outline and the same magenta background. Change only this: \(change).", image: raw)
                if let s = SpriteCleaner.clean(edit, size: base.size) {
                    try s.png.write(to: tmp.appendingPathComponent("custom-\(face).png"))
                }
            }
            // Swap the finished set in all at once.
            let fm = FileManager.default
            try? fm.removeItem(at: Self.dir)
            try fm.createDirectory(at: Self.dir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: tmp, to: Self.dir)
            Self.customName = name
            SpriteArt.forget(.custom)
            version += 1
            Log.info("buddy maker: made a custom buddy")
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            self.error = (error as? MakerError)?.message ?? "Couldn't make the buddy: \(error.localizedDescription)"
            Log.info("buddy maker failed: \(error.localizedDescription)")
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: Self.dir)
        SpriteArt.forget(.custom)
        version += 1
    }

    struct MakerError: Error { let message: String; init(_ m: String) { message = m } }

    /// The photo, shrunk to at most 1024 px and re-encoded as JPEG (drops location and other metadata).
    static func photoJPEG(_ url: URL) -> Data? {
        guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1024 / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// One Gemini image call. Returns the image bytes.
    static func generate(_ prompt: String, image: Data?) async throws -> Data {
        var parts: [[String: Any]] = [["text": prompt]]
        if let image {
            let mime = image.starts(with: [0x89, 0x50]) ? "image/png" : "image/jpeg"
            parts.append(["inline_data": ["mime_type": mime, "data": image.base64EncodedString()]])
        }
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["responseModalities": ["IMAGE"], "imageConfig": ["aspectRatio": "1:1"]],
        ]
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 150
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.shared["GEMINI_API_KEY"], forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            if code == 429 { throw MakerError("Gemini is out of image credit for this key. Check billing in Google AI Studio.") }
            let msg = (obj?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
            throw MakerError("Gemini said no: \(msg.split(separator: "\n").first ?? "")")
        }
        for cand in obj?["candidates"] as? [[String: Any]] ?? [] {
            for p in (cand["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] {
                if let d = (p["inline_data"] ?? p["inlineData"]) as? [String: Any], let b64 = d["data"] as? String,
                   let bytes = Data(base64Encoded: b64) { return bytes }
            }
        }
        throw MakerError("Gemini didn't send a picture back. Try a different description.")
    }
}

/// Turns a generated drawing into a crisp sprite (the Swift twin of clean() in scripts/gen-sprites.py):
/// remove the background, crop to the character, and turn each drawn block into exactly one pixel.
enum SpriteCleaner {
    struct Sprite { var png: Data; var size: (Int, Int) }

    static func clean(_ data: Data, size: (Int, Int)? = nil) -> Sprite? {
        guard let src = NSBitmapImageRep(data: data)?.cgImage else { return nil }
        let W = src.width, H = src.height
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: W, height: H))

        func rgb(_ i: Int) -> (Int, Int, Int) { (Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) }
        // Background: magenta-ish or corner-colored pixels reachable from the edge.
        let corners = [0, W - 1, (H - 1) * W, H * W - 1].map(rgb)
        func background(_ c: (Int, Int, Int)) -> Bool {
            if c.0 > 55 && c.2 > 55 && c.1 < min(c.0, c.2) - 30 { return true }
            return corners.contains { abs($0.0 - c.0) <= 40 && abs($0.1 - c.1) <= 40 && abs($0.2 - c.2) <= 40 }
        }
        var clear = [Bool](repeating: false, count: W * H)
        var stack: [Int] = []
        for x in 0..<W { stack.append(x); stack.append((H - 1) * W + x) }
        for y in 0..<H { stack.append(y * W); stack.append(y * W + W - 1) }
        while let i = stack.popLast() {
            if clear[i] || !background(rgb(i)) { continue }
            clear[i] = true
            let x = i % W, y = i / W
            if x > 0 { stack.append(i - 1) }
            if x < W - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - W) }
            if y < H - 1 { stack.append(i + W) }
        }
        dropSpecks(&clear, W, H)

        // Crop to what's left.
        var minX = W, minY = H, maxX = -1, maxY = -1
        for y in 0..<H { for x in 0..<W where !clear[y * W + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX, maxY > minY else { return nil }
        let cw = maxX - minX + 1, ch = maxY - minY + 1

        let (w, h): (Int, Int)
        if let size { (w, h) = size } else {
            let block = blockSize(px, clear, W, minX, minY, cw, ch)
            (w, h) = (max(1, Int((Double(cw) / block).rounded())), max(1, Int((Double(ch) / block).rounded())))
        }
        guard w > 4, h > 4, w <= 64, h <= 64 else { return nil }

        // One sample from the middle of each block, centered in a square.
        let side = max(w, h)
        var out = [UInt8](repeating: 0, count: side * side * 4)
        let ox = (side - w) / 2, oy = (side - h) / 2
        for y in 0..<h { for x in 0..<w {
            let sx = minX + min(cw - 1, Int((Double(x) + 0.5) * Double(cw) / Double(w)))
            let sy = minY + min(ch - 1, Int((Double(y) + 0.5) * Double(ch) / Double(h)))
            let si = sy * W + sx
            guard !clear[si] else { continue }
            let di = ((oy + y) * side + ox + x) * 4
            out[di] = px[si * 4]; out[di + 1] = px[si * 4 + 1]; out[di + 2] = px[si * 4 + 2]; out[di + 3] = 255
        } }
        guard let octx = CGContext(data: &out, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = octx.makeImage(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return nil }
        return Sprite(png: png, size: (w, h))
    }

    /// Clears small islands left over from the background, keeping the character.
    static func dropSpecks(_ clear: inout [Bool], _ W: Int, _ H: Int) {
        var label = [Int](repeating: -1, count: W * H)
        var sizes: [Int] = []
        for start in 0..<(W * H) where !clear[start] && label[start] < 0 {
            let id = sizes.count
            var count = 0, stack = [start]
            label[start] = id
            while let i = stack.popLast() {
                count += 1
                let x = i % W, y = i / W
                for n in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1]
                where n >= 0 && !clear[n] && label[n] < 0 {
                    label[n] = id
                    stack.append(n)
                }
            }
            sizes.append(count)
        }
        guard let biggest = sizes.max() else { return }
        for i in 0..<(W * H) where label[i] >= 0 && sizes[label[i]] < biggest / 50 { clear[i] = true }
    }

    /// The size of the drawing's square "pixels": the smallest frequent run length of one color along rows.
    static func blockSize(_ px: [UInt8], _ clear: [Bool], _ W: Int, _ x0: Int, _ y0: Int, _ cw: Int, _ ch: Int) -> Double {
        var runs: [Int: Int] = [:]
        for y in stride(from: y0, to: y0 + ch, by: 3) {
            var run = 0
            var prev: (Int, Int, Int, Bool)?
            for x in x0..<(x0 + cw) {
                let i = y * W + x
                let c = (Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2]), clear[i])
                if let p = prev, p.3 == c.3, abs(p.0 - c.0) <= 24, abs(p.1 - c.1) <= 24, abs(p.2 - c.2) <= 24 {
                    run += 1
                } else {
                    if run >= 6 { runs[run, default: 0] += 1 }
                    run = 1
                    prev = c
                }
            }
        }
        guard let top = runs.values.max() else { return Double(max(cw, ch)) / 32 }
        let base = runs.filter { Double($0.value) >= Double(top) * 0.35 }.keys.min() ?? 32
        let near = runs.filter { abs($0.key - base) <= 2 }
        let total = near.values.reduce(0, +)
        return Double(near.reduce(0) { $0 + $1.key * $1.value }) / Double(max(1, total))
    }
}
