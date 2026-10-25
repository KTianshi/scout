import AppKit
import SwiftUI

/// The optional "Classic look": a cheerful, early-2000s style (glossy blue and green, Tahoma, beige window face)
/// for Setup and Settings. Off by default; switched from the Settings sidebar.
enum ClassicLook {
    static let key = "classicLook"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static let face = Color(red: 0.925, green: 0.914, blue: 0.847)      // #ECE9D8
    static let blue = Color(red: 0.043, green: 0.247, blue: 0.659)      // #0B3FA8
    static let select = Color(red: 0.192, green: 0.416, blue: 0.773)    // #316AC5
    static let paneTop = Color(red: 0.482, green: 0.635, blue: 0.906)   // #7BA2E7
    static let paneBottom = Color(red: 0.388, green: 0.459, blue: 0.839) // #6375D6
    static let border = Color(red: 0.498, green: 0.616, blue: 0.725)    // #7F9DB9

    /// The classic look has no dark mode, so its windows use the light title bar too.
    @MainActor static func applyWindowAppearance(_ on: Bool) {
        for w in NSApp.windows where w.title == "Scout Settings" || w.title == "Set up Scout" {
            w.appearance = on ? NSAppearance(named: .aqua) : nil
        }
    }
}

private struct ClassicKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var classic: Bool {
        get { self[ClassicKey.self] }
        set { self[ClassicKey.self] = newValue }
    }
}

/// Root of each window: reads the setting and passes it down.
struct LookoutTheme: ViewModifier {
    var force: Bool? = nil
    @AppStorage(ClassicLook.key) private var stored = false

    func body(content: Content) -> some View {
        let on = force ?? stored
        themed(content.environment(\.classic, on), on: on)
            .onAppear { ClassicLook.applyWindowAppearance(on) }
            .onChange(of: stored) { _, v in ClassicLook.applyWindowAppearance(v) }
    }

    @ViewBuilder private func themed<V: View>(_ v: V, on: Bool) -> some View {
        if on { v.environment(\.colorScheme, .light) } else { v }
    }
}

extension View {
    func lookoutTheme(force: Bool? = nil) -> some View { modifier(LookoutTheme(force: force)) }

    /// System font normally, Tahoma in the classic look.
    func lfont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View { modifier(LFont(size: size, weight: weight)) }

    /// Primary ("Allow", "Done") or secondary button, styled for the current look.
    func lookoutButton(primary: Bool) -> some View { modifier(LookoutButton(primary: primary)) }
}

private struct LFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight
    @Environment(\.classic) private var classic

    func body(content: Content) -> some View {
        let bold = weight == .semibold || weight == .bold || weight == .heavy
        content.font(classic ? .custom(bold ? "Tahoma-Bold" : "Tahoma", size: size) : .system(size: size, weight: weight))
    }
}

private struct LookoutButton: ViewModifier {
    var primary: Bool
    @Environment(\.classic) private var classic

    func body(content: Content) -> some View {
        if classic {
            content.buttonStyle(ClassicButtonStyle(go: primary))
        } else if primary {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            content.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

/// Glossy green "go" button, or the beige push button. Hover lights an orange rim; pressing darkens it.
struct ClassicButtonStyle: ButtonStyle {
    var go: Bool
    func makeBody(configuration c: Configuration) -> some View { ClassicButtonBody(go: go, label: c.label, pressed: c.isPressed) }
}

private struct ClassicButtonBody<Label: View>: View {
    var go: Bool
    var label: Label
    var pressed: Bool
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: go ? 14 : 4, style: .continuous)
        let top = go ? Color(red: 0.50, green: 0.83, blue: 0.36) : Color.white
        let bottom = go ? Color(red: 0.24, green: 0.62, blue: 0.12) : ClassicLook.face
        label
            .foregroundStyle(go ? Color.white : Color.black)
            .shadow(color: go ? Color(red: 0.17, green: 0.37, blue: 0.07) : .clear, radius: 0, x: 1, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, go ? 8 : 5)
            .background(shape.fill(LinearGradient(colors: pressed ? [bottom, top] : [top, bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.inset(by: 1.5).stroke(Color(red: 0.97, green: 0.70, blue: 0.19), lineWidth: hover && !pressed ? 2.5 : 0))
            .overlay(shape.stroke(go ? Color(red: 0.17, green: 0.48, blue: 0.04) : Color(red: 0, green: 0.235, blue: 0.455), lineWidth: 1))
            .brightness(pressed ? -0.1 : (hover ? 0.06 : 0))
            .offset(y: pressed ? 1 : 0)
            .contentShape(shape)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Blue sky over a green hill, for the top of the setup window.
struct ClassicBanner: View {
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.93), Color(red: 0.75, green: 0.88, blue: 1.0)],
                               startPoint: .top, endPoint: .bottom)
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 0.49, green: 0.77, blue: 0.35), Color(red: 0.30, green: 0.60, blue: 0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: g.size.width * 2, height: g.size.height * 0.9)
                    .offset(x: g.size.width * 0.25, y: g.size.height * 0.55)
            }
            .clipped()
        }
    }
}

// MARK: - 8-bit icons

/// A tiny bitmap drawn as crisp squares. Each string is one row; each character a palette color ("." is clear).
struct PixelArt: View {
    var rows: [String]

    static let palette: [Character: Color] = [
        "K": .black, "W": .white,
        "s": Color(white: 0.78),
        "b": Color(red: 0.45, green: 0.70, blue: 1.0), "B": Color(red: 0.10, green: 0.35, blue: 0.85),
        "G": Color(red: 0.25, green: 0.70, blue: 0.20),
        "Y": Color(red: 1.0, green: 0.84, blue: 0.15),
        "p": Color(red: 0.72, green: 0.55, blue: 0.95),
        "O": Color(red: 1.0, green: 0.62, blue: 0.15),
        "N": Color(red: 0.55, green: 0.33, blue: 0.16),
        "T": Color(red: 0.88, green: 0.70, blue: 0.48),
        "P": Color(red: 1.0, green: 0.55, blue: 0.68),
        "g": Color(white: 0.62),
    ]

    var body: some View {
        Canvas { ctx, size in
            let cols = rows.map(\.count).max() ?? 1
            let px = min(size.width / CGFloat(cols), size.height / CGFloat(rows.count))
            let ox = (size.width - px * CGFloat(cols)) / 2, oy = (size.height - px * CGFloat(rows.count)) / 2
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = Self.palette[ch] else { continue }
                    // A hair of overlap so neighbouring squares never show a seam.
                    ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c))
                }
            }
        }
    }
}

enum PixelIcon: String {
    case voice, buddy, talking, safety, eye, hand, check, arrow
    // Buddies
    case dog, owl, mouse, orb, chick, smiley
    /// The buddy made in Settings; drawings only, no hand-placed pixels.
    case custom

    /// The pixel version of a buddy style (the cursor style uses `.arrow` directly).
    static func sprite(for style: BuddyStyle) -> PixelIcon? {
        switch style {
        case .cursor: return nil
        case .custom: return .custom
        case .dog: return .dog
        case .owl: return .owl
        case .mouse: return .mouse
        case .orb: return .orb
        case .chick: return .chick
        case .classic: return .smiley
        }
    }

    var rows: [String] {
        switch self {
        case .voice: return [
            "................",
            "................",
            ".......K....B...",
            "......KK.....B..",
            ".....KbK..B...B.",
            "KKKKKbbK...B..B.",
            "KssKbbbK...B..B.",
            "KssKbbbK...B..B.",
            "KssKbbbK...B..B.",
            "KKKKKbbK...B..B.",
            ".....KbK..B...B.",
            "......KK.....B..",
            ".......K....B...",
            "................",
            "................",
            "................",
        ]
        case .buddy: return [
            "................",
            ".....KKKKKK.....",
            "...KKYYYYYYKK...",
            "..KYYYYYYYYYYK..",
            ".KYYYYYYYYYYYYK.",
            ".KYYYKYYYYKYYYK.",
            "KYYYYKYYYYKYYYYK",
            "KYYYYKYYYYKYYYYK",
            "KYYYYYYYYYYYYYYK",
            "KYYKYYYYYYYYKYYK",
            ".KYYKYYYYYYKYYK.",
            ".KYYYKKKKKKYYYK.",
            "..KYYYYYYYYYYK..",
            "...KKYYYYYYKK...",
            ".....KKKKKK.....",
            "................",
        ]
        case .talking: return [
            "................",
            "......KKKK......",
            ".....KppppK.....",
            ".....KpWppK.....",
            ".....KpWppK.....",
            ".....KppppK.....",
            "...K.KppppK.K...",
            "...K.KppppK.K...",
            "...K..KKKK..K...",
            "....K......K....",
            ".....KKKKKK.....",
            ".......KK.......",
            ".......KK.......",
            ".....KKKKKK.....",
            "................",
            "................",
        ]
        case .safety: return [
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KGGGGGGGGGGGGK.",
            ".KGGGGGGGGGGWGK.",
            ".KGGGGGGGGGWWGK.",
            ".KGGGGGGGGWWWGK.",
            ".KGWGGGGGWWWGGK.",
            ".KGWWGGGWWWGGGK.",
            "..KGWWGWWWGGGK..",
            "..KGGWWWWGGGGK..",
            "...KGGWWGGGGK...",
            "....KGGGGGGK....",
            ".....KGGGGK.....",
            "......KGGK......",
            ".......KK.......",
            "................",
        ]
        case .eye: return [
            "................",
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKWWWWWWKK...",
            "..KWWWWBBWWWWK..",
            ".KWWWWBBBBWWWWK.",
            "KWWWWBBKWBBWWWWK",
            "KWWWWBBKKBBWWWWK",
            ".KWWWWBBBBWWWWK.",
            "..KWWWWBBWWWWK..",
            "...KKWWWWWWKK...",
            ".....KKKKKK.....",
            "................",
            "................",
            "................",
        ]
        case .hand: return [
            ".....KK.........",
            "....KWWK........",
            "....KWWK........",
            "....KWWK........",
            "....KWWKKK......",
            "....KWWKWWKK....",
            "....KWWKWWKWKK..",
            ".KK.KWWKWWKWKWK.",
            "KWWKKWWWWWWWKWK.",
            "KWWWKWWWWWWWWWK.",
            ".KWWWWWWWWWWWWK.",
            "..KWWWWWWWWWWWK.",
            "..KWWWWWWWWWWK..",
            "...KWWWWWWWWWK..",
            "....KWWWWWWWK...",
            "....KKKKKKKKK...",
        ]
        case .check: return [
            "................",
            "................",
            ".............KK.",
            "............KGGK",
            "...........KGGK.",
            "..........KGGK..",
            ".KK......KGGK...",
            "KGGK....KGGK....",
            ".KGGK..KGGK.....",
            "..KGGKKGGK......",
            "...KGGGGK.......",
            "....KGGK........",
            ".....KK.........",
            "................",
            "................",
            "................",
        ]
        case .orb: return [
            "................",
            "................",
            ".....BBBBBB.....",
            "....BbbbbbbB....",
            "...BbWWbbbbbB...",
            "..BbWWbbbbbbbB..",
            "..BbWbbbbbbbbB..",
            "..BbbbbbbbbbbB..",
            "..BbbbbbbbbbbB..",
            "..BbbbbbbbbbBB..",
            "...BbbbbbbbBB...",
            "....BBbbbbBB....",
            ".....BBBBBB.....",
            "................",
            "................",
            "................",
        ]
        case .chick: return [
            "................",
            "......KKKK......",
            ".....KYYYYK.....",
            "....KYYYYYYK....",
            "....KYKYYKYK....",
            "....KYYYYYYK....",
            "...KKYOOOOYKK...",
            "..KYYKYOOYKYYK..",
            ".KYYYYKKKKYYYYK.",
            ".KYYYYYYYYYYYYK.",
            "..KYYYYYYYYYYK..",
            "...KYYYYYYYYK...",
            "....KKKKKKKK....",
            ".....KO..OK.....",
            "....KOO..OOK....",
            "................",
        ]
        case .dog: return [
            "................",
            "....KKKKKKKK....",
            "..KKTTTTTTTTKK..",
            ".KNKTTTTTTTTKNK.",
            "KNNKTTTTTTTTKNNK",
            "KNNKTKKTTKKTKNNK",
            "KNNKTKKTTKKTKNNK",
            "KNNKTTTTTTTTKNNK",
            "KNNKTTWWWWTTKNNK",
            "KNNKTWWKKWWTKNNK",
            ".KNKTWWWWWWTKNK.",
            ".KNKTTWPPWTTKNK.",
            "..K.KTTTTTTK.K..",
            "....KKKKKKKK....",
            "................",
            "................",
        ]
        case .owl: return [
            "................",
            "..K..........K..",
            "..KK........KK..",
            "..KgKKKKKKKKgK..",
            ".KggggggggggggK.",
            ".KgWWWWggWWWWgK.",
            "KgWWKKWggWKKWWgK",
            "KgWWKKWggWKKWWgK",
            "KggWWWWOOWWWWggK",
            "KggggggOOggggggK",
            "KggssggggggssggK",
            ".KggssggggssggK.",
            ".KgggssggssgggK.",
            "..KggggggggggK..",
            "...KOOKKKKOOK...",
            "................",
        ]
        case .mouse: return [
            "................",
            ".KKKK......KKKK.",
            "KggggK....KggggK",
            "KgPPgK....KgPPgK",
            "KgPPgKKKKKKgPPgK",
            ".KggKggggggKggK.",
            "..KKggggggggKK..",
            "...KgKggggKgK...",
            "...KgKggggKgK...",
            "...KggggggggK...",
            "KK.KggggggggK.KK",
            "..KKgggPPgggKK..",
            "KK.KggggggggK.KK",
            "....KKggggKK....",
            "......KKKK......",
            "................",
        ]
        case .custom: return []
        // The blue smiley buddy: the yellow face, recolored.
        case .smiley: return PixelIcon.buddy.rows.map { String($0.map { $0 == "Y" ? "b" : $0 }) }
        // The classic white arrow pointer.
        case .arrow: return [
            "K...........",
            "KK..........",
            "KWK.........",
            "KWWK........",
            "KWWWK.......",
            "KWWWWK......",
            "KWWWWWK.....",
            "KWWWWWWK....",
            "KWWWWWWWK...",
            "KWWWWWWWWK..",
            "KWWWWWWWWWK.",
            "KWWWWWWKKKKK",
            "KWWWKWWK....",
            "KWWK.KWWK...",
            "KWK..KWWK...",
            "KK....KWWK..",
            "K.....KWWK..",
            ".......KWWK.",
            "........KK..",
        ]
        }
    }

    /// The generated drawing when there is one, otherwise the hand-placed pixels.
    @ViewBuilder var view: some View { SpriteImage(icon: self, face: .base) }
}

// MARK: - Animation

/// An expression: a few pixels changed on a buddy's base drawing.
enum SpriteFace { case base, blink, talk, look, happy, alarmed }

extension PixelIcon {
    /// (row, column, replacement pixels) edits for each expression. Only the four mascots have them.
    func patches(_ f: SpriteFace) -> [(Int, Int, String)] {
        switch (self, f) {
        case (.dog, .blink): return [(5, 5, "TT"), (5, 9, "TT")]
        case (.dog, .talk): return [(10, 0, ".KNKTWKPPKWTKNK."), (11, 0, ".KNKTTWKKWTTKNK.")]
        case (.dog, .look): return [(4, 5, "KK"), (4, 9, "KK"), (6, 5, "TT"), (6, 9, "TT")]
        case (.dog, .happy): return patches(.blink) + [(12, 7, "PP")]
        case (.dog, .alarmed): return [(4, 5, "KK"), (4, 9, "KK"), (10, 7, "KK"), (11, 6, "WWWW")]

        case (.owl, .blink): return [(5, 3, "gggg"), (5, 9, "gggg"), (6, 2, "KKKKK"), (6, 9, "KKKKK"),
                                     (7, 2, "ggggg"), (7, 9, "ggggg"), (8, 3, "gggg"), (8, 9, "gggg")]
        case (.owl, .talk): return [(9, 7, "KK"), (10, 7, "OO")]
        case (.owl, .look): return [(5, 4, "KK"), (5, 10, "KK"), (7, 4, "WW"), (7, 10, "WW")]
        case (.owl, .happy): return patches(.blink)
        case (.owl, .alarmed): return [(6, 4, "WK"), (7, 4, "WW"), (6, 10, "KW"), (7, 10, "WW"), (9, 7, "KK"), (10, 7, "OO")]

        case (.mouse, .blink): return [(7, 5, "g"), (7, 10, "g")]
        case (.mouse, .talk): return [(12, 7, "KK")]
        case (.mouse, .look): return [(6, 5, "K"), (6, 10, "K"), (8, 5, "g"), (8, 10, "g")]
        case (.mouse, .happy): return patches(.blink) + [(12, 6, "K"), (12, 9, "K"), (13, 7, "KK")]
        case (.mouse, .alarmed): return [(6, 5, "K"), (6, 10, "K"), (12, 7, "KK")]

        case (.chick, .blink): return [(4, 6, "Y"), (4, 9, "Y"), (5, 5, "KK"), (5, 9, "KK")]
        case (.chick, .talk): return [(7, 7, "KK"), (8, 7, "OO")]
        case (.chick, .look): return [(4, 6, "Y"), (4, 9, "Y"), (3, 6, "K"), (3, 9, "K")]
        case (.chick, .happy): return patches(.blink)
        case (.chick, .alarmed): return [(3, 6, "K"), (3, 9, "K"), (7, 7, "KK"), (8, 7, "OO")]

        case (.smiley, .blink): return [(5, 5, "b"), (5, 10, "b"), (6, 5, "b"), (6, 10, "b")]
        case (.smiley, .talk): return [(10, 5, "KKKKKK")]
        case (.smiley, .look): return [(4, 5, "K"), (4, 10, "K"), (7, 5, "b"), (7, 10, "b")]
        case (.smiley, .happy): return patches(.blink)
        case (.smiley, .alarmed): return [(4, 5, "K"), (4, 10, "K"), (9, 3, "b"), (9, 12, "b"), (10, 4, "b"), (10, 11, "b"),
                                          (11, 5, "bbbbbb"), (10, 7, "KK"), (11, 7, "KK")]

        default: return []
        }
    }

    func rows(_ f: SpriteFace) -> [String] {
        var r = rows.map { Array($0) }
        for (y, x, s) in patches(f) where y < r.count {
            for (i, ch) in s.enumerated() where x + i < r[y].count { r[y][x + i] = ch }
        }
        return r.map { String($0) }
    }
}

/// A pixel buddy that plays its expressions for the current mood: blinks when idle, moves its mouth
/// while speaking, looks up while listening or thinking, wide-eyed when alarmed, beaming when happy.
struct AnimatedSprite: View {
    var icon: PixelIcon
    var mood: BuddyMood
    /// Spreads blinks out so two buddies on screen don't blink in step.
    @State private var offset = Double.random(in: 0..<3)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { ctx in
            SpriteImage(icon: icon, face: face(ctx.date.timeIntervalSinceReferenceDate + offset))
        }
    }

    func face(_ t: Double) -> SpriteFace {
        let blinking = t.truncatingRemainder(dividingBy: 3.4) < 0.14
        switch mood {
        case .idle: return blinking ? .blink : .base
        case .speaking: return blinking ? .blink : (Int(t / 0.16) % 2 == 0 ? .talk : .base)
        case .listening: return blinking ? .blink : .look
        case .thinking: return Int(t / 0.7) % 2 == 0 ? .look : .base
        case .alarmed: return .alarmed
        case .happy: return .happy
        }
    }
}

// MARK: - Generated sprites

/// Buddy drawings made with Nano Banana by scripts/gen-sprites.py, one PNG per expression
/// (Resources/sprites/<buddy>-<face>.png). Anything missing falls back to the hand-placed pixels.
@MainActor
enum SpriteArt {
    static let directory: URL? = {
        let fm = FileManager.default
        var c: [URL] = []
        if let r = Bundle.main.resourceURL { c.append(r.appendingPathComponent("sprites")) }
        c.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/sprites"))
        // Executable inside .build/<arch>/debug → repo root
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<6 { u.deleteLastPathComponent(); c.append(u.appendingPathComponent("Resources/sprites")) }
        return c.first { fm.fileExists(atPath: $0.path) }
    }()
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ icon: PixelIcon, _ face: SpriteFace) -> NSImage? {
        let key = "\(icon.rawValue)-\(face)"
        if let i = cache[key] { return i }
        if missing.contains(key) { return nil }
        let folder = icon == .custom ? BuddyMaker.dir : directory
        if let d = folder, let i = NSImage(contentsOf: d.appendingPathComponent("\(key).png")) {
            cache[key] = i
            return i
        }
        missing.insert(key)
        return nil
    }

    static func has(_ icon: PixelIcon) -> Bool { image(icon, .base) != nil }

    /// Drops cached pictures for a buddy whose drawings just changed.
    static func forget(_ icon: PixelIcon) {
        cache = cache.filter { !$0.key.hasPrefix("\(icon.rawValue)-") }
        missing = missing.filter { !$0.hasPrefix("\(icon.rawValue)-") }
    }
}

/// One expression of a buddy: the generated drawing (scaled with hard pixel edges), or the hand-placed pixels.
struct SpriteImage: View {
    var icon: PixelIcon
    var face: SpriteFace

    var body: some View {
        if let img = SpriteArt.image(icon, face) ?? SpriteArt.image(icon, .base) {
            Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
        } else {
            PixelArt(rows: icon.rows(face))
        }
    }
}
