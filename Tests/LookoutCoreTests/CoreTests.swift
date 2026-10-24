import Foundation
import Testing
@testable import LookoutCore

@Suite struct DomainTests {
    @Test func registrable() {
        #expect(Domains.registrable("login.paypal.com.secure-verify.net") == "secure-verify.net")
        #expect(Domains.registrable("www.bbc.co.uk") == "bbc.co.uk")
        #expect(Domains.host(of: "https://www.Chase.com/login?x=1") == "chase.com")
    }

    @Test func lookalikes() {
        #expect(Domains.lookalike("micros0ft-security-alert.com") != nil)
        #expect(Domains.lookalike("paypal.com.secure-verify.net") != nil)
        #expect(Domains.lookalike("paypai.com") != nil)
        #expect(Domains.lookalike("firstnationaltrust-secure-login.verify-account.net") != nil)
        #expect(Domains.lookalike("paypal.com") == nil)
        #expect(Domains.lookalike("support.apple.com") == nil)
        #expect(Domains.lookalike("firstnationaltrust.com") == nil)
        #expect(Domains.lookalike("nytimes.com") == nil)
    }

    @Test func punycode() {
        #expect(Domains.isPunycode("xn--frstnationaltrust-9ob.com"))
        #expect(Domains.isPunycode("fírstnationaltrust.com"))
        #expect(!Domains.isPunycode("chase.com"))
    }

    @Test func extract() {
        let d = Domains.extract(from: "From: IRS <notice@irs-gov-payments.co> visit https://www.example.com/x now")
        #expect(d.contains("irs-gov-payments.co"))
        #expect(d.contains("example.com"))
    }
}

@Suite struct SignalTests {
    let techSupport = ScreenContext(
        text: """
        Windows Defender Security Center. Your computer has been infected with a Trojan virus.
        Do not close this window or restart your computer. Call Microsoft Support immediately at (888) 555-0142.
        """,
        url: "https://micros0ft-security-alert.com/alert"
    )

    @Test func techSupportSignals() {
        let kinds = Set(ScamSignals.analyze(techSupport).map(\.kind))
        #expect(kinds.contains(.infectedClaim))
        #expect(kinds.contains(.doNotClose))
        #expect(kinds.contains(.phoneCallToAction))
        #expect(kinds.contains(.lookalikeDomain))
    }

    @Test func phoneNumbers() {
        #expect(ScamSignals.phoneNumbers(in: "call +1-844-555-0199 or (888) 555-0142 or 1.800.555.0123").count == 3)
        #expect(ScamSignals.phoneNumbers(in: "order 2024-1234").isEmpty)
    }

    @Test func wordBoundaries() {
        // "first" must not trigger "irs"; "passage" must not trigger "ssa".
        let s = ScamSignals.analyze(ScreenContext(text: "The first passage of the book."))
        #expect(!s.contains { $0.kind == .govImpersonation })
    }

    @Test func giftCardShoppingIsNotPayment() {
        let shop = ScreenContext(
            text: "ShopRiver Gift Cards. $50 Birthday gift card. Add to cart. Your cart subtotal $50.00. Gift message: Happy birthday Emma! Proceed to checkout",
            url: "https://www.shopriver.com/gift-cards", sensitiveFields: ["card"]
        )
        let s = ScamSignals.analyze(shop)
        #expect(!s.contains { $0.kind == .giftCardPayment && $0.weight > 1 })
    }

    @Test func remoteAppRunning() {
        let s = ScamSignals.analyze(ScreenContext(text: "", runningApps: ["Finder", "AnyDesk"]))
        #expect(s.contains { $0.kind == .remoteAccessAppRunning })
    }
}

@Suite struct RiskTests {
    @Test func accumulatesAcrossSteps() {
        let e = RiskEngine()
        let t0 = Date()
        let a1 = e.ingest(ScamSignals.analyze(ScreenContext(text: "Your refund of $399.99 has been processed. If you did not authorize this, call (844) 555-0199.")), at: t0)
        let a2 = e.ingest(ScamSignals.analyze(ScreenContext(text: "Download AnyDesk and give the technician your 9-digit code.")), at: t0.addingTimeInterval(20))
        #expect(a2.probability > a1.probability)
    }

    @Test func repeatedScreenDoesNotInflate() {
        let e = RiskEngine()
        let ctx = ScreenContext(text: "Act now! Final notice. Your account will be closed.")
        let t0 = Date()
        let a = e.ingest(ScamSignals.analyze(ctx), at: t0)
        var last = a
        for i in 1...20 { last = e.ingest(ScamSignals.analyze(ctx), at: t0.addingTimeInterval(Double(i) * 3)) }
        #expect(last.logOdds <= a.logOdds + 1e-9)
    }

    @Test func decays() {
        let e = RiskEngine()
        let t0 = Date()
        let hi = e.ingest(ScamSignals.analyze(SignalTests().techSupport), at: t0)
        let later = e.assess(currentScreen: [], at: t0.addingTimeInterval(600))
        #expect(later.probability < hi.probability)
        #expect(later.probability < 0.2)
    }

    @Test func modelVerdictMoves() {
        let e = RiskEngine()
        let base = e.assess(currentScreen: [])
        let up = e.ingestModelVerdict(isScam: true, confidence: 0.95)
        #expect(up.probability > base.probability)
        let down = e.ingestModelVerdict(isScam: false, confidence: 0.95)
        #expect(down.probability < up.probability)
    }
}

@Suite struct PolicyTests {
    let p = ActionPolicy()

    @Test func monotone() {
        var last = Action.quiet
        for i in 0...100 {
            let a = p.decide(probability: Double(i) / 100).action
            #expect(a >= last)
            last = a
        }
    }

    @Test func lowRiskQuiet() { #expect(p.decide(probability: 0.02).action == .quiet) }
    @Test func highRiskInterrupts() { #expect(p.decide(probability: 0.9).action == .interrupt) }

    @Test func blockOnlyWithStakes() {
        #expect(p.decide(probability: 0.99).action != .blockAndAlert)
        #expect(p.decide(probability: 0.95, context: .init(paymentEntryVisible: true)).action == .blockAndAlert)
    }

    @Test func stakesLowerThreshold() {
        let plain = p.threshold(for: .interrupt)!
        let pay = p.threshold(for: .interrupt, context: .init(paymentEntryVisible: true))!
        #expect(pay < plain)
    }

    @Test func thresholdsAreConservative() {
        let nudge = p.threshold(for: .nudge)!, interrupt = p.threshold(for: .interrupt)!
        #expect(nudge > 0.25 && nudge < 0.4)
        #expect(interrupt > 0.5 && interrupt < 0.65)
    }

    @Test func hardRuleFloor() {
        #expect(p.decide(probability: 0.01, context: .init(hardRuleMinimum: .interrupt)).action == .interrupt)
    }
}

@Suite struct HardRuleTests {
    @Test func techSupportRule() {
        let r = HardRules.evaluate(ScamSignals.analyze(SignalTests().techSupport), text: "")
        #expect(r.contains { $0.id == "tech-support-phone" })
    }

    @Test func giftCardGov() {
        let ctx = ScreenContext(text: "IRS final notice: you owe $1,500. To avoid arrest, pay today with Target gift cards and read the codes to the officer.")
        let r = HardRules.evaluate(ScamSignals.analyze(ctx), text: ctx.text)
        #expect(r.contains { $0.id == "gift-card-payment" })
    }

    @Test func newsArticleSuppressed() {
        let ctx = ScreenContext(
            text: "How to spot a gift card scam. According to the FTC, scammers pretending to be the IRS demand payment with gift cards and threaten arrest. Protect yourself: never pay with gift cards. Report fraud at reportfraud.ftc.gov.",
            url: "https://www.nytimes.com/2026/scams"
        )
        let r = HardRules.evaluate(ScamSignals.analyze(ctx), text: ctx.text)
        #expect(r.isEmpty)
    }
}

@Suite struct PointTagTests {
    @Test func parsesSteps() {
        let s = "[STEP:1] Click the paperclip. [POINT:412,88:paperclip]\n[STEP:2] Pick your file. [POINT:none]"
        let steps = PointTags.steps(in: s)
        #expect(steps.count == 2)
        #expect(steps[0].point == PointTags.Point(x: 412, y: 88, label: "paperclip"))
        #expect(steps[0].text == "Click the paperclip.")
        #expect(steps[1].point == nil)
    }

    @Test func pointsWithoutSteps() {
        let steps = PointTags.steps(in: "Click Send. [POINT:10,20:send] Then wait. [POINT:30,40]")
        #expect(steps.count == 2)
        #expect(steps[1].point?.x == 30)
        #expect(steps[1].point?.label == nil)
    }

    @Test func stripAndPartial() {
        #expect(PointTags.strip("Hi there [POINT:1,2:x].") == "Hi there.")
        #expect(PointTags.stripTrailingPartialTag("Click it [POIN") == "Click it ")
        #expect(PointTags.stripTrailingPartialTag("Price [is] fine") == "Price [is] fine")
    }
}

@Suite struct SecretsTests {
    @Test func parse() {
        let v = Secrets.parse("# c\nexport ANTHROPIC_API_KEY=\"sk-test\"\nTWILIO_FROM='+15555550100'\nBAD LINE\n")
        #expect(v["ANTHROPIC_API_KEY"] == "sk-test")
        #expect(v["TWILIO_FROM"] == "+15555550100")
        #expect(v.count == 2)
    }
}

@Suite struct VerdictTests {
    @Test func parseVerdict() throws {
        let raw = #"{"is_scam":true,"confidence":0.93,"scam_type":"tech_support","explanation":"x","what_to_do":"y","family_summary":"z","point_x":640,"point_y":400,"point_label":"phone"}"#
        let v = try ScamVerdict.parse(raw)
        #expect(v.isScam && v.point?.x == 640)
    }

    @Test func requestBody() throws {
        let c = ClaudeClient(apiKey: "k", model: "claude-sonnet-5-5")
        let b = c.body(system: "s", text: "t", image: nil, maxTokens: 10, effort: "low", schema: Prompts.scamSchema, stream: false)
        #expect(b["model"] as? String == "claude-sonnet-5-5")
        #expect(b["temperature"] == nil)
        let oc = b["output_config"] as? [String: Any]
        #expect(oc?["effort"] as? String == "low")
        #expect(JSONSerialization.isValidJSONObject(b))
    }
}

@Suite struct PipelineTests {
    @Test func techSupportInterrupts() {
        let r = ScamPipeline().evaluate(SignalTests().techSupport)
        #expect(r.action >= .interrupt)
        #expect(r.target == .phone)
        #expect(r.spoken.contains("phone number"))
    }

    @Test func benignQuiet() {
        let r = ScamPipeline().evaluate(ScreenContext(text: "Chicken soup recipe. Ingredients: 1 chicken, 2 carrots. Simmer for 2 hours.", url: "https://www.allrecipes.com/soup"))
        #expect(r.action == .quiet)
    }

    @Test func medicareLetterQuiet() {
        let r = ScamPipeline().evaluate(ScreenContext(
            text: "Medicare Summary Notice for Part B. THIS IS NOT A BILL. You may be billed $23.40. Questions? Call 1-800-555-0123.",
            appName: "Preview"
        ))
        #expect(r.action <= .nudge)
    }
}
