# Session-level evaluation — test

560 sessions from eval/sessions_scripted_test.jsonl, eval/sessions_redteam.jsonl. Every screen goes through the app's own extractor (`lookout-signals`).

## redteam (48 scam / 72 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 100.0% | 80.6% | 3.08 | 93.2% | 2.0 |
| Same model, no history | 56.2% | 0.0% | 0.00 | 56.8% | 1 |
| Previous detector | 97.9% | 16.7% | 0.64 | 88.6% | 2 |
| **Playbook HMM** | 93.8% | 2.8% | 0.10 | 81.8% | 2 |
| Playbook HMM + hard rules | 95.8% | 15.3% | 0.45 | 84.1% | 1.0 |
| Max of previous + HMM | 97.9% | 19.4% | 0.74 | 93.2% | 1 |
| **Shipped: hybrid** (interrupt) | 95.8% | 22.2% | 0.67 | 90.9% | 1.0 |
| Shipped: any reaction incl. nudge | 97.9% | 23.6% | 0.67 | 90.9% | 1 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 92% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 25% | 0% | 0% | 25% | 25% | 33% |
| gift_shopping | 100% | 0% | 0% | 0% | 58% | 0% | 58% | 58% |
| government | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 100% | 0% | 92% | 83% | 92% | 92% | 92% | 100% |
| legit_notices | 17% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 92% | 0% | 0% | 17% | 33% | 17% | 33% | 33% |
| refund | 100% | 67% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 83% | 0% | 75% | 0% | 0% | 75% | 17% | 17% |
| tech_support | 100% | 75% | 100% | 92% | 92% | 100% | 92% | 92% |

Session-level ROC AUC: no_history 0.962, shipped 0.990, playbook 0.996, playbook_rules 0.925, combined 0.990, hybrid 0.881

## scripted (148 scam / 292 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.3% | 33.2% | 0.26 | 89.1% | 1 |
| Same model, no history | 75.0% | 0.0% | 0.00 | 75.0% | 1 |
| Previous detector | 98.0% | 8.2% | 0.07 | 88.3% | 1 |
| **Playbook HMM** | 95.3% | 0.0% | 0.00 | 82.8% | 1 |
| Playbook HMM + hard rules | 96.6% | 0.0% | 0.00 | 87.5% | 1 |
| Max of previous + HMM | 99.3% | 8.2% | 0.07 | 93.8% | 1 |
| **Shipped: hybrid** (interrupt) | 99.3% | 0.0% | 0.00 | 93.8% | 1 |
| Shipped: any reaction incl. nudge | 99.3% | 0.0% | 0.00 | 95.3% | 1 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| government | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 97% | 0% | 92% | 81% | 86% | 97% | 97% | 97% |
| reading_about_scams | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 65% | 0% | 65% | 0% | 0% | 65% | 0% | 0% |
| tech_support | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.996, shipped 0.997, playbook 1.000, playbook_rules 1.000, combined 0.999, hybrid 1.000

## all (196 scam / 364 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.5% | 42.6% | 0.48 | 90.1% | 1 |
| Same model, no history | 70.4% | 0.0% | 0.00 | 70.3% | 1.0 |
| Previous detector | 98.0% | 9.9% | 0.11 | 88.4% | 1.0 |
| **Playbook HMM** | 94.9% | 0.5% | 0.01 | 82.6% | 1.0 |
| Playbook HMM + hard rules | 96.4% | 3.0% | 0.04 | 86.6% | 1 |
| Max of previous + HMM | 99.0% | 10.4% | 0.12 | 93.6% | 1.0 |
| **Shipped: hybrid** (interrupt) | 98.5% | 4.4% | 0.05 | 93.0% | 1 |
| Shipped: any reaction incl. nudge | 99.0% | 4.7% | 0.05 | 94.2% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 22% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 6% | 0% | 0% | 6% | 6% | 8% |
| gift_shopping | 100% | 0% | 0% | 0% | 14% | 0% | 14% | 14% |
| government | 100% | 96% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 98% | 0% | 92% | 82% | 88% | 96% | 96% | 98% |
| legit_notices | 17% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 22% | 0% | 0% | 4% | 8% | 4% | 8% | 8% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 92% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 69% | 0% | 67% | 0% | 0% | 67% | 4% | 4% |
| tech_support | 100% | 94% | 100% | 98% | 98% | 100% | 98% | 98% |

Session-level ROC AUC: no_history 0.992, shipped 0.996, playbook 0.999, playbook_rules 0.984, combined 0.998, hybrid 0.977
