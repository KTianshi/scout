import AppKit
import SwiftUI
import LookoutCore

/// One friendly window for everything a person (or whoever sets Lookout up for them) might want to change.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: SettingsModel

    init(companion: Companion) { model = SettingsModel(companion: companion) }

    func show() {
        model.reload()
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Lookout Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.toolbar = NSToolbar()
        w.toolbarStyle = .unified
        w.contentMinSize = NSSize(width: 760, height: 520)
        w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        w.setContentSize(NSSize(width: 900, height: 640))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    unowned let companion: Companion
    @Published var voiceID = LookoutVoice.current.id
    @Published var speed = VoiceSpeed.current
    @Published var style = BuddyStyle.current
    @Published var follows = true
    @Published var shortcut = TalkShortcut.current
    @Published var shortcutTaken = false
    @Published var guardian = true
    @Published var visible = true
    @Published var autoGuide = GuideMode.automatic
    @Published var elderName = LookoutConfig.elderName
    @Published var familyName = LookoutConfig.familyName

    init(companion: Companion) {
        self.companion = companion
        reload()
    }

    func reload() {
        follows = companion.overlay.followsCursor
        guardian = companion.guardianEnabled
        visible = companion.overlay.state.visible
    }

    var cartesia: CartesiaSpeech? { companion.speech as? CartesiaSpeech }

    func pickVoice(_ v: LookoutVoice) {
        voiceID = v.id
        LookoutVoice.current = v
        cartesia?.client.voiceID = v.id
        sample()
    }

    func pickSpeed(_ s: VoiceSpeed) {
        speed = s
        VoiceSpeed.current = s
        cartesia?.rate = s.rate
        sample()
    }

    private func sample() {
        guard let c = cartesia else { return }
        c.stop()
        Task {
            await c.speak("Hi, I'm Lookout. This is how I'll sound.")
            // Re-cache the warning lines in the new voice so they still play instantly.
            _ = await c.client.prewarm(CartesiaSpeech.standardLines())
        }
    }

    func pickStyle(_ s: BuddyStyle) {
        style = s
        BuddyStyle.current = s
        companion.overlay.state.style = s
    }

    func setFollows(_ on: Bool) {
        follows = on
        companion.overlay.followsCursor = on
    }

    func pickShortcut(_ s: TalkShortcut) {
        shortcut = s
        TalkShortcut.current = s
        shortcutTaken = !companion.registerTalkShortcut()
    }

    func setAutoGuide(_ on: Bool) {
        autoGuide = on
        GuideMode.automatic = on
    }

    func setVisible(_ on: Bool) {
        visible = on
        AppDelegate.shared?.setVisible(on)
    }

    func setGuardian(_ on: Bool) {
        guardian = on
        AppDelegate.shared?.setGuardian(on)
    }

    func saveNames() {
        LookoutConfig.setNames(elder: elderName, family: familyName)
    }
}

// MARK: - Views

enum SettingsPane: String, CaseIterable, Identifiable {
    case voice, buddy, talking, safety
    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voice"
        case .buddy: return "Buddy"
        case .talking: return "Talking"
        case .safety: return "Safety"
        }
    }
    var subtitle: String {
        switch self {
        case .voice: return "Pick how Lookout sounds. Tap a voice to hear it."
        case .buddy: return "Pick how Lookout looks and where it waits."
        case .talking: return "Hold the keys, ask your question, then let go."
        case .safety: return "How Lookout watches out for scams."
        }
    }
    var icon: String {
        switch self {
        case .voice: return "waveform"
        case .buddy: return "sparkles"
        case .talking: return "mic.fill"
        case .safety: return "shield.lefthalf.filled"
        }
    }
    var tint: Color {
        switch self {
        case .voice: return Color(red: 0.36, green: 0.42, blue: 0.98)
        case .buddy: return Color(red: 0.62, green: 0.36, blue: 0.96)
        case .talking: return Color(red: 0.98, green: 0.45, blue: 0.35)
        case .safety: return Color(red: 0.20, green: 0.72, blue: 0.50)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var pane: SettingsPane? = .voice

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    BuddyView(style: model.style, mood: .idle, pointing: false, level: 0)
                        .frame(width: 64, height: 64)
                        .scaleEffect(0.55)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lookout").font(.system(size: 17, weight: .semibold))
                        Text("Your on-screen helper").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)
                List(SettingsPane.allCases, selection: $pane) { p in
                    Label {
                        Text(p.title).font(.system(size: 15, weight: .medium))
                    } icon: {
                        Image(systemName: p.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.tint.gradient))
                    }
                    .padding(.vertical, 4)
                    .tag(p)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            let p = pane ?? .voice
            ZStack {
                AuroraBackground(tint: p.tint)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title).font(.system(size: 32, weight: .bold))
                            Text(p.subtitle).font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                        switch p {
                        case .voice: VoicePane(model: model)
                        case .buddy: BuddyPane(model: model)
                        case .talking: TalkingPane(model: model)
                        case .safety: SafetyPane(model: model)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: p)
        }
    }
}

/// Soft blurred color blobs behind the glass so it has something to refract.
struct AuroraBackground: View {
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Circle().fill(tint).frame(width: w * 0.7).blur(radius: 120).offset(x: w * 0.25, y: -h * 0.35)
                Circle().fill(Color(red: 0.25, green: 0.75, blue: 0.95)).frame(width: w * 0.55).blur(radius: 130).offset(x: -w * 0.3, y: h * 0.4)
                Circle().fill(Color(red: 0.85, green: 0.45, blue: 0.90)).frame(width: w * 0.4).blur(radius: 120).offset(x: w * 0.35, y: h * 0.45)
            }
            .opacity(scheme == .dark ? 0.55 : 0.35)
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on macOS 26, frosted material before that.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill((tint ?? .clear).opacity(0.18)))
        }
    }
}

struct CardTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }
}

// MARK: Voice

struct VoicePane: View {
    @ObservedObject var model: SettingsModel
    static let hues: [Color] = [
        Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.75, green: 0.45, blue: 0.95),
        Color(red: 0.25, green: 0.70, blue: 0.75), Color(red: 0.95, green: 0.70, blue: 0.30), Color(red: 0.45, green: 0.75, blue: 0.45),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Voices")
            VStack(spacing: 0) {
                ForEach(Array(LookoutVoice.all.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Divider().padding(.leading, 70) }
                    VoiceRow(voice: v, hue: Self.hues[i % Self.hues.count], selected: model.voiceID == v.id) { model.pickVoice(v) }
                }
            }
            .padding(.vertical, 6)
            .glassCard()
        }
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Speaking speed")
            HStack(spacing: 8) {
                ForEach(VoiceSpeed.allCases, id: \.self) { s in
                    PillButton(title: s.title, icon: s == .slower ? "tortoise.fill" : s == .faster ? "hare.fill" : "figure.walk",
                               selected: model.speed == s) { model.pickSpeed(s) }
                }
            }
            .padding(10)
            .glassCard()
        }
    }
}

struct VoiceRow: View {
    var voice: LookoutVoice
    var hue: Color
    var selected: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(String(voice.label.prefix(1)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(LinearGradient(colors: [hue, hue.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: hue.opacity(0.4), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.label).font(.system(size: 16, weight: .semibold))
                    Text(voice.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(hover ? Color.accentColor : Color.secondary.opacity(0.5))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hover ? 0.05 : 0)))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PillButton: View {
    var title: String
    var icon: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
            .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Buddy

struct BuddyPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.16, green: 0.12, blue: 0.30)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            BuddyView(style: model.style, mood: .idle, pointing: false, level: 0)
                .frame(width: 64, height: 64)
                .scaleEffect(1.5)
            VStack {
                Spacer()
                Text("This is how Lookout looks on your screen")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 14)
            }
        }
        .frame(height: 190)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Look")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(BuddyStyle.allCases, id: \.self) { s in
                    StyleTile(style: s, selected: model.style == s) { model.pickStyle(s) }
                }
            }
            .padding(10)
            .glassCard()
        }

        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Behavior")
            VStack(spacing: 0) {
                ToggleRow(icon: "eye.fill", tint: .blue, title: "Show Lookout on my screen",
                          detail: model.visible ? "Your buddy is on screen." : "Hidden. Lookout still warns you and answers when you ask.",
                          isOn: Binding(get: { model.visible }, set: { model.setVisible($0) }))
                Divider().padding(.leading, 58)
                ToggleRow(icon: "cursorarrow.motionlines", tint: .purple, title: "Follow my pointer",
                          detail: model.follows ? "Lookout stays next to your mouse pointer." : "Lookout waits in the corner. Drag it anywhere, or click it to ask.",
                          isOn: Binding(get: { model.follows }, set: { model.setFollows($0) }))
            }
            .padding(.vertical, 6)
            .glassCard()
        }
    }
}

struct StyleTile: View {
    var style: BuddyStyle
    var selected: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BuddyView(style: style, mood: .idle, pointing: false, level: 0)
                    .frame(width: 64, height: 64)
                    .scaleEffect(style == .classic ? 0.6 : 0.85)
                    .frame(width: 64, height: 64)
                Text(style.name).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hover ? 0.06 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .scaleEffect(hover && !selected ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ToggleRow: View {
    var icon: String
    var tint: Color
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: Talking

struct TalkingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Hold to talk")
            VStack(spacing: 0) {
                ForEach(Array(TalkShortcut.allCases.enumerated()), id: \.element) { i, s in
                    if i > 0 { Divider().padding(.horizontal, 14) }
                    Button { model.pickShortcut(s) } label: {
                        HStack(spacing: 14) {
                            HStack(spacing: 6) {
                                ForEach(Self.keys(s), id: \.self) { Keycap(label: $0) }
                            }
                            Text(s.spoken).font(.system(size: 14)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: model.shortcut == s ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(model.shortcut == s ? Color.accentColor : Color.secondary.opacity(0.35))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .glassCard()
            if model.shortcutTaken {
                Label("Another app already uses these keys. Please pick a different one.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.orange)
                    .padding(.leading, 6)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Step by step")
            ToggleRow(icon: "figure.walk", tint: .orange, title: "Walk me through it automatically",
                      detail: model.autoGuide ? "After you click, Lookout looks again and gives the next step on its own."
                                              : "Lookout gives one step at a time. Say “next” when you're ready for more.",
                      isOn: Binding(get: { model.autoGuide }, set: { model.setAutoGuide($0) }))
                .padding(.vertical, 6)
                .glassCard()
        }
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 15))
                .foregroundStyle(.yellow)
            Text("You can also type a question: click the eye icon at the top of your screen and choose “Ask Lookout…”.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// "⌃⌥ Space" → ["⌃", "⌥", "Space"]
    static func keys(_ s: TalkShortcut) -> [String] {
        let parts = s.symbol.split(separator: " ")
        return (parts.first.map { $0.map(String.init) } ?? []) + parts.dropFirst().map(String.init)
    }
}

struct Keycap: View {
    var label: String
    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(minWidth: 34, minHeight: 32)
            .padding(.horizontal, label.count > 1 ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

// MARK: Safety

struct SafetyPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Protection")
            ToggleRow(icon: "shield.lefthalf.filled", tint: .green, title: "Watch for scams",
                      detail: "Lookout gently stops you if something looks like a scam.",
                      isOn: Binding(get: { model.guardian }, set: { model.setGuardian($0) }))
                .padding(.vertical, 6)
                .glassCard()
        }
        if LookoutConfig.familyEnabled {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Names")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    NameField(title: "Your name", icon: "person.fill", text: $model.elderName, onCommit: model.saveNames)
                    NameField(title: "Family helper", icon: "heart.fill", text: $model.familyName, onCommit: model.saveNames)
                }
                Text("Lookout tells your family helper when it stops a scam, like “\(model.familyName.isEmpty ? "Sarah" : model.familyName) has been told.”")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(16)
            .glassCard()
        }
        }
        permissionsButton
    }

    @ViewBuilder var permissionsButton: some View {
        let b = Button { model.companion.setup.show() } label: {
            Label("Check permissions…", systemImage: "lock.shield").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 6)
        }
        .controlSize(.large)
        if #available(macOS 26, *) { b.buttonStyle(.glass) } else { b.buttonStyle(.bordered) }
    }
}

struct NameField: View {
    var title: String
    var icon: String
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .onSubmit(onCommit)
                .onChange(of: text) { _, _ in onCommit() }
        }
    }
}

// MARK: - App icon

/// Drawn at launch so the Dock (shown while Settings is open) has a real icon.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.30, green: 0.18, blue: 0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color(red: 0.42, green: 0.76, blue: 1.0)).frame(width: 520).blur(radius: 110).opacity(0.75)
            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 0.42, green: 0.76, blue: 1.0)], center: .init(x: 0.4, y: 0.35), startRadius: 4, endRadius: 230))
                .frame(width: 400)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 8).frame(width: 400))
        }
        .frame(width: 1024, height: 1024)
        .padding(0)
    }

    @MainActor static func image() -> NSImage? {
        let r = ImageRenderer(content: AppIconView().frame(width: 1024, height: 1024).padding(100).frame(width: 1024, height: 1024).scaleEffect(0.82))
        r.scale = 1
        return r.nsImage
    }
}
