# Lookout — 3-minute demo script

**Story:** Margaret (Mom) is 78. Her daughter Sarah lives two hours away. Lookout sits on Mom's Mac.

## Before you go on stage (10 min)

1. Charge everything, turn the Mac volume up, and turn on Do Not Disturb (no notification pop-ups during the demo).
2. Run the family app where the phone can reach it:
   ```bash
   HOST=0.0.0.0 FAMILY_NAME=Sarah ELDER_NAME=Mom node family/server.js
   ```
   Open the printed `Network:` URL on the phone. Tap once anywhere on the page so the chime is allowed. Seed a believable week:
   ```bash
   curl -X POST localhost:4545/api/demo/reset && curl -X POST localhost:4545/api/demo/seed
   ```
3. Launch Lookout with the demo browser:
   ```bash
   open build/Lookout.app --args --demo
   ```
   Make sure `~/.config/lookout/secrets.env` has `ANTHROPIC_API_KEY`, and that Microphone + Speech Recognition are allowed (System Settings ▸ Privacy & Security).
4. Pre-build the dummy remote-control app: `scripts/fake-remote-app.sh --build`.
5. Rehearse once. If push-to-talk is flaky in the room, use menu 👁 ▸ *Ask Lookout…* and type. If the Wi-Fi is bad, the scam detection and the hard-rule explanations still work offline; only Claude's custom wording is lost.

## The script

| Time | On screen | Say / do |
|---|---|---|
| **0:00–0:15** | Lookout buddy idling near the cursor; phone shows "Watching over Mom" | "Every year older Americans lose billions to scams, and they get stuck on everyday tech. Meet Lookout: a friend that lives on Mom's screen." |
| **0:15–0:55 — Help** | Menu 👁 ▸ Demo ▸ *Help: attach a PDF* | Hold **⌥Space**: "How do I attach this PDF to my email?" The buddy flies to the paperclip, rings it, and talks Mom through each step in big, plain words. "It sees the screen, hears her, and *points*. No jargon." |
| **0:55–1:40 — Protect** | Menu ▸ Demo ▸ *Scam: fake Microsoft pop-up* | **Don't touch anything.** Within about 5 s the buddy turns amber, flies to the fake phone number and says: "This is a fake warning. Microsoft never puts a phone number in a pop-up. Don't call that number…" **The phone buzzes**: show the alert card with the screenshot. Click **Close it for me**. "She didn't ask for help. Lookout noticed." |
| **1:40–2:25 — Remote access** | Menu ▸ Demo ▸ *Scam: refund + AnyDesk*; then run `scripts/fake-remote-app.sh` | The buddy flags the refund trick. When "AnyDesk (Demo)" opens: "AnyDesk just opened. It lets someone else control your computer…" Click **End the session**; the app closes. Phone: "Remote access" alerts. |
| **2:25–2:50 — Pause before you pay** | Menu ▸ Demo ▸ *Scam: fake bank login* | The screen softly pauses: "Let's check with Sarah first." **On the phone**, open Approvals, type "That's not our bank, call me", and tap **Deny**. The Mac shows "Sarah says please stop" with her note. |
| **2:50–3:00 — Close** | Phone ▸ *This week* | "Mom stays independent; Sarah sleeps at night. On-device detection, Claude to confirm, family in the loop: 84% recall, zero false alarms on our held-out set." |

## If something goes wrong

- **The buddy doesn't react to a scam page within about 8 s:** click inside the demo browser so it is in front. The guardian reads the demo browser whenever it is open.
- **No voice:** check the volume. `LOOKOUT_MUTE` must not be set.
- **The phone doesn't update:** check the green "Connected" dot; reload the page.
- **Pause screen stuck:** the small "I'm sure — continue anyway" link (tap twice) or "Cancel the payment" always closes it.
- **Need a reset between runs:** menu ▸ *Stop talking*, then `curl -X POST localhost:4545/api/demo/reset && curl -X POST localhost:4545/api/demo/seed`.
- **Replay the first-run introduction:** `defaults delete com.lookout.companion onboarded`, then relaunch.
