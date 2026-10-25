import AppKit
import ApplicationServices
import ScreenCaptureKit
import LookoutCore

/// An on-screen control we can point at. Frame is in top-left-origin global display coordinates.
struct UIElementInfo {
    var role: String
    var label: String
    var frame: CGRect
}

/// Everything observed in one pass.
struct Snapshot {
    var context: ScreenContext
    /// JPEG sent to Claude, and its pixel size.
    var image: ClaudeClient.Image?
    /// Maps image pixels → top-left global display points.
    var imageToScreen: CGAffineTransform = .identity
    var elements: [UIElementInfo] = []
    /// When the snapshot came from Lookout's own demo browser, threat rects are known exactly.
    var knownThreatRects: [String: CGRect] = [:]
    var knownTargetRects: [String: CGRect] = [:]
    var isFixture = false

    func screenPoint(forImagePoint p: CGPoint) -> CGPoint { p.applying(imageToScreen) }

    /// Snap a point to the control the model meant. Prefers a nearby control whose name matches `label`
    /// (e.g. "Attach files"), then the smallest control under the point, then the closest small one.
    /// Big containers (toolbars, rows, panes) are never chosen: highlighting them points at nothing.
    func snap(_ p: CGPoint, label: String? = nil, within radius: CGFloat = 48) -> (CGPoint, UIElementInfo?) {
        // Text boxes are often wide (a chat's message field), so they get a bigger size limit than buttons.
        let fields: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSecureTextField"]
        let controls = elements.filter { e in
            let big = fields.contains(e.role)
            return e.frame.width > 4 && e.frame.height > 4 && e.frame.width < (big ? 1600 : 320) && e.frame.height < (big ? 400 : 140)
        }
        func center(_ e: UIElementInfo) -> CGPoint { CGPoint(x: e.frame.midX, y: e.frame.midY) }
        func dist(_ e: UIElementInfo) -> CGFloat {
            e.frame.insetBy(dx: -6, dy: -6).contains(p) ? 0 : hypot(center(e).x - p.x, center(e).y - p.y)
        }
        // Claude copied a control's center from the list: that's the control it means, whatever it's called.
        // (Screen points; the list's pixel centers map back to within a couple of points.)
        if let e = controls.filter({ hypot(center($0).x - p.x, center($0).y - p.y) <= 3 })
            .min(by: { hypot(center($0).x - p.x, center($0).y - p.y) < hypot(center($1).x - p.x, center($1).y - p.y) }) {
            return (center(e), e)
        }
        if let label, label.count >= 3 {
            let words = label.lowercased().split(separator: " ").filter { $0.count >= 4 }
            // An exact name is strong evidence, so size limits don't apply (file rows and menu items are wide).
            let named = elements.filter { $0.frame.width > 4 && $0.frame.height > 4 && $0.frame.height < 200 }.filter { e in
                let l = e.label.lowercased()
                return l.contains(label.lowercased()) || words.contains { l.contains($0) }
            }
            if let e = named.filter({ dist($0) <= radius * 3 }).min(by: { dist($0) < dist($1) }) { return (center(e), e) }
        }
        // The model named something we couldn't match: its own point is better than any nearby control.
        // Geometry alone picks wrong ones: the nearest ("Recipients" became "Subject"), or one hidden under a
        // window (Gmail's Compose button sits beneath the compose window, and won over the To field).
        if label != nil { return (p, nil) }
        let area = { (e: UIElementInfo) in e.frame.width * e.frame.height }
        if let e = controls.filter({ dist($0) == 0 }).min(by: { area($0) < area($1) }) { return (center(e), e) }
        if let e = controls.filter({ dist($0) <= radius }).min(by: { dist($0) < dist($1) }) { return (center(e), e) }
        return (p, nil)
    }

    /// Find the element whose label contains `text` (e.g. the phone number the detector flagged).
    func element(matching text: String) -> UIElementInfo? {
        let needle = text.lowercased()
        guard needle.count >= 3 else { return nil }
        return elements.first { $0.label.lowercased().contains(needle) }
    }
}

enum Permissions {
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings(_ pane: String) {
        // pane: Privacy_ScreenCapture, Privacy_Accessibility, Privacy_Microphone, Privacy_SpeechRecognition
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(u)
        }
    }
}

@MainActor
final class ScreenObserver {
    /// Live snapshot of the main display + frontmost window. Missing permissions degrade gracefully.
    /// The display to capture (where Lookout is); nil means the main display.
    var displayID: CGDirectDisplayID?

    func snapshot(includeImage: Bool, fast: Bool = false) async -> Snapshot {
        let front = NSWorkspace.shared.frontmostApplication
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        var ctx = ScreenContext(text: "", appName: front?.localizedName, runningApps: running)
        var snap = Snapshot(context: ctx)

        if Permissions.accessibility, let pid = front?.processIdentifier, pid != getpid() {
            let ax = AXReader(pid: pid)
            let r = ax.read(timeBudget: fast ? 0.7 : nil)
            ctx.text = r.text
            ctx.windowTitle = r.windowTitle
            ctx.url = r.url
            ctx.sensitiveFields = r.sensitive
            snap.elements = r.elements
        }
        snap.context = ctx

        if includeImage, Permissions.screenRecording, let (img, xf) = await captureMainDisplay() {
            snap.image = img
            snap.imageToScreen = xf
        }
        return snap
    }

    /// ScreenCaptureKit screenshot of the main display without Lookout's own windows.
    func captureMainDisplay() async -> (ClaudeClient.Image, CGAffineTransform)? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let wanted = displayID ?? CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else { return nil }
            let mine = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            let maxEdge = LookoutConfig.screenshotMaxEdge
            // display.width is in points; go up to the Retina pixel density so small icons stay legible.
            let density = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }?.backingScaleFactor ?? 1
            let scale = min(density, maxEdge / CGFloat(max(display.width, display.height)))
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.showsCursor = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            guard let jpeg = ImageUtil.jpeg(cg, quality: 0.72) else { return nil }
            let bounds = CGDisplayBounds(display.displayID)
            let sx = bounds.width / CGFloat(cg.width), sy = bounds.height / CGFloat(cg.height)
            let xf = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: bounds.minX, ty: bounds.minY)
            return (ClaudeClient.Image(data: jpeg, width: cg.width, height: cg.height), xf)
        } catch {
            Log.info("capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}

enum ImageUtil {
    /// Downscale so the longest edge is at most `maxEdge` pixels.
    static func downscale(_ cg: CGImage, maxEdge: CGFloat) -> CGImage {
        let k = maxEdge / CGFloat(max(cg.width, cg.height))
        guard k < 1 else { return cg }
        let w = Int(CGFloat(cg.width) * k), h = Int(CGFloat(cg.height) * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    static func jpeg(_ cg: CGImage, quality: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Small thumbnail data URL for the family feed.
    static func thumbnailDataURL(_ jpeg: Data, maxEdge: CGFloat = 640) -> String? {
        guard let img = NSImage(data: jpeg) else { return nil }
        let s = img.size
        let k = min(1, maxEdge / max(s.width, s.height))
        let size = NSSize(width: s.width * k, height: s.height * k)
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return nil }
        return "data:image/jpeg;base64," + d.base64EncodedString()
    }
}

/// Walks the Accessibility tree of the frontmost window: visible text, actionable elements, URL, secure fields.
struct AXReader {
    let pid: pid_t
    struct Result { var text = ""; var windowTitle: String?; var url: String?; var elements: [UIElementInfo] = []; var sensitive: [String] = [] }

    func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    func str(_ e: AXUIElement, _ name: String) -> String? {
        if let s = attr(e, name) as? String { return s }
        if let u = attr(e, name) as? URL { return u.absoluteString }
        return nil
    }
    func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    /// `timeBudget` (help only): stop walking after this long. The guardian reads everything (scam text can be deep).
    func read(maxNodes: Int = 2500, timeBudget: TimeInterval? = nil) -> Result {
        var r = Result()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        // Chrome / Electron only expose web content when asked.
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let win = attr(app, kAXFocusedWindowAttribute) else { return r }
        let w = win as! AXUIElement
        r.windowTitle = str(w, kAXTitleAttribute)
        var lines: [String] = []
        var seen = Set<String>()
        var queue: [AXUIElement] = [w]
        var visited = 0
        let actionable: Set<String> = ["AXButton", "AXLink", "AXTextField", "AXSecureTextField", "AXMenuItem", "AXCheckBox", "AXPopUpButton", "AXTab", "AXRadioButton", "AXComboBox", "AXTextArea", "AXImage", "AXStaticText"]
        // Time budget as well as a node cap: huge lists (a Finder folder, a long inbox) took 2+ s to walk.
        // Breadth-first means the window's toolbars and visible controls come first; the screenshot covers the rest.
        let deadline = Date().addingTimeInterval(timeBudget ?? .infinity)
        while !queue.isEmpty && visited < maxNodes && (visited % 50 != 0 || Date() < deadline) {
            let e = queue.removeFirst()
            visited += 1
            let role = str(e, kAXRoleAttribute) ?? ""
            if role == "AXWebArea", r.url == nil { r.url = str(e, "AXURL") }
            if r.url == nil, role == "AXTextField", let d = str(e, kAXDescriptionAttribute), d.lowercased().contains("address") {
                r.url = str(e, kAXValueAttribute)
            }
            let value = role == "AXSecureTextField" ? nil : str(e, kAXValueAttribute)
            let title = str(e, kAXTitleAttribute)
            let desc = str(e, kAXDescriptionAttribute)
            let placeholder = str(e, "AXPlaceholderValue")
            let label = [title, desc, value, placeholder].compactMap { $0 }.filter { !$0.isEmpty }.first ?? ""
            for t in [title, desc, value, placeholder].compactMap({ $0 }) where !t.isEmpty && t.count < 2000 {
                if seen.insert(t).inserted { lines.append(t) }
            }
            if role == "AXSecureTextField" { r.sensitive.append("password") }
            if role == "AXTextField" {
                let l = label.lowercased()
                if l.contains("card number") || l.contains("cvv") || l.contains("cvc") { r.sensitive.append("card") }
                if l.contains("gift card") || l.contains("pin") && l.contains("card") { r.sensitive.append("gift-card") }
                if l.contains("social security") || l.contains("ssn") { r.sensitive.append("ssn") }
                if l.contains("routing") || l.contains("account number") { r.sensitive.append("bank") }
            }
            if actionable.contains(role), let f = frame(e), !label.isEmpty {
                r.elements.append(UIElementInfo(role: role, label: label, frame: f))
            }
            if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: kids) }
        }
        r.text = lines.joined(separator: "\n")
        r.sensitive = Array(Set(r.sensitive))
        return r
    }
}
