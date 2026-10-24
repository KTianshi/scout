import AppKit
import LookoutCore

// Lookout
//   Lookout                          normal menu-bar companion
//   Lookout --demo [scenario.html]   companion + demo browser window
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

if let fixture = opt("--fixture") {
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
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    if args.contains("--demo") {
        let i = args.firstIndex(of: "--demo")!
        let next = i + 1 < args.count && !args[i + 1].hasPrefix("--") ? args[i + 1] : nil
        delegate.openDemoOnLaunch = .some(next)
    }
    delegate.askOnLaunch = opt("--ask")
    app.delegate = delegate
    app.run()
}
}
