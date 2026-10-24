import Foundation

/// A snapshot of what is on screen, reduced to what the detectors need.
/// Built either from live capture (ScreenCaptureKit + Accessibility) or from a fixture file.
public struct ScreenContext: Sendable, Equatable {
    public var text: String
    public var url: String?
    public var appName: String?
    public var windowTitle: String?
    public var runningApps: [String]
    /// Sensitive entry fields visible on screen ("card", "gift-card", "ssn", "bank", "password").
    public var sensitiveFields: [String]

    public init(
        text: String,
        url: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        runningApps: [String] = [],
        sensitiveFields: [String] = []
    ) {
        self.text = text
        self.url = url
        self.appName = appName
        self.windowTitle = windowTitle
        self.runningApps = runningApps
        self.sensitiveFields = sensitiveFields
    }

    /// Stable fingerprint so the guardian can skip re-analysing an unchanged screen.
    public var fingerprint: Int {
        var hasher = Hasher()
        hasher.combine(text)
        hasher.combine(url)
        hasher.combine(appName)
        hasher.combine(runningApps)
        return hasher.finalize()
    }
}

public enum SignalKind: String, Sendable, CaseIterable, Codable {
    // Scam indicators
    case infectedClaim
    case doNotClose
    case phoneCallToAction
    case techBrand
    case urgency
    case legalThreat
    case govImpersonation
    case govDomainMismatch
    case giftCardPayment
    case wirePayment
    case p2pPayment
    case cryptoPayment
    case guaranteedReturns
    case secrecy
    case familyEmergency
    case remoteAccessInstruction
    case remoteAccessAppRunning
    case refundBait
    case prizeFee
    case credentialRequest
    case ssnRequest
    case medicareNumberRequest
    case lookalikeDomain
    case punycodeDomain
    case suspiciousTLD
    case smallFeeDelivery
    case utilityShutoff
    case romanceMoney
    case charityPressure
    case sensitiveEntryOnRiskyPage
    case comboPaymentPressure
    case comboRemoteRefund
    case comboInfectedPhone
    case modelVerdict
    // Benign indicators (negative weight)
    case notABill
    case neverAskReassurance
    case scamEducation
    case officialDomain
    case userInitiatedShopping

    public var isBenign: Bool {
        switch self {
        case .notABill, .neverAskReassurance, .scamEducation, .officialDomain, .userInitiatedShopping:
            return true
        default:
            return false
        }
    }
}

/// What kind of on-screen element the buddy should point at for a given threat.
public enum ThreatTarget: String, Sendable, Codable {
    case phone, giftCard = "gift-card", link, login, remoteApp = "remote-app", wire, crypto, ssn, card, none
}

public struct Signal: Sendable, Equatable {
    public var kind: SignalKind
    /// Log-odds contribution.
    public var weight: Double
    /// The text that triggered it (used for explanations and to find the element to point at).
    public var evidence: String
    public var target: ThreatTarget

    public init(kind: SignalKind, weight: Double, evidence: String, target: ThreatTarget = .none) {
        self.kind = kind
        self.weight = weight
        self.evidence = evidence
        self.target = target
    }
}

public enum Action: Int, Sendable, Comparable, CaseIterable, Codable {
    case quiet = 0
    case nudge = 1
    case interrupt = 2
    case blockAndAlert = 3

    public static func < (lhs: Action, rhs: Action) -> Bool { lhs.rawValue < rhs.rawValue }

    public var name: String {
        switch self {
        case .quiet: return "quiet"
        case .nudge: return "nudge"
        case .interrupt: return "interrupt"
        case .blockAndAlert: return "block+alert"
        }
    }
}

public enum Math {
    public static func sigmoid(_ x: Double) -> Double { 1.0 / (1.0 + exp(-x)) }
    public static func logit(_ p: Double) -> Double {
        let c = min(max(p, 1e-6), 1 - 1e-6)
        return log(c / (1 - c))
    }
}
