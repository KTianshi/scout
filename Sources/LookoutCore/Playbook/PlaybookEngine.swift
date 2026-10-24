import Foundation

/// Swift port of lookout_detect (model.py + engine.py). Reads the same model/playbooks.json and must
/// produce the same numbers (checked by parity tests against vectors exported from Python).
public final class PlaybookModel: @unchecked Sendable {
    public let states: [String]
    public let isScam: [Bool]
    public let playbookOf: [String?]
    public let stageIndex: [Int]
    public let playbooks: [String]
    public let labels: [String: String]
    public let hints: [String]
    public let start: [Double]
    public let A: [[Double]]
    public let Q: [[Double]]
    public let tauScam: Double
    public let tauBenign: Double
    public let distraction: Double
    public let idle = 0
    public var n: Int { states.count }

    public enum LoadError: Error { case bad(String) }

    public static func load(url: URL) throws -> PlaybookModel {
        let data = try Data(contentsOf: url)
        guard let cfg = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LoadError.bad("not an object") }
        return try PlaybookModel(config: cfg)
    }

    /// Finds model/playbooks.json: app bundle Resources, then the working directory, then next to the executable.
    public static func locate() -> URL? {
        let fm = FileManager.default
        var c: [URL] = []
        if let r = Bundle.main.resourceURL { c.append(r.appendingPathComponent("model/playbooks.json")) }
        c.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("model/playbooks.json"))
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<6 { u.deleteLastPathComponent(); c.append(u.appendingPathComponent("model/playbooks.json")) }
        return c.first { fm.fileExists(atPath: $0.path) }
    }

    public init(config cfg: [String: Any]) throws {
        let events = cfg["events"] as? [String] ?? []
        guard events == PlaybookEvent.allCases.map(\.rawValue) else { throw LoadError.bad("events must match PlaybookEvent order") }
        let E = events.count
        let floor = (cfg["probability_floor"] as? Double) ?? 1e-4
        let benignDefault = (cfg["default_benign_rate"] as? Double) ?? 0.002
        let scamDefault = (cfg["default_scam_rate"] as? Double) ?? 0.01
        // JSONSerialization does not keep key order; benign state order comes from the raw text.
        let benignCfg = (cfg["benign"] as? [String: Any])?["states"] as? [String: [String: Any]] ?? [:]
        let pbCfg = cfg["playbooks"] as? [String: [String: Any]] ?? [:]
        let order = cfg["order"] as? [String: Any] ?? [:]
        guard let benignOrder = order["benign"] as? [String], let pbOrder = order["playbooks"] as? [String],
              Set(benignOrder) == Set(benignCfg.keys), Set(pbOrder) == Set(pbCfg.keys) else {
            throw LoadError.bad("playbooks.json needs an \"order\" block listing every benign state and playbook")
        }
        guard benignOrder.first == "idle" else { throw LoadError.bad("first benign state must be idle") }

        var states: [String] = [], isScam: [Bool] = [], playbookOf: [String?] = [], stageIndex: [Int] = []
        var Q: [[Double]] = [], start: [Double] = [], hints: [String] = []
        func emitRow(_ emit: [String: Any], _ def: Double) -> [Double] {
            var q = Array(repeating: def, count: E)
            for (k, v) in emit { if let i = events.firstIndex(of: k), let d = (v as? NSNumber)?.doubleValue { q[i] = d } }
            return q.map { min(max($0, floor), 1 - floor) }
        }
        for name in benignOrder {
            let s = benignCfg[name] ?? [:]
            states.append(name); isScam.append(false); playbookOf.append(nil); stageIndex.append(-1); hints.append("")
            Q.append(emitRow(s["emit"] as? [String: Any] ?? [:], benignDefault))
            start.append((s["start"] as? NSNumber)?.doubleValue ?? 0)
        }
        var labels: [String: String] = [:]
        for pb in pbOrder {
            let spec = pbCfg[pb] ?? [:]
            labels[pb] = spec["label"] as? String ?? pb
            for (i, st) in (spec["stages"] as? [[String: Any]] ?? []).enumerated() {
                states.append("\(pb):\(st["name"] as? String ?? "\(i)")"); isScam.append(true); playbookOf.append(pb); stageIndex.append(i)
                hints.append(st["hint"] as? String ?? "")
                Q.append(emitRow(st["emit"] as? [String: Any] ?? [:], scamDefault))
                start.append(0)
            }
        }
        let n = states.count
        var A = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var enterTotal = 0.0
        for (j, name) in benignOrder.enumerated() where j != 0 {
            let s = benignCfg[name] ?? [:]
            let enter = (s["enter"] as? NSNumber)?.doubleValue ?? 0
            A[0][j] = enter; enterTotal += enter
            let stay = (s["stay"] as? NSNumber)?.doubleValue ?? 0.8
            A[j][j] = stay; A[j][0] += 1 - stay
        }
        for pb in pbOrder {
            let spec = pbCfg[pb] ?? [:]
            let idx = (0..<n).filter { playbookOf[$0] == pb }
            var entry: [Double] = (spec["entry_stages"] as? [NSNumber])?.map(\.doubleValue) ?? ([1.0] + Array(repeating: 0.0, count: idx.count - 1))
            let es = entry.reduce(0, +); entry = entry.map { $0 / es }
            let enter = (spec["enter"] as? NSNumber)?.doubleValue ?? 1e-4
            for (k, p) in zip(idx, entry) { A[0][k] += enter * p; start[k] += enter * p }
            enterTotal += enter
            let rows = ((spec["transitions"] as? [String: Any])?["rows"] as? [[NSNumber]])?.map { $0.map(\.doubleValue) } ?? []
            guard rows.count == idx.count else { throw LoadError.bad("\(pb): one transition row per stage") }
            for (i, k) in idx.enumerated() {
                let r = rows[i]
                let (stay, adv, skip) = (r[0], r[1], r[2])
                var abandon = r[3]
                A[k][k] += stay
                if i + 1 < idx.count { A[k][idx[i + 1]] += adv } else { abandon += adv }
                if i + 2 < idx.count { A[k][idx[i + 2]] += skip }
                else if i + 1 < idx.count { A[k][idx[i + 1]] += skip }
                else { A[k][k] += skip }
                A[k][0] += abandon
            }
        }
        A[0][0] = 1 - enterTotal
        start[0] = 0
        start[0] = 1 - start.reduce(0, +)
        let timing = cfg["timing"] as? [String: Any] ?? [:]
        self.states = states; self.isScam = isScam; self.playbookOf = playbookOf; self.stageIndex = stageIndex
        self.playbooks = pbOrder; self.labels = labels; self.hints = hints
        self.start = start; self.A = A; self.Q = Q
        self.tauScam = (timing["scam_return_tau_s"] as? NSNumber)?.doubleValue ?? 1800
        self.tauBenign = (timing["benign_return_tau_s"] as? NSNumber)?.doubleValue ?? 900
        self.distraction = (cfg["distraction"] as? NSNumber)?.doubleValue ?? 0
    }

    public func transition(dt: Double) -> [[Double]] {
        guard dt > 0 else { return A }
        let rs = 1 - exp(-dt / tauScam), rb = 1 - exp(-dt / tauBenign)
        var out = A
        for s in 0..<n where s != idle {
            let r = isScam[s] ? rs : rb
            for j in 0..<n { out[s][j] = (1 - r) * A[s][j] + (j == idle ? r : 0) }
        }
        return out
    }

    public func stages(of pb: String) -> [Int] { (0..<n).filter { playbookOf[$0] == pb } }
}

public struct PlaybookLedgerEntry: Sendable, Equatable {
    public var step: Int
    public var t: Double
    public var item: String
    public var logBF: Double
    public var source: String
}

public struct PlaybookState: Sendable {
    public var step: Int
    public var pScam: Double
    public var logOdds: Double
    public var byType: [String: Double]
    public var topType: String?
    public var topTypeLabel: String?
    public var stagePosterior: [String: Double]
    public var currentStage: String?
    public var nextStage: String?
    public var nextHint: String?
    public var logLikelihood: Double
    public var ledger: [PlaybookLedgerEntry]
    /// Most likely benign look-alike activity (remote_help, gift_shopping, ...) and the posterior mass on all of them.
    public var lookalike: String?
    public var lookalikeP: Double

    public var summary: String {
        let top = topType.map { "\($0)@\(currentStage ?? "?")" } ?? "-"
        let ev = ledger.filter { $0.item != "time passes" && abs($0.logBF) > 0.05 }
            .map { String(format: "%@ %+.1f", $0.item, $0.logBF) }.joined(separator: ", ")
        return String(format: "playbook p=%.3f %@ [%@]", pScam, top, ev)
    }
}

/// Forward filter in log space with an exact evidence ledger (see lookout_detect/engine.py).
public final class PlaybookEngine: @unchecked Sendable {
    public let model: PlaybookModel
    private let logStart: [Double]
    private let logQ: [[Double]]
    private let log1mQ: [[Double]]
    public private(set) var logAlpha: [Double]?
    public private(set) var tLast: Double?
    public private(set) var step = 0
    public private(set) var logLikelihood = 0.0
    public private(set) var logOdds: Double
    public private(set) var ledger: [PlaybookLedgerEntry] = []
    private let lock = NSLock()

    public init(model: PlaybookModel) {
        self.model = model
        logStart = model.start.map { $0 > 0 ? log($0) : -.infinity }
        logQ = model.Q.map { $0.map { log($0) } }
        log1mQ = model.Q.map { $0.map { log1p(-$0) } }
        logOdds = 0
        logOdds = odds(logStart)
    }

    public var priorLogOdds: Double { odds(logStart) }

    static func lse(_ a: [Double]) -> Double {
        guard let m = a.max(), m.isFinite else { return a.max() ?? -.infinity }
        return log(a.reduce(0) { $0 + exp($1 - m) }) + m
    }

    func odds(_ w: [Double]) -> Double {
        var s: [Double] = [], b: [Double] = []
        for (i, x) in w.enumerated() { if model.isScam[i] { s.append(x) } else { b.append(x) } }
        return Self.lse(s) - Self.lse(b)
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        logAlpha = nil; tLast = nil; step = 0; logLikelihood = 0; ledger = []; logOdds = odds(logStart)
    }

    func predict(dt: Double) -> [Double] {
        guard let a = logAlpha else { return logStart }
        let T = model.transition(dt: dt)
        let n = model.n
        var out = Array(repeating: -Double.infinity, count: n)
        for j in 0..<n {
            var col: [Double] = []
            col.reserveCapacity(n)
            for i in 0..<n where T[i][j] > 0 { col.append(a[i] + log(T[i][j])) }
            out[j] = col.isEmpty ? -.infinity : Self.lse(col)
        }
        return out
    }

    @discardableResult
    public func observe(_ obs: PlaybookObservation) -> PlaybookState {
        lock.lock(); defer { lock.unlock() }
        let dt = tLast.map { max(0, obs.t - $0) } ?? 0
        let pred = predict(dt: dt)
        step += 1
        var entries: [PlaybookLedgerEntry] = []
        var L = odds(pred)
        if logAlpha != nil { entries.append(.init(step: step, t: obs.t, item: "time passes", logBF: L - logOdds, source: "model")) }
        let all = PlaybookEvent.allCases
        let present = all.filter { obs.events.contains($0) }
        let absent = obs.observed.filter { !obs.events.contains($0) }
        var cum = pred
        var items: [(String, [Double])] = []
        if !absent.isEmpty {
            let idx = absent.map { all.firstIndex(of: $0)! }
            items.append(("nothing else on screen", (0..<model.n).map { s in idx.reduce(0) { $0 + log1mQ[s][$1] } }))
        }
        for e in present {
            let k = all.firstIndex(of: e)!
            items.append((e.rawValue, (0..<model.n).map { logQ[$0][k] }))
        }
        // Mixture emission (see model.py): track own and idle partial products for an exact ledger.
        var own = Array(repeating: 0.0, count: model.n)
        var idlePart = 0.0
        let d = model.distraction
        for (name, term) in items {
            for s in 0..<model.n { own[s] += term[s] }
            idlePart += term[model.idle]
            for s in 0..<model.n {
                if d <= 0 || s == model.idle { cum[s] = pred[s] + own[s] }
                else {
                    let a = log1p(-d) + own[s], b = log(d) + idlePart
                    let m = max(a, b)
                    cum[s] = pred[s] + m + log(exp(a - m) + exp(b - m))
                }
            }
            let Ln = odds(cum)
            entries.append(.init(step: step, t: obs.t, item: name, logBF: Ln - L, source: obs.source))
            L = Ln
        }
        let norm = Self.lse(cum)
        logLikelihood += norm
        logAlpha = cum.map { $0 - norm }
        logOdds = L
        tLast = obs.t
        ledger.append(contentsOf: entries)
        return stateLocked(entries)
    }

    /// What the state would be after `obs`, without recording it.
    public func peek(_ obs: PlaybookObservation) -> PlaybookState {
        lock.lock()
        let saved = (logAlpha, tLast, step, logLikelihood, logOdds, ledger)
        lock.unlock()
        let s = observe(obs)
        lock.lock()
        (logAlpha, tLast, step, logLikelihood, logOdds, ledger) = saved
        lock.unlock()
        return s
    }

    public func state() -> PlaybookState {
        lock.lock(); defer { lock.unlock() }
        return stateLocked([])
    }

    public func posterior() -> [Double] {
        (logAlpha ?? logStart).map { exp($0) }
    }

    private func stateLocked(_ entries: [PlaybookLedgerEntry]) -> PlaybookState {
        let post = posterior()
        var byType: [String: Double] = [:]
        for pb in model.playbooks { byType[pb] = model.stages(of: pb).reduce(0) { $0 + post[$1] } }
        let pScam = (0..<model.n).filter { model.isScam[$0] }.reduce(0) { $0 + post[$1] }
        let act = (0..<model.n).filter { !model.isScam[$0] && $0 != model.idle }
        let lookP = act.reduce(0) { $0 + post[$1] }
        let look = act.max { post[$0] < post[$1] }.flatMap { lookP > 0 ? model.states[$0] : nil }
        // Deterministic tie-break: playbook order.
        let top = model.playbooks.max { (byType[$0] ?? 0) < (byType[$1] ?? 0) }
        var stagePost: [String: Double] = [:], cur: String?, nxt: String?, hint: String?
        if let top, (byType[top] ?? 0) > 0 {
            let idx = model.stages(of: top)
            let tot = idx.reduce(0) { $0 + post[$1] }
            let w = idx.map { post[$0] / tot }
            for (k, p) in zip(idx, w) { stagePost[String(model.states[k].split(separator: ":")[1])] = p }
            let curLocal = w.indices.max { w[$0] < w[$1] } ?? 0
            cur = String(model.states[idx[curLocal]].split(separator: ":")[1])
            if curLocal + 1 < idx.count {
                var best = -1.0, bestK = idx[curLocal + 1]
                for j in (curLocal + 1)..<idx.count {
                    let p = zip(idx, w).reduce(0) { $0 + $1.1 * model.A[$1.0][idx[j]] }
                    if p > best { best = p; bestK = idx[j] }
                }
                nxt = String(model.states[bestK].split(separator: ":")[1])
                hint = model.hints[bestK]
            }
        }
        return PlaybookState(step: step, pScam: pScam, logOdds: logOdds, byType: byType, topType: top,
                             topTypeLabel: top.flatMap { model.labels[$0] }, stagePosterior: stagePost,
                             currentStage: cur, nextStage: nxt, nextHint: hint, logLikelihood: logLikelihood, ledger: entries,
                             lookalike: look, lookalikeP: lookP)
    }

    /// Largest evidence entries so far, for explanations.
    public func topEvidence(_ k: Int = 4) -> [PlaybookLedgerEntry] {
        lock.lock(); defer { lock.unlock() }
        return ledger.filter { $0.item != "time passes" }.sorted { abs($0.logBF) > abs($1.logBF) }.prefix(k).map { $0 }
    }
}
