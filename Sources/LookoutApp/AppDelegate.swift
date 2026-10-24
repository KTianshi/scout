import AppKit
import LookoutCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    let companion = Companion()
    private var statusItem: NSStatusItem!
    private var guardianItem: NSMenuItem!
    private var shortcutItems: [NSMenuItem] = []
    var openDemoOnLaunch: String?? = nil
    /// Scripted question after launch (rehearsal / testing): --ask "..."
    var askOnLaunch: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        companion.start()
        if let demo = openDemoOnLaunch { companion.openDemo(demo) }
        if let q = askOnLaunch {
            Task { try? await Task.sleep(nanoseconds: 6_000_000_000); companion.ask(q) }
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
        let sc = NSMenuItem(title: "Talk shortcut (hold)", action: nil, keyEquivalent: "")
        let scm = NSMenu()
        for s in TalkShortcut.allCases {
            let i = item(s.symbol, #selector(pickShortcut(_:)), "")
            i.representedObject = s.rawValue
            i.state = s == TalkShortcut.current ? .on : .off
            scm.addItem(i)
            shortcutItems.append(i)
        }
        sc.submenu = scm
        m.addItem(sc)
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
        m.addItem(item("Stop talking (Esc)", #selector(stopTalking), "."))
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
        // Remember what the person was looking at, so Lookout answers about that screen, not the question box.
        let previous = NSWorkspace.shared.frontmostApplication
        let demoWasFront = previous?.processIdentifier == getpid() && companion.demoBrowser.window.isVisible
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
        // Give focus back to whatever was in front before looking.
        if demoWasFront { companion.demoBrowser.show() }
        else if let previous, previous.processIdentifier != getpid() { previous.activate() }
        Task { try? await Task.sleep(nanoseconds: 400_000_000); companion.ask(q) }
    }

    @objc func explainAction() {
        companion.explain()
    }

    @objc func toggleGuardian() {
        companion.guardianEnabled.toggle()
        guardianItem.state = companion.guardianEnabled ? .on : .off
    }

    @objc func openDemoAction() { companion.openDemo() }
    @objc func openScenario(_ sender: NSMenuItem) { companion.openDemo(sender.representedObject as? String) }
    @objc func setupAction() { companion.setup.show() }
    @objc func stopTalking() { companion.stopEverything() }

    @objc func pickShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = TalkShortcut(rawValue: raw) else { return }
        TalkShortcut.current = s
        let ok = companion.registerTalkShortcut()
        for i in shortcutItems { i.state = (i.representedObject as? String) == raw ? .on : .off }
        if !ok {
            let a = NSAlert()
            a.messageText = "That shortcut is taken"
            a.informativeText = "Another app is already using \(s.symbol). Please pick a different one."
            a.runModal()
        }
    }
}
