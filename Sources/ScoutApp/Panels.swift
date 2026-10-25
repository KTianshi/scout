import AppKit
import SwiftUI
import ScoutCore

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
        // Testing only: SCOUT_TEST_AUTOCLICK=primary|secondary presses a button after 3 s.
        if let auto = ProcessInfo.processInfo.environment["SCOUT_TEST_AUTOCLICK"], !buttons.isEmpty {
            let b = auto == "secondary" && buttons.count > 1 ? buttons[1] : buttons[0]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak p] in
                guard let self, let p, self.panel === p else { return }
                Log.info("test autoclick: \(b.title)")
                self.hide(); b.action()
            }
        }
    }

    func hide() { WindowRetirement.retire(panel); panel = nil }
    var isShowing: Bool { panel != nil }
}

/// Hides a window now but frees it a moment later. The cards' buttons close their own window: freeing it
/// while SwiftUI is still dispatching that click left SwiftUI reading a dead window and crashed Scout
/// (EXC_BAD_ACCESS inside MainActor.assumeIsolated in _ButtonGesture, right after "Yes, please").
@MainActor
enum WindowRetirement {
    static func retire(_ w: NSWindow?) {
        guard let w else { return }
        w.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { w.contentView = nil; _ = w }
    }
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

    func show(familyName: String, reason: String, explanation: String = "", sender: SenderCheck? = nil,
              onCancel: @escaping () -> Void, onOverride: @escaping () -> Void) {
        hide()
        model.familyName = familyName
        model.reason = reason
        model.explanation = explanation
        model.sender = sender?.isHighRisk == true ? sender : nil
        model.status = .waiting
        model.onCancel = { [weak self] in self?.hide(); onCancel() }
        model.onOverride = { [weak self] in self?.hide(); onOverride() }
        for screen in NSScreen.screens {
            let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // The page behind stays visible but blurred: you can tell where you are, not keep reading it.
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            let host = NSHostingView(rootView: PayPauseView(model: model))
            host.frame = blur.bounds
            host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
            w.contentView = blur
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
        // Testing only: SCOUT_TEST_AUTOCLICK presses "Go back" / "Cancel the payment" after 4 s.
        if ProcessInfo.processInfo.environment["SCOUT_TEST_AUTOCLICK"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.isShowing else { return }
                Log.info("test autoclick: pay pause go back")
                self.model.onCancel()
            }
        }
    }

    func hide() { windows.forEach { WindowRetirement.retire($0) }; windows.removeAll() }
    var isShowing: Bool { !windows.isEmpty }
}

@MainActor
final class PayPauseModel: ObservableObject {
    enum Status { case waiting, approved, denied, offline, selfPause }
    @Published var familyName = "Sarah"
    @Published var reason = ""
    /// Claude's plain-language reason ("The IRS never asks for gift cards.").
    @Published var explanation = ""
    /// CRS's finding about the sender, shown only when it was a real, high-risk answer.
    @Published var sender: SenderCheck?
    @Published var status: Status = .waiting
    @Published var note: String?
    var onCancel: () -> Void = {}
    var onOverride: () -> Void = {}
}

/// A full-screen stop before money or a password goes somewhere risky. Same language as the warning card
/// (white card, orange accent, the buddy looking worried), only bigger, on a blurred and dimmed screen.
struct PayPauseView: View {
    @ObservedObject var model: PayPauseModel
    @State private var confirmOverride = false
    @State private var shown = false

    static let accent = Color(red: 0.90, green: 0.45, blue: 0.08)
    static let ink = Color(white: 0.08)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            card
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = true } }
    }

    var card: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 22) {
                Text(subline)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.2))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHY I STOPPED YOU")
                            .font(.system(size: 12, weight: .bold)).kerning(0.8)
                            .foregroundStyle(Color(white: 0.45))
                        ForEach(Array(reasons.enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: r.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Self.accent)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Self.accent.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(r.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Self.ink)
                                        if let badge = r.badge {
                                            Text(badge).font(.system(size: 11, weight: .bold)).kerning(0.5)
                                                .padding(.horizontal, 7).padding(.vertical, 2)
                                                .foregroundStyle(Self.accent)
                                                .background(Capsule().stroke(Self.accent.opacity(0.5), lineWidth: 1))
                                        }
                                    }
                                    if let d = r.detail {
                                        Text(d).font(.system(size: 15)).foregroundStyle(Color(white: 0.35))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.965)))
                }
                if let note = model.note, !note.isEmpty {
                    Text("“\(note)” — \(model.familyName)").font(.system(size: 18).italic()).foregroundStyle(Color(white: 0.3))
                }
                buttons
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        // Shadow on its own shape: on the card itself it bled onto every row inside.
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white).shadow(color: .black.opacity(0.35), radius: 40, y: 18))
    }

    var header: some View {
        HStack(spacing: 18) {
            BuddyView(style: BuddyStyle.current, mood: model.status == .approved ? .happy : .alarmed, pointing: false, level: 0)
                .frame(width: 60, height: 60)
                .padding(8)
                .background(Circle().fill(.white))
                .compositingGroup()
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 13, weight: .bold)).kerning(1)
                    .foregroundStyle(.white.opacity(0.85))
                Text(headline)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: headerColors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var buttons: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                SwiftUI.Button(action: model.onCancel) {
                    Label(primaryTitle, systemImage: model.status == .approved ? "xmark" : "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(model.status == .approved ? Color(white: 0.15) : .white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(model.status == .approved ? Color(white: 0.94) : Self.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if model.status == .approved {
                    SwiftUI.Button(action: model.onOverride) {
                        Text("Continue").font(.system(size: 20, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.20, green: 0.65, blue: 0.40)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.status == .waiting || model.status == .offline || model.status == .selfPause {
                SwiftUI.Button(confirmOverride ? "Tap again only if you're sure it's safe" : "I know this is safe. Continue anyway") {
                    if confirmOverride { model.onOverride() } else { confirmOverride = true }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(confirmOverride ? Self.accent : Color(white: 0.5))
            }
        }
        .padding(.top, 2)
    }

    struct Reason { var icon: String; var title: String; var detail: String?; var badge: String? = nil }

    var reasons: [Reason] {
        guard model.status != .approved else { return [] }
        var out: [Reason] = []
        if !model.reason.isEmpty { out.append(Reason(icon: "creditcard.trianglebadge.exclamationmark", title: "It wants something private", detail: model.reason)) }
        if let s = model.sender {
            let seen = s.newToday ? "That address was created today." : s.firstSeen.map { "First seen \($0)." } ?? ""
            out.append(Reason(icon: "envelope.badge.shield.half.filled", title: "The sender is high risk",
                              detail: "\(s.email) scores \(s.score ?? 100) out of 100. \(seen)", badge: "CRS CHECKED"))
        }
        if !model.explanation.isEmpty { out.append(Reason(icon: "exclamationmark.bubble.fill", title: "It doesn't add up", detail: model.explanation)) }
        return out
    }

    var headerColors: [Color] {
        switch model.status {
        case .approved: return [Color(red: 0.22, green: 0.70, blue: 0.45), Color(red: 0.13, green: 0.55, blue: 0.35)]
        case .denied: return [Color(red: 0.88, green: 0.30, blue: 0.22), Color(red: 0.72, green: 0.18, blue: 0.14)]
        default: return [Color(red: 0.98, green: 0.58, blue: 0.16), Color(red: 0.86, green: 0.38, blue: 0.05)]
        }
    }

    var eyebrow: String {
        switch model.status {
        case .approved: return "ALL CLEAR"
        default: return "SCOUT PAUSED THIS PAGE"
        }
    }

    var primaryTitle: String {
        switch model.status {
        case .denied: return "OK, close this"
        case .approved: return "Go back anyway"
        case .selfPause: return "Go back to safety"
        default: return "Cancel the payment"
        }
    }

    var headline: String {
        switch model.status {
        case .selfPause: return "Stop. Don't enter anything here."
        case .waiting, .offline: return "Let's check with \(model.familyName) first"
        case .approved: return "\(model.familyName) says it's OK"
        case .denied: return "\(model.familyName) says please stop"
        }
    }

    var subline: String {
        switch model.status {
        case .selfPause: return "Take a slow breath. Nothing has been sent. A real company will never rush you or ask for gift cards."
        case .waiting: return "I've sent \(model.familyName) a message. Nothing has been sent. We'll wait together."
        case .offline: return "I couldn't reach \(model.familyName). Please call them on a number you know before you go on."
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
        w.contentView = NSHostingView(rootView: SetupView(close: { [weak w] in w?.close() }).scoutTheme())
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
                    .scoutButton(primary: true)
                    .keyboardShortcut(.defaultAction)
                    notNow(st)
                } else {
                    Button { close() } label: {
                        Text("Done").lfont(17, .semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .scoutButton(primary: true)
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
        if classic { b.scoutButton(primary: false) } else { b.buttonStyle(.plain).foregroundStyle(.secondary) }
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

