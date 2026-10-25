import AppKit
import WebKit
import LookoutCore

/// Scout's own little browser window for demo scenarios and fixture mode.
/// Reading the DOM directly gives exact text and element positions with no TCC permissions,
/// so the demo works even before Screen Recording / Accessibility are granted.
@MainActor
final class DemoBrowser: NSObject, WKNavigationDelegate, NSWindowDelegate {
    let window: NSWindow
    let web: WKWebView
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private(set) var currentFile: URL?
    var onNavigate: ((URL) -> Void)?
    var onClose: (() -> Void)?

    static let contentSize = NSSize(width: 1280, height: 800)

    init(visible: Bool) {
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(origin: .zero, size: Self.contentSize), configuration: cfg)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                          styleMask: visible ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless],
                          backing: .buffered, defer: false)
        super.init()
        web.navigationDelegate = self
        window.delegate = self
        window.contentView = web
        window.title = "Scout Demo Browser"
        window.isReleasedWhenClosed = false
        if visible {
            window.center()
        } else {
            // Off-screen but still rendered.
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderBack(nil)
        }
    }

    func show() {
        // Float above other apps so the demo page is reliably "the screen" Scout points at.
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func load(_ file: URL) async {
        currentFile = file
        await withCheckedContinuation { c in
            loadWaiter = c
            web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent().deletingLastPathComponent())
        }
        // Let animations/layout settle.
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadWaiter?.resume(); self.loadWaiter = nil
            if let u = webView.url { self.onNavigate?(u) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loadWaiter?.resume(); self.loadWaiter = nil }
    }

    static let extractJS = """
    (() => {
      const meta = n => (document.querySelector(`meta[name="${n}"]`) || {}).content || null;
      const rect = el => { const r = el.getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; };
      const label = el => (el.getAttribute('aria-label') || el.innerText || el.value || el.placeholder || el.title || '').trim().slice(0, 200);
      const threats = {}; document.querySelectorAll('[data-lookout-threat]').forEach(el => { threats[el.getAttribute('data-lookout-threat')] = rect(el); });
      const targets = {}; document.querySelectorAll('[data-lookout-target]').forEach(el => { targets[el.getAttribute('data-lookout-target')] = rect(el); });
      const sensitive = [...new Set([...document.querySelectorAll('[data-lookout-sensitive]')].map(el => el.getAttribute('data-lookout-sensitive')))];
      if (document.querySelector('input[type=password]') && !sensitive.includes('password')) sensitive.push('password');
      const els = [...document.querySelectorAll('button, a, input, textarea, select, [role=button], [data-lookout-threat], [data-lookout-target]')]
        .filter(el => { const r = el.getBoundingClientRect(); return r.width > 2 && r.height > 2 && r.bottom > 0 && r.top < innerHeight; })
        .slice(0, 400).map(el => ({ role: el.tagName.toLowerCase(), label: label(el), rect: rect(el) }));
      return JSON.stringify({ text: document.body.innerText, title: document.title, url: meta('lookout-url'), app: meta('lookout-app'),
        label: meta('lookout-label'), ignore: !!meta('lookout-ignore'), threats, targets, sensitive, els, w: innerWidth, h: innerHeight });
    })()
    """

    struct PageInfo {
        var context: ScreenContext
        var label: String?
        var threats: [String: CGRect]
        var targets: [String: CGRect]
        var elements: [UIElementInfo]
    }

    /// Reads the page; rects are in CSS pixels of the viewport (top-left origin).
    func readPage(runningApps: [String]) async -> PageInfo? {
        guard let raw = try? await web.evaluateJavaScript(Self.extractJS) as? String,
              let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        func r(_ a: Any?) -> CGRect? {
            guard let a = a as? [NSNumber], a.count == 4 else { return nil }
            return CGRect(x: a[0].doubleValue, y: a[1].doubleValue, width: a[2].doubleValue, height: a[3].doubleValue)
        }
        var threats: [String: CGRect] = [:], targets: [String: CGRect] = [:]
        for (k, v) in (o["threats"] as? [String: Any] ?? [:]) { threats[k] = r(v) }
        for (k, v) in (o["targets"] as? [String: Any] ?? [:]) { targets[k] = r(v) }
        let els: [UIElementInfo] = (o["els"] as? [[String: Any]] ?? []).compactMap { e in
            guard let rect = r(e["rect"]) else { return nil }
            return UIElementInfo(role: e["role"] as? String ?? "", label: e["label"] as? String ?? "", frame: rect)
        }
        // Pages marked lookout-ignore (the demo launcher) are invisible to the guardian.
        let ignore = o["ignore"] as? Bool ?? false
        let ctx = ScreenContext(
            text: ignore ? "" : o["text"] as? String ?? "",
            url: o["url"] as? String,
            appName: o["app"] as? String ?? "Scout Demo Browser",
            windowTitle: o["title"] as? String,
            runningApps: runningApps,
            sensitiveFields: o["sensitive"] as? [String] ?? []
        )
        return PageInfo(context: ctx, label: o["label"] as? String, threats: threats, targets: targets, elements: els)
    }

    func snapshotJPEG() async -> (Data, Int, Int)? {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = web.bounds
        guard let img = try? await web.takeSnapshot(configuration: cfg),
              let full = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let cg = ImageUtil.downscale(full, maxEdge: 1280)
        guard let jpeg = ImageUtil.jpeg(cg, quality: 0.75) else { return nil }
        return (jpeg, cg.width, cg.height)
    }

    /// Web-view point (CSS px, top-left) → global top-left display point.
    func toScreenTopLeft(_ p: CGPoint) -> CGPoint {
        let inWindow = web.convert(NSPoint(x: p.x, y: p.y), to: nil) // web view is flipped
        let onScreen = window.convertPoint(toScreen: inWindow)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: onScreen.x, y: primaryHeight - onScreen.y)
    }

    func toScreenTopLeft(_ r: CGRect) -> CGRect {
        let a = toScreenTopLeft(r.origin)
        let b = toScreenTopLeft(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Full snapshot in the same shape as live capture, with coordinates mapped to the screen.
    func snapshot(runningApps: [String], includeImage: Bool, mapToScreen: Bool) async -> Snapshot? {
        guard let page = await readPage(runningApps: runningApps) else { return nil }
        var snap = Snapshot(context: page.context)
        snap.isFixture = true
        let map: (CGRect) -> CGRect = { mapToScreen ? self.toScreenTopLeft($0) : $0 }
        snap.elements = page.elements.map { UIElementInfo(role: $0.role, label: $0.label, frame: map($0.frame)) }
        snap.knownThreatRects = page.threats.mapValues(map)
        snap.knownTargetRects = page.targets.mapValues(map)
        if includeImage, let (jpeg, w, h) = await snapshotJPEG() {
            snap.image = ClaudeClient.Image(data: jpeg, width: w, height: h)
            let sx = web.bounds.width / CGFloat(w), sy = web.bounds.height / CGFloat(h)
            if mapToScreen {
                let o = toScreenTopLeft(CGPoint.zero)
                snap.imageToScreen = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: o.x, ty: o.y)
            } else {
                snap.imageToScreen = CGAffineTransform(scaleX: sx, y: sy)
            }
        }
        return snap
    }

    func close() { window.orderOut(nil) }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.onClose?() }
    }
}
