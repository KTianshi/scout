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
        DebugShot.take("settings")
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Lookout Settings"
        w.contentMinSize = NSSize(width: 640, height: 460)
        w.contentViewController = NSHostingController(rootView: SettingsView(model: model).lookoutTheme())
        w.setContentSize(NSSize(width: 720, height: 560))
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
    @Published var wakeWord = WakeListener.enabled
    @Published var deepCheck = DeepCheck.enabled
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

    func setDeepCheck(_ on: Bool) {
        deepCheck = on
        DeepCheck.enabled = on
    }

    func setWakeWord(_ on: Bool) {
        wakeWord = on
        WakeListener.enabled = on
        if on, !(Listener.micAuthorized && Listener.speechAuthorized) {
            Task { _ = await Listener.requestPermissions() }
        }
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
        case .voice: return Color(red: 0.95, green: 0.50, blue: 0.20)
        case .buddy: return Color(red: 0.20, green: 0.55, blue: 0.92)
        case .talking: return Color(red: 0.55, green: 0.30, blue: 0.85)
        case .safety: return Color(red: 0.25, green: 0.65, blue: 0.15)
        }
    }
}

/// A sidebar of sections on the left; the chosen one (Voice to start) on the right.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State var pane: SettingsPane = .voice
    @Environment(\.classic) private var classic

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model, pane: $pane)
            Divider()
            ScrollView { SettingsPageContent(pane: pane, model: model) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(classic ? ClassicLook.face : Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    @Binding var pane: SettingsPane
    @Environment(\.classic) private var classic
    @AppStorage(ClassicLook.key) private var classicOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if classic && model.style == .cursor {
                    PixelIcon.arrow.view.frame(width: 16, height: 24).frame(width: 32, height: 32)
                } else {
                    BuddyView(style: model.style, mood: .idle, pointing: false, level: 0)
                        .frame(width: 64, height: 64)
                        .scaleEffect(0.5)
                        .frame(width: 32, height: 32)
                }
                Text("Lookout").lfont(18, .semibold)
            }
            .padding(.leading, 4)
            .padding(.bottom, 14)
            ForEach(SettingsPane.allCases) { p in
                SidebarRow(pane: p, selected: pane == p) { pane = p }
            }
            Spacer()
            Toggle(isOn: $classicOn) { Text("Classic look").lfont(14) }
                .toggleStyle(.switch)
                .padding(.horizontal, 6)
        }
        .foregroundStyle(classic ? Color.white : Color.primary)
        .padding(14)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(classic ? AnyShapeStyle(LinearGradient(colors: [ClassicLook.paneTop, ClassicLook.paneBottom], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.primary.opacity(0.03)))
    }
}

struct SidebarRow: View {
    var pane: SettingsPane
    var selected: Bool
    var action: () -> Void
    @Environment(\.classic) private var classic
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if classic, let px = PixelIcon(rawValue: pane.rawValue) {
                    px.view.frame(width: 28, height: 28)
                } else {
                    Image(systemName: pane.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .frame(width: 22)
                }
                Text(pane.title).lfont(16, selected && classic ? .semibold : .regular)
                    .foregroundStyle(classic && selected ? ClassicLook.blue : (classic ? .white : .primary))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: classic ? 5 : 8, style: .continuous).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    var background: Color {
        if classic { return selected ? .white : (hover ? .white.opacity(0.2) : .clear) }
        return selected ? Color.accentColor.opacity(0.14) : (hover ? Color.primary.opacity(0.05) : .clear)
    }
}

struct SettingsPageContent: View {
    var pane: SettingsPane
    @ObservedObject var model: SettingsModel
    @Environment(\.classic) private var classic

    var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                Text(pane.title).lfont(26, .semibold)
                    .foregroundStyle(classic ? ClassicLook.blue : .primary)
                switch pane {
                case .voice: VoicePane(model: model)
                case .buddy: BuddyPane(model: model)
                case .talking: TalkingPane(model: model)
                case .safety: SafetyPane(model: model)
                }
            }
            .foregroundStyle(classic ? Color.black : Color.primary)
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

/// `Lookout --render-ui DIR`: renders the setup steps and every settings page to PNGs (light and dark), offscreen.
@MainActor
enum UIRenderer {
    static func run(dir: String, companion: Companion) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = SettingsModel(companion: companion)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance { MainActor.assumeIsolated {
                let scheme: ColorScheme = name == "dark" ? .dark : .light
                @MainActor func save<V: View>(_ v: V, _ file: String, width: CGFloat, height: CGFloat? = nil) {
                    let root = v.frame(width: width, height: height)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, scheme)
                    let r = ImageRenderer(content: root)
                    r.scale = 2
                    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(file).png"))
                }
                for look in [false, true] {
                    let tag = look ? "classic-" : ""
                    for step in 0...3 { save(SetupView(previewStep: step).lookoutTheme(force: look), "\(tag)setup-\(step)", width: 440, height: 560) }
                    for p in SettingsPane.allCases { save(SettingsView(model: model, pane: p).lookoutTheme(force: look), "\(tag)settings-\(p.rawValue)", width: 720, height: 560) }
                    save(VStack(alignment: .leading, spacing: 22) { BuddyPane(model: model) }.padding(28).lookoutTheme(force: look), "\(tag)buddies", width: 560)
                }
            } }
        }
        print("rendered UI to \(dir)")
    }
}

extension View {
    /// Liquid Glass on macOS 26, frosted material before that.
    /// (Compile-time guard: the Glass API only exists in the macOS 26 SDK / Swift 6.2 toolchains.)
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            frostedCard(cornerRadius: cornerRadius, tint: tint)
        }
        #else
        frostedCard(cornerRadius: cornerRadius, tint: tint)
        #endif
    }

    /// Settings groups: one quiet surface, hairline edge, no tint.
    func settingsGroup() -> some View { modifier(SettingsGroup()) }

    @ViewBuilder func frostedCard(cornerRadius: CGFloat, tint: Color?) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill((tint ?? .clear).opacity(0.18)))
    }
}

/// Settings groups: one quiet surface with a hairline edge (white with a blue-gray edge in the classic look).
struct SettingsGroup: ViewModifier {
    @Environment(\.classic) private var classic

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: classic ? 5 : 12, style: .continuous)
        content
            .background(shape.fill(classic ? Color.white : Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.stroke(classic ? ClassicLook.border : Color.primary.opacity(0.08), lineWidth: classic ? 1 : 0.5))
            .clipShape(shape)
    }
}

struct CardTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .lfont(13, .medium)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
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
            VStack(spacing: 0) {
                ForEach(Array(LookoutVoice.all.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Divider().padding(.leading, 14) }
                    VoiceRow(voice: v, hue: Self.hues[i % Self.hues.count], selected: model.voiceID == v.id) { model.pickVoice(v) }
                }
            }
            .settingsGroup()
        }
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Speed")
            Picker("Speed", selection: Binding(get: { model.speed }, set: { model.pickSpeed($0) })) {
                ForEach(VoiceSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.label).lfont(16)
                    Text(voice.detail).lfont(13).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").lfont(15, .semibold).foregroundStyle(Color.accentColor)
                } else if hover {
                    Image(systemName: "play.fill").lfont(12).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color.primary.opacity(hover ? 0.04 : 0))
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
                if let icon { Image(systemName: icon).lfont(13, .semibold) }
                Text(title).lfont(15, .semibold)
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
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Look")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(BuddyStyle.allCases, id: \.self) { s in
                    StyleTile(style: s, selected: model.style == s) { model.pickStyle(s) }
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Behavior")
            VStack(spacing: 0) {
                ToggleRow(icon: "eye.fill", tint: .blue, title: "Show Lookout on my screen",
                          isOn: Binding(get: { model.visible }, set: { model.setVisible($0) }))
                Divider().padding(.leading, 58)
                ToggleRow(icon: "cursorarrow.motionlines", tint: .purple, title: "Follow my pointer",
                          isOn: Binding(get: { model.follows }, set: { model.setFollows($0) }))
            }
            .settingsGroup()
        }
    }
}

struct StyleTile: View {
    var style: BuddyStyle
    var selected: Bool
    var action: () -> Void
    @Environment(\.classic) private var classic
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BuddyView(style: style, mood: .idle, pointing: false, level: 0)
                    .frame(width: 64, height: 64)
                    .scaleEffect(style == .classic && !classic ? 0.6 : 0.85)
                    .frame(width: 64, height: 64)
                Text(style.name).lfont(14, .semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(hover ? 0.05 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
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
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lfont(16)
                if let detail {
                    Text(detail).lfont(13).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                            Spacer()
                            Image(systemName: model.shortcut == s ? "checkmark.circle.fill" : "circle")
                                .lfont(22)
                                .foregroundStyle(model.shortcut == s ? Color.accentColor : Color.secondary.opacity(0.35))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .settingsGroup()
            if model.shortcutTaken {
                Label("Another app uses these keys. Pick different ones.", systemImage: "exclamationmark.triangle.fill")
                    .lfont(14).foregroundStyle(.orange)
                    .padding(.leading, 6)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Hands-free")
            ToggleRow(icon: "waveform.badge.mic", tint: .pink, title: "Start by saying “Hey Lookout”",
                      detail: "Talk without pressing keys. Lookout only listens for its name, and nothing leaves your Mac until you say it.",
                      isOn: Binding(get: { model.wakeWord }, set: { model.setWakeWord($0) }))
                .settingsGroup()
        }
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Step by step")
            ToggleRow(icon: "figure.walk", tint: .orange, title: "Give me the next step on its own",
                      detail: model.autoGuide ? "After each click, Lookout looks again and tells you what to do next."
                                              : "Lookout waits until you ask for the next step.",
                      isOn: Binding(get: { model.autoGuide }, set: { model.setAutoGuide($0) }))
                .settingsGroup()
        }
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
                      detail: "Spots warning signs, like fake virus alerts or requests for gift cards, and stops you before you call or pay.",
                      isOn: Binding(get: { model.guardian }, set: { model.setGuardian($0) }))
                .settingsGroup()
            ToggleRow(icon: "sparkle.magnifyingglass", tint: .indigo, title: "Double-check with Claude",
                      detail: "Claude also reads each new screen to catch scams with no warning signs, like a friendly stranger asking for money. This sends screen text to Claude.",
                      isOn: Binding(get: { model.deepCheck }, set: { model.setDeepCheck($0) }))
                .settingsGroup()
                .disabled(!model.guardian)
                .opacity(model.guardian ? 1 : 0.5)
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
                    .lfont(13).foregroundStyle(.secondary)
            }
            .padding(16)
            .settingsGroup()
        }
        }
        permissionsButton
    }

    var permissionsButton: some View {
        Button { model.companion.setup.show() } label: {
            Text("Check permissions").lfont(15).padding(.horizontal, 6)
        }
        .lookoutButton(primary: false)
    }
}

struct NameField: View {
    var title: String
    var icon: String
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).lfont(13, .medium).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .lfont(16)
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
