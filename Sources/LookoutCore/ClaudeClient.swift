import Foundation

/// Minimal Claude Messages API client over raw HTTP (Swift has no official Anthropic SDK).
public final class ClaudeClient: @unchecked Sendable {
    public enum ClientError: Error, LocalizedError {
        case noKey
        case http(Int, String)
        case refusal(String?)
        case badResponse(String)
        public var errorDescription: String? {
            switch self {
            case .noKey: return "No Anthropic API key configured."
            case .http(let c, let b): return "Claude API error \(c): \(b.prefix(300))"
            case .refusal(let c): return "Claude declined (\(c ?? "unknown"))."
            case .badResponse(let s): return "Unexpected response: \(s.prefix(200))"
            }
        }
    }

    public struct Image: Sendable {
        public var data: Data
        public var mediaType: String
        public var width: Int
        public var height: Int
        public init(data: Data, mediaType: String = "image/jpeg", width: Int, height: Int) {
            self.data = data; self.mediaType = mediaType; self.width = width; self.height = height
        }
    }

    public let apiKey: String?
    public var model: String
    public var useServerFallbacks = true
    private let session: URLSession

    public init(apiKey: String? = Secrets.shared.anthropicKey, model: String = LookoutConfig.model) {
        self.apiKey = apiKey
        self.model = model
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg)
    }


    /// Opens (and caches) the TLS connection before a real request needs it, so the first call after a key
    /// press doesn't pay for a cold handshake. Fire-and-forget; failures don't matter.
    /// (Approach from Clicky's ClaudeAPI.warmUpTLSConnectionIfNeeded, MIT.)
    public func warmUp() {
        var r = URLRequest(url: LookoutConfig.apiBase)
        r.httpMethod = "HEAD"
        r.timeoutInterval = 5
        session.dataTask(with: r).resume()
    }

    public var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    // MARK: Request building

    public func body(system: String, text: String, image: Image?, maxTokens: Int, effort: String?, schema: [String: Any]?, stream: Bool) -> [String: Any] {
        var content: [[String: Any]] = []
        if let image {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": text])
        var b: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        var output: [String: Any] = [:]
        if let effort { output["effort"] = effort }
        if let schema { output["format"] = ["type": "json_schema", "schema": schema] }
        if !output.isEmpty { b["output_config"] = output }
        if stream { b["stream"] = true }
        if useServerFallbacks { b["fallbacks"] = "default" }
        return b
    }

    func request(_ body: [String: Any]) throws -> URLRequest {
        guard let key = apiKey, !key.isEmpty else { throw ClientError.noKey }
        var r = URLRequest(url: LookoutConfig.apiBase.appendingPathComponent("v1/messages"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(LookoutConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if body["fallbacks"] != nil {
            r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    // MARK: Calls

    /// Non-streaming call; returns concatenated text blocks.
    public func complete(system: String, text: String, image: Image? = nil, maxTokens: Int = 2048, effort: String? = "low", schema: [String: Any]? = nil) async throws -> String {
        var b = body(system: system, text: text, image: image, maxTokens: maxTokens, effort: effort, schema: schema, stream: false)
        var (data, resp) = try await session.data(for: request(b))
        var code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400, useServerFallbacks, String(decoding: data, as: UTF8.self).contains("fallback") {
            // Older deployments may not accept server-side fallbacks; retry once without.
            b["fallbacks"] = nil
            (data, resp) = try await session.data(for: request(b))
            code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard code == 200 else { throw ClientError.http(code, String(decoding: data, as: UTF8.self)) }
        return try Self.parseText(data)
    }

    public static func parseText(_ data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.badResponse(String(decoding: data, as: UTF8.self))
        }
        if (obj["stop_reason"] as? String) == "refusal" {
            let cat = (obj["stop_details"] as? [String: Any])?["category"] as? String
            throw ClientError.refusal(cat)
        }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        return blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
    }

    /// Streaming call; yields text deltas as they arrive.
    public func stream(system: String, text: String, image: Image? = nil, maxTokens: Int = 2048, effort: String? = "low") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let b = self.body(system: system, text: text, image: image, maxTokens: maxTokens, effort: effort, schema: nil, stream: true)
                    let (bytes, resp) = try await self.session.bytes(for: self.request(b))
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code != 200 {
                        var err = ""
                        for try await line in bytes.lines { err += line; if err.count > 2000 { break } }
                        throw ClientError.http(code, err)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let d = payload.data(using: .utf8),
                              let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        switch ev["type"] as? String {
                        case "content_block_delta":
                            if let delta = ev["delta"] as? [String: Any], (delta["type"] as? String) == "text_delta",
                               let t = delta["text"] as? String {
                                continuation.yield(t)
                            }
                        case "message_delta":
                            if let delta = ev["delta"] as? [String: Any], (delta["stop_reason"] as? String) == "refusal" {
                                throw ClientError.refusal(nil)
                            }
                        case "error":
                            throw ClientError.badResponse(payload)
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Scam confirmation

    public func confirmScam(screen: ScreenContext, image: Image?, heuristicSummary: String) async throws -> ScamVerdict {
        let w = image?.width ?? 0, h = image?.height ?? 0
        var text = "On-device detector notes: \(heuristicSummary)\n"
        if let u = screen.url { text += "Address bar: \(u)\n" }
        if let a = screen.appName { text += "Front app: \(a)\n" }
        if !screen.runningApps.isEmpty { text += "Running apps: \(screen.runningApps.prefix(30).joined(separator: ", "))\n" }
        text += "Screen text (may be partial):\n\(screen.text.prefix(6000))"
        let raw = try await complete(system: Prompts.scamConfirm(imageWidth: w, imageHeight: h), text: text, image: image, maxTokens: 1200, effort: "low", schema: Prompts.scamSchema)
        return try ScamVerdict.parse(raw)
    }
}

public struct ScamVerdict: Sendable, Equatable {
    public var isScam: Bool
    public var confidence: Double
    public var scamType: String
    public var explanation: String
    public var whatToDo: String
    public var familySummary: String
    public var point: PointTags.Point?

    public init(isScam: Bool, confidence: Double, scamType: String, explanation: String, whatToDo: String, familySummary: String, point: PointTags.Point?) {
        self.isScam = isScam; self.confidence = confidence; self.scamType = scamType
        self.explanation = explanation; self.whatToDo = whatToDo; self.familySummary = familySummary; self.point = point
    }

    public static func parse(_ raw: String) throws -> ScamVerdict {
        // Be tolerant of stray prose around the JSON.
        var s = raw
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { s = String(s[a...b]) }
        guard let d = s.data(using: .utf8), let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw ClaudeClient.ClientError.badResponse(raw)
        }
        let px = (o["point_x"] as? NSNumber)?.doubleValue ?? -1
        let py = (o["point_y"] as? NSNumber)?.doubleValue ?? -1
        return ScamVerdict(
            isScam: o["is_scam"] as? Bool ?? false,
            confidence: (o["confidence"] as? NSNumber)?.doubleValue ?? 0.5,
            scamType: o["scam_type"] as? String ?? "other",
            explanation: o["explanation"] as? String ?? "",
            whatToDo: o["what_to_do"] as? String ?? "",
            familySummary: o["family_summary"] as? String ?? "",
            point: px >= 0 && py >= 0 ? PointTags.Point(x: px, y: py, label: o["point_label"] as? String) : nil
        )
    }
}
