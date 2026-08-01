#!/usr/bin/env python3
"""Python ORDERING (OR) suite: the simulator's frozen candidate order must equal
the reference UTF-8 bytewise order for every OR fixture, and be deterministic
under input shuffling. The MQL5 UTF-8 comparator must reproduce these ranks.
"""
from __future__ import annotations

import pathlib
import random
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "ScreeningExecutionV2"))

import ordering_fixtures as orf
import screening_simulator_v2 as sim


def _candidate(o: orf.OCand) -> sim.Candidate:
    return sim.Candidate(
        strategy_id=1200, family_id=o.family, hypothesis_version="H",
        canonical_variant_id="V", origin_id="O", sequence_id=o.sequence_id,
        event_id=o.event_id, clock_domain="BROKER_SERVER_RAW",
        time_authority_id="MSZZ_TIME_RAW_BROKER_V1", signal_time=o.signal,
        expiry_time=o.signal + 1000, direction=1, entry=100.0, stop=99.0,
        target=102.0, target_r=2.0, stop_distance_points=100.0,
    )


def _ranks_via_sim(cands: list[sim.Candidate]) -> list[int]:
    # sort input indices by the simulator's frozen key (stable via trailing i)
    order = sorted(range(len(cands)), key=lambda i: (sim._sort_key(cands[i]), i))
    ranks = [0] * len(cands)
    for rank, idx in enumerate(order):
        ranks[idx] = rank
    return ranks


class OrderingTests(unittest.TestCase):
    def test_ranks_match_reference(self):
        ids = orf.fixture_ids()
        self.assertEqual(len(ids), len(set(ids)), "duplicate OR ids")
        for fx in orf.FIXTURES:
            with self.subTest(fx.id):
                cands = [_candidate(o) for o in fx.cands]
                self.assertEqual(
                    _ranks_via_sim(cands), orf.expected_ranks(fx),
                    f"{fx.id} {fx.behavior}",
                )

    def test_shuffled_determinism(self):
        rng = random.Random(20260731)
        for fx in orf.FIXTURES:
            base = [_candidate(o) for o in fx.cands]
            base_sorted = sorted(base, key=sim._sort_key)
            base_keys = [(c.event_id, c.sequence_id, c.signal_time, c.family_id) for c in base_sorted]
            for _ in range(5):
                shuffled = base[:]
                rng.shuffle(shuffled)
                s = sorted(shuffled, key=sim._sort_key)
                keys = [(c.event_id, c.sequence_id, c.signal_time, c.family_id) for c in s]
                # equal-key ties may reorder equal candidates but the key sequence
                # (what the outcome document depends on) is identical.
                self.assertEqual(keys, base_keys, f"{fx.id} nondeterministic")

    def test_emoji_vs_high_bmp_divergence(self):
        # OR09 guards the UTF-8-vs-UTF-16 divergence explicitly.
        fx = next(f for f in orf.FIXTURES if f.id == "OR09")
        cands = [_candidate(o) for o in fx.cands]
        order = sorted(cands, key=sim._sort_key)
        # explicit codepoints: ascii 'A', high-BMP U+F900, supplementary U+1F600
        self.assertEqual(
            [[hex(ord(ch)) for ch in c.event_id] for c in order],
            [["0x41"], ["0xf900"], ["0x1f600"]],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
