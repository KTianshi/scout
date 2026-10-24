# Session-level evaluation — playbooks_learned

560 sessions from eval/sessions_redteam_B.jsonl, eval/sessions_scripted_test.jsonl. Every screen goes through the app's own extractor (`lookout-signals`).

## redteamB (48 scam / 72 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 100.0% | 75.0% | 2.39 | 95.7% | 1.0 |
| Same model, no history | 79.2% | 1.4% | 0.03 | 76.6% | 1.0 |
| Previous detector | 95.8% | 12.5% | 0.28 | 95.7% | 1.0 |
| **Playbook HMM** | 100.0% | 13.9% | 0.39 | 95.7% | 1.0 |
| Playbook HMM + hard rules | 100.0% | 25.0% | 0.67 | 97.9% | 1.0 |
| Max of previous + HMM | 100.0% | 25.0% | 0.67 | 100.0% | 1.0 |
| **Shipped: hybrid** (interrupt) | 100.0% | 4.2% | 0.11 | 93.6% | 1.0 |
| Shipped: any reaction incl. nudge | 100.0% | 5.6% | 0.11 | 97.9% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 92% | 0% | 0% | 50% | 50% | 50% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 8% | 0% | 67% | 8% | 8% | 8% |
| government | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 100% | 58% | 83% | 100% | 100% | 100% | 100% | 100% |
| legit_notices | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 83% | 8% | 0% | 25% | 25% | 25% | 17% | 25% |
| refund | 100% | 83% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 75% | 0% | 67% | 8% | 8% | 67% | 0% | 0% |
| tech_support | 100% | 92% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.994, shipped 0.991, playbook 0.999, playbook_rules 0.933, combined 0.999, hybrid 0.979

## scripted (148 scam / 292 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.3% | 33.2% | 0.26 | 89.1% | 1 |
| Same model, no history | 89.9% | 0.0% | 0.00 | 89.1% | 1 |
| Previous detector | 98.0% | 8.2% | 0.07 | 88.3% | 1 |
| **Playbook HMM** | 99.3% | 0.0% | 0.00 | 96.1% | 1 |
| Playbook HMM + hard rules | 99.3% | 0.0% | 0.00 | 96.9% | 1 |
| Max of previous + HMM | 99.3% | 8.2% | 0.07 | 96.1% | 1 |
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
| grandparent | 97% | 59% | 92% | 97% | 97% | 97% | 84% | 89% |
| reading_about_scams | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 65% | 0% | 65% | 0% | 0% | 65% | 0% | 0% |
| tech_support | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.998, shipped 0.997, playbook 1.000, playbook_rules 1.000, combined 0.999, hybrid 1.000

## all (196 scam / 364 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 99.5% | 41.5% | 0.45 | 90.9% | 1 |
| Same model, no history | 87.2% | 0.3% | 0.00 | 85.7% | 1 |
| Previous detector | 97.4% | 9.1% | 0.08 | 90.3% | 1 |
| **Playbook HMM** | 99.5% | 2.7% | 0.03 | 96.0% | 1 |
| Playbook HMM + hard rules | 99.5% | 4.9% | 0.06 | 97.1% | 1 |
| Max of previous + HMM | 99.5% | 11.5% | 0.12 | 97.1% | 1 |
| **Shipped: hybrid** (interrupt) | 96.9% | 0.8% | 0.01 | 85.1% | 1.0 |
| Shipped: any reaction incl. nudge | 98.0% | 1.1% | 0.01 | 88.6% | 1.0 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 22% | 0% | 0% | 12% | 12% | 12% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 2% | 0% | 16% | 2% | 2% | 2% |
| government | 100% | 96% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 98% | 59% | 90% | 98% | 98% | 98% | 88% | 92% |
| legit_notices | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| reading_about_scams | 20% | 2% | 0% | 6% | 6% | 6% | 4% | 6% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 96% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 67% | 0% | 65% | 2% | 2% | 65% | 0% | 0% |
| tech_support | 100% | 98% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.997, shipped 0.996, playbook 1.000, playbook_rules 0.985, combined 0.999, hybrid 0.996
