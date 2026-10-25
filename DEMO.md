# Scout — 3-minute demo script

**Story:** Margaret is 78. She's sharp, but computers get in her way, and scammers know it. Scout sits on her Mac: a calm helper that shows her where to click and stops scams before they start.

## Before you go on stage (10 min)

1. Charge everything, turn the Mac volume up, and turn on Do Not Disturb (no notification pop-ups during the demo).
2. Make sure `~/.config/lookout/secrets.env` has `ANTHROPIC_API_KEY` and `CARTESIA_API_KEY`, and that Screen Recording, Accessibility, Microphone and Speech Recognition are allowed for Scout (Settings ▸ Safety ▸ *Check permissions…*).
3. Launch Scout with the demo browser:
   ```bash
   open /Applications/Scout.app --args --demo
   ```
   Click the Dock icon once to check Settings: voice, buddy style, *Deep check with Claude* on.
4. Pre-build the dummy remote-control app: `scripts/fake-remote-app.sh --build`.
5. Open Gmail in Chrome with a draft to a friend, for the live help moment.
6. Rehearse once. If voice input is flaky in the room, use the Ask box (menu 👁 ▸ *Ask Scout…*) and type. If the Wi-Fi drops, the on-device detector and hard rules still work; only Claude's wording and the deep check are lost.

## The script

| Time | On screen | Say / do |
|---|---|---|
| **0:00–0:15** | The blue cursor buddy resting next to the pointer | "Older Americans lose billions a year to scams, and everyday tech gets in their way. Meet Scout: it lives on the screen, sees what you see, talks, and points." |
| **0:15–0:55 — Help, in a real app** | Gmail draft in Chrome | Hold the talk keys: "How do I attach a file?" The buddy flies to the paperclip, rings it, and says one short step. Click it, then: "What next?" It looks again and points at the next thing. "Any app, no setup. It reads the screen fresh every time." |
| **0:55–1:35 — Protect** | Demo launcher ▸ **1** (fake virus alert) | **Don't touch anything.** Within about 3 s the buddy turns amber, flies to the fake phone number and says why it's fake. Click **Close it for me**. "She didn't ask. Scout noticed." |
| **1:35–2:05 — Remote access** | Launcher ▸ **5**, then run `scripts/fake-remote-app.sh` | The buddy flags the refund trick. When "AnyDesk (Demo)" opens, it asks whether she started it herself; click **End the session** and the app closes. |
| **(optional) CRS sender check** | Launcher ▸ **2** (IRS gift cards) | Scout checks the email's sender with CRS Fraud Finder live: "I checked who sent this. That email address first appeared today and is rated very high risk." Say: "We check the scammer, never Grandma." (Needs `node family/server.js` running with the CRS credentials; Kyle's integration.) |
| **2:05–2:30 — Pause before you pay** | Launcher ▸ **4** (fake bank sign-in) | The screen softly pauses: "Let's slow down for a moment." Click **Go back**. "No lecture, no lockout. The choice stays hers." |
| **2:30–2:50 — Scams with no red flags** | A friendly romance message (any app; TextEdit works) | No keywords, no links. The deep check reads it and warns: "Real soldiers never ask people they met online to pay for leave papers." "Claude reads every new screen. On our 154-screen benchmark: every scam caught, zero false alarms." |
| **2:50–3:00 — Close** | Settings window | "A friend on the screen. Calm help, real protection, and it never makes her feel silly." |

## If something goes wrong

- **The buddy doesn't react to a scam page within about 8 s:** click inside the demo browser so it is in front.
- **No voice:** check the volume. `LOOKOUT_MUTE` must not be set.
- **Pause screen stuck:** "Go back", or the small "I'm sure — continue anyway" link (tap twice).
- **Need a reset between runs:** press Esc (or menu ▸ *Stop talking*).
- **Replay the first-run introduction:** `defaults delete com.scout.companion onboarded`, then relaunch.
