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
        for w in NSApp.windows where w.title == "Lookout Settings" || w.title == "Set up Lookout" {
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
    case orb, cat, bear, chick, ghost, smiley

    /// The pixel version of a buddy style (the cursor style uses `.arrow` directly).
    static func sprite(for style: BuddyStyle) -> PixelIcon? {
        switch style {
        case .cursor: return nil
        case .orb: return .orb
        case .cat: return .cat
        case .bear: return .bear
        case .chick: return .chick
        case .ghost: return .ghost
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
        case .cat: return [
            "................",
            ".KK..........KK.",
            ".KOK........KOK.",
            ".KOOK......KOOK.",
            ".KOPOKKKKKKOPOK.",
            ".KOOOOOOOOOOOOK.",
            "KOOOOOOOOOOOOOOK",
            "KOOKKOOOOOOKKOOK",
            "KOOKKOOOOOOKKOOK",
            "KOOOOOOOOOOOOOOK",
            "KKKOOOOPPOOOOKKK",
            "KOOOOOOKKOOOOOOK",
            ".KKOOOKOOKOOOKK.",
            "..KOOOOOOOOOOK..",
            "...KKKKKKKKKK...",
            "................",
        ]
        case .bear: return [
            "................",
            ".KKK........KKK.",
            "KNNNK......KNNNK",
            "KNTNKKKKKKKKNTNK",
            "KNNNNNNNNNNNNNNK",
            ".KNNNNNNNNNNNNK.",
            ".KNNKKNNNNKKNNK.",
            "KNNNKKNNNNKKNNNK",
            "KNNNNNTTTTNNNNNK",
            "KNNNNTTKKTTNNNNK",
            "KNNNNTTKKTTNNNNK",
            ".KNNNTTTTTTNNNK.",
            ".KNNNNTKKTNNNNK.",
            "..KNNNNNNNNNNK..",
            "...KKKKKKKKKK...",
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
        case .ghost: return [
            "................",
            ".....KKKKKK.....",
            "...KKWWWWWWKK...",
            "..KWWWWWWWWWWK..",
            ".KWWWWWWWWWWWWK.",
            ".KWWKKWWWWKKWWK.",
            ".KWWKKWWWWKKWWK.",
            ".KWWWWWWWWWWWWK.",
            "KKWWWWWPPWWWWWKK",
            "KWWWWWWPPWWWWWWK",
            ".KWWWWWWWWWWWWK.",
            ".KWWWWWWWWWWWWK.",
            ".KWWWWWWWWWWWWK.",
            ".KWWWKWWWWKWWWK.",
            ".KWWK.KWWK.KWWK.",
            "..KK...KK...KK..",
        ]
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

    var view: PixelArt { PixelArt(rows: rows) }
}
