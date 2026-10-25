# Scout: demo video plan (~2:30)

Akhil: hook, help, voice, close. Kyle: the scam catch and how the detection works. The lines are a guide; say them your own way.

**Format:** a screen recording with Scout's real audio, and our voices over it. A small face-cam bubble in the corner while each of us talks (optional, but judges like seeing the team). Record each segment separately and cut them together.

---

## 1. Hook (Akhil, 0:00–0:20)

**On screen:** face cam, or a phone buzzing with "Grandma 📞". Cut to a cursor wandering around Gmail, lost.

> "Every one of us has gotten this call: *how do I attach the photo again?* Our grandparents are sharp, but computers get in their way. And scammers know it. Americans over 60 lost 352 million dollars to AI-powered scams last year."

**On screen:** Scout the dog pops in next to the pointer. Title card: **Scout**.

> "So we built Scout: a patient companion that's always there."

## 2. Help in a real app (Akhil, 0:20–0:55)

**On screen:** real Gmail in Chrome, a new draft open.
1. Hold ⌥ Space and ask: *"How do I attach a photo?"* (the waveform shows while you talk).
2. Scout flies to the paperclip and says one step.
3. Click it. Scout notices on its own and gives the next step.
4. Finish, and Scout says *"Perfect. You're all set."*

> "Scout sees the screen and the real buttons on it, so it points at exactly the right spot. And like a patient companion looking over your shoulder, it watches for your click and tells you the next step. No setup, and it works in any app."

**Optional quick cut (3–4 s):** System Settings, *"how do I connect to Wi-Fi?"*, the buddy lands on Wi-Fi.

## 3. Voice (Akhil, 0:55–1:20)

**On screen:** any app.
1. Hold ⌥ Space: *"Talk a little slower."* Scout confirms, slower.
2. *"Use a British voice."* Scout switches and speaks in it.
3. Quick flash of Settings ▸ Voice (the 12 voices) and Settings ▸ Asking.

> "Scout's voice runs on Cartesia both ways: Sonic is how it talks, and Ink is how it hears you. Your question is ready about a tenth of a second after you let go. You can just ask it to change its own settings. The one thing it won't do by voice is turn off scam warnings, because a scammer on the phone could tell you to say that."

**Hand-off:** "But helping is only half of it. Kyle?"

## 4. The scam catch, live (Kyle, 1:20–1:50)

**On screen:** demo launcher ▸ **2** (the fake IRS gift-card email). **Don't touch the mouse.**
1. Scout looks worried and says *"I checked who sent this. That email address first appeared today and is rated very high risk."*
2. The pause card appears. Zoom in on **"The sender is high risk · CRS CHECKED"**.
3. Click **Go back to safety**.

> "People being scammed don't know it, so they never ask for help. Scout doesn't wait to be asked. Here it read the email, checked the sender with CRS Fraud Finder (an address created today, 100 out of 100 risk), and stopped the screen before any gift card codes went out. We check the scammer, never you: only the sender's address leaves the computer."

**Optional quick cut (3 s):** the fake virus pop-up, the buddy on the fake phone number, *Close it for me*.

## 5. How it decides (Kyle, 1:50–2:15)

**On screen:** a simple diagram: `pop-up → phone call → remote access → bank → gift cards`, with **Claude** and **CRS** arrows feeding into **Playbook model → stay quiet / warn / pause**. Then the TextEdit romance message (`demo/romance-message.txt`) getting caught (2–3 s), then the benchmark card.

> "Scams follow playbooks. A fake virus pop-up, then a phone call, then remote access, then gift cards. Any single step can be innocent: families really do use AnyDesk, and people really do buy gift cards. But the sequence isn't. I built a hidden Markov model over those playbooks, so Scout tracks the odds a scam is in progress and can always explain why. Claude reads the screen and CRS checks the sender, but they're witnesses; the model is the judge. That's how it catches a friendly 'soldier' message with no scam keywords at all, and stays quiet on a real birthday gift card. On our 154-screen benchmark: 79 of 79 scams caught, zero false alarms."

**Benchmark card:** **79 / 79 scams caught · 0 / 75 false alarms** (154 screens).

## 6. Close (Akhil, 2:15–2:30)

**On screen:** heyscout.club in Chrome, then the end card: Scout the dog, **heyscout.club**, *Akhil Reddy · Kyle Tianshi · Cal Hacks 13.0*.

> "Calm help. Real protection. It only speaks up when it matters. Scout. Download it at heyscout dot club."

---

## Recording checklist

- **Before recording:** turn on Do Not Disturb, close personal tabs (the deep check reads screens), set the volume to about 70%, and open the demo browser (`open /Applications/Scout.app --args --demo`). Have Gmail and `demo/romance-message.txt` ready.
- **Turn "Hey Scout" off while recording** (Settings ▸ Asking) so the voice-over doesn't trigger it. Use ⌥ Space for the asks.
- **Get two clean takes** of segments 2 and 4. Don't move the mouse while the scam page loads.
- **Record internal audio** so Scout's voice is clear: QuickTime / ⌘⇧5 with internal audio, or BlackHole. Record the voice-over separately if the room is noisy.
- **Cut tight:** dead air under 1 s, and speed up the waits (Claude thinking) to 2×.
