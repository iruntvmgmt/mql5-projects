#!/usr/bin/env python3
"""Python JOURNAL_BINDING (JB) suite over the certified public simulator entry.

Every fixture builds a real family-8 journal, an honest verified bundle via the
binding adapter, applies its tamper, then calls the certified public
run_screening(bundle, ...) and asserts the run-status token. Binding failures
must yield REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH with zero outcomes.
"""
from __future__ import annotations

import dataclasses
import hashlib
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "JournalTransportV2"))
sys.path.insert(0, str(HERE.parent / "ScreeningExecutionV2"))

import journal_binding_fixtures as jbf
import research_journal_transport_v2 as jt
import screening_simulator_v2 as sim
import verified_candidate_journal_v2 as adapt
from screening_market_v2 import (
    build_market_manifest, instrument_params_bytes, market_data_bytes,
    parse_instrument_params, parse_market_data, MarketBar,
)

HEADER = jbf.header_line().split(",")


def _market():
    market = parse_market_data(market_data_bytes(jbf.SYMBOL, jbf.TF, [MarketBar(*b) for b in jbf.BARS]))
    mm = build_market_manifest(market)
    params = parse_instrument_params(
        instrument_params_bytes(jbf.SYMBOL, jbf.TF, jbf.POINT_SIZE_1E8, jbf.TICK_SIZE_1E8, 0, 0)
    )
    return market, mm, params


def _manifest(journal_sha: str, row_count: int, source_sha: str, symbol: str, timeframe: int) -> jt.Manifest:
    return jt.Manifest(jt.MANIFEST_VERSION, jt.WRITER_VERSION, jt.SCHEMA_VERSION,
                       symbol, timeframe, row_count, journal_sha, source_sha)


_MUT = {
    "MUTATE_ENTRY": lambda c: dataclasses.replace(c, entry=c.entry + 1.0),
    "MUTATE_STOP": lambda c: dataclasses.replace(c, stop=c.stop - 0.5),
    "MUTATE_TARGET": lambda c: dataclasses.replace(c, target=c.target + 1.0),
    "MUTATE_TARGET_R": lambda c: dataclasses.replace(c, target_r=c.target_r + 1.0),
    "MUTATE_SIGNAL": lambda c: dataclasses.replace(c, signal_time=c.signal_time + 1),
    "MUTATE_EXPIRY": lambda c: dataclasses.replace(c, expiry_time=c.expiry_time + 1),
    "MUTATE_EVENT_ID": lambda c: dataclasses.replace(c, event_id=c.event_id + "X"),
    "MUTATE_SEQUENCE_ID": lambda c: dataclasses.replace(c, sequence_id=c.sequence_id + "X"),
}


def build_case(fx: jbf.JBFixture):
    market, mm, params = _market()
    rows = list(fx.rows)
    used = list(reversed(rows)) if fx.permute_rows else rows
    jbytes = jbf.journal_bytes(used)

    try:
        honest_sha = jt.reconstruct_verified_rows(jbytes, HEADER).journal_sha256
    except jt.TransportError:
        # Source journal is intentionally invalid (e.g. bad clock/authority in a
        # row). Build a valid baseline bundle, then inject the invalid bytes so
        # the certified entry re-derives them and fails closed with the token.
        base = jbf.journal_bytes([jbf.A_LONG])
        base_sha = jt.reconstruct_verified_rows(base, HEADER).journal_sha256
        base_man = _manifest(base_sha, 1, market.market_data_sha256, jbf.SYMBOL, jbf.TF)
        bundle = adapt.build_verified_bundle(base, HEADER, base_man, jbf.SYMBOL, jbf.TF, market.market_data_sha256)
        return dataclasses.replace(bundle, journal_bytes=jbytes), market, mm, params

    # honest manifest over the exact (possibly permuted) bytes
    man = _manifest(honest_sha, len(used), market.market_data_sha256, jbf.SYMBOL, jbf.TF)
    bundle = adapt.build_verified_bundle(jbytes, HEADER, man, jbf.SYMBOL, jbf.TF, market.market_data_sha256)

    # ---- apply tampers (all via immutable replace on the frozen bundle) ----
    if fx.stale_manifest_after_permute:
        stale = jt.reconstruct_verified_rows(jbf.journal_bytes(rows), HEADER).journal_sha256
        bundle = dataclasses.replace(bundle, manifest=dataclasses.replace(bundle.manifest, journal_sha256=stale))

    man_over = dict(
        journal_sha256=fx.manifest_journal_sha,
        row_count=fx.manifest_row_count,
        source_data_sha256=fx.manifest_source_sha,
        symbol=fx.manifest_symbol,
        timeframe=fx.manifest_timeframe,
    )
    man_over = {k: v for k, v in man_over.items() if v is not None}
    if man_over:
        bundle = dataclasses.replace(bundle, manifest=dataclasses.replace(bundle.manifest, **man_over))

    t = fx.tamper
    if t in _MUT:
        cands = list(bundle.candidates)
        cands[0] = _MUT[t](cands[0])
        bundle = dataclasses.replace(bundle, candidates=tuple(cands))
    elif t == "ADD_CANDIDATE":
        extra = dataclasses.replace(bundle.candidates[0], event_id="EXTRA|1", sequence_id="EXTRA|1")
        bundle = dataclasses.replace(bundle, candidates=bundle.candidates + (extra,))
    elif t == "REMOVE_CANDIDATE":
        bundle = dataclasses.replace(bundle, candidates=bundle.candidates[:-1])
    elif t == "DUP_CANDIDATE":
        bundle = dataclasses.replace(bundle, candidates=bundle.candidates + (bundle.candidates[0],))
    elif t == "BUNDLE_VERSION":
        bundle = dataclasses.replace(bundle, bundle_version="X")
    elif t == "TRANSPORT_VERSION":
        bundle = dataclasses.replace(bundle, transport_version="X")
    elif t == "PROJECTION_VERSION":
        bundle = dataclasses.replace(bundle, projection_version="X")
    elif t == "SCHEMA_VERSION":
        bundle = dataclasses.replace(bundle, schema_version="X")

    return bundle, market, mm, params


class JournalBindingTests(unittest.TestCase):
    def test_all(self):
        ids = jbf.fixture_ids()
        self.assertEqual(len(ids), len(set(ids)), "duplicate JB ids")
        for fx in jbf.FIXTURES:
            with self.subTest(fx.id):
                bundle, market, mm, params = build_case(fx)
                status, outcomes = sim.run_screening(
                    bundle, market, mm, params, "MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST"
                )
                self.assertEqual(status, fx.expect_run_status, f"{fx.id} {fx.behavior}")
                if status != sim.RUN_OK:
                    self.assertEqual(outcomes, [], f"{fx.id} must emit no outcomes on abort")

    def test_projection_preserves_journal_target(self):
        # JB01 candidate must carry the journal-owned target and target_r verbatim.
        bundle, *_ = build_case(jbf.FIXTURES[0])
        c = bundle.candidates[0]
        self.assertEqual(c.target, 102.0)
        self.assertEqual(c.target_r, 2.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
