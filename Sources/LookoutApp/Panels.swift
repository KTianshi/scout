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
        p.hasShadow = true
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

    var accent: Color { alarmed ? Color(red: 0.93, green: 0.48, blue: 0.1) : Color(red: 0.2, green: 0.5, blue: 0.9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: alarmed ? "exclamationmark.shield.fill" : "hand.wave.fill")
                    .font(.system(size: 28)).foregroundStyle(accent)
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Color(white: 0.08))
            }
            Text(message).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(Color(white: 0.15))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ForEach(buttons) { b in
                    SwiftUI.Button(action: b.action) {
                        Text(b.title).font(.system(size: 20, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .frame(minWidth: 150)
                            .foregroundStyle(b.primary ? .white : Color(white: 0.1))
                            .background(RoundedRectangle(cornerRadius: 14).fill(b.primary ? accent : Color(white: 0.9)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(accent, lineWidth: 3))
        .padding(6)
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
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
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
    enum Status { case waiting, approved, denied, offline }
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
            Color(red: 0.06, green: 0.12, blue: 0.22).opacity(0.86).ignoresSafeArea()
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
                        Text(model.status == .denied ? "OK, close this" : "Cancel the payment")
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
                if model.status == .waiting || model.status == .offline {
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
        case .waiting, .offline: return "Let's check with \(model.familyName) first"
        case .approved: return "\(model.familyName) says it's OK"
        case .denied: return "\(model.familyName) says please stop"
        }
    }

    var subline: String {
        switch model.status {
        case .waiting: return "\(model.reason)\nI've sent \(model.familyName) a message. Take a slow breath. We'll wait together."
        case .offline: return "\(model.reason)\nI couldn't reach \(model.familyName). Please call them on a number you know."
        case .approved: return "You can go ahead now."
        case .denied: return "This payment isn't safe. Nothing has been sent. You did the right thing by pausing."
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
                 why: "Hold Option and Space, then just talk to me.", granted: Listener.micAuthorized && Listener.speechAuthorized,
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
