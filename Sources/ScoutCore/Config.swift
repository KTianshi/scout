import Foundation

/// One place for tunables that are not per-user settings.
public enum ScoutConfig {
    /// Vision model for help and scam confirmation. Override with SCOUT_MODEL.
    public static var model: String {
        ProcessInfo.processInfo.environment["SCOUT_MODEL"] ?? "claude-sonnet-5-5"
    }
    public static let anthropicVersion = "2026-10-21"
    public static var apiBase: URL {
        URL(string: ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.anthropic.com")!
    }
    public static var familyServer: URL {
        URL(string: Secrets.shared["SCOUT_FAMILY_URL"] ?? "http://127.0.0.1:4545")!
    }
    /// Family features (alerts to the family app, "check with Sarah first" approvals, family wording).
    /// Off for now: it felt infantilizing. Turn back on with SCOUT_FAMILY=1 in secrets.env.
    public static var familyEnabled: Bool { Secrets.shared["SCOUT_FAMILY"] == "1" }

    /// Names come from Settings first, then secrets.env, then demo defaults.
    public static var elderName: String { saved("elderName") ?? Secrets.shared["ELDER_NAME"] ?? "Mom" }
    public static var familyName: String { saved("familyName") ?? Secrets.shared["FAMILY_NAME"] ?? "Sarah" }

    public static func setNames(elder: String, family: String) {
        UserDefaults.standard.set(elder.trimmingCharacters(in: .whitespaces), forKey: "elderName")
        UserDefaults.standard.set(family.trimmingCharacters(in: .whitespaces), forKey: "familyName")
    }

    private static func saved(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Probability above which the guardian asks Claude to confirm.
    /// Override with SCOUT_CONFIRM_THRESHOLD (e.g. 0.03 to ask Claude about nearly every screen with any signal).
    public static var confirmThreshold: Double {
        ProcessInfo.processInfo.environment["SCOUT_CONFIRM_THRESHOLD"].flatMap(Double.init) ?? 0.10
    }
    /// Seconds between guardian passes.
    public static let guardianInterval: TimeInterval = 3
    /// Longest edge of screenshots sent to the model.
    /// About 1080p-class: sharp enough for small toolbar icons, within the model's 2576 px limit.
    public static let screenshotMaxEdge: CGFloat = 1920
}

/// Loads secrets from the environment, then ~/.config/scout/secrets.env (KEY=VALUE lines).
/// Never logs values.
public final class Secrets: @unchecked Sendable {
    public static let shared = Secrets()
    private var values: [String: String] = [:]

    /// ~/.config/scout/secrets.env, or the file from before the rename (~/.config/lookout/) if that's the one there.
    public static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let current = home.appendingPathComponent(".config/scout/secrets.env")
        let old = home.appendingPathComponent(".config/lookout/secrets.env")
        return !FileManager.default.fileExists(atPath: current.path) && FileManager.default.fileExists(atPath: old.path) ? old : current
    }

    public init(fileURL: URL = Secrets.fileURL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let data = try? String(contentsOf: fileURL, encoding: .utf8) {
            values = Secrets.parse(data)
        }
        for (k, v) in environment where !v.isEmpty { values[k] = v }
    }

    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            if l.hasPrefix("export ") { l = String(l.dropFirst(7)) }
            guard let eq = l.firstIndex(of: "=") else { continue }
            let k = l[..<eq].trimmingCharacters(in: .whitespaces)
            var v = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            }
            if !k.isEmpty { out[k] = v }
        }
        return out
    }

    public subscript(_ key: String) -> String? { values[key] }
    public var anthropicKey: String? { values["ANTHROPIC_API_KEY"] }
    public var hasAnthropicKey: Bool { !(anthropicKey ?? "").isEmpty }
    /// For diagnostics: which keys are present (never values).
    public var presentKeys: [String] { values.keys.filter { $0.hasPrefix("ANTHROPIC") || $0.hasPrefix("TWILIO") || $0.hasPrefix("SCOUT") }.sorted() }
}
