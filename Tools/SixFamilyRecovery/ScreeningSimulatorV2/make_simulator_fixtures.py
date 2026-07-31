#!/usr/bin/env python3
"""Serialize the 58 shared simulator fixtures + the Python reference expected outcomes.

Emits (committed, consumed by the MQL5 parity test):
  simulator_fixtures.csv   - language-neutral fixture inputs (META/BAR/CAND rows)
  expected_outcomes.csv    - fixture_id,run_status,row_count,outcome_sha256 (reference)

Canonical CSV bytes: UTF-8 no BOM, CRLF incl final, fully double-quoted data rows.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

from screening_market_v2 import (
    MarketBar, build_market_manifest, instrument_params_bytes, market_data_bytes,
    parse_instrument_params, parse_market_data,
)
import screening_simulator_v2 as sim
import simulator_fixtures as fx

ROOT = Path(__file__).resolve().parent
HEADER = ["fixture_id", "kind"] + [f"c{i}" for i in range(14)]


def _canon(fields):
    s = io.StringIO(newline="")
    csv.writer(s, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return s.getvalue()


def _row(fid, kind, vals):
    v = list(vals) + [""] * (14 - len(vals))
    return _canon([fid, kind] + [str(x) for x in v])


def _overrides(f):
    clock, auth, sd = "BROKER_SERVER_RAW", "MSZZ_TIME_RAW_BROKER_V1", "AUTO"
    for e in f.expect:
        clock = e.get("__clock__", clock)
        auth = e.get("__auth__", auth)
        if "__stop_distance__" in e:
            sd = repr(e["__stop_distance__"])
    return clock, auth, sd


def fixture_rows(f):
    rows = []
    src = "AUTO" if f.cm_source is None else f.cm_source
    mm = "AUTO" if f.mm_sha_override is None else f.mm_sha_override
    te = "NONE" if f.test_end is None else f.test_end
    ps, ts, stops, freeze = f.params
    rows.append(_row(f.id, "META", [te, f.policy_id, f.cm_symbol, f.cm_timeframe, fx.JSHA, src,
                                    ps, ts, stops, freeze, mm, f.expect_run_status, fx.SYMBOL, fx.TF]))
    for b in f.bars:
        rows.append(_row(f.id, "BAR", list(b)))
    clock, auth, sd = _overrides(f)
    for fc in f.cands:
        rows.append(_row(f.id, "CAND", [fc.d, fc.signal, fc.expiry, repr(fc.entry), repr(fc.stop),
                                        repr(fc.target_r), fc.fam, fc.event, fc.seq, 1200,
                                        clock, auth, sd]))
    return rows


def reference_outcome(f):
    """Return (run_status, row_count, sha256) from the Python reference, or TRANSPORT_REJECT."""
    bars = [MarketBar(*b) for b in f.bars]
    try:
        market = parse_market_data(market_data_bytes(fx.SYMBOL, fx.TF, bars))
    except Exception:
        return ("TRANSPORT_REJECT", 0, "")
    from dataclasses import replace
    mm = build_market_manifest(market)
    if f.mm_sha_override is not None:
        mm = replace(mm, market_data_sha256=f.mm_sha_override)
    params = parse_instrument_params(instrument_params_bytes(fx.SYMBOL, fx.TF, *f.params))
    source = f.cm_source if f.cm_source is not None else market.market_data_sha256
    cm = sim.CandidateManifest(f.cm_symbol, f.cm_timeframe, fx.JSHA, source)
    clock, auth, sd = _overrides(f)
    sd_val = None if sd == "AUTO" else float(sd)
    cands = [fx.build_candidate(fc, clock, auth, sd_val) for fc in f.cands]
    status, outcomes = sim.run_screening(cands, cm, market, mm, params, f.policy_id, f.test_end)
    return (status, len(outcomes), sim.outcomes_sha256(status, outcomes))


def main() -> int:
    frows = [_canon(HEADER)]
    erows = [_canon(["fixture_id", "run_status", "row_count", "outcome_sha256"])]
    for f in fx.FIXTURES:
        frows.extend(fixture_rows(f))
        rs, rc, sha = reference_outcome(f)
        erows.append(_canon([f.id, rs, str(rc), sha]))
    (ROOT / "simulator_fixtures.csv").write_bytes(("\r\n".join(frows) + "\r\n").encode("utf-8"))
    (ROOT / "expected_outcomes.csv").write_bytes(("\r\n".join(erows) + "\r\n").encode("utf-8"))
    print(f"wrote {len(fx.FIXTURES)} fixtures")
    for line in erows[1:6]:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
