"""Scripted session generator for evaluation.

Deliberately NOT sampled from the HMM (that would make the evaluation circular). Each session is a list
of *screens* (text, url, running apps, sensitive fields, time) written from hand-made templates, with
realistic noise: skipped stages, everyday screens in between, out-of-order steps, repeated screens,
abandoned scams. Screens are turned into events by the app's own extractor (`scout-signals`), so
extractor misses and false triggers are part of the evaluation.

    .venv/bin/python -m scout_detect.scripts_gen --n 400 --seed 7 --out eval/sessions_scripted.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

NUM = lambda r: f"({r.choice(['844','855','866','877','888'])}) 555-01{r.randint(10,99)}"
AMT = lambda r: f"${r.choice([199.99, 299.99, 399.99, 449.00, 499.95, 1500, 2500, 3200])}"

NEUTRAL = [
    ("Chicken noodle soup recipe. Ingredients: 1 whole chicken, 3 carrots, 2 celery stalks. Simmer for 2 hours. Serves 6.", "https://www.allrecipes.com/recipe/soup", ["Safari"]),
    ("Weather for Sacramento: Sunny, high 74°F, low 52°F. Tomorrow: partly cloudy.", "https://weather.com/today", ["Safari"]),
    ("Inbox — Mail. From: Linda Park. Subject: Book club Thursday? Hi Margaret, are we still meeting at 2? Bring the lemon bars!", None, ["Mail"]),
    ("Photos — Library. Thanksgiving 2025 (48 photos). Shared album: Grandkids.", None, ["Photos"]),
    ("The New York Times — City council approves new library hours. The downtown branch will stay open until 8 pm on weekdays.", "https://www.nytimes.com/2026/10/22/local/library.html", ["Safari"]),
    ("Calendar — Tuesday: Dr. Patel 10:30 AM. Thursday: Book club 2:00 PM.", None, ["Calendar"]),
    ("Crossword — 14 Across: Large body of water (5). 3 Down: Opposite of night (3).", "https://www.nytimes.com/crosswords", ["Safari"]),
    ("Facebook — Susan shared a photo: 'Look at my tomatoes this year!' 12 likes. Comment.", "https://www.facebook.com/", ["Safari"]),
    ("YouTube — How to make sourdough bread at home (12:41). Subscribe.", "https://www.youtube.com/watch?v=abc", ["Safari"]),
    ("Messages — Jake: Hi Grandma! Saw the pictures from the garden, they look great 🌻", None, ["Messages"]),
    ("Kaiser Permanente — Your lab results are ready. Sign in to view your message from Dr. Patel.", "https://healthy.kaiserpermanente.org/", ["Safari"]),
    ("Spotify — Frank Sinatra radio. Now playing: Fly Me to the Moon.", None, ["Spotify"]),
]

# ------------------------------------------------------------------ scam playbooks (stage → screen makers)

def ts_popup(r):
    brand = r.choice(["Microsoft", "Windows Defender", "Apple Security", "Apple Support"])
    dom = r.choice(["micros0ft-security-alert.com", "windows-defender-alert.help", "apple-support-warning.live", "secure-mac-alert.xyz"])
    t = r.choice([
        f"{brand} Security Warning. Your computer has been infected with a Trojan spyware. Do not close this window or restart your computer. Call {brand} Support immediately at {NUM(r)}. Error code 0x80073b01.",
        f"WARNING! {brand}: Virus detected. Your personal data is at risk. Access to this PC has been blocked for security reasons. Call the helpline {NUM(r)} (toll free) right away.",
        f"{brand} — Critical Alert. Threats detected: 5. Your files will be deleted in 5 minutes. Do not ignore. Contact a certified technician at {NUM(r)}.",
    ])
    return dict(text=t, url=f"https://{dom}/alert")


def remote_install(r, why):
    app = r.choice(["AnyDesk", "TeamViewer", "UltraViewer", "ScreenConnect"])
    t = r.choice([
        f"{why}: Step 1. Download {app} using the button below. Step 2. Open it and read the 9-digit address to the technician. Step 3. Click Accept when the technician connects.",
        f"To continue, please install {app} so our technician can connect and help you. Give the technician your {app} ID when asked.",
    ])
    return dict(text=t, url=f"https://{r.choice(['support-desk.live','help-center-online.site','secure-assist.top'])}/start"), app


def ts_remote(r):
    s, app = remote_install(r, "Microsoft Support")
    s["launch"] = app
    return s


def bank_screen(r, extra=""):
    bank, dom = r.choice([("Chase", "secure.chase.com"), ("Wells Fargo", "connect.secure.wellsfargo.com"), ("Bank of America", "secure.bankofamerica.com")])
    return dict(text=f"{bank} Online Banking. Account summary. Checking ...4821 Available balance $8,412.07. Savings ...1190 $21,300.00. {extra}", url=f"https://{dom}/accounts")


def ts_banking(r):
    return bank_screen(r)


def pay_giftcard(r, who):
    t = r.choice([
        f"Target Gift Cards. eGift card $500. Buy 4 cards. {who} said to read the numbers on the back of each card over the phone. Do not tell the cashier what they are for.",
        f"Bitcoin Depot — Bitcoin ATM locator. Insert cash and scan the wallet address QR code you were sent. {who} is waiting on the line.",
        f"Wire transfer — Send money. Recipient: {r.choice(['J. Miller Trading LLC','Secure Federal Account','D. Davis Legal'])}. Amount {AMT(r)}. Purpose: refund correction. Don't discuss this with the bank teller.",
    ])
    return dict(text=t, url=r.choice([None, "https://www.target.com/gift-cards", "https://bitcoindepot.com/locations"]))


def ts_payment(r):
    return pay_giftcard(r, "The Microsoft technician")


def rf_invoice(r):
    brand = r.choice(["Norton LifeLock", "Geek Squad", "PayPal", "McAfee", "Amazon Prime"])
    t = r.choice([
        f"From: {brand} Billing <billing@{r.choice(['norton-renewals.info','geeksquad-billing.co','pp-invoices.net'])}>. Subject: Order confirmation. Your subscription has been renewed for {AMT(r)}. If you did not authorize this charge, call our billing department at {NUM(r)} within 24 hours to cancel and receive a refund.",
        f"INVOICE #{r.randint(10000,99999)} — {brand}. Auto-renewal successful: {AMT(r)} has been charged to your account. To cancel this order or dispute this charge, call {NUM(r)} immediately.",
    ])
    return dict(text=t, url=None, app="Mail")


def rf_remote(r):
    s, app = remote_install(r, "Refund Department")
    s["text"] += " We need to connect to process your refund."
    s["launch"] = app
    return s


def rf_overpay(r):
    s = bank_screen(r, r.choice(["Incoming transfer: REFUND $4,000.00.", "Pending credit $3,999.00 — refund."]))
    return s


def rf_payment(r):
    s = pay_giftcard(r, "The refund agent")
    s["text"] = "Oh no, we accidentally refunded too much. You must send back the difference today. " + s["text"]
    return s


def gp_contact(r):
    who = r.choice(["Tyler", "Jake", "Emma", "Ryan"])
    return dict(text=r.choice([
        f"Messages — +1 (916) 555-01{r.randint(10,99)}: Grandma it's me, {who}. I got a new number. Can you talk? It's an emergency.",
        f"Messages — Unknown: Hi Grandpa, it's me. Please don't be mad. I'm in trouble and I need your help right now.",
    ]), app="Messages")


def gp_story(r):
    return dict(text=r.choice([
        "Messages — I was in a car accident and the police arrested me. I'm in jail. My lawyer Mr. Davis says I need bail money today or I stay here for the weekend.",
        "Messages — I'm at the hospital after an accident in Mexico and they won't let me leave until the bill is paid. The attorney will call you.",
    ]), app="Messages")


def gp_secrecy(r):
    return dict(text=r.choice([
        "Messages — Please don't tell Mom and Dad, they'll kill me. Keep this between us, ok? The lawyer said there's a gag order.",
        "Messages — Promise you won't tell anyone. I'm so embarrassed. Just between you and me.",
    ]), app="Messages")


def gp_payment(r):
    return dict(text=r.choice([
        f"Messages — Can you send the bail money by Zelle to Davis Legal? It's {AMT(r)}. Or wire transfer to the court account. Hurry please.",
        "Messages — The lawyer says buy Apple gift cards, $500 each, and send pictures of the codes. A courier can pick up cash in an envelope too.",
    ]), app="Messages")


def gv_notice(r):
    agency, dom = r.choice([("IRS — Internal Revenue Service", "irs-gov-payments.co"), ("Social Security Administration", "ssa-benefits-update.info"), ("U.S. Department of Treasury", "treasury-notice.online")])
    return dict(text=f"From: {agency} <notice@{dom}>. FINAL NOTICE. Case number {r.randint(100000,999999)}. Our records show an unresolved issue with your account. Respond immediately to avoid suspension. Call {NUM(r)}.", url=None, app="Mail")


def gv_threat(r):
    return dict(text=r.choice([
        "Officer badge number 4471: a warrant has been issued for your arrest for tax fraud. Your Social Security number has been suspended due to suspicious activity. Do not discuss this case with anyone.",
        "Legal action: The federal agent says you will be arrested today unless the balance is settled. Your bank accounts will be frozen.",
    ]), app="Mail")


def gv_payment(r):
    return dict(text=f"To settle the balance of {AMT(r)} today, purchase Google Play or Target gift cards and read the codes to the officer. Gift card codes: [ ] [ ] [ ]", url=None, sensitive=["gift-card"])


PLAYBOOKS = {
    "tech_support": [("popup", ts_popup), ("call", None), ("remote", ts_remote), ("banking", ts_banking), ("payment", ts_payment)],
    "refund": [("invoice", rf_invoice), ("call", None), ("remote", rf_remote), ("overpay", rf_overpay), ("payment", rf_payment)],
    "grandparent": [("contact", gp_contact), ("story", gp_story), ("secrecy", gp_secrecy), ("payment", gp_payment)],
    "government": [("notice", gv_notice), ("threat", gv_threat), ("payment", gv_payment)],
}

# ------------------------------------------------------------------ benign look-alikes

def b_remote_help(r):
    who = r.choice(["Jake", "Sarah", "Emma"])
    app = r.choice(["AnyDesk", "TeamViewer", "Screen Sharing"])
    out = [dict(text=f"Messages — {who}: Hi Mom, I'm going to connect with {app} to fix the printer. Click Accept when it pops up 🙂", app="Messages", stage="benign:remote_help")]
    out.append(dict(text=f"{app} — Incoming session from {who} (saved contact). Accept / Decline.", launch=app, stage="benign:remote_help"))
    for _ in range(r.randint(1, 3)):
        out.append(dict(text=r.choice(["Printers & Scanners — HP OfficeJet 3830: Ready.", "System Settings — Software Update: macOS is up to date.", "Finder — Downloads (12 items)."]), stage="benign:remote_help"))
    if r.random() < 0.35:  # hard negative: family helps with online banking
        out.append(dict(**bank_screen(r), stage="benign:remote_help"))
    out.append(dict(text=f"Messages — {who}: All done! Love you.", app="Messages", end_remote=app, stage="benign:remote_help"))
    return out


def b_gift(r):
    return [dict(text="ShopRiver Gift Cards. $50 Birthday eGift card. Add to cart. Customer reviews 4.8 stars.", url="https://www.shopriver.com/gift-cards", stage="benign:gift_shopping"),
            dict(text="Your cart. $50 Birthday eGift card for Emma. Gift message: Happy birthday sweetheart! Subtotal $50.00. Proceed to checkout. Sale ends today!", url="https://www.shopriver.com/cart", stage="benign:gift_shopping"),
            dict(text="Checkout. Card number. Expiration. Place your order. Estimated delivery: email within 1 hour.", url="https://www.shopriver.com/checkout", sensitive=["card"], stage="benign:gift_shopping")]


def b_bank(r):
    return [dict(**bank_screen(r), stage="benign:banking"),
            dict(text="Bill Pay — PG&E. Amount $84.20. Deliver by Nov 3. Pay from Checking ...4821. Submit.", url="https://secure.chase.com/billpay", stage="benign:banking")]


def b_news(r):
    return [dict(text=r.choice([
        "AARP Fraud Watch — How to spot a grandparent scam. Scammers pose as a grandchild in jail and ask for bail money by gift card, and beg you not to tell anyone. If you get a call like this, hang up and call your grandchild directly.",
        "NYT — 'Pig Butchering' scams drain retirees' savings. According to the FTC, victims lost $3.5 billion last year. Experts say never pay with gift cards or a Bitcoin ATM.",
        "FTC Consumer Alert — Tech support scams. Microsoft will never put a phone number in a pop-up warning. If you see one, close the browser. Report fraud at reportfraud.ftc.gov.",
    ]), url=r.choice(["https://www.aarp.org/money/scams-fraud/", "https://www.nytimes.com/2026/09/12/business/scams.html", "https://consumer.ftc.gov/alerts"]), stage="benign:reading_about_scams")]


def b_real_invoice(r):
    return [dict(text=f"From: Amazon.com <auto-confirm@amazon.com>. Your order of 'Reading glasses 3-pack' has shipped. Order total $18.99. Track package.", app="Mail", stage="neutral"),
            dict(text="Norton 360 — Your subscription renews on Dec 1 for $49.99. Manage your subscription in your Norton account. No action is needed.", url="https://my.norton.com/account", stage="neutral")]


def b_real_gov(r):
    return [dict(text="Social Security — my Social Security. Your benefit statement is ready. Sign in to view your 2026 cost-of-living adjustment.", url="https://www.ssa.gov/myaccount/", stage="neutral"),
            dict(text="IRS — Where's My Refund? Your tax return has been received and is being processed.", url="https://www.irs.gov/refunds", stage="neutral")]


def b_family_money(r):
    return [dict(text="Messages — Emma: Hi Grandma!! Thank you so much for the birthday card 🥰 Can you Venmo me $20 for the movie Saturday? No worries if not!", app="Messages", stage="neutral"),
            dict(text="Venmo — Pay Emma Mitchell $20.00. Note: Movie night 🍿. Pay.", url="https://venmo.com/", stage="neutral")]


BENIGN_KINDS = {"remote_help": b_remote_help, "gift_shopping": b_gift, "banking": b_bank, "reading_about_scams": b_news,
                "real_invoice": b_real_invoice, "real_government": b_real_gov, "family_money": b_family_money}


# ------------------------------------------------------------------ session assembly

def neutral(r):
    t, u, apps = r.choice(NEUTRAL)
    return dict(text=t, url=u, app=apps[0], stage="neutral")


def finalize(r, screens, base_apps=("Safari", "Mail", "Messages")):
    """Assign times and the running-apps list (remote apps stay running once launched)."""
    t = float(r.randint(0, 3600))
    running = set(base_apps)
    out = []
    for s in screens:
        t += s.pop("gap", None) or (r.uniform(20, 180) if s.get("stage") != "neutral" else r.uniform(30, 900))
        if s.get("launch"):
            running.add(s.pop("launch"))
        app = s.pop("app", None)
        end = s.pop("end_remote", None)
        out.append(dict(t=round(t, 1), text=s.get("text", ""), url=s.get("url"), app=app or "Safari",
                        apps=sorted(running), sensitive=s.get("sensitive", []), stage=s.get("stage", "neutral")))
        if end:
            running.discard(end)
    return out


def scam_session(r, pb):
    stages = list(PLAYBOOKS[pb])
    # Noise: skip a middle stage, swap two middle stages, abandon early, repeat screens, everyday screens in between.
    if len(stages) > 3 and r.random() < 0.2:
        del stages[r.randrange(1, len(stages) - 1)]
    if len(stages) > 3 and r.random() < 0.15:
        i = r.randrange(1, len(stages) - 2)
        stages[i], stages[i + 1] = stages[i + 1], stages[i]
    abandoned = r.random() < 0.15
    if abandoned:
        stages = stages[: r.randint(1, len(stages) - 1)]
    screens = [neutral(r) for _ in range(r.randint(0, 4))]
    for name, make in stages:
        reps = 1 if make is None else r.choice([1, 1, 1, 2])
        for _ in range(reps):
            s = make(r) if make else neutral(r) | {"gap": r.uniform(60, 600)}
            s["stage"] = f"{pb}:{name}"
            screens.append(s)
        for _ in range(r.choice([0, 0, 1, 2])):
            screens.append(neutral(r))
    screens += [neutral(r) for _ in range(r.randint(0, 2))]
    return dict(label="scam", kind=pb, abandoned=abandoned, screens=finalize(r, screens))


def benign_session(r, kind):
    screens = [neutral(r) for _ in range(r.randint(2, 6))]
    if kind != "everyday":
        screens += BENIGN_KINDS[kind](r)
    screens += [neutral(r) for _ in range(r.randint(1, 8 if kind == "everyday" else 4))]
    if kind == "everyday":
        screens += [neutral(r) for _ in range(r.randint(10, 30))]
    return dict(label="benign", kind=kind, abandoned=False, screens=finalize(r, screens))


def generate(n: int, seed: int) -> list[dict]:
    r = random.Random(seed)
    out = []
    kinds = list(PLAYBOOKS) + ["benign:" + k for k in list(BENIGN_KINDS) + ["everyday"]]
    for i in range(n):
        k = kinds[i % len(kinds)]
        s = benign_session(r, k.split(":", 1)[1]) if k.startswith("benign:") else scam_session(r, k)
        s["id"] = f"scripted-{seed}-{i:04d}"
        s["source"] = "scripted"
        out.append(s)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=440)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default="eval/sessions_scripted.jsonl")
    a = ap.parse_args()
    sessions = generate(a.n, a.seed)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    with open(a.out, "w") as f:
        for s in sessions:
            f.write(json.dumps(s) + "\n")
    print(f"wrote {len(sessions)} sessions to {a.out}")


if __name__ == "__main__":
    main()
