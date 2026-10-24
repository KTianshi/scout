import AppKit
import LookoutCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    let companion = Companion()
    private var statusItem: NSStatusItem!
    private var guardianItem: NSMenuItem!
    var openDemoOnLaunch: String?? = nil
    /// Scripted question after launch (rehearsal / testing): --ask "..."
    var askOnLaunch: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        companion.start()
        if let demo = openDemoOnLaunch { companion.openDemo(demo) }
        if let q = askOnLaunch {
            Task { try? await Task.sleep(nanoseconds: 6_000_000_000); await companion.handleUtterance(q) }
        }
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "Lookout")
            b.image?.isTemplate = true
        }
        let m = NSMenu()
        m.addItem(item("Ask Lookout…", #selector(askTypedAction), "l"))
        m.addItem(item("Explain what's on screen", #selector(explainAction), "e"))
        m.addItem(.separator())
        guardianItem = item("Watching for scams", #selector(toggleGuardian), "")
        guardianItem.state = .on
        m.addItem(guardianItem)
        m.addItem(.separator())
        let demo = NSMenuItem(title: "Demo", action: nil, keyEquivalent: "")
        let dm = NSMenu()
        dm.addItem(item("Open demo browser", #selector(openDemoAction), "d"))
        for (title, file) in [
            ("Help: attach a PDF", "email-attach.html"), ("Help: Medicare letter", "medicare-letter.html"),
            ("Scam: fake Microsoft pop-up", "tech-support.html"), ("Scam: IRS gift cards", "irs-gift-card.html"),
            ("Scam: grandson in jail", "grandchild-jail.html"), ("Scam: fake bank login", "bank-login.html"),
            ("Scam: refund + AnyDesk", "refund-anydesk.html"), ("Scam: crypto investment", "crypto-investment.html"),
            ("Safe: gift card for grandkid", "amazon-gift-card.html"), ("Safe: bank statement", "bank-statement.html"),
        ] {
            let i = item(title, #selector(openScenario(_:)), "")
            i.representedObject = file
            dm.addItem(i)
        }
        demo.submenu = dm
        m.addItem(demo)
        m.addItem(item("Set up permissions…", #selector(setupAction), ""))
        m.addItem(item("Stop talking", #selector(stopTalking), "."))
        m.addItem(.separator())
        m.addItem(item("Quit Lookout", #selector(NSApplication.terminate(_:)), "q"))
        statusItem.menu = m
    }

    func item(_ t: String, _ s: Selector, _ k: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        return i
    }

    @objc func askTypedAction() { askTyped() }

    func askTyped() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "What can I help with?"
        a.informativeText = "Type your question, like “How do I attach this PDF?”"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 28))
        f.font = .systemFont(ofSize: 17)
        a.accessoryView = f
        a.addButton(withTitle: "Ask")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let q = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Give focus back to whatever was in front (e.g. the demo browser) before looking.
        if companion.demoBrowser.window.isVisible { companion.demoBrowser.show() }
        Task { try? await Task.sleep(nanoseconds: 300_000_000); await companion.handleUtterance(q) }
    }

    @objc func explainAction() {
        if companion.demoBrowser.window.isVisible { companion.demoBrowser.show() }
        Task { await companion.explainScreen() }
    }

    @objc func toggleGuardian() {
        companion.guardianEnabled.toggle()
        guardianItem.state = companion.guardianEnabled ? .on : .off
    }

    @objc func openDemoAction() { companion.openDemo() }
    @objc func openScenario(_ sender: NSMenuItem) { companion.openDemo(sender.representedObject as? String) }
    @objc func setupAction() { companion.setup.show() }
    @objc func stopTalking() { companion.speech.stop(); companion.overlay.reset(); companion.card.hide() }
}
