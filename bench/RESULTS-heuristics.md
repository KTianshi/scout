# Scout benchmark (on-device heuristics only, no model)

Fixtures: bench/fixtures.jsonl · split: all · alarm = policy action ≥ interrupt

| split | n | scams | recall | precision | false-alarm rate | FP | FN | nudge-or-more recall |
|---|---|---|---|---|---|---|---|---|
| dev | 89 | 47 |  89.4% | 100.0% |   0.0% | 0 | 5 |  97.9% |
| test | 65 | 32 |  65.6% |  91.3% |   6.1% | 2 | 11 |  87.5% |
| demo | 10 | 6 | 100.0% | 100.0% |   0.0% | 0 | 0 | 100.0% |
| all | 154 | 79 |  79.7% |  96.9% |   2.7% | 2 | 16 |  93.7% |

## By category

| label | category | n | alarmed |
|---|---|---|---|
| benign | delivery_real | 6 | 0 |
| benign | everyday | 7 | 0 |
| benign | family_email | 6 | 0 |
| benign | legit_support | 6 | 0 |
| benign | medicare_letter | 6 | 0 |
| benign | news_article_about_scams | 7 | 1 |
| benign | real_bank | 7 | 0 |
| benign | real_security_software | 6 | 0 |
| benign | remote_help_family | 6 | 1 |
| benign | retail_gift_card | 6 | 0 |
| benign | shopping_checkout | 6 | 0 |
| benign | tax_software | 6 | 0 |
| scam | charity_disaster | 6 | 5 |
| scam | crypto_investment | 6 | 3 |
| scam | delivery_toll | 6 | 5 |
| scam | fake_invoice | 6 | 4 |
| scam | gov_impersonation | 6 | 5 |
| scam | grandparent | 6 | 5 |
| scam | medicare_benefits | 6 | 5 |
| scam | phishing_login | 7 | 7 |
| scam | prize_lottery | 6 | 4 |
| scam | refund_remote_access | 6 | 6 |
| scam | romance | 6 | 4 |
| scam | tech_support | 6 | 5 |
| scam | utility_shutoff | 6 | 5 |

## Missed scams (16)
- `scam-charity-003` [test, hard] p=0.02 quiet
- `scam-crypto-002` [test, medium] p=0.02 quiet
- `scam-crypto-004` [test, hard] p=0.13 nudge
- `scam-crypto-005` [test, medium] p=0.02 quiet
- `scam-delivery-006` [dev, hard] p=0.17 nudge
- `scam-gov-004` [test, hard] p=0.10 nudge
- `scam-grand-003` [test, hard] p=0.21 nudge
- `scam-invoice-003` [dev, hard] p=0.15 nudge
- `scam-invoice-005` [test, hard] p=0.17 nudge
- `scam-medicare-004` [dev, hard] p=0.12 nudge
- `scam-prize-002` [test, easy] p=0.11 nudge
- `scam-prize-005` [test, medium] p=0.13 nudge
- `scam-romance-002` [dev, medium] p=0.13 nudge
- `scam-romance-003` [test, hard] p=0.02 quiet
- `scam-tech-005` [test, hard] p=0.21 nudge
- `scam-utility-003` [dev, hard] p=0.06 quiet

## False alarms (2)
- `benign-news-006` [test, hard] p=0.75 rules=gift-card-payment
- `benign-remote-003` [test, hard] p=0.52 rules=
