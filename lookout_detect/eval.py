"""Session-level evaluation of scam detectors on the same screens.

Every screen goes through the app's own extractor (`lookout-signals --engine`), then each detector scores
the resulting observations in order:

  rule        flags any single high-risk event (remote access, payment demand, gift card / wire / crypto page,
              phone number in a pop-up, infection claim, sensitive field on an unknown site)
  no_history  the playbook HMM reset before every observation: same model, no memory of earlier steps
  shipped     the detector the app shipped before this work (evidence memory + hard rules), from Swift
  playbook    the playbook HMM (this work)
  playbook_rules  playbook HMM, plus an alarm whenever a hard rule fires (always-true facts like
              "gift cards are never payment for the government")
  combined    max(shipped, playbook)
  hybrid      what the app ships (Swift ScamPipeline): playbook HMM + previous detector + hard rules, where the HMM
              can veto only evidence that a recognised benign look-alike also produces

Metrics (alarm = p >= threshold, default 0.5): session recall, benign false-alarm rate, false alarms per
hour of benign use, % of scams caught before the payment stage, and where in the playbook the first alarm lands.

    .venv/bin/python -m lookout_detect.eval eval/sessions_scripted.jsonl [eval/sessions_redteam.jsonl] --out eval
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
from collections import defaultdict
from pathlib import Path

import numpy as np

from .engine import Engine
from .events import Event, Observation
from .model import load_model

ROOT = Path(__file__).resolve().parent.parent
SIGNALS_BIN = ROOT / ".build" / "debug" / "lookout-signals"
DETECTORS = ["rule", "no_history", "shipped", "playbook", "playbook_rules", "combined", "hybrid", "hybrid_any_reaction"]
HIGH_RISK = {Event.REMOTE_ACCESS_STARTED, Event.PAYMENT_DEMAND, Event.GIFT_CARD_PAGE, Event.WIRE_OR_CRYPTO_PAGE,
             Event.PHONE_NUMBER_IN_POPUP, Event.INFECTED_CLAIM, Event.SENSITIVE_FIELD_ON_UNKNOWN_SITE}


def extract(session: dict) -> list[dict]:
    """Run the Swift extractor + shipped detector + Swift playbook engine over a session's screens."""
    lines = "\n".join(json.dumps({k: s.get(k) for k in ("t", "text", "url", "app", "apps", "sensitive")}) for s in session["screens"])
    out = subprocess.run([str(SIGNALS_BIN), "--engine"], input=lines, capture_output=True, text=True, cwd=ROOT, check=True)
    return [json.loads(l) for l in out.stdout.splitlines() if l.strip()]


def score(session: dict, extracted: list[dict], model) -> dict[str, list[float]]:
    eng = Engine(model)
    series = {d: [] for d in DETECTORS}
    for scr, ex in zip(session["screens"], extracted):
        ev = frozenset(ex["events"])
        ob = Observation(t=scr["t"], events=ev)
        st = eng.observe(ob)
        p = st.p_scam
        assert abs(p - ex["p_scam"]) < 1e-6, "Swift and Python engines disagree"
        series["playbook"].append(p)
        series["no_history"].append(Engine(model).observe(Observation(t=0, events=ev)).p_scam)
        series["shipped"].append(ex["risk_p"])
        series["rule"].append(1.0 if any(Event(e) in HIGH_RISK for e in ev) else 0.0)
        series["playbook_rules"].append(max(p, 1.0 if ex.get("rules") else 0.0))
        series["combined"].append(max(p, ex["risk_p"]))
        # What the app ships, computed by the Swift ScamPipeline itself (action >= interrupt counts as an alarm).
        series["hybrid"].append(max(ex["shipped_p"], 1.0 if ex["shipped_action"] in ("interrupt", "block+alert") else 0.0))
        # Any visible reaction at all, including the gentle nudge bubble.
        series["hybrid_any_reaction"].append(1.0 if ex["shipped_action"] != "quiet" else 0.0)
    return series


def session_metrics(session: dict, series: list[float], thr: float) -> dict:
    stages = [s["stage"] for s in session["screens"]]
    alarms = [i for i, p in enumerate(series) if p >= thr]
    first = alarms[0] if alarms else None
    m = {"alarm": first is not None, "first": first, "max_p": max(series) if series else 0.0}
    if session["label"] == "scam":
        scam_idx = [i for i, st in enumerate(stages) if st.split(":")[0] == session["kind"]]
        pay = [i for i, st in enumerate(stages) if st.endswith(":payment")]
        m["reached_payment"] = bool(pay)
        m["before_payment"] = first is not None and pay and first < pay[0]
        if first is not None and scam_idx:
            seen = sum(1 for i in scam_idx if i <= first)
            m["detect_step"] = seen                          # scam screens seen until the first alarm
            m["detect_frac"] = seen / len(scam_idx)
            m["detect_stage"] = stages[first]
    else:
        episodes = sum(1 for i, p in enumerate(series) if p >= thr and (i == 0 or series[i - 1] < thr))
        dur_h = (session["screens"][-1]["t"] - session["screens"][0]["t"] + 60) / 3600
        m["episodes"], m["hours"] = episodes, dur_h
    return m


def summarize(sessions, all_series, thr: float) -> dict:
    res = {}
    for d in DETECTORS:
        ms = [session_metrics(s, all_series[s["id"]][d], thr) | {"label": s["label"], "kind": s["kind"]} for s in sessions]
        scams = [m for m in ms if m["label"] == "scam"]
        benign = [m for m in ms if m["label"] == "benign"]
        paid = [m for m in scams if m.get("reached_payment")]
        steps = [m["detect_step"] for m in scams if "detect_step" in m]
        res[d] = {
            "recall": sum(m["alarm"] for m in scams) / max(1, len(scams)),
            "false_alarm_rate": sum(m["alarm"] for m in benign) / max(1, len(benign)),
            "false_alarms_per_hour": sum(m["episodes"] for m in benign) / max(1e-9, sum(m["hours"] for m in benign)),
            "caught_before_payment": sum(bool(m["before_payment"]) for m in paid) / max(1, len(paid)),
            "median_detect_step": statistics.median(steps) if steps else None,
            "n_scam": len(scams), "n_benign": len(benign),
            "by_kind": {k: sum(m["alarm"] for m in ms if m["kind"] == k) / max(1, sum(1 for m in ms if m["kind"] == k))
                        for k in sorted({m["kind"] for m in ms})},
        }
    return res


def roc(sessions, all_series, d):
    """Session-level: TPR vs benign FPR as the threshold sweeps over max p."""
    y = np.array([s["label"] == "scam" for s in sessions])
    s = np.array([max(all_series[x["id"]][d]) for x in sessions])
    thr = np.unique(np.concatenate([[0, 1.0001], s]))[::-1]
    tpr = [(s[y] >= t).mean() for t in thr]
    fpr = [(s[~y] >= t).mean() for t in thr]
    auc = float(np.trapezoid(tpr, fpr)) if hasattr(np, "trapezoid") else float(np.trapz(tpr, fpr))
    return fpr, tpr, auc


def plots(sessions, all_series, res, out: Path, title: str):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colors = {"rule": "#9aa0a6", "no_history": "#f2a65a", "shipped": "#6c8ebf", "playbook": "#2a9d8f", "playbook_rules": "#1d6f65", "combined": "#264653", "hybrid": "#e76f51", "hybrid_any_reaction": "#f4a261"}
    names = {"rule": "Single-event rule", "no_history": "Same model, no history", "shipped": "Previous detector",
             "playbook": "Playbook HMM", "playbook_rules": "Playbook HMM + hard rules", "combined": "Max of previous + HMM", "hybrid": "Shipped: hybrid", "hybrid_any_reaction": "Shipped: any reaction (incl. nudge)"}

    # 1. Metrics bars
    fig, ax = plt.subplots(1, 3, figsize=(13, 3.6))
    for i, (key, lab) in enumerate([("recall", "Scam sessions caught"), ("false_alarm_rate", "Benign sessions with a false alarm"),
                                    ("caught_before_payment", "Caught before the payment step")]):
        vals = [res[d][key] for d in DETECTORS]
        ax[i].bar(range(len(DETECTORS)), vals, color=[colors[d] for d in DETECTORS])
        ax[i].set_xticks(range(len(DETECTORS)), [names[d] for d in DETECTORS], rotation=30, ha="right", fontsize=8)
        ax[i].set_ylim(0, 1.05); ax[i].set_title(lab, fontsize=10)
        for j, v in enumerate(vals):
            ax[i].text(j, v + 0.02, f"{v:.0%}", ha="center", fontsize=8)
        ax[i].spines[["top", "right"]].set_visible(False)
    fig.suptitle(title, fontsize=11)
    fig.tight_layout(); fig.savefig(out / "metrics.png", dpi=160); plt.close(fig)

    # 2. ROC
    fig, ax = plt.subplots(figsize=(4.6, 4.2))
    for d in ["no_history", "shipped", "playbook", "playbook_rules"]:
        fpr, tpr, auc = roc(sessions, all_series, d)
        ax.plot(fpr, tpr, color=colors[d], label=f"{names[d]} (AUC {auc:.3f})", lw=2)
    ax.plot([0, 1], [0, 1], ls=":", color="#ccc")
    ax.set_xlabel("Benign sessions falsely alarmed"); ax.set_ylabel("Scam sessions caught")
    ax.legend(fontsize=7, loc="lower right"); ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout(); fig.savefig(out / "roc.png", dpi=160); plt.close(fig)

    # 3. Timeline of one refund (or tech-support) session
    pick = next((s for s in sessions if s["kind"] == "refund" and not s.get("abandoned") and any(st["stage"].endswith("payment") for st in s["screens"])), None) \
        or next(s for s in sessions if s["label"] == "scam")
    ser = all_series[pick["id"]]
    fig, ax = plt.subplots(figsize=(10, 3.4))
    x = range(len(pick["screens"]))
    for d in ["rule", "no_history", "shipped", "playbook"]:
        ax.step(x, ser[d], where="post", color=colors[d], label=names[d], lw=2 if d == "playbook" else 1.4)
    ax.axhline(0.5, ls="--", color="#bbb", lw=1)
    labels = [st["stage"].split(":")[-1] if st["stage"] != "neutral" else "·" for st in pick["screens"]]
    ax.set_xticks(list(x), labels, rotation=40, ha="right", fontsize=7)
    ax.set_ylim(-0.03, 1.03); ax.set_ylabel("P(scam)")
    ax.set_title(f"One {pick['kind']} session, screen by screen ({pick['id']})", fontsize=10)
    ax.legend(fontsize=7, ncol=4, loc="upper left"); ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout(); fig.savefig(out / "timeline.png", dpi=160); plt.close(fig)


def table(res, thr) -> str:
    names = {"rule": "Single-event rule", "no_history": "Same model, no history", "shipped": "Previous detector",
             "playbook": "**Playbook HMM**", "playbook_rules": "Playbook HMM + hard rules", "combined": "Max of previous + HMM", "hybrid": "**Shipped: hybrid** (interrupt)", "hybrid_any_reaction": "Shipped: any reaction incl. nudge"}
    lines = [f"| detector (alarm at p ≥ {thr}) | scams caught | benign sessions falsely alarmed | false alarms / hour | caught before payment | median scam screens until alarm |",
             "|---|---|---|---|---|---|"]
    for d in DETECTORS:
        r = res[d]
        lines.append(f"| {names[d]} | {r['recall']:.1%} | {r['false_alarm_rate']:.1%} | {r['false_alarms_per_hour']:.2f} | {r['caught_before_payment']:.1%} | {r['median_detect_step']} |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", default="eval")
    ap.add_argument("--threshold", type=float, default=0.5)
    ap.add_argument("--model", default=None, help="alternate playbooks.json (e.g. learned parameters)")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    model = load_model(a.model) if a.model else load_model()
    sessions = []
    for f in a.files:
        sessions += [json.loads(l) for l in open(f) if l.strip()]
    all_series = {}
    for s in sessions:
        # With an alternate model the Swift engine (default parameters) can't be parity-checked.
        all_series[s["id"]] = (_score_noassert if a.model else score)(s, extract(s), model)

    report = {"threshold": a.threshold, "files": a.files, "n_sessions": len(sessions)}
    sources = sorted({s["source"] for s in sessions})
    md = [f"# Session-level evaluation{(' — ' + a.tag) if a.tag else ''}", "",
          f"{len(sessions)} sessions from {', '.join(a.files)}. Every screen goes through the app's own extractor (`lookout-signals`).", ""]
    for src in sources + (["all"] if len(sources) > 1 else []):
        sub = [s for s in sessions if src == "all" or s["source"] == src]
        res = summarize(sub, all_series, a.threshold)
        report[src] = res
        n_s = sum(s["label"] == "scam" for s in sub)
        md += [f"## {src} ({n_s} scam / {len(sub) - n_s} benign sessions)", "", table(res, a.threshold), "",
               "Per kind (share of sessions alarmed; benign kinds are false alarms):", "",
               "| kind | " + " | ".join(DETECTORS) + " |", "|---|" + "---|" * len(DETECTORS)]
        for k in res["playbook"]["by_kind"]:
            md.append(f"| {k} | " + " | ".join(f"{res[d]['by_kind'][k]:.0%}" for d in DETECTORS) + " |")
        md.append("")
        aucs = {d: roc(sub, all_series, d)[2] for d in ["no_history", "shipped", "playbook", "playbook_rules", "combined", "hybrid"]}
        md.append("Session-level ROC AUC: " + ", ".join(f"{d} {v:.3f}" for d, v in aucs.items()))
        md.append("")
        report[src + "_auc"] = aucs
        plots(sub, all_series, res, out if src == (sources[-1] if len(sources) == 1 else "all") else out / src, f"{src}: {n_s} scam / {len(sub) - n_s} benign sessions") \
            if (out / src).mkdir(parents=True, exist_ok=True) is None else None
    tag = ("_" + a.tag) if a.tag else ""
    (out / f"results{tag}.json").write_text(json.dumps(report, indent=1, default=float))
    (out / f"results{tag}.md").write_text("\n".join(md))
    print("\n".join(md))


def _score_noassert(session, extracted, model):
    eng = Engine(model)
    series = {d: [] for d in DETECTORS}
    for scr, ex in zip(session["screens"], extracted):
        ev = frozenset(ex["events"])
        st = eng.observe(Observation(t=scr["t"], events=ev))
        p = st.p_scam
        series["playbook"].append(p)
        series["no_history"].append(Engine(model).observe(Observation(t=0, events=ev)).p_scam)
        series["shipped"].append(ex["risk_p"])
        series["rule"].append(1.0 if any(Event(e) in HIGH_RISK for e in ev) else 0.0)
        series["playbook_rules"].append(max(p, 1.0 if ex.get("rules") else 0.0))
        series["combined"].append(max(p, ex["risk_p"]))
        # What the app ships, computed by the Swift ScamPipeline itself (action >= interrupt counts as an alarm).
        series["hybrid"].append(max(ex["shipped_p"], 1.0 if ex["shipped_action"] in ("interrupt", "block+alert") else 0.0))
        # Any visible reaction at all, including the gentle nudge bubble.
        series["hybrid_any_reaction"].append(1.0 if ex["shipped_action"] != "quiet" else 0.0)
    return series


if __name__ == "__main__":
    main()
