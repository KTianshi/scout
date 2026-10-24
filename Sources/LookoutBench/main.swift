import Foundation
import LookoutCore

// lookout-bench: runs the on-device scam pipeline over labeled fixtures and reports
// precision / recall / false alarms. "Alarm" = the policy would interrupt (or block).
//
//   swift run lookout-bench [--fixtures bench/fixtures.jsonl] [--split dev|test|all] [--verbose] [--demo demo/scenarios]

struct Fixture: Decodable {
    var id: String
    var label: String
    var category: String
    var split: String?
    var text: String
    var url: String?
    var apps: [String]?
    var difficulty: String?
}

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let fixturesPath = opt("--fixtures") ?? "bench/fixtures.jsonl"
let splitFilter = opt("--split") ?? "all"
let verbose = args.contains("--verbose")
let demoDir = opt("--demo")
let markdownOut = opt("--markdown")

struct Row { var id: String; var label: String; var category: String; var split: String; var p: Double; var action: Action; var rules: [String]; var summary: String; var difficulty: String }

func run(_ ctx: ScreenContext) -> ScamPipeline.Result {
    // Fresh engine per fixture: each fixture is an independent screen.
    ScamPipeline().evaluate(ctx)
}

var rows: [Row] = []
let text = (try? String(contentsOfFile: fixturesPath, encoding: .utf8)) ?? ""
if text.isEmpty { FileHandle.standardError.write("No fixtures at \(fixturesPath)\n".data(using: .utf8)!) }
let dec = JSONDecoder()
for line in text.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
    guard let f = try? dec.decode(Fixture.self, from: Data(line.utf8)) else {
        FileHandle.standardError.write("bad line: \(line.prefix(80))\n".data(using: .utf8)!); continue
    }
    let split = f.split ?? "dev"
    if splitFilter != "all" && split != splitFilter { continue }
    let apps = f.apps ?? []
    let ctx = ScreenContext(text: f.text, url: f.url, appName: apps.first, runningApps: apps)
    let r = run(ctx)
    rows.append(Row(id: f.id, label: f.label, category: f.category, split: split, p: r.probability, action: r.action, rules: r.rules.map(\.id), summary: r.summary, difficulty: f.difficulty ?? "?"))
}

// Demo scenarios (HTML): strip tags, read meta.
if let demoDir {
    let fm = FileManager.default
    let files = ((try? fm.contentsOfDirectory(atPath: demoDir)) ?? []).filter { $0.hasSuffix(".html") }.sorted()
    for file in files {
        guard let html = try? String(contentsOfFile: demoDir + "/" + file, encoding: .utf8) else { continue }
        let ctx = FixtureText.context(fromHTML: html)
        let r = run(ctx.context)
        rows.append(Row(id: "demo/" + file, label: ctx.label ?? "?", category: "demo", split: "demo", p: r.probability, action: r.action, rules: r.rules.map(\.id), summary: r.summary, difficulty: "demo"))
    }
}

func metrics(_ rs: [Row], alarmAt: Action = .interrupt) -> (tp: Int, fp: Int, fn: Int, tn: Int) {
    var tp = 0, fp = 0, fn = 0, tn = 0
    for r in rs {
        let alarm = r.action >= alarmAt
        switch (r.label == "scam", alarm) {
        case (true, true): tp += 1
        case (true, false): fn += 1
        case (false, true): fp += 1
        case (false, false): tn += 1
        }
    }
    return (tp, fp, fn, tn)
}

func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "  n/a" : String(format: "%5.1f%%", 100 * Double(a) / Double(b)) }

var out = ""
func say(_ s: String = "") { print(s); out += s + "\n" }

say("# Lookout benchmark (on-device heuristics only, no model)")
say()
say("Fixtures: \(fixturesPath) · split: \(splitFilter) · alarm = policy action ≥ interrupt")
say()
say("| split | n | scams | recall | precision | false-alarm rate | FP | FN | nudge-or-more recall |")
say("|---|---|---|---|---|---|---|---|---|")
for s in ["dev", "test", "demo", "all"] {
    let rs = s == "all" ? rows.filter { $0.split != "demo" } : rows.filter { $0.split == s }
    if rs.isEmpty { continue }
    let m = metrics(rs), mn = metrics(rs, alarmAt: .nudge)
    say("| \(s) | \(rs.count) | \(m.tp + m.fn) | \(pct(m.tp, m.tp + m.fn)) | \(pct(m.tp, m.tp + m.fp)) | \(pct(m.fp, m.fp + m.tn)) | \(m.fp) | \(m.fn) | \(pct(mn.tp, mn.tp + mn.fn)) |")
}
say()
say("## By category")
say()
say("| label | category | n | alarmed |")
say("|---|---|---|---|")
let cats = Dictionary(grouping: rows.filter { $0.split != "demo" }, by: { "\($0.label)|\($0.category)" })
for k in cats.keys.sorted() {
    let rs = cats[k]!
    let parts = k.split(separator: "|")
    let alarmed = rs.filter { $0.action >= .interrupt }.count
    say("| \(parts[0]) | \(parts[1]) | \(rs.count) | \(alarmed) |")
}
say()
let misses = rows.filter { $0.label == "scam" && $0.action < .interrupt }
let fas = rows.filter { $0.label == "benign" && $0.action >= .interrupt }
say("## Missed scams (\(misses.count))")
for r in misses { say("- `\(r.id)` [\(r.split), \(r.difficulty)] " + (verbose ? r.summary : String(format: "p=%.2f %@", r.p, r.action.name))) }
say()
say("## False alarms (\(fas.count))")
for r in fas { say("- `\(r.id)` [\(r.split), \(r.difficulty)] " + (verbose ? r.summary : String(format: "p=%.2f rules=%@", r.p, r.rules.joined(separator: ",")))) }
if verbose {
    say()
    say("## Demo scenarios")
    for r in rows where r.split == "demo" { say("- `\(r.id)` label=\(r.label) \(r.summary)") }
}
if let markdownOut { try? out.write(toFile: markdownOut, atomically: true, encoding: .utf8) }
