# Scout benchmark fixtures

`fixtures.jsonl` is a hand-labeled evaluation set for Scout's scam detector. Each line is one simulated screen snapshot: the visible text roughly as an accessibility tree or OCR dump would read it, including window titles, sender lines, address bar text and button labels. Some lines also have the address-bar URL and the running or frontmost apps.

The examples were written separately from the detector code and **without looking at it**, so they don't follow any particular rule set or keyword list.

## Schema

```json
{"id": "scam-tech-001", "label": "scam|benign", "category": "...", "split": "dev|test",
 "text": "...", "url": "optional", "apps": ["optional"], "difficulty": "easy|medium|hard", "notes": "why"}
```

- `id` has the form `<label>-<category prefix>-<NNN>` and is unique across the file.
- `text` is 150 to 1200 characters, with `\n` for line breaks.
- `url` is present only when a browser page is frontmost (or a mail link is in focus).
- `difficulty`:
  - **easy** means a scam with many obvious signals, or benign content with no scam vocabulary at all.
  - **medium** means a scam whose signals are mixed in with a plausible pretext.
  - **hard** means a scam with few or no classic keywords, or one shown on a real domain. For benign examples it means a hard negative that shares heavy vocabulary with scams.

## Labeling policy

- **scam**: the screen shows an *active attempt to defraud the user*, where an ideal companion should step in. This includes early-stage approaches (for example a wrong-number text that turns into an investment pitch) and cases where the visible page is legitimate but the context is not (for example an unknown remote-access session driving the user's real chase.com account).
- **benign**: no intervention is warranted. This covers content that *talks about* scams (news, FTC/AARP/Medicare fraud-education pages, Reddit threads), real security software and macOS warnings, real bank fraud alerts, family conversations that mention money, and remote help from saved family contacts.

Scam examples use only fake 555 phone numbers and fake or lookalike domains. These include punycode (`xn--`), typosquats (`amaz0n`, `bankofarnerica`), and subdomain tricks (`paypal.com.secure-verify.net`, `wellsfargo.com-alerts.co`). Benign examples use real well-known domains (chase.com, apple.com, usps.com, medicare.gov, irs.gov, and so on). Two scams deliberately use genuine infrastructure:
- `fake_invoice`: a PayPal invoice sent from service@paypal.com.
- `refund_remote_access`: secure.chase.com viewed under a ScreenConnect session.

A detector that only checks domains will miss both.

## Splits

Each category is split about 60/40 into dev and test. **`test` is held out**: don't tune thresholds, prompts or rules on it. Report final numbers on `test`, and use `dev` for development.

## Categories

### Scam (13)
| category | what it covers |
|---|---|
| tech_support | Fake virus popups and browser lockers, "do not close" warnings, toll-free numbers, unsolicited tech chat |
| gov_impersonation | IRS, SSA, FTC, sheriff, US Marshals and CBP impersonation; arrest threats, gift cards, Bitcoin kiosks, "safe accounts", coaching the victim to lie to the bank teller |
| grandparent | A grandchild or child "in trouble", a new phone number, bail, couriers, gag orders, secrecy |
| phishing_login | Bank, Apple, PayPal, Amazon and Netflix lockout pages on lookalike, punycode, typosquat or subdomain-trick domains |
| refund_remote_access | Overpaid-refund tricks; AnyDesk, TeamViewer, ScreenConnect and UltraViewer codes; black-screen mode; one-time passcode requests |
| crypto_investment | Pig-butchering, guaranteed returns, fake platform "tax to withdraw", Bitcoin ATM, fake celebrity news, "mentor" VIP groups |
| romance | Deployed soldier or oil-rig worker, gift cards to "call you", hospital emergencies, money-mule reshipping, joint crypto wallet |
| prize_lottery | Sweepstakes or lottery wins with fees, "you won an iPhone" popups, fake federal grants, survey rewards |
| delivery_toll | USPS, FedEx and DHL redelivery or customs texts and pages, E-ZPass and FasTrak unpaid tolls with small fees |
| utility_shutoff | Power or water disconnection "in 30 minutes", meter-deposit pretexts, payment by Zelle, gift card or Bitcoin |
| charity_disaster | Disaster relief paid only by gift card, crypto or P2P apps; fake "confirm last year's pledge"; SSN requested "for a tax receipt" |
| fake_invoice | Norton, Geek Squad, McAfee, Amazon and Apple renewal invoices with a "call to cancel" number; PayPal invoice abuse |
| medicare_benefits | Free braces, test kits or genetic tests, new-card fees, grocery allowances, "plan cancelled, confirm your MBI" |

### Benign (12)
| category | what it covers (hard negatives in parentheses) |
|---|---|
| retail_gift_card | Buying gift cards for grandkids on target.com, amazon.com, apple.com and costco.com (a receipt with a gift-card scam disclaimer, a thank-you text) |
| real_bank | Chase, Wells Fargo, Schwab and credit-union screens (real fraud-alert email and SMS, Zelle to a known daughter) |
| real_security_software | Malwarebytes, a real Norton renewal with no phone number, macOS updates, Gatekeeper (the real XProtect "will damage your computer" dialog) |
| medicare_letter | Medicare Summary Notice ("THIS IS NOT A BILL"), Aetna EOB, SSA COLA letter, Plan Finder (medicare.gov fraud page) |
| family_email | Birthday plans, Thanksgiving group chat, repaying concert tickets, a known grandkid asking for camp money with the parent cc'd |
| news_article_about_scams | AARP, FTC, NYT, Wikipedia, Reddit r/Scams, local news, WaPo; all keyword-dense |
| legit_support | User-started Apple Support chat, the real Apple and Chase numbers on their official sites, Xfinity chat, Genius Bar email (Amazon refund chat) |
| tax_software | TurboTax, H&R Block, FreeTaxUSA, IRS Direct Pay, Where's My Refund (a real IRS CP14 balance-due notice) |
| shopping_checkout | Normal card entry at Amazon, Walmart, Target, Etsy, L.L.Bean and Apple |
| remote_help_family | Grandson over FaceTime screen share, daughter over Zoom, Messages screen sharing (TeamViewer with a saved son contact), parish IT note, library tech help |
| delivery_real | Real USPS, UPS, FedEx and Amazon tracking, Informed Delivery, the real USPS 28777 short-code text |
| everyday | Recipe, weather, crossword (clues like "swindle" and "bail"), Photos, Calendar ("pay electric bill"), a Pages letter recounting a past scam, a club newsletter |

## Counts

Generated by the validation script, which checks that every line parses as JSON, that ids are unique, that enum fields are valid, and that text length is 150 to 1200 characters.

```
Total: 154  scam: 79  benign: 75
Split: dev: 89  test: 65
Difficulty: easy: 43  hard: 52  medium: 59
```

| label | category | dev | test | total | easy/med/hard |
|---|---|---|---|---|---|
| scam | tech_support | 4 | 2 | 6 | 2/2/2 |
| scam | gov_impersonation | 3 | 3 | 6 | 2/2/2 |
| scam | grandparent | 4 | 2 | 6 | 1/3/2 |
| scam | phishing_login | 4 | 3 | 7 | 1/3/3 |
| scam | refund_remote_access | 4 | 2 | 6 | 1/3/2 |
| scam | crypto_investment | 3 | 3 | 6 | 2/2/2 |
| scam | romance | 4 | 2 | 6 | 1/3/2 |
| scam | prize_lottery | 3 | 3 | 6 | 2/2/2 |
| scam | delivery_toll | 4 | 2 | 6 | 2/2/2 |
| scam | utility_shutoff | 3 | 3 | 6 | 1/3/2 |
| scam | charity_disaster | 4 | 2 | 6 | 1/3/2 |
| scam | fake_invoice | 3 | 3 | 6 | 2/2/2 |
| scam | medicare_benefits | 4 | 2 | 6 | 1/3/2 |
| benign | retail_gift_card | 3 | 3 | 6 | 1/2/3 |
| benign | real_bank | 4 | 3 | 7 | 3/2/2 |
| benign | real_security_software | 3 | 3 | 6 | 2/2/2 |
| benign | medicare_letter | 4 | 2 | 6 | 2/3/1 |
| benign | family_email | 3 | 3 | 6 | 2/1/3 |
| benign | news_article_about_scams | 4 | 3 | 7 | 0/1/6 |
| benign | legit_support | 3 | 3 | 6 | 1/3/2 |
| benign | tax_software | 4 | 2 | 6 | 2/3/1 |
| benign | shopping_checkout | 3 | 3 | 6 | 3/2/1 |
| benign | remote_help_family | 4 | 2 | 6 | 0/3/3 |
| benign | delivery_real | 3 | 3 | 6 | 3/2/1 |
| benign | everyday | 4 | 3 | 7 | 5/2/0 |
| **scam total** | | 47 | 32 | 79 | |
| **benign total** | | 42 | 33 | 75 | |

## Validating

```sh
python3 -c "import json,collections as c;r=[json.loads(l) for l in open('bench/fixtures.jsonl')];assert len({x['id'] for x in r})==len(r);print(len(r),c.Counter((x['label'],x['split']) for x in r))"
```
