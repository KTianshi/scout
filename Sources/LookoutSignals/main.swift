import Foundation
import LookoutCore

// lookout-signals: the app's on-device extractor as a filter, so Python evaluation uses the exact same code.
//
//   stdin  JSON Lines: {"text": "...", "url": "...", "app": "...", "apps": ["AnyDesk"], "sensitive": ["card"], "t": 12.0}
//   stdout JSON Lines: {"events": ["URGENT_LANGUAGE", ...], "signals": [{"kind": "urgency", "weight": 1.0}, ...]}
//   --engine: also run the playbook engine over the lines in order (uses "t") and add "p_scam", "top_type", "stage", "ledger",
//             plus "risk_p"/"risk_action" from the shipped evidence-memory detector (baseline).

let useEngine = CommandLine.arguments.contains("--engine")
var engine: PlaybookEngine?
// The current shipped detector (evidence memory + hard rules + policy), without the playbook HMM, as a baseline.
let riskOnly = ScamPipeline(playbook: nil)
// The full shipped pipeline (playbook HMM + evidence memory + hard rules + policy), exactly as the app runs it.
let shipped = ScamPipeline()
if useEngine {
    guard let url = PlaybookModel.locate(), let m = try? PlaybookModel.load(url: url) else {
        FileHandle.standardError.write("model/playbooks.json not found\n".data(using: .utf8)!); exit(2)
    }
    engine = PlaybookEngine(model: m)
}

var lineNo = 0
while let line = readLine(strippingNewline: true) {
    lineNo += 1
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
        FileHandle.standardError.write("line \(lineNo): not JSON\n".data(using: .utf8)!); continue
    }
    let ctx = ScreenContext(text: o["text"] as? String ?? "", url: o["url"] as? String, appName: o["app"] as? String,
                            runningApps: o["apps"] as? [String] ?? [], sensitiveFields: o["sensitive"] as? [String] ?? [])
    let signals = ScamSignals.analyze(ctx)
    let events = PlaybookEvents.extract(ctx, signals: signals)
    var out: [String: Any] = [
        "events": PlaybookEvent.allCases.filter { events.contains($0) }.map(\.rawValue),
        "signals": signals.map { ["kind": $0.kind.rawValue, "weight": $0.weight] },
    ]
    if let engine {
        let t = (o["t"] as? NSNumber)?.doubleValue ?? Double(lineNo)
        let s = engine.observe(PlaybookObservation(t: t, events: events, source: "screen"))
        out["p_scam"] = s.pScam
        out["top_type"] = s.topType ?? NSNull()
        out["stage"] = s.currentStage ?? NSNull()
        out["ledger"] = s.ledger.map { ["item": $0.item, "log_bf": $0.logBF] }
        out["lookalike"] = s.lookalike ?? NSNull()
        out["lookalike_p"] = s.lookalikeP
        let r = riskOnly.evaluate(ctx, at: Date(timeIntervalSince1970: t))
        out["risk_p"] = r.assessment.probability
        out["risk_action"] = r.action.name
        out["rules"] = r.rules.map(\.id)
        let full = shipped.evaluate(ctx, at: Date(timeIntervalSince1970: t))
        out["shipped_p"] = full.probability
        out["shipped_action"] = full.action.name
    }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
