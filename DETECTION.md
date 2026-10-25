# Scout's scam detector: scams as playbooks

**Idea.** Scams follow a playbook of stages. A fake tech-support scam goes pop-up → phone call → remote access → bank → gift cards. Any single step is ambiguous: families really do use AnyDesk to help, and people really do buy gift cards as presents. The *sequence* is not ambiguous. Scout models each scam type as a hidden sequence of stages, and an explainable probabilistic engine (not the LLM) decides whether a scam is in progress.

## The model (`model/playbooks.json`, one editable file)

**One combined hidden Markov model**, about 25 states:
- **Benign states:** `idle` plus look-alike activities: `remote_help` (family on AnyDesk), `gift_shopping`, `banking`, `paying_people` (a grandchild's $20 Venmo request) and `reading_about_scams`.
- **Scam playbooks**, one branch of stages each:
  - `tech_support`: popup → call → remote → banking → payment
  - `refund`: invoice → call → remote → overpay → payment
  - `grandparent`: contact → story → secrecy → payment
  - `government`: notice → threat → payment
- **Transitions:** idle enters a playbook with a tiny probability per observation. Most scams start at stage 1, and some start off-screen with a phone call.
  - Each stage then stays, advances, skips one, or abandons back to idle.
  - **Time matters:** before every observation, each state drifts back to idle with probability `1 − exp(−Δt/τ)` (τ = 30 min for scams, 15 min for benign activities). An AnyDesk launch 40 seconds after a fake pop-up is linked to it; one three days later is not.
- **Observations** are *sets* of evidence flags seen together, 18 types such as `PHONE_NUMBER_IN_POPUP`, `REMOTE_ACCESS_STARTED`, `PAYMENT_DEMAND` and `SECRECY_REQUEST`. Each flag is an independent yes/no given the state.
  - Every non-idle state is "distracted" with probability 0.3, meaning it emits like idle. Mid-scam, people still check the weather.
- **Claude never decides.** Its flag (`CLAUDE_FLAG`) is just one more observation, and it only counts on screens Claude actually looked at.
  - P(flag | scam) = 0.9 and P(flag | benign) = 0.045, from the single-screen benchmark.
  - That caps any one Claude report at +3.0 nats.

Every number in the file has a one-line "why".

## The engine (`scout_detect/engine.py`, mirrored in Swift `ScoutCore/Playbook/`)

Forward filtering in log space, one step per observation. After each step it reports:
- **P(scam)** = posterior mass on scam states; **P(type)** per playbook; and the **stage posterior** within the most likely playbook.
- **The most likely next stage** and its plain-language hint ("installing a program like AnyDesk"). It's computed but not spoken.
- **An exact evidence ledger** of log Bayes factors per flag, e.g. `REMOTE_ACCESS_STARTED +3.4`, plus a "time passes" term. The prior log-odds plus every ledger entry equals the current log-odds exactly (tested). Family alerts show the top entries: "Why: surprise refund/invoice +4.2 · remote-control app +3.1".
- **Parity:** the Swift port matches the Python reference to 1e-9 on exported vectors (`model/parity_vectors.json`, Swift `PlaybookParityTests`).

## CRS: checking the scammer, not grandma (`family/crs.js`, `SenderCheck.swift`)

When a screen is already suspicious (risk ≥ 0.10), Scout reads the **sender's email address** from it (a `mailto:` address or a "From:" line). It sends that address to **CRS Fraud Finder** (AtData email risk, CRS sandbox) through the family server, which holds the CRS keys. This runs in parallel with the Claude check.
- **The result is evidence, not a verdict.** It enters the playbook model as `CRS_SENDER_HIGH_RISK`, which, like Claude's flag, only counts on screens where the check actually ran.
- **Calibration** (sandbox):
  - `auto-confirm@amazon.com` scores **0/100**, domain risk 1/10, first seen 2006.
  - `notice@irs-gov-payments.co` and `billing@norton-renewals.info` score **100/100**, domain risk 10/10, first seen the same day.
  - P(high | scam) = 0.8, since some scammers use free mail; P(high | benign) = 0.04. One CRS answer can therefore move the odds by at most about 3 nats.
- **The buddy says:** "I checked who sent this. That email address first appeared today and is rated very high risk." The family approval card shows the score.
- **Responsible data:**
  - Only the scam message's sender address is sent, never anything about the person Scout protects.
  - It runs only on suspicious screens, with one lookup per address per day (cached).
  - Credentials stay on the family server.
  - Without credentials a clearly-labelled mock answer is used, and mock answers never change the score.
- **Not covered by the session evaluation:** every non-test CRS lookup is a billable call to their data supplier, so the evaluation numbers below are without CRS.

## What the app acts on (`ScamPipeline`)

1. **The playbook HMM decides.**
2. **The older evidence-memory detector** covers scam types without a playbook (crypto, phishing, prizes). It can raise the risk only when it is confident **and** corroborated:
   - **Claude flags the screen:** the old detector's risk must be ≥ 0.6.
   - **A "never benign" signal appears** (fake web address, secrecy, crypto ATM, legal threat, prize fee…): its risk must be ≥ 0.9.
   - **Either way**, the HMM must not be explaining the screen as a benign look-alike.
3. **Hard rules** ("gift cards are never payment for a bill") now supply explanations only. On held-out data they fired on gift shopping and on articles about scams.
4. **Policy thresholds:** a nudge needs P ≈ 0.33 and an interrupt P ≈ 0.58. They were 0.09 and 0.29, which reacted to too many ordinary screens. Payment fields or an active remote-control app lower them.

## Evaluation (`scout_detect/eval.py`, results in `eval/`)

Sessions are sequences of screens (text, URL, running apps, sensitive fields, time). **Every screen goes through the app's own Swift extractor** (`scout-signals`), so extractor misses count against the detectors. Three sources:
- **Scripted** (`scripts_gen.py`): hand-written templates with noise: skipped and out-of-order steps, everyday screens in between, abandoned scams. They are *not* sampled from the HMM, which would make the evaluation circular. Seed 7 was used for tuning; seed 99 is held out.
- **Red-team A and B** (`redteam.py`): sessions Claude wrote for each scam type and each benign look-alike. Claude never saw our model or event list.
  - **A** was used once, for model selection: it revealed that hard rules and the old detector caused most false alarms.
  - **B** was generated afterwards and is the clean held-out check.

**Final results, alarm = interrupt.** "Before payment" means caught before the payment step.

| Detector | Red-team B: caught | Red-team B: benign falsely alarmed | All 680: caught | All 680: benign falsely alarmed | All 680: false alarms/hour | All 680: before payment |
|---|---|---|---|---|---|---|
| Single-event rule | 100% | 75.0% | 99.6% | 47.9% | 0.64 | 91.3% |
| Same model, no history | 64.6% | 1.4% | 69.3% | 0.2% | 0.00 | 68.9% |
| Previous detector | 95.8% | 12.5% | 97.5% | 10.3% | 0.12 | 90.0% |
| **Playbook HMM** | 97.9% | **2.8%** | 95.5% | **0.9%** | **0.01** | 84.0% |
| **Shipped (HMM + corroborated escalation)** | **100%** | 4.2% | **96.7%** | 1.1% | 0.02 | 84.5% |

"All 680" = scripted test + red-team A + red-team B (244 scam / 436 benign sessions). Per-kind tables, ROC curves and plots are in `eval/final/`.

**What it shows:**
- **History is the point.** The same model reset before every screen catches only 69% of scams. With memory it catches 95.5%, without adding false alarms.
- **Look-alikes are handled.** The previous detector alarmed on 67% of family remote-help sessions; the playbook HMM alarmed on 0%.
- **The trade-off:** about 9× fewer false alarms than the previous detector, for about 1 point of recall. Scams are caught slightly later (84.5% before payment vs 90%), because a screen now needs corroboration.
- **Single screens** (`bench/`, 154 fixtures, with Claude confirmation): held-out recall stays 84.4%, with 0 false alarms and no nudges on benign screens.

**Learning the parameters** (`learn.py`, MAP Baum-Welch on emissions with a Beta prior centred on the hand-set values; transitions stay hand-set):

| Parameters | Red-team B: caught | Red-team B: benign falsely alarmed | Red-team B: before payment |
|---|---|---|---|
| Hand-set (shipped) | 97.9% | 2.8% | 89.4% |
| Learned on scripted sessions | 100% | 13.9% | 95.7% |
| Learned on red-team A | 97.9% | 1.4% | 95.7% |

Learning on my own templates overfits them. Learning on Claude-written sessions transfers better. The gains on B amount to 1 benign session and 3 scam sessions out of 120, so the explainable hand-set parameters stay the default. `model/playbooks_learned_redteamA.json` is ready if you want to try it.

## Known gaps

- **Articles about scams still fool the HMM about 17% of the time** on red-team B, because they read like a playbook step by step. The extractor already drops advice sentences, but more is needed.
- **Only 4 playbooks.** Crypto/romance, phishing and prize scams rely on the older detector plus Claude. Early-stage romance or "wrong number" chats with no scam vocabulary are missed everywhere.
- **Small test sets** (48 red-team scams per set), so differences of a few points are not significant.
- **Claude-written sessions are not real victim data.** Real transcripts (FTC, AARP) would be the next evaluation.

## Reproduce

```bash
python3 -m venv .venv && .venv/bin/pip install numpy pytest matplotlib anthropic
.venv/bin/python -m pytest scout_detect/tests            # engine tests
scripts/swiftw test                                         # Swift tests incl. parity
.venv/bin/python -m scout_detect.scripts_gen --seed 99 --out eval/sessions_scripted_test.jsonl
.venv/bin/python -m scout_detect.redteam --per-kind 12 --offset 100 --tag B --out eval/sessions_redteam_B.jsonl   # needs ANTHROPIC_API_KEY
.venv/bin/python -m scout_detect.eval eval/sessions_scripted_test.jsonl eval/sessions_redteam.jsonl eval/sessions_redteam_B.jsonl --out eval/final --tag final
.venv/bin/python -m scout_detect.learn eval/sessions_redteam.jsonl --out model/playbooks_learned_redteamA.json
```
