import Foundation

/// "Hey Scout, talk slower", "use a deeper voice", "be the owl": Scout changes its own settings when asked, instead
/// of sending the person off to find a Settings window. Checked before Claude, so it's instant and works offline.
/// A request must be about Scout itself ("you", "your voice", "talk"), so "how do I make my mouse faster?" is still help.
@MainActor
enum SelfSettings {
    /// Returns true when the request was a settings change (and has been answered).
    static func handle(_ q: String, companion c: Companion) async -> Bool {
        let t = " " + q.lowercased().replacingOccurrences(of: "[^a-z' ]+", with: " ", options: .regularExpression) + " "
        func has(_ phrases: String...) -> Bool { phrases.contains { t.contains(" \($0) ") } }
        let m = c.settings.model
        let aboutScout = has("you", "your", "yourself", "scout")
        let aboutTalking = has("talk", "talking", "speak", "speaking", "voice", "sound")

        // Speed
        if aboutTalking || has("slow down", "speed up") {
            let now = VoiceSpeed.current
            if has("slower", "slow down", "more slowly", "too fast") {
                guard now != .slower else { await reply("This is as slow as I go.", c); return true }
                m.pickSpeed(now == .faster ? .normal : .slower, sample: false)
                await reply("Okay. I'll talk a little slower.", c)
                return true
            }
            if has("faster", "speed up", "quicker", "more quickly", "too slow", "hurry") {
                guard now != .faster else { await reply("This is as fast as I go.", c); return true }
                m.pickSpeed(now == .slower ? .normal : .faster, sample: false)
                await reply("Okay. I'll talk a little faster.", c)
                return true
            }
            if has("normal speed", "regular speed", "usual speed") {
                m.pickSpeed(.normal, sample: false)
                await reply("Okay. Back to my usual speed.", c)
                return true
            }
        }

        // Voice
        if has("voice") && (aboutScout || has("different", "another", "new", "change", "switch", "use")) {
            let all = ScoutVoice.all
            let i = all.firstIndex(of: .current) ?? -1
            func next(_ ok: (ScoutVoice) -> Bool) -> ScoutVoice? {
                (1...all.count).lazy.map { all[(i + $0 + all.count) % all.count] }.first(where: ok)
            }
            let named = all.first { v in v.keywords.contains { has($0) } }
            let pick: ScoutVoice?
            if let named { pick = named }
            else if has("lower", "deeper", "man", "male", "guy", "man's") { pick = next { $0.lower } }
            else if has("higher", "woman", "female", "lady", "woman's") { pick = next { !$0.lower } }
            else { pick = next { _ in true } }
            if let pick {
                m.pickVoice(pick, sample: false)
                await reply("Okay. This is my new voice. How does it sound?", c)
            }
            return true
        }

        // Buddy
        if has("be", "become", "turn into", "switch to", "change to", "change into", "look like", "be a", "be the") && aboutScout || has("be a", "be the", "turn into", "switch to the") {
            let styles: [(BuddyStyle, [String])] = [(.owl, ["owl", "hoot"]), (.chick, ["chick", "chicken", "clicken", "bird"]),
                                                    (.mouse, ["mouse"]), (.dog, ["dog", "puppy", "doggy"]), (.cursor, ["cursor", "arrow"])]
            if let (style, _) = styles.first(where: { $0.1.contains { has($0) } }) {
                m.pickStyle(style)
                await reply("Okay! How do I look?", c)
                return true
            }
        }

        // "Hey Scout"
        if has("hey scout") {
            if has("stop listening", "turn off", "don't listen", "stop", "disable") {
                m.setWakeWord(false)
                await reply("Okay. I'll stop listening for Hey Scout. Hold \(TalkShortcut.current.spoken) when you need me.", c)
                return true
            }
            if has("listen for", "turn on", "start listening", "enable") {
                m.setWakeWord(true)
                await reply("Okay. Just say Hey Scout whenever you need me.", c)
                return true
            }
        }

        // Where the buddy waits
        if aboutScout && has("stop following", "stay in the corner", "go to the corner", "stay put") {
            m.setFollows(false)
            await reply("Okay. I'll wait in the corner.", c)
            return true
        }
        if has("follow my mouse", "follow my pointer", "follow my cursor", "stay next to my mouse", "stay close") {
            m.setFollows(true)
            await reply("Okay. I'll stay right next to your pointer.", c)
            return true
        }

        // Scam warnings can't be switched off by voice: a scammer on the phone could talk someone into saying it.
        if has("scam", "scams", "warnings", "protection") && has("turn off", "stop", "disable", "don't warn", "no more", "off") && aboutScout {
            await reply("To keep you safe, scam warnings can only be turned off in my Settings window.", c)
            return true
        }

        if has("your settings", "scout settings", "scout's settings", "settings for you") {
            c.settings.show()
            await reply("Here are my settings.", c)
            return true
        }
        return false
    }

    private static func reply(_ text: String, _ c: Companion) async {
        c.overlay.setMood(.speaking)
        c.overlay.say(text)
        await c.speech.speak(text)
        c.overlay.setMood(.happy)
        try? await Task.sleep(nanoseconds: 900_000_000)
        c.overlay.reset()
    }
}
