import AVFoundation
import Foundation
import ScoutCore

/// Push-to-talk transcription with Cartesia Ink (streaming STT over a websocket). Fed from the same microphone tap
/// as Apple Speech, which keeps running as the backup: if Cartesia can't be reached (venue Wi-Fi), the question
/// still gets through. SCOUT_STT=apple turns Cartesia off.
final class CartesiaSTT: @unchecked Sendable {
    static var isConfigured: Bool {
        !(Secrets.shared["CARTESIA_API_KEY"] ?? "").isEmpty && (Secrets.shared["SCOUT_STT"] ?? "cartesia") != "apple"
    }

    /// Called on the main thread with everything heard so far (final words plus the words still being decided).
    var onPartial: ((String) -> Void)?

    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var pending = Data()
    private var finals = ""
    private var interim = ""
    private var failed = false
    private var gotAny = false
    private var flushed: CheckedContinuation<Void, Never>?
    private let started = Date()

    init(hints: [String]) {
        guard let key = Secrets.shared["CARTESIA_API_KEY"] else { failed = true; return }
        var c = URLComponents(string: "wss://api.cartesia.ai/stt/websocket")!
        var q = [URLQueryItem(name: "model", value: "ink-2"),
                 URLQueryItem(name: "encoding", value: "pcm_s16le"),
                 URLQueryItem(name: "sample_rate", value: "16000"),
                 URLQueryItem(name: "cartesia_version", value: "2026-08-14")]
        // Names it should expect (running apps, everyday services), within Cartesia's 100 terms / 1,200 characters.
        var budget = 1_100
        for h in Set(hints) where budget - h.count > 0 && q.count < 100 {
            q.append(URLQueryItem(name: "keyterm", value: h))
            budget -= h.count
        }
        c.queryItems = q
        var r = URLRequest(url: c.url!)
        r.setValue(key, forHTTPHeaderField: "X-API-Key")
        let ws = URLSession.shared.webSocketTask(with: r)
        socket = ws
        ws.resume()
        receive()
    }

    /// From the audio thread: convert to 16 kHz mono PCM and send about every 100 ms.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !failed, let socket else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
        }
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let p = out.int16ChannelData?[0] else { return }
        pending.append(Data(bytes: p, count: Int(out.frameLength) * 2))
        if pending.count >= 3_200 {   // 100 ms at 16 kHz, 16-bit
            let chunk = pending
            pending = Data()
            socket.send(.data(chunk)) { [weak self] e in if e != nil { self?.markFailed("send") } }
        }
    }

    /// After the key is released: flush, wait briefly for the last words, close. nil if Cartesia didn't answer.
    func finish(timeout: Double = 1.6) async -> String? {
        let (socket, rest, dead) = lock.withLock { () -> (URLSessionWebSocketTask?, Data, Bool) in
            defer { pending = Data() }
            return (self.socket, pending, failed)
        }
        guard let socket, !dead else { return nil }
        if !rest.isEmpty { try? await socket.send(.data(rest)) }
        try? await socket.send(.string("finalize"))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { flushed = c }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.resumeFlush() }
        }
        socket.cancel(with: .normalClosure, reason: nil)
        let text: String? = lock.withLock {
            guard gotAny, !failed || !finals.isEmpty else { return nil }
            return (finals + interim).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let text else { return nil }
        Log.info(String(format: "heard via Cartesia ink-2 (%.1f s)", Date().timeIntervalSince(started)))
        return text.isEmpty ? nil : text
    }

    func cancel() { lock.lock(); let s = socket; socket = nil; lock.unlock(); s?.cancel(with: .goingAway, reason: nil); resumeFlush() }

    private func resumeFlush() {
        lock.lock(); let c = flushed; flushed = nil; lock.unlock()
        c?.resume()
    }

    private func markFailed(_ why: String) {
        lock.lock()
        let first = !failed
        failed = true
        lock.unlock()
        if first { Log.info("cartesia stt unavailable (\(why)); using Apple Speech") }
        resumeFlush()
    }

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.markFailed("connection")
            case .success(let msg):
                if case .string(let s) = msg, let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] {
                    self.handle(o)
                }
                self.receive()
            }
        }
    }

    private func handle(_ o: [String: Any]) {
        switch o["type"] as? String {
        case "transcript":
            let text = o["text"] as? String ?? ""
            lock.lock()
            gotAny = true
            // `text` is a delta: final chunks are concatenated as-is; the latest non-final chunk is shown after them.
            if o["is_final"] as? Bool == true { finals += text; interim = "" } else { interim = text }
            let all = (finals + interim).trimmingCharacters(in: .whitespaces)
            lock.unlock()
            if !all.isEmpty { DispatchQueue.main.async { [weak self] in self?.onPartial?(all) } }
        case "flush_done", "done":
            resumeFlush()
        case "error":
            markFailed("\(o["status_code"] ?? "") \(o["message"] ?? "")")
        default:
            break
        }
    }
}
