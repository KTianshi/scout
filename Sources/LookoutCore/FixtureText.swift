import Foundation

/// Turns a demo HTML scenario into a ScreenContext without a browser (for the benchmark and tests).
/// The app's fixture mode renders the page in WebKit instead, so it also gets a real screenshot.
public enum FixtureText {
    public struct Parsed {
        public var context: ScreenContext
        public var label: String?
        public var threat: String?
    }

    static func meta(_ html: String, _ name: String) -> String? {
        let pattern = #"<meta\s+name=["']"# + NSRegularExpression.escapedPattern(for: name) + #"["']\s+content=["']([^"']*)["']"#
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    public static func stripTags(_ html: String) -> String {
        var s = html
        for block in ["script", "style", "head", "svg"] {
            s = s.replacingOccurrences(of: "<\(block)[^>]*>[\\s\\S]*?</\(block)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(br|/p|/div|/li|/h\\d|/tr)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        // Keep input placeholders/values: they are visible text on screen.
        s = s.replacingOccurrences(of: #"<input[^>]*placeholder=["']([^"']*)["'][^>]*>"#, with: " $1 ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&middot;": "·"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sensitiveFields(_ html: String) -> [String] {
        guard let r = try? NSRegularExpression(pattern: #"data-lookout-sensitive=["']([^"']+)["']"#) else { return [] }
        var out: [String] = []
        for m in r.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let range = Range(m.range(at: 1), in: html) {
                let v = String(html[range]); if !out.contains(v) { out.append(v) }
            }
        }
        return out
    }

    public static func context(fromHTML html: String, runningApps: [String] = []) -> Parsed {
        let url = meta(html, "lookout-url")
        let app = meta(html, "lookout-app")
        var title: String?
        if let r = html.range(of: "<title>"), let e = html.range(of: "</title>"), r.upperBound < e.lowerBound {
            title = String(html[r.upperBound..<e.lowerBound])
        }
        let ctx = ScreenContext(text: stripTags(html), url: url, appName: app, windowTitle: title, runningApps: runningApps, sensitiveFields: sensitiveFields(html))
        return Parsed(context: ctx, label: meta(html, "lookout-label"), threat: nil)
    }
}
