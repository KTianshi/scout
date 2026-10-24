import Foundation

/// Evidence events for the playbook HMM. Order and names must match model/playbooks.json "events"
/// and lookout_detect/events.py.
public enum PlaybookEvent: String, CaseIterable, Sendable, Codable {
    case URGENT_LANGUAGE, PHONE_NUMBER_IN_POPUP, BRAND_IMPERSONATION, LOOKALIKE_DOMAIN, INFECTED_CLAIM
    case REFUND_OVERPAYMENT, REMOTE_ACCESS_STARTED, SCREEN_SHARE_ACTIVE, BANK_SITE_OPENED
    case SENSITIVE_FIELD_ON_UNKNOWN_SITE, PAYMENT_DEMAND, GIFT_CARD_PAGE, WIRE_OR_CRYPTO_PAGE
    case SECRECY_REQUEST, FAMILY_EMERGENCY_STORY, LEGAL_THREAT, GOV_IMPERSONATION, CLAUDE_FLAG
    case CRS_SENDER_HIGH_RISK

    /// Flags reported by an outside check (Claude, CRS); they only count (present or absent) when that check ran.
    public var isModelReported: Bool { self == .CLAUDE_FLAG || self == .CRS_SENDER_HIGH_RISK }
}

/// One step for the playbook engine: everything noticed at one moment.
public struct PlaybookObservation: Sendable, Equatable {
    public var t: TimeInterval
    public var events: Set<PlaybookEvent>
    public var modelRan: Bool
    public var crsChecked: Bool
    public var source: String

    public init(t: TimeInterval, events: Set<PlaybookEvent> = [], modelRan: Bool = false, crsChecked: Bool = false, source: String = "screen") {
        self.t = t
        self.events = events
        self.modelRan = modelRan || events.contains(.CLAUDE_FLAG)
        self.crsChecked = crsChecked || events.contains(.CRS_SENDER_HIGH_RISK)
        self.source = source
    }

    public var observed: [PlaybookEvent] {
        PlaybookEvent.allCases.filter { e in
            switch e {
            case .CLAUDE_FLAG: return modelRan
            case .CRS_SENDER_HIGH_RISK: return crsChecked
            default: return true
            }
        }
    }
}

/// Maps the existing on-device detector (ScamSignals) onto playbook events, so the app and the
/// Python evaluation share one extractor (`lookout-signals` exposes this to Python).
public enum PlaybookEvents {
    static let bankDomains: Set<String> = [
        "chase.com", "wellsfargo.com", "bankofamerica.com", "citi.com", "citibank.com", "usbank.com", "capitalone.com",
        "pnc.com", "tdbank.com", "schwab.com", "fidelity.com", "firstnationaltrust.com", "ally.com", "discover.com",
    ]
    static let screenShareApps = ["screen sharing", "screensharing", "zoom.us", "facetime", "webex", "microsoft teams"]

    public static func extract(_ ctx: ScreenContext, signals: [Signal]? = nil) -> Set<PlaybookEvent> {
        let sig = signals ?? ScamSignals.analyze(ctx)
        func w(_ k: SignalKind) -> Double { sig.filter { $0.kind == k }.map(\.weight).max() ?? 0 }
        func has(_ k: SignalKind, _ min: Double = 0.01) -> Bool { w(k) >= min }
        var out = Set<PlaybookEvent>()
        let host = ctx.url.flatMap(Domains.host(of:))
        let official = sig.contains { $0.kind == .officialDomain }

        if has(.urgency, 0.5) { out.insert(.URGENT_LANGUAGE) }
        if has(.phoneCallToAction, 1.2) || (has(.phoneCallToAction) && (has(.refundBait, 1.0) || has(.govImpersonation) || has(.legalThreat) || has(.infectedClaim))) {
            out.insert(.PHONE_NUMBER_IN_POPUP)
        }
        if (has(.techBrand) && !official) || has(.lookalikeDomain) { out.insert(.BRAND_IMPERSONATION) }
        if has(.lookalikeDomain) || has(.punycodeDomain) || has(.govDomainMismatch) { out.insert(.LOOKALIKE_DOMAIN) }
        if has(.infectedClaim) || has(.doNotClose) { out.insert(.INFECTED_CLAIM) }
        if has(.refundBait, 1.0) || has(.comboRemoteRefund) { out.insert(.REFUND_OVERPAYMENT) }
        // A page instructing to install AnyDesk is the remote-access stage just as much as the app launching.
        if has(.remoteAccessAppRunning) || has(.remoteAccessInstruction, 2.0) { out.insert(.REMOTE_ACCESS_STARTED) }
        let running = ctx.runningApps.map { $0.lowercased() }
        if running.contains(where: { r in screenShareApps.contains { r.contains($0) } }) { out.insert(.SCREEN_SHARE_ACTIVE) }
        if let h = host, bankDomains.contains(Domains.registrable(h)) { out.insert(.BANK_SITE_OPENED) }
        if !ctx.sensitiveFields.isEmpty, !(host.map(Domains.isTrusted) ?? false) { out.insert(.SENSITIVE_FIELD_ON_UNKNOWN_SITE) }
        if has(.giftCardPayment, 2.0) || has(.wirePayment) || has(.p2pPayment) || has(.cryptoPayment, 2.0) || has(.comboPaymentPressure) {
            out.insert(.PAYMENT_DEMAND)
        }
        if has(.giftCardPayment) || ctx.sensitiveFields.contains("gift-card") { out.insert(.GIFT_CARD_PAGE) }
        if has(.wirePayment) || has(.p2pPayment) || has(.cryptoPayment, 0.4) { out.insert(.WIRE_OR_CRYPTO_PAGE) }
        if has(.secrecy) { out.insert(.SECRECY_REQUEST) }
        // The story often comes without a family word ("I was in a car accident, the police arrested me"):
        // two or more emergency cues in one message count too.
        let lower = ctx.text.lowercased()
        if has(.familyEmergency) || ScamSignals.hits(lower, ScamSignals.emergencyWords).count >= 2 { out.insert(.FAMILY_EMERGENCY_STORY) }
        if has(.legalThreat) { out.insert(.LEGAL_THREAT) }
        if (has(.govImpersonation) && !(host?.hasSuffix(".gov") ?? false)) || has(.govDomainMismatch) { out.insert(.GOV_IMPERSONATION) }
        return out
    }
}
