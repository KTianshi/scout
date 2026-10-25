import AppKit
import LookoutCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    let companion = Companion()
    private var statusItem: NSStatusItem!
    private var guardianItem: NSMenuItem!
    private var visibleItem: NSMenuItem!
    var openDemoOnLaunch: String?? = nil
    /// Scripted question after launch (rehearsal / testing): --ask "..."
    var askOnLaunch: String?
    var openSettingsOnLaunch = false
    var openAskOnLaunch = false
    let askPanel = AskPanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        buildMainMenu()
        if let icon = AppIconView.image() { NSApp.applicationIconImage = icon }
        companion.start()
        if let demo = openDemoOnLaunch { companion.openDemo(demo); NSApp.activate(ignoringOtherApps: true) }
        if openSettingsOnLaunch { companion.settings.show() }
        if openAskOnLaunch { askTyped() }
        if let q = askOnLaunch {
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                // Scripted runs ask about the demo page when there is one, so bring it to the front first.
                if openDemoOnLaunch != nil { companion.demoBrowser.show(); NSApp.activate(ignoringOtherApps: true) }
                try? await Task.sleep(nanoseconds: 500_000_000)
                companion.ask(q)
            }
        }
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "pawprint.circle.fill", accessibilityDescription: "Scout")
            b.image?.isTemplate = true
        }
        let m = NSMenu()
        m.addItem(item("Ask Scout…", #selector(askTypedAction), "l"))
        m.addItem(item("Explain what's on screen", #selector(explainAction), "e"))
        m.addItem(.separator())
        guardianItem = item("Watching for scams", #selector(toggleGuardian), "")
        guardianItem.state = .on
        m.addItem(guardianItem)
        visibleItem = item("Show Scout on my screen", #selector(toggleVisible(_:)), "")
        visibleItem.state = companion.overlay.state.visible ? .on : .off
        m.addItem(visibleItem)
        m.addItem(item("Settings…", #selector(settingsAction), ","))
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
        m.addItem(item("Quit Scout", #selector(NSApplication.terminate(_:)), "q"))
        statusItem.menu = m
    }

    func item(_ t: String, _ s: Selector, _ k: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        return i
    }

    @objc func askTypedAction() { askTyped() }

    func askTyped() {
        // The box doesn't take focus from the app the person was using, so Scout answers about that screen.
        let demoWasFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() && companion.demoBrowser.window.isVisible
        companion.prepareForQuestion()
        askPanel.show { [weak self] q in
            guard let self else { return }
            if demoWasFront { self.companion.demoBrowser.show() }
            Task { try? await Task.sleep(nanoseconds: 150_000_000); self.companion.ask(q) }
        }
    }

    @objc func explainAction() {
        companion.explain()
    }

    @objc func toggleGuardian() { setGuardian(!companion.guardianEnabled) }

    @objc func openDemoAction() { companion.openDemo() }
    @objc func openScenario(_ sender: NSMenuItem) { companion.openDemo(sender.representedObject as? String) }
    @objc func setupAction() { companion.setup.show() }
    @objc func stopTalking() { companion.stopEverything() }

    @objc func settingsAction() { companion.settings.show() }

    /// Opening Scout again (Spotlight, Launchpad, Finder) while it's running, or clicking its Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        companion.settings.show()
        return false
    }

    /// The app menu shown while Scout is in front (it has a Dock icon).
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let am = NSMenu()
        am.addItem(item("Settings…", #selector(settingsAction), ","))
        am.addItem(item("Ask Scout…", #selector(askTypedAction), "l"))
        am.addItem(.separator())
        am.addItem(NSMenuItem(title: "Hide Scout", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        am.addItem(NSMenuItem(title: "Quit Scout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = am
        main.addItem(appItem)
        // Standard Edit menu so ⌘C/⌘V work in text fields (names in Settings, the Ask box).
        let editItem = NSMenuItem()
        let em = NSMenu(title: "Edit")
        em.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        em.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        em.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        em.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = em
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let wm = NSMenu(title: "Window")
        wm.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = wm
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc func toggleVisible(_ sender: NSMenuItem) {
        setVisible(!companion.overlay.state.visible)
    }

    /// From Settings or the menu: show or hide the resting buddy.
    func setVisible(_ on: Bool) {
        companion.overlay.state.visible = on
        visibleItem.state = on ? .on : .off
    }

    /// From Settings: keep the menu check mark in sync.
    func setGuardian(_ on: Bool) {
        companion.guardianEnabled = on
        guardianItem.state = on ? .on : .off
    }
}
