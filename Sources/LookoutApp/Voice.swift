import AppKit
import AVFoundation
import Speech
import Carbon.HIToolbox

// MARK: - Speech output

/// Anything that can say text out loud. AVSpeechSynthesizer today; Cartesia (streaming) can slot in later.
@MainActor
protocol SpeechOutput: AnyObject {
    /// Speak and resume when finished (or interrupted).
    func speak(_ text: String) async
    func stop()
    var isSpeaking: Bool { get }
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

// MARK: - Push to talk (Option + Space, hold)

/// Carbon hot key: works without Accessibility or Input Monitoring permission, and reports press + release.
final class PushToTalkHotKey {
    static var shared: PushToTalkHotKey?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        PushToTalkHotKey.shared = self
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) { PushToTalkHotKey.shared?.onPress?() }
                else if kind == UInt32(kEventHotKeyReleased) { PushToTalkHotKey.shared?.onRelease?() }
            }
            return noErr
        }, 2, &types, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4C4B4F55), id: 1) // 'LKOU'
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
        Log.info("push-to-talk hotkey ⌥Space registered: \(status == noErr)")
    }
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
