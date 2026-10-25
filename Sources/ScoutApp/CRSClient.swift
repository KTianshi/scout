import Foundation
import ScoutCore

/// CRS Fraud Finder, called straight from the app (a Swift port of family/crs.js), so the sender check works
/// without the family server. Only the scam message's sender address is sent, never anything about the person
/// Scout protects. Credentials: CRS_USERNAME / CRS_PASSWORD in secrets.env. Never logged.
actor CRSClient {
    static let shared = CRSClient()

    private let base = URL(string: Secrets.shared["CRS_BASE_URL"] ?? "https://api-sandbox.stitchcredit.com:443/api")!
    private var token: String?
    private var tokenExpires = Date.distantPast
    private var cache: [String: (at: Date, result: SenderCheck)] = [:]

    nonisolated static var isConfigured: Bool {
        !(Secrets.shared["CRS_USERNAME"] ?? "").isEmpty && !(Secrets.shared["CRS_PASSWORD"] ?? "").isEmpty
            && Secrets.shared["CRS_MOCK"] != "1"
    }

    /// nil when CRS can't be reached; the caller then treats the sender as unchecked.
    func checkSender(_ raw: String) async -> SenderCheck? {
        let email = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard email.contains("@") else { return nil }
        if let hit = cache[email], Date().timeIntervalSince(hit.at) < 24 * 3600 { return hit.result }
        do {
            let t = try await login()
            let (status, json) = try await post("fraud-finder/fraud-finder", ["email": email], auth: t)
            guard status == 200, let json else { throw CRSError.http("Fraud Finder", status) }
            let result = Self.interpret(email, json)
            cache[email] = (Date(), result)
            return result
        } catch {
            Log.info("crs sender check failed: \(error)")
            return nil
        }
    }

    enum CRSError: Error, CustomStringConvertible {
        case http(String, Int)
        var description: String { if case .http(let what, let code) = self { return "\(what) HTTP \(code)" }; return "" }
    }

    private func login() async throws -> String {
        if let token, Date() < tokenExpires.addingTimeInterval(-60) { return token }
        let (status, json) = try await post("users/login", ["username": Secrets.shared["CRS_USERNAME"] ?? "",
                                                             "password": Secrets.shared["CRS_PASSWORD"] ?? ""], auth: nil)
        guard status == 200, let t = json?["token"] as? String else { throw CRSError.http("login", status) }
        token = t
        tokenExpires = Date().addingTimeInterval((json?["expires"] as? NSNumber)?.doubleValue ?? 3600)
        return t
    }

    private func post(_ path: String, _ body: [String: String], auth: String?) async throws -> (Int, [String: Any]?) {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        if let auth { r.setValue("Bearer \(auth)", forHTTPHeaderField: "authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: d) as? [String: Any])
    }

    /// Same thresholds and wording as family/crs.js `interpret`.
    static func interpret(_ email: String, _ j: [String: Any]) -> SenderCheck {
        let risk = j["risk"] as? [String: Any] ?? [:]
        let eam = j["eam"] as? [String: Any] ?? [:]
        let score = (risk["score"] as? NSNumber)?.intValue
        let domainRisk = ((risk["domain"] as? [String: Any])?["domain_risk_score"] as? NSNumber)?.intValue
        let firstSeen = eam["date_first_seen"] as? String
        let longevity = (eam["longevity"] as? NSNumber)?.intValue
        // CRS dates are UTC; "today" also means today where the person is (evenings in California are tomorrow in UTC).
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let localToday = f.string(from: Date())
        f.timeZone = TimeZone(identifier: "UTC")
        let newToday = firstSeen == "now" || firstSeen == f.string(from: Date()) || firstSeen == localToday

        var verdict = SenderCheck.Verdict.unknown
        if let score {
            if score >= 80 || (domainRisk ?? 0) >= 8 { verdict = .high }
            else if score <= 30 && (longevity == nil || longevity! >= 1) { verdict = .low }
            else { verdict = .medium }
        }
        let sentence: String
        switch verdict {
        case .high:
            sentence = newToday
                ? "I checked who sent this. That email address first appeared today and is rated very high risk."
                : "I checked who sent this. That email address is rated high risk (\(score ?? 0) out of 100)."
        case .low:
            sentence = firstSeen.map { "The sender's address has been in use since \($0.prefix(4)) and looks normal." } ?? "The sender's address looks normal."
        default:
            sentence = "I couldn't tell much about who sent this."
        }
        return SenderCheck(email: email, verdict: verdict, score: score, firstSeen: firstSeen, newToday: newToday, sentence: sentence, source: "crs")
    }
}
