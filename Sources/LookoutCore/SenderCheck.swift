import Foundation

/// Result of checking a suspicious message's SENDER with CRS Fraud Finder (via the family server).
/// Only scammer-side identifiers are checked, never anything about the person Lookout protects.
public struct SenderCheck: Sendable, Equatable {
    public enum Verdict: String, Sendable { case high, medium, low, unknown }
    public var email: String
    public var verdict: Verdict
    public var score: Int?
    public var firstSeen: String?
    public var newToday: Bool
    /// Plain-language sentence for the buddy ("I checked who sent this...").
    public var sentence: String
    /// "crs" for a real CRS answer; "mock" when CRS was not configured or unreachable.
    public var source: String

    public init(email: String, verdict: Verdict, score: Int?, firstSeen: String?, newToday: Bool, sentence: String, source: String) {
        self.email = email; self.verdict = verdict; self.score = score; self.firstSeen = firstSeen
        self.newToday = newToday; self.sentence = sentence; self.source = source
    }

    /// Only real CRS answers count as evidence; mock answers are shown in logs but never change the score.
    public var countsAsEvidence: Bool { source == "crs" && verdict != .unknown }
    public var isHighRisk: Bool { countsAsEvidence && verdict == .high }

    public static func from(json o: [String: Any]) -> SenderCheck? {
        guard let email = o["email"] as? String else { return nil }
        return SenderCheck(
            email: email,
            verdict: Verdict(rawValue: o["verdict"] as? String ?? "") ?? .unknown,
            score: (o["score"] as? NSNumber)?.intValue,
            firstSeen: o["firstSeen"] as? String,
            newToday: o["newToday"] as? Bool ?? false,
            sentence: o["sentence"] as? String ?? "",
            source: o["source"] as? String ?? "mock"
        )
    }

    static let emailRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)

    /// The sender of the message on screen: a mailto: address, or the address on a "From:" line.
    public static func extractSender(_ ctx: ScreenContext) -> String? {
        if let u = ctx.url, u.lowercased().hasPrefix("mailto:") {
            let addr = String(u.dropFirst(7)).components(separatedBy: "?").first ?? ""
            if firstEmail(in: addr) != nil { return addr.lowercased() }
        }
        for line in ctx.text.split(whereSeparator: \.isNewline).prefix(60) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.lowercased().hasPrefix("from:") || l.lowercased().hasPrefix("from ") {
                if let e = firstEmail(in: l) { return e.lowercased() }
            }
        }
        return nil
    }

    static func firstEmail(in s: String) -> String? {
        let ns = s as NSString
        guard let m = emailRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}
