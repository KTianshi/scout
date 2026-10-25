import Foundation
import CryptoKit

/// Cartesia Sonic text-to-speech over raw HTTP (POST /tts/bytes → WAV).
/// Clips are cached on disk by (voice, settings, text), so the fixed lines Lookout says during a scam
/// interrupt can be generated ahead of time and still play instantly if the network drops.
public final class CartesiaClient: @unchecked Sendable {
    public enum ClientError: Error, LocalizedError {
        case noKey
        case http(Int, String)
        public var errorDescription: String? {
            switch self {
            case .noKey: return "No Cartesia API key configured."
            case .http(let c, let b): return "Cartesia error \(c): \(b.prefix(300))"
            }
        }
    }

    public static let apiVersion = "2026-08-14"
    public static let baseURL = URL(string: "https://api.cartesia.ai")!

    public let apiKey: String?
    public var model: String
    public var voiceID: String
    /// Slightly slow and calm: the listener is an older adult.
    public var speed: Double
    public var emotion: String?
    public let cacheDir: URL
    private let session: URLSession

    public init(apiKey: String? = Secrets.shared["CARTESIA_API_KEY"],
                model: String = Secrets.shared["CARTESIA_MODEL"] ?? "sonic-3.6",
                // Default is the voice from Cartesia's Cal Hacks starter guide; override with CARTESIA_VOICE_ID.
                voiceID: String = Secrets.shared["CARTESIA_VOICE_ID"] ?? "a0e99841-438c-4a64-b679-ae501e7d6091",
                speed: Double = Secrets.shared["CARTESIA_SPEED"].flatMap(Double.init) ?? 0.9,
                emotion: String? = Secrets.shared["CARTESIA_EMOTION"],
                cacheDir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Lookout/voice", isDirectory: true)) {
        self.apiKey = apiKey
        self.model = model
        self.voiceID = voiceID
        self.speed = speed
        self.emotion = emotion
        self.cacheDir = cacheDir
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 20
        session = URLSession(configuration: cfg)
    }


    /// Opens (and caches) the TLS connection before a real request needs it, so the first call after a key
    /// press doesn't pay for a cold handshake. Fire-and-forget; failures don't matter.
    /// (Approach from Clicky's ClaudeAPI.warmUpTLSConnectionIfNeeded, MIT.)
    public func warmUp() {
        var r = URLRequest(url: Self.baseURL)
        r.httpMethod = "HEAD"
        r.timeoutInterval = 5
        session.dataTask(with: r).resume()
    }

    public var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    public func body(_ text: String) -> [String: Any] {
        var gen: [String: Any] = ["speed": speed, "volume": 1.0]
        if let emotion { gen["emotion"] = emotion }
        return [
            "model_id": model,
            "transcript": text,
            "voice": voiceID,
            "language": "en",
            "output_format": ["container": "wav", "encoding": "pcm_s16le", "sample_rate": 44100],
            "generation_config": gen,
        ]
    }

    public func cacheURL(for text: String) -> URL {
        let key = "\(model)|\(voiceID)|\(speed)|\(emotion ?? "")|\(text)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(String(hash.prefix(32)) + ".wav")
    }

    public func cached(_ text: String) -> Data? { try? Data(contentsOf: cacheURL(for: text)) }

    /// WAV audio for `text`, from the cache or Cartesia.
    public func wav(_ text: String) async throws -> Data {
        if let d = cached(text) { return d }
        guard let key = apiKey, !key.isEmpty else { throw ClientError.noKey }
        var r = URLRequest(url: Self.baseURL.appendingPathComponent("tts/bytes"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "cartesia-version")
        r.httpBody = try JSONSerialization.data(withJSONObject: body(text))
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.http(code, String(decoding: data, as: UTF8.self)) }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: cacheURL(for: text), options: .atomic)
        return data
    }

    /// Generate and cache lines ahead of time (sequentially, to stay well inside rate limits).
    public func prewarm(_ lines: [String]) async -> Int {
        var n = 0
        for l in lines where cached(l) == nil {
            if (try? await wav(l)) != nil { n += 1 }
        }
        return n
    }
}
