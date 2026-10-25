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

/// Glossy green "go" button, or the beige push button.
struct ClassicButtonStyle: ButtonStyle {
    var go: Bool

    func makeBody(configuration c: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: go ? 14 : 4, style: .continuous)
        return c.label
            .foregroundStyle(go ? Color.white : Color.black)
            .shadow(color: go ? Color(red: 0.17, green: 0.37, blue: 0.07) : .clear, radius: 0, x: 1, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, go ? 8 : 5)
            .background(shape.fill(LinearGradient(
                colors: go ? [Color(red: 0.50, green: 0.83, blue: 0.36), Color(red: 0.24, green: 0.62, blue: 0.12)]
                           : [.white, ClassicLook.face],
                startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(go ? Color(red: 0.17, green: 0.48, blue: 0.04) : Color(red: 0, green: 0.235, blue: 0.455), lineWidth: 1))
            .brightness(c.isPressed ? -0.08 : 0)
            .contentShape(shape)
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
