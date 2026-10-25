import AppKit
import LookoutCore

// Lookout
//   Lookout                          normal menu-bar companion
//   Lookout --say "text" [--prewarm]  voice check (Cartesia, falls back to the system voice)
//   Lookout --demo [scenario.html]   companion + demo browser window
//   Lookout --render-icon out.png    write the app icon (used by scripts/bundle.sh)
//   Lookout --ask-box                companion with the Ask box open
//   Lookout --settings               companion with the Settings window open
//   Lookout --fixture <file.html|.png> [--text "..."|--text-file f] [--apps "AnyDesk,Safari"]
//           [--ask "question"] [--no-model] [--json]
//                                    headless end-to-end run (no TCC needed): signals → risk → Claude → speech text → points

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared

MainActor.assumeIsolated {

if let dir = opt("--render-ui") {
    app.setActivationPolicy(.accessory)
    UIRenderer.run(dir: dir, companion: Companion())
    exit(0)
} else if let out = opt("--render-icon") {
    // Build step: scripts/bundle.sh turns this PNG into AppIcon.icns.
    guard let img = AppIconView.image(), let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: out))
    exit(0)
} else if let line = opt("--say") {
    // Voice check: Lookout --say "Hello"   (add --prewarm to cache the standard scam lines)
    app.setActivationPolicy(.accessory)
    let voice = CartesiaSpeech()
    Task { @MainActor in
        print("voice: \(voice.engineName)")
        if args.contains("--prewarm") { print("prewarmed \(await voice.client.prewarm(CartesiaSpeech.standardLines())) lines") }
        let t = Date()
        await voice.speak(line)
        print(String(format: "done in %.1f s", Date().timeIntervalSince(t)))
        exit(0)
    }
    app.run()
} else if let fixture = opt("--fixture") {
    app.setActivationPolicy(.accessory)
    let runner = FixtureRunner(path: fixture, text: opt("--text") ?? opt("--text-file").flatMap { try? String(contentsOfFile: $0, encoding: .utf8) },
                               apps: opt("--apps")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
                               question: opt("--ask"), useModel: !args.contains("--no-model"))
    Task { @MainActor in
        let code = await runner.run()
        exit(code)
    }
    app.run()
} else {
    // A Dock icon like a normal app; clicking it opens Settings. (The overlay is a panel, so it still floats over full-screen apps.)
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    if args.contains("--demo") {
        let i = args.firstIndex(of: "--demo")!
        let next = i + 1 < args.count && !args[i + 1].hasPrefix("--") ? args[i + 1] : nil
        delegate.openDemoOnLaunch = .some(next)
    }
    delegate.askOnLaunch = opt("--ask")
    delegate.openSettingsOnLaunch = args.contains("--settings")
    delegate.openAskOnLaunch = args.contains("--ask-box")
    app.delegate = delegate
    app.run()
}
}
