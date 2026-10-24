import AppKit
import LookoutCore

/// Runs the whole pipeline on a file instead of the live screen and prints what Lookout would do.
@MainActor
final class FixtureRunner {
    let path: String
    let text: String?
    let apps: [String]
    let question: String?
    let useModel: Bool

    init(path: String, text: String?, apps: [String], question: String?, useModel: Bool) {
        self.path = path; self.text = text; self.apps = apps; self.question = question; self.useModel = useModel
    }

    func line(_ s: String) { print(s); fflush(stdout) }

    func run() async -> Int32 {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { line("fixture not found: \(path)"); return 2 }
        var snap: Snapshot
        var label: String?
        if url.pathExtension.lowercased().hasPrefix("htm") {
            let browser = DemoBrowser(visible: false)
            await browser.load(url)
            guard let s = await browser.snapshot(runningApps: apps, includeImage: true, mapToScreen: false) else { line("could not read page"); return 3 }
            snap = s
            label = (try? String(contentsOf: url, encoding: .utf8)).flatMap { FixtureText.context(fromHTML: $0).label }
        } else {
            guard let img = NSImage(contentsOf: url), let full = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let jpeg = ImageUtil.jpeg(ImageUtil.downscale(full, maxEdge: LookoutConfig.screenshotMaxEdge), quality: 0.75) else { line("could not read image"); return 3 }
            let cg = ImageUtil.downscale(full, maxEdge: LookoutConfig.screenshotMaxEdge)
            let sidecar = url.deletingPathExtension().appendingPathExtension("txt")
            let t = text ?? (try? String(contentsOf: sidecar, encoding: .utf8)) ?? ""
            snap = Snapshot(context: ScreenContext(text: t, runningApps: apps))
            snap.image = ClaudeClient.Image(data: jpeg, width: cg.width, height: cg.height)
            snap.isFixture = true
        }
        if let text, url.pathExtension.lowercased().hasPrefix("htm") { snap.context.text += "\n" + text }

        line("== Lookout fixture: \(url.lastPathComponent)\(label.map { " (label: \($0))" } ?? "")")
        line("url=\(snap.context.url ?? "-") app=\(snap.context.appName ?? "-") sensitive=\(snap.context.sensitiveFields) image=\(snap.image.map { "\($0.width)x\($0.height)" } ?? "none") elements=\(snap.elements.count)")
        let pipeline = ScamPipeline()
        var result = pipeline.evaluate(snap.context)
        line("heuristics: \(result.summary)")
        let claude = ClaudeClient()
        var verdict: ScamVerdict?
        var sender: SenderCheck?
        if let email = SenderCheck.extractSender(snap.context) {
            sender = useModel ? await FamilyClient().checkSender(email) : nil
            line("sender: \(email) → CRS \(sender.map { "\($0.verdict.rawValue) score=\($0.score.map(String.init) ?? "-") firstSeen=\($0.firstSeen ?? "-") (\($0.source))" } ?? "not checked (family server not running or --no-model)")")
        }
        if useModel && result.shouldConfirmWithModel {
            if claude.isConfigured {
                let t0 = Date()
                do {
                    let v = try await claude.confirmScam(screen: snap.context, image: snap.image, heuristicSummary: result.summary)
                    verdict = v
                    result = pipeline.applyModelVerdict(v, ctx: snap.context, sender: sender)
                    line(String(format: "claude (%.1fs): scam=%@ conf=%.2f type=%@ point=%@", Date().timeIntervalSince(t0), v.isScam ? "yes" : "no", v.confidence, v.scamType, v.point.map { "\(Int($0.x)),\(Int($0.y)) \($0.label ?? "")" } ?? "none"))
                    line("after claude: \(result.summary)")
                } catch {
                    line("claude error: \(error.localizedDescription)")
                }
            } else {
                line("claude: skipped (no ANTHROPIC_API_KEY)")
            }
        }
        line("ACTION: \(result.action.name)  p=\(String(format: "%.2f", result.probability))")
        if result.action >= .interrupt {
            line("SAY: \(result.spoken)")
            if let r = snap.knownThreatRects[result.target.rawValue] ?? snap.knownThreatRects.values.first {
                line("POINT (page marker \(result.target.rawValue)): \(Int(r.midX)),\(Int(r.midY))")
            }
            if let p = verdict?.point {
                let s = snap.screenPoint(forImagePoint: CGPoint(x: p.x, y: p.y))
                let (snapped, el) = snap.snap(s)
                line("POINT (claude): \(Int(s.x)),\(Int(s.y)) → snapped \(Int(snapped.x)),\(Int(snapped.y)) \(el.map { "[\($0.role) \($0.label.prefix(40))]" } ?? "")")
                if let r = snap.knownThreatRects.values.first {
                    let hit = r.insetBy(dx: -24, dy: -24).contains(snapped)
                    line("  claude point \(hit ? "HITS" : "MISSES") the marked threat element")
                }
            }
            if !snap.context.sensitiveFields.isEmpty && result.probability >= 0.3 {
                line("PAY PAUSE: would show 'Let's check with \(LookoutConfig.familyName) first' and request family approval")
            }
        }

        if let q = question {
            line("-- help: \(q)")
            guard claude.isConfigured else { line("help: skipped (no key)"); return 0 }
            let w = snap.image?.width ?? 0, h = snap.image?.height ?? 0
            let companionText = helpText(q, snap)
            let t0 = Date()
            do {
                let answer = try await claude.complete(system: Prompts.help(imageWidth: w, imageHeight: h), text: companionText, image: snap.image, maxTokens: 1500, effort: "medium")
                line(String(format: "help answer (%.1fs):", Date().timeIntervalSince(t0)))
                for s in PointTags.steps(in: answer) {
                    var desc = "  [\(s.index)] \(s.text)"
                    if let p = s.point {
                        let sp = snap.screenPoint(forImagePoint: CGPoint(x: p.x, y: p.y))
                        let (snapped, el) = snap.snap(sp)
                        desc += "  → point \(Int(sp.x)),\(Int(sp.y)) snapped \(Int(snapped.x)),\(Int(snapped.y)) \(el.map { "[\($0.role) \($0.label.prefix(30))]" } ?? "")"
                        for (name, r) in snap.knownTargetRects where r.insetBy(dx: -20, dy: -20).contains(snapped) { desc += " ✓ hits target '\(name)'" }
                    }
                    line(desc)
                }
            } catch {
                line("help error: \(error.localizedDescription)")
            }
        }
        return 0
    }

    func helpText(_ q: String, _ snap: Snapshot) -> String {
        var s = "Question: \(q)\n"
        if let a = snap.context.appName { s += "Front app: \(a)\n" }
        if let u = snap.context.url { s += "Address: \(u)\n" }
        let inv = snap.imageToScreen.inverted()
        let els = snap.elements.prefix(120).map { e -> String in
            let c = CGPoint(x: e.frame.midX, y: e.frame.midY).applying(inv)
            return "- \(e.role) \"\(e.label.replacingOccurrences(of: "\n", with: " ").prefix(80))\" at \(Int(c.x)),\(Int(c.y))"
        }
        if !els.isEmpty { s += "On-screen controls (center pixel in the screenshot):\n" + els.joined(separator: "\n") + "\n" }
        return s
    }
}
