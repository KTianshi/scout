import Foundation
import Network

/// Is the internet usable right now, and for which service?
///
/// NWPathMonitor knows when Wi-Fi is off. Venue Wi-Fi that says "connected" but drops everything (Cal Hacks)
/// only shows up as timeouts, so each service also sits out a short cool-down after it fails. While a service
/// is down, callers skip it at once and use the on-device fallback instead of waiting on another timeout.
public final class Connectivity: @unchecked Sendable {
    /// SCOUT_OFFLINE=1 pretends there is no internet (to rehearse a demo on bad Wi-Fi).
    public static let shared: Connectivity = {
        if ProcessInfo.processInfo.environment["SCOUT_OFFLINE"] == "1" {
            let c = Connectivity(monitor: false)
            c.forcedOffline = true
            c.pathOK = false
            return c
        }
        return Connectivity(monitor: true)
    }()
    private var forcedOffline = false

    public enum Service: String, Sendable { case claude, cartesia }

    private let lock = NSLock()
    private var pathOK = true
    private var downUntil: [Service: Date] = [:]
    private var lastNetworkFailure: Date?
    private var pathMonitor: NWPathMonitor?
    /// Called (on a background queue) when the OS reports the network coming or going.
    public var onPathChange: (@Sendable (Bool) -> Void)?

    /// How long a service sits out after a network failure (timeout, no route…).
    public static let networkCooldown: TimeInterval = 30
    /// After an answer like "bad key" or "out of credits": retrying every few seconds won't help.
    public static let accountCooldown: TimeInterval = 600

    public init(monitor: Bool = false) {
        guard monitor else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in self?.setPath(ok: path.status == .satisfied) }
        m.start(queue: DispatchQueue(label: "scout.connectivity"))
        pathMonitor = m
    }

    /// The OS has a route to the internet (it may still be a dead venue network).
    public var isOnline: Bool { lock.withLock { pathOK } }

    /// Wi-Fi is off, or something timed out in the last 30 s: prefer on-device paths (e.g. Apple's on-device
    /// speech recognizer) over ones that need a server.
    public func internetLooksBad(now: Date = Date()) -> Bool {
        lock.withLock { !pathOK || lastNetworkFailure.map { now.timeIntervalSince($0) < Self.networkCooldown } ?? false }
    }

    /// Worth calling this service now?
    public func isUsable(_ s: Service, now: Date = Date()) -> Bool {
        lock.withLock { pathOK && (downUntil[s].map { now >= $0 } ?? true) }
    }

    public func setPath(ok: Bool) {
        let changed: Bool = lock.withLock {
            if forcedOffline { return false }
            let c = pathOK != ok
            pathOK = ok
            // Back online: give every service a fresh try instead of waiting out old cool-downs.
            if c && ok { downUntil = [:]; lastNetworkFailure = nil }
            return c
        }
        if changed { onPathChange?(ok) }
    }

    /// Record a failed call. Network errors and server overload cool down briefly; auth/credit errors longer.
    /// Returns true if the error was one that marks the service down.
    @discardableResult
    public func reportFailure(_ s: Service, error: Error, now: Date = Date()) -> Bool {
        guard let cooldown = Self.cooldown(for: error) else { return false }
        lock.withLock {
            downUntil[s] = now.addingTimeInterval(cooldown)
            if Self.isNetworkError(error) { lastNetworkFailure = now }
        }
        return true
    }

    /// Record an HTTP answer. 401/402/403 (bad key, no credits) and 429/5xx mark the service down for a while.
    public func reportStatus(_ s: Service, code: Int, now: Date = Date()) {
        let cooldown: TimeInterval?
        switch code {
        case 200..<300: reportSuccess(s); return
        case 401, 402, 403: cooldown = Self.accountCooldown
        case 429, 500...599: cooldown = Self.networkCooldown
        default: cooldown = nil
        }
        if let cooldown { lock.withLock { downUntil[s] = now.addingTimeInterval(cooldown) } }
    }

    public func reportSuccess(_ s: Service) {
        lock.withLock { downUntil[s] = nil; lastNetworkFailure = nil }
    }

    static func cooldown(for error: Error) -> TimeInterval? {
        isNetworkError(error) ? networkCooldown : nil
    }

    /// Timeouts and "can't reach the server" errors, as opposed to a bad request or a refusal.
    public static func isNetworkError(_ error: Error) -> Bool {
        if error is DeadlineExceeded { return true }
        guard let u = error as? URLError else {
            let ns = error as NSError
            return ns.domain == NSURLErrorDomain && networkCodes.contains(URLError.Code(rawValue: ns.code))
        }
        return networkCodes.contains(u.code)
    }

    private static let networkCodes: Set<URLError.Code> = [
        .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed, .cannotLoadFromNetwork,
    ]
}

public struct DeadlineExceeded: Error, LocalizedError {
    public let seconds: Double
    public var errorDescription: String? { String(format: "No answer within %.0f s", seconds) }
}

/// Runs `op`, giving up after `seconds` (the operation is cancelled). For calls that must not hold up a
/// scam warning or a spoken answer when the network is slow.
public func withDeadline<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            throw DeadlineExceeded(seconds: seconds)
        }
        defer { g.cancelAll() }
        return try await g.next()!
    }
}
