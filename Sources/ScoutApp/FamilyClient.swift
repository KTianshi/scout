import Foundation
import ScoutCore

enum Log {
    /// Logs go to stderr and ~/Library/Application Support/Scout/scout.log. Never log keys or screen text.
    static let dir: URL = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = support.appendingPathComponent("Scout", isDirectory: true)
        // Before the rename everything lived in "Lookout" (voice cache, custom buddy, family data): move it over once.
        let old = support.appendingPathComponent("Lookout", isDirectory: true)
        if !fm.fileExists(atPath: d.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: d) }
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let file = dir.appendingPathComponent("scout.log")
    private static let queue = DispatchQueue(label: "scout.log")

    static func info(_ s: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        queue.async {
            if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.data(using: .utf8)!.write(to: file) }
        }
    }
}

/// Talks to the family web app (family/server.js). Failures are logged, never fatal.
final class FamilyClient: @unchecked Sendable {
    let base: URL
    private let session: URLSession

    init(base: URL = ScoutConfig.familyServer) {
        self.base = base
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        session = URLSession(configuration: cfg)
    }

    struct Event {
        var type: String          // scam_alert | remote_access | payment_pause | help | info
        var title: String
        var explanation: String
        var risk: Double? = nil
        var url: String? = nil
        var app: String? = nil
        var screenshot: String? = nil
        var action: String? = nil
    }

    private func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
        guard ScoutConfig.familyEnabled else { return nil }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (d, resp) = try await session.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { Log.info("family \(path) → HTTP \(code)"); return nil }
            return try JSONSerialization.jsonObject(with: d) as? [String: Any]
        } catch {
            Log.info("family server unreachable (\(path)): \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func send(_ e: Event) async -> Bool {
        guard ScoutConfig.familyEnabled else { return false }
        var b: [String: Any] = ["type": e.type, "title": e.title, "explanation": e.explanation]
        if let v = e.risk { b["risk"] = v }
        if let v = e.url { b["url"] = v }
        if let v = e.app { b["app"] = v }
        if let v = e.screenshot { b["screenshot"] = v }
        if let v = e.action { b["action"] = v }
        let ok = await post("api/events", b) != nil
        Log.info("family event \(e.type) '\(e.title)' sent=\(ok)")
        return ok
    }

    /// Creates an approval request; returns its id.
    func requestApproval(title: String, explanation: String, amount: Double?, payee: String?, method: String?, risk: Double, screenshot: String?) async -> String? {
        var b: [String: Any] = ["title": title, "explanation": explanation, "risk": risk]
        if let amount { b["amount"] = amount }
        if let payee { b["payee"] = payee }
        if let method { b["method"] = method }
        if let screenshot { b["screenshot"] = screenshot }
        let id = await post("api/approvals", b)?["id"] as? String
        Log.info("family approval requested id=\(id ?? "none")")
        return id
    }

    /// CRS Fraud Finder check of a suspicious message's sender, via the family server (which holds the CRS keys).
    func checkSender(_ email: String) async -> SenderCheck? {
        var r = URLRequest(url: base.appendingPathComponent("api/crs/check-sender"))
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return SenderCheck.from(json: o)
        } catch {
            Log.info("crs sender check unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    enum ApprovalStatus: String { case pending, approved, denied, unknown }

    func approvalStatus(_ id: String) async -> (ApprovalStatus, String?) {
        do {
            let (d, _) = try await session.data(from: base.appendingPathComponent("api/approvals/\(id)"))
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            return (ApprovalStatus(rawValue: o?["status"] as? String ?? "") ?? .unknown, o?["note"] as? String)
        } catch {
            return (.unknown, nil)
        }
    }
}
