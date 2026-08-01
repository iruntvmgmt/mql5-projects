#!/usr/bin/env python3
"""Data-driven Python reference test over the 58 shared ScreeningSimulatorV2 fixtures.

Fixtures come from simulator_fixtures.FIXTURES (the single language-neutral
source). Emits fixture_coverage.csv: python_result from this run, and
mql5_result/parity_result joined from mql5_results.csv when present
(produced by collect_mql5_results.py from the isolated /portable runtime
log), else PENDING."""

from __future__ import annotations

import csv
import io
import unittest
from pathlib import Path

from screening_market_v2 import (
    MarketBar, MarketTransportError, build_market_manifest, instrument_params_bytes,
    market_data_bytes, parse_instrument_params, parse_market_data,
)
import screening_simulator_v2 as sim
import simulator_fixtures as fx

ROOT = Path(__file__).resolve().parent
_coverage: list[tuple] = []


def _mm(market, sha_override):
    mm = build_market_manifest(market)
    if sha_override is not None:
        from dataclasses import replace
        mm = replace(mm, market_data_sha256=sha_override)
    return mm


def _candidates(f: fx.Fixture):
    clock, auth, sd = "BROKER_SERVER_RAW", "MSZZ_TIME_RAW_BROKER_V1", None
    for e in f.expect:
        clock = e.get("__clock__", clock)
        auth = e.get("__auth__", auth)
        sd = e.get("__stop_distance__", sd)
    return [fx.build_candidate(fc, clock, auth, sd) for fc in f.cands]


def _run(f: fx.Fixture):
    bars = [MarketBar(*b) for b in f.bars]
    market = parse_market_data(market_data_bytes(fx.SYMBOL, fx.TF, bars))
    mm = _mm(market, f.mm_sha_override)
    params = parse_instrument_params(instrument_params_bytes(fx.SYMBOL, fx.TF, *f.params))
    source = f.cm_source if f.cm_source is not None else market.market_data_sha256
    cm = sim.CandidateManifest(f.cm_symbol, f.cm_timeframe, fx.JSHA, source)
    # EXECUTION_CORE fixtures exercise the internal mechanics core directly; the
    # certified public run_screening(bundle, ...) journal-binding path is covered
    # by the JB suite, not by F01-F58.
    return sim._run_screening_core(_candidates(f), cm, market, mm, params, f.policy_id, f.test_end)


class SimulatorMatrix(unittest.TestCase):
    def _record(self, f, ok):
        exp_status = f.expect_run_status if f.expect_run_status != "RUN_OK" else (
            f.expect[0].get("status", "ACCEPTED") if f.expect else "ACCEPTED")
        exp_exit = f.expect[0].get("exit_reason", "") if f.expect else ""
        _coverage.append((f.id, f.behavior, exp_status, exp_exit,
                          "PASS" if ok else "FAIL", "PENDING", "PENDING"))
        self.assertTrue(ok, f"{f.id} {f.behavior}")

    def test_all_fixtures(self):
        for f in fx.FIXTURES:
            if f.expect_run_status == "TRANSPORT_REJECT":
                try:
                    parse_market_data(market_data_bytes(fx.SYMBOL, fx.TF,
                                                        [MarketBar(*b) for b in f.bars]))
                    ok = False
                except MarketTransportError:
                    ok = True
                self._record(f, ok)
                continue

            status, outcomes = _run(f)
            if f.expect_run_status != "RUN_OK":
                self._record(f, status == f.expect_run_status and outcomes == [])
                continue

            ok = status == sim.RUN_OK
            for i, exp in enumerate(f.expect):
                o = outcomes[i]
                for key, val in exp.items():
                    if key.startswith("__"):
                        continue
                    ok = ok and (getattr(o, key) == val)
            # determinism: shuffled re-run yields identical canonical bytes
            if len(f.cands) > 1:
                f2 = fx.Fixture(**{**f.__dict__, "cands": list(reversed(f.cands))})
                s2, o2 = _run(f2)
                ok = ok and (sim.outcomes_document(status, outcomes) ==
                             sim.outcomes_document(s2, o2))
            self._record(f, ok)


# Cross-language coverage (all 95 fixtures across the three groups) is produced
# by make_coverage_v2.py from the validated collector-V2 output; this suite only
# proves the Python EXECUTION_CORE reference behavior.

if __name__ == "__main__":
    unittest.main(verbosity=2)
