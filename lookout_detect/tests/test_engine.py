import math

import numpy as np
import pytest

from lookout_detect import Engine, Event, Observation, load_model

E = Event


def obs(t, *events, model_ran=False, source="screen"):
    return Observation(t=t, events=frozenset(events), model_ran=model_ran, source=source)


@pytest.fixture(scope="module")
def model():
    return load_model()


def test_model_is_valid(model):
    assert np.allclose(model.A.sum(axis=1), 1)
    assert abs(model.start.sum() - 1) < 1e-12
    for dt in (0, 5, 600, 86400):
        assert np.allclose(model.transition(dt).sum(axis=1), 1)


def test_full_tech_support_sequence_is_flagged(model):
    eng = Engine(model)
    seq = [
        obs(0, E.INFECTED_CLAIM, E.PHONE_NUMBER_IN_POPUP, E.URGENT_LANGUAGE, E.BRAND_IMPERSONATION),
        obs(40),                                   # on the phone with the "technician"
        obs(150, E.REMOTE_ACCESS_STARTED, source="apps"),
        obs(300, E.BANK_SITE_OPENED, E.REMOTE_ACCESS_STARTED),
        obs(520, E.GIFT_CARD_PAGE, E.PAYMENT_DEMAND, E.REMOTE_ACCESS_STARTED),
    ]
    states = eng.run(seq)
    assert states[-1].p_scam > 0.9
    assert states[-1].top_type == "tech_support"
    assert states[-1].current_stage == "payment"


def test_family_remote_help_stays_low(model):
    eng = Engine(model)
    seq = [
        obs(0),
        obs(60, E.REMOTE_ACCESS_STARTED, source="apps"),
        obs(90, E.REMOTE_ACCESS_STARTED, E.SCREEN_SHARE_ACTIVE),
        obs(400),
        obs(700, E.REMOTE_ACCESS_STARTED),
        obs(1200),
    ]
    states = eng.run(seq)
    assert max(s.p_scam for s in states) < 0.3


def test_single_gift_card_purchase_stays_low(model):
    eng = Engine(model)
    states = eng.run([obs(0), obs(30, E.GIFT_CARD_PAGE), obs(60, E.GIFT_CARD_PAGE, E.URGENT_LANGUAGE), obs(90)])
    assert max(s.p_scam for s in states) < 0.1


def test_remote_access_after_refund_invoice_is_more_alarming_than_alone(model):
    alone = Engine(model).run([obs(0), obs(60, E.REMOTE_ACCESS_STARTED)])[-1].p_scam
    eng = Engine(model)
    after = eng.run([obs(0, E.REFUND_OVERPAYMENT, E.PHONE_NUMBER_IN_POPUP, E.BRAND_IMPERSONATION), obs(120), obs(240, E.REMOTE_ACCESS_STARTED)])
    assert after[-1].p_scam > 10 * alone
    remote_entry = [e for e in eng.ledger if e.item == "REMOTE_ACCESS_STARTED"][0]
    assert remote_entry.log_bf > 1.0


def test_posteriors_sum_to_one(model):
    eng = Engine(model)
    for o in [obs(0, E.URGENT_LANGUAGE), obs(10, E.LEGAL_THREAT, E.GOV_IMPERSONATION), obs(20, E.PAYMENT_DEMAND)]:
        s = eng.observe(o)
        post = eng.posterior()
        assert abs(post.sum() - 1) < 1e-9
        assert abs(sum(s.by_type.values()) + post[~model.is_scam].sum() - 1) < 1e-9
        assert abs(sum(s.stage_posterior.values()) - 1) < 1e-9
        assert abs(s.p_scam - sum(s.by_type.values())) < 1e-9


def test_ledger_sums_to_log_odds(model):
    eng = Engine(model)
    eng.run([
        obs(0, E.REFUND_OVERPAYMENT, E.PHONE_NUMBER_IN_POPUP),
        obs(100),
        obs(200, E.REMOTE_ACCESS_STARTED),
        obs(5000, E.BANK_SITE_OPENED),
    ])
    total = eng.prior_log_odds + sum(e.log_bf for e in eng.ledger)
    assert abs(total - eng.log_odds) < 1e-9
    p = 1 / (1 + math.exp(-eng.log_odds))
    assert abs(p - eng.state().p_scam) < 1e-9


def test_risk_decays_after_quiet_gap(model):
    eng = Engine(model)
    hi = eng.observe(obs(0, E.INFECTED_CLAIM, E.PHONE_NUMBER_IN_POPUP, E.URGENT_LANGUAGE, E.BRAND_IMPERSONATION)).p_scam
    assert hi > 0.9
    later = eng.observe(obs(3 * 3600)).p_scam
    assert later < 0.3


def test_model_flag_only_counts_when_model_ran(model):
    a = Engine(model).observe(obs(0, E.URGENT_LANGUAGE)).log_odds
    b = Engine(model).observe(obs(0, E.URGENT_LANGUAGE, model_ran=False)).log_odds
    c = Engine(model).observe(obs(0, E.URGENT_LANGUAGE, model_ran=True)).log_odds      # Claude looked: said safe
    d = Engine(model).observe(obs(0, E.URGENT_LANGUAGE, E.CLAUDE_FLAG)).log_odds        # Claude flagged it
    assert a == b
    assert c < a < d
    assert d - a <= 3.0 + 1e-6, "one model report is capped at ~+3 nats"


def test_next_stage_prediction(model):
    s = Engine(model).observe(obs(0, E.INFECTED_CLAIM, E.PHONE_NUMBER_IN_POPUP, E.URGENT_LANGUAGE, E.BRAND_IMPERSONATION))
    assert s.top_type == "tech_support" and s.current_stage == "popup"
    assert s.next_stage in ("call", "remote")
    assert s.next_hint


def test_grandparent_and_government_sequences(model):
    g = Engine(model).run([obs(0, E.FAMILY_EMERGENCY_STORY, E.URGENT_LANGUAGE), obs(60, E.FAMILY_EMERGENCY_STORY, E.LEGAL_THREAT),
                           obs(120, E.SECRECY_REQUEST), obs(180, E.PAYMENT_DEMAND, E.WIRE_OR_CRYPTO_PAGE)])[-1]
    assert g.top_type == "grandparent" and g.p_scam > 0.9
    v = Engine(model).run([obs(0, E.GOV_IMPERSONATION, E.URGENT_LANGUAGE), obs(30, E.LEGAL_THREAT, E.GOV_IMPERSONATION),
                           obs(90, E.PAYMENT_DEMAND, E.GIFT_CARD_PAGE)])[-1]
    assert v.top_type == "government" and v.p_scam > 0.9


def test_everyday_day_stays_quiet(model):
    eng = Engine(model)
    rng = np.random.default_rng(0)
    t = 0.0
    worst = 0.0
    for _ in range(300):
        t += float(rng.exponential(120))
        ev = []
        if rng.random() < 0.03: ev.append(E.URGENT_LANGUAGE)
        if rng.random() < 0.01: ev.append(E.BANK_SITE_OPENED)
        worst = max(worst, eng.observe(obs(t, *ev)).p_scam)
    assert worst < 0.1


def test_crs_sender_flag_only_counts_when_checked(model):
    base = [E.GOV_IMPERSONATION, E.URGENT_LANGUAGE]
    unchecked = Engine(model).observe(obs(0, *base)).log_odds
    clean = Engine(model).observe(Observation(t=0, events=frozenset(base), crs_checked=True)).log_odds   # CRS: sender looks normal
    flagged = Engine(model).observe(obs(0, *base, E.CRS_SENDER_HIGH_RISK)).log_odds                       # CRS: high-risk sender
    assert clean < unchecked < flagged
    assert flagged - unchecked <= 3.0 + 1e-6, "one CRS result is capped at ~+3 nats"


def test_crs_flag_pushes_government_notice_over_the_line(model):
    seq = [obs(0, E.GOV_IMPERSONATION, E.URGENT_LANGUAGE), obs(60, E.LEGAL_THREAT, E.GOV_IMPERSONATION)]
    without = Engine(model).run(seq)[-1].p_scam
    eng = Engine(model)
    eng.observe(obs(0, E.GOV_IMPERSONATION, E.URGENT_LANGUAGE, E.CRS_SENDER_HIGH_RISK))
    with_crs = eng.observe(obs(60, E.LEGAL_THREAT, E.GOV_IMPERSONATION)).p_scam
    assert with_crs > without
    assert any(e.item == "CRS_SENDER_HIGH_RISK" and e.log_bf > 1.0 for e in eng.ledger)
