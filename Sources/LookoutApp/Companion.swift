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
    lazy var settings = SettingsWindow(companion: self)
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
    private var recentWarnings: [String: Date] = [:]
    private var dismissedWarnings: [String: Date] = [:]
    private var lastWarnedKey: String?
    /// They dismissed the warning: that page stays quiet for 30 minutes.
    func dismissWarning() { if let k = lastWarnedKey { dismissedWarnings[k] = Date() } }
    private var lastAlertAt = Date.distantPast
    /// Pages Claude confidently called safe, and when. The guardian stays quiet there for a while.
    private var clearedPages: [String: Date] = [:]
    private var scamPages: [String: Date] = [:]
    /// Developer tools are full of scam words (code, docs, chats about Scout itself) and aren't where our users get scammed.
    static let ignoredApps: Set<String> = ["Terminal", "iTerm2", "Xcode", "Code", "Visual Studio Code", "Cursor", "Warp", "Ghostty", "Claude"]
    private var lastConfirmedFingerprint: Int?
    private var stableFingerprint: Int?
    private var stableSince = Date()
    private var lastSweepAt = Date.distantPast
    private var confirmInFlight = false
    private var pausedApprovalFor: Int?
    private var knownRemoteApps: Set<pid_t> = []
    private var dismissedRemoteApps: Set<pid_t> = []
    private(set) var stuck = StuckDetector()

    // MARK: Start

    func start() {
        Companion.pipelineForTitle = pipeline
        overlay.show()
        overlay.onTap = { AppDelegate.shared?.askTyped() }
        registerTalkShortcut()
        watchAppSwitches()
        ActionWatcher.extraWindowKey = { [weak self] in
            guard let self, self.demoInFront else { return "" }
            return self.demoBrowser.web.url?.absoluteString ?? ""
        }
        startWakeWord()
        demoBrowser.onClose = { [weak self] in self?.stopEverything() }
        startGuardian()
        startRemoteShield()
        stuck.start { [weak self] in self?.offerHelpBecauseStuck() }
        if let c = speech as? CartesiaSpeech, c.client.isConfigured {
            Task { let n = await c.client.prewarm(CartesiaSpeech.standardLines()); Log.info("cartesia: prewarmed \(n) lines") }
        }
        Log.info("Scout started. voice=\(speech.engineName) model=\(claude.model) key=\(claude.isConfigured ? "yes" : "no") screen=\(Permissions.screenRecording) ax=\(Permissions.accessibility) mic=\(Listener.canUseMicrophone)")
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
            ? "Hi, I'm Scout. I need a couple of permissions before I can see your screen. I've opened a window to help."
            : "Hi, I'm Scout. Hold \(TalkShortcut.current.spoken) any time to ask me something."
        // With the setup window open, say it but don't draw a bubble over the window's button.
        if missing && !demoBrowser.window.isVisible { setup.show() } else { overlay.say(hello) }
        // Only speak up when something is needed (permissions). Every other launch is silent: a voice out of
        // nowhere after a restart is startling, especially for an older person.
        if missing { await speech.speak(hello) } else { try? await Task.sleep(nanoseconds: 3_000_000_000) }
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
            ("Hello!", overlay.followsCursor ? "Hi, I'm Scout. I'll stay close by, right next to your pointer."
                                             : "Hi, I'm Scout. I'll wait here in the corner. Click me any time."),
            ("I can help", "If you get stuck, hold \(TalkShortcut.current.spoken) and just ask me. I'll point to the right spot."),
            ("I watch out for you", "If something looks like a scam, I'll stop you gently and explain." + (LookoutConfig.familyEnabled ? " And I'll let \(LookoutConfig.familyName) know." : "")),
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

    /// Esc is only grabbed while Scout is talking or pointing, so it never steals Esc from other apps otherwise.
    func updateEscapeKey() {
        if busy {
            HotKeys.shared.register(id: HotKeys.escapeID, keyCode: UInt32(kVK_Escape), modifiers: 0,
                                    onPress: { [weak self] in Log.info("user: Esc"); self?.stopEverything() })
        } else {
            HotKeys.shared.unregister(id: HotKeys.escapeID)
        }
    }

    /// Silence Scout immediately: cancel the current answer, stop speaking, put the buddy back.
    func stopEverything() {
        generation += 1
        activeTask?.cancel()
        activeTask = nil
        speech.stop()
        card.hide()
        overlay.reset()
        busy = false
    }

    /// End the current help/explain request without touching the overlay (the caller takes it over).
    func cancelRequest() {
        generation += 1
        activeTask?.cancel()
        activeTask = nil
        guideWaiting = false
    }

    /// Run a help / explain request, replacing any request already in progress.
    func runRequest(_ work: @escaping @MainActor () async -> Void) {
        stopEverything()
        requestApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let gen = generation
        activeTask = Task { [weak self] in
            await work()
            // Finished: later app switches must not "stop" a request that's long over (and wipe an alert).
            if let self, self.generation == gen { self.activeTask = nil }
        }
    }

    /// The app the person was in when they asked. Switching to another app means they've moved on.
    private var requestApp: pid_t?

    func watchAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                guard let self, self.activeTask != nil, !self.guideWaiting, let pid, pid != getpid(), let asked = self.requestApp, pid != asked else { return }
                Log.info("user switched apps: stopping")
                self.stopEverything()
            }
        }
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

    /// `fast`: for help, where a quick answer beats reading every row of a huge list.
    func snapshot(includeImage: Bool, fast: Bool = false) async -> Snapshot {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        if demoInFront {
            // Demo mode never falls back to the live screen: if the page can't be read this instant, skip the pass.
            if let s = await demoBrowser.snapshot(runningApps: running, includeImage: includeImage, mapToScreen: true) { return s }
            var empty = Snapshot(context: ScreenContext(text: "", runningApps: running))
            empty.isFixture = true
            return empty
        }
        observer.displayID = overlay.displayID
        return await observer.snapshot(includeImage: includeImage, fast: fast)
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
        wake.stop()   // one microphone user at a time
        prepareForQuestion()
        // Talking over Scout interrupts it.
        stopEverything()
        guard Listener.canUseMicrophone else {
            overlay.say("I can't hear yet. Click the Scout menu at the top and choose “Ask Scout…” to type instead.")
            return
        }
        Task {
            if !(Listener.micAuthorized && Listener.speechAuthorized) {
                guard await Listener.requestPermissions() else {
                    overlay.say("I need permission to use the microphone. I've opened the setup window.")
                    setup.show(); return
                }
                // They let go of the keys while the permission dialog was up: don't start a mic nobody is holding.
                guard HotKeys.shared.isHeld(HotKeys.talkID) else {
                    overlay.say("Thanks! Now hold \(TalkShortcut.current.spoken) and ask me.")
                    return
                }
            }
            do {
                listening = true
                overlay.isPinned = false
                overlay.setMood(.listening)
                overlay.say("I'm listening…")
                listener.onPartial = { [weak self] t in self?.overlay.say(t, title: "You said") }
                listener.onLevel = { [weak self] l in self?.overlay.state.listeningLevel = l }
                listener.hints = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
                try listener.start()
            } catch {
                listening = false
                overlay.say("Sorry, the microphone didn't start.")
                Log.info("listener start failed: \(error)")
            }
        }
    }

    // MARK: "Hey Scout"

    let wake = WakeListener()

    /// Keeps the wake-word listener running only while it can't hear Scout itself or clash with push-to-talk.
    func startWakeWord() {
        wake.onWake = { [weak self] in
            guard let self else { return }
            self.stopEverything()
            self.prepareForQuestion()
            self.overlay.isPinned = false
            self.overlay.setMood(.listening)
            self.overlay.say("I'm listening…")
        }
        wake.onPartialQuestion = { [weak self] q in
            if !q.isEmpty { self?.overlay.say(q, title: "You said") }
        }
        wake.onQuestion = { [weak self] q in
            Log.info("wake word question: \(q.prefix(120))")
            self?.ask(q)
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                let shouldRun = WakeListener.enabled && !self.listening && (!self.busy || self.guideWaiting) && !self.speech.isSpeaking
                if shouldRun && !self.wake.isRunning { self.wake.start() }
                if !shouldRun && self.wake.isRunning { self.wake.stop() }
            }
        }
    }

    /// Started the moment someone begins asking (key press, wake word, Ask box): warm the connections and
    /// take the screenshot of what they're looking at while they're still talking.
    private var prefetched: (snap: Task<Snapshot, Never>, at: Date, app: pid_t?)?

    func prepareForQuestion() {
        claude.warmUp()
        (speech as? CartesiaSpeech)?.client.warmUp()
        let app = NSWorkspace.shared.frontmostApplication?.processIdentifier
        prefetched = (Task { await self.snapshot(includeImage: true, fast: true) }, Date(), app)
    }

    /// The screenshot taken when they started asking, if it still describes the screen they asked about.
    func takePrefetched() async -> Snapshot? {
        guard let p = prefetched else { return nil }
        prefetched = nil
        guard Date().timeIntervalSince(p.at) < 20, p.app == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return await p.snap.value
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

    /// Claude effort for a question's first answer (LOOKOUT_HELP_EFFORT overrides, for measuring).
    static var firstStepEffort: String { ProcessInfo.processInfo.environment["LOOKOUT_HELP_EFFORT"] ?? "medium" }
    static let allSet = "Perfect. You're all set."

    /// The guide's turn in `turns`, so its prompt shows the other turns as history.
    private var currentTurn: Int?

    /// Follow-along help: look, give one step, wait for the person to do it, look again.
    func help(question: String) async {
        let owner = generation
        busy = true
        defer { if generation == owner { busy = false } }
        speech.stop()
        card.hide()
        overlay.setMood(.thinking)
        overlay.say("Let me look…", title: question)
        guard claude.isConfigured else {
            await offlineHelp(question: question, snap: await snapshot(includeImage: true))
            return
        }
        let gen = generation
        let turn = beginTurn(question, app: NSWorkspace.shared.frontmostApplication?.localizedName)
        currentTurn = turn
        defer { if currentTurn == turn { currentTurn = nil } }
        defer { guideWaiting = false }
        var given: [String] = []
        var lastAction: ActionWatcher.Action?
        var early = await takePrefetched()
        var stepNo = 0, looks = 0
        while stepNo < 12 && looks < 20 {
            stepNo += 1; looks += 1
            let t0 = Date()
            let snap: Snapshot
            if let e = early { snap = e; early = nil } else { snap = await snapshot(includeImage: true, fast: true) }
            if Task.isCancelled || generation != gen { return }
            // If they click while Claude is still writing, that answer is about a screen that's gone: look again.
            let interrupter = stepNo > 1 ? ActionWatcher() : nil
            var superseded = false
            let tSnap = Date().timeIntervalSince(t0)
            let w = snap.image?.width ?? 0, h = snap.image?.height ?? 0
            // Stream: fly as soon as the point arrives, speak each sentence as it completes.
            let speaker = SentenceQueue(speech: speech) { [weak self] in self?.generation == gen }
            var watcher: ActionWatcher?
            var actedEarly = false   // they did the step while Scout was still explaining it
            var reply = "", spokenUpTo = 0, pointed = false
            var tFirst: TimeInterval?
            let title = "Step \(stepNo)"
            do {
                for try await delta in claude.stream(system: Prompts.guide(imageWidth: w, imageHeight: h),
                                                     text: guideUserText(question: question, snap: snap, given: given, action: lastAction),
                                                     image: snap.image, maxTokens: 600, effort: stepNo == 1 ? Self.firstStepEffort : "low") {
                    if Task.isCancelled || generation != gen { speaker.cancel(); interrupter?.stop(); watcher?.stop(); return }
                    if spokenUpTo == 0, interrupter?.sawClick == true { superseded = true; break }
                    if let w = watcher, w.ready() { actedEarly = true; break }
                    reply += delta
                    if tFirst == nil { tFirst = Date().timeIntervalSince(t0) }
                    let body = reply.replacingOccurrences(of: "[DONE]", with: "", options: .caseInsensitive)
                    if !pointed, let p = PointTags.steps(in: body).compactMap(\.point).first {
                        pointed = true
                        point(at: p, snap: snap)
                    }
                    let visible = PointTags.strip(PointTags.stripTrailingPartialTag(body))
                    guard !visible.isEmpty else { continue }
                    if watcher == nil { watcher = ActionWatcher(); interrupter?.stop(); guideWaiting = false }   // people often click as soon as they see where to go
                    overlay.setMood(.speaking)
                    overlay.say(visible, title: title)
                    let chars = Array(visible)
                    if spokenUpTo < chars.count, let end = Companion.sentenceEnd(in: visible, from: visible.index(visible.startIndex, offsetBy: spokenUpTo)) {
                        let n = visible.distance(from: visible.startIndex, to: end)
                        speaker.add(String(chars[spokenUpTo..<n]))
                        spokenUpTo = n
                    }
                }
            } catch {
                speaker.cancel(); watcher?.stop(); interrupter?.stop()
                if Task.isCancelled || generation != gen { return }
                Log.info("help failed: \(error.localizedDescription)")
                overlay.setMood(.idle)
                let msg = "Sorry, I couldn't reach my helper just now. Please try again in a moment."
                overlay.say(msg)
                await speech.speak(msg)
                return
            }
            interrupter?.stop()
            if Task.isCancelled || generation != gen { speaker.cancel(); watcher?.stop(); return }
            if superseded {
                speaker.cancel(); watcher?.stop()
                Log.info("guide: they acted while the step was being written; looking again")
                stepNo -= 1
                continue
            }
            let done = reply.range(of: "[DONE]", options: .caseInsensitive) != nil
            let body = reply.replacingOccurrences(of: "[DONE]", with: "", options: .caseInsensitive)
            let text = PointTags.strip(body)
            guard !text.isEmpty else { watcher?.stop(); break }
            let chars = Array(text)
            if spokenUpTo < chars.count { speaker.add(String(chars[spokenUpTo...])) }
            if !pointed { overlay.release() }
            // A one-shot answer ("What is Slack?") gets no "Step 1" title.
            if done && stepNo == 1 && !pointed { overlay.say(text, title: nil) } else { overlay.say(text, title: title) }
            Log.info(String(format: "guide step %d done=%@ (look %.1fs, first word %.1fs, full %.1fs): ", stepNo, done ? "true" : "false",
                            tSnap, tFirst ?? 0, Date().timeIntervalSince(t0)) + text.prefix(300))
            updateTurn(turn, step: text, finished: done)
            given.append(text)
            let w8 = watcher ?? ActionWatcher()
            // Finish talking, unless they do the step first: then stop mid-sentence and move on, so nobody waits
            // through a long explanation of something they've already done.
            if !actedEarly {
                var finishedTalking = false
                let talk = Task { @MainActor in await speaker.finish(); finishedTalking = true }
                while !finishedTalking && !Task.isCancelled && generation == gen {
                    if w8.ready() { actedEarly = true; break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if actedEarly { talk.cancel() }
            }
            if actedEarly {
                speaker.cancel()
                speech.stop()
                Log.info("guide: step done while still talking; moving on")
            }
            if Task.isCancelled || generation != gen { w8.stop(); return }
            if done && actedEarly {
                w8.stop()
                overlay.release()
                overlay.setMood(.happy)
                overlay.say(Self.allSet, title: nil)
                await speech.speak(Self.allSet)
                break
            }
            if done {
                // The last step still needs doing ("click Send"): wait for it, then close like a person would.
                if pointed, GuideMode.automatic {
                    overlay.setMood(.idle)
                    guideWaiting = true
                    let finished = await w8.wait(timeout: 60)
                    if Task.isCancelled || generation != gen { return }
                    if finished != nil {
                        overlay.release()
                        overlay.setMood(.happy)
                        overlay.say(Self.allSet, title: nil)
                        await speech.speak(Self.allSet)
                    }
                } else {
                    w8.stop()
                }
                break
            }
            if !GuideMode.automatic {
                // Clicky-style: one fresh answer per question. The pointer stays until they act on it;
                // "next" (or any follow-up) looks again with the whole conversation in mind.
                overlay.state.hint = "Hold \(TalkShortcut.current.symbol) and say “next” when you're ready"
                overlay.setMood(.idle)
                guideWaiting = true
                _ = await w8.wait(timeout: 25)
                guideWaiting = false
                if Task.isCancelled || generation != gen { return }
                overlay.reset()
                return
            }
            overlay.setMood(.idle)
            // Stays true until the next step starts talking: the step they just did may open another app.
            guideWaiting = true
            let action = actedEarly ? w8.currentAction() : await w8.wait(timeout: 90)
            if Task.isCancelled || generation != gen { guideWaiting = false; return }
            guard let action else {
                guideWaiting = false
                overlay.release()
                overlay.say("I'm right here whenever you're ready.")
                break
            }
            lastAction = action
            // Straight on to the next step (no "nice"/"got it" filler: it read as a pause, not a person).
            overlay.setMood(.thinking)
        }
        let summary = given.joined(separator: " ")
        Task { await family.send(.init(type: "help", title: "Helped with: \(question.prefix(80))", explanation: String(summary.prefix(300)), app: nil)) }
        overlay.setMood(.happy)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if Task.isCancelled || generation != gen { return }
        overlay.reset()
    }

    /// Testing only (LOOKOUT_TEST_GUIDE_CLICK=1): click what Scout pointed at, 2.5 s later, so the follow-along
    /// loop can be exercised end to end without a person. Clicks only inside the front window of the app named by
    /// LOOKOUT_TEST_GUIDE_APP (e.g. Calculator), or the demo browser when that's unset.
    func testAutoClick(at p: CGPoint) {
        let env = ProcessInfo.processInfo.environment
        guard env["LOOKOUT_TEST_GUIDE_CLICK"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            var allowed: CGRect?
            if let name = env["LOOKOUT_TEST_GUIDE_APP"] {
                if let app = NSWorkspace.shared.frontmostApplication, app.localizedName == name { allowed = Self.focusedWindowFrame(app.processIdentifier) }
            } else if self.demoInFront {
                let f = self.demoBrowser.window.frame
                let primary = NSScreen.screens.first?.frame.height ?? 0
                allowed = CGRect(x: f.minX, y: primary - f.maxY, width: f.width, height: f.height)
            }
            guard let allowed, allowed.contains(p) else { Log.info("test click skipped: outside the allowed window"); return }
            Log.info("test click at \(Int(p.x)),\(Int(p.y))")
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Top-left global frame of an app's focused window (Accessibility).
    static func focusedWindowFrame(_ pid: pid_t) -> CGRect? {
        let ax = AXUIElementCreateApplication(pid)
        var win: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win else { return nil }
        var pv: AnyObject?, sv: AnyObject?
        guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(w as! AXUIElement, kAXSizeAttribute as CFString, &sv) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sv as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Fly to what the model pointed at and ring it.
    func point(at p: PointTags.Point, snap: Snapshot) {
        let screenPt = snap.screenPoint(forImagePoint: CGPoint(x: p.x, y: p.y))
        let (snapped, el) = snap.snap(screenPt, label: p.label)
        // No matching control: ring the spot itself.
        let hl = el.map { overlayRect(fromScreenTopLeft: $0.frame) }
            ?? overlayRect(fromScreenTopLeft: CGRect(x: snapped.x - 22, y: snapped.y - 16, width: 44, height: 32))
        overlay.fly(to: overlayPoint(fromScreenTopLeft: snapped), highlight: hl)
        testAutoClick(at: snapped)
        Log.info("point: img(\(Int(p.x)),\(Int(p.y))) → screen(\(Int(snapped.x)),\(Int(snapped.y))) label=\(p.label ?? "-") snapped=\(el?.label.prefix(30) ?? "no")")
    }

    /// True while the guide waits for the person to do a step (switching apps then is part of the task).
    private(set) var guideWaiting = false

    func guideUserText(question: String, snap: Snapshot, given: [String], action: ActionWatcher.Action?) -> String {
        var s = helpUserText(question: question, snap: snap)
        if !given.isEmpty {
            s += "\nSteps you already gave for this question:\n"
            for (i, g) in given.enumerated() { s += "\(i + 1). \(g)\n" }
            if let action { s += "Since your last step, they \(action.describe(in: snap)).\n" }
            s += "Give the next step for the screen as it is now.\n"
        }
        return s
    }

    /// What Scout and the person have done together recently. Updated as each step is given (not when a
    /// guide finishes), so a guide cut short by "what now?" is still remembered and can be continued.
    struct Turn {
        var question: String
        var app: String?
        var steps: [String] = []
        var actions: [String] = []
        var finished = false
        var at = Date()
    }
    private var turns: [Turn] = []

    func beginTurn(_ question: String, app: String?) -> Int {
        turns.append(Turn(question: question, app: app))
        if turns.count > 6 { turns.removeFirst(turns.count - 6) }
        return turns.count - 1
    }

    func updateTurn(_ i: Int, step: String? = nil, action: String? = nil, finished: Bool = false) {
        guard turns.indices.contains(i) else { return }
        if let step { turns[i].steps.append(step) }
        if let action { turns[i].actions.append(action) }
        if finished { turns[i].finished = true }
        turns[i].at = Date()
    }

    func remember(question: String, answer: String) {
        let i = beginTurn(question, app: nil)
        updateTurn(i, step: String(answer.prefix(600)), finished: true)
    }

    /// Earlier turns (not the current one), newest last, from the last 20 minutes.
    func historyText(excluding current: Int?) -> String {
        let recent = turns.enumerated().filter { $0.offset != current && Date().timeIntervalSince($0.element.at) < 1200 }.map(\.element)
        guard !recent.isEmpty else { return "" }
        var s = "Earlier in this conversation (oldest first; the screen may have changed since):\n"
        for t in recent {
            s += "- They asked: \"\(t.question)\"" + (t.app.map { " (in \($0))" } ?? "") + "\n"
            for (k, step) in t.steps.enumerated() {
                s += "  You said: \(step)\n"
                if k < t.actions.count { s += "  Then they: \(t.actions[k])\n" }
            }
            if !t.finished { s += "  (Not finished. If their new question is short or vague, like \"what now?\" or \"I did it\", they are continuing this task.)\n" }
        }
        return s + "\n"
    }

    func helpUserText(question: String, snap: Snapshot) -> String {
        var s = historyText(excluding: currentTurn)
        s += "Question: \(question)\n"
        if let a = snap.context.appName { s += "Front app: \(a)\n" }
        if let t = snap.context.windowTitle { s += "Window: \(t)\n" }
        if let u = snap.context.url { s += "Address: \(u)\n" }
        let inv = snap.imageToScreen.inverted()
        let iw = CGFloat(snap.image?.width ?? Int.max), ih = CGFloat(snap.image?.height ?? Int.max)
        // Only controls actually visible in the screenshot, real controls (buttons, links, fields) before plain text,
        // so big apps like Gmail don't fill the list with off-screen rows before reaching Send.
        let visible = snap.elements.filter { e in
            let c = CGPoint(x: e.frame.midX, y: e.frame.midY).applying(inv)
            return c.x >= 0 && c.y >= 0 && c.x < iw && c.y < ih && e.label.count < 120
        }
        let passive: Set<String> = ["AXStaticText", "AXImage"]
        let ordered = visible.filter { !passive.contains($0.role) } + visible.filter { passive.contains($0.role) }
        let els = ordered.prefix(160).map { e -> String in
            let c = CGPoint(x: e.frame.midX, y: e.frame.midY).applying(inv)
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

    // MARK: Explain this letter

    func explainScreen(question: String = "What does this letter mean?") async {
        let owner = generation
        busy = true
        defer { if generation == owner { busy = false } }
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
            remember(question: question, answer: buffer)
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
        // The demo launcher lists every scam by name; it isn't one.
        if snap.isFixture, demoBrowser.web.url?.lastPathComponent == "index.html" { return }
        guard !snap.context.text.isEmpty || !snap.context.runningApps.isEmpty else { return }
        if let app = snap.context.appName, Self.ignoredApps.contains(app) { return }
        let page = Self.pageKey(snap.context)
        // A page Claude called safe stays quiet for 10 minutes, but its screens still feed the playbook
        // engine so the session history stays complete; only a hard rule can interrupt it.
        let cleared = clearedPages[page].map { Date().timeIntervalSince($0) < 600 } ?? false
        // Claude already called this page a scam: don't re-ask every pass (a blinking cursor changes the fingerprint).
        let knownScam = scamPages[page].map { Date().timeIntervalSince($0) < 120 } ?? false
        // Without screen text every screen looks "unchanged", so ordinary clicking would read as stuck.
        if !snap.context.text.isEmpty {
            stuck.observe(fingerprint: snap.context.fingerprint, window: (snap.context.appName ?? "") + (snap.context.windowTitle ?? ""))
        }
        // Preview first: if this screen is suspicious enough for outside checks (Claude, and CRS on the
        // sender), the playbook observation is committed once, together with their answers as evidence.
        var result = pipeline.evaluate(snap.context, commitPlaybook: false)
        let fp = snap.context.fingerprint
        if fp != stableFingerprint { stableFingerprint = fp; stableSince = Date() }
        // Outside checks (Kyle's flow): Claude and, when the screen shows a sender address, CRS Fraud Finder,
        // in parallel, from risk >= 0.10. Skipped on pages Claude already settled (cleared or confirmed scam).
        let senderEmail = SenderCheck.extractSender(snap.context)
        let willConfirm = !cleared && !knownScam && result.shouldConfirmWithModel && fp != lastConfirmedFingerprint && !confirmInFlight
            && (claude.isConfigured || senderEmail != nil)
        // Deep check: Claude also reads screens the on-device rules found nothing on (friendly romance and
        // crypto chats have no trigger words). On the 154-screen benchmark Claude alone caught 79/79 scams
        // with 0/75 false alarms. Text only, once per settled screen, at most every 8 s.
        let willSweep = !willConfirm && !cleared && !knownScam && DeepCheck.enabled && claude.isConfigured && !confirmInFlight
            && snap.context.text.count >= 80 && fp != lastConfirmedFingerprint
            && Date().timeIntervalSince(stableSince) >= 2 && Date().timeIntervalSince(lastSweepAt) >= 8
        if !willConfirm && !willSweep { result = pipeline.commit(snap.context) }
        if result.probability > 0.05 { Log.info("guardian: \(result.summary)") }
        guard result.action > .quiet || willConfirm || willSweep else { return }
        if cleared && result.rules.isEmpty { return }

        var verdict: ScamVerdict?
        var full = snap
        if willConfirm || willSweep {
            confirmInFlight = true
            lastConfirmedFingerprint = fp
            // Background check: don't turn the buddy into a spinner while it's pointing or talking in a help answer.
            if willSweep { lastSweepAt = Date() } else if !busy { overlay.setMood(.thinking) }
            if willConfirm { full = await snapshot(includeImage: claude.isConfigured) }
            let summary = result.summary
            let ctx = full.context, image = full.image
            // Claude and CRS run in parallel; either can fail without blocking the other.
            async let claudeAnswer: ScamVerdict? = claude.isConfigured
                ? (try? await claude.confirmScam(screen: ctx, image: image, heuristicSummary: summary)) : nil
            async let crsAnswer: SenderCheck? = (willConfirm && senderEmail != nil) ? await checkSenderCached(senderEmail!) : nil
            verdict = await claudeAnswer
            let sender = await crsAnswer
            // Both answers enter the playbook HMM as evidence, committed once for this screen.
            result = pipeline.applyChecks(verdict: verdict, sender: sender, ctx: full.context)
            if let c = sender { Log.info("crs sender check: \(c.verdict.rawValue) score=\(c.score.map(String.init) ?? "-") firstSeen=\(c.firstSeen ?? "-") source=\(c.source)") }
            if let v = verdict {
                if v.isScam { scamPages[page] = Date() }
                // Claude read the screen and says scam: warn, even if the rules and the playbook are still quiet.
                if v.isScam, result.action < .interrupt {
                    result.decision.action = .interrupt
                    result.decision.reason += "; raised by Claude \(willSweep ? "deep check" : "check")"
                    if !v.explanation.isEmpty { result.explanation = v.explanation; result.advice = v.whatToDo }
                }
                Log.info("claude verdict\(willSweep ? " (deep check)" : ""): scam=\(v.isScam) conf=\(v.confidence) type=\(v.scamType) why=\(v.explanation.prefix(160)) → \(result.summary)")
                // Claude has looked at the actual screen: its "not a scam" is final unless a hard rule fired or
                // CRS rated the sender high risk (then the playbook engine decides with both pieces of evidence).
                // (Not gated on confidence: the schema's "0 to 1" comes back as either certainty or scam odds.)
                if !v.isScam, result.rules.isEmpty, sender?.verdict != .high {
                    clearedPages[page] = Date()
                    Log.info("guardian: page cleared by Claude for 10 min")
                    confirmInFlight = false
                    if !busy && !card.isShowing { overlay.setMood(.idle) }   // a warning card still up keeps the buddy amber
                    return
                }
            } else if claude.isConfigured {
                Log.info("claude check unavailable; deciding with on-device evidence\(sender != nil ? " and CRS" : "")")
            }
            confirmInFlight = false
            if !busy && !card.isShowing { overlay.setMood(.idle) }   // a warning card still up keeps the buddy amber
        }
        await act(on: result, verdict: verdict, snap: full)
    }

    /// Browsers where ⌘W closes just the scam tab. (Chrome's id is com.google.Chrome: the old case-sensitive
    /// check for "chrome" never matched it, so real Chrome only ever got "Got it".)
    static func isBrowser(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier?.lowercased() else { return false }
        return ["safari", "chrome", "firefox", "edge", "brave", "thebrowser", "opera", "vivaldi", "chromium"].contains { id.contains($0) }
    }

    /// The page's URL, or app + window title outside a browser.
    static func pageKey(_ c: ScreenContext) -> String {
        c.url ?? "\(c.appName ?? "")|\(c.windowTitle ?? "")"
    }

    private var senderChecks: [String: SenderCheck] = [:]

    /// One CRS lookup per sender address per session (the family server also caches for a day).
    func checkSenderCached(_ email: String) async -> SenderCheck? {
        if let c = senderChecks[email] { return c }
        guard let c = await family.checkSender(email) else { return nil }
        senderChecks[email] = c
        return c
    }

    func act(on r: ScamPipeline.Result, verdict: ScamVerdict?, snap: Snapshot) async {
        // One alert per page (URL, or app + window) per 90 seconds, however the evidence shifts.
        let key = Self.pageKey(snap.context)
        switch r.action {
        case .quiet:
            return
        case .nudge:
            // Low-level suspicion stays silent: the "take your time" bubble popped up far too often to be useful.
            // Only real warnings (interrupt and above) reach the person.
            return
        case .interrupt, .blockAndAlert:
            // One warning per page, then quiet for 10 minutes (30 once they've dismissed it). Also keyed by what
            // would be said: Gmail's address changes between the inbox and the open message, and the same email
            // warned three times in four minutes.
            let now = Date()
            if let t = dismissedWarnings[key], now.timeIntervalSince(t) < 1800 { return }
            if let t = recentWarnings[key], now.timeIntervalSince(t) < 600 { return }
            if let t = recentWarnings[r.spoken], now.timeIntervalSince(t) < 600 { return }
            recentWarnings[key] = now
            recentWarnings[r.spoken] = now
            lastWarnedKey = key
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
        cancelRequest()   // a warning takes over from any help answer in progress
        busy = true
        defer { busy = false }
        speech.stop()
        overlay.setMood(.alarmed)
        if let (p, rect) = threatPoint(r, verdict: verdict, snap: snap) { overlay.fly(to: p, highlight: rect) }
        let spoken = r.spoken.isEmpty ? "This looks like a scam. Let's stop here." : r.spoken
        overlay.say(spoken, title: "Wait — this looks like a scam")
        let canClose = demoInFront || Self.isBrowser(NSWorkspace.shared.frontmostApplication)
        // Only offer to close in a browser: ⌘W anywhere else closes whatever window is in front.
        let buttons: [ActionCard.Button] = canClose ? [
            .init(title: "Close it for me", primary: true) { [weak self] in Log.info("user: close it"); self?.dismissWarning(); self?.closeThreat() },
            .init(title: "I'm OK, thanks", primary: false) { [weak self] in Log.info("user: I'm OK"); self?.dismissWarning(); self?.overlay.reset() },
        ] : [
            .init(title: "Got it", primary: true) { [weak self] in Log.info("user: got it"); self?.dismissWarning(); self?.overlay.reset() },
        ]
        card.show(title: "Let's be careful", message: "You're safe. Nothing has happened yet." + (LookoutConfig.familyEnabled ? " \(LookoutConfig.familyName) has been told." : ""), alarmed: true, buttons: buttons, near: buddyScreenPoint)
        Task {
            let thumb = snap.image.flatMap { ImageUtil.thumbnailDataURL($0.data) }
            await family.send(.init(type: "scam_alert",
                                    title: Companion.alertTitle(verdict: verdict, rule: r.rules.first),
                                    explanation: [verdict?.familySummary.isEmpty == false ? verdict!.familySummary : r.explanation, r.stageLine, Companion.evidenceLine(pipeline)].compactMap { $0 }.joined(separator: " "),
                                    risk: r.probability, url: snap.context.url, app: snap.context.appName, screenshot: thumb,
                                    action: "Scout interrupted and explained the warning signs"))
        }
        DebugShot.take("interrupt")
        // Let the buddy and the card appear first, then speak: a calmer start than a voice out of nowhere.
        try? await Task.sleep(nanoseconds: 800_000_000)
        await speech.speak(spoken)
    }

    /// "Why: AnyDesk launched +3.1 · refund invoice +4.2" from the playbook evidence ledger.
    static func evidenceLine(_ p: ScamPipeline) -> String? {
        guard let pb = p.playbook else { return nil }
        let top = pb.topEvidence(3).filter { $0.logBF > 0.5 && $0.item != "nothing else on screen" }
        guard !top.isEmpty else { return nil }
        let names: [String: String] = [
            "REMOTE_ACCESS_STARTED": "remote-control app", "PHONE_NUMBER_IN_POPUP": "phone number in a pop-up", "INFECTED_CLAIM": "fake virus warning",
            "REFUND_OVERPAYMENT": "surprise refund/invoice", "BANK_SITE_OPENED": "bank site opened", "PAYMENT_DEMAND": "payment demand",
            "GIFT_CARD_PAGE": "gift cards", "WIRE_OR_CRYPTO_PAGE": "wire/crypto", "SECRECY_REQUEST": "asked to keep it secret",
            "FAMILY_EMERGENCY_STORY": "family emergency story", "LEGAL_THREAT": "legal threat", "GOV_IMPERSONATION": "posing as government",
            "LOOKALIKE_DOMAIN": "fake web address", "BRAND_IMPERSONATION": "posing as a brand", "URGENT_LANGUAGE": "pressure to hurry",
            "CLAUDE_FLAG": "AI check agreed", "CRS_SENDER_HIGH_RISK": "sender flagged by CRS", "SENSITIVE_FIELD_ON_UNKNOWN_SITE": "asks for private info", "SCREEN_SHARE_ACTIVE": "screen sharing",
        ]
        return "Why: " + top.map { String(format: "%@ +%.1f", names[$0.item] ?? $0.item, $0.logBF) }.joined(separator: " · ")
    }

    nonisolated(unsafe) static var pipelineForTitle: ScamPipeline?

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
        if let pb = pipelineForTitle?.playbook?.state(), pb.pScam >= 0.5, let l = pb.topTypeLabel { return "Stopped: \(l)" }
        return "Possible scam on \(LookoutConfig.elderName)'s screen"
    }

    /// Leaves the page in front: the demo browser goes back to its launcher; a real browser closes the tab (⌘W).
    /// Decided by what's in front, not by whether the demo browser happens to be open somewhere behind it.
    func closeFrontPage() {
        if demoInFront {
            Task { await demoBrowser.load(Companion.demoIndexURL()) }
        } else if Self.isBrowser(NSWorkspace.shared.frontmostApplication), Permissions.accessibility {
            let src = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: true); down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: false); up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    func closeThreat() {
        pipeline.engine.reset()
        closeFrontPage()
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
        cancelRequest()
        speech.stop()
        card.hide()
        overlay.setMood(.alarmed)
        let field = snap.context.sensitiveFields.first ?? "payment"
        let what: String = ["gift-card": "gift card codes", "ssn": "your Social Security number", "password": "your password", "bank": "your bank details"][field] ?? "your card details"
        let reason = "This page is asking for \(what), and something about it doesn't look right."
        payPause.show(familyName: LookoutConfig.familyName, reason: reason, onCancel: { [weak self] in
            guard let self else { return }
            self.closeFrontPage()   // "Go back" really leaves the page
            self.overlay.setMood(.happy)
            Task { await self.speech.speak("Good choice. Nothing was sent.") ; self.overlay.reset() }
        }, onOverride: { [weak self] in
            self?.overlay.reset()
            Log.info("pay pause: user continued")
        })
        DebugShot.take("paypause")
        // CRS's finding about the sender, when it ran and was high risk (Kyle).
        let crsLine = r.senderCheck?.isHighRisk == true ? (r.senderCheck?.sentence ?? "") + " " : ""
        guard LookoutConfig.familyEnabled else {
            // No family check: just a calm pause, and the choice stays theirs.
            payPause.model.status = .selfPause
            Task { await speech.speak("Let's slow down for a moment. \(reason) \(crsLine)Take a breath. Nobody real will rush you.") }
            return
        }
        let spoken = "Let's pause for a moment. \(reason) \(crsLine)I'm asking \(LookoutConfig.familyName) to take a look."
        Task { await speech.speak(spoken) }
        let thumb = snap.image.flatMap { ImageUtil.thumbnailDataURL($0.data) }
        let amount = Self.firstAmount(in: snap.context.text)
        let id = await family.requestApproval(title: "\(LookoutConfig.elderName) is about to enter \(what)", explanation: [r.explanation.isEmpty ? reason : r.explanation, r.senderCheck?.isHighRisk == true ? "CRS: the sender's address (\(r.senderCheck!.email)) scores \(r.senderCheck!.score ?? 100)/100 risk\(r.senderCheck!.newToday ? " and first appeared today" : "")." : nil, Companion.evidenceLine(pipeline)].compactMap { $0 }.joined(separator: " "), amount: amount, payee: snap.context.url.flatMap { Domains.host(of: $0) }, method: field == "gift-card" ? "gift card" : field, risk: r.probability, screenshot: thumb)
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
            Task { @MainActor in self?.checkRemote(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                if self?.knownRemoteApps.remove(pid) != nil {
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
                                explanation: "A remote-control program started. Scout asked whether it was expected.", risk: pipeline.engine.assess(currentScreen: []).probability, app: name, action: "Asked \(LookoutConfig.elderName) whether to end the session"))
        await speech.speak(msg)
    }

    func endRemoteSession(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "the program"
        // Test safety switch: only ever terminate Scout's own dummy apps.
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
        card.show(title: "Want some help?", message: "I can show you where to click.", alarmed: false, buttons: [
            .init(title: "Yes, please", primary: true) { [weak self] in
                guard let self else { return }
                if Listener.canUseMicrophone { self.overlay.say("Hold \(TalkShortcut.current.spoken), and tell me what you're trying to do.") }
                else { AppDelegate.shared?.askTyped() }
            },
            .init(title: "No thanks", primary: false) { [weak self] in self?.stuck.snooze(); self?.overlay.reset() },
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
        }
    }
}

/// "Seems stuck": same window, screen not changing, and repeated clicks for a while.
@MainActor
/// "Need a hand?" when someone seems stuck. Off by default: it guessed wrong too often (waiting for a
/// verification code looks like being stuck). Settings ▸ Buddy turns it on.
enum StuckHelp {
    nonisolated static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "stuckHelp") }
        set { UserDefaults.standard.set(newValue, forKey: "stuckHelp") }
    }
}

final class StuckDetector {
    private var clicks: [Date] = []
    private var sameSince = Date()
    private var lastWindow = ""
    private var lastFingerprint = 0
    private var lastOffer = Date.distantPast
    private var monitor: Any?
    private var onStuck: (() -> Void)?
    var window: TimeInterval = 60
    var minClicks = 10
    /// At most one offer every 15 minutes; "No thanks" quiets it for 2 hours.
    var cooldown: TimeInterval = 900

    func snooze() { lastOffer = Date().addingTimeInterval(7200 - cooldown) }

    func start(onStuck: @escaping () -> Void) {
        self.onStuck = onStuck
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            // (Not MainActor.assumeIsolated: that check crashed the follow timer.)
            Task { @MainActor in self?.clicks.append(Date()) }
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
        guard StuckHelp.enabled else { clicks.removeAll(); return }
        if now.timeIntervalSince(sameSince) >= window, clicks.count >= minClicks, now.timeIntervalSince(lastOffer) > cooldown {
            lastOffer = now
            clicks.removeAll()
            onStuck?()
        }
    }
}

/// LOOKOUT_DEBUG_SHOTS=1: saves an image of Scout's own windows only (never other apps)
/// to ~/Library/Application Support/Lookout/shots/. Demo/debug only.
enum DebugShot {
    static var enabled: Bool { ProcessInfo.processInfo.environment["LOOKOUT_DEBUG_SHOTS"] == "1" }
    static func take(_ name: String) {
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Only Scout's own windows (never other apps' content), composited over a plain background.
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

/// Claude reads every settled screen, not only the ones the on-device rules flag. On by default.
enum DeepCheck {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "deepCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deepCheck") }
    }
}

/// How help moves between steps. Default (automatic): Scout watches for the click and gives the next step
/// on its own, like someone watching over your shoulder. Off: one answer per question, like Clicky.
enum GuideMode {
    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "autoGuide") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoGuide") }
    }
}

/// Watches what the person does after a help step: where they click, whether they type.
@MainActor
final class ActionWatcher {
    struct Action {
        var click: CGPoint?   // top-left global screen coordinates
        var typed: Int = 0

        /// "clicked "Google Calendar" (at 812,40 in this screenshot)" / "typed some text"
        func describe(in snap: Snapshot) -> String {
            var parts: [String] = []
            if let c = click {
                let img = c.applying(snap.imageToScreen.inverted())
                let el = snap.elements.filter { $0.frame.insetBy(dx: -4, dy: -4).contains(c) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                let on = el.map { " on \"\($0.label.prefix(60))\"" } ?? ""
                parts.append("clicked\(on) (at \(Int(img.x)),\(Int(img.y)) in this screenshot)")
            }
            if typed > 0 { parts.append("typed some text (\(typed) keys)") }
            return parts.isEmpty ? "moved to a new window or page" : parts.joined(separator: " and ")
        }
    }

    private var monitor: Any?
    private let startWindow = ActionWatcher.frontWindowKey()
    private var windowChangedAt: Date?
    private var lastWindowCheck = Date()
    var sawClick: Bool { lastClick != nil }
    private var lastClick: (at: Date, point: CGPoint)?
    private var lastKey: Date?
    private var keys = 0

    private var localMonitor: Any?
    /// Extra state that changes when the person moves on inside Scout's own windows (the demo browser's page).
    static var extraWindowKey: (@MainActor () -> String)?

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] e in
            let isKey = e.type == .keyDown
            let loc = NSEvent.mouseLocation
            Task { @MainActor in self?.record(isKey: isKey, appKitPoint: loc) }
        }
        // Global monitors never see events in our own windows, and the demo browser is one of them.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] e in
            let isKey = e.type == .keyDown
            let loc = NSEvent.mouseLocation
            Task { @MainActor in self?.record(isKey: isKey, appKitPoint: loc) }
            return e
        }
    }

    private func record(isKey: Bool, appKitPoint: CGPoint) {
        if isKey { lastKey = Date(); keys += 1; return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        lastClick = (Date(), CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y))
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        monitor = nil
        localMonitor = nil
    }

    /// Front app + its focused window's title: changes when a page, tab, dialog or app changes.
    static func frontWindowKey() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "" }
        var title = ""
        if Permissions.accessibility {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.1)
            var win: AnyObject?
            if AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win {
                var t: AnyObject?
                if AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success { title = (t as? String) ?? "" }
            }
        }
        return "\(app.processIdentifier)|\(title)|\(extraWindowKey?() ?? "")"
    }

    /// True once they've done something and the screen had a moment to update: a click (0.35 s ago, not
    /// followed by typing), a pause after typing (1.3 s), or a new window, tab or app (Enter submitted a form).
    func ready() -> Bool {
        if let k = lastKey, Date().timeIntervalSince(k) > 1.3 { return true }
        if let c = lastClick, lastKey.map({ $0 < c.at }) ?? true, Date().timeIntervalSince(c.at) > 0.35 { return true }
        // (An Accessibility round-trip, so at most twice a second: a slow app must not stall the overlay.)
        if windowChangedAt == nil, Date().timeIntervalSince(lastWindowCheck) >= 0.5 {
            lastWindowCheck = Date()
            if Self.frontWindowKey() != startWindow { windowChangedAt = Date() }
        }
        if let w = windowChangedAt, Date().timeIntervalSince(w) > 0.4 { return true }
        return false
    }

    /// What they've done so far (for when Scout noticed it while still talking).
    func currentAction() -> Action {
        stop()
        return Action(click: lastClick?.point, typed: keys)
    }

    /// Returns once ready(), or nil after the timeout with nothing done.
    func wait(timeout: TimeInterval) async -> Action? {
        let start = Date()
        while !Task.isCancelled && Date().timeIntervalSince(start) < timeout {
            if ready() { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        stop()
        guard !Task.isCancelled, lastClick != nil || lastKey != nil || windowChangedAt != nil else { return nil }
        return Action(click: lastClick?.point, typed: keys)
    }
}

/// Speaks sentences in order as they arrive from a stream, fetching each clip as soon as it's queued.
@MainActor
final class SentenceQueue {
    private let speech: SpeechOutput
    private var items: [String] = []
    private var task: Task<Void, Never>?
    private var closed = false
    private var wake: CheckedContinuation<Void, Never>?
    /// False once the request was stopped (Esc, a new question): drop whatever is left.
    private let isCurrent: () -> Bool

    init(speech: SpeechOutput, isCurrent: @escaping () -> Bool) { self.speech = speech; self.isCurrent = isCurrent }

    func add(_ sentence: String) {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        items.append(s)
        speech.prepare(s)
        if task == nil { task = Task { await self.run() } }
        wake?.resume(); wake = nil
    }

    func finish() async {
        closed = true
        wake?.resume(); wake = nil
        await task?.value
    }

    func cancel() {
        closed = true
        items.removeAll()
        wake?.resume(); wake = nil
        task?.cancel()
    }

    private func run() async {
        while !Task.isCancelled && isCurrent() {
            if items.isEmpty {
                if closed { return }
                await withCheckedContinuation { wake = $0 }
                continue
            }
            while speech.isSpeaking && !Task.isCancelled && isCurrent() { try? await Task.sleep(nanoseconds: 40_000_000) }
            guard !Task.isCancelled, isCurrent(), !items.isEmpty else { continue }   // cancelled while waiting
            await speech.speak(items.removeFirst())
        }
    }
}
