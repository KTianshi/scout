import Foundation

/// Chooses how loudly to react, by minimising expected cost.
///
/// For each action a: E[cost(a)] = p · missCost(a) · stakes + (1 − p) · falseAlarmCost(a)
/// Missing a scam is far worse than a false alarm, but false alarms erode trust with older users
/// (and the family), so interrupting needs real evidence. Stakes rise when money or
/// remote control is on the line. Hard rules can force a minimum action.
public struct ActionPolicy: Sendable {
    public struct Costs: Sendable {
        public var falseAlarm: [Action: Double]
        public var miss: [Action: Double]
        public init(falseAlarm: [Action: Double], miss: [Action: Double]) {
            self.falseAlarm = falseAlarm
            self.miss = miss
        }
        public static let `default` = Costs(
            falseAlarm: [.quiet: 0, .nudge: 3, .interrupt: 25, .blockAndAlert: 60],
            miss: [.quiet: 100, .nudge: 70, .interrupt: 15, .blockAndAlert: 3]
        )
    }

    public struct Context: Sendable {
        public var paymentEntryVisible: Bool
        public var remoteAccessActive: Bool
        public var hardRuleMinimum: Action?
        public init(paymentEntryVisible: Bool = false, remoteAccessActive: Bool = false, hardRuleMinimum: Action? = nil) {
            self.paymentEntryVisible = paymentEntryVisible
            self.remoteAccessActive = remoteAccessActive
            self.hardRuleMinimum = hardRuleMinimum
        }
    }

    public struct Decision: Sendable {
        public var action: Action
        public var expectedCosts: [Action: Double]
        public var reason: String
    }

    public var costs: Costs
    public init(costs: Costs = .default) { self.costs = costs }

    public func stakes(_ ctx: Context) -> Double {
        var s = 1.0
        if ctx.paymentEntryVisible { s *= 2.0 }
        if ctx.remoteAccessActive { s *= 1.5 }
        return s
    }

    public func decide(probability p: Double, context ctx: Context = Context()) -> Decision {
        let stakes = stakes(ctx)
        var allowed = Action.allCases
        // Blocking the screen is only justified when something irreversible is about to happen.
        if !(ctx.paymentEntryVisible || ctx.remoteAccessActive) { allowed.removeAll { $0 == .blockAndAlert } }
        var ec: [Action: Double] = [:]
        for a in allowed {
            ec[a] = p * (costs.miss[a] ?? 0) * stakes + (1 - p) * (costs.falseAlarm[a] ?? 0)
        }
        var best = allowed.min { (ec[$0] ?? .infinity) < (ec[$1] ?? .infinity) } ?? .quiet
        var reason = String(format: "min expected cost at p=%.2f, stakes×%.1f", p, stakes)
        if let floor = ctx.hardRuleMinimum, floor > best {
            best = allowed.contains(floor) ? floor : (allowed.max() ?? .interrupt)
            reason += "; raised by hard rule"
        }
        return Decision(action: best, expectedCosts: ec, reason: reason)
    }

    /// Smallest probability at which the policy reaches at least `action` (for docs / tests).
    public func threshold(for action: Action, context: Context = Context()) -> Double? {
        var lo = 0.0, hi = 1.0
        guard decide(probability: 1.0, context: context).action >= action else { return nil }
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if decide(probability: mid, context: context).action >= action { hi = mid } else { lo = mid }
        }
        return hi
    }
}
