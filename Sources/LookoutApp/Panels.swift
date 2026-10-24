import AppKit
import SwiftUI
import LookoutCore

/// A floating, clickable card with big buttons (the overlay itself is click-through).
@MainActor
final class ActionCard {
    private var panel: NSPanel?

    struct Button { var title: String; var primary: Bool; var action: () -> Void }

    func show(title: String, message: String, alarmed: Bool, buttons: [Button], near: CGPoint? = nil) {
        hide()
        let view = ActionCardView(title: title, message: message, alarmed: alarmed, buttons: buttons.map { b in
            ActionCardView.Item(title: b.title, primary: b.primary) { [weak self] in self?.hide(); b.action() }
        })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The card draws its own soft shadow; the system one traces the transparent padding as a jagged outline.
        p.hasShadow = false
        p.contentView = host
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let size = host.fittingSize
        // Put the card in the bottom corner farthest from the buddy so it never covers the speech bubble.
        let buddyX = near?.x ?? vf.midX
        let x = buddyX > vf.midX ? vf.minX + 32 : vf.maxX - size.width - 32
        p.setFrameOrigin(NSPoint(x: x, y: vf.minY + 40))
        p.orderFrontRegardless()
        panel = p
        // Testing only: LOOKOUT_TEST_AUTOCLICK=primary|secondary presses a button after 3 s.
        if let auto = ProcessInfo.processInfo.environment["LOOKOUT_TEST_AUTOCLICK"], !buttons.isEmpty {
            let b = auto == "secondary" && buttons.count > 1 ? buttons[1] : buttons[0]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak p] in
                guard let self, let p, self.panel === p else { return }
                Log.info("test autoclick: \(b.title)")
                self.hide(); b.action()
            }
        }
    }

    func hide() { panel?.orderOut(nil); panel = nil }
    var isShowing: Bool { panel != nil }
}

struct ActionCardView: View {
    struct Item: Identifiable { let id = UUID(); var title: String; var primary: Bool; var action: () -> Void }
    var title: String
    var message: String
    var alarmed: Bool
    var buttons: [Item]

    var accent: Color { alarmed ? Color(red: 0.90, green: 0.45, blue: 0.08) : Color(red: 0.16, green: 0.47, blue: 0.90) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: alarmed ? "shield.lefthalf.filled" : "hand.wave.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.12)))
                Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(white: 0.08))
            }
            Text(message).font(.system(size: 16)).foregroundStyle(Color(white: 0.25))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(buttons) { b in
                    SwiftUI.Button(action: b.action) {
                        Text(b.title).font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(b.primary ? .white : Color(white: 0.15))
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(b.primary ? accent : Color(white: 0.94)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .padding(24)
    }
}

// MARK: - Pause before you pay

@MainActor
final class PayPauseScreen {
    private var windows: [NSWindow] = []
    let model = PayPauseModel()

    func show(familyName: String, reason: String, onCancel: @escaping () -> Void, onOverride: @escaping () -> Void) {
        hide()
        model.familyName = familyName
        model.reason = reason
        model.status = .waiting
        model.onCancel = { [weak self] in self?.hide(); onCancel() }
        model.onOverride = { [weak self] in self?.hide(); onOverride() }
        for screen in NSScreen.screens {
            let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: PayPauseView(model: model))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() { windows.forEach { $0.orderOut(nil) }; windows.removeAll() }
    var isShowing: Bool { !windows.isEmpty }
}

@MainActor
final class PayPauseModel: ObservableObject {
    enum Status { case waiting, approved, denied, offline, selfPause }
    @Published var familyName = "Sarah"
    @Published var reason = ""
    @Published var status: Status = .waiting
    @Published var note: String?
    var onCancel: () -> Void = {}
    var onOverride: () -> Void = {}
}

struct PayPauseView: View {
    @ObservedObject var model: PayPauseModel
    @State private var breathe = false
    @State private var confirmOverride = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.12, blue: 0.22).opacity(0.94).ignoresSafeArea()
            VStack(spacing: 28) {
                Circle()
                    .fill(Color(red: 0.35, green: 0.66, blue: 0.98).opacity(0.85))
                    .frame(width: 120, height: 120)
                    .scaleEffect(breathe ? 1.12 : 0.9)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: breathe)
                    .overlay(Image(systemName: "hand.raised.fill").font(.system(size: 50)).foregroundStyle(.white))
                Text(headline).font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subline).font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center).frame(maxWidth: 900)
                if let note = model.note, !note.isEmpty {
                    Text("“\(note)” — \(model.familyName)").font(.system(size: 24, weight: .regular, design: .rounded).italic())
                        .foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 20) {
                    Button(action: model.onCancel) {
                        Text(model.status == .denied ? "OK, close this" : model.status == .selfPause ? "Go back" : "Cancel the payment")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 34).padding(.vertical, 18)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                            .foregroundStyle(Color(red: 0.06, green: 0.12, blue: 0.22))
                    }.buttonStyle(.plain)
                    if model.status == .approved {
                        Button(action: model.onOverride) {
                            Text("Continue").font(.system(size: 26, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 34).padding(.vertical, 18)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.25, green: 0.74, blue: 0.52)))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }
                }
                if model.status == .waiting || model.status == .offline || model.status == .selfPause {
                    Button(confirmOverride ? "Tap again if you're sure it's safe" : "I'm sure — continue anyway") {
                        if confirmOverride { model.onOverride() } else { confirmOverride = true }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 18, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(60)
        }
        .onAppear { breathe = true }
    }

    var headline: String {
        switch model.status {
        case .selfPause: return "Let's slow down for a moment"
        case .waiting, .offline: return "Let's check with \(model.familyName) first"
        case .approved: return "\(model.familyName) says it's OK"
        case .denied: return "\(model.familyName) says please stop"
        }
    }

    var subline: String {
        switch model.status {
        case .selfPause: return "\(model.reason)\nTake a slow breath. A real company will never rush you, and nobody can make you pay right now."
        case .waiting: return "\(model.reason)\nI've sent \(model.familyName) a message. Take a slow breath. We'll wait together."
        case .offline: return "\(model.reason)\nI couldn't reach \(model.familyName). Please call them on a number you know."
        case .approved: return "You can go ahead now."
        case .denied: return "This isn't safe. Nothing has been sent. You did the right thing by pausing."
        }
    }
}

// MARK: - Setup / permissions

@MainActor
final class SetupWindow {
    private var window: NSWindow?
    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Set up Lookout"
        w.contentView = NSHostingView(rootView: SetupView())
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

struct SetupView: View {
    @State private var tick = 0
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    struct Item: Identifiable {
        let id: String
        var icon: String
        var title: String
        var why: String
        var granted: Bool
        var pane: String
        var request: () -> Void
    }

    var items: [Item] {
        _ = tick
        return [
            Item(id: "screen", icon: "rectangle.dashed.badge.record", title: "See your screen",
                 why: "So I can spot fake warnings and show you where to click.", granted: Permissions.screenRecording,
                 pane: "Privacy_ScreenCapture", request: Permissions.requestScreenRecording),
            Item(id: "ax", icon: "hand.point.up.left.fill", title: "Read buttons and text",
                 why: "So I can point at the exact button you need.", granted: Permissions.accessibility,
                 pane: "Privacy_Accessibility", request: Permissions.requestAccessibility),
            Item(id: "mic", icon: "mic.fill", title: "Hear your questions",
                 why: "Hold \(TalkShortcut.current.spoken), then just talk to me.", granted: Listener.micAuthorized && Listener.speechAuthorized,
                 pane: "Privacy_Microphone", request: { Task { _ = await Listener.requestPermissions() } }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Hi! I'm Lookout.").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("I need your OK for three things. Click each blue button, then switch Lookout on in the window that opens.")
                .font(.system(size: 22, design: .rounded)).foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack(spacing: 18) {
                    Image(systemName: item.icon).font(.system(size: 34)).frame(width: 56)
                        .foregroundStyle(item.granted ? .green : .blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(item.why).font(.system(size: 18, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.granted {
                        Label("Done", systemImage: "checkmark.circle.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.green)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold)).foregroundStyle(.blue)
                            Button("Allow") { item.request(); Permissions.openSettings(item.pane) }
                                .font(.system(size: 20, weight: .semibold)).controlSize(.large).buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.1)))
            }
            Text("Tip: after switching on Screen Recording, macOS may ask you to quit and reopen Lookout. That's normal.")
                .font(.system(size: 17, design: .rounded)).foregroundStyle(.secondary)
            Text("Even without these, you can try the demo from the Lookout menu at the top of your screen.")
                .font(.system(size: 17, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(width: 760)
        .onReceive(timer) { _ in tick += 1 }
    }
}
