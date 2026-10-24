"""Learn emission probabilities with Baum-Welch (MAP-EM), starting from the hand-set values.

E-step: forward-backward over each session (log space, time-dependent transitions A(dt), mixture emissions).
M-step: for every state s and event e,
    q[s,e] = (expected count of e present while s emits from its own distribution + kappa * q0[s,e])
             / (expected number of such observations where e was observable + kappa)
i.e. a Beta(kappa*q0, kappa*(1-q0)) prior centred on the hand-set value, so sparse data cannot push a
parameter to an extreme. Screens emitted in "distracted" mode count toward idle's emissions.
Transitions are kept as hand-set (their time dependence makes them poorly identified from few sessions).

    .venv/bin/python -m lookout_detect.learn eval/sessions_scripted.jsonl --out model/playbooks_learned.json
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import numpy as np

from .engine import logsumexp
from .events import Event, Observation
from .model import EVENTS, DEFAULT_PATH, build

E = len(EVENTS)


def sequences(files: list[str]) -> list[list[Observation]]:
    from .eval import extract
    out = []
    for f in files:
        for line in open(f):
            if not line.strip():
                continue
            s = json.loads(line)
            ex = extract(s)
            out.append([Observation(t=scr["t"], events=frozenset(e["events"])) for scr, e in zip(s["screens"], ex)])
    return out


def emission_parts(model, logQ, log1mQ, obs: Observation):
    """Per-state log own-emission, log idle-emission, observed mask and presence vector."""
    x = np.array([e in obs.events for e in EVENTS], dtype=float)
    mask = np.array([e in obs.observed() for e in EVENTS], dtype=float)
    own = (mask * (x * logQ + (1 - x) * log1mQ)).sum(axis=1)
    return own, own[model.idle], x, mask


def fit(model, seqs, iters: int = 8, kappa: float = 20.0, verbose: bool = True):
    q0 = model.Q.copy()
    d = model.distraction
    n = model.n
    with np.errstate(divide="ignore"):
        log_start = np.log(model.start)
    history = []
    for it in range(iters):
        logQ, log1mQ = np.log(model.Q), np.log1p(-model.Q)
        num = np.zeros((n, E))
        den = np.zeros((n, E))
        total_ll = 0.0
        for seq in seqs:
            T = len(seq)
            parts = [emission_parts(model, logQ, log1mQ, o) for o in seq]
            logb = np.zeros((T, n)); rho = np.ones((T, n))
            for t, (own, idle_part, _, _) in enumerate(parts):
                if d > 0:
                    a = np.log1p(-d) + own; b = np.log(d) + idle_part
                    mix = np.logaddexp(a, b)
                    mix[model.idle] = own[model.idle]
                    rho[t] = np.exp(a - mix); rho[t, model.idle] = 1.0
                    logb[t] = mix
                else:
                    logb[t] = own
            with np.errstate(divide="ignore"):
                logA = [None] + [np.log(model.transition(max(0.0, seq[t].t - seq[t - 1].t))) for t in range(1, T)]
            la = np.zeros((T, n)); lb = np.zeros((T, n))
            la[0] = log_start + logb[0]
            for t in range(1, T):
                la[t] = logsumexp(la[t - 1][:, None] + logA[t], axis=0) + logb[t]
            for t in range(T - 2, -1, -1):
                lb[t] = logsumexp(logA[t + 1] + (logb[t + 1] + lb[t + 1])[None, :], axis=1)
            ll = logsumexp(la[-1])
            total_ll += float(ll)
            gamma = np.exp(la + lb - ll)
            for t, (_, _, x, mask) in enumerate(parts):
                g_own = gamma[t] * rho[t]
                num += np.outer(g_own, x * mask)
                den += np.outer(g_own, mask)
                # distracted screens were emitted from idle's distribution
                g_idle = float((gamma[t] * (1 - rho[t])).sum())
                num[model.idle] += g_idle * x * mask
                den[model.idle] += g_idle * mask
        newQ = (num + kappa * q0) / (den + kappa)
        floor = float(model.config.get("probability_floor", 1e-4))
        model.Q = np.clip(newQ, floor, 1 - floor)
        history.append(total_ll)
        if verbose:
            print(f"iter {it + 1}: log-likelihood {total_ll:.2f}")
    return model, history


def to_config(model, base: dict) -> dict:
    cfg = copy.deepcopy(base)
    for i, name in enumerate(model.states):
        emit = {e.value: round(float(model.Q[i, k]), 5) for k, e in enumerate(EVENTS)}
        if model.playbook_of[i] is None:
            cfg["benign"]["states"][name]["emit"] = emit
        else:
            pb, stage = name.split(":", 1)
            st = next(s for s in cfg["playbooks"][pb]["stages"] if s["name"] == stage)
            st["emit"] = emit
    cfg["about"] = "LEARNED by lookout_detect/learn.py (MAP Baum-Welch on emissions, Beta prior centred on the hand-set values). " + cfg["about"]
    return cfg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", default="model/playbooks_learned.json")
    ap.add_argument("--iters", type=int, default=8)
    ap.add_argument("--kappa", type=float, default=20.0)
    a = ap.parse_args()
    base = json.loads(Path(DEFAULT_PATH).read_text())
    model = build(base)
    seqs = sequences(a.files)
    print(f"{len(seqs)} sequences, {sum(map(len, seqs))} observations")
    model, hist = fit(model, seqs, a.iters, a.kappa)
    cfg = to_config(model, base)
    Path(a.out).write_text(json.dumps(cfg, indent=1))
    q0 = build(base).Q
    diff = np.abs(model.Q - q0)
    i, k = np.unravel_index(np.argmax(diff), diff.shape)
    print(f"wrote {a.out}; largest change: {model.states[i]} / {EVENTS[k].value}: {q0[i, k]:.3f} → {model.Q[i, k]:.3f}")


if __name__ == "__main__":
    main()
