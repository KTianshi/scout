# Progress

Status as of the overnight build. Each milestone ends with a passing build (`scripts/swiftw build`), passing tests (`scripts/swiftw test`) and a commit.

| # | Milestone | Status | How to try it |
|---|---|---|---|
| 0 | Skeleton: SwiftPM, bundle.sh, overlay buddy, menu bar, secrets loader | ✅ | `scripts/bundle.sh && open build/Lookout.app` |
| 1 | Help mode end to end (screenshot + AX/DOM → Claude → steps with [POINT], snapped to elements) | ✅ | Menu ▸ Demo ▸ Help: attach a PDF, then Menu ▸ Ask Lookout… “How do I attach this PDF?” |
| 2 | Voice: best installed calm voice behind `SpeechOutput`; ⌥Space push-to-talk with Apple Speech | ✅ (push-to-talk needs the bundled app + mic permission) | Hold ⌥Space and talk |
| 3 | Scam pipeline: ScamSignals → RiskEngine → Claude confirm → ActionPolicy → proactive interrupt that points at the threat | ✅ | Menu ▸ Demo ▸ Scam: fake Microsoft pop-up |
| 4 | Demo scenarios (6 scams + 4 benign) and benchmark (154 labeled fixtures) | ✅ | `open demo/index.html`; `.build/debug/lookout-bench --demo demo/scenarios` |
| 5 | Remote-access shield (detect, warn, end session, alert family) | ✅ tested only against a dummy app | `scripts/fake-remote-app.sh` while Lookout runs |
| 6 | Pause before you pay + family approval | ✅ | Menu ▸ Demo ▸ Scam: fake bank login; approve/deny in the family app |
| 7 | Family web app (live feed, approvals, weekly summary, mobile) | ✅ | `node family/server.js` → http://127.0.0.1:4545 |
| 8 | Explain this letter; “seems stuck” nudge; dictation (“type …”) | ✅ (stuck nudge + dictation need Accessibility; untested live) | Menu ▸ Explain what's on screen |
| 9 | Polish, onboarding, DEMO.md, README | see below | |

## What is stubbed / not verified
- Live (non-demo) screen reading needs Screen Recording + Accessibility, which only a human can grant. The demo browser path needs neither.
- Push-to-talk and dictation are implemented but were not exercised live (no mic permission granted overnight).
- Cartesia TTS: only the `SpeechOutput` protocol seam exists, as asked.
- Twilio SMS: code path exists in `family/server.js`, gated off; only mock-logged.
- Closing a real browser tab uses ⌘W via CGEvent (needs Accessibility). In the demo browser it navigates back to the launcher.
