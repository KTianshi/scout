import AppKit
import AVFoundation
import Speech
import Carbon.HIToolbox
import LookoutCore

// MARK: - Speech output

/// Anything that can say text out loud. AVSpeechSynthesizer today; Cartesia (streaming) can slot in later.
@MainActor
protocol SpeechOutput: AnyObject {
    /// Speak and resume when finished (or interrupted).
    func speak(_ text: String) async
    func stop()
    var isSpeaking: Bool { get }
    /// Start generating audio for a line that will be spoken soon (no-op by default).
    func prepare(_ text: String)
    /// Human-readable name of the voice engine, for logs and the menu.
    var engineName: String { get }
}

extension SpeechOutput {
    func prepare(_ text: String) {}
}

/// Cartesia Sonic voice, falling back to the system voice when there is no key or no network.
@MainActor
final class CartesiaSpeech: NSObject, SpeechOutput, AVAudioPlayerDelegate {
    let client: CartesiaClient
    let fallback: SystemSpeech
    private var player: AVAudioPlayer?
    private var waiter: CheckedContinuation<Void, Never>?
    private var pending: [String: Task<Data?, Never>] = [:]
    private var generation = 0
    var muted = ProcessInfo.processInfo.environment["LOOKOUT_MUTE"] == "1"
    /// Playback speed from Settings. Cartesia's own speed knob barely changes anything, so we time-stretch here.
    var rate: Float = VoiceSpeed.current.rate

    init(client: CartesiaClient = CartesiaClient(), fallback: SystemSpeech? = nil) {
        self.client = client
        // The menu's voice pick wins unless CARTESIA_VOICE_ID is set explicitly.
        if Secrets.shared["CARTESIA_VOICE_ID"] == nil { client.voiceID = LookoutVoice.current.id }
        self.fallback = fallback ?? SystemSpeech()
        super.init()
    }

    var engineName: String { client.isConfigured ? "Cartesia \(client.model)" : "System voice (no Cartesia key)" }
    var isSpeaking: Bool { (player?.isPlaying ?? false) || fallback.isSpeaking }

    func prepare(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, pending[clean] == nil, client.isConfigured || client.cached(clean) != nil else { return }
        let c = client
        pending[clean] = Task.detached { try? await c.wav(clean) }
    }

    func speak(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        generation += 1
        let myGen = generation
        if muted { Log.info("say: \(clean)"); try? await Task.sleep(nanoseconds: UInt64(min(6.0, Double(clean.count) * 0.05) * 1e9)); return }
        prepare(clean)
        let started = Date()
        let audio = await pending[clean]?.value
        pending[clean] = nil
        // stop() was called (or a newer line started) while we were generating.
        guard myGen == generation else { return }
        guard let audio, let p = try? AVAudioPlayer(data: audio) else {
            Log.info("say (system fallback): \(clean)")
            await fallback.speak(clean)
            return
        }
        Log.info(String(format: "say (cartesia, %.0f ms): ", Date().timeIntervalSince(started) * 1000) + clean)
        player = p
        p.delegate = self
        p.enableRate = true
        p.rate = rate
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiter = c
            if !p.play() { waiter = nil; c.resume() }
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        waiter?.resume(); waiter = nil
        fallback.stop()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard p === self.player else { return }
            self.waiter?.resume(); self.waiter = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard p === self.player else { return }
            self.waiter?.resume(); self.waiter = nil
        }
    }

    /// Lines Lookout says during scams and common moments, generated ahead of time so they play
    /// instantly and keep working offline.
    static func standardLines() -> [String] {
        var lines = HardRules.all.map(\.spoken)
        let fam = LookoutConfig.familyName
        lines += [
            "Hi, I'm Lookout. Hold \(TalkShortcut.current.spoken) any time to ask me something.",
            "There. It's gone. You did great.",
            "Good choice. Nothing was sent.",
            "\(fam) says it's OK. You can go ahead.",
            "\(fam) says please don't. This isn't safe. Nothing was sent.",
            "Want some help? I'm right here.",
            "This looks like a scam. Let's stop here.",
        ]
        return lines
    }
}

@MainActor
final class SystemSpeech: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var waiters: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    let voice: AVSpeechSynthesisVoice?
    var muted = ProcessInfo.processInfo.environment["LOOKOUT_MUTE"] == "1"

    override init() {
        voice = SystemSpeech.bestVoice()
        super.init()
        synth.delegate = self
    }

    /// Prefer a Premium, then Enhanced, calm US English voice.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let preferredNames = ["Ava", "Zoe", "Allison", "Samantha", "Evan", "Nathan", "Susan", "Joelle", "Noelle", "Serena", "Kate"]
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium: s += 300
            case .enhanced: s += 200
            default: s += 0
            }
            if v.language == "en-US" { s += 50 }
            if let i = preferredNames.firstIndex(where: { v.name.hasPrefix($0) }) { s += 40 - i }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 1000 }
            if v.identifier.contains("eloquence") || v.identifier.contains("speech.synthesis.voice.") && v.quality == .default { s -= 20 }
            return s
        }
        return voices.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    var isSpeaking: Bool { synth.isSpeaking }
    var engineName: String { "System voice (\(voice?.name ?? "default"))" }

    func speak(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        Log.info("say: \(clean)")
        if muted { try? await Task.sleep(nanoseconds: UInt64(min(6.0, Double(clean.count) * 0.05) * 1e9)); return }
        let u = AVSpeechUtterance(string: clean)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        u.pitchMultiplier = 1.0
        u.postUtteranceDelay = 0.15
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters[ObjectIdentifier(u)] = c
            synth.speak(u)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        for (_, c) in waiters { c.resume() }
        waiters.removeAll()
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume() }
    }
}

/// Cartesia voices offered in the menu: clear and friendly, picked for older listeners.
struct LookoutVoice: Equatable {
    let id: String
    let name: String

    /// "Katie (clear, friendly)" → "Katie" and "Clear, friendly".
    var label: String { String(name.prefix { $0 != " " }) }
    var detail: String {
        guard let open = name.firstIndex(of: "(") else { return "" }
        let d = name[name.index(after: open)...].dropLast()
        return d.prefix(1).uppercased() + d.dropFirst()
    }

    static let all: [LookoutVoice] = [
        .init(id: "f786b574-daa5-4673-aa0c-cbe3e8534c02", name: "Katie (clear, friendly)"),
        .init(id: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4", name: "Skylar (warm, American)"),
        .init(id: "9626c31c-bec5-4cca-baa8-f8ba9e84c8bc", name: "Jacqueline (reassuring)"),
        .init(id: "47c38ca4-5f35-497b-b1a3-415245fb35e1", name: "Daniel (crisp, male)"),
        .init(id: "0ad65e7f-006c-47cf-bd31-52279d487913", name: "Rupert (caring, older male)"),
        .init(id: "b24f41fd-00a3-4cd8-992a-a0c9f13f3ef1", name: "Clive (calm, British)"),
    ]

    static var current: LookoutVoice {
        get { all.first { $0.id == UserDefaults.standard.string(forKey: "cartesiaVoice") } ?? all[0] }
        set { UserDefaults.standard.set(newValue.id, forKey: "cartesiaVoice") }
    }
}

enum VoiceSpeed: String, CaseIterable {
    case slower, normal, faster

    var title: String {
        switch self {
        case .slower: return "Slower"
        case .normal: return "Normal"
        case .faster: return "Faster"
        }
    }
    /// Playback rate (pitch is kept). Clips are already generated a touch slow for older listeners.
    var rate: Float {
        switch self {
        case .slower: return 0.85
        case .normal: return 1.0
        case .faster: return 1.2
        }
    }

    static var current: VoiceSpeed {
        get { UserDefaults.standard.string(forKey: "voiceSpeed").flatMap(VoiceSpeed.init) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceSpeed") }
    }
}

// MARK: - Global shortcuts (push to talk, Esc to stop)

/// The hold-to-talk shortcut. Changeable from the menu because ⌥Space clashes with other assistants.
enum TalkShortcut: String, CaseIterable {
    case ctrlOptionSpace, ctrlShiftSpace, optionSpace

    var keyCode: UInt32 { UInt32(kVK_Space) }
    var modifiers: UInt32 {
        switch self {
        case .ctrlOptionSpace: return UInt32(controlKey | optionKey)
        case .ctrlShiftSpace: return UInt32(controlKey | shiftKey)
        case .optionSpace: return UInt32(optionKey)
        }
    }
    var symbol: String {
        switch self {
        case .ctrlOptionSpace: return "⌃⌥ Space"
        case .ctrlShiftSpace: return "⌃⇧ Space"
        case .optionSpace: return "⌥ Space"
        }
    }
    /// How Lookout says it out loud.
    var spoken: String {
        switch self {
        case .ctrlOptionSpace: return "Control, Option and Space"
        case .ctrlShiftSpace: return "Control, Shift and Space"
        case .optionSpace: return "Option and Space"
        }
    }

    static var current: TalkShortcut {
        get { UserDefaults.standard.string(forKey: "talkShortcut").flatMap(TalkShortcut.init) ?? .ctrlOptionSpace }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "talkShortcut") }
    }
}

/// Carbon hot keys: work without Accessibility or Input Monitoring permission, and report press + release.
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var press: [UInt32: () -> Void] = [:]
    private var release: [UInt32: () -> Void] = [:]
    private var installed = false

    static let talkID: UInt32 = 1
    static let escapeID: UInt32 = 2

    private func install() {
        guard !installed else { return }
        installed = true
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let kind = GetEventKind(event)
            let id = hk.id
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) { HotKeys.shared.press[id]?() }
                else if kind == UInt32(kEventHotKeyReleased) { HotKeys.shared.release[id]?() }
            }
            return noErr
        }, 2, &types, nil, nil)
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> Bool {
        install()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4C4B4F55), id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        press[id] = onPress
        release[id] = onRelease
        return true
    }

    func unregister(id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        press[id] = nil
        release[id] = nil
    }

    func isRegistered(_ id: UInt32) -> Bool { refs[id] != nil }
}

// MARK: - Speech recognition

/// Streams microphone audio into Apple Speech. Shape adapted from OpenClicky's AppleSpeechTranscriptionProvider (MIT).
@MainActor
final class Listener {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
    private(set) var latest = ""
    var onPartial: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    private var finish: CheckedContinuation<String, Never>?

    /// The app bundle must declare usage strings, otherwise touching the mic terminates the process.
    static var canUseMicrophone: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil &&
        Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
    }

    static func requestPermissions() async -> Bool {
        guard canUseMicrophone else { return false }
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        return speechOK && micOK
    }

    static var speechAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var micAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    func start() throws {
        latest = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req, weak self] buffer, _ in
            req?.append(buffer)
            guard let ch = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0
            let n = Int(buffer.frameLength)
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            let level = CGFloat(min(1, rms * 12))
            Task { @MainActor in self?.onLevel?(level) }
        }
        engine.prepare()
        try engine.start()
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.latest = text; self.onPartial?(text) }
                if isFinal || error != nil { self.deliver() }
            }
        }
    }

    /// Stop listening and return the final transcript (falls back to the latest partial after a short wait).
    func stop() async -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        return await withCheckedContinuation { c in
            finish = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.deliver() }
        }
    }

    private func deliver() {
        guard let f = finish else { return }
        finish = nil
        task?.cancel()
        task = nil
        f.resume(returning: latest)
    }
}
