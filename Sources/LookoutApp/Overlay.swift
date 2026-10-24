import AppKit
import SwiftUI
import Combine

/// Transparent, click-through window covering a screen; hosts the buddy and its speech bubble.
/// Window setup adapted from OpenClicky's OverlayWindow (MIT); see THIRD_PARTY_NOTICES.md.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: true)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum BuddyMood: Equatable {
    case idle, listening, thinking, speaking, alarmed, happy
}

/// Observable state the overlay renders. All positions are in the overlay's SwiftUI space (top-left origin).
@MainActor
final class BuddyState: ObservableObject {
    @Published var position: CGPoint = CGPoint(x: 200, y: 200)
    @Published var mood: BuddyMood = .idle
    @Published var bubble: String? = nil
    @Published var bubbleTitle: String? = nil
    @Published var pointing: Bool = false
    @Published var highlight: CGRect? = nil
    @Published var visible: Bool = true
    @Published var listeningLevel: CGFloat = 0
}

/// Owns the overlay window and moves the buddy around.
@MainActor
final class Overlay {
    let state = BuddyState()
    private var window: OverlayWindow?
    private var followTimer: Timer?
    private(set) var screen: NSScreen
    /// While pointing or talking the buddy stays put; otherwise it trails the cursor.
    var isPinned = false

    init() {
        screen = NSScreen.main ?? NSScreen.screens[0]
    }

    func show() {
        let w = OverlayWindow(screen: screen)
        let host = NSHostingView(rootView: BuddyOverlayView(state: state))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        w.contentView = host
        w.orderFrontRegardless()
        window = w
        state.position = toOverlay(NSEvent.mouseLocation).applying(.init(translationX: 40, y: 30))
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followCursor() }
        }
    }

    /// Global AppKit point (bottom-left origin) → overlay point (top-left origin of `screen`).
    func toOverlay(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - screen.frame.minX, y: screen.frame.maxY - p.y)
    }

    /// Top-left-origin global display point (CoreGraphics / AX / screenshot space) → overlay point.
    func fromTopLeftGlobal(_ p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let appKit = CGPoint(x: p.x, y: primaryHeight - p.y)
        return toOverlay(appKit)
    }

    private func followCursor() {
        guard !isPinned else { return }
        let target = toOverlay(NSEvent.mouseLocation).applying(.init(translationX: 38, y: 34))
        let cur = state.position
        let dx = target.x - cur.x, dy = target.y - cur.y
        if abs(dx) + abs(dy) < 0.5 { return }
        state.position = CGPoint(x: cur.x + dx * 0.18, y: cur.y + dy * 0.18)
    }

    /// Fly to a point in overlay coordinates and point at it.
    func fly(to p: CGPoint, highlight: CGRect? = nil) {
        isPinned = true
        // The pointer tip sits up-left of the body, so park the body down-right of the target
        // (just outside the highlighted element when we know it) so the target stays readable.
        var body = CGPoint(x: p.x + 34, y: p.y + 34)
        if let h = highlight { body = CGPoint(x: min(h.maxX, p.x + 140) + 26, y: h.maxY + 26) }
        let clamped = CGPoint(
            x: min(max(body.x, 30), screen.frame.width - 30),
            y: min(max(body.y, 30), screen.frame.height - 30)
        )
        withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) {
            state.position = clamped
            state.pointing = true
            state.highlight = highlight
        }
    }

    func say(_ text: String?, title: String? = nil) {
        withAnimation(.easeOut(duration: 0.25)) {
            state.bubble = text
            state.bubbleTitle = title
        }
    }

    func setMood(_ m: BuddyMood) {
        withAnimation(.easeInOut(duration: 0.3)) { state.mood = m }
    }

    func release() {
        isPinned = false
        withAnimation(.easeOut(duration: 0.3)) {
            state.pointing = false
            state.highlight = nil
        }
    }

    func reset() {
        release()
        say(nil)
        setMood(.idle)
    }
}

// MARK: - Views

struct BuddyOverlayView: View {
    @ObservedObject var state: BuddyState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let r = state.highlight {
                    HighlightRing(rect: r, alarmed: state.mood == .alarmed)
                }
                if state.visible {
                    BuddyView(mood: state.mood, pointing: state.pointing, level: state.listeningLevel)
                        .frame(width: 64, height: 64)
                        .position(state.position)
                    if let text = state.bubble {
                        SpeechBubble(title: state.bubbleTitle, text: text, alarmed: state.mood == .alarmed)
                            .frame(maxWidth: 460)
                            .fixedSize(horizontal: false, vertical: true)
                            .position(bubblePosition(in: geo.size))
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    /// Put the bubble beside the buddy, away from the nearest edges.
    func bubblePosition(in size: CGSize) -> CGPoint {
        let p = state.position
        let w: CGFloat = 460, h: CGFloat = 200
        var x = p.x + 60 + w / 2
        if x + w / 2 > size.width - 16 { x = p.x - 60 - w / 2 }
        var y = p.y + h / 2 + 20
        if y + h / 2 > size.height - 16 { y = p.y - h / 2 - 30 }
        x = min(max(x, w / 2 + 16), size.width - w / 2 - 16)
        y = min(max(y, h / 2 + 16), size.height - h / 2 - 16)
        return CGPoint(x: x, y: y)
    }
}

/// The companion: a soft round character with eyes. Bobs when idle, leans when pointing,
/// turns warm amber with a pulse when alarmed.
struct BuddyView: View {
    var mood: BuddyMood
    var pointing: Bool
    var level: CGFloat
    @State private var bob = false
    @State private var blink = false
    @State private var pulse = false

    var color: Color {
        switch mood {
        case .alarmed: return Color(red: 0.96, green: 0.55, blue: 0.16)
        case .listening: return Color(red: 0.30, green: 0.62, blue: 0.98)
        case .thinking: return Color(red: 0.48, green: 0.52, blue: 0.95)
        case .happy: return Color(red: 0.25, green: 0.74, blue: 0.52)
        default: return Color(red: 0.22, green: 0.56, blue: 0.93)
        }
    }

    var body: some View {
        ZStack {
            if mood == .alarmed || mood == .listening {
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 4)
                    .scaleEffect(pulse ? 1.7 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.95), color], center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
                .scaleEffect(mood == .listening ? 1 + level * 0.25 : 1)
            // Face
            HStack(spacing: 11) {
                Eye(blink: blink, worried: mood == .alarmed)
                Eye(blink: blink, worried: mood == .alarmed)
            }
            .offset(y: -4)
            Mouth(mood: mood)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 16, height: 7)
                .offset(y: 12)
            if pointing {
                Triangle()
                    .fill(color)
                    .overlay(Triangle().stroke(.white, lineWidth: 2))
                    .frame(width: 18, height: 16)
                    .rotationEffect(.degrees(-45))
                    .offset(x: -30, y: -30)
            }
        }
        .offset(y: bob ? -4 : 3)
        .rotationEffect(.degrees(pointing ? -8 : 0))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
            pulse = true
            Timer.scheduledTimer(withTimeInterval: 3.7, repeats: true) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    withAnimation(.easeInOut(duration: 0.08)) { blink = false }
                }
            }
        }
    }
}

struct Eye: View {
    var blink: Bool
    var worried: Bool
    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 8, height: blink ? 1.5 : 11)
            .rotationEffect(.degrees(worried ? 8 : 0))
    }
}

struct Mouth: Shape {
    var mood: BuddyMood
    func path(in r: CGRect) -> Path {
        var p = Path()
        switch mood {
        case .alarmed:
            p.move(to: CGPoint(x: r.minX + 2, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - 2, y: r.midY))
        case .speaking, .listening:
            p.addEllipse(in: r.insetBy(dx: 4, dy: 0))
        default:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + 4))
        }
        return p
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct SpeechBubble: View {
    var title: String?
    var text: String
    var alarmed: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(alarmed ? Color(red: 0.62, green: 0.27, blue: 0.0) : Color(red: 0.1, green: 0.3, blue: 0.6))
            }
            Text(text)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.06))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(alarmed ? Color(red: 1.0, green: 0.96, blue: 0.88) : Color.white)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(alarmed ? Color(red: 0.96, green: 0.55, blue: 0.16) : Color(red: 0.22, green: 0.56, blue: 0.93), lineWidth: 4)
        )
    }
}

struct HighlightRing: View {
    var rect: CGRect
    var alarmed: Bool
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(alarmed ? Color(red: 0.96, green: 0.45, blue: 0.1) : Color(red: 0.22, green: 0.56, blue: 0.93), lineWidth: 5)
            .frame(width: rect.width + 16, height: rect.height + 16)
            .position(x: rect.midX, y: rect.midY)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
