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
        // Testing only: LOOKOUT_TEST_AUTOCLICK presses "Go back" / "Cancel the payment" after 4 s.
        if ProcessInfo.processInfo.environment["LOOKOUT_TEST_AUTOCLICK"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.isShowing else { return }
                Log.info("test autoclick: pay pause go back")
                self.model.onCancel()
            }
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
        DebugShot.take("setup")
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Set up Scout"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: SetupView(close: { [weak w] in w?.close() }).lookoutTheme())
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

/// Permissions, one at a time: one icon, one short sentence, a picture of exactly what to turn on, one button.
struct SetupView: View {
    var close: () -> Void = {}
    /// For rendering previews: force a step (0...2) or the finished state (3).
    var previewStep: Int? = nil
    @Environment(\.classic) private var classic
    @State private var tick = 0
    @State private var skipped: Set<String> = []
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    struct Step: Identifiable {
        let id: String
        var icon: String
        var pixel: PixelIcon
        var title: String
        var why: String
        var granted: Bool
        var pane: String
        /// Turned on with a switch in System Settings (false: the Mac asks with its own pop-ups).
        var inSettings = true
        /// One extra line for after System Settings opens.
        var after: String = ""
        var request: () -> Void
    }

    var steps: [Step] {
        _ = tick
        return [
            Step(id: "screen", icon: "eye", pixel: .eye, title: "Let me see your screen",
                 why: "So I can spot fake warnings and point to the right button.", granted: Permissions.screenRecording,
                 pane: "Privacy_ScreenCapture", after: "If your Mac asks, click Quit & Reopen.", request: Permissions.requestScreenRecording),
            Step(id: "ax", icon: "hand.point.up.left", pixel: .hand, title: "Let me read buttons",
                 why: "So I can point at exactly what to click.", granted: Permissions.accessibility,
                 pane: "Privacy_Accessibility", after: "Type your Mac password if asked.", request: Permissions.requestAccessibility),
            Step(id: "mic", icon: "mic", pixel: .talking, title: "Let me hear you",
                 why: "Hold \(TalkShortcut.current.spoken) and just ask.", granted: Listener.micAuthorized && Listener.speechAuthorized,
                 pane: "Privacy_Microphone", inSettings: !Listener.micUndecided,
                 request: { if Listener.micUndecided { Task { _ = await Listener.requestPermissions() } } else { Permissions.openSettings("Privacy_Microphone") } }),
        ]
    }

    /// The first step that is neither done nor skipped; nil when everything is handled.
    var current: Step? {
        if let p = previewStep { return p < steps.count ? steps[p] : nil }
        return steps.first { !$0.granted && !skipped.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(steps) { st in
                    Capsule()
                        .fill(dotColor(st))
                        .frame(width: st.id == current?.id ? 22 : 7, height: 7)
                }
            }
            .padding(.top, 34)
            .animation(.easeInOut(duration: 0.25), value: current?.id)
            .padding(.bottom, 22)

            if let st = current {
                VStack(spacing: 14) {
                    stepIcon(st.icon, pixel: st.pixel)
                        .foregroundStyle(classic ? ClassicLook.blue : Color.accentColor)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(classic ? Color.white : Color.accentColor.opacity(0.12)))
                        .overlay(Circle().stroke(classic ? ClassicLook.blue : .clear, lineWidth: 3))
                        .padding(.bottom, 6)
                    Text(st.title)
                        .lfont(24, .semibold)
                        .foregroundStyle(classic ? ClassicLook.blue : .primary)
                        .multilineTextAlignment(.center)
                    Text(st.why)
                        .lfont(17)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    howTo(st).padding(.top, 8)
                }
                .id(st.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                VStack(spacing: 14) {
                    stepIcon("checkmark", pixel: .check)
                        .foregroundStyle(.green)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(classic ? Color.white : Color.green.opacity(0.14)))
                        .overlay(Circle().stroke(classic ? Color(red: 0.24, green: 0.62, blue: 0.12) : .clear, lineWidth: 3))
                        .padding(.bottom, 6)
                    Text(skipped.isEmpty ? "You're all set" : "Ready when you are")
                        .lfont(24, .semibold)
                        .foregroundStyle(classic ? ClassicLook.blue : .primary)
                    Text(skipped.isEmpty ? "I'll stay in the corner of your screen." : "You can finish this later from the Scout menu.")
                        .lfont(17)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                if let st = current {
                    Button {
                        if st.inSettings { st.request(); Permissions.openSettings(st.pane) } else { st.request() }
                    } label: {
                        Text(st.inSettings ? "Open System Settings" : "Allow").lfont(17, .semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .lookoutButton(primary: true)
                    .keyboardShortcut(.defaultAction)
                    notNow(st)
                } else {
                    Button { close() } label: {
                        Text("Done").lfont(17, .semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .lookoutButton(primary: true)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(height: 84, alignment: .top)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 40)
        .frame(width: 440, height: 560)
        .foregroundStyle(classic ? Color.black : Color.primary)
        .background(alignment: .top) {
            if classic { ZStack(alignment: .top) { ClassicLook.face; ClassicBanner().frame(height: 108) } }
        }
        .animation(.easeInOut(duration: 0.35), value: current?.id)
        .onReceive(timer) { _ in tick += 1 }
    }

    /// Exactly what to do, as a short numbered list.
    func howTo(_ st: Step) -> some View {
        let lines = st.inSettings
            ? ["Click Open System Settings below.", "Find Scout in the list.", "Turn on the switch next to it."] + (st.after.isEmpty ? [] : [st.after])
            : ["Click Allow below.", "Your Mac asks twice: once for the microphone, once for speech.", "Click OK or Allow both times."]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").lfont(15, .semibold).frame(width: 18, alignment: .trailing)
                    Text(line).lfont(15).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func stepIcon(_ symbol: String, pixel: PixelIcon) -> some View {
        if classic { pixel.view.frame(width: 40, height: 40) }
        else { Image(systemName: symbol).font(.system(size: 30)) }
    }

    @ViewBuilder func notNow(_ st: Step) -> some View {
        let b = Button { withAnimation(.easeInOut(duration: 0.3)) { _ = skipped.insert(st.id) } } label: { Text("Not now").lfont(15) }
        if classic { b.lookoutButton(primary: false) } else { b.buttonStyle(.plain).foregroundStyle(.secondary) }
    }

    func dotColor(_ st: Step) -> Color {
        if let p = previewStep, let i = steps.firstIndex(where: { $0.id == st.id }) {
            return i < p ? .green : (i == p ? .accentColor : Color.primary.opacity(0.15))
        }
        if st.granted { return .green }
        if st.id == current?.id { return .accentColor }
        return Color.primary.opacity(0.15)
    }
}

