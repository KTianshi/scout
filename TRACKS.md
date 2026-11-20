# Scout: tracks and what to write for each

Ordered by how strong our fit is. Each section has a paragraph ready to paste into Devpost's per-prize questions (or the write-up), and what has to be true on the day.

**Numbers we can stand behind (all measured, reproducible):**
- **79 of 79 scams caught, 0 of 75 false alarms** on our 154-screen benchmark (Claude-backed detection; `scout-bench --model-all`). Rules alone caught 36.7%; rules plus Claude on flagged screens 93.7%.
- **All 10 demo pages correct:** 6 scams warn or block, 4 look-alikes (birthday gift card, real bank statement, Medicare letter, attaching a PDF) stay quiet.
- **CRS, live sandbox:** `notice@irs-gov-payments.co` → 100/100, created today. `auto-confirm@amazon.com` → 0/100, around since 2006.
- **Speed:** a question is transcribed about **0.1 s** after the key is released (Cartesia Ink); "Hey Scout" answers in about 1 s; help starts speaking in about 2 s.

---

## 1. [Anthropic] Claude for Public Benefit ($5k + Claude credits)

**Fit:** the strongest one. Older adults losing savings to scams is plainly public benefit, and Claude does the hard parts.

> Scout is a patient on-screen companion for older adults: it shows them where to click in any app and steps in, unasked, when a scam appears. Claude does the seeing and the explaining. For help, Claude reads a screenshot together with the macOS Accessibility tree, so every step is grounded in a real button and Scout's pointer lands on it. For protection, Claude reads each new screen and catches scams that have no keywords at all, like a friendly "soldier" who needs a small fee. We deliberately don't let Claude be the only judge: its verdict is one piece of evidence in an explainable playbook model, alongside CRS's check of the sender. On our 154-screen benchmark, that combination caught every scam with zero false alarms. Scout stays quiet unless it matters, uses plain words, and never makes anyone feel silly.

**Show:** real-app help (Gmail), the romance message with no red flags.

## 2. Cal Hacks: Best People-First Social Impact

**Fit:** who it helps and why they'd actually use it is the whole project.

> One app for two everyday problems older adults face on a computer: tasks that are confusing, and scammers who target them. The usual fix is calling family. Scout is a companion that's always there: it speaks calmly, gives one step at a time, watches for your click before the next one, and stays silent unless there's a real scam. When money or a password is about to go somewhere risky, it pauses the screen and explains why in plain words. The choice always stays with the person. It works in any app with no setup, and the wake word listens on-device.

## 3. [CRS] Best Use of CRS API ($2k / $1k)

**Fit:** CRS runs live inside the scam decision, not beside it. Requirement: *use the sandbox meaningfully and show it working live in the demo.*

> Scout uses CRS Fraud Finder to check the scammer, never the person it protects. When a suspicious screen shows a sender's email address, Scout sends only that address to CRS, in parallel with Claude's look at the screen. CRS's answer (risk score, domain risk, when the address first appeared) becomes calibrated evidence in our playbook model: a high-risk sender adds the same weight as Claude's own flag. Then Scout says it out loud, *"I checked who sent this. That email address first appeared today and is rated very high risk,"* and shows it on the pause screen with a "CRS checked" badge. A scammer can copy the IRS logo perfectly, but not a ten-year history for their address. In the live sandbox, a fake IRS sender scores 100/100 (created today) and Amazon's real sender scores 0/100 (since 2006), so real messages stay quiet.

**On the day:** `CRS_USERNAME` / `CRS_PASSWORD` in secrets.env on the demo laptop (Settings ▸ Safety shows *Connected*). Demo the IRS email live.

## 4. [Cartesia] Best Use of Cartesia ($1.5k)

**Fit:** both directions of Scout's voice are Cartesia.

> Scout is a voice-first companion for older adults, and Cartesia is both its voice and its ears. **Sonic** speaks every answer, streamed sentence by sentence so Scout starts talking while Claude is still thinking, in twelve warm voices described by how they sound, at three speeds. Scam warnings are cached in advance, so they play the instant a scam appears. **Ink** (`ink-2`, streaming) transcribes push-to-talk with the names of the person's running apps as keyterms; the question is ready about 0.1 s after the key is released. Apple's recognizer runs on the same audio as a backup, so a flaky connection never loses a question. You can even ask Scout to change its own voice or speed out loud.

**Show:** ask a question, then "talk slower", then "use a British voice".

## 5. [Armadin] Best Security Hack

> Scout is anti-fraud that lives where the fraud happens: on the screen. It models scams as playbooks over time (pop-up → phone call → remote access → bank → gift cards) with a hidden Markov model, so one odd screen isn't an alarm but the sequence is. It spots remote-control apps like AnyDesk opening during a scam and offers to end the session. It pauses the screen before gift-card codes, card numbers, an SSN or a password go to a risky page. And it's hardened against social engineering of the protector itself: scam warnings can't be turned off by voice, because a scammer on the phone could tell the victim to say it.

## 6. [Microsoft] Built for the Real World

> Nothing in Scout is scripted for a particular app. It reads the live screen and Accessibility tree of whatever is in front (Gmail, Finder, System Settings, Slack, Calculator) and points at the real control. It floats over full-screen apps, follows the pointer across monitors, recovers when the microphone changes, and falls back to on-device recognition if the network drops.

**Show:** let the judge pick an app.

## 7. Cal Hacks: Most Technically Complex

> A native Swift macOS app combining ScreenCaptureKit, the Accessibility API, streaming Claude with inline pointing tags snapped to real UI elements, streaming TTS and STT, an on-device wake word, a global action watcher that notices when you've done the step, and an explainable 25-state hidden Markov model over scam playbooks (Python reference, Swift port matching to 1e-9) fused with Claude and CRS evidence.

## 8. [MLH] Best Domain Name from GoDaddy Registry

**Domain:** **heyscout.club**. The URL is the wake word: you say "Hey Scout" to use it, and heyscout.club is where you get it. Live, with the download.

## 9. [MLH] Commit Fellowship

Opt in on Devpost and fill out MLH's form. Nothing to build.

## 10. [MLH] Best Use of Gemini API

> Scout's buddy is a character people get attached to, so anyone can make their own. In Settings ▸ Buddy, describe one ("a friendly orange tabby cat") or add a photo of a pet, and Nano Banana (`gemini-3-pro-image`) draws it as pixel art, then draws five more expressions from that first drawing (blink, talking, looking, happy, worried) so it stays the same character. Scout cleans each drawing into a crisp sprite and the new buddy flies around, talks and looks worried during scam warnings like the built-in ones. It takes about a minute.

**On the day:** `GEMINI_API_KEY` is in secrets.env on Akhil's laptop (tested: a full buddy in 78 s). Demo it last, or show a buddy made beforehand, since it takes a minute.

## Skip

Solana, Convex, Visa, Coinbase x402, Snowflake, Vultr and the rest. Bolting them on would cost hours and weaken the story.

---

## Devpost checklist

- [ ] Name: **Scout: AI Guide & Scam Guardian**. Tagline: *Sees your screen, shows you where to click, and stops scams before they start.*
- [ ] "Built with" also lists `cartesia-ink` and `crs-api` (along with swift, swiftui, claude, cartesia, screencapturekit, accessibility-api, python, hidden-markov-model, gemini).
- [ ] Try-it links: **https://heyscout.club** and the GitHub repo.
- [ ] Gallery: the pause card with CRS CHECKED, the buddy pointing in Gmail, the Settings ▸ Safety pane, the playbook diagram, the benchmark numbers.
- [ ] In "How we built it", credit Farza's open-source **Clicky** (MIT) for the pointing-cursor animation.
- [ ] Select every track above (1–10) in Devpost's prize list. Video link before 9:00 AM.
