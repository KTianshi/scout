import AppKit
import SwiftUI

/// A Spotlight-style box for typing a question. It's a non-activating panel, so the app the person was
/// using stays in front and Scout answers about that screen, not about this box.
@MainActor
final class AskPanel {
    private var panel: KeyPanel?
    private var resignObserver: NSObjectProtocol?

    final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    var isShowing: Bool { panel != nil }

    func show(onAsk: @escaping (String) -> Void) {
        hide()
        let view = AskView(
            onSubmit: { [weak self] q in self?.hide(); onAsk(q) },
            onCancel: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let p = KeyPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.contentView = host
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - vf.height * 0.2))
        p.makeKeyAndOrderFront(nil)
        // Clicking anywhere else closes it, like Spotlight.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        panel = p
    }

    func hide() {
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct AskView: View {
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    static let examples = ["How do I attach a file?", "What is this app?", "Explain this letter", "Is this safe?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BuddyView(style: BuddyStyle.current, mood: .idle, pointing: false, level: 0)
                    .frame(width: 64, height: 64)
                    .scaleEffect(0.6)
                    .frame(width: 40, height: 40)
                TextField("Ask Scout anything…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($focused)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { e in
                    Button { onSubmit(e) } label: {
                        Text(e)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                hint("return", "to ask")
                hint("esc", "to close")
                Spacer()
                hint(TalkShortcut.current.symbol, "hold to talk instead")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(width: 660)
        .glassCard(cornerRadius: 28)
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .padding(40)
        .onExitCommand(perform: onCancel)
        .onAppear { focused = true }
    }

    func submit() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        onSubmit(q)
    }

    func hint(_ key: String, _ what: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            Text(what).font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }
}
