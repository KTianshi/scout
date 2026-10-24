# Good morning ☀️ — Lookout handoff

Branch `overnight`, not pushed (`git log --oneline main..overnight` won't work: `main` has no commits; use `git log --oneline`). Everything below was run overnight unless marked *untested*.

## 1. What works, and how to run it

```bash
cd ~/Documents/GitHub/lookout
scripts/swiftw build && scripts/swiftw test     # 31 tests pass
scripts/bundle.sh                               # → build/Lookout.app
node family/server.js                           # family app → http://127.0.0.1:4545 (HOST=0.0.0.0 for your phone)
open build/Lookout.app --args --demo            # Lookout + demo browser
open demo/index.html                            # scenario launcher in a normal browser
.build/debug/lookout-bench --demo demo/scenarios [--model]
```

Verified end to end in Lookout's demo browser, with the API key from `~/.config/lookout/secrets.env`:
- **Help:** "How do I attach this PDF?" → 4 spoken steps; step 1 flies to and rings the paperclip (2–3 s to the first step).
- **Scam interrupt:** the fake Microsoft pop-up is caught by on-device heuristics within one 3 s tick. Claude confirms in about 4.5 s, then the buddy flies to the phone number and explains, and the family feed gets "Stopped: Fake tech-support pop-up" with a thumbnail.
- **All 10 demo pages are correct:** the 6 scams interrupt or pause, and the 4 safe lookalikes stay quiet, including buying a gift card for a grandkid, the real bank statement and the Medicare letter.
- **Pause before you pay:** on the fake bank login, a full-screen "Let's check with Sarah first" appears. Approve or Deny on the family app unblocks it, and Sarah's note is shown.
- **Remote-access shield:** detects "AnyDesk (Demo)" launching, warns, ends it on request, and alerts family. It was tested only against the dummy app from `scripts/fake-remote-app.sh`; no real apps were touched.
- **Explain this letter:** the Medicare letter is read back in plain sentences ("This is not a bill… the most you may owe is $48.36").
- **Onboarding:** a 4-line introduction on first launch, then the permission setup window.
- **Family app:** live SSE feed, approvals with notes, weekly summary, mobile layout, chime and vibrate. SMS is mock-only.

## 2. What you need to do by hand

1. **Grant permissions** to `build/Lookout.app` in System Settings ▸ Privacy & Security:
   - **Screen Recording:** for live screens outside the demo browser.
   - **Accessibility:** to read buttons and text in Safari, Chrome and Mail, plus ⌘W close, dictation, and the "seems stuck" click counting.
   - **Microphone** and **Speech Recognition:** for ⌥Space push-to-talk. macOS asks the first time you hold ⌥Space.

   The menu item *Set up permissions…* opens a big friendly window with an Allow button for each. The demo browser path needs **none** of these.
2. **Stable code signing (recommended):** run `scripts/make-signing-identity.sh` once, then `scripts/bundle.sh`. I did **not** run it, because it adds a certificate and trust setting to your login keychain and macOS asks for your password. Until you do, the app is signed ad-hoc and **you must re-grant permissions after every rebuild**.
3. **Optional toolchain fix:** your Command Line Tools have stale files from an older install that break plain `swift build`. `scripts/swiftw` works around it. For a permanent fix, reinstall the CLT, or run `sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap` (the newer `bridging.modulemap` replaces it). I did not touch system files.
4. **Keys:** `ANTHROPIC_API_KEY` is already in `~/.config/lookout/secrets.env`. For real SMS, add `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`, `FAMILY_PHONE` and set `LOOKOUT_SMS_ENABLED=1`. That path is written but has never been run.
5. **Heads-up:** my overnight test runs briefly popped Lookout windows onto your screen, muted. Around 03:15–03:20 the logs show someone clicking "Close it for me" and "continue anyway" on those cards. If that wasn't you, it's worth a look, but nothing else was affected.

## 3. Known bugs and rough edges (most important first)

1. **Live mode on real browsers is untested.** Without TCC permissions I could only test the demo browser. Accessibility-tree reading of Safari or Chrome pages, URL detection (`AXURL`), element snapping and ⌘W-to-close need a run-through once permissions are granted. If live mode misbehaves on stage, use the demo browser.
2. **Push-to-talk is untested live.** ⌥Space is a Carbon hotkey, so it needs no extra permission. It can clash if you use ⌥Space for something else; change it in `Voice.swift`. Typed questions (menu ▸ Ask Lookout…) are the fallback.
3. **Main display only:** screenshots and pointing are not multi-monitor aware.
4. **Heuristic recall on unseen data is 66%** (84% with Claude). Early-stage romance or pig-butchering chats with no scam vocabulary are missed in every configuration (see bench/RESULTS.md).
5. **The guardian re-reads the AX tree every 3 s** (up to 2,500 nodes). This may be heavy on huge pages; tune `guardianInterval` / `maxNodes` if the Mac feels sluggish.
6. **Pay pause triggers on any sensitive field on a risky page,** including a password box on a phishing page. That's intended, but the title says "about to enter your password" rather than a payment.
7. **The "seems stuck" nudge and dictation are implemented but untested live** (they need Accessibility).
8. **The family server has no authentication.** Anyone on the LAN can approve. Fine for a demo; put a token in front of it before real use.
9. **Help step timing:** steps after the first are spoken back to back with a short pause. The buddy doesn't wait for the user to actually click.
10. **Debug shots** (`LOOKOUT_DEBUG_SHOTS=1`) capture only Lookout's own windows, so live-mode shots won't show the app underneath.

## 4. Benchmark

154 labeled fixtures (79 scam / 75 benign), dev/test split, tuned on dev only. Full tables are in `bench/RESULTS.md`.

| configuration | test recall | test precision | test false-alarm rate |
|---|---|---|---|
| heuristics only | 65.6% | 91.3% | 6.1% |
| heuristics + Claude (p ≥ 0.10) | **84.4%** | **100%** | **0.0%** |
| heuristics + Claude (p ≥ 0.025) | 87.5% | 100% | 0.0% |

Across all 154 fixtures with Claude: 92.4% recall, 0 false alarms. Demo pages: 6/6 scams caught, 0/4 false alarms.

## 5. Suggested next steps for the remaining hours

1. **Grant permissions and rehearse DEMO.md twice** (about 30 min). This matters most. Try one live Safari page (open `demo/scenarios/tech-support.html` in Safari) to see whether live mode is stage-ready, but keep the demo browser as the plan.
2. **Put the family app on your phone** with `HOST=0.0.0.0` and check the chime and vibration on the real device.
3. **Voice polish:** download a Premium voice (System Settings ▸ Accessibility ▸ Spoken Content ▸ System voice ▸ Manage Voices ▸ "Ava (Premium)"). Lookout picks the best installed voice automatically. Or wire Cartesia behind `SpeechOutput`.
4. **Recall:** add a periodic Claude review for messaging apps (Messages, WhatsApp) so friendly-stranger openers get caught. That's the main gap in the benchmark.
5. **Pitch slide:** use the benchmark table and the architecture diagram in README.md.
