import AppKit
import SwiftUI
import Combine

/// Transparent, click-through window covering a screen; hosts the buddy and its speech bubble.
/// A non-activating panel rather than a plain window: with a Dock icon, only panels can float over
/// other apps' full-screen spaces.
/// Window setup adapted from OpenClicky's OverlayWindow (MIT); see THIRD_PARTY_NOTICES.md.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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

    var color: Color {
        switch self {
        case .alarmed: return Color(red: 0.96, green: 0.55, blue: 0.16)
        case .listening: return Color(red: 0.30, green: 0.62, blue: 0.98)
        case .thinking: return Color(red: 0.48, green: 0.52, blue: 0.95)
        case .happy: return Color(red: 0.25, green: 0.74, blue: 0.52)
        default: return Color(red: 0.22, green: 0.56, blue: 0.93)
        }
    }
}

/// How the buddy looks. Picked from the menu; remembered across launches.
enum BuddyStyle: String, CaseIterable {
    // Scout the dog is the mascot and the default; Hoot, Mouse and Clicken are its friends.
    case dog, owl, mouse, chick, cursor, orb, cat, bear, ghost, classic

    var title: String {
        switch self {
        case .dog: return "Scout the dog 🐶"
        case .owl: return "Hoot the owl 🦉"
        case .mouse: return "Mouse the mouse 🐭"
        case .cursor: return "Blue cursor"
        case .orb: return "Glowing dot"
        case .cat: return "Cat 🐱"
        case .bear: return "Bear 🐻"
        case .chick: return "Clicken 🐥"
        case .ghost: return "Ghost 👻"
        case .classic: return "Smiley face"
        }
    }
    /// Short name for the Settings tiles.
    var name: String {
        switch self {
        case .dog: return "Scout"
        case .owl: return "Hoot"
        case .mouse: return "Mouse"
        case .cursor: return "Cursor"
        case .orb: return "Glow"
        case .cat: return "Cat"
        case .bear: return "Bear"
        case .chick: return "Clicken"
        case .ghost: return "Ghost"
        case .classic: return "Smiley"
        }
    }
    var emoji: String? {
        switch self {
        case .dog: return "🐶"
        case .owl: return "🦉"
        case .mouse: return "🐭"
        case .cat: return "🐱"
        case .bear: return "🐻"
        case .chick: return "🐥"
        case .ghost: return "👻"
        default: return nil
        }
    }

    static var current: BuddyStyle {
        get { UserDefaults.standard.string(forKey: "buddyStyle").flatMap(BuddyStyle.init) ?? .dog }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "buddyStyle") }
    }
}

/// Observable state the overlay renders. All positions are in the overlay's SwiftUI space (top-left origin).
@MainActor
final class BuddyState: ObservableObject {
    @Published var position: CGPoint = CGPoint(x: 200, y: 200)
    @Published var mood: BuddyMood = .idle
    @Published var bubble: String? = nil
    @Published var bubbleTitle: String? = nil
    /// A small hint under the bubble text (e.g. how to ask for the next step). Cleared with the bubble.
    @Published var hint: String? = nil
    /// Where the bubble sits. Fixed when it appears so it doesn't chase the cursor; moves only when the buddy flies.
    @Published var bubbleAnchor: CGPoint = .zero
    @Published var pointing: Bool = false
    @Published var highlight: CGRect? = nil
    /// What the buddy is pointing at: not drawn, but the bubble is kept off it.
    var avoid: CGRect? = nil
    /// Off hides the resting buddy; it still appears to warn or answer.
    @Published var visible: Bool = !UserDefaults.standard.bool(forKey: "buddyHidden") {
        didSet { UserDefaults.standard.set(!visible, forKey: "buddyHidden") }
    }
    @Published var listeningLevel: CGFloat = 0
    @Published var style: BuddyStyle = .current
    /// Swells mid-flight (see Overlay.flyArc).
    @Published var flightScale: CGFloat = 1
    /// The cursor-style buddy's heading: -35° at rest (like a pointer), along the arc in flight.
    @Published var rotation: Double = -35
    /// Small Clicky-style tag at the target ("right here!"), typed out a letter at a time.
    @Published var tag: String = ""
    @Published var tagScale: CGFloat = 1
    /// The pointer is over the bubble: fade it so whatever is underneath can be seen and clicked.
    @Published var bubbleFaded = false

    /// Put the bubble beside the buddy, on screen, and never on top of what it's pointing at.
    func bubblePosition(in size: CGSize) -> CGPoint {
        let p = bubbleAnchor
        let w: CGFloat = 380
        // Rough height: ~30 characters per line at 19 pt, plus title and padding.
        let chars = CGFloat((bubble ?? "").count)
        let h: CGFloat = max(70, ceil(chars / 30) * 27 + (bubbleTitle == nil ? 34 : 60))
        let avoid = (avoid ?? highlight ?? CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60)).insetBy(dx: -14, dy: -14)
        let gap: CGFloat = 36
        let candidates = [
            CGPoint(x: p.x + gap + w / 2, y: p.y + h / 2 + 14),   // right, below
            CGPoint(x: p.x - gap - w / 2, y: p.y + h / 2 + 14),   // left, below
            CGPoint(x: p.x + gap + w / 2, y: p.y - h / 2 - 30),   // right, above
            CGPoint(x: p.x - gap - w / 2, y: p.y - h / 2 - 30),   // left, above
            CGPoint(x: avoid.midX, y: avoid.minY - h / 2 - 12),   // straight above the target
            CGPoint(x: avoid.midX, y: avoid.maxY + h / 2 + 12),   // straight below the target
        ]
        func clamped(_ c: CGPoint) -> CGPoint {
            CGPoint(x: min(max(c.x, w / 2 + 16), size.width - w / 2 - 16), y: min(max(c.y, h / 2 + 16), size.height - h / 2 - 16))
        }
        func rect(_ c: CGPoint) -> CGRect { CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h) }
        // Keep the side it first appeared on while the text streams in; only move if it would cover the target.
        let key = "\(Int(p.x)),\(Int(p.y))"
        if let (k, i) = lockedSide, k == key, !rect(clamped(candidates[i])).intersects(avoid) { return clamped(candidates[i]) }
        for (i, c) in candidates.map(clamped).enumerated() where !rect(c).intersects(avoid) { lockedSide = (key, i); return c }
        return clamped(candidates[0])
    }
    /// Which placement the bubble took for the current anchor (plain var: set during layout, never published).
    private var lockedSide: (String, Int)?

    /// Where the pointer tag goes: just right of the buddy like Clicky, or to its left near the screen's right edge.
    func tagPosition(in size: CGSize) -> CGPoint {
        let half = (18 + CGFloat(tag.count) * 7.6) / 2
        var x = position.x + 12 + half
        if x + half > size.width - 8 { x = position.x - 12 - half }
        return CGPoint(x: max(half + 8, x), y: position.y + 20)
    }

    /// The bubble's rough on-screen rect (same size estimate as the placement).
    func bubbleRect(in size: CGSize) -> CGRect {
        let c = bubblePosition(in: size)
        let chars = CGFloat((bubble ?? "").count)
        let h: CGFloat = max(70, ceil(chars / 30) * 27 + (bubbleTitle == nil ? 34 : 60))
        return CGRect(x: c.x - 190, y: c.y - h / 2, width: 380, height: h)
    }
}

/// Owns the overlay window and moves the buddy around.
@MainActor
final class Overlay {
    let state = BuddyState()
    private var window: OverlayWindow?
    private var followTask: Task<Void, Never>?
    private var handle: BuddyHandle?
    private(set) var screen: NSScreen
    /// While pointing or talking the buddy stays put; otherwise it rests at its home spot.
    var isPinned = false
    /// Trails the cursor like a cursor buddy, or parks in a corner (drag to move, click to ask).
    /// Rests in the corner by default; following the pointer is a choice in Settings ▸ Buddy, remembered.
    /// LOOKOUT_DOCK=1 forces the corner.
    var followsCursor: Bool = ProcessInfo.processInfo.environment["LOOKOUT_DOCK"] != "1" && UserDefaults.standard.bool(forKey: "buddyFollows") {
        didSet {
            UserDefaults.standard.set(followsCursor, forKey: "buddyFollows")
            guard window != nil else { return }
            // The drag handle only exists in docked mode; next to the cursor it would swallow clicks.
            handle?.close()
            handle = followsCursor ? nil : BuddyHandle(overlay: self)
            if !followsCursor, !isPinned {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { state.position = home }
            }
        }
    }
    /// Offset of the resting buddy from the cursor tip.
    static let cursorOffset = CGPoint(x: 35, y: 25)   // Clicky's offset: sits just below-right of the real pointer
    /// Where the buddy rests, in overlay coordinates. Drag the buddy to move it; remembered across launches.
    var home: CGPoint {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: "buddyHomeX") != nil {
                return clamp(CGPoint(x: d.double(forKey: "buddyHomeX"), y: d.double(forKey: "buddyHomeY")))
            }
            let vf = screen.visibleFrame
            return toOverlay(CGPoint(x: vf.maxX - 70, y: vf.minY + 70))
        }
        set {
            UserDefaults.standard.set(Double(newValue.x), forKey: "buddyHomeX")
            UserDefaults.standard.set(Double(newValue.y), forKey: "buddyHomeY")
        }
    }
    /// Clicking the buddy (without dragging).
    var onTap: (() -> Void)?

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
        watchSpaces()
        state.position = followsCursor ? cursorTarget() : home
        // The drag handle only exists in docked mode; next to the cursor it would swallow clicks.
        if !followsCursor { handle = BuddyHandle(overlay: self) }
        // A main-actor loop rather than a Timer + assumeIsolated, which crashed in the executor check.
        followTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self else { return }
                self.followPointerToItsScreen()
                if self.followsCursor { self.followCursor() }
                self.handle?.sync()
                self.fadeBubbleUnderCursor()
            }
        }
    }

    /// Swiping to another desktop or a full-screen app: make sure the buddy is there too, and log whether it is.
    func watchSpaces() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let w = self.window else { return }
                w.orderFrontRegardless()
                Log.info("space changed: overlay on this space=\(w.isOnActiveSpace) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-")")
            }
        }
    }

    /// The display Scout is on, for screenshots (it lives on the screen with the pointer).
    var displayID: CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Multiple monitors: when the pointer moves to another screen (and Scout isn't busy pointing or
    /// talking), the overlay moves there with it, like Clicky.
    private func followPointerToItsScreen() {
        guard !isPinned, state.bubble == nil, let w = window else { return }
        let mouse = NSEvent.mouseLocation
        guard !screen.frame.contains(mouse), let next = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        screen = next
        w.setFrame(next.frame, display: true)
        w.contentView?.frame = NSRect(origin: .zero, size: next.frame.size)
        state.position = followsCursor ? cursorTarget() : home
    }

    private func fadeBubbleUnderCursor() {
        let over = state.bubble != nil
            && state.bubbleRect(in: screen.frame.size).insetBy(dx: -16, dy: -16).contains(toOverlay(NSEvent.mouseLocation))
        if over != state.bubbleFaded { state.bubbleFaded = over }
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 40), screen.frame.width - 40), y: min(max(p.y, 40), screen.frame.height - 40))
    }

    /// Overlay point → global AppKit point (bottom-left origin).
    func toAppKit(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + screen.frame.minX, y: screen.frame.maxY - p.y)
    }

    /// Called while the user drags the buddy.
    func dragged(to p: CGPoint) {
        state.position = clamp(p)
    }

    func dragEnded() {
        home = state.position
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

    func cursorTarget() -> CGPoint {
        toOverlay(NSEvent.mouseLocation).applying(.init(translationX: Self.cursorOffset.x, y: Self.cursorOffset.y))
    }

    private func followCursor() {
        guard !isPinned else { return }
        let target = cursorTarget()
        let cur = state.position
        let dx = target.x - cur.x, dy = target.y - cur.y
        if abs(dx) + abs(dy) < 0.5 { return }
        // Snappy but smooth: most of the way each frame, so it feels attached to the cursor.
        state.position = CGPoint(x: cur.x + dx * 0.35, y: cur.y + dy * 0.35)
    }

    /// Fly to a point in overlay coordinates and point at it.
    func fly(to p: CGPoint, highlight: CGRect? = nil) {
        isPinned = true
        // The pointer tip sits up-left of the body, so park the body down-right of the target
        // (just outside the highlighted element when we know it) so the target stays readable.
        var body = CGPoint(x: p.x + 34, y: p.y + 34)
        if let h = highlight { body = CGPoint(x: min(h.maxX, p.x + 140) + 26, y: h.maxY + 26) }
        if state.style == .cursor {
            // Like Clicky: the triangle's tip lands right at the target (8 right, 12 below).
            // The tip sits up-left of the triangle's center, so this puts the nose on the target point.
            body = CGPoint(x: p.x + 8, y: p.y + 12)
        }
        let clamped = CGPoint(
            x: min(max(body.x, 30), screen.frame.width - 30),
            y: min(max(body.y, 30), screen.frame.height - 30)
        )
        state.bubbleAnchor = clamped
        state.tag = ""
        // No box around the target (it read as "wrong place" when the box and the control didn't line up):
        // like Clicky, the cursor's nose is the pointer. The rect is kept only so the bubble stays clear of it.
        state.avoid = highlight
        withAnimation(.easeOut(duration: 0.25)) {
            state.pointing = true
        }
        flyArc(to: clamped) { [weak self] in self?.typeTag() }
    }

    private static let tagPhrases = ["right here!", "this one!", "over here!", "click this!", "here it is!"]
    /// When pointing at a threat (a scam link, a fake phone number), the tag warns instead of inviting a click.
    private static let warningPhrases = ["don't click!", "careful!", "not this one!"]
    private var tagTask: Task<Void, Never>?

    /// Clicky's pointer tag: pops in small and springs up, then types a short phrase with a natural rhythm.
    /// (From Clicky's OverlayWindow.streamNavigationBubbleCharacter, MIT.)
    private func typeTag() {
        tagTask?.cancel()
        guard state.pointing else { return }
        let phrase = (state.mood == .alarmed ? Self.warningPhrases : Self.tagPhrases).randomElement() ?? "careful!"
        // Arrived: nose back to the resting pointer angle so it points at the target (Clicky's -35°).
        withAnimation(.easeInOut(duration: 0.3)) { state.rotation = -35 }
        state.tag = ""
        state.tagScale = 0.5
        tagTask = Task { @MainActor [weak self] in
            for (i, ch) in phrase.enumerated() {
                guard let self, !Task.isCancelled, self.state.pointing else { return }
                self.state.tag.append(ch)
                if i == 0 { withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { self.state.tagScale = 1 } }
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.03...0.06) * 1e9))
            }
        }
    }

    private var flight: Task<Void, Never>?

    /// Swoops along a quadratic bezier arc with smoothstep easing, swelling at the apex and settling on landing.
    /// Adapted from Clicky's OverlayWindow.animateBezierFlightArc (MIT); see THIRD_PARTY_NOTICES.md.
    func flyArc(to end: CGPoint, completion: (@MainActor () -> Void)? = nil) {
        flight?.cancel()
        let start = state.position
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 2 else {
            state.position = end
            state.flightScale = 1
            withAnimation(.easeInOut(duration: 0.3)) { state.rotation = -35 }
            completion?()
            return
        }
        let duration = min(max(distance / 900, 0.45), 1.1)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let control = CGPoint(x: mid.x, y: mid.y - min(distance * 0.2, 80))
        let began = Date()
        flight = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let linear: CGFloat = min(1, CGFloat(Date().timeIntervalSince(began)) / duration)
                let t: CGFloat = linear * linear * (3 - 2 * linear)
                let u: CGFloat = 1 - t
                let a: CGFloat = u * u, b: CGFloat = 2 * u * t, c: CGFloat = t * t
                let x: CGFloat = a * start.x + b * control.x + c * end.x
                let y: CGFloat = a * start.y + b * control.y + c * end.y
                self.state.position = CGPoint(x: x, y: y)
                self.state.flightScale = 1 + CGFloat(sin(Double(linear) * .pi)) * 0.3
                // Face the direction of travel (tangent of the curve); +90° because the tip points up at 0°.
                let tx: CGFloat = 2 * u * (control.x - start.x) + 2 * t * (end.x - control.x)
                let ty: CGFloat = 2 * u * (control.y - start.y) + 2 * t * (end.y - control.y)
                self.state.rotation = Double(atan2(ty, tx)) * 180 / .pi + 90
                if linear >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.state.flightScale = 1
            withAnimation(.easeInOut(duration: 0.3)) { self.state.rotation = -35 }
            completion?()
        }
    }

    /// Glide somewhere and stay, without pointing.
    func moveTo(_ p: CGPoint) {
        isPinned = true
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { state.position = p; state.bubbleAnchor = p; state.pointing = false }
    }

    func say(_ text: String?, title: String? = nil) {
        if text != nil, state.bubble == nil { state.bubbleAnchor = state.position }
        if text == nil || text != state.bubble { state.hint = nil }
        withAnimation(.easeOut(duration: 0.25)) {
            state.bubble = text
            state.bubbleTitle = title
        }
    }

    func setMood(_ m: BuddyMood) {
        withAnimation(.easeInOut(duration: 0.3)) { state.mood = m }
    }

    func release() {
        let wasPointing = state.pointing
        tagTask?.cancel()
        state.tag = ""
        withAnimation(.easeOut(duration: 0.3)) {
            state.pointing = false
            state.highlight = nil
        }
        state.avoid = nil
        // Like Clicky: fly back to the pointer in an arc instead of jumping, then follow again.
        if wasPointing, followsCursor {
            flyArc(to: cursorTarget()) { [weak self] in self?.isPinned = false }
        } else {
            isPinned = false
        }
    }

    func reset() {
        release()
        say(nil)
        setMood(.idle)
        if !followsCursor {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { state.position = home }
        }
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
                if state.visible || state.bubble != nil || state.mood != .idle {
                    BuddyView(style: state.style, mood: state.mood, pointing: state.pointing, level: state.listeningLevel, rotation: state.rotation)
                        .frame(width: 64, height: 64)
                        .scaleEffect((state.style == .cursor ? 1 : (state.pointing || state.mood == .alarmed ? 0.8 : 0.6)) * state.flightScale)
                        .position(state.position)
                    if !state.tag.isEmpty {
                        PointerTag(text: state.tag, alarmed: state.mood == .alarmed)
                            .scaleEffect(state.tagScale)
                            .fixedSize()
                            .position(state.tagPosition(in: geo.size))
                    }
                    if let text = state.bubble {
                        SpeechBubble(title: state.bubbleTitle, text: text, alarmed: state.mood == .alarmed, talking: state.mood == .speaking, hint: state.hint)
                            .frame(maxWidth: 380)
                            .fixedSize(horizontal: false, vertical: true)
                            .position(state.bubblePosition(in: geo.size))
                            .opacity(state.bubbleFaded ? 0.12 : 1)
                            .animation(.easeOut(duration: 0.2), value: state.bubbleFaded)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

}

struct BuddyView: View {
    var style: BuddyStyle
    var mood: BuddyMood
    var pointing: Bool
    var level: CGFloat
    var rotation: Double = -35
    @AppStorage(ClassicLook.key) private var classicLook = false

    var body: some View {
        if classicLook, let sprite = PixelIcon.sprite(for: style) {
            EmojiBuddy(emoji: "", mood: mood, pointing: pointing, level: level, sprite: sprite)
        } else {
            styled
        }
    }

    @ViewBuilder private var styled: some View {
        switch style {
        case .cursor: CursorBuddy(mood: mood, level: level, rotation: rotation)
        case .orb: OrbBuddy(mood: mood, pointing: pointing, level: level)
        case .classic: FaceBuddy(mood: mood, pointing: pointing, level: level)
        default: EmojiBuddy(emoji: style.emoji ?? "🐱", mood: mood, pointing: pointing, level: level)
        }
    }
}

/// Clicky's look: a small glowing blue triangle that sits beside the real pointer like a second cursor.
/// A waveform replaces it while listening, a spinner while thinking. (From Clicky's OverlayWindow, MIT.)
struct CursorBuddy: View {
    var mood: BuddyMood
    var level: CGFloat
    var rotation: Double

    static let blue = Color(red: 0x33 / 255, green: 0x80 / 255, blue: 1)        // Clicky's #3380FF
    static let amber = Color(red: 1, green: 0.55, blue: 0.2)
    var color: Color { mood == .alarmed ? Self.amber : mood == .happy ? Color(red: 0.25, green: 0.78, blue: 0.5) : Self.blue }

    @AppStorage(ClassicLook.key) private var classicLook = false

    var body: some View {
        ZStack {
            Group {
                if classicLook {
                    // The classic white arrow. It already leans like a pointer, so it turns relative to the triangle's resting angle.
                    PixelIcon.arrow.view
                        .frame(width: 14, height: 22)
                        .rotationEffect(.degrees(rotation + 35), anchor: .topLeading)
                        .shadow(color: mood == .alarmed ? Self.amber : .black.opacity(0.35), radius: mood == .alarmed ? 8 : 1.5, x: 0.5, y: 1)
                } else {
                    EquilateralTriangle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(rotation))
                        .shadow(color: color, radius: mood == .alarmed ? 12 : 8)
                }
            }
            .opacity(mood == .listening || mood == .thinking ? 0 : 1)
            CursorWaveform(level: level, color: color)
                .opacity(mood == .listening ? 1 : 0)
            CursorSpinner(color: color)
                .opacity(mood == .thinking ? 1 : 0)
        }
        .animation(.easeIn(duration: 0.15), value: mood)
    }
}

/// Clicky's cursor-like triangle (equilateral, tip up before rotation).
struct EquilateralTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let size = min(rect.width, rect.height)
        let h = size * sqrt(3.0) / 2.0
        p.move(to: CGPoint(x: rect.midX, y: rect.midY - h / 1.5))
        p.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + h / 3))
        p.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + h / 3))
        p.closeSubpath()
        return p
    }
}

/// Five bars that move with the voice (Clicky's BlueCursorWaveformView).
struct CursorWaveform: View {
    var level: CGFloat
    var color: Color
    private let profile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { ctx in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color)
                        .frame(width: 2.5, height: height(i, ctx.date))
                }
            }
            .shadow(color: color.opacity(0.6), radius: 6)
        }
    }

    private func height(_ i: Int, _ date: Date) -> CGFloat {
        let phase = CGFloat(date.timeIntervalSinceReferenceDate * 3.6) + CGFloat(i) * 0.35
        let eased = pow(min(max(level - 0.008, 0) * 2.85, 1), 0.76)
        return 3 + eased * 12 * profile[i] + (sin(phase) + 1) / 2 * 1.5
    }
}

/// Small spinning arc while Claude thinks (Clicky's BlueCursorSpinnerView).
struct CursorSpinner: View {
    var color: Color
    @State private var spinning = false
    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 15, height: 15)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .shadow(color: color.opacity(0.6), radius: 6)
            .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spinning = true } }
    }
}

/// Clicky's little blue tag next to the target.
struct PointerTag: View {
    var text: String
    var alarmed: Bool
    var body: some View {
        let c = alarmed ? CursorBuddy.amber : CursorBuddy.blue
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c).shadow(color: c.opacity(0.55), radius: 6))
    }
}

/// The glowing-orb look. Breathes when idle, ripples when listening or alarmed,
/// a spinning highlight while thinking.
struct OrbBuddy: View {
    var mood: BuddyMood
    var pointing: Bool
    var level: CGFloat
    @State private var breathe = false
    @State private var pulse = false
    @State private var spin = false

    var color: Color {
        switch mood {
        case .idle, .speaking: return Color(red: 0.42, green: 0.76, blue: 1.0)
        default: return mood.color
        }
    }

    var body: some View {
        ZStack {
            if mood == .alarmed || mood == .listening {
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 2.5)
                    .frame(width: 30, height: 30)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(color)
                .frame(width: 34, height: 34)
                .blur(radius: 10)
                .opacity(mood == .speaking ? 1 : 0.8)
            Circle()
                .fill(RadialGradient(colors: [.white, color], center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: 16))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                .scaleEffect(mood == .listening ? 1 + level * 0.3 : 1)
            if mood == .thinking {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)
            }
            if pointing {
                PointerTip(color: color).offset(x: -20, y: -20)
            }
        }
        .scaleEffect(breathe ? 1.06 : 0.94)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
            pulse = true
            spin = true
        }
    }
}

/// A cute character (emoji) with a soft mood-colored glow behind it.
struct EmojiBuddy: View {
    var emoji: String
    var mood: BuddyMood
    var pointing: Bool
    var level: CGFloat
    /// Classic look: a pixel sprite in place of the emoji.
    var sprite: PixelIcon? = nil
    @State private var bob = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if mood == .alarmed || mood == .listening {
                Circle()
                    .stroke(mood.color.opacity(0.55), lineWidth: 3)
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulse ? 1.6 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(mood.color)
                .frame(width: 44, height: 44)
                .blur(radius: 10)
                .opacity(mood == .idle ? 0.25 : 0.6)
            Group {
                if let sprite { sprite.view.frame(width: 40, height: 40) }
                else { Text(emoji).font(.system(size: 44)) }
            }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .scaleEffect(mood == .listening ? 1 + level * 0.2 : 1)
            if pointing {
                PointerTip(color: mood.color).offset(x: -30, y: -30)
            }
        }
        .offset(y: bob ? -3 : 2)
        .rotationEffect(.degrees(pointing ? -8 : 0))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
            pulse = true
        }
    }
}

struct PointerTip: View {
    var color: Color
    var body: some View {
        Triangle()
            .fill(color)
            .overlay(Triangle().stroke(.white, lineWidth: 2))
            .frame(width: 18, height: 16)
            .rotationEffect(.degrees(-45))
    }
}

/// The original look: a soft round character with eyes. Bobs when idle, leans when pointing,
/// turns warm amber with a pulse when alarmed.
struct FaceBuddy: View {
    var mood: BuddyMood
    var pointing: Bool
    var level: CGFloat
    @State private var bob = false
    @State private var blink = false
    @State private var pulse = false

    var color: Color { mood.color }

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
                PointerTip(color: color).offset(x: -30, y: -30)
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
    var talking = false
    var hint: String? = nil

    var accent: Color { alarmed ? Color(red: 0.90, green: 0.45, blue: 0.08) : Color(red: 0.16, green: 0.47, blue: 0.90) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            Text(text)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(white: 0.1))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if talking {
                HStack(spacing: 5) {
                    Text("esc")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.6), lineWidth: 1))
                    Text("to stop").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(white: 0.5))
                .padding(.top, 2)
            } else if let hint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(alarmed ? Color(red: 1.0, green: 0.975, blue: 0.94) : Color.white)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(alarmed ? accent.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
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

/// A small invisible window that sits on top of the resting buddy so it can be dragged or clicked
/// (the overlay itself is click-through). Hidden while the buddy is pointing, so it never blocks a target.
@MainActor
final class BuddyHandle {
    private let panel: NSPanel
    private unowned let overlay: Overlay
    private var dragging = false
    static let size: CGFloat = 72

    init(overlay: Overlay) {
        self.overlay = overlay
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let v = HandleView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        v.onDrag = { [weak self] p in self?.dragging = true; self?.overlay.dragged(to: p) }
        v.onEnd = { [weak self] moved in
            guard let self else { return }
            self.dragging = false
            if moved { self.overlay.dragEnded() } else { self.overlay.onTap?() }
        }
        v.toOverlay = { [weak overlay] p in overlay?.toOverlay(p) ?? p }
        panel.contentView = v
        sync()
    }

    func close() { panel.orderOut(nil) }

    func sync() {
        let active = !overlay.isPinned && overlay.state.visible
        if !active { if panel.isVisible { panel.orderOut(nil) }; return }
        if !dragging {
            let c = overlay.toAppKit(overlay.state.position)
            panel.setFrameOrigin(NSPoint(x: c.x - Self.size / 2, y: c.y - Self.size / 2))
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    final class HandleView: NSView {
        var onDrag: ((CGPoint) -> Void)?
        var onEnd: ((Bool) -> Void)?
        var toOverlay: ((CGPoint) -> CGPoint)?
        private var start: CGPoint?
        private var moved = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with e: NSEvent) { start = NSEvent.mouseLocation; moved = false }
        override func mouseDragged(with e: NSEvent) {
            let m = NSEvent.mouseLocation
            if let s = start, hypot(m.x - s.x, m.y - s.y) > 4 { moved = true }
            guard moved, let p = toOverlay?(m) else { return }
            NSCursor.closedHand.set()
            onDrag?(p)
            window?.setFrameOrigin(NSPoint(x: m.x - BuddyHandle.size / 2, y: m.y - BuddyHandle.size / 2))
        }
        override func mouseUp(with e: NSEvent) { onEnd?(moved); start = nil }
    }
}
