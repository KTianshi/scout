"""Builds one combined HMM from model/playbooks.json.

States: benign states first (idle + look-alike activities), then every stage of every scam playbook.
  idle            → benign activity (enter_b), scam playbook p (enter_p × entry_stages_p), else stays idle
  benign activity → stays (stay_b) or returns to idle
  scam stage i    → [stay, advance one, skip one, abandon→idle] from the playbook's transition rows
Time: before each observation, scam stages drift to idle with prob 1 - exp(-dt/tau_scam), benign
activities with 1 - exp(-dt/tau_benign).
Emissions: each event is an independent Bernoulli with P(event present | state) = q[state, event], and every
non-idle state is "distracted" with probability d (emits like idle): b_s(x) = (1-d) b_stage(x) + d b_idle(x).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from .events import Event

DEFAULT_PATH = Path(__file__).resolve().parent.parent / "model" / "playbooks.json"
EVENTS = list(Event)


@dataclass
class PlaybookModel:
    config: dict
    states: list[str]            # "idle", "remote_help", ..., "tech_support:popup", ...
    is_scam: np.ndarray          # bool [n]
    playbook_of: list[str | None]
    stage_index: list[int]       # stage position within its playbook (-1 for benign)
    playbooks: list[str]
    start: np.ndarray            # [n] probabilities
    A: np.ndarray                # [n, n] base transition probabilities (dt = 0)
    Q: np.ndarray                # [n, E] P(event present | state)
    tau_scam: float
    tau_benign: float
    distraction: float = 0.0
    idle: int = 0

    @property
    def n(self) -> int:
        return len(self.states)

    def transition(self, dt: float) -> np.ndarray:
        """Transition matrix for a gap of dt seconds between observations."""
        A = self.A.copy()
        if dt <= 0:
            return A
        r_scam = 1.0 - np.exp(-dt / self.tau_scam)
        r_benign = 1.0 - np.exp(-dt / self.tau_benign)
        e_idle = np.zeros(self.n)
        e_idle[self.idle] = 1.0
        for s in range(self.n):
            if s == self.idle:
                continue
            r = r_scam if self.is_scam[s] else r_benign
            A[s] = (1 - r) * A[s] + r * e_idle
        return A

    def stages_of(self, playbook: str) -> list[int]:
        return [i for i, p in enumerate(self.playbook_of) if p == playbook]

    def label(self, playbook: str) -> str:
        return self.config["playbooks"][playbook].get("label", playbook)

    def hint(self, state: int) -> str:
        pb = self.playbook_of[state]
        if pb is None:
            return ""
        return self.config["playbooks"][pb]["stages"][self.stage_index[state]].get("hint", "")


def build(config: dict) -> PlaybookModel:
    events = config["events"]
    assert events == [e.value for e in EVENTS], "playbooks.json events must match lookout_detect.events.Event order"
    E = len(events)
    floor = float(config.get("probability_floor", 1e-4))
    benign_default = float(config.get("default_benign_rate", 0.002))
    scam_default = float(config.get("default_scam_rate", 0.01))

    states, is_scam, playbook_of, stage_index = [], [], [], []
    rows_q, start = [], []
    benign = config["benign"]["states"]
    order = config.get("order", {})
    if order:
        assert order["benign"] == list(benign) and order["playbooks"] == list(config["playbooks"]), "order block must match object key order"
    assert next(iter(benign)) == "idle", "the first benign state must be idle"
    for name, s in benign.items():
        states.append(name); is_scam.append(False); playbook_of.append(None); stage_index.append(-1)
        q = np.full(E, benign_default)
        for e, v in s["emit"].items():
            q[events.index(e)] = v
        rows_q.append(q)
        start.append(float(s.get("start", 0.0)))

    playbooks = list(config["playbooks"])
    for pb in playbooks:
        spec = config["playbooks"][pb]
        for i, st in enumerate(spec["stages"]):
            states.append(f"{pb}:{st['name']}"); is_scam.append(True); playbook_of.append(pb); stage_index.append(i)
            q = np.full(E, scam_default)
            for e, v in st["emit"].items():
                q[events.index(e)] = v
            rows_q.append(q)
            start.append(0.0)

    n = len(states)
    A = np.zeros((n, n))
    idle = 0
    # Benign activities
    enter_total = 0.0
    for j, (name, s) in enumerate(benign.items()):
        if j == idle:
            continue
        A[idle, j] = float(s.get("enter", 0.0))
        enter_total += A[idle, j]
        stay = float(s.get("stay", 0.8))
        A[j, j] = stay
        A[j, idle] += 1.0 - stay
    # Scam playbooks
    for pb in playbooks:
        spec = config["playbooks"][pb]
        idx = [k for k in range(n) if playbook_of[k] == pb]
        entry = np.asarray(spec.get("entry_stages", [1.0] + [0.0] * (len(idx) - 1)), dtype=float)
        entry = entry / entry.sum()
        enter = float(spec.get("enter", 1e-4))
        for k, p in zip(idx, entry):
            A[idle, k] += enter * p
        enter_total += enter
        start_mass = enter  # scams can be in progress when Lookout starts, at the entry rate
        for k, p in zip(idx, entry):
            start[k] += start_mass * p
        rows = spec["transitions"]["rows"]
        assert len(rows) == len(idx), f"{pb}: one transition row per stage"
        for i, k in enumerate(idx):
            stay, adv, skip, abandon = rows[i]
            A[k, k] += stay
            if i + 1 < len(idx):
                A[k, idx[i + 1]] += adv
            else:
                abandon += adv
            if i + 2 < len(idx):
                A[k, idx[i + 2]] += skip
            else:
                # can't skip past the end: treat as advance if possible, else stay
                if i + 1 < len(idx):
                    A[k, idx[i + 1]] += skip
                else:
                    A[k, k] += skip
            A[k, idle] += abandon
    A[idle, idle] = 1.0 - enter_total
    assert A[idle, idle] > 0
    assert np.allclose(A.sum(axis=1), 1.0), "transition rows must sum to 1"

    start = np.asarray(start, dtype=float)
    start[idle] = 0.0
    start[idle] = 1.0 - start.sum()
    assert start[idle] > 0

    Q = np.clip(np.vstack(rows_q), floor, 1 - floor)
    t = config.get("timing", {})
    return PlaybookModel(
        config=config, states=states, is_scam=np.asarray(is_scam), playbook_of=playbook_of, stage_index=stage_index,
        playbooks=playbooks, start=start, A=A, Q=Q,
        tau_scam=float(t.get("scam_return_tau_s", 1800)), tau_benign=float(t.get("benign_return_tau_s", 900)),
        distraction=float(config.get("distraction", 0.0)),
    )


def load_model(path: str | Path = DEFAULT_PATH) -> PlaybookModel:
    with open(path) as f:
        return build(json.load(f))
