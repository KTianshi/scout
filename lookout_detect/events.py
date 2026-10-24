"""Evidence events and observations.

One observation = everything noticed at one moment (one screen change, one app launch). It is a SET of
events, because a fake pop-up shows urgency, a phone number and a brand at the same time.
An observation with no events is NEUTRAL_ACTIVITY: "the screen changed and nothing suspicious was on it".
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Event(str, Enum):
    URGENT_LANGUAGE = "URGENT_LANGUAGE"
    PHONE_NUMBER_IN_POPUP = "PHONE_NUMBER_IN_POPUP"
    BRAND_IMPERSONATION = "BRAND_IMPERSONATION"
    LOOKALIKE_DOMAIN = "LOOKALIKE_DOMAIN"
    INFECTED_CLAIM = "INFECTED_CLAIM"
    REFUND_OVERPAYMENT = "REFUND_OVERPAYMENT"
    REMOTE_ACCESS_STARTED = "REMOTE_ACCESS_STARTED"
    SCREEN_SHARE_ACTIVE = "SCREEN_SHARE_ACTIVE"
    BANK_SITE_OPENED = "BANK_SITE_OPENED"
    SENSITIVE_FIELD_ON_UNKNOWN_SITE = "SENSITIVE_FIELD_ON_UNKNOWN_SITE"
    PAYMENT_DEMAND = "PAYMENT_DEMAND"
    GIFT_CARD_PAGE = "GIFT_CARD_PAGE"
    WIRE_OR_CRYPTO_PAGE = "WIRE_OR_CRYPTO_PAGE"
    SECRECY_REQUEST = "SECRECY_REQUEST"
    FAMILY_EMERGENCY_STORY = "FAMILY_EMERGENCY_STORY"
    LEGAL_THREAT = "LEGAL_THREAT"
    GOV_IMPERSONATION = "GOV_IMPERSONATION"
    CLAUDE_FLAG = "CLAUDE_FLAG"


NEUTRAL_ACTIVITY = frozenset()  # an observation with no flags

# Flags reported by a model (Claude). They only count, present or absent, when the model actually ran.
MODEL_REPORTED = frozenset({Event.CLAUDE_FLAG})


@dataclass(frozen=True)
class Observation:
    t: float                                  # seconds (any epoch); only differences matter
    events: frozenset = field(default_factory=frozenset)
    model_ran: bool = False                   # True if Claude looked at this screen
    source: str = "screen"                    # where it came from: screen, apps, claude, manual

    def __post_init__(self):
        object.__setattr__(self, "events", frozenset(Event(e) for e in self.events))
        if Event.CLAUDE_FLAG in self.events:
            object.__setattr__(self, "model_ran", True)

    def observed(self) -> list[Event]:
        """Flags whose presence or absence is informative for this observation."""
        return [e for e in Event if self.model_ran or e not in MODEL_REPORTED]

    def to_json(self) -> dict:
        return {"t": self.t, "events": sorted(e.value for e in self.events), "model_ran": self.model_ran, "source": self.source}

    @staticmethod
    def from_json(d: dict) -> "Observation":
        return Observation(t=float(d["t"]), events=frozenset(d.get("events", [])), model_ran=bool(d.get("model_ran", False)), source=d.get("source", "screen"))
