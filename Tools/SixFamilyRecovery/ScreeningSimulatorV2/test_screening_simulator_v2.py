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
    return sim.run_screening(_candidates(f), cm, market, mm, params, f.policy_id, f.test_end)


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


def _load_mql5_results():
    # Optional per-fixture MQL5 isolated-runtime results produced by
    # collect_mql5_results.py. When present, the MQL5 parity test's PASS is
    # simultaneously the cross-language parity result (identical run-status +
    # canonical outcome SHA-256 vs the Python reference).
    path = ROOT / "mql5_results.csv"
    if not path.exists():
        return {}
    with path.open(newline="") as f:
        return {row["fixture_id"]: row["mql5_result"] for row in csv.DictReader(f)}


def tearDownModule():
    mql5 = _load_mql5_results()
    merged = []
    for fid, behavior, exp_status, exp_exit, py, _m, _p in sorted(set(_coverage)):
        mres = mql5.get(fid, "PENDING")
        parity = "PENDING" if mres == "PENDING" else (
            "PASS" if (py == "PASS" and mres == "PASS") else "FAIL")
        merged.append((fid, behavior, exp_status, exp_exit, py, mres, parity))
    rows = [("fixture_id", "behavior", "expected_status", "expected_exit",
             "python_result", "mql5_result", "parity_result")] + merged
    out = io.StringIO()
    w = csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\r\n", doublequote=True)
    for r in rows:
        w.writerow(r)
    (ROOT / "fixture_coverage.csv").write_bytes(out.getvalue().encode("utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
