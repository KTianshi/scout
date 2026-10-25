import Foundation

/// Cheap on-device heuristic pass over screen text, URL and running apps.
/// Produces log-odds signals; RiskEngine turns them into a probability.
/// No network, no model: runs every few seconds.
public enum ScamSignals {

    // MARK: Lexicons

    static let infected = [
        "computer is infected", "computer has been infected", "mac is infected", "device is infected",
        "virus detected", "viruses detected", "infected with", "trojan", "spyware", "malware detected",
        "has been compromised", "has been hacked", "security breach", "your computer has been locked",
        "your computer is locked", "system has been locked", "pornographic", "zeus virus", "critical alert",
        "threat detected", "threats detected", "firewall has been breached", "files will be deleted",
        "hard drive will be", "data is at risk", "unauthorized access detected", "error code: 0x", "error # 0x",
        "dw6vb36",
    ]
    static let doNotClose = [
        "do not close", "don't close", "do not restart", "do not shut down", "do not turn off",
        "do not ignore", "closing this window", "don't restart", "don't turn off", "don't shut down",
    ]
    static let techBrands = [
        "microsoft", "windows defender", "windows support", "apple support", "apple security", "apple care",
        "applecare", "norton", "mcafee", "geek squad", "tech support", "technical support", "support team",
        "security center", "help desk", "helpdesk", "certified technician",
    ]
    static let urgency = [
        "immediately", "within 24 hours", "within 48 hours", "urgent", "act now", "final notice", "final warning",
        "suspended", "will be locked", "has been locked", "expires today", "right away", "last chance",
        "in 30 minutes", "within the hour", "today only", "as soon as possible", "time is running out",
        "limited time", "before it's too late", "within 2 hours", "within one hour", "account will be closed",
        "will be disconnected", "will be terminated", "avoid suspension", "respond now", "deadline", "don't delay",
        "hurry", "only a few spots", "expire",
    ]
    static let legalThreat = [
        "arrest", "warrant", "lawsuit", "legal action", "deported", "deportation", "jail", "prison",
        "criminal charges", "sheriff", "us marshal", "u.s. marshal", "federal agent", "court case", "prosecution",
        "suspend your social security", "social security number has been suspended", "badge number", "under investigation",
        "illegal substances", "money laundering", "drug trafficking", "intercepted", "linked to this", "non-disclosure order",
        "case number", "be arrested", "seize", "frozen",
    ]
    static let govNames = [
        "irs", "internal revenue", "social security administration", "ssa", "department of treasury",
        "treasury department", "medicare", "fbi", "federal trade commission", "homeland security",
        "us customs", "u.s. customs", "customs and border protection", "dea", "police department", "department of justice", "federal reserve",
    ]
    static let giftCardWords = ["gift card", "giftcard", "prepaid card", "itunes credit", "steam wallet", "vanilla card", "green dot", "itunes card", "google play card", "steam card", "apple card code", "ebay card"]
    static let giftCardPaymentCues = [
        "pay", "payment", "codes", "code on the back", "scratch", "read the number", "read me the",
        "send the code", "send me the code", "photo of the card", "pictures of the card", "card numbers",
        "buy", "purchase", "settle", "fee", "fine", "owe", "providing the numbers", "silver part", "pictures of the codes", "picture of the back",
    ]
    static let wireWords = [
        "wire transfer", "wire the money", "wire the funds", "western union", "moneygram", "money order",
        "send money", "send the money", "bail money", "bail", "transfer the funds", "cash in an envelope",
        "overnight the cash", "courier will pick up", "send cash", "routing number", "safe account", "secure account",
        "secure federal account", "protect your assets", "move your savings", "move your money", "bond of $", "reduced bond", "bonding clerk",
    ]
    static let p2pWords = ["zelle", "venmo", "cash app", "cashapp", "paypal friends", "apple cash"]
    static let p2pCues = ["send", "pay", "transfer", "payment", "@", "accepted", "$"]
    static let cryptoWords = [
        "bitcoin atm", "crypto atm", "btc atm", "send bitcoin", "deposit bitcoin", "usdt", "tether",
        "wallet address", "deposit crypto", "bitcoin wallet", "crypto wallet", "send crypto", "ethereum address",
        "buy bitcoin", "coinflip atm", "bitcoin depot",
    ]
    static let cryptoMentions = ["bitcoin", "crypto", "btc", "ethereum", "blockchain"]
    static let guaranteed = [
        "guaranteed return", "guaranteed profit", "guaranteed income", "% monthly", "% per month", "% a month",
        "% weekly", "% daily", "risk-free", "risk free", "no risk", "double your", "triple your",
        "can't lose", "cannot lose", "passive income", "my uncle's platform", "insider", "vip trading",
        "trading platform", "withdraw your profits", "withdrawal fee", "unlock your withdrawal", "contract trading",
        "gold trading", "trading app", "the app she uses", "the app he uses", "mentor", "investment opportunity",
    ]
    static let secrecy = [
        "don't tell", "do not tell", "keep this between us", "keep this to yourself", "don't discuss",
        "do not discuss", "don't mention", "do not mention", "keep this confidential", "keep it confidential",
        "keep this secret", "keep it secret", "don't let mom", "don't let dad", "don't let anyone know",
        "between you and me", "no one can know", "nobody can know", "do not share this", "gag order",
        "don't talk to", "do not contact your bank", "don't call your bank", "bank may lie", "bank is involved",
        "do not hang up", "don't hang up", "stay on the line", "discussing the matter", "jeopardize", "tell no one", "confidential case",
    ]
    static let familyWords = [
        "grandma", "grandpa", "granny", "nana", "it's me", "its me", "your grandson", "your granddaughter",
        "your nephew", "your niece", "your son", "your daughter",
    ]
    static let emergencyWords = [
        "car accident", "in jail", "arrested", "bail", "hospital", "lawyer", "attorney", "public defender",
        "stuck in", "lost my wallet", "broke my phone", "new number", "in trouble", "emergency",
    ]
    static let remoteApps = [
        "anydesk", "teamviewer", "screenconnect", "connectwise", "ultraviewer", "logmein", "supremo",
        "rustdesk", "quick assist", "quickassist", "splashtop", "remotepc", "zoho assist", "gotoassist",
        "remote utilities", "aeroadmin", "ammyy",
    ]
    static let remoteCues = [
        "download", "install", "code", "session id", "your id", "9-digit", "9 digit", "allow", "give the",
        "technician", "connect", "access", "remote", "accept", "address",
    ]
    static let refundWords = [
        "refund", "overpaid", "over-refunded", "refunded too much", "accidentally refunded", "auto-renewal",
        "auto renewal", "subscription has been renewed", "subscription renewed", "has been charged",
        "if you did not authorize", "if you didn't authorize", "to cancel", "cancel this order", "dispute this charge",
        "invoice", "order confirmation", "billing department", "renewed for",
    ]
    static let prizeWords = [
        "you've won", "you have won", "you won", "winner", "claim your prize", "lottery", "sweepstakes",
        "jackpot", "selected to receive", "prize", "publishers clearing", "grant approved", "exclusive reward",
        "you qualify for", "you've been chosen", "you have been chosen", "congratulations",
    ]
    static let feeWords = ["processing fee", "fee", "taxes upfront", "pay the taxes", "shipping fee", "release fee", "customs fee", "small payment", "handling fee"]
    static let credentialWords = ["password", "passcode", "sign in", "log in", "login", "username", "verify your account", "confirm your identity", "verify your identity", "security questions", "one-time code", "verification code", "pin"]
    static let credentialPressure = ["verify", "locked", "unusual activity", "suspicious activity", "suspended", "confirm", "restore", "unlock", "update your", "limited", "re-activate", "reactivate"]
    static let ssnWords = ["social security number", "ssn", "social security #", "last 4 of your social"]
    static let medicareNumberWords = ["medicare number", "medicare card number", "medicare id", "mbi", "beneficiary identifier"]
    static let medicareBait = ["free back brace", "free knee brace", "new medicare card", "free genetic test", "free covid test", "free dna", "medicare benefits update", "extra benefits", "free diabetic"]
    static let deliveryWords = ["package", "parcel", "delivery", "shipment", "usps", "ups", "fedex", "dhl", "toll", "e-zpass", "ezpass", "fastrak", "sunpass"]
    static let deliveryFeeCues = ["redelivery fee", "unpaid toll", "outstanding toll", "pay the fee", "small fee", "address incomplete", "update your address", "customs fee", "$1.", "$2.", "$3.", "$0.", "pay now", "late fee", "unpaid balance", "held at", "reopen this message", "activate the link", "reply y", "confirm your preferred delivery", "schedule your delivery", "delivery attempt", "attempted delivery"]
    static let utilityWords = ["power", "electric", "electricity", "gas", "water", "utility", "pg&e", "con edison", "energy company", "meter", "power company", "service"]
    static let shutoffWords = ["disconnect", "shut off", "shutoff", "cut off", "turned off", "disconnection", "will be off", "service interruption", "uninterrupted", "interrupted"]
    static let romanceWords = ["my love", "my darling", "sweetheart", "my dear", "honey", "soulmate", "i love you", "trust me", "our future", "met online", "when we meet", "my queen", "my king", "forever yours", "sweetheart"]
    static let moneyAsk = ["send", "wire", "money", "loan", "help me pay", "need $", "need you to", "transfer", "pay for", "fee", "ticket", "visa", "customs", "invest", "clearance fee", "pay the fee", "pay you back", "gift card"]
    static let charityWords = ["donate", "donation", "relief fund", "victims", "disaster relief", "charity", "orphans", "earthquake", "hurricane", "flood", "lost everything", "medicine tonight", "god bless"]
    static let notABill = ["this is not a bill", "this is not a bill.", "not a bill"]
    static let neverAsk = [
        "we will never ask", "we'll never ask", "will never ask you", "never ask for your password",
        "never ask you to", "never call you", "we will not ask", "never request",
    ]
    static let education = [
        "scam", "scammer", "scammers", "fraudster", "fraudsters", "how to spot", "warning signs", "red flags",
        "protect yourself", "fraud prevention", "ftc", "consumer alert", "according to", "report fraud",
        "reportfraud", "aarp fraud watch", "if you get a call", "if someone asks you", "experts say", "tips to avoid",
        "this type of", "common tactic", "never pay with gift cards", "scams", "is this a scam", "pig butchering",
        "pig-butchering", "fraud alert tips", "victims lost", "told investigators", "police said", "the scheme",
    ]
    static let articleMarkers = [
        "min read", "published", "updated", "posted by", "comments", "share this article", "advertisement",
        "reporter", "staff writer", "subscribe", "points", "upvote", "reply", "related stories", "editor's note", "by the associated press",
    ]
    static let returnsRegex = try! NSRegularExpression(pattern: #"(made|earn(ed)?|returns? of|profit of|up) \d{1,3}(\.\d+)? ?%|\d{1,3} ?% (a|per|each|every|this|just this) (day|week|month)"#)
    static let shopping = [
        "add to cart", "your cart", "order summary", "proceed to checkout", "place your order", "shipping address",
        "estimated delivery", "subtotal", "continue shopping", "add to bag", "free returns", "customer reviews",
        "gift message", "qty",
    ]

    static let phoneRegex = try! NSRegularExpression(
        pattern: #"(?:\+?1[\s.\-]?)?\(?\b[2-9]\d{2}\)?[\s.\-]?\d{3}[\s.\-]\d{4}\b"#
    )
    static let moneyRegex = try! NSRegularExpression(pattern: #"\$\s?\d[\d,]*(?:\.\d{2})?"#)

    // MARK: Helpers

    static func hits(_ text: String, _ words: [String]) -> [String] {
        words.filter { text.contains($0) }
    }

    /// Whole-word match for short tokens like "irs" or "ssa" to avoid "first", "passage".
    static func wordHits(_ text: String, _ words: [String]) -> [String] {
        words.filter { w in
            if w.count > 4 || w.contains(" ") { return text.contains(w) }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func near(_ text: String, _ a: [String], _ b: [String], window: Int = 160) -> (String, String)? {
        for x in a {
            var searchStart = text.startIndex
            while let r = text.range(of: x, range: searchStart..<text.endIndex) {
                let lo = text.index(r.lowerBound, offsetBy: -window, limitedBy: text.startIndex) ?? text.startIndex
                let hi = text.index(r.upperBound, offsetBy: window, limitedBy: text.endIndex) ?? text.endIndex
                let slice = text[lo..<hi]
                if let y = b.first(where: { slice.contains($0) }) { return (x, y) }
                searchStart = r.upperBound
            }
        }
        return nil
    }

    public static func phoneNumbers(in text: String) -> [String] {
        let ns = text as NSString
        return phoneRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static let adviceMarkers = ["never ", "scammer", "fraudster", "beware", "be careful", "watch out for", "won't ever", "will not ask", "is a scam", "are scams", "warning sign", "red flag", "protect yourself"]

    /// Drops sentences that give anti-scam advice; returns the remaining text and how many were dropped.
    static func removeAdviceSentences(_ t: String) -> (String, Int) {
        var kept: [Substring] = [], dropped = 0
        var start = t.startIndex
        var i = t.startIndex
        func flush(_ end: String.Index) {
            let sentence = t[start..<end]
            if adviceMarkers.contains(where: { sentence.contains($0) }) { dropped += 1 } else { kept.append(sentence) }
            start = end
        }
        while i < t.endIndex {
            let c = t[i]
            i = t.index(after: i)
            if c == "." || c == "!" || c == "?" || c == "\n" { flush(i) }
        }
        if start < t.endIndex { flush(t.endIndex) }
        return (kept.joined(), dropped)
    }

    static let freeMail: Set<String> = ["gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "live.com", "icloud.com", "aol.com", "msn.com", "proton.me", "protonmail.com"]

    /// Domain of an email sender line ("From: Name <a@b.com>").
    static func senderDomain(_ t: String) -> String? {
        guard let r = t.range(of: #"from:[^\n]*@([a-z0-9.-]+\.[a-z]{2,})"#, options: .regularExpression) else { return nil }
        let line = String(t[r])
        guard let at = line.lastIndex(of: "@") else { return nil }
        return String(line[line.index(after: at)...]).trimmingCharacters(in: CharacterSet(charactersIn: ">) "))
    }

    static func capped(_ count: Int, per: Double, cap: Double) -> Double {
        min(Double(count) * per, cap)
    }

    // MARK: Analysis

    public static func analyze(_ ctx: ScreenContext) -> [Signal] {
        let original = [ctx.windowTitle ?? "", ctx.text].joined(separator: "\n")
        let full = original.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        // Scam vocabulary inside advice ("We will never ask for gift cards") is not a request.
        let (t, adviceCount) = removeAdviceSentences(full)
        var out: [Signal] = []
        func add(_ k: SignalKind, _ w: Double, _ ev: String, _ target: ThreatTarget = .none) {
            out.append(Signal(kind: k, weight: w, evidence: ev, target: target))
        }

        let phones = phoneNumbers(in: original)
        let callNear = phones.isEmpty ? nil : near(t, ["call", "contact", "dial", "phone", "toll free", "toll-free", "helpline", "hotline"], phones.map { $0.lowercased() }, window: 120)

        // Tech-support pattern
        let inf = hits(t, infected)
        if !inf.isEmpty { add(.infectedClaim, 1.6 + capped(inf.count - 1, per: 0.4, cap: 0.8), inf[0]) }
        let dnc = hits(t, doNotClose)
        if !dnc.isEmpty { add(.doNotClose, 1.8, dnc[0]) }
        let brands = hits(t, techBrands)
        if !brands.isEmpty { add(.techBrand, 0.3, brands[0]) }
        if let phone = phones.first, callNear != nil {
            var w = 0.6
            if !brands.isEmpty || !inf.isEmpty { w += 1.2 }
            add(.phoneCallToAction, w, phone, .phone)
        }
        if !inf.isEmpty, callNear != nil { add(.comboInfectedPhone, 1.5, phones.first ?? "", .phone) }

        // Pressure
        let urg = hits(t, urgency)
        if !urg.isEmpty { add(.urgency, capped(urg.count, per: 0.5, cap: 1.5), urg[0]) }
        let legal = wordHits(t, legalThreat)
        if !legal.isEmpty { add(.legalThreat, 1.0 + capped(legal.count - 1, per: 0.4, cap: 1.0), legal[0]) }
        let gov = wordHits(t, govNames)
        if !gov.isEmpty { add(.govImpersonation, 0.4, gov[0]) }
        let sec = hits(t, secrecy)
        if !sec.isEmpty { add(.secrecy, 2.0 + capped(sec.count - 1, per: 0.4, cap: 0.8), sec[0]) }

        // Payment rails
        let gc = hits(t, giftCardWords)
        var paymentDemand = false
        if !gc.isEmpty {
            let looksLikeShopping = hits(t, shopping).count >= 2
            let underPressure = !legal.isEmpty || !urg.isEmpty || !sec.isEmpty || !gov.isEmpty || !hits(t, romanceWords).isEmpty || !hits(t, prizeWords).isEmpty
            if let (_, cue) = near(t, gc, giftCardPaymentCues, window: 120), !looksLikeShopping || underPressure {
                add(.giftCardPayment, 2.6, "\(gc[0]) … \(cue)", .giftCard)
                paymentDemand = true
            } else {
                add(.giftCardPayment, 0.3, gc[0], .giftCard)
            }
        }
        let wire = hits(t, wireWords)
        if !wire.isEmpty { add(.wirePayment, 1.2 + capped(wire.count - 1, per: 0.3, cap: 0.6), wire[0], .wire); paymentDemand = true }
        let p2p = hits(t, p2pWords)
        if !p2p.isEmpty, let (_, cue) = near(t, p2p, p2pCues, window: 60) {
            add(.p2pPayment, 1.0, "\(p2p[0]) \(cue)", .wire); paymentDemand = true
        }
        let crypto = hits(t, cryptoWords)
        if !crypto.isEmpty { add(.cryptoPayment, 2.2, crypto[0], .crypto); paymentDemand = true }
        else {
            let cm = wordHits(t, cryptoMentions)
            if !cm.isEmpty { add(.cryptoPayment, 0.4, cm[0], .crypto) }
        }
        var guar = hits(t, guaranteed)
        if returnsRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { guar.append("% returns") }
        if !guar.isEmpty { add(.guaranteedReturns, 1.6 + capped(guar.count - 1, per: 0.4, cap: 0.8), guar[0], .crypto) }

        // Family emergency
        let fam = hits(t, familyWords), emer = hits(t, emergencyWords)
        if !fam.isEmpty, !emer.isEmpty {
            let w = paymentDemand || !sec.isEmpty ? 1.6 : 0.6
            add(.familyEmergency, w, "\(fam[0]) … \(emer[0])", .wire)
        }

        // Remote access
        let ra = wordHits(t, remoteApps)
        if !ra.isEmpty {
            if near(t, ra, remoteCues, window: 140) != nil {
                add(.remoteAccessInstruction, 2.2, ra[0], .remoteApp)
            } else {
                add(.remoteAccessInstruction, 0.6, ra[0], .remoteApp)
            }
        }
        let running = ctx.runningApps.map { $0.lowercased() }
        if let app = running.first(where: { r in remoteApps.contains(where: { r.contains($0.replacingOccurrences(of: " ", with: "")) || r.contains($0) }) }) {
            add(.remoteAccessAppRunning, 1.8, app, .remoteApp)
        }

        // Refund / invoice bait
        let ref = wordHits(t, refundWords).filter { $0 != "refund" || t.range(of: #"\brefund\b"#, options: .regularExpression) != nil }
        if !ref.isEmpty {
            var w = 0.4
            if callNear != nil { w += 1.3 }
            if !ra.isEmpty { w += 0.6 }
            add(.refundBait, w, ref[0], callNear != nil ? .phone : .none)
            if !ra.isEmpty { add(.comboRemoteRefund, 1.2, "\(ra[0]) + \(ref[0])", .remoteApp) }
        }

        // Prize / fee
        let prize = hits(t, prizeWords)
        if !prize.isEmpty {
            let fee = hits(t, feeWords)
            add(.prizeFee, fee.isEmpty && !paymentDemand ? 0.6 : 2.0, prize[0])
        }

        // Credentials & identity
        let cred = wordHits(t, credentialWords), pressure = hits(t, credentialPressure)
        if !cred.isEmpty, !pressure.isEmpty { add(.credentialRequest, 0.8, "\(cred[0]) … \(pressure[0])", .login) }
        let ssn = hits(t, ssnWords)
        if !ssn.isEmpty, near(t, ssn, ["enter", "provide", "confirm", "verify", "give", "read", "what is", "need your", "full", "reply with"], window: 80) != nil {
            add(.ssnRequest, 1.3, ssn[0], .ssn)
        }
        let mbi = wordHits(t, medicareNumberWords), bait = hits(t, medicareBait)
        if !mbi.isEmpty, near(t, mbi, ["enter", "provide", "confirm", "verify", "give", "read", "need your", "what is", "reply with", "send", "text us"], window: 80) != nil {
            add(.medicareNumberRequest, bait.isEmpty ? 1.0 : 2.2, mbi[0], .ssn)
        } else if !bait.isEmpty {
            add(.medicareNumberRequest, 0.8, bait[0])
        }

        // Delivery / toll small fee
        let del = wordHits(t, deliveryWords), delFee = hits(t, deliveryFeeCues)
        if !del.isEmpty, !delFee.isEmpty { add(.smallFeeDelivery, 1.8, "\(del[0]) … \(delFee[0])", .link) }

        // Utility shutoff
        let util = wordHits(t, utilityWords), shut = hits(t, shutoffWords)
        if !util.isEmpty, !shut.isEmpty {
            let w = paymentDemand || !urg.isEmpty ? 1.8 : 0.5
            add(.utilityShutoff, w, "\(util[0]) \(shut[0])")
        }

        // Romance + money
        let opener = hits(t, ["wrong number", "my mistake", "sorry to bother", "nice to meet you anyway", "we are not friends", "saw your profile", "saw you in the"])
        if !opener.isEmpty, !guar.isEmpty || near(t, opener, moneyAsk, window: 400) != nil { add(.romanceMoney, 1.0, "stranger opener: " + opener[0]) }
        let rom = hits(t, romanceWords)
        if !rom.isEmpty, near(t, rom, moneyAsk, window: 240) != nil {
            let hasAmount = moneyRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
            add(.romanceMoney, hasAmount ? 2.0 : 1.2, rom[0])
        }

        // Charity pressure
        let ch = hits(t, charityWords)
        if !ch.isEmpty, paymentDemand || !urg.isEmpty { add(.charityPressure, paymentDemand ? 1.5 : 0.8, ch[0]) }

        // Combos
        let romancing = out.contains { $0.kind == .romanceMoney }
        let pretext = out.contains { [.charityPressure, .utilityShutoff, .familyEmergency, .prizeFee].contains($0.kind) }
        let pressureCount = [!urg.isEmpty, !legal.isEmpty, !sec.isEmpty, romancing, pretext].filter { $0 }.count
        if paymentDemand, pressureCount > 0 {
            add(.comboPaymentPressure, 0.8 + 0.5 * Double(pressureCount), "payment + pressure", out.first(where: { [.giftCard, .wire, .crypto].contains($0.target) })?.target ?? .none)
        }

        // Domains
        var hosts: [String] = []
        if let u = ctx.url, let h = Domains.host(of: u) { hosts.append(h) }
        for d in Domains.extract(from: original) where !hosts.contains(d) { hosts.append(d) }
        let pageHost = ctx.url.flatMap(Domains.host(of:))
        var sawLookalike = false
        for h in hosts {
            if Domains.isPunycode(h) {
                add(.punycodeDomain, 2.2, h, .link); sawLookalike = true; break
            }
        }
        for h in hosts {
            if let hit = Domains.lookalike(h) {
                add(.lookalikeDomain, h == pageHost ? 3.0 : 2.4, "\(hit.domain) \(hit.reason)", h == pageHost ? .login : .link)
                sawLookalike = true
                break
            }
        }
        if !gov.isEmpty {
            // Government named, but the page / sender is not .gov
            let senderOrPage = hosts.first { !$0.hasSuffix(".gov") && !Domains.isTrusted($0) }
            if let s = senderOrPage, s.contains("gov") || s.contains("irs") || s.contains("ssa") || s.contains("treasury") || s.contains("medicare") {
                add(.govDomainMismatch, 1.5, s, .link)
            }
        }
        if let h = pageHost ?? hosts.first, Domains.suspiciousTLDs.contains(Domains.tld(h)), !Domains.isTrusted(h) {
            add(.suspiciousTLD, 0.7, h, .link)
        }

        if sawLookalike, !cred.isEmpty, !out.contains(where: { $0.kind == .credentialRequest }) {
            add(.credentialRequest, 0.8, cred[0], .login)
        }

        // Sensitive entry on a page that already looks risky
        let riskyPage = sawLookalike || paymentDemand || !inf.isEmpty || !sec.isEmpty
        if riskyPage, let field = ctx.sensitiveFields.first {
            add(.sensitiveEntryOnRiskyPage, 1.0, field, field == "gift-card" ? .giftCard : (field == "ssn" ? .ssn : .card))
        }

        // Benign context
        let nab = hits(t, notABill)
        if !nab.isEmpty { add(.notABill, -2.0, nab[0]) }
        let nev = hits(t, neverAsk)
        if !nev.isEmpty { add(.neverAskReassurance, -1.5, nev[0]) }
        if adviceCount > 0 { add(.scamEducation, -min(0.5 * Double(adviceCount), 1.5), "\(adviceCount) advice sentence(s)") }
        let edu = wordHits(full, education)
        if !edu.isEmpty { add(.scamEducation, -min(1.2 * Double(edu.count), 4.5), edu.prefix(3).joined(separator: ", ")) }
        if let ph = pageHost, Domains.isTrusted(ph) { add(.officialDomain, -2.0, ph) }
        else if let sender = senderDomain(full), !freeMail.contains(sender), Domains.isTrusted(sender) { add(.officialDomain, -1.0, sender) }
        let art = hits(full, articleMarkers)
        if art.count >= 2 { add(.scamEducation, -1.0, "article: " + art.prefix(2).joined(separator: ", ")) }
        let shop = hits(t, shopping)
        if shop.count >= 2 { add(.userInitiatedShopping, -min(0.6 * Double(shop.count), 2.0), shop[0]) }

        // A screen that reads strongly as an article or advice page: halve the scam evidence.
        let benignTotal = out.filter { $0.weight < 0 }.reduce(0) { $0 + $1.weight }
        if benignTotal <= -5 {
            out = out.map { var s = $0; if s.weight > 0 { s.weight *= 0.5 }; return s }
        }
        return out
    }

    /// The prior log-odds plus the sum of signal weights for one screen, without memory.
    public static func screenScore(_ signals: [Signal], prior: Double = RiskEngine.Config().prior) -> Double {
        prior + signals.reduce(0) { $0 + $1.weight }
    }
}
