#!/usr/bin/env python3
"""Fail-closed tests for the MSZZ integer market transports."""

from __future__ import annotations

import unittest

from screening_market_v2 import (
    MARKET_DATA_HEADER,
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
    point_size_1e8_from_decimal,
    points_from_price,
    verify_candidate_point_size,
    verify_instrument_params,
    verify_market_manifest,
    _canonical_record,
)

SYMBOL = "XAUUSD"
TIMEFRAME = 5
POINT_1E8 = 1_000_000  # 0.01


def bars() -> list[MarketBar]:
    # Integer point counts for ordinary decimal prices (point_size 0.01).
    return [
        MarketBar(1000, 10000, 10050, 9950, 10020, 20),
        MarketBar(1300, 10020, 10100, 10000, 10080, 20),
        MarketBar(1600, 10080, 10120, 10030, 10040, 30),
    ]


def market_bytes() -> bytes:
    return market_data_bytes(SYMBOL, TIMEFRAME, bars())


def base_rows() -> list[list[str]]:
    return [market_bar_fields(SYMBOL, TIMEFRAME, bar) for bar in bars()]


def with_row(rows: list[list[str]]) -> bytes:
    lines = [",".join(MARKET_DATA_HEADER)]
    lines.extend(_canonical_record(row) for row in rows)
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


class ProducerTests(unittest.TestCase):
    def test_price_to_points_exact(self) -> None:
        self.assertEqual(points_from_price(100.20, POINT_1E8), 10020)
        self.assertEqual(points_from_price(2000.37, POINT_1E8), 200037)
        self.assertEqual(point_size_1e8_from_decimal(0.01), 1_000_000)
        self.assertEqual(point_size_1e8_from_decimal(0.00001), 1000)

    def test_off_grid_price_rejected(self) -> None:
        with self.assertRaisesRegex(MarketTransportError, "PRICE_NOT_ON_POINT_GRID"):
            points_from_price(100.205, POINT_1E8)  # half a point off grid


class MarketDataTests(unittest.TestCase):
    def test_valid_round_trip(self) -> None:
        raw = market_bytes()
        market = parse_market_data(raw)
        self.assertEqual(market.symbol, SYMBOL)
        self.assertEqual(market.row_count, 3)
        self.assertEqual(market.bars[2].close_points, 10040)
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
            ("header", market_bytes().replace(b"spread_points", b"spread_pts", 1),
             "MARKET_HEADER_MISMATCH"),
        ]
        for name, data, reason in cases:
            with self.subTest(name=name):
                with self.assertRaisesRegex(MarketTransportError, reason):
                    parse_market_data(data)

    def test_noncanonical_integer_rejected(self) -> None:
        rows = base_rows()
        rows[0][6] = "010000"  # leading zero
        with self.assertRaisesRegex(MarketTransportError, "INVALID_INTEGER"):
            parse_market_data(with_row(rows))

    def test_float_in_integer_field_rejected(self) -> None:
        rows = base_rows()
        rows[0][6] = "10000.0"
        with self.assertRaisesRegex(MarketTransportError, "INVALID_INTEGER"):
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
        rows[0][7] = "9900"  # high < open
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
        tampered = MarketBar(1000, 10000, 10050, 9950, 10021, 20)
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
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 1_000_000, 1_000_000, 0, 0)
        params = parse_instrument_params(raw)
        self.assertEqual(params.point_size, 0.01)
        self.assertEqual(params.tick_size, 0.01)
        self.assertEqual(params.tick_ratio_points, 1)
        self.assertEqual(params.minimum_distance_points, 0)
        verify_instrument_params(params, SYMBOL, TIMEFRAME)

    def test_five_digit_forex_point(self) -> None:
        raw = instrument_params_bytes("EURUSD", TIMEFRAME, 1000, 1000, 0, 0)  # 0.00001
        params = parse_instrument_params(raw)
        self.assertEqual(params.point_size, 0.00001)

    def test_minimum_distance_derivation(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 1_000_000, 1_000_000, 30, 50)
        self.assertEqual(parse_instrument_params(raw).minimum_distance_points, 50)

    def test_minimum_mismatch_rejected(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 1_000_000, 1_000_000, 30, 50)
        raw = raw.replace(b'"30","50","50"', b'"30","50","30"')
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_MINIMUM_DISTANCE_MISMATCH"):
            parse_instrument_params(raw)

    def test_grid_incompatible_rejected(self) -> None:
        raw = instrument_params_bytes(SYMBOL, TIMEFRAME, 1_000_000, 1_500_000, 0, 0)
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_GRID_INCOMPATIBLE"):
            parse_instrument_params(raw)

    def test_point_size_cross_check(self) -> None:
        params = parse_instrument_params(
            instrument_params_bytes(SYMBOL, TIMEFRAME, 1_000_000, 1_000_000, 0, 0)
        )
        verify_candidate_point_size(params, 2.0, 200.0)  # 0.01 matches
        with self.assertRaisesRegex(MarketTransportError, "INSTRUMENT_POINT_SIZE_MISMATCH"):
            verify_candidate_point_size(params, 2.0, 100.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
