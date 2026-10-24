# Lookout demo scenarios

Static, local HTML pages for the live demo and for fixture mode. **Everything here is fake.** No page makes network requests (no CDNs, fonts or remote images), every form calls `preventDefault`, phone numbers are 555 numbers, and the crypto address is an obvious placeholder. Brand-like visuals are generic approximations (four colored squares, a bank "column" glyph) rather than real logos.

Open `demo/index.html` in a browser to get a launcher. Number keys 1–9 and 0 open scenarios in the same tab.

## Page contract (what the app reads)

Each `scenarios/*.html` page is laid out for a 1280x800 viewport and includes:

| Marker | Meaning |
| --- | --- |
| `<meta name="lookout-label" content="scam\|benign">` | Ground-truth label for the bench |
| `<meta name="lookout-url" content="…">` | The URL (or `mailto:` / `sms:` / `file:` source) the page pretends to be |
| `<meta name="lookout-app" content="Safari\|Mail\|Messages\|Preview">` | Pretend frontmost app |
| `data-lookout-threat="phone\|gift-card\|link\|login\|remote-app\|wire\|crypto\|ssn\|card"` | The single most dangerous element (scam pages only, exactly one per page) |
| `data-lookout-target="…"` | The main element the user would interact with (benign pages only) |
| `data-lookout-sensitive="card\|gift-card\|ssn\|bank\|password"` | Payment and identity entry fields |

Each page draws its own app chrome at the top (a Safari tab and address bar, or a Mail, Messages or Preview window), so the fake URL or sender shows up in screenshots and text extraction. `scenarios/manifest.json` lists every page with `file, label, category, url, app, threat, title`, plus `target` and `sensitive` derived from the markup.

## Scams (Lookout should warn)

| # | File | Pretend source | Tactics it tests | Threat element | Expected Lookout behavior |
| --- | --- | --- | --- | --- | --- |
| 1 | `tech-support.html` | Safari, `https://micros0ft-security-alert.com/windows-defender/alert.html?err=0x80073b01` (zero for "o", "Not Secure") | Full-window fake Windows Defender alert, "Do not close this window or restart", error code, animated fake scan, threat counter | `phone`: the pulsing **(888) 555-0142** button | Warn right away. Point at the phone number and say real Microsoft/Apple never put a phone number in a pop-up. Tell the user not to call and that it's safe to close the tab. |
| 2 | `irs-gift-card.html` | Mail, from "IRS Department of Treasury" `<notice@irs-gov-payments.co>` | Government impersonation, arrest warrant by 5 PM, gift cards (Target/Apple) read over the phone, "do not discuss this with anyone" | `gift-card`: the red payment-instructions box. Gift card code and PIN inputs are `sensitive=gift-card`. | Warn. The IRS never takes gift cards and never threatens arrest by email. Discourage typing codes and suggest telling a family member. |
| 3 | `grandchild-jail.html` | Messages, unknown number +1 (916) 555-0168, "Tyler" | Grandparent scam: car accident, broken nose explains the strange voice, $3,000 bail, "lawyer Mr. Davis", deadline, "please don't tell Mom and Dad" | `wire`: the bubble asking for wire transfer or Zelle to the lawyer's account | Warn. Suggest calling Tyler or his parents on a number already saved in contacts before sending any money. |
| 4 | `bank-login.html` | Safari, `https://firstnationaltrust-secure-login.verify-account.net/signin/verify?session=a83f2c91` | Lookalike domain (the real bank is `firstnationaltrust.com`, see #8), "account locked", 24-hour countdown, asks for password, SSN, debit card and PIN on one page | `login`: the password field (`sensitive=password`). SSN is `sensitive=ssn`. Card and PIN are `sensitive=card`. | Warn before typing. Point out that the domain isn't the bank's and that banks don't ask for SSN and PIN to "unlock" an account. |
| 5 | `refund-anydesk.html` | Safari, `https://techguard-refund-center.support-desk.live/refund/claim?inv=TG-884213` | Fake $399.99 auto-renewal, refund bait, step-by-step "Download AnyDesk, read your 9-digit code, log in to your bank", "do not cancel your card" | `remote-app`: the big red **Download AnyDesk** button | Warn strongly. Never let a stranger connect to the computer. Say not to call +1-844-555-0199. |
| 6 | `crypto-investment.html` | Safari, `https://app.bitgrowth-pro.io/dashboard?ref=linda-w-silverhearts` | Romance/pig-butchering: "Linda" from a dating site, "guaranteed 30% monthly", fake gains chart, countdown bonus, Bitcoin ATM deposit, "don't tell your bank", withdrawal "unlock tax" | `crypto`: the "Deposit via Bitcoin ATM" panel with the fake wallet `bc1q-DEMO-FAKE-WALLET-lookout-0000-not-real-xx` | Warn. Guaranteed returns plus an online-only friend plus a Bitcoin ATM is a classic scam. Suggest not sending more and talking to family. |

## Benign lookalikes (Lookout should stay quiet, or help)

These pages contain scary words on purpose ("gift card", "fraud", "password", "card number", phone numbers, dollar amounts) to measure false alarms.

| # | File | Pretend source | Why it's tricky | Target element | Expected Lookout behavior |
| --- | --- | --- | --- | --- | --- |
| 7 | `amazon-gift-card.html` | Safari, `https://www.shopriver.com/gift-cards/birthday-egift?amount=50` | Buying a gift card, with a card number field and even a line saying "scammers often ask for gift cards" | `add-to-cart`: the **Add to Cart** button. Card number and CVV are `sensitive=card`. | No scam alarm. The user started this, it's a normal store domain, and it's a gift for a grandchild. A gentle "this is a normal store" is fine if asked. |
| 8 | `bank-statement.html` | Safari, `https://www.firstnationaltrust.com/accounts/statement?acct=checking&period=2026-09` | Real bank domain (contrast with #4), "Fraud protection tips" box, "We will never ask for your password by phone" | `balance`: the account summary card | No alarm. Can explain the statement (Social Security and pension deposits, rent, Medicare premium). |
| 9 | `medicare-letter.html` | Preview, `Medicare_Summary_Notice_Sep2026.pdf` | Official-looking letter with dollar amounts, a Medicare number, a phone number (1-800-555-0123) and fraud language | `letter`: the page | No alarm. **Help demo:** "What is this letter?" It's a summary of claims, *not a bill*. The most the user may owe providers is $48.36. |
| 10 | `email-attach.html` | Mail compose window, To: Sarah, Subject: "Doctor's letter" | Normal compose window with a PDF on the desktop | `attach`: the paperclip button in the toolbar | No alarm. **Help demo:** "How do I attach this PDF?" Lookout points at the paperclip, or says to drag `Dr Patel letter.pdf` into the message. |

## Notes

- The pages use small `setInterval` animations (scan progress, countdowns). There's no audio, no `alert()`, no `beforeunload`, and nothing traps the user.
- `bank-login.html` and `bank-statement.html` share the same fictional brand on purpose, so the only real difference is the domain.
- The grandparent scam (#3) is a Messages conversation, not an email, because that's how these usually arrive now. Its `lookout-url` is `sms:+1-916-555-0168`.
- To regenerate screenshots at 1280x800: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1280,800 --screenshot=out.png file://$PWD/demo/scenarios/<file>.html`
