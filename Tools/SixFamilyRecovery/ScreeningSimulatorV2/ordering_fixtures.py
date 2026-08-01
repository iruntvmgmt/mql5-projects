#!/usr/bin/env python3
"""Language-neutral ORDERING (OR) fixture source for the frozen candidate order:
signal_time asc, family_id asc, event_id UTF-8 bytewise asc, sequence_id UTF-8
bytewise asc, stable. The expected rank of each candidate is generated from
Python UTF-8 bytes (the reference) and must be reproduced exactly by the MQL5
UTF-8 byte comparator.

The decisive case (OR09) contrasts a supplementary-plane emoji (U+1F600) with a
high-BMP character (U+F900): UTF-8 byte order puts U+F900 first, whereas MQL5
StringCompare over UTF-16 code units would place the emoji first — so a naive
comparator fails this fixture and the explicit UTF-8 comparator passes.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class OCand:
    signal: int
    family: int
    event_id: str
    sequence_id: str


@dataclass(frozen=True)
class ORFixture:
    id: str
    behavior: str
    cands: tuple[OCand, ...]


def _c(event: str, seq: str = "S|1", signal: int = 100, family: int = 8) -> OCand:
    return OCand(signal, family, event, seq)


FIXTURES: list[ORFixture] = [
    ORFixture("OR01", "ascii alphabetical", (_c("A"), _c("B"), _c("C"))),
    ORFixture("OR02", "punctuation + digit + shorter-first", (_c("E|1"), _c("E|10"), _c("E|2"))),
    ORFixture("OR03", "identical prefix shorter first", (_c("ABC"), _c("AB"), _c("ABCD"))),
    ORFixture("OR04", "event tie resolved by sequence", (_c("E|1", "S|2"), _c("E|1", "S|1"))),
    ORFixture("OR05", "shuffled input deterministic", (_c("C"), _c("A"), _c("B"))),
    ORFixture("OR06", "stable order for exact equal keys",
              (_c("E|1", "S|1"), _c("E|1", "S|1"), _c("E|1", "S|1"))),
    ORFixture("OR07", "accented latin bytewise", (_c("café"), _c("cafe"), _c("cafz"))),
    ORFixture("OR08", "greek vs ascii high byte", (_c("Α"), _c("Z"), _c("A"))),
    ORFixture("OR09", "emoji vs high-BMP (UTF-8 vs UTF-16 divergence)",
              (_c("\U0001F600"), _c("豈"), _c("A"))),
    ORFixture("OR10", "multibyte event tie resolved by multibyte sequence",
              (_c("é", "é|2"), _c("é", "é|1"))),
    ORFixture("OR11", "signal_time precedence", (_c("Z", signal=200), _c("A", signal=100))),
    ORFixture("OR12", "family_id precedence", (_c("Z", family=8), _c("A", family=13))),
    ORFixture("OR13", "cyrillic ordering", (_c("А"), _c("Я"), _c("A"))),
]


def sort_key(c: OCand):
    """Reference frozen key: UTF-8 bytewise on the string IDs."""
    return (c.signal, c.family, c.event_id.encode("utf-8"), c.sequence_id.encode("utf-8"))


def expected_ranks(fx: ORFixture) -> list[int]:
    """Rank (0-based sorted position) of each input candidate. Stable: equal
    keys keep input order, so the earliest input index gets the lower rank."""
    order = sorted(range(len(fx.cands)), key=lambda i: (sort_key(fx.cands[i]), i))
    ranks = [0] * len(fx.cands)
    for rank, idx in enumerate(order):
        ranks[idx] = rank
    return ranks


def fixture_ids() -> list[str]:
    return [f.id for f in FIXTURES]
