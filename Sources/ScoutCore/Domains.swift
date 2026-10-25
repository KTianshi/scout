import Foundation

/// Domain helpers: extraction, registrable domain, lookalike and punycode checks.
public enum Domains {
    /// Brand token → the registrable domains that brand legitimately uses.
    public static let brands: [String: [String]] = [
        "microsoft": ["microsoft.com", "live.com", "office.com", "windows.com", "outlook.com"],
        "windows": ["microsoft.com", "windows.com"],
        "apple": ["apple.com", "icloud.com"],
        "icloud": ["icloud.com", "apple.com"],
        "paypal": ["paypal.com"],
        "amazon": ["amazon.com"],
        "chase": ["chase.com"],
        "wellsfargo": ["wellsfargo.com"],
        "bankofamerica": ["bankofamerica.com"],
        "citibank": ["citi.com", "citibank.com"],
        "netflix": ["netflix.com"],
        "norton": ["norton.com"],
        "mcafee": ["mcafee.com"],
        "geeksquad": ["bestbuy.com", "geeksquad.com"],
        "usps": ["usps.com"],
        "fedex": ["fedex.com"],
        "ups": ["ups.com"],
        "walmart": ["walmart.com"],
        "venmo": ["venmo.com"],
        "zelle": ["zellepay.com"],
        "ezpass": ["e-zpassny.com", "ezpassnj.com", "e-zpassiag.com"],
        "coinbase": ["coinbase.com"],
        "medicare": ["medicare.gov", "cms.gov"],
        "socialsecurity": ["ssa.gov"],
        "irs": ["irs.gov"],
        "treasury": ["treasury.gov"],
        "firstnationaltrust": ["firstnationaltrust.com"],
        "facebook": ["facebook.com"],
        "google": ["google.com"],
    ]

    /// Registrable domains we treat as trusted when they are the page's own address.
    public static let trusted: Set<String> = {
        var s = Set(brands.values.flatMap { $0 })
        s.formUnion([
            "ups.com", "ssa.gov", "irs.gov", "medicare.gov", "usa.gov", "ftc.gov", "aarp.org",
            "google.com", "gmail.com", "yahoo.com", "nytimes.com", "cnn.com", "bbc.co.uk", "npr.org",
            "weather.com", "target.com", "walmart.com", "bestbuy.com", "costco.com", "cvs.com",
            "turbotax.intuit.com", "intuit.com", "hrblock.com", "facetime.apple.com", "zoom.us",
            "wikipedia.org", "allrecipes.com", "shopriver.com", "kaiserpermanente.org",
        ])
        return s
    }()

    static let multiPartSuffixes: Set<String> = ["co.uk", "com.au", "co.jp", "com.br", "co.nz", "org.uk", "gov.uk"]

    static let suspiciousTLDs: Set<String> = [
        "xyz", "top", "help", "support", "live", "click", "info", "online", "site", "icu", "buzz",
        "shop", "store", "win", "loan", "vip", "work", "rest", "cam", "monster", "tk", "ml", "ga", "cf", "gq",
    ]

    private static let knownTLDs = "com|net|org|gov|edu|io|co|us|uk|info|biz|xyz|top|help|support|live|click|online|site|icu|buzz|shop|store|win|loan|vip|work|rest|cam|monster|tk|ml|ga|cf|gq|ru|cn|me|app|dev|ly|to|cc|pro|tech|money|finance|bank|security|services"

    private static let domainRegex = try! NSRegularExpression(
        pattern: #"(?:https?://)?((?:[a-z0-9¡-￿](?:[a-z0-9¡-￿-]{0,61}[a-z0-9¡-￿])?\.)+(?:"# + knownTLDs + #"))(?![a-z0-9-])"#,
        options: [.caseInsensitive]
    )

    /// Host of a URL string, lowercased, without "www.".
    public static func host(of url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !s.contains("://") { s = "http://" + s }
        guard let comps = URLComponents(string: s), var h = comps.host, !h.isEmpty else {
            // URLComponents rejects some unicode hosts; fall back to manual parse.
            let afterScheme = s.components(separatedBy: "://").last ?? s
            let h = afterScheme.split(whereSeparator: { "/?#:".contains($0) }).first.map(String.init)
            return h.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h
    }

    public static func registrable(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) { return labels.suffix(3).joined(separator: ".") }
        return lastTwo
    }

    public static func tld(_ host: String) -> String {
        String(host.split(separator: ".").last ?? "")
    }

    public static func isTrusted(_ host: String) -> Bool {
        let h = host.lowercased()
        if trusted.contains(h) { return true }
        if trusted.contains(registrable(h)) { return true }
        if h.hasSuffix(".gov") { return true }
        return false
    }

    /// All domain-looking tokens in text (including sender addresses), lowercased.
    public static func extract(from text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        for m in domainRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var d = ns.substring(with: m.range(at: 1)).lowercased()
            if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
            // Skip things like "e.g." or version-number noise
            if d.count < 5 { continue }
            if !out.contains(d) { out.append(d) }
        }
        return out
    }

    /// Undo common character substitutions used in typosquats.
    public static func deconfuse(_ s: String) -> String {
        var r = s.lowercased()
        let map: [(String, String)] = [
            ("0", "o"), ("1", "l"), ("3", "e"), ("4", "a"), ("5", "s"), ("7", "t"), ("@", "a"),
            ("rn", "m"), ("vv", "w"), ("í", "i"), ("ì", "i"), ("ï", "i"), ("á", "a"), ("à", "a"),
            ("é", "e"), ("ó", "o"), ("ò", "o"), ("ú", "u"), ("ı", "i"), ("а", "a"), ("е", "e"),
            ("о", "o"), ("р", "p"), ("с", "c"), ("х", "x"),
        ]
        for (a, b) in map { r = r.replacingOccurrences(of: a, with: b) }
        return r.replacingOccurrences(of: "-", with: "")
    }

    public struct LookalikeHit: Equatable, Sendable {
        public var domain: String
        public var brand: String
        public var reason: String
    }

    /// Detects brand impersonation in a host: brand token present (after deconfusing)
    /// but the registrable domain is not one the brand uses.
    public static func lookalike(_ host: String) -> LookalikeHit? {
        let h = host.lowercased()
        if isTrusted(h) { return nil }
        let reg = registrable(h)
        let flat = deconfuse(h.replacingOccurrences(of: ".", with: ""))
        let raw = h.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "-", with: "")
        // Hyphen/dot-separated parts, deconfused, for short brand names ("irs-gov-payments").
        let parts = h.split(whereSeparator: { $0 == "." || $0 == "-" }).map { deconfuse(String($0)) }
        for (brand, official) in brands {
            if official.contains(reg) { continue }
            let found = brand.count <= 4 ? parts.contains(brand) : flat.contains(brand)
            if found {
                let reason = raw.contains(brand) ? "uses the name \(brand) but is not \(official[0])" : "is a misspelling of \(official[0])"
                return LookalikeHit(domain: h, brand: brand, reason: reason)
            }
        }
        // Near-miss of a brand's main label (one edit away), e.g. "paypai.com"
        let mainLabel = String(reg.split(separator: ".").first ?? "")
        let labelParts = [mainLabel] + mainLabel.split(separator: "-").map(String.init)
        for (brand, official) in brands where brand.count >= 5 {
            if official.contains(reg) { continue }
            if labelParts.contains(where: { editDistance($0, brand) == 1 }) {
                return LookalikeHit(domain: h, brand: brand, reason: "is a misspelling of \(official[0])")
            }
        }
        return nil
    }

    public static func isPunycode(_ host: String) -> Bool {
        host.lowercased().split(separator: ".").contains { $0.hasPrefix("xn--") }
            || host.unicodeScalars.contains { $0.value > 0x7F }
    }

    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
