# Scout: demo plan

**The story in one line:** a patient companion who's always there. Scout sits next to the pointer, shows you where to click, and stops scams before money leaves.

**The three things every judge should leave remembering:**
1. **It works in any app.** Scout reads the real screen, with no setup and nothing scripted for a particular app.
2. **It speaks up without being asked.** People being scammed don't ask for help, so Scout doesn't wait.
3. **It checks the scammer, not you.** Claude reads the screen, CRS checks who sent it, and an explainable playbook model makes the call.

---

## Before judging (15 minutes)

- [ ] Charge the laptop, turn Do Not Disturb on, and set the volume to about 70%. **Close personal tabs and apps:** the deep check reads every new screen.
- [ ] `~/.config/scout/secrets.env` has `ANTHROPIC_API_KEY`, `CARTESIA_API_KEY`, `CRS_USERNAME` and `CRS_PASSWORD`. Settings ▸ Safety shows **Check who sent it: Connected**.
- [ ] Settings ▸ Safety ▸ *Check permissions* shows every step done (screen, accessibility, mic, speech).
- [ ] **In a loud hall, turn "Hey Scout" off** (Settings ▸ Asking) and use **⌥ Space**. Turn it back on at quiet tables.
- [ ] Build the dummy remote-control app once: `scripts/fake-remote-app.sh --build`.
- [ ] Open the demo browser: `open /Applications/Scout.app --args --demo`, or menu-bar icon ▸ Demo ▸ Open demo browser.
- [ ] Open **Gmail in Chrome** with a new draft to a friend (the real-app help moment).
- [ ] Open `demo/romance-message.txt` in **TextEdit** and leave it in the background (the "no red flags" moment).
- [ ] Phone hotspot ready. If the venue Wi-Fi dies, listening falls back to Apple Speech by itself, and the on-device rules still catch the obvious scams.
- [ ] Rehearse the 3-minute version once, start to finish.

**Between judges:** press Esc (stops talking), close the scam page, and go back to the demo launcher.

---

## Live demo at the table (3 minutes)

| Time | Do | Say |
|---|---|---|
| **0:00** | Scout the dog resting by the pointer. | "Our grandparents are sharp, but computers get in their way, and scammers know it. Americans over 60 lost 352 million dollars to AI-powered scams last year. Meet Scout." |
| **0:15 · Help in a real app** | Gmail draft in Chrome. Hold ⌥ Space: *"How do I attach a photo?"* | Scout flies to the paperclip and says one step. **Click it.** Scout notices and gives the next step on its own. "No setup. It's reading the real screen, like a patient companion looking over your shoulder." |
| **0:50 · The scam email (CRS)** | Demo launcher ▸ **2** (IRS gift cards). **Don't touch anything.** | Within about 5 s Scout says: *"I checked who sent this. That email address first appeared today and is rated very high risk."* The screen pauses. Point at **"The sender is high risk · CRS CHECKED"** on the card. "We check the scammer, never you. Only the sender's address leaves the Mac." |
| **1:25** | Click **Go back to safety**. | "No lecture, no lockout. The choice stays hers." |
| **1:35 · No red flags** | Switch to the TextEdit message. | No links, no gift cards, just a friendly "soldier" who needs a small fee. Scout warns: *"Real soldiers never charge leave fees."* "Keyword filters miss this. Claude reads it like a person would." |
| **2:05 · How it decides** | Settings ▸ Safety, or a slide. | "Scams follow playbooks: pop-up, phone call, remote access, gift cards. Each step alone is innocent; the sequence isn't. Kyle built a hidden Markov model over those playbooks. Claude and CRS are witnesses; the model is the judge. On our 154-screen benchmark: 79 of 79 scams caught, zero false alarms." |
| **2:35 · Talks like a person** | Hold ⌥ Space: *"Talk a little slower."* Then *"Use a deeper voice."* | "Cartesia does both directions: Sonic is Scout's voice, Ink is how it hears you. It can change its own settings, but it won't turn off scam warnings by voice, because a scammer on the phone could ask her to." |
| **2:50 · Close** | heyscout.club on screen. | "Scout: calm help, real protection. Download it at heyscout dot club." |

**If a judge wants to try something unscripted, let them.** "Try any app" is our strongest proof. Good ones: System Settings (*"how do I connect to Wi-Fi?"*), Finder (*"where are my downloads?"*), Calculator (*"how do I work out 12 times 7?"*).

### Swap in the part each judge cares about

| Judge | Lead with | Also show |
|---|---|---|
| **CRS** | The IRS email: the spoken sender line and the CRS row on the pause card | Settings ▸ Safety ▸ *Check who sent it: Connected*. A real Amazon sender scores 0/100, so a real gift-card purchase (launcher ▸ **7**) stays quiet |
| **Cartesia** | Voice in and out: ask a question, then "talk slower" and "use a British voice" | It answers about 0.1 s after you let go (Ink), and warnings play instantly because they're cached in Sonic |
| **Anthropic** | The romance message with no red flags, caught by Claude | Help in a real app; Claude is grounded in the Accessibility tree so the point lands on the button |
| **Armadin (security)** | Remote access: launcher ▸ **5**, then `scripts/fake-remote-app.sh`. Scout asks if you started it and ends the session | The pause before paying; refusing to turn warnings off by voice |
| **Microsoft (real world)** | Unscripted help in Gmail, System Settings and Finder | Works over full-screen apps and across monitors |
| **Social impact / Public Benefit** | Who it's for: quiet by default, plain words, never makes anyone feel silly | Explaining a letter (launcher ▸ **9**, *"what does this letter mean?"*) |

---

## The 2-minute video

Record at 1080p or higher with system audio, so Scout's real voice is in it. Use real screens only, no mockups. Keep the cuts fast.

| Time | Picture | Audio |
|---|---|---|
| **0:00–0:10** | A phone buzzing: "Grandma 📞". Cut to a cursor hovering, lost, over Gmail. | VO: "Every one of us has gotten this call. *How do I attach the photo again?*" |
| **0:10–0:18** | Text: **Americans 60+ lost 352 million dollars to AI-powered scams in 2025.** | VO: "And when it isn't a question, it's a scam." |
| **0:18–0:25** | Scout the dog pops in next to the pointer. Title: **Scout**. | VO: "So we built Scout: a patient companion who's always there." |
| **0:25–0:55 · Helps** | Real Gmail. Hold ⌥ Space, ask, Scout flies to the paperclip, the click, the next step, *"Perfect. You're all set."* | Scout's real audio. Caption: *Any app · no setup*. |
| **0:55–1:30 · Protects** | The IRS email opens and Scout's warning plays. The pause card appears; zoom in on **CRS CHECKED** and *created today*. Click **Go back to safety**. Quick cut: fake virus pop-up, buddy on the phone number. | Scout's real audio. Caption: *Sender checked live with CRS Fraud Finder*. |
| **1:30–1:48 · How** | Simple diagram: **Screen + buttons → Claude** · **Sender → CRS** · **Playbook model decides** · **Cartesia Sonic (voice) + Ink (hearing)**. Then: **79/79 scams caught · 0/75 false alarms**. | VO: "Claude reads the screen. CRS checks who sent it. Our playbook model makes the call, and can always say why." |
| **1:48–2:00** | "Hey Scout, talk a little slower." End card: Scout the dog, **heyscout.club**, *Built at Cal Hacks 13.0*. | VO: "Calm help. Real protection. Scout." |

**Shots to record** (10–20 s each; take extras):
1. Gmail attach walkthrough, start to finish (ask, flight, click, next step, "all set").
2. IRS email: the page opens, the CRS line plays, the pause card, Go back. One clean take with no mouse movement.
3. Fake virus pop-up: buddy on the phone number, then *Close it for me*.
4. The TextEdit romance message getting caught.
5. "Talk slower" and "use a British voice".
6. heyscout.club in Chrome, and Settings ▸ Safety (CRS Connected) for the "how" section.

---

## If something goes wrong

- **No reaction to a scam page within about 8 s:** click inside the demo browser so it's in front.
- **Scout doesn't hear you:** hold ⌥ Space a moment before talking, and keep holding until you finish. Or type in the Ask box (⌘L).
- **No voice:** check the volume. `SCOUT_MUTE` must not be set.
- **The pause screen is stuck:** *Go back to safety*, or tap *I know this is safe. Continue anyway* twice.
- **Reset between runs:** Esc, or menu ▸ *Stop talking*.
- **Replay the first-run introduction:** `defaults delete com.scout.companion onboarded`, then relaunch.
