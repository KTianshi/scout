import Foundation

/// signals → risk → hard rules → policy, plus a plain-language explanation that works without a model.
/// Shared by the live Guardian, fixture mode and the benchmark.
public final class ScamPipeline: @unchecked Sendable {
    public struct Result: Sendable {
        public var assessment: RiskEngine.Assessment
        public var rules: [HardRule]
        public var decision: ActionPolicy.Decision
        public var explanation: String
        public var advice: String
        public var target: ThreatTarget
        /// The text of the most dangerous thing, used to find it on screen.
        public var targetEvidence: String?
        public var shouldConfirmWithModel: Bool

        public var probability: Double { assessment.probability }
        public var action: Action { decision.action }
        public var spoken: String { [explanation, advice].filter { !$0.isEmpty }.joined(separator: " ") }

        public var summary: String {
            let ev = assessment.activeEvidence.prefix(6).map { "\($0.kind.rawValue)(\(String(format: "%.1f", $0.weight)): \($0.evidence))" }
            let neg = assessment.screenSignals.filter { $0.weight < 0 }.map { "\($0.kind.rawValue)(\(String(format: "%.1f", $0.weight)))" }
            return String(format: "p=%.2f ", probability) + "action=\(action.name) rules=[\(rules.map(\.id).joined(separator: ","))] evidence=[\(ev.joined(separator: "; "))] benign=[\(neg.joined(separator: ","))]"
        }
    }

    public let engine: RiskEngine
    public let policy: ActionPolicy

    public init(engine: RiskEngine = RiskEngine(), policy: ActionPolicy = ActionPolicy()) {
        self.engine = engine
        self.policy = policy
    }

    public func evaluate(_ ctx: ScreenContext, at now: Date = Date()) -> Result {
        let signals = ScamSignals.analyze(ctx)
        let a = engine.ingest(signals, at: now)
        return decide(ctx: ctx, assessment: a)
    }

    public func applyModelVerdict(_ v: ScamVerdict, ctx: ScreenContext, at now: Date = Date()) -> Result {
        let screen = ScamSignals.analyze(ctx)
        let a = engine.ingestModelVerdict(isScam: v.isScam, confidence: v.confidence, at: now, screen: screen)
        var r = decide(ctx: ctx, assessment: a)
        // A confident "this is safe" from the model caps the reaction at a gentle nudge, unless a hard rule fires.
        if !v.isScam, v.confidence >= 0.85, r.rules.isEmpty, r.decision.action > .nudge {
            r.decision.action = .nudge
            r.decision.reason += "; capped by confident model verdict"
        }
        if v.isScam, !v.explanation.isEmpty {
            r.explanation = v.explanation
            r.advice = v.whatToDo
        }
        r.shouldConfirmWithModel = false
        return r
    }

    func decide(ctx: ScreenContext, assessment a: RiskEngine.Assessment) -> Result {
        // Hard rules see remembered evidence plus this screen's benign context.
        let ruleInput = a.activeEvidence + a.screenSignals.filter { $0.weight < 0 }
        let rules = HardRules.evaluate(ruleInput, text: ctx.text)
        let remote = a.activeEvidence.contains { $0.kind == .remoteAccessAppRunning }
        let paymentVisible = !ctx.sensitiveFields.isEmpty
        let floor = rules.map(\.minimum).max()
        let ctxP = ActionPolicy.Context(paymentEntryVisible: paymentVisible, remoteAccessActive: remote, hardRuleMinimum: floor)
        let d = policy.decide(probability: a.probability, context: ctxP)
        let (explanation, advice, target) = Self.explain(rules: rules, evidence: a.activeEvidence)
        let targetEvidence = a.activeEvidence.first { $0.target == target && $0.target != .none }?.evidence
        let confirm = a.probability >= LookoutConfig.confirmThreshold || !rules.isEmpty
        return Result(assessment: a, rules: rules, decision: d, explanation: explanation, advice: advice, target: target, targetEvidence: targetEvidence, shouldConfirmWithModel: confirm)
    }

    /// Template explanation from hard rules or the strongest evidence.
    public static func explain(rules: [HardRule], evidence: [Signal]) -> (String, String, ThreatTarget) {
        if let r = rules.max(by: { $0.minimum < $1.minimum }) {
            let target = r.target != .none ? r.target : (evidence.first { $0.target != .none }?.target ?? .none)
            return (r.message, r.advice, target)
        }
        guard let top = evidence.first(where: { $0.weight > 0 && $0.kind != .modelVerdict }) else {
            return ("", "", .none)
        }
        let t = evidence.first { $0.target != .none }?.target ?? .none
        let msg: String
        switch top.kind {
        case .infectedClaim, .doNotClose, .comboInfectedPhone:
            msg = "This looks like a fake virus warning. Real ones never ask you to call or pay."
        case .lookalikeDomain, .punycodeDomain:
            msg = "This website's address isn't the real one. It may be pretending to be a company you know."
        case .giftCardPayment:
            msg = "Someone wants to be paid with gift cards. That is always a scam."
        case .wirePayment, .p2pPayment:
            msg = "Someone is asking you to send money quickly. Let's slow down and check first."
        case .cryptoPayment, .guaranteedReturns:
            msg = "Promises of guaranteed money with crypto are a common scam."
        case .secrecy:
            msg = "They're asking you to keep this a secret. That's a warning sign."
        case .remoteAccessInstruction, .remoteAccessAppRunning, .comboRemoteRefund:
            msg = "This wants to let someone control your computer. Only allow that for people you know."
        case .refundBait:
            msg = "This looks like a fake charge meant to make you call them."
        case .prizeFee:
            msg = "Real prizes never ask you to pay a fee first."
        case .legalThreat, .govImpersonation, .govDomainMismatch:
            msg = "This is pretending to be the government. They never threaten you like this."
        case .smallFeeDelivery:
            msg = "This delivery message asking for a small fee is a common trick."
        case .utilityShutoff:
            msg = "Real utility companies don't threaten to cut you off within minutes."
        case .familyEmergency, .romanceMoney:
            msg = "Someone is asking for money in a hurry. Let's check with your family first."
        case .credentialRequest, .ssnRequest, .medicareNumberRequest, .sensitiveEntryOnRiskyPage:
            msg = "This page asks for private information. Let's make sure it's real first."
        default:
            msg = "Something here looks a little off. Let's take a careful look together."
        }
        return (msg, "Please don't type anything or call anyone yet.", t)
    }
}
