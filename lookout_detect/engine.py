"""Forward filtering over the combined playbook HMM, entirely in log space.

For every observation:
  1. predict:  log pred_j = logsumexp_i (log alpha_i + log A(dt)_ij)
  2. update:   log alpha_j ∝ log pred_j + log b_j(x)
  3. report:   P(scam) = mass on scam states, P(type), stage posterior, next stage, evidence ledger

Evidence ledger (log Bayes factors, in nats). Scam-vs-benign log-odds evolve as

    L_t = L_{t-1} + drift_t + sum_k contribution_{t,k}

  drift_t           time passing / stage transitions (log predicted odds minus previous log odds)
  contribution_t,k  one entry per piece of evidence: the change in log-odds when that flag is added,
                    with "nothing else on screen" (all observed-but-absent flags) first, then present
                    flags in a fixed order. The entries sum EXACTLY to the observation's log Bayes factor
                    log P(x_t | history, scam) - log P(x_t | history, benign).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .events import Event, Observation
from .model import EVENTS, PlaybookModel, load_model

NEG_INF = -np.inf


def logsumexp(a: np.ndarray, axis=None) -> np.ndarray:
    m = np.max(a, axis=axis, keepdims=True)
    m = np.where(np.isfinite(m), m, 0.0)
    with np.errstate(divide="ignore"):
        out = np.log(np.sum(np.exp(a - m), axis=axis, keepdims=True)) + m
    return np.squeeze(out, axis=axis) if axis is not None else out.item()


@dataclass
class LedgerEntry:
    step: int
    t: float
    item: str          # an Event value, "time passes", or "nothing else on screen"
    log_bf: float      # nats; positive pushes toward scam
    source: str

    def to_json(self) -> dict:
        return {"step": self.step, "t": self.t, "item": self.item, "log_bf": round(self.log_bf, 6), "source": self.source}


@dataclass
class EngineState:
    step: int
    t: float
    p_scam: float
    log_odds: float
    by_type: dict[str, float]
    top_type: str | None
    top_type_label: str | None
    stage_posterior: dict[str, float]            # within the top scam type, normalised
    current_stage: str | None
    next_stage: str | None
    next_hint: str | None
    next_event: str | None                       # the event the next stage most characteristically produces
    log_likelihood: float                        # log P(x_1..t) under the whole model
    lookalike: str | None = None                 # most likely benign look-alike activity (not idle), if any
    lookalike_p: float = 0.0                     # posterior mass on benign look-alike activities
    ledger: list[LedgerEntry] = field(default_factory=list)   # entries added by this observation

    def to_json(self) -> dict:
        d = {k: v for k, v in self.__dict__.items() if k != "ledger"}
        d["ledger"] = [e.to_json() for e in self.ledger]
        return d


class Engine:
    def __init__(self, model: PlaybookModel | None = None):
        self.model = model or load_model()
        m = self.model
        self.scam = m.is_scam
        self.benign = ~m.is_scam
        with np.errstate(divide="ignore"):
            self.log_start = np.log(m.start)
        self.logQ = np.log(m.Q)
        self.log1mQ = np.log1p(-m.Q)
        self.reset()

    # ------------------------------------------------------------------ state

    def reset(self) -> None:
        self.log_alpha: np.ndarray | None = None
        self.t_last: float | None = None
        self.step = 0
        self.log_likelihood = 0.0
        self.ledger: list[LedgerEntry] = []
        self.log_odds = self._odds(self.log_start)

    def _odds(self, log_w: np.ndarray) -> float:
        return float(logsumexp(log_w[self.scam]) - logsumexp(log_w[self.benign]))

    @property
    def prior_log_odds(self) -> float:
        return self._odds(self.log_start)

    def posterior(self) -> np.ndarray:
        if self.log_alpha is None:
            return np.exp(self.log_start)
        return np.exp(self.log_alpha)

    # ------------------------------------------------------------------ core

    def predict(self, dt: float) -> np.ndarray:
        """Log predicted state distribution for the next observation after dt seconds."""
        if self.log_alpha is None:
            return self.log_start.copy()
        with np.errstate(divide="ignore"):
            logA = np.log(self.model.transition(dt))
        return logsumexp(self.log_alpha[:, None] + logA, axis=0)

    def _mix(self, own: np.ndarray, idle_part: float) -> np.ndarray:
        """log((1-d) exp(own_s) + d exp(idle_part)) for non-idle states; idle keeps its own emission."""
        d = self.model.distraction
        if d <= 0:
            return own
        out = np.logaddexp(np.log1p(-d) + own, np.log(d) + idle_part)
        out[self.model.idle] = own[self.model.idle]
        return out

    def emission_terms(self, obs: Observation) -> list[tuple[str, np.ndarray]]:
        """Per-item log-likelihood vectors over states, in ledger order. Their sum is log b(x)."""
        present = [e for e in EVENTS if e in obs.events]
        absent = [e for e in obs.observed() if e not in obs.events]
        items: list[tuple[str, np.ndarray]] = []
        if absent:
            idx = [EVENTS.index(e) for e in absent]
            items.append(("nothing else on screen", self.log1mQ[:, idx].sum(axis=1)))
        for e in present:
            items.append((e.value, self.logQ[:, EVENTS.index(e)]))
        return items

    def observe(self, obs: Observation) -> EngineState:
        dt = 0.0 if self.t_last is None else max(0.0, obs.t - self.t_last)
        log_pred = self.predict(dt)
        self.step += 1
        entries: list[LedgerEntry] = []

        L_prev = self.log_odds
        L = self._odds(log_pred)
        if self.log_alpha is not None:
            entries.append(LedgerEntry(self.step, obs.t, "time passes", L - L_prev, "model"))

        # Emission = mixture of the state's own distribution and idle's ("distracted" screens). Track both
        # partial products so every ledger entry is an exact chain-rule step of the mixture likelihood.
        own = np.zeros(self.model.n)
        idle_part = 0.0
        cum = log_pred.copy()
        for name, term in self.emission_terms(obs):
            own = own + term
            idle_part = idle_part + term[self.model.idle]
            cum = log_pred + self._mix(own, idle_part)
            L_new = self._odds(cum)
            entries.append(LedgerEntry(self.step, obs.t, name, L_new - L, obs.source))
            L = L_new

        norm = logsumexp(cum)
        self.log_likelihood += float(norm)
        self.log_alpha = cum - norm
        self.log_odds = L
        self.t_last = obs.t
        self.ledger.extend(entries)
        return self.state(entries)

    def run(self, observations) -> list[EngineState]:
        return [self.observe(o) for o in observations]

    # ------------------------------------------------------------------ reporting

    def state(self, entries: list[LedgerEntry] | None = None) -> EngineState:
        m = self.model
        post = self.posterior()
        by_type = {pb: float(post[m.stages_of(pb)].sum()) for pb in m.playbooks}
        p_scam = float(post[self.scam].sum())
        top = max(by_type, key=by_type.get) if by_type else None
        stage_post, cur, nxt, hint, nev = {}, None, None, None, None
        if top is not None and by_type[top] > 0:
            idx = m.stages_of(top)
            w = post[idx] / post[idx].sum()
            stage_post = {m.states[k].split(":", 1)[1]: float(p) for k, p in zip(idx, w)}
            cur_local = int(np.argmax(w))
            cur = m.states[idx[cur_local]].split(":", 1)[1]
            # Next stage: one transition from the current stage distribution, restricted to later stages.
            A = m.transition(0.0)
            later = idx[cur_local + 1:]
            if later:
                nxt_p = (w @ A[np.ix_(idx, idx)])[cur_local + 1:]
                k = later[int(np.argmax(nxt_p))]
                nxt = m.states[k].split(":", 1)[1]
                hint = m.hint(k)
                lift = self.logQ[k] - self.logQ[m.idle]
                nev = EVENTS[int(np.argmax(lift))].value
        act = [i for i in range(m.n) if not m.is_scam[i] and i != m.idle]
        look_p = float(post[act].sum())
        look = m.states[act[int(np.argmax(post[act]))]] if act and look_p > 0 else None
        return EngineState(
            lookalike=look, lookalike_p=look_p,
            step=self.step, t=self.t_last or 0.0, p_scam=p_scam, log_odds=self.log_odds, by_type=by_type,
            top_type=top, top_type_label=m.label(top) if top else None, stage_posterior=stage_post,
            current_stage=cur, next_stage=nxt, next_hint=hint, next_event=nev,
            log_likelihood=self.log_likelihood, ledger=entries or [],
        )

    def explain(self, top: int = 5) -> list[LedgerEntry]:
        """Largest evidence entries so far (by absolute size), for UI and family alerts."""
        return sorted((e for e in self.ledger if e.item != "time passes"), key=lambda e: -abs(e.log_bf))[:top]
