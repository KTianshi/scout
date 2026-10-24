import AppKit
import LookoutCore
import Carbon.HIToolbox

/// The brain of the app: ties observation, detection, Claude, voice and the buddy together.
@MainActor
final class Companion {
    let overlay = Overlay()
    let speech: SpeechOutput = CartesiaSpeech()
    let observer = ScreenObserver()
    let claude = ClaudeClient()
    let family = FamilyClient()
    let pipeline = ScamPipeline()
    let card = ActionCard()
    let payPause = PayPauseScreen()
    let setup = SetupWindow()
    let listener = Listener()
    lazy var demoBrowser = DemoBrowser(visible: true)

    var guardianEnabled = true
    private var guardianTask: Task<Void, Never>?
    /// A help answer or alert is playing. While busy, Esc stops everything.
    private var busy = false {
        didSet { if busy != oldValue { updateEscapeKey() } }
    }
    /// The help / explain request in progress, so Esc or a new question can cancel it.
    private var activeTask: Task<Void, Never>?
    /// Bumped on every stop; long-running loops check it and bail out.
    private(set) var generation = 0
    private var listening = false
    private var lastAlertKey: String?
    private var lastAlertAt = Date.distantPast
    private var lastNudgeFingerprint: Int?
    private var lastConfirmedFingerprint: Int?
    private var confirmInFlight = false
    private var pausedApprovalFor: Int?
    private var knownRemoteApps: Set<pid_t> = []
    private var dismissedRemoteApps: Set<pid_t> = []
    private var stuck = StuckDetector()

    // MARK: Start

    func start() {
        overlay.show()
        overlay.onTap = { AppDelegate.shared?.askTyped() }
        registerTalkShortcut()
        demoBrowser.onClose = { [weak self] in self?.stopEverything() }
        startGuardian()
        startRemoteShield()
        stuck.start { [weak self] in self?.offerHelpBecauseStuck() }
        if let c = speech as? CartesiaSpeech, c.client.isConfigured {
            Task { let n = await c.client.prewarm(CartesiaSpeech.standardLines()); Log.info("cartesia: prewarmed \(n) lines") }
        }
        Log.info("Lookout started. voice=\(speech.engineName) model=\(claude.model) key=\(claude.isConfigured ? "yes" : "no") screen=\(Permissions.screenRecording) ax=\(Permissions.accessibility) mic=\(Listener.canUseMicrophone)")
        Task { await greet() }
    }

    func greet() async {
        let firstRun = !UserDefaults.standard.bool(forKey: "onboarded") || ProcessInfo.processInfo.environment["LOOKOUT_ONBOARD"] == "1"
        if firstRun && !demoBrowser.window.isVisible {
            UserDefaults.standard.set(true, forKey: "onboarded")
            await onboard()
            return
        }
        overlay.setMood(.happy)
        let missing = (!Permissions.screenRecording || !Permissions.accessibility) && !demoBrowser.window.isVisible
        let hello = missing
            ? "Hi, I'm Lookout. I need a couple of permissions before I can see your screen. I've opened a window to help."
            : "Hi, I'm Lookout. Hold \(TalkShortcut.current.spoken) any time to ask me something."
        overlay.say(hello)
        if missing && !demoBrowser.window.isVisible { setup.show() }
        await speech.speak(hello)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if !busy { overlay.reset() }
    }

    /// First launch: a short, warm introduction, then permissions.
    func onboard() async {
        busy = true
        defer { busy = false }
        let screen = overlay.screen.frame
        overlay.moveTo(CGPoint(x: screen.width / 2 - 200, y: screen.height / 2 - 120))
        let lines: [(String?, String)] = [
            ("Hello!", "Hi, I'm Lookout. I'll stay here in the corner of your screen."),
            ("I can help", "If you get stuck, hold \(TalkShortcut.current.spoken) and just ask me. I'll point to the right spot."),
            ("I watch out for you", "If something looks like a scam, I'll stop you gently and explain. And I'll let \(LookoutConfig.familyName) know."),
            ("One last thing", "I need your OK to see the screen. I'll open a window that shows you how."),
        ]
        for (title, text) in lines {
            overlay.setMood(.speaking)
            overlay.say(text, title: title)
            DebugShot.take("onboard-\(title ?? "")")
            await speech.speak(text)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        overlay.setMood(.happy)
        if !Permissions.screenRecording || !Permissions.accessibility || !Listener.micAuthorized { setup.show() }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        overlay.reset()
    }

    // MARK: Shortcuts and stopping

    @discardableResult
    func registerTalkShortcut() -> Bool {
        let sc = TalkShortcut.current
        let ok = HotKeys.shared.register(id: HotKeys.talkID, keyCode: sc.keyCode, modifiers: sc.modifiers,
                                         onPress: { [weak self] in self?.beginListening() },
                                         onRelease: { [weak self] in self?.endListening() })
        Log.info("push-to-talk \(sc.symbol) registered: \(ok)")
        return ok
    }

    /// Esc is only grabbed while Lookout is talking or pointing, so it never steals Esc from other apps otherwise.
    func updateEscapeKey() {
        if busy {
            HotKeys.shared.register(id: HotKeys.escapeID, keyCode: UInt32(kVK_Escape), modifiers: 0,
                                    onPress: { [weak self] in Log.info("user: Esc"); self?.stopEverything() })
        } else {
            HotKeys.shared.unregister(id: HotKeys.escapeID)
        }
    }

    /// Silence Lookout immediately: cancel the current answer, stop speaking, put the buddy back.
    func stopEverything() {
        generation += 1
        activeTask?.cancel()
        activeTask = nil
        speech.stop()
        card.hide()
        overlay.reset()
        busy = false
    }

    /// Run a help / explain request, replacing any request already in progress.
    func runRequest(_ work: @escaping @MainActor () async -> Void) {
        stopEverything()
        activeTask = Task { await work() }
    }

    func ask(_ q: String) { runRequest { [weak self] in await self?.handleUtterance(q) } }
    func explain() { runRequest { [weak self] in await self?.explainScreen() } }

    // MARK: Snapshots

    /// The demo browser counts as "the screen" when it is open and in front.
    var demoInFront: Bool {
        // In demo mode the demo browser is "the screen" whenever it is visible and not hidden behind other apps.
        demoBrowser.window.isVisible && !demoBrowser.window.isMiniaturized
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
    }

    func snapshot(includeImage: Bool) async -> Snapshot {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        if demoInFront, let s = await demoBrowser.snapshot(runningApps: running, includeImage: includeImage, mapToScreen: true) {
            return s
        }
        return await observer.snapshot(includeImage: includeImage)
    }

    func overlayPoint(fromScreenTopLeft p: CGPoint) -> CGPoint { overlay.fromTopLeftGlobal(p) }
    var buddyScreenPoint: CGPoint { CGPoint(x: overlay.state.position.x + overlay.screen.frame.minX, y: 0) }
    func overlayRect(fromScreenTopLeft r: CGRect) -> CGRect {
        let o = overlay.fromTopLeftGlobal(r.origin)
        return CGRect(origin: o, size: r.size)
    }

    // MARK: Voice input

    func beginListening() {
        guard !listening else { return }
        speech.stop()
        guard Listener.canUseMicrophone else {
            overlay.say("I can't hear yet. Click the Lookout menu at the top and choose “Ask Lookout…” to type instead.")
            return
        }
        Task {
            if !(Listener.micAuthorized && Listener.speechAuthorized) {
                guard await Listener.requestPermissions() else {
                    overlay.say("I need permission to use the microphone. I've opened the setup window.")
                    setup.show(); return
                }
            }
            do {
                listening = true
                overlay.isPinned = false
                overlay.setMood(.listening)
                overlay.say("I'm listening…")
                listener.onPartial = { [weak self] t in self?.overlay.say(t, title: "You said") }
                listener.onLevel = { [weak self] l in self?.overlay.state.listeningLevel = l }
                try listener.start()
            } catch {
                listening = false
                overlay.say("Sorry, the microphone didn't start.")
                Log.info("listener start failed: \(error)")
            }
        }
    }

    func endListening() {
        guard listening else { return }
        listening = false
        Task {
            let text = await listener.stop()
            overlay.state.listeningLevel = 0
            let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { overlay.say("I didn't catch that. Hold \(TalkShortcut.current.spoken) and try again."); overlay.setMood(.idle); return }
            ask(q)
        }
    }

    func handleUtterance(_ q: String) async {
        let lower = q.lowercased()
        if lower.hasPrefix("type ") || lower.hasPrefix("write ") {
            let text = String(q.drop(while: { $0 != " " }).dropFirst())
            await dictate(text)
        } else if lower.contains("explain") && (lower.contains("letter") || lower.contains("this") || lower.contains("document") || lower.contains("mean")) || lower.contains("what does this") {
            await explainScreen(question: q)
        } else {
            await help(question: q)
        }
    }

    // MARK: Help mode

    func help(question: String) async {
        busy = true
        defer { busy = false }
        speech.stop()
        card.hide()
        overlay.setMood(.thinking)
        overlay.say("Let me look…", title: question)
        let snap = await snapshot(includeImage: true)
        guard claude.isConfigured else {
            await offlineHelp(question: question, snap: snap)
            return
        }
        let w = snap.image?.width ?? 0, h = snap.image?.height ?? 0
        let prompt = helpUserText(question: question, snap: snap)
        let player = StepPlayer(companion: self, snap: snap)
        var buffer = ""
        var consumed = 0
        do {
            for try await delta in claude.stream(system: Prompts.help(imageWidth: w, imageHeight: h), text: prompt, image: snap.image, maxTokens: 1500, effort: "medium") {
                buffer += delta
                // Hand complete steps to the player as they arrive.
                let steps = PointTags.steps(in: buffer)
                let complete = buffer.range(of: "[STEP:", options: .backwards).map { _ in max(0, steps.count - 1) } ?? 0
                while consumed < complete { player.enqueue(steps[consumed]); consumed += 1 }
            }
            let steps = PointTags.steps(in: buffer)
            while consumed < steps.count { player.enqueue(steps[consumed]); consumed += 1 }
            Log.info("help answer: \(PointTags.strip(buffer).prefix(400))")
            await player.finish()
            if Task.isCancelled { return }
            await family.send(.init(type: "help", title: "Helped with: \(question.prefix(80))", explanation: PointTags.strip(buffer).prefix(300).description, app: snap.context.appName))
        } catch {
            if Task.isCancelled { return }
            Log.info("help failed: \(error.localizedDescription)")
            overlay.setMood(.idle)
            let msg = "Sorry, I couldn't reach my helper just now. Please try again in a moment."
            overlay.say(msg)
            await speech.speak(msg)
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if Task.isCancelled { return }
        overlay.reset()
    }

    func helpUserText(question: String, snap: Snapshot) -> String {
        var s = "Question: \(question)\n"
        if let a = snap.context.appName { s += "Front app: \(a)\n" }
        if let t = snap.context.windowTitle { s += "Window: \(t)\n" }
        if let u = snap.context.url { s += "Address: \(u)\n" }
        let inv = snap.imageToScreen.inverted()
        let els = snap.elements.prefix(120).compactMap { e -> String? in
            let c = CGPoint(x: e.frame.midX, y: e.frame.midY).applying(inv)
            guard c.x >= 0, c.y >= 0, e.label.count < 120 else { return nil }
            return "- \(e.role) \"\(e.label.replacingOccurrences(of: "\n", with: " "))\" at \(Int(c.x)),\(Int(c.y))"
        }
        if !els.isEmpty { s += "On-screen controls (center pixel in the screenshot):\n" + els.joined(separator: "\n") + "\n" }
        if snap.image == nil { s += "No screenshot is available. Use the controls list and text below.\nScreen text:\n\(snap.context.text.prefix(3000))\n" }
        return s
    }

    /// Without an API key, do something useful in the demo: point at the page's marked target.
    func offlineHelp(question: String, snap: Snapshot) async {
        if let (name, r) = snap.knownTargetRects.first {
            let p = overlayPoint(fromScreenTopLeft: CGPoint(x: r.midX, y: r.midY))
            overlay.fly(to: p, highlight: overlayRect(fromScreenTopLeft: r))
            let msg = name == "attach"
                ? "Click the little paperclip here. Then pick your PDF and click Choose File."
                : "Start here. Click this one."
            overlay.setMood(.speaking); overlay.say(msg)
            await speech.speak(msg)
        } else {
            let msg = "I need my internet helper for that, and it isn't set up yet. Ask your family to add the key."
            overlay.say(msg); await speech.speak(msg)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        overlay.reset()
    }

    /// Plays help steps one at a time: fly, show, speak.
    final class StepPlayer {
        unowned let companion: Companion
        let snap: Snapshot
        private var queue: [PointTags.Step] = []
        private var task: Task<Void, Never>?
        private var waiting: CheckedContinuation<Void, Never>?
        private var done = false

        let generation: Int
        @MainActor init(companion: Companion, snap: Snapshot) { self.companion = companion; self.snap = snap; self.generation = companion.generation }

        @MainActor func enqueue(_ s: PointTags.Step) {
            queue.append(s)
            companion.speech.prepare(s.text)
            if task == nil { task = Task { @MainActor in await self.run() } }
            waiting?.resume(); waiting = nil
        }

        @MainActor func finish() async {
            done = true
            waiting?.resume(); waiting = nil
            if task == nil { task = Task { @MainActor in await self.run() } }
            await task?.value
        }

        @MainActor private func run() async {
            let c = companion
            while true {
                if c.generation != generation { return }
                if queue.isEmpty {
                    if done { break }
                    await withCheckedContinuation { waiting = $0 }
                    continue
                }
                let step = queue.removeFirst()
                if let p = step.point {
                    let screenPt = snap.screenPoint(forImagePoint: CGPoint(x: p.x, y: p.y))
                    let (snapped, el) = snap.snap(screenPt)
                    let hl = el.map { c.overlayRect(fromScreenTopLeft: $0.frame) }
                    c.overlay.fly(to: c.overlayPoint(fromScreenTopLeft: snapped), highlight: hl)
                    Log.info("point step \(step.index): img(\(Int(p.x)),\(Int(p.y))) → screen(\(Int(snapped.x)),\(Int(snapped.y))) label=\(p.label ?? "-") snapped=\(el?.label.prefix(30) ?? "no")")
                } else {
                    c.overlay.release()
                }
                c.overlay.setMood(.speaking)
                c.overlay.say(step.text, title: step.index > 0 ? "Step \(step.index)" : nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { DebugShot.take("help-step\(step.index)") }
                await c.speech.speak(step.text)
                if c.generation != generation { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            c.overlay.setMood(.happy)
        }
    }

    // MARK: Explain this letter

    func explainScreen(question: String = "What does this letter mean?") async {
        busy = true
        defer { busy = false }
        speech.stop()
        overlay.setMood(.thinking)
        overlay.say("Let me read it…", title: "Explaining")
        let snap = await snapshot(includeImage: true)
        guard claude.isConfigured else {
            let msg = "I need my internet helper to read letters, and it isn't set up yet."
            overlay.say(msg); await speech.speak(msg); overlay.reset(); return
        }
        var text = "Question: \(question)\nScreen text:\n\(snap.context.text.prefix(8000))"
        if let a = snap.context.appName { text = "Front app: \(a)\n" + text }
        do {
            var buffer = "", spokenUpTo = buffer.startIndex
            overlay.setMood(.speaking)
            for try await delta in claude.stream(system: Prompts.explainDocument, text: text, image: snap.image, maxTokens: 900, effort: "low") {
                buffer += delta
                // Speak sentence by sentence as they complete.
                if Task.isCancelled { return }
                while let end = Companion.sentenceEnd(in: buffer, from: spokenUpTo) {
                    let sentence = String(buffer[spokenUpTo..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    spokenUpTo = end
                    if !sentence.isEmpty { overlay.say(sentence, title: "About this letter"); await speech.speak(sentence) }
                }
            }
            if Task.isCancelled { return }
            let rest = String(buffer[spokenUpTo...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { overlay.say(rest); await speech.speak(rest) }
            await family.send(.init(type: "help", title: "Explained a letter", explanation: String(buffer.prefix(400)), app: snap.context.appName))
        } catch {
            if Task.isCancelled { return }
            let msg = "Sorry, I couldn't read it just now."
            overlay.say(msg); await speech.speak(msg)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        overlay.reset()
    }

    /// End of the next complete sentence: . ! ? followed by whitespace (so "$48.36" and "Dr." mid-stream don't split).
    static func sentenceEnd(in s: String, from start: String.Index) -> String.Index? {
        var i = start
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            if ".!?".contains(c), next < s.endIndex, s[next].isWhitespace {
                let abbrev = ["Dr", "Mr", "Mrs", "Ms", "St"].contains { s[start..<i].hasSuffix($0) }
                if !(c == "." && abbrev) { return next }
            }
            i = next
        }
        return nil
    }

    // MARK: Dictation

    func dictate(_ text: String) async {
        guard Permissions.accessibility, let app = NSWorkspace.shared.frontmostApplication else {
            overlay.say("I need the “Read buttons and text” permission to type for you."); return
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else {
            overlay.say("Click in the box where you want the words first, then ask again."); return
        }
        let ok = AXUIElementSetAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, text as CFString) == .success
        let msg = ok ? "Done. I typed it for you." : "Sorry, I couldn't type in that box."
        overlay.say(msg); await speech.speak(msg)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        overlay.reset()
    }

    // MARK: Guardian

    func startGuardian() {
        guardianTask?.cancel()
        guardianTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LookoutConfig.guardianInterval * 1e9))
                guard let self else { return }
                if self.guardianEnabled { await self.guardianPass() }
            }
        }
    }

    func guardianPass() async {
        guard !listening, !payPause.isShowing else { return }
        let snap = await snapshot(includeImage: false)
        if snap.isFixture && snap.context.text.isEmpty { return }
        guard !snap.context.text.isEmpty || !snap.context.runningApps.isEmpty else { return }
        stuck.observe(fingerprint: snap.context.fingerprint, window: (snap.context.appName ?? "") + (snap.context.windowTitle ?? ""))
        var result = pipeline.evaluate(snap.context)
        if result.probability > 0.05 { Log.info("guardian: \(result.summary)") }
        guard result.action > .quiet else { return }

        let fp = snap.context.fingerprint
        var verdict: ScamVerdict?
        var full = snap
        if result.shouldConfirmWithModel, claude.isConfigured, fp != lastConfirmedFingerprint, !confirmInFlight {
            confirmInFlight = true
            lastConfirmedFingerprint = fp
            overlay.setMood(.thinking)
            full = await snapshot(includeImage: true)
            do {
                let v = try await claude.confirmScam(screen: full.context, image: full.image, heuristicSummary: result.summary)
                verdict = v
                result = pipeline.applyModelVerdict(v, ctx: full.context)
                Log.info("claude verdict: scam=\(v.isScam) conf=\(v.confidence) type=\(v.scamType) why=\(v.explanation.prefix(160)) → \(result.summary)")
            } catch {
                Log.info("claude confirm failed, using heuristics: \(error.localizedDescription)")
            }
            confirmInFlight = false
            if !busy { overlay.setMood(.idle) }
        }
        await act(on: result, verdict: verdict, snap: full)
    }

    func act(on r: ScamPipeline.Result, verdict: ScamVerdict?, snap: Snapshot) async {
        // One alert per page (URL, or app + window) per 90 seconds, however the evidence shifts.
        let key = snap.context.url ?? "\(snap.context.appName ?? "")|\(snap.context.windowTitle ?? "")"
        switch r.action {
        case .quiet:
            return
        case .nudge:
            let fp = snap.context.fingerprint
            guard !busy, lastNudgeFingerprint != fp else { return }
            lastNudgeFingerprint = fp
            overlay.say("Hmm. Take your time here. If anyone is rushing you, that's a warning sign.", title: "Just checking")
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, !self.busy else { return }
                self.overlay.say(nil)
            }
        case .interrupt, .blockAndAlert:
            if key == lastAlertKey, Date().timeIntervalSince(lastAlertAt) < 90 { return }
            lastAlertKey = key
            lastAlertAt = Date()
            let paymentRisk = !snap.context.sensitiveFields.isEmpty && r.probability >= 0.3
            if r.action == .blockAndAlert || paymentRisk, !snap.context.sensitiveFields.isEmpty {
                await pauseBeforePay(r, snap: snap)
            } else {
                await interrupt(r, verdict: verdict, snap: snap)
            }
        }
    }

    /// Where to point for this threat, in overlay coordinates.
    func threatPoint(_ r: ScamPipeline.Result, verdict: ScamVerdict?, snap: Snapshot) -> (CGPoint, CGRect?)? {
        if let rect = snap.knownThreatRects[r.target.rawValue] ?? snap.knownThreatRects.values.first {
            return (overlayPoint(fromScreenTopLeft: CGPoint(x: rect.midX, y: rect.midY)), overlayRect(fromScreenTopLeft: rect))
        }
        if let ev = r.targetEvidence {
            let needle = ev.components(separatedBy: " … ").first ?? ev
            if let el = snap.element(matching: needle) {
                return (overlayPoint(fromScreenTopLeft: CGPoint(x: el.frame.midX, y: el.frame.midY)), overlayRect(fromScreenTopLeft: el.frame))
            }
        }
        if let p = verdict?.point {
            let s = snap.screenPoint(forImagePoint: CGPoint(x: p.x, y: p.y))
            let (snapped, el) = snap.snap(s)
            return (overlayPoint(fromScreenTopLeft: snapped), el.map { overlayRect(fromScreenTopLeft: $0.frame) })
        }
        return nil
    }

    func interrupt(_ r: ScamPipeline.Result, verdict: ScamVerdict?, snap: Snapshot) async {
        busy = true
        defer { busy = false }
        speech.stop()
        overlay.setMood(.alarmed)
        if let (p, rect) = threatPoint(r, verdict: verdict, snap: snap) { overlay.fly(to: p, highlight: rect) }
        let spoken = r.spoken.isEmpty ? "This looks like a scam. Let's stop here." : r.spoken
        overlay.say(spoken, title: "Wait — this looks like a scam")
        let canClose = demoInFront || NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.contains("Safari") == true || NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.contains("chrome") == true
        card.show(title: "Let's be careful", message: "You're safe. Nothing has happened yet. \(LookoutConfig.familyName) has been told.", alarmed: true, buttons: [
            .init(title: canClose ? "Close it for me" : "Got it", primary: true) { [weak self] in Log.info("user: close it"); self?.closeThreat() },
            .init(title: "I'm OK, thanks", primary: false) { [weak self] in Log.info("user: I'm OK"); self?.overlay.reset() },
        ], near: buddyScreenPoint)
        Task {
            let thumb = snap.image.flatMap { ImageUtil.thumbnailDataURL($0.data) }
            await family.send(.init(type: "scam_alert",
                                    title: Companion.alertTitle(verdict: verdict, rule: r.rules.first),
                                    explanation: verdict?.familySummary.isEmpty == false ? verdict!.familySummary : r.explanation,
                                    risk: r.probability, url: snap.context.url, app: snap.context.appName, screenshot: thumb,
                                    action: "Lookout interrupted and explained the warning signs"))
        }
        DebugShot.take("interrupt")
        await speech.speak(spoken)
    }

    static func alertTitle(verdict: ScamVerdict?, rule: HardRule?) -> String {
        let names: [String: String] = [
            "tech_support": "Fake tech-support pop-up", "government": "Fake government demand", "family_emergency": "Fake family emergency",
            "phishing": "Fake sign-in page", "refund_remote_access": "Refund + remote-access scam", "crypto_investment": "Crypto investment scam",
            "romance": "Romance money request", "prize": "Fake prize", "delivery_fee": "Fake delivery fee", "utility": "Fake utility shut-off",
            "charity": "Fake charity appeal", "invoice": "Fake invoice", "medicare": "Medicare scam",
            "tech-support-phone": "Fake tech-support pop-up", "gift-card-payment": "Gift card payment demand", "secrecy-money": "Secret money request",
            "remote-access-stranger": "Remote-access scam", "remote-access-with-money": "Remote access during payment", "crypto-atm": "Crypto ATM scam",
            "lookalike-login": "Fake sign-in page", "government-threat": "Fake government threat",
        ]
        if let v = verdict, v.isScam, let n = names[v.scamType] { return "Stopped: \(n)" }
        if let r = rule, let n = names[r.id] { return "Stopped: \(n)" }
        return "Possible scam on \(LookoutConfig.elderName)'s screen"
    }

    func closeThreat() {
        pipeline.engine.reset()
        if demoInFront || demoBrowser.window.isVisible {
            Task {
                await demoBrowser.load(Companion.demoIndexURL())
            }
        } else if Permissions.accessibility {
            // Cmd+W in the browser.
            let src = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: true); down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: false); up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
        overlay.setMood(.happy)
        let msg = "There. It's gone. You did great."
        overlay.say(msg)
        Task { await speech.speak(msg); try? await Task.sleep(nanoseconds: 1_500_000_000); overlay.reset() }
    }

    // MARK: Pause before you pay

    func pauseBeforePay(_ r: ScamPipeline.Result, snap: Snapshot) async {
        let fp = snap.context.url?.hashValue ?? snap.context.fingerprint
        guard pausedApprovalFor != fp else { return }
        pausedApprovalFor = fp
        speech.stop()
        card.hide()
        overlay.setMood(.alarmed)
        let field = snap.context.sensitiveFields.first ?? "payment"
        let what: String = ["gift-card": "gift card codes", "ssn": "your Social Security number", "password": "your password", "bank": "your bank details"][field] ?? "your card details"
        let reason = "This page is asking for \(what), and something about it doesn't look right."
        payPause.show(familyName: LookoutConfig.familyName, reason: reason, onCancel: { [weak self] in
            guard let self else { return }
            if self.demoBrowser.window.isVisible { Task { await self.demoBrowser.load(Companion.demoIndexURL()) } }
            self.overlay.setMood(.happy)
            Task { await self.speech.speak("Good choice. Nothing was sent.") ; self.overlay.reset() }
        }, onOverride: { [weak self] in
            self?.overlay.reset()
            Log.info("pay pause: user continued")
        })
        DebugShot.take("paypause")
        let spoken = "Let's pause for a moment. \(reason) I'm asking \(LookoutConfig.familyName) to take a look."
        Task { await speech.speak(spoken) }
        let thumb = snap.image.flatMap { ImageUtil.thumbnailDataURL($0.data) }
        let amount = Self.firstAmount(in: snap.context.text)
        let id = await family.requestApproval(title: "\(LookoutConfig.elderName) is about to enter \(what)", explanation: r.explanation.isEmpty ? reason : r.explanation, amount: amount, payee: snap.context.url.flatMap { Domains.host(of: $0) }, method: field == "gift-card" ? "gift card" : field, risk: r.probability, screenshot: thumb)
        guard let id else { payPause.model.status = .offline; return }
        // Poll until a family member decides.
        while payPause.isShowing {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let (status, note) = await family.approvalStatus(id)
            payPause.model.note = note
            switch status {
            case .approved:
                payPause.model.status = .approved
                DebugShot.take("paypause-approved")
                await speech.speak("\(LookoutConfig.familyName) says it's OK. You can go ahead.")
                return
            case .denied:
                payPause.model.status = .denied
                DebugShot.take("paypause-denied")
                await speech.speak("\(LookoutConfig.familyName) says please don't. This isn't safe. Nothing was sent.")
                return
            default: continue
            }
        }
    }

    static func firstAmount(in text: String) -> Double? {
        guard let r = text.range(of: #"\$\s?\d[\d,]*(\.\d{2})?"#, options: .regularExpression) else { return nil }
        return Double(text[r].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    // MARK: Remote access shield

    static let remoteAppNames = ["anydesk", "teamviewer", "screenconnect", "connectwise", "ultraviewer", "logmein", "supremo", "rustdesk", "splashtop", "remotepc", "zoho assist", "gotoassist", "aeroadmin", "ammyy"]

    func startRemoteShield() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.checkRemote(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                if self?.knownRemoteApps.remove(app.processIdentifier) != nil {
                    self?.pipeline.engine.forget([.remoteAccessAppRunning])
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications { checkRemote(app, quiet: true) }
    }

    static func isRemoteApp(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bid = (app.bundleIdentifier ?? "").lowercased()
        return remoteAppNames.contains { name.contains($0) || bid.contains($0.replacingOccurrences(of: " ", with: "")) }
    }

    func checkRemote(_ app: NSRunningApplication, quiet: Bool = false) {
        guard Self.isRemoteApp(app), !knownRemoteApps.contains(app.processIdentifier) else { return }
        knownRemoteApps.insert(app.processIdentifier)
        Log.info("remote shield: detected \(app.localizedName ?? "?") pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "-")")
        pipeline.engine.ingest([Signal(kind: .remoteAccessAppRunning, weight: 1.8, evidence: app.localizedName ?? "remote app", target: .remoteApp)])
        if quiet { return }
        Task { await warnRemote(app) }
    }

    func warnRemote(_ app: NSRunningApplication) async {
        busy = true
        defer { busy = false }
        let name = app.localizedName ?? "A remote control program"
        speech.stop()
        overlay.setMood(.alarmed)
        let msg = "\(name) just opened. It lets someone else control your computer. Did you start it yourself, with someone you know?"
        overlay.say(msg, title: "Someone may be connecting")
        card.show(title: "\(name) is running", message: "If a stranger asked you to open it, let's end it now.", alarmed: true, buttons: [
            .init(title: "End the session", primary: true) { [weak self] in self?.endRemoteSession(app) },
            .init(title: "It's my family", primary: false) { [weak self] in
                self?.dismissedRemoteApps.insert(app.processIdentifier)
                self?.overlay.reset()
            },
        ], near: buddyScreenPoint)
        await family.send(.init(type: "remote_access", title: "\(name) opened on \(LookoutConfig.elderName)'s Mac",
                                explanation: "A remote-control program started. Lookout asked whether it was expected.", risk: pipeline.engine.assess(currentScreen: []).probability, app: name, action: "Asked \(LookoutConfig.elderName) whether to end the session"))
        await speech.speak(msg)
    }

    func endRemoteSession(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "the program"
        // Test safety switch: only ever terminate Lookout's own dummy apps.
        if ProcessInfo.processInfo.environment["LOOKOUT_TERMINATE_ONLY_DEMO"] == "1", !(app.bundleIdentifier ?? "").hasPrefix("com.lookout.demo") {
            Log.info("remote shield: refusing to terminate non-demo app \(name) (LOOKOUT_TERMINATE_ONLY_DEMO)")
            return
        }
        Log.info("remote shield: terminating \(name) pid=\(app.processIdentifier) on user request")
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !app.isTerminated { app.forceTerminate() } }
        overlay.setMood(.happy)
        let msg = "I closed \(name). Nobody can control your computer now. If someone is on the phone, you can hang up."
        overlay.say(msg)
        Task {
            await family.send(.init(type: "remote_access", title: "\(name) session ended", explanation: "\(LookoutConfig.elderName) chose to end the remote-control session.", app: name, action: "Closed \(name)"))
            await speech.speak(msg)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            overlay.reset()
        }
    }

    // MARK: Stuck

    func offerHelpBecauseStuck() {
        guard !busy, !listening, !card.isShowing else { return }
        overlay.setMood(.happy)
        overlay.say("Want some help? Just hold \(TalkShortcut.current.spoken) and tell me what you're trying to do.", title: "Need a hand?")
        card.show(title: "Want some help?", message: "I can show you where to click.", alarmed: false, buttons: [
            .init(title: "Yes, please", primary: true) { [weak self] in
                guard let self else { return }
                if Listener.canUseMicrophone { self.overlay.say("Hold \(TalkShortcut.current.spoken), and tell me what you're trying to do.") }
                else { AppDelegate.shared?.askTyped() }
            },
            .init(title: "No thanks", primary: false) { [weak self] in self?.overlay.reset() },
        ])
        Task { await speech.speak("Want some help? I'm right here.") }
    }

    // MARK: Demo

    static func demoDirectory() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("demo")) }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("demo"))
        // Executable inside .build/<arch>/debug → repo root
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<6 { u.deleteLastPathComponent(); candidates.append(u.appendingPathComponent("demo")) }
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }

    static func demoIndexURL() -> URL {
        (demoDirectory() ?? URL(fileURLWithPath: "demo")).appendingPathComponent("index.html")
    }

    func openDemo(_ file: String? = nil) {
        let url = file.map { (Self.demoDirectory() ?? URL(fileURLWithPath: "demo")).appendingPathComponent("scenarios/\($0)") } ?? Self.demoIndexURL()
        demoBrowser.show()
        Task { await demoBrowser.load(url) }
        demoBrowser.onNavigate = { [weak self] _ in
            // New page: allow fresh alerts.
            self?.lastAlertKey = nil
            self?.pausedApprovalFor = nil
            self?.lastNudgeFingerprint = nil
        }
    }
}

/// "Seems stuck": same window, screen not changing, and repeated clicks for a while.
@MainActor
final class StuckDetector {
    private var clicks: [Date] = []
    private var sameSince = Date()
    private var lastWindow = ""
    private var lastFingerprint = 0
    private var lastOffer = Date.distantPast
    private var monitor: Any?
    private var onStuck: (() -> Void)?
    var window: TimeInterval = 40
    var minClicks = 6

    func start(onStuck: @escaping () -> Void) {
        self.onStuck = onStuck
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clicks.append(Date()) }
        }
    }

    func observe(fingerprint: Int, window w: String) {
        let now = Date()
        if w != lastWindow || fingerprint != lastFingerprint {
            lastWindow = w; lastFingerprint = fingerprint; sameSince = now
            clicks.removeAll()
            return
        }
        clicks.removeAll { now.timeIntervalSince($0) > window }
        if now.timeIntervalSince(sameSince) >= window, clicks.count >= minClicks, now.timeIntervalSince(lastOffer) > 180 {
            lastOffer = now
            clicks.removeAll()
            onStuck?()
        }
    }
}

/// LOOKOUT_DEBUG_SHOTS=1: saves an image of Lookout's own windows only (never other apps)
/// to ~/Library/Application Support/Lookout/shots/. Demo/debug only.
enum DebugShot {
    static var enabled: Bool { ProcessInfo.processInfo.environment["LOOKOUT_DEBUG_SHOTS"] == "1" }
    static func take(_ name: String) {
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Only Lookout's own windows (never other apps' content), composited over a plain background.
            // Front-to-back order from the window server, filtered to this process.
            let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let pid = Int(getpid())
            let mine = info.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }.compactMap { ($0[kCGWindowNumber as String] as? Int).map { CGWindowID($0) } }
            guard !mine.isEmpty else { return }
            var ptrs = mine.map { UnsafeRawPointer(bitPattern: UInt($0)) }
            guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
                  let img = CGImage(windowListFromArrayScreenBounds: CGDisplayBounds(CGMainDisplayID()), windowArray: arr, imageOption: .nominalResolution),
                  let data = ImageUtil.jpeg(img, quality: 0.7) else { return }
            let dir = Log.dir.appendingPathComponent("shots", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = dir.appendingPathComponent("\(name).jpg")
            try? data.write(to: f)
            Log.info("debug shot: \(f.path)")
        }
    }
}
