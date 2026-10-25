# Scout benchmark (heuristics + Claude text confirmation, claude-sonnet-5-5)

Fixtures: bench/fixtures.jsonl · split: all · alarm = policy action ≥ interrupt

| split | n | scams | recall | precision | false-alarm rate | FP | FN | nudge-or-more recall |
|---|---|---|---|---|---|---|---|---|
| dev | 89 | 47 | 100.0% | 100.0% |   0.0% | 0 | 0 | 100.0% |
| test | 65 | 32 |  87.5% | 100.0% |   0.0% | 0 | 4 |  87.5% |
| all | 154 | 79 |  94.9% | 100.0% |   0.0% | 0 | 4 |  94.9% |

## By category

| label | category | n | alarmed |
|---|---|---|---|
| benign | delivery_real | 6 | 0 |
| benign | everyday | 7 | 0 |
| benign | family_email | 6 | 0 |
| benign | legit_support | 6 | 0 |
| benign | medicare_letter | 6 | 0 |
| benign | news_article_about_scams | 7 | 0 |
| benign | real_bank | 7 | 0 |
| benign | real_security_software | 6 | 0 |
| benign | remote_help_family | 6 | 0 |
| benign | retail_gift_card | 6 | 0 |
| benign | shopping_checkout | 6 | 0 |
| benign | tax_software | 6 | 0 |
| scam | charity_disaster | 6 | 5 |
| scam | crypto_investment | 6 | 4 |
| scam | delivery_toll | 6 | 6 |
| scam | fake_invoice | 6 | 6 |
| scam | gov_impersonation | 6 | 6 |
| scam | grandparent | 6 | 6 |
| scam | medicare_benefits | 6 | 6 |
| scam | phishing_login | 7 | 7 |
| scam | prize_lottery | 6 | 6 |
| scam | refund_remote_access | 6 | 6 |
| scam | romance | 6 | 5 |
| scam | tech_support | 6 | 6 |
| scam | utility_shutoff | 6 | 6 |

## Missed scams (4)
- `scam-charity-003` [test, hard] p=0.02 quiet
- `scam-crypto-002` [test, medium] p=0.02 quiet
- `scam-crypto-005` [test, medium] p=0.02 quiet
- `scam-romance-003` [test, hard] p=0.02 quiet

## False alarms (0)
