import AppKit
import AVFoundation
import ScoutCore

// Scout
//   Scout                          normal menu-bar companion
//   Scout --say "text" [--prewarm]  voice check (Cartesia, falls back to the system voice)
//   Scout --demo [scenario.html]   companion + demo browser window
//   Scout --render-icon out.png    write the app icon (used by scripts/bundle.sh)
//   Scout --ask-box                companion with the Ask box open
//   Scout --settings               companion with the Settings window open
//   Scout --fixture <file.html|.png> [--text "..."|--text-file f] [--apps "AnyDesk,Safari"]
//           [--ask "question"] [--no-model] [--json]
//                                    headless end-to-end run (no TCC needed): signals → risk → Claude → speech text → points

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared

MainActor.assumeIsolated {

if let desc = opt("--make-buddy") {
    // Dev: draw a custom buddy from a description without opening Settings, then exit.
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
        await BuddyMaker.shared.make(name: opt("--buddy-name") ?? "My buddy", description: desc, photo: nil)
        print(BuddyMaker.shared.error ?? "made a buddy in \(BuddyMaker.dir.path)")
        exit(BuddyMaker.shared.error == nil ? 0 : 1)
    }
    app.run()
} else if let dir = opt("--render-ui") {
    app.setActivationPolicy(.accessory)
    UIRenderer.run(dir: dir, companion: Companion())
    exit(0)
} else if let out = opt("--render-icon") {
    // Build step: scripts/bundle.sh turns this PNG into AppIcon.icns.
    guard let img = AppIconView.image(), let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: out))
    exit(0)
} else if let file = opt("--stt-test") {
    // Transcribe an audio file through the push-to-talk Cartesia path: Scout --stt-test question.aiff
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
        guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: file)),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 4_096) else { print("can't read \(file)"); exit(1) }
        let stt = CartesiaSTT(hints: Listener.commonNames)
        while (try? f.read(into: buf)) != nil, buf.frameLength > 0 {
            stt.append(buf)
            try? await Task.sleep(nanoseconds: UInt64(Double(buf.frameLength) / f.processingFormat.sampleRate * 1e9))   // real time
        }
        let t = Date()
        let text = await stt.finish()
        print(String(format: "cartesia: %@  (%.2f s after the audio ended)", text ?? "(nothing)", Date().timeIntervalSince(t)))
        exit(text == nil ? 1 : 0)
    }
    app.run()
} else if let line = opt("--say") {
    // Voice check: Scout --say "Hello"   (add --prewarm to cache the standard scam lines)
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
