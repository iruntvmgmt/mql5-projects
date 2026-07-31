#!/usr/bin/env python3
"""Emit the committed shared market-transport fixtures and their hashes.

The exact bars/params below are the frozen cross-language fixture and must be
mirrored verbatim in Test_MSZZ_ScreeningMarketV2.mq5. Both languages produce
byte-identical canonical documents; the recorded SHA-256 values prove it.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

from screening_market_v2 import (
    MarketBar,
    build_market_manifest,
    instrument_params_bytes,
    market_data_bytes,
    market_manifest_bytes,
    parse_instrument_params,
    parse_market_data,
    sha256_hex,
)

ROOT = Path(__file__).resolve().parent
SYMBOL = "XAUUSD"
TIMEFRAME = 5

# All OHLC values are exact multiples of 0.25 so they are exactly representable
# in binary double. At the frozen 16-fractional-digit precision this guarantees
# DoubleToString(v,16) (MQL5) and f"{v:.16f}" (Python) emit byte-identical
# strings; non-representable large-magnitude prices exceed double precision and
# can diverge between the two formatters. See the decimal-precision note in
# SCREENING_SIMULATOR_V2_IMPLEMENTATION.md.
BARS = [
    MarketBar(1000, 100.0, 100.5, 99.5, 100.25, 20),
    MarketBar(1300, 100.25, 101.0, 100.0, 100.75, 20),
    MarketBar(1600, 100.75, 101.25, 100.25, 100.5, 30),
]

POINT_SIZE = 0.01
TICK_SIZE = 0.01
STOPS_LEVEL_POINTS = 0
FREEZE_LEVEL_POINTS = 0


def _canonical(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return stream.getvalue()


def main() -> int:
    market = market_data_bytes(SYMBOL, TIMEFRAME, BARS)
    (ROOT / "market_data_fixture.csv").write_bytes(market)
    parsed = parse_market_data(market)

    manifest = build_market_manifest(parsed)
    manifest_raw = market_manifest_bytes(manifest)
    (ROOT / "market_manifest_fixture.csv").write_bytes(manifest_raw)

    params_raw = instrument_params_bytes(
        SYMBOL, TIMEFRAME, POINT_SIZE, TICK_SIZE, STOPS_LEVEL_POINTS, FREEZE_LEVEL_POINTS
    )
    (ROOT / "instrument_params_fixture.csv").write_bytes(params_raw)
    params = parse_instrument_params(params_raw)

    rows = [
        ("artifact", "sha256", "detail"),
        ("market_data_fixture.csv", parsed.market_data_sha256, f"row_count={parsed.row_count}"),
        ("market_manifest_fixture.csv", sha256_hex(manifest_raw), f"symbol={manifest.symbol}"),
        ("instrument_params_fixture.csv", params.params_sha256,
         f"min_distance_points={params.minimum_distance_points}"),
    ]
    with (ROOT / "cross_language_market_hashes.csv").open("w", newline="") as handle:
        handle.write("\r\n".join(_canonical(list(row)) for row in rows) + "\r\n")

    for name, sha, detail in rows[1:]:
        print(f"{name}\t{sha}\t{detail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
