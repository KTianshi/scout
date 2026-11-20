import Foundation
import Testing
@testable import ScoutCore

@Suite struct ConnectivityTests {
    @Test func networkFailureCoolsDownThenRecovers() {
        let c = Connectivity()
        let t = Date()
        #expect(c.isUsable(.claude, now: t))
        #expect(c.reportFailure(.claude, error: URLError(.timedOut), now: t))
        #expect(!c.isUsable(.claude, now: t.addingTimeInterval(5)))
        #expect(c.isUsable(.cartesia, now: t.addingTimeInterval(5)))   // other services unaffected
        #expect(c.internetLooksBad(now: t.addingTimeInterval(5)))
        #expect(c.isUsable(.claude, now: t.addingTimeInterval(Connectivity.networkCooldown + 1)))
        #expect(!c.internetLooksBad(now: t.addingTimeInterval(Connectivity.networkCooldown + 1)))
    }

    @Test func nonNetworkErrorsDoNotCoolDown() {
        let c = Connectivity()
        #expect(!c.reportFailure(.claude, error: ClaudeClient.ClientError.refusal(nil)))
        #expect(!c.reportFailure(.claude, error: URLError(.cancelled)))
        #expect(c.isUsable(.claude))
    }

    @Test func outOfCreditsSitsOutLonger() {
        let c = Connectivity()
        let t = Date()
        c.reportStatus(.cartesia, code: 402, now: t)
        #expect(!c.isUsable(.cartesia, now: t.addingTimeInterval(Connectivity.networkCooldown + 1)))
        #expect(c.isUsable(.cartesia, now: t.addingTimeInterval(Connectivity.accountCooldown + 1)))
        c.reportStatus(.claude, code: 400)   // a bad request is our bug, not an outage
        #expect(c.isUsable(.claude))
        #expect(!c.internetLooksBad(now: t))   // credits ≠ no internet
    }

    @Test func pathDownBlocksAndComingBackClearsCooldowns() {
        let c = Connectivity()
        c.reportFailure(.claude, error: URLError(.notConnectedToInternet))
        c.setPath(ok: false)
        #expect(!c.isOnline && !c.isUsable(.cartesia) && c.internetLooksBad())
        c.setPath(ok: true)
        #expect(c.isUsable(.claude) && c.isUsable(.cartesia) && !c.internetLooksBad())
    }

    @Test func gatedClientsFailFastOffline() async throws {
        let gate = Connectivity()
        gate.setPath(ok: false)
        let claude = ClaudeClient(apiKey: "test-key")
        claude.gate = gate
        let t0 = Date()
        await #expect(throws: URLError.self) { try await claude.complete(system: "s", text: "t") }
        let tts = CartesiaClient(apiKey: "test-key", cacheDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        tts.gate = gate
        await #expect(throws: URLError.self) { try await tts.wav("Hello there") }
        #expect(Date().timeIntervalSince(t0) < 0.5)
    }

    @Test func deadlineGivesUpOnSlowCalls() async throws {
        let t0 = Date()
        await #expect(throws: DeadlineExceeded.self) {
            try await withDeadline(0.2) { try await Task.sleep(nanoseconds: 5_000_000_000); return 1 }
        }
        #expect(Date().timeIntervalSince(t0) < 1)
        #expect(Connectivity.isNetworkError(DeadlineExceeded(seconds: 1)))
        #expect(try await withDeadline(1) { 42 } == 42)
    }
}
