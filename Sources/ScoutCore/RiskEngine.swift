import Foundation

/// Accumulates scam evidence across screens over time.
///
/// Scams unfold in steps (a pop-up, then a phone call, then a remote-access app, then a payment page),
/// so evidence is remembered per signal kind and decays with a half-life. Each kind counts once
/// (the strongest recent instance), so an unchanged screen re-observed every few seconds does not
/// inflate the score. Benign context only applies to the current screen.
public final class RiskEngine: @unchecked Sendable {
    public struct Config: Sendable {
        /// Base-rate log-odds of "a scam is in progress" on any given screen (~2%).
        public var prior: Double = -3.9
        /// Seconds for remembered evidence to lose half its weight.
        public var halfLife: TimeInterval = 120
        /// Evidence below this (after decay) is forgotten.
        public var floor: Double = 0.05
        public init() {}
    }

    public struct Assessment: Sendable {
        public var probability: Double
        public var logOdds: Double
        public var screenSignals: [Signal]
        /// Remembered evidence currently contributing, strongest first.
        public var activeEvidence: [Signal]
        public var topTarget: ThreatTarget {
            let order = activeEvidence.filter { $0.target != .none }
            return order.first?.target ?? .none
        }
    }

    private struct Memory { var signal: Signal; var at: Date }

    /// Evidence about the current page's address only counts while that page is on screen.
    public static let pageLocal: Set<SignalKind> = [.lookalikeDomain, .punycodeDomain, .suspiciousTLD, .govDomainMismatch, .sensitiveEntryOnRiskyPage]

    public let config: Config
    private var memory: [SignalKind: Memory] = [:]
    private let lock = NSLock()

    public init(config: Config = Config()) {
        self.config = config
    }

    func decayed(_ w: Double, from: Date, to: Date) -> Double {
        let dt = max(0, to.timeIntervalSince(from))
        return w * pow(0.5, dt / config.halfLife)
    }

    @discardableResult
    public func ingest(_ signals: [Signal], at now: Date = Date()) -> Assessment {
        lock.lock(); defer { lock.unlock() }
        // Refresh memory with positive evidence.
        for s in signals where s.weight > 0 && !RiskEngine.pageLocal.contains(s.kind) {
            if let m = memory[s.kind] {
                let old = decayed(m.signal.weight, from: m.at, to: now)
                if s.weight >= old { memory[s.kind] = Memory(signal: s, at: now) }
            } else {
                memory[s.kind] = Memory(signal: s, at: now)
            }
        }
        return assessLocked(currentScreen: signals, at: now)
    }

    /// Fold in a model (Claude) verdict as strong, decaying evidence.
    @discardableResult
    public func ingestModelVerdict(isScam: Bool, confidence: Double, at now: Date = Date(), screen: [Signal] = []) -> Assessment {
        lock.lock(); defer { lock.unlock() }
        let c = min(max(confidence, 0), 1)
        let w = (isScam ? 1 : -1) * (1.0 + 3.0 * c)
        memory[.modelVerdict] = Memory(signal: Signal(kind: .modelVerdict, weight: w, evidence: isScam ? "model: scam" : "model: safe"), at: now)
        return assessLocked(currentScreen: screen, at: now)
    }

    public func assess(currentScreen: [Signal], at now: Date = Date()) -> Assessment {
        lock.lock(); defer { lock.unlock() }
        return assessLocked(currentScreen: currentScreen, at: now)
    }

    private func assessLocked(currentScreen: [Signal], at now: Date) -> Assessment {
        var active: [Signal] = []
        for (k, m) in memory {
            let w = decayed(m.signal.weight, from: m.at, to: now)
            if abs(w) < config.floor { memory[k] = nil; continue }
            var s = m.signal; s.weight = w
            active.append(s)
        }
        let local = currentScreen.filter { $0.weight > 0 && RiskEngine.pageLocal.contains($0.kind) }
        active.append(contentsOf: local)
        active.sort { $0.weight > $1.weight }
        let positive = active.reduce(0) { $0 + $1.weight }
        let negative = currentScreen.filter { $0.weight < 0 }.reduce(0) { $0 + $1.weight }
        let L = config.prior + positive + negative
        return Assessment(probability: Math.sigmoid(L), logOdds: L, screenSignals: currentScreen, activeEvidence: active)
    }

    public func reset() {
        lock.lock(); memory.removeAll(); lock.unlock()
    }

    /// Forget evidence of a kind (e.g. after the remote-access app was closed).
    public func forget(_ kinds: Set<SignalKind>) {
        lock.lock(); for k in kinds { memory[k] = nil }; lock.unlock()
    }
}
