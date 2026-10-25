# Scout

_Formerly "Lookout": the code modules (`LookoutCore`, `LookoutApp`), the bundle id `com.lookout.companion`, `~/.config/lookout/secrets.env` and the log folder keep the old name so permissions, settings and keys carry over._

A friendly animated companion that lives on an older adult's Mac screen. It can see the screen, listen, talk and point at things. It does two jobs:

1. **Help, in any app.** Spoken help with everyday tasks: "How do I attach this PDF?", "What does this letter mean?", "What is Slack?" Each answer comes from a fresh look at the screen; the buddy flies to the right button and rings it. Ask "what next?" and it looks again, remembering the conversation.
2. **Protect.** It notices scams *without being asked*. It points right at the threat (the fake phone number, the gift-card box, the "Download AnyDesk" button) and explains calmly what is wrong and what to do. Before money or a password goes to a risky page, it pauses the screen so the person can slow down. A deep check has Claude read every new screen, so scams with no warning signs (a friendly stranger asking for money) are caught too.

Built for a CalHacks demo. Every user-facing word aims to be calm, short and plain.

## Quick start

You don't need Xcode: the Command Line Tools are enough (`xcode-select --install` if `swift --version` fails).

```bash
# 1. Build + test (scripts/swiftw wraps `swift` to work around this Mac's Command Line Tools; see below)
scripts/swiftw build
scripts/swiftw test

# 2. The Mac app
scripts/bundle.sh                     # → build/Scout.app (signed, with app icon)
cp -R build/Scout.app /Applications/ && open /Applications/Scout.app --args --demo   # opens the demo browser too
```

Put your key in `~/.config/lookout/secrets.env` (or export it):

```
ANTHROPIC_API_KEY=sk-ant-...
CARTESIA_API_KEY=sk_car_...           # Scout's voice (Sonic). The voice and speed are picked in Settings.
```

The family features (alerts to the family app, "check with Sarah first" approvals) are off. `LOOKOUT_FAMILY=1` turns them back on, with `ELDER_NAME`, `FAMILY_NAME` and `node family/server.js`.

Without a key, Scout still runs the on-device scam detector and hard rules, and help mode falls back to pointing at the demo page's marked target.

## Using it

- **Ask:** hold the talk keys (⌃⌥ Space by default), talk, let go. Or the Ask box: menu 👁 ▸ *Ask Scout…* (⌘L), or click the buddy when it rests in a corner. Optional: turn on *Say "Hey Scout"* for hands-free (on-device until the wake word).
- **Next step:** ask "what next?" By default Scout watches for your click and gives the next step on its own, like someone watching over your shoulder; turn off *Walk me through it automatically* (Settings ▸ Talking) for one step per question.
- **Stop:** Esc, hold the talk keys to talk over it, or switch apps.
- **Explain:** say "What does this letter mean?", or menu ▸ *Explain what's on screen*.
- **Dictation:** say "type …" with a text box focused (needs Accessibility).
- **Protection** runs by itself every 3 seconds (Settings ▸ Safety).
- **Settings:** click the Dock icon. Voice (six Cartesia voices, speed), buddy look (glowing orb, cat, bear, chick, ghost, smiley), show/hide, follow the pointer, talk keys, hands-free, deep check.
- **Demo:** menu ▸ *Demo* opens any scenario in Scout's own demo browser.

## Architecture

```
Package.swift
  LookoutCore   pure logic, no permissions needed, unit-tested (Swift Testing)
    ScamSignals    on-device heuristics over screen text + URL + running apps → log-odds signals
    Domains        lookalike / typosquat / punycode / official-domain checks
    RiskEngine     per-signal-kind evidence memory with a 120 s half-life → P(scam in progress)
    ActionPolicy   argmin expected cost over {quiet, nudge, interrupt, block+alert}, explicit false-alarm vs missed-scam costs
    HardRules      always-true facts ("gift cards are never payment for a bill") with spoken explanations
    ScamPipeline   signals → risk → rules → policy (+ Claude verdict) → what to say and where to point
    PointTags      [STEP:n] / [POINT:x,y:label] parsing (pattern from OpenClicky)
    Prompts        help, scam confirmation (JSON schema), letter explainer
    ClaudeClient   raw-HTTP Messages API client (streaming, vision, structured outputs, refusal fallbacks)
  LookoutApp    AppKit + SwiftUI menu-bar app
    Overlay        transparent click-through panel (floats over full-screen apps); buddy styles, fly-to-point, bubble that
                   avoids the target and fades under the pointer
    Settings       Liquid Glass settings window (voice, buddy, talking, safety); AskPanel: Spotlight-style ask box
    ScreenObserver ScreenCaptureKit snapshot + Accessibility tree of the frontmost window (text, elements, URL, secure fields)
    DemoBrowser    Scout's own WebKit window; reads text + exact element rects from the DOM (no permissions needed)
    Companion      help (one fresh step per question, streamed pointing and speech, conversation memory), guardian loop
                   with deep check, interrupts, remote-access shield, pause-before-pay, dictation, wake word
    Voice          SpeechOutput protocol → Cartesia Sonic (CartesiaClient: /tts/bytes, on-disk clip cache, scam lines prewarmed so they play
                   instantly and offline) with AVSpeechSynthesizer fallback; push-to-talk and "Hey Scout" → Apple Speech
    Panels         clickable action card, full-screen "Let's slow down" pause, permission setup window
    FamilyClient   events + approval requests to the family server (off unless LOOKOUT_FAMILY=1)
    FixtureRunner  `Scout --fixture page.html` runs the whole pipeline headless
  LookoutBench  `lookout-bench`: precision / recall / false alarms over bench/fixtures.jsonl
family/         zero-dependency Node server + one mobile-first page (only used with LOOKOUT_FAMILY=1)
demo/           10 local scenario pages (6 scams, 4 safe lookalikes) + launcher
bench/          154 labeled fixtures (dev/test split) + results
```

### How protection decides

1. **Every 3 s** the guardian reads the screen (Accessibility text + URL, or the demo browser's DOM) and runs `ScamSignals`. This is cheap and runs on the device.
2. `RiskEngine` folds the signals into remembered evidence, so a scam that unfolds over several screens (refund email → phone call → AnyDesk → bank page) accumulates. A repeated screen does not inflate risk, and address-specific evidence only counts while that page is showing.
3. If P(scam) ≥ 0.10 or a hard rule fires, **Claude confirms** with a screenshot (`claude-sonnet-5-5`, structured JSON verdict, plain-language explanation, pixel point of the threat).
4. **Deep check:** screens the rules found nothing on are read by Claude too (text only, once per settled screen, at most every 8 s). Every verdict enters the playbook engine as evidence, once per screen.
5. `ActionPolicy` picks the cheapest action given the costs, with higher stakes when payment fields are visible or a remote-control app is running. Claude's "not a scam" quiets that page for 10 minutes unless a hard rule fires (its screens still feed the engine); a "scam" verdict always warns. Low-level suspicion stays silent.
6. **Interrupt:** the buddy turns amber, flies to the threat, says what is wrong and what to do, and shows a big "Close it for me / I'm OK" card. **Block:** a full-screen calm "Let's slow down" pause with *Go back* / *Continue anyway*.

### Scam playbook engine (see `DETECTION.md`)

Scams are modelled as sequences of stages (pop-up → call → remote access → bank → payment) in one hidden Markov model with benign look-alike states (family remote help, gift shopping, banking, paying people, reading about scams). `model/playbooks.json` holds every parameter with a one-line justification; the Python reference (`lookout_detect/`) and the Swift engine (`LookoutCore/Playbook/`) read it and agree to 1e-9. Claude's findings enter only as evidence. On 680 held-out sessions it alarms on 1.1% of benign sessions vs 10.3% for the previous detector, at 96.7% recall.

### CRS sender check

On suspicious screens, the sender's email address is checked with **CRS Fraud Finder** via the family server (`POST /api/crs/check-sender`; set `CRS_USERNAME` / `CRS_PASSWORD` in `~/.config/lookout/secrets.env`). A high-risk result becomes evidence in the playbook model and a line in the buddy's warning ("that email address first appeared today and is rated very high risk"). Only the scammer's address is ever sent. See `DETECTION.md`.

### Benchmark (see `bench/RESULTS.md`)

All 154 single-screen fixtures (79 scams, 75 benign look-alikes), current playbook engine:

| | recall | false alarms |
|---|---|---|
| on-device rules + playbook only | 36.7% | 0 / 75 |
| + Claude confirmation of flagged screens | 93.7% | 1 / 75 |
| **+ deep check (Claude reads every screen)** | **100%** | **0 / 75** |

The on-device number is low by design: the playbook engine wants corroboration across screens before it alarms (see `DETECTION.md`; on 680 multi-screen sessions it catches 96.7%). `lookout-bench --model-all` reproduces the last row.

## Testing without permissions

```bash
.build/debug/Scout --say "Hello" [--prewarm]                                              # voice check (prints which engine spoke)
.build/debug/Scout --fixture demo/scenarios/tech-support.html            # signals → risk → Claude → speech → point
.build/debug/Scout --fixture demo/scenarios/email-attach.html --ask "How do I attach this PDF?"
.build/debug/Scout --fixture screenshot.png --text "screen text…" --apps "AnyDesk,Safari"
.build/debug/lookout-bench --demo demo/scenarios [--model | --model-all] [--verbose]
```

Useful environment switches: `LOOKOUT_MUTE=1` (no audio), `LOOKOUT_MODEL`, `LOOKOUT_CONFIRM_THRESHOLD`, `LOOKOUT_FAMILY_URL`, `LOOKOUT_DEBUG_SHOTS=1` (saves images of Scout's *own* windows to `~/Library/Application Support/Lookout/shots/`), `LOOKOUT_ONBOARD=1` (replay onboarding), and the test-only `LOOKOUT_TEST_AUTOCLICK` and `LOOKOUT_TERMINATE_ONLY_DEMO`.

## Privacy

- Screenshots and screen text are sent to the Claude API for help requests and scam confirmation, and screen text for the deep check (Settings ▸ Safety turns it off). Nothing is written to disk. The exception is `LOOKOUT_DEBUG_SHOTS`, which saves only Scout's own windows, under `~/Library/Application Support/Lookout/`.
- The log (`~/Library/Application Support/Lookout/lookout.log`) records decisions and spoken text, never API keys.
- Voice input is on-device (Apple Speech). With "Hey Scout" on, the microphone listens locally for the wake word; nothing is sent until it hears it.

## Build notes

This Mac's Command Line Tools have stale files from an older install (`usr/include/swift/module.modulemap` and an old `PackageDescription` private interface), which break every `swift build`. `scripts/swiftw` hides them with a VFS overlay without touching system files. If you reinstall the CLT, plain `swift build` works and `swiftw` becomes a pass-through.

## Credits

Patterns adapted from [OpenClicky](https://github.com/jasonkneen/openclicky) (MIT); see `THIRD_PARTY_NOTICES.md`.
