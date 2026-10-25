import Foundation

/// Parses guidance tags emitted by the model.
///
///   [POINT:x,y:label]   point at pixel (x,y) in the screenshot the model was shown
///   [POINT:none]        nothing to point at
///   [STEP:n]            start of step n in a multi-step walkthrough
///
/// Pattern adapted from OpenClicky's CompanionManager+PointTagParsing (MIT); see THIRD_PARTY_NOTICES.md.
public enum PointTags {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var label: String?
        public init(x: Double, y: Double, label: String?) { self.x = x; self.y = y; self.label = label }
    }

    /// One spoken chunk, optionally with a place to point while saying it.
    public struct Step: Equatable, Sendable {
        public var index: Int
        public var text: String
        public var point: Point?
        public init(index: Int, text: String, point: Point?) { self.index = index; self.text = text; self.point = point }
    }

    static let pointRegex = try! NSRegularExpression(
        pattern: #"\[POINT:\s*(?:none|(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*:\s*([^\]]*?))?)\s*\]"#,
        options: [.caseInsensitive]
    )
    static let stepRegex = try! NSRegularExpression(pattern: #"\[STEP:\s*(\d+)\s*\]"#, options: [.caseInsensitive])

    /// Remove every tag and tidy whitespace: what gets spoken / shown.
    public static func strip(_ text: String) -> String {
        var s = text
        for r in [pointRegex, stepRegex] {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #" +([.,!?])"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// While streaming, a tag may be half-received; hide a trailing "[POI…" fragment.
    public static func stripTrailingPartialTag(_ text: String) -> String {
        guard let open = text.lastIndex(of: "[") else { return text }
        let frag = text[open...]
        if frag.contains("]") { return text }
        let up = frag.uppercased()
        let prefixes = ["[POINT", "[STEP"]
        if prefixes.contains(where: { $0.hasPrefix(up) || up.hasPrefix($0) }) {
            return String(text[..<open])
        }
        return text
    }

    public static func points(in text: String) -> [Point] {
        let ns = text as NSString
        return pointRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.range(at: 1).location != NSNotFound, m.range(at: 2).location != NSNotFound,
                  let x = Double(ns.substring(with: m.range(at: 1))),
                  let y = Double(ns.substring(with: m.range(at: 2))) else { return nil }
            var label: String?
            if m.range(at: 3).location != NSNotFound {
                let l = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
                label = l.isEmpty ? nil : l
            }
            return Point(x: x, y: y, label: label)
        }
    }

    /// Split a response into steps. Text before the first [STEP] is step 0 (intro).
    /// Without [STEP] tags, each [POINT] closes a step (text up to and including the tag).
    public static func steps(in text: String) -> [Step] {
        let ns = text as NSString
        let stepMatches = stepRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var chunks: [(Int, String)] = []
        if stepMatches.isEmpty {
            // Split after each POINT tag.
            let pms = pointRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            var start = 0, i = 1
            for m in pms {
                let end = m.range.location + m.range.length
                chunks.append((i, ns.substring(with: NSRange(location: start, length: end - start))))
                start = end; i += 1
            }
            if start < ns.length { chunks.append((i, ns.substring(from: start))) }
        } else {
            let intro = ns.substring(to: stepMatches[0].range.location)
            if !strip(intro).isEmpty { chunks.append((0, intro)) }
            for (k, m) in stepMatches.enumerated() {
                let n = Int(ns.substring(with: m.range(at: 1))) ?? (k + 1)
                let from = m.range.location + m.range.length
                let to = k + 1 < stepMatches.count ? stepMatches[k + 1].range.location : ns.length
                chunks.append((n, ns.substring(with: NSRange(location: from, length: to - from))))
            }
        }
        return chunks.compactMap { (n, raw) in
            let spoken = strip(raw)
            let p = points(in: raw).first
            if spoken.isEmpty && p == nil { return nil }
            return Step(index: n, text: spoken, point: p)
        }
    }
}
