# Lookout

A friendly animated companion that lives on an older adult's Mac screen. It can see the screen, listen, talk and point at things. It does two jobs:

1. **Help.** Step-by-step, spoken help with everyday tasks: "How do I attach this PDF?", "What does this Medicare letter mean?" The buddy flies to each button as it explains.
2. **Protect.** It notices scams *without being asked*. It points right at the threat (the fake phone number, the gift-card box, the "Download AnyDesk" button), explains calmly what is wrong and what to do, and alerts family. Before money or a password goes to a risky page, it pauses the screen until a family member approves.

Built for a CalHacks demo. Every user-facing word aims to be calm, short and plain.

## Quick start

```bash
# 1. Build + test (scripts/swiftw wraps `swift` to work around this Mac's Command Line Tools; see below)
scripts/swiftw build
scripts/swiftw test

# 2. Family app (phone view for the adult child)
node family/server.js                 # http://127.0.0.1:4545   (HOST=0.0.0.0 to open it from a phone on the same Wi-Fi)

# 3. The Mac app
scripts/bundle.sh                     # → build/Lookout.app (signed)
open build/Lookout.app --args --demo  # opens the demo browser too
```

Put your key in `~/.config/lookout/secrets.env` (or export it):

```
ANTHROPIC_API_KEY=sk-ant-...
ELDER_NAME=Mom
FAMILY_NAME=Sarah
```

Without a key, Lookout still runs the on-device scam detector and hard rules, and help mode falls back to pointing at the demo page's marked target.

## Using it

- **Ask:** hold **⌥ Option + Space**, talk, let go. Or menu bar 👁 ▸ *Ask Lookout…* to type.
- **Explain:** menu ▸ *Explain what's on screen*, or say "What does this letter mean?"
- **Dictation:** say "type …" with a text box focused (needs Accessibility).
- **Protection** runs by itself every 3 seconds (menu ▸ *Watching for scams* toggles it).
- **Demo:** menu ▸ *Demo* opens any scenario in Lookout's own demo browser.

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
    Overlay        transparent click-through window; the buddy (idle bob, fly-to-point, alarmed, listening) + big-text bubble
    ScreenObserver ScreenCaptureKit snapshot + Accessibility tree of the frontmost window (text, elements, URL, secure fields)
    DemoBrowser    Lookout's own WebKit window; reads text + exact element rects from the DOM (no permissions needed)
    Companion      help walkthroughs, guardian loop, interrupts, remote-access shield, pause-before-pay, stuck nudge, dictation
    Voice          SpeechOutput protocol → AVSpeechSynthesizer (best Premium/Enhanced voice); ⌥Space push-to-talk → Apple Speech
    Panels         clickable action card, full-screen "Let's check with Sarah first" pause, permission setup window
    FamilyClient   events + approval requests to the family server
    FixtureRunner  `Lookout --fixture page.html` runs the whole pipeline headless
  LookoutBench  `lookout-bench`: precision / recall / false alarms over bench/fixtures.jsonl
family/         zero-dependency Node server + one mobile-first page: live feed (SSE), approvals, weekly summary
demo/           10 local scenario pages (6 scams, 4 safe lookalikes) + launcher
bench/          154 labeled fixtures (dev/test split) + results
```

### How protection decides

1. **Every 3 s** the guardian reads the screen (Accessibility text + URL, or the demo browser's DOM) and runs `ScamSignals`. This is cheap and runs on the device.
2. `RiskEngine` folds the signals into remembered evidence, so a scam that unfolds over several screens (refund email → phone call → AnyDesk → bank page) accumulates. A repeated screen does not inflate risk, and address-specific evidence only counts while that page is showing.
3. If P(scam) ≥ 0.10 or a hard rule fires, **Claude confirms** with a screenshot (`claude-sonnet-5-5`, structured JSON verdict, plain-language explanation, pixel point of the threat).
4. `ActionPolicy` picks the cheapest action given the costs, with higher stakes when payment fields are visible or a remote-control app is running. A confident "safe" from Claude caps the reaction at a nudge unless a hard rule fires.
5. **Interrupt:** the buddy turns amber, flies to the threat, says what is wrong and what to do, shows a big "Close it for me / I'm OK" card, and posts a family alert with a thumbnail. **Block:** a full-screen calm pause plus a family approval request; Approve/Deny on the phone unblocks it.

### Benchmark (see `bench/RESULTS.md`)

| | held-out test recall | precision | false alarms |
|---|---|---|---|
| on-device heuristics only | 65.6% | 91.3% | 6.1% |
| heuristics + Claude confirmation | **84.4%** | **100%** | **0%** |

## Testing without permissions

```bash
.build/debug/Lookout --fixture demo/scenarios/tech-support.html            # signals → risk → Claude → speech → point
.build/debug/Lookout --fixture demo/scenarios/email-attach.html --ask "How do I attach this PDF?"
.build/debug/Lookout --fixture screenshot.png --text "screen text…" --apps "AnyDesk,Safari"
.build/debug/lookout-bench --demo demo/scenarios [--model] [--verbose]
node family/test.js
```

Useful environment switches: `LOOKOUT_MUTE=1` (no audio), `LOOKOUT_MODEL`, `LOOKOUT_CONFIRM_THRESHOLD`, `LOOKOUT_FAMILY_URL`, `LOOKOUT_DEBUG_SHOTS=1` (saves images of Lookout's *own* windows to `~/Library/Application Support/Lookout/shots/`), `LOOKOUT_ONBOARD=1` (replay onboarding), and the test-only `LOOKOUT_TEST_AUTOCLICK` and `LOOKOUT_TERMINATE_ONLY_DEMO`.

## Privacy

- Screenshots and screen text are sent to the Claude API only for help requests and for scam confirmation, and are never written to disk. The exception is `LOOKOUT_DEBUG_SHOTS`, which saves only Lookout's own windows, under `~/Library/Application Support/Lookout/`.
- The log (`~/Library/Application Support/Lookout/lookout.log`) records decisions and spoken text, never API keys.
- Family alerts carry a small thumbnail only when an interrupt fires.

## Build notes

This Mac's Command Line Tools have stale files from an older install (`usr/include/swift/module.modulemap` and an old `PackageDescription` private interface), which break every `swift build`. `scripts/swiftw` hides them with a VFS overlay without touching system files. If you reinstall the CLT, plain `swift build` works and `swiftw` becomes a pass-through.

## Credits

Patterns adapted from [OpenClicky](https://github.com/jasonkneen/openclicky) (MIT); see `THIRD_PARTY_NOTICES.md`.
