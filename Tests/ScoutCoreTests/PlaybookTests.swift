import Foundation
import Testing
@testable import ScoutCore

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func loadModel() throws -> PlaybookModel {
    try PlaybookModel.load(url: repoRoot.appendingPathComponent("model/playbooks.json"))
}

@Suite struct PlaybookParityTests {
    /// The Swift engine must reproduce the Python reference (scout_detect) to 1e-9 on every step.
    @Test func matchesPythonVectors() throws {
        let model = try loadModel()
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("model/parity_vectors.json"))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let seqs = root["sequences"] as! [String: [String: Any]]
        #expect(seqs.count >= 5)
        for (name, seq) in seqs {
            #expect(seq["states"] as? [String] == model.states, "state order differs for \(name)")
            let eng = PlaybookEngine(model: model)
            #expect(abs(eng.priorLogOdds - (seq["prior_log_odds"] as! Double)) < 1e-9)
            for step in seq["steps"] as! [[String: Any]] {
                let o = step["obs"] as! [String: Any]
                let events = Set((o["events"] as! [String]).compactMap(PlaybookEvent.init(rawValue:)))
                let s = eng.observe(PlaybookObservation(t: o["t"] as! Double, events: events, modelRan: o["model_ran"] as! Bool, crsChecked: o["crs_checked"] as? Bool ?? false, source: o["source"] as! String))
                #expect(abs(s.pScam - (step["p_scam"] as! Double)) < 1e-9, "\(name) p_scam")
                #expect(abs(s.logOdds - (step["log_odds"] as! Double)) < 1e-9, "\(name) log_odds")
                #expect(abs(s.logLikelihood - (step["log_likelihood"] as! Double)) < 1e-9, "\(name) loglik")
                let post = eng.posterior(), ref = step["posterior"] as! [Double]
                #expect(zip(post, ref).allSatisfy { abs($0 - $1) < 1e-9 }, "\(name) posterior")
                let ledger = step["ledger"] as! [[Any]]
                #expect(ledger.count == s.ledger.count, "\(name) ledger length")
                for (a, b) in zip(s.ledger, ledger) {
                    #expect(a.item == b[0] as! String)
                    #expect(abs(a.logBF - (b[1] as! Double)) < 1e-9, "\(name) ledger \(a.item)")
                }
                #expect(s.topType == step["top_type"] as? String)
                #expect(s.currentStage == step["current_stage"] as? String)
                #expect(s.nextStage == step["next_stage"] as? String)
            }
        }
    }

    @Test func ledgerSumsToLogOdds() throws {
        let eng = PlaybookEngine(model: try loadModel())
        eng.observe(.init(t: 0, events: [.REFUND_OVERPAYMENT, .PHONE_NUMBER_IN_POPUP]))
        eng.observe(.init(t: 100))
        eng.observe(.init(t: 200, events: [.REMOTE_ACCESS_STARTED]))
        let total = eng.priorLogOdds + eng.ledger.reduce(0) { $0 + $1.logBF }
        #expect(abs(total - eng.logOdds) < 1e-9)
    }
}

@Suite struct PlaybookEventMappingTests {
    @Test func techSupportPopup() {
        let ctx = ScreenContext(text: "Windows Defender: your computer has been infected. Do not close this window. Call Microsoft Support immediately at (888) 555-0142.",
                                url: "https://micros0ft-security-alert.com/alert")
        let ev = PlaybookEvents.extract(ctx)
        #expect(ev.isSuperset(of: [.INFECTED_CLAIM, .PHONE_NUMBER_IN_POPUP, .URGENT_LANGUAGE, .BRAND_IMPERSONATION, .LOOKALIKE_DOMAIN]))
    }

    @Test func remoteAppAndBank() {
        let ev = PlaybookEvents.extract(ScreenContext(text: "Account summary", url: "https://secure.chase.com/accounts", runningApps: ["Safari", "AnyDesk"]))
        #expect(ev.contains(.REMOTE_ACCESS_STARTED))
        #expect(ev.contains(.BANK_SITE_OPENED))
    }

    @Test func giftShoppingIsNotPaymentDemand() {
        let ev = PlaybookEvents.extract(ScreenContext(text: "ShopRiver gift cards. $50 birthday gift card. Add to cart. Your cart subtotal $50. Proceed to checkout",
                                                      url: "https://www.shopriver.com/gift-cards", sensitiveFields: ["card"]))
        #expect(ev.contains(.GIFT_CARD_PAGE))
        #expect(!ev.contains(.PAYMENT_DEMAND))
        #expect(!ev.contains(.SENSITIVE_FIELD_ON_UNKNOWN_SITE))
    }

    @Test func eventOrderMatchesModel() throws {
        let model = try loadModel()
        #expect(model.Q.first?.count == PlaybookEvent.allCases.count)
    }
}

@Suite struct SenderCheckTests {
    @Test func extractsSender() {
        #expect(SenderCheck.extractSender(ScreenContext(text: "x", url: "mailto:notice@irs-gov-payments.co")) == "notice@irs-gov-payments.co")
        #expect(SenderCheck.extractSender(ScreenContext(text: "Inbox\nFrom: IRS Department of Treasury <Notice@IRS-gov-payments.co>\nSubject: Final notice")) == "notice@irs-gov-payments.co")
        #expect(SenderCheck.extractSender(ScreenContext(text: "Call us or email help@example.com")) == nil)
    }

    @Test func onlyRealCRSAnswersCount() throws {
        let pipeline = ScamPipeline()
        let ctx = ScreenContext(text: "From: IRS <notice@irs-gov-payments.co>\nFINAL NOTICE. Respond immediately to avoid suspension.", url: "mailto:notice@irs-gov-payments.co")
        let high = SenderCheck(email: "notice@irs-gov-payments.co", verdict: .high, score: 100, firstSeen: "2026-10-24", newToday: true, sentence: "I checked who sent this.", source: "crs")
        let mock = SenderCheck(email: "notice@irs-gov-payments.co", verdict: .high, score: 100, firstSeen: nil, newToday: true, sentence: "x", source: "mock")
        let withCRS = ScamPipeline().applyChecks(verdict: nil, sender: high, ctx: ctx)
        let withMock = ScamPipeline().applyChecks(verdict: nil, sender: mock, ctx: ctx)
        let without = pipeline.commit(ctx)
        #expect((withCRS.playbook?.pScam ?? 0) > (without.playbook?.pScam ?? 0))
        #expect(abs((withMock.playbook?.pScam ?? 0) - (without.playbook?.pScam ?? 0)) < 1e-12)
        #expect(withCRS.spoken.contains("I checked who sent this."))
    }
}
