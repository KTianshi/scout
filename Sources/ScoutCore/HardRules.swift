import Foundation

/// Facts that are always true, regardless of what a model thinks.
/// Each rule carries the plain-language explanation the buddy says out loud.
public struct HardRule: Sendable {
    public var id: String
    /// What is wrong, in one or two short sentences.
    public var message: String
    /// What to do next.
    public var advice: String
    public var minimum: Action
    public var target: ThreatTarget
    let matches: @Sendable (Set<SignalKind>, String) -> Bool

    public var spoken: String { "\(message) \(advice)" }
}

public struct HardRuleHit: Sendable {
    public var rule: HardRule
}

public enum HardRules {
    static func has(_ s: Set<SignalKind>, _ k: SignalKind...) -> Bool { k.allSatisfy { s.contains($0) } }
    static func any(_ s: Set<SignalKind>, _ k: SignalKind...) -> Bool { k.contains { s.contains($0) } }

    public static let all: [HardRule] = [
        HardRule(
            id: "tech-support-phone",
            message: "This is a fake warning. Real companies like Microsoft and Apple never put a phone number in a pop-up.",
            advice: "Please don't call that number. Let's close this window together.",
            minimum: .interrupt, target: .phone,
            matches: { s, _ in has(s, .phoneCallToAction) && any(s, .infectedClaim, .doNotClose) }
        ),
        HardRule(
            id: "gift-card-payment",
            message: "Gift cards are never used to pay the government, a bill, or a fine. Only scammers ask for gift card codes.",
            advice: "Please don't buy the cards or read out any codes.",
            minimum: .interrupt, target: .giftCard,
            matches: { s, t in
                s.contains(.giftCardPayment) && (any(s, .govImpersonation, .legalThreat, .utilityShutoff, .secrecy, .comboPaymentPressure, .refundBait, .prizeFee, .familyEmergency, .romanceMoney))
            }
        ),
        HardRule(
            id: "secrecy-money",
            message: "Someone is asking you to send money and keep it a secret. Real family and real officials never ask for that.",
            advice: "Let's call your family on a number you already know before doing anything.",
            minimum: .interrupt, target: .wire,
            matches: { s, _ in s.contains(.secrecy) && any(s, .wirePayment, .p2pPayment, .giftCardPayment, .cryptoPayment, .familyEmergency) }
        ),
        HardRule(
            id: "remote-access-stranger",
            message: "This page wants you to let a stranger control your computer. Once they're in, they can take your money.",
            advice: "Please don't install that program or give anyone a code.",
            minimum: .interrupt, target: .remoteApp,
            matches: { s, _ in s.contains(.remoteAccessInstruction) && any(s, .refundBait, .phoneCallToAction, .infectedClaim, .comboRemoteRefund) }
        ),
        HardRule(
            id: "remote-access-with-money",
            message: "Someone may be controlling your computer while money is on the screen.",
            advice: "Let's end that connection first.",
            minimum: .blockAndAlert, target: .remoteApp,
            matches: { s, _ in s.contains(.remoteAccessAppRunning) && any(s, .sensitiveEntryOnRiskyPage, .refundBait, .credentialRequest, .comboRemoteRefund) }
        ),
        HardRule(
            id: "crypto-atm",
            message: "No real business, government, or friend asks you to put cash into a Bitcoin machine.",
            advice: "Please don't send any money. This is a scam.",
            minimum: .interrupt, target: .crypto,
            matches: { s, t in s.contains(.cryptoPayment) && (t.contains("atm") || s.contains(.guaranteedReturns) || s.contains(.romanceMoney) || s.contains(.legalThreat)) }
        ),
        HardRule(
            id: "lookalike-login",
            message: "This website is pretending to be a company you trust. The web address is not the real one.",
            advice: "Please don't type your password or any numbers here. Let's close it.",
            minimum: .interrupt, target: .login,
            matches: { s, _ in any(s, .lookalikeDomain, .punycodeDomain) && any(s, .credentialRequest, .ssnRequest, .sensitiveEntryOnRiskyPage) }
        ),
        HardRule(
            id: "government-threat",
            message: "Government agencies never threaten to arrest you over email, text, or a phone call, and they never demand payment right away.",
            advice: "Don't reply or pay. We can look up the real number together.",
            minimum: .interrupt, target: .none,
            matches: { s, _ in has(s, .govImpersonation, .legalThreat) && any(s, .giftCardPayment, .wirePayment, .p2pPayment, .cryptoPayment, .urgency, .govDomainMismatch) }
        ),
    ]

    public static func evaluate(_ signals: [Signal], text: String) -> [HardRule] {
        // Benign context (e.g. an article about scams) disables the hard rules for this screen.
        let benign = signals.filter { $0.weight < 0 }.reduce(0) { $0 + $1.weight }
        if benign <= -2.0 { return [] }
        let kinds = Set(signals.filter { $0.weight > 0.25 }.map(\.kind))
        let t = text.lowercased()
        return all.filter { $0.matches(kinds, t) }
    }
}
