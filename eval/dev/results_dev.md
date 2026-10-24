# Session-level evaluation — dev

440 sessions from eval/sessions_scripted.jsonl. Every screen goes through the app's own extractor (`lookout-signals`).

## scripted (148 scam / 292 benign sessions)

| detector (alarm at p ≥ 0.5) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |
|---|---|---|---|---|---|
| Single-event rule | 98.6% | 32.9% | 0.27 | 87.5% | 1.0 |
| Same model, no history | 75.0% | 0.0% | 0.00 | 74.2% | 1 |
| Previous detector | 98.0% | 7.9% | 0.07 | 86.7% | 1 |
| **Playbook HMM** | 96.6% | 0.0% | 0.00 | 82.8% | 1 |
| Playbook HMM + hard rules | 96.6% | 0.0% | 0.00 | 85.2% | 1 |
| Max of previous + HMM | 98.6% | 7.9% | 0.07 | 91.4% | 1.0 |
| **Shipped: hybrid** (interrupt) | 96.6% | 0.0% | 0.00 | 78.9% | 1 |
| Shipped: any reaction incl. nudge | 96.6% | 0.0% | 0.00 | 80.5% | 1 |

Per kind (share of sessions alarmed; benign kinds are false alarms):

| kind | rule | no_history | shipped | playbook | playbook_rules | combined | hybrid | hybrid_any_reaction |
|---|---|---|---|---|---|---|---|---|
| banking | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| everyday | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| family_money | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| gift_shopping | 100% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| government | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| grandparent | 95% | 0% | 92% | 86% | 86% | 95% | 86% | 86% |
| reading_about_scams | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_government | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| real_invoice | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| refund | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| remote_help | 62% | 0% | 62% | 0% | 0% | 62% | 0% | 0% |
| tech_support | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Session-level ROC AUC: no_history 0.994, shipped 0.997, playbook 0.998, playbook_rules 0.998, combined 0.997, hybrid 0.998
