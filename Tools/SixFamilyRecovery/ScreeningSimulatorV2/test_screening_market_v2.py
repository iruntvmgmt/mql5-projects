#!/usr/bin/env python3
"""Fail-closed tests for the MSZZ screening-simulator market transports."""

from __future__ import annotations

import unittest

from screening_market_v2 import (
    CLOCK_DOMAIN,
    MARKET_DATA_HEADER,
    MARKET_DATA_VERSION,
    TIME_AUTHORITY,
    InstrumentParams,
    MarketBar,
    MarketTransportError,
    build_market_manifest,
    instrument_params_bytes,
    market_bar_fields,
    market_data_bytes,
    market_manifest_bytes,
    parse_instrument_params,
    parse_market_data,
    parse_market_manifest,
    verify_candidate_point_size,
    verify_instrument_params,
    verify_market_manifest,
    _canonical_record,
)

SYMBOL = "XAUUSD"
TIMEFRAME = 5


def bars() -> list[MarketBar]:
    # Exactly-representable (multiples of 0.25) so MQL5/Python 16-digit strings agree.
    return [
        MarketBar(1000, 100.0, 100.5, 99.5, 100.25, 20),
        MarketBar(1300, 100.25, 101.0, 100.0, 100.75, 20),
        MarketBar(1600, 100.75, 101.25, 100.25, 100.5, 30),
    ]


def market_bytes() -> bytes:
    return market_data_bytes(SYMBOL, TIMEFRAME, bars())


def with_row(rows: list[list[str]]) -> bytes:
    lines = [",".join(MARKET_DATA_HEADER)]
    lines.extend(_canonical_record(row) for row in rows)
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def base_rows() -> list[list[str]]:
    data = bars()
    return [market_bar_fields(SYMBOL, TIMEFRAME, bar) for bar in data]


class MarketDataTests(unittest.TestCase):
    def test_valid_round_trip(self) -> None:
        raw = market_bytes()
        market = parse_market_data(raw)
        self.assertEqual(market.symbol, SYMBOL)
        self.assertEqual(market.timeframe, TIMEFRAME)
        self.assertEqual(market.row_count, 3)
        self.assertEqual(len(market.market_data_sha256), 64)
        # Reserialize byte-for-byte.
        self.assertEqual(market_data_bytes(SYMBOL, TIMEFRAME, list(market.bars)), raw)

    def test_fail_closed_matrix(self) -> None:
        cases: list[tuple[str, bytes, str]] = [
            ("bom", b"\xef\xbb\xbf" + market_bytes(), "UTF8_BOM_FORBIDDEN"),
            ("no_final_crlf", market_bytes()[:-2], "MISSING_FINAL_CRLF"),
            ("bare_lf", market_bytes().replace(b"\r\n", b"\n", 1), "BARE_LF"),
            (
                "unquoted",
                market_bytes().replace(b'"MSZZ_SCREENING_MARKET_DATA_V2"',
                                       b"MSZZ_SCREENING_MARKET_DATA_V2", 1),
                "UNQUOTED_FIELD",
            ),
            (
                "header",
                market_bytes().replace(b"spread_points", b"spread_pts", 1),
                "MARKET_HEADER_MISMATCH",
            ),
        ]
        for name, data, reason in cases:
            with self.subTest(name=name):
                with self.assertRaisesRegex(MarketTransportError, reason):
                    parse_market_data(data)

    def test_noncanonical_decimal_rejected(self) -> None:
        rows = base_rows()
        rows[0][6] = "100.0"  # not 16 fractional digits
        with self.assertRaisesRegex(MarketTransportError, "INVALID_NUMBER"):
            parse_market_data(with_row(rows))

    def test_duplicate_time_rejected(self) -> None:
        rows = base_rows()
        rows[1][5] = rows[0][5]
        with self.assertRaisesRegex(MarketTransportError, "DUPLICATE_MARKET_TIME"):
            parse_market_data(with_row(rows))

    def test_non_monotonic_time_rejected(self) -> None:
        rows = base_rows()
        rows[2][5] = "500"
        with self.assertRaisesRegex(MarketTransportError, "NON_MONOTONIC_MARKET_TIME"):
            parse_market_data(with_row(rows))

    def test_bad_ohlc_rejected(self) -> None:
        rows = base_rows()
        rows[0][7] = "99.0000000000000000"  # high < open
        with self.assertRaisesRegex(MarketTransportError, "INVALID_MARKET_BAR"):
            parse_market_data(with_row(rows))

    def test_negative_spread_rejected(self) -> None:
        rows = base_rows()
        rows[0][10] = "-1"
        with self.assertRaisesRegex(MarketTransportError, "INVALID_SPREAD"):
            parse_market_data(with_row(rows))

    def test_wrong_version_rejected(self) -> None:
        rows = base_rows()
        rows[0][0] = "OTHER"
        with self.assertRaisesRegex(MarketTransportError, "UNSUPPORTED_MARKET_DATA_VERSION"):
            parse_market_data(with_row(rows))

    def test_inconsistent_symbol_rejected(self) -> None:
        rows = base_rows()
        rows[1][1] = "EURUSD"
        with self.assertRaisesRegex(MarketTransportError, "INCONSISTENT_MARKET_MARKET"):
            parse_market_data(with_row(rows))

    def test_bad_clock_authority_rejected(self) -> None:
        rows = base_rows()
        rows[0][3] = "UTC_CONVERTED"
        with self.assertRaisesRegex(MarketTransportError, "UNSUPPORTED_MARKET_TIME_AUTHORITY"):
            parse_market_data(with_row(rows))


class MarketManifestTests(unittest.TestCase):
    def test_round_trip_and_verify(self) -> None:
        market = parse_market_data(market_bytes())
        manifest = build_market_manifest(market)
        parsed = parse_market_manifest(market_manifest_bytes(manifest))
        self.assertEqual(parsed, manifest)
        verify_market_manifest(parsed, market)

    def test_hash_mismatch_rejected(self) -> None:
        market = parse_market_data(market_bytes())
        manifest = build_market_manifest(market)
        tampered = MarketBar(1000, 100.0, 100.5, 99.5, 100.375, 20)
        other = parse_market_data(market_data_bytes(SYMBOL, TIMEFRAME, [tampered] + bars()[1:]))
        with self.assertRaisesRegex(MarketTransportError, "MARKET_HASH_MISMATCH"):
            verify_market_manifest(manifest, other)

    def test_market_mismatch_rejected(self) -> None:
        market = parse_market_data(market_bytes())
        manifest = build_market_manifest(market)
        other = parse_market_data(market_data_bytes("EURUSD", TIMEFRAME, bars()))
        with self.assertRaisesRegex(MarketTransportError, "MARKET_MANIFEST_MARKET_MISMATCH"):
            verify_market_manifest(manifest, other)


class InstrumentParamsTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 0.01, 0.01, 0, 0)
        params = parse_instrument_params(raw)
        self.assertEqual(params.point_size, 0.01)
        self.assertEqual(params.minimum_distance_points, 0)
        self.assertEqual(params.minimum_distance_price, 0.0)
        verify_instrument_params(params, SYMBOL, TIMEFRAME)

    def test_minimum_distance_derivation(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 0.01, 0.01, 30, 50)
        params = parse_instrument_params(raw)
        self.assertEqual(params.minimum_distance_points, 50)

    def test_minimum_mismatch_rejected(self) -> None:
        raw = bytearray(instrument_params_bytes(SYMBOL, TIMEFRAME, 0.01, 0.01, 30, 50))
        raw = bytes(raw).replace(b'"50","50"', b'"50","30"')  # tamper minimum
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_MINIMUM_DISTANCE_MISMATCH"):
            parse_instrument_params(raw)

    def test_grid_incompatible_rejected(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 0.01, 0.015, 0, 0)
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_GRID_INCOMPATIBLE"):
            parse_instrument_params(raw)

    def test_point_size_cross_check(self) -> None:
        params = parse_instrument_params(instrument_params_bytes(SYMBOL, TIMEFRAME, 0.01, 0.01, 0, 0))
        # risk 2.0 over 200 points => 0.01, matches.
        verify_candidate_point_size(params, 2.0, 200.0)
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_POINT_SIZE_MISMATCH"):
            verify_candidate_point_size(params, 2.0, 100.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
