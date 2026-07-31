#!/usr/bin/env python3
"""Emit the committed shared market-transport fixtures and their hashes.

Prices are ordinary decimals; the integer transport stores them as exact point
counts, so there is no dependence on cross-language float formatting. The exact
values below are the frozen cross-language fixture and are mirrored verbatim in
Test_MSZZ_ScreeningMarketV2.mq5.
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
    point_size_1e8_from_decimal,
    points_from_price,
    sha256_hex,
)

ROOT = Path(__file__).resolve().parent
SYMBOL = "XAUUSD"
TIMEFRAME = 5

POINT_SIZE = 0.01
TICK_SIZE = 0.01
POINT_SIZE_1E8 = point_size_1e8_from_decimal(POINT_SIZE)      # 1_000_000
TICK_SIZE_1E8 = point_size_1e8_from_decimal(TICK_SIZE)        # 1_000_000
STOPS_LEVEL_POINTS = 0
FREEZE_LEVEL_POINTS = 0

# Ordinary decimal OHLC bid prices + integer spread points. Exactly representable
# as integer point counts (unlike the float transport, this needs no coincidence).
DECIMAL_BARS = [
    #  time, open,   high,   low,    close,  spread
    (1000, 100.00, 100.50, 99.50, 100.20, 20),
    (1300, 100.20, 101.00, 100.00, 100.80, 20),
    (1600, 100.80, 101.20, 100.30, 100.40, 30),
]


def _bar(row: tuple) -> MarketBar:
    t, o, h, low, c, spr = row
    p = lambda price: points_from_price(price, POINT_SIZE_1E8)
    return MarketBar(t, p(o), p(h), p(low), p(c), spr)


def _canonical(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return stream.getvalue()


def main() -> int:
    bars = [_bar(r) for r in DECIMAL_BARS]
    market = market_data_bytes(SYMBOL, TIMEFRAME, bars)
    (ROOT / "market_data_fixture.csv").write_bytes(market)
    parsed = parse_market_data(market)

    manifest = build_market_manifest(parsed)
    manifest_raw = market_manifest_bytes(manifest)
    (ROOT / "market_manifest_fixture.csv").write_bytes(manifest_raw)

    params_raw = instrument_params_bytes(
        SYMBOL, TIMEFRAME, POINT_SIZE_1E8, TICK_SIZE_1E8, STOPS_LEVEL_POINTS, FREEZE_LEVEL_POINTS
    )
    (ROOT / "instrument_params_fixture.csv").write_bytes(params_raw)
    params = parse_instrument_params(params_raw)

    rows = [
        ("artifact", "sha256", "detail"),
        ("market_data_fixture.csv", parsed.market_data_sha256, f"row_count={parsed.row_count}"),
        ("market_manifest_fixture.csv", sha256_hex(manifest_raw), f"symbol={manifest.symbol}"),
        ("instrument_params_fixture.csv", params.params_sha256,
         f"point_size={params.point_size}"),
    ]
    with (ROOT / "cross_language_market_hashes.csv").open("w", newline="") as handle:
        handle.write("\r\n".join(_canonical(list(row)) for row in rows) + "\r\n")

    for name, sha, detail in rows[1:]:
        print(f"{name}\t{sha}\t{detail}")
    # Show the integer encoding of the first bar for the MQL fixture mirror.
    b0 = bars[0]
    print(f"bar0 points: o={b0.open_points} h={b0.high_points} l={b0.low_points} "
          f"c={b0.close_points} spread={b0.spread_points}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
