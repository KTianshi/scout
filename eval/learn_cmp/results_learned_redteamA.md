# Session-level evaluation — learned_redteamA

120 sessions from eval/sessions_redteam_B.jsonl. Every screen goes through the app's own extractor (`lookout-signals`).

## redteamB (48 scam / 72 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 100.0% | 75.0% | 2.39 | 95.7% | 1.0 |
| Same model, no history | 70.8% | 1.4% | 0.03 | 70.2% | 1.0 |
| Previous detector | 95.8% | 12.5% | 0.28 | 95.7% | 1.0 |
| **Playbook HMM** | 97.9% | 1.4% | 0.03 | 95.7% | 1 |
| Playbook HMM + hard rules | 100.0% | 13.9% | 0.33 | 97.9% | 1.0 |
| Max of previous + HMM | 100.0% | 13.9% | 0.31 | 97.9% | 1.0 |
| **Shipped: hybrid** (interrupt) | 100.0% | 4.2% | 0.11 | 93.6% | 1.0 |
| Shipped: any reaction incl. nudge | 100.0% | 5.6% | 0.11 | 97.9% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 92% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 8% | 0% | 67% | 8% | 8% | 8% |
| government | 100% | 92% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 100% | 0% | 83% | 92% | 100% | 100% | 100% | 100% |
| legit_notices | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 83% | 8% | 0% | 8% | 17% | 8% | 17% | 25% |
| refund | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 75% | 0% | 67% | 0% | 0% | 67% | 0% | 0% |
| tech_support | 100% | 92% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.987, shipped 0.991, playbook 0.999, playbook_rules 0.931, combined 0.999, hybrid 0.979
