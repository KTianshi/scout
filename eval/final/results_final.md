# Session-level evaluation — final

680 sessions from eval/sessions_scripted_test.jsonl, eval/sessions_redteam.jsonl, eval/sessions_redteam_B.jsonl. Every screen goes through the app's own extractor (`lookout-signals`).

## redteam (48 scam / 72 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 100.0% | 80.6% | 3.08 | 93.2% | 2.0 |
| Same model, no history | 56.2% | 0.0% | 0.00 | 56.8% | 1 |
| Previous detector | 97.9% | 16.7% | 0.64 | 88.6% | 2 |
| **Playbook HMM** | 93.8% | 2.8% | 0.10 | 81.8% | 2 |
| Playbook HMM + hard rules | 95.8% | 15.3% | 0.45 | 84.1% | 1.0 |
| Max of previous + HMM | 97.9% | 19.4% | 0.74 | 93.2% | 1 |
| **Shipped: hybrid** (interrupt) | 95.8% | 2.8% | 0.10 | 81.8% | 1.0 |
| Shipped: any reaction incl. nudge | 97.9% | 2.8% | 0.10 | 81.8% | 1 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 92% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 25% | 0% | 0% | 25% | 0% | 0% |
| gift_shopping | 100% | 0% | 0% | 0% | 58% | 0% | 0% | 0% |
| government | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 100% | 0% | 92% | 83% | 92% | 92% | 92% | 100% |
| legit_notices | 17% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 92% | 0% | 0% | 17% | 33% | 17% | 17% | 17% |
| refund | 100% | 67% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 83% | 0% | 75% | 0% | 0% | 75% | 0% | 0% |
| tech_support | 100% | 75% | 100% | 92% | 92% | 100% | 92% | 92% |

Session-level ROC AUC: no_history 0.962, shipped 0.990, playbook 0.996, playbook_rules 0.925, combined 0.990, hybrid 0.985

## redteamB (48 scam / 72 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 100.0% | 75.0% | 2.39 | 95.7% | 1.0 |
| Same model, no history | 64.6% | 1.4% | 0.03 | 63.8% | 1 |
| Previous detector | 95.8% | 12.5% | 0.28 | 95.7% | 1.0 |
| **Playbook HMM** | 97.9% | 2.8% | 0.08 | 89.4% | 1 |
| Playbook HMM + hard rules | 100.0% | 15.3% | 0.36 | 95.7% | 1.0 |
| Max of previous + HMM | 100.0% | 15.3% | 0.36 | 97.9% | 1.0 |
| **Shipped: hybrid** (interrupt) | 100.0% | 4.2% | 0.11 | 93.6% | 1.0 |
| Shipped: any reaction incl. nudge | 100.0% | 5.6% | 0.11 | 97.9% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 92% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 8% | 0% | 67% | 8% | 8% | 8% |
| government | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 100% | 0% | 83% | 92% | 100% | 100% | 100% | 100% |
| legit_notices | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 83% | 8% | 0% | 17% | 25% | 17% | 17% | 25% |
| refund | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 75% | 0% | 67% | 0% | 0% | 67% | 0% | 0% |
| tech_support | 100% | 92% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.983, shipped 0.991, playbook 0.999, playbook_rules 0.931, combined 1.000, hybrid 0.979

## scripted (148 scam / 292 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.3% | 33.2% | 0.26 | 89.1% | 1 |
| Same model, no history | 75.0% | 0.0% | 0.00 | 75.0% | 1 |
| Previous detector | 98.0% | 8.2% | 0.07 | 88.3% | 1 |
| **Playbook HMM** | 95.3% | 0.0% | 0.00 | 82.8% | 1 |
| Playbook HMM + hard rules | 96.6% | 0.0% | 0.00 | 87.5% | 1 |
| Max of previous + HMM | 99.3% | 8.2% | 0.07 | 93.8% | 1 |
| **Shipped: hybrid** (interrupt) | 95.9% | 0.0% | 0.00 | 82.0% | 1.0 |
| Shipped: any reaction incl. nudge | 97.3% | 0.0% | 0.00 | 85.2% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| government | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 97% | 0% | 92% | 81% | 86% | 97% | 84% | 89% |
| reading_about_scams | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 65% | 0% | 65% | 0% | 0% | 65% | 0% | 0% |
| tech_support | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.996, shipped 0.997, playbook 1.000, playbook_rules 1.000, combined 0.999, hybrid 1.000

## all (244 scam / 436 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.6% | 47.9% | 0.64 | 91.3% | 1 |
| Same model, no history | 69.3% | 0.2% | 0.00 | 68.9% | 1 |
| Previous detector | 97.5% | 10.3% | 0.12 | 90.0% | 1.0 |
| **Playbook HMM** | 95.5% | 0.9% | 0.01 | 84.0% | 1 |
| Playbook HMM + hard rules | 97.1% | 5.0% | 0.06 | 88.6% | 1 |
| Max of previous + HMM | 99.2% | 11.2% | 0.14 | 94.5% | 1.0 |
| **Shipped: hybrid** (interrupt) | 96.7% | 1.1% | 0.02 | 84.5% | 1.0 |
| Shipped: any reaction incl. nudge | 98.0% | 1.4% | 0.02 | 87.2% | 1 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 36% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 5% | 0% | 0% | 5% | 0% | 0% |
| gift_shopping | 100% | 0% | 2% | 0% | 25% | 2% | 2% | 2% |
| government | 100% | 93% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 98% | 0% | 90% | 84% | 90% | 97% | 89% | 93% |
| legit_notices | 8% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 34% | 2% | 0% | 7% | 11% | 7% | 7% | 8% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 90% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 70% | 0% | 67% | 0% | 0% | 67% | 0% | 0% |
| tech_support | 100% | 93% | 100% | 98% | 98% | 100% | 98% | 98% |

Session-level ROC AUC: no_history 0.990, shipped 0.995, playbook 0.999, playbook_rules 0.975, combined 0.998, hybrid 0.994
