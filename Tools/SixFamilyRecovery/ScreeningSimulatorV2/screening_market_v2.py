#!/usr/bin/env python3
"""Strict canonical INTEGER transports for the MSZZ screening simulator.

Real-data-safe: OHLC are stored as signed integer point counts and instrument
sizes as integer 1e-8 units, so ordinary decimal instrument prices
(100.20, 2000.37, 1.23456, ...) are represented exactly. Nothing in the
canonical transport or the SHA-256 depends on cross-language float formatting.
Prices are reconstructed only at simulation time as ``points * point_size``,
where ``point_size = point_size_1e8 / 1e8`` (1e8 is binary-exact, so MQL5 and
Python compute the identical double).

Family-neutral; does not modify a family generator, production path, or the
certified candidate JournalTransportV2.

Byte conventions match the certified research transport: UTF-8 no BOM, CRLF
after every record including the final one, an unquoted header line, fully
double-quoted canonical data records, integers matching ``-?(0|[1-9][0-9]*)``.
Every accepted record must reserialize byte-for-byte. Nothing is repaired,
inferred, forward-filled, or normalized from an alternate spelling.
"""

from __future__ import annotations

import hashlib
import io
import csv
import re
from dataclasses import dataclass
from pathlib import Path

MARKET_DATA_VERSION = "MSZZ_SCREENING_MARKET_DATA_V2"
MARKET_MANIFEST_VERSION = "MSZZ_SCREENING_MARKET_MANIFEST_V2"
INSTRUMENT_PARAMS_VERSION = "MSZZ_SCREENING_INSTRUMENT_PARAMS_V2"

CLOCK_DOMAIN = "BROKER_SERVER_RAW"
TIME_AUTHORITY = "MSZZ_TIME_RAW_BROKER_V1"

# Fixed integer scale for instrument sizes. MT5 SYMBOL_DIGITS <= 8, so every
# real point/tick size is an exact multiple of 1e-8. 1e8 < 2^53 is binary-exact.
PRICE_SCALE_1E8 = 100_000_000

MARKET_DATA_HEADER = [
    "market_data_version",
    "symbol",
    "timeframe",
    "clock_domain",
    "time_authority_id",
    "time_raw",
    "open_points",
    "high_points",
    "low_points",
    "close_points",
    "spread_points",
]

MARKET_MANIFEST_HEADER = [
    "manifest_version",
    "market_data_version",
    "symbol",
    "timeframe",
    "clock_domain",
    "time_authority_id",
    "row_count",
    "market_data_sha256",
]

INSTRUMENT_PARAMS_HEADER = [
    "params_version",
    "symbol",
    "timeframe",
    "point_size_1e8",
    "tick_size_1e8",
    "stops_level_points",
    "freeze_level_points",
    "minimum_distance_points",
]


class MarketTransportError(ValueError):
    """Raised on any fail-closed market-transport violation."""


# --------------------------------------------------------------------------
# Shared byte / canonical primitives
# --------------------------------------------------------------------------
def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_sha256(value: str) -> bool:
    return len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _decode_utf8(data: bytes) -> str:
    if data.startswith(b"\xef\xbb\xbf"):
        raise MarketTransportError("UTF8_BOM_FORBIDDEN")
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise MarketTransportError("INVALID_UTF8") from exc


def _canonical_record(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    writer = csv.writer(
        stream,
        delimiter=",",
        quotechar='"',
        quoting=csv.QUOTE_ALL,
        lineterminator="",
        doublequote=True,
    )
    writer.writerow(fields)
    return stream.getvalue()


def _integer_exact(value: str) -> int:
    if not re.fullmatch(r"-?(0|[1-9][0-9]*)", value):
        raise MarketTransportError("INVALID_INTEGER")
    return int(value)


def _text_record_at(text: str, index: int) -> str:
    quoted = False
    start = 0
    current = 0
    i = 0
    while i < len(text):
        char = text[i]
        if char == '"':
            if quoted and i + 1 < len(text) and text[i + 1] == '"':
                i += 2
                continue
            quoted = not quoted
        elif char == "\r" and not quoted:
            if i + 1 >= len(text) or text[i + 1] != "\n":
                raise MarketTransportError("BARE_CR")
            if current == index:
                return text[start:i]
            current += 1
            i += 1
            start = i + 1
        elif char == "\n" and not quoted:
            raise MarketTransportError("BARE_LF")
        i += 1
    raise MarketTransportError("RECORD_INDEX_MISSING")


def _records(text: str) -> list[list[str]]:
    if not text:
        raise MarketTransportError("EMPTY_DOCUMENT")
    if not text.endswith("\r\n"):
        raise MarketTransportError("MISSING_FINAL_CRLF")
    stream = io.StringIO(text, newline="")
    try:
        rows = list(csv.reader(stream, delimiter=",", quotechar='"', strict=True))
    except csv.Error as exc:
        raise MarketTransportError("MALFORMED_RFC4180") from exc
    if not rows or any(not row for row in rows):
        raise MarketTransportError("EMPTY_RECORD")
    return rows


def _require_quoted_canonical(text: str, row: list[str], record_index: int) -> None:
    raw_record = _text_record_at(text, record_index)
    if not re.fullmatch(r'"(?:[^"]|"")*"(?:,"(?:[^"]|"")*")*', raw_record, re.S):
        raise MarketTransportError("UNQUOTED_FIELD")
    if _canonical_record(row) != raw_record:
        raise MarketTransportError("NONCANONICAL_RECORD")


# --------------------------------------------------------------------------
# Market data (MSZZ_SCREENING_MARKET_DATA_V2) — integer point counts
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class MarketBar:
    time_raw: int
    open_points: int
    high_points: int
    low_points: int
    close_points: int
    spread_points: int


@dataclass(frozen=True)
class MarketData:
    symbol: str
    timeframe: int
    market_data_sha256: str
    bars: tuple[MarketBar, ...]

    @property
    def row_count(self) -> int:
        return len(self.bars)


def market_bar_fields(symbol: str, timeframe: int, bar: MarketBar) -> list[str]:
    return [
        MARKET_DATA_VERSION,
        symbol,
        str(timeframe),
        CLOCK_DOMAIN,
        TIME_AUTHORITY,
        str(bar.time_raw),
        str(bar.open_points),
        str(bar.high_points),
        str(bar.low_points),
        str(bar.close_points),
        str(bar.spread_points),
    ]


def market_data_bytes(symbol: str, timeframe: int, bars: list[MarketBar]) -> bytes:
    lines = [",".join(MARKET_DATA_HEADER)]
    lines.extend(_canonical_record(market_bar_fields(symbol, timeframe, bar)) for bar in bars)
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def parse_market_data(data: bytes) -> MarketData:
    text = _decode_utf8(data)
    rows = _records(text)
    if rows[0] != MARKET_DATA_HEADER:
        raise MarketTransportError("MARKET_HEADER_MISMATCH")

    symbol: str | None = None
    timeframe: int | None = None
    previous_time: int | None = None
    bars: list[MarketBar] = []
    for record_index, row in enumerate(rows[1:], start=1):
        if len(row) != len(MARKET_DATA_HEADER):
            raise MarketTransportError("MARKET_COLUMN_COUNT_MISMATCH")
        _require_quoted_canonical(text, row, record_index)
        if row[0] != MARKET_DATA_VERSION:
            raise MarketTransportError("UNSUPPORTED_MARKET_DATA_VERSION")
        if not row[1]:
            raise MarketTransportError("MISSING_MARKET_SYMBOL")
        tf = _integer_exact(row[2])
        if row[3] != CLOCK_DOMAIN or row[4] != TIME_AUTHORITY:
            raise MarketTransportError("UNSUPPORTED_MARKET_TIME_AUTHORITY")
        if symbol is None:
            symbol = row[1]
            timeframe = tf
        elif row[1] != symbol or tf != timeframe:
            raise MarketTransportError("INCONSISTENT_MARKET_MARKET")

        time_raw = _integer_exact(row[5])
        open_points = _integer_exact(row[6])
        high_points = _integer_exact(row[7])
        low_points = _integer_exact(row[8])
        close_points = _integer_exact(row[9])
        spread_points = _integer_exact(row[10])

        if time_raw <= 0:
            raise MarketTransportError("INVALID_MARKET_BAR")
        if previous_time is not None:
            if time_raw == previous_time:
                raise MarketTransportError("DUPLICATE_MARKET_TIME")
            if time_raw < previous_time:
                raise MarketTransportError("NON_MONOTONIC_MARKET_TIME")
        if not (open_points > 0 and high_points > 0 and low_points > 0 and close_points > 0):
            raise MarketTransportError("INVALID_MARKET_BAR")
        if high_points < max(open_points, close_points) or low_points > min(open_points, close_points):
            raise MarketTransportError("INVALID_MARKET_BAR")
        if high_points < low_points:
            raise MarketTransportError("INVALID_MARKET_BAR")
        if spread_points < 0:
            raise MarketTransportError("INVALID_SPREAD")

        bars.append(
            MarketBar(time_raw, open_points, high_points, low_points, close_points, spread_points)
        )
        previous_time = time_raw

    if symbol is None or timeframe is None or not bars:
        raise MarketTransportError("EMPTY_MARKET_DATA")

    return MarketData(symbol, timeframe, sha256_hex(data), tuple(bars))


# --------------------------------------------------------------------------
# Market manifest (MSZZ_SCREENING_MARKET_MANIFEST_V2)
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class MarketManifest:
    manifest_version: str
    market_data_version: str
    symbol: str
    timeframe: int
    clock_domain: str
    time_authority_id: str
    row_count: int
    market_data_sha256: str


def build_market_manifest(market: MarketData) -> MarketManifest:
    return MarketManifest(
        manifest_version=MARKET_MANIFEST_VERSION,
        market_data_version=MARKET_DATA_VERSION,
        symbol=market.symbol,
        timeframe=market.timeframe,
        clock_domain=CLOCK_DOMAIN,
        time_authority_id=TIME_AUTHORITY,
        row_count=market.row_count,
        market_data_sha256=market.market_data_sha256,
    )


def market_manifest_bytes(manifest: MarketManifest) -> bytes:
    fields = [
        manifest.manifest_version,
        manifest.market_data_version,
        manifest.symbol,
        str(manifest.timeframe),
        manifest.clock_domain,
        manifest.time_authority_id,
        str(manifest.row_count),
        manifest.market_data_sha256,
    ]
    return (
        ",".join(MARKET_MANIFEST_HEADER) + "\r\n" + _canonical_record(fields) + "\r\n"
    ).encode("utf-8")


def parse_market_manifest(data: bytes) -> MarketManifest:
    text = _decode_utf8(data)
    rows = _records(text)
    if len(rows) != 2 or rows[0] != MARKET_MANIFEST_HEADER:
        raise MarketTransportError("MARKET_MANIFEST_SHAPE_MISMATCH")
    _require_quoted_canonical(text, rows[1], 1)
    values = rows[1]
    if len(values) != len(MARKET_MANIFEST_HEADER):
        raise MarketTransportError("MARKET_MANIFEST_SHAPE_MISMATCH")
    timeframe = _integer_exact(values[3])
    row_count = _integer_exact(values[6])
    if (
        values[0] != MARKET_MANIFEST_VERSION
        or values[1] != MARKET_DATA_VERSION
        or not values[2]
        or values[4] != CLOCK_DOMAIN
        or values[5] != TIME_AUTHORITY
        or row_count < 0
        or not is_sha256(values[7])
    ):
        raise MarketTransportError("INVALID_MARKET_MANIFEST_FIELD")
    return MarketManifest(
        values[0], values[1], values[2], timeframe, values[4], values[5], row_count, values[7]
    )


def verify_market_manifest(manifest: MarketManifest, market: MarketData) -> None:
    if (
        manifest.manifest_version != MARKET_MANIFEST_VERSION
        or manifest.market_data_version != MARKET_DATA_VERSION
    ):
        raise MarketTransportError("MARKET_MANIFEST_VERSION_MISMATCH")
    if manifest.symbol != market.symbol or manifest.timeframe != market.timeframe:
        raise MarketTransportError("MARKET_MANIFEST_MARKET_MISMATCH")
    if manifest.row_count != market.row_count:
        raise MarketTransportError("MARKET_MANIFEST_ROW_COUNT_MISMATCH")
    if manifest.market_data_sha256 != market.market_data_sha256:
        raise MarketTransportError("MARKET_HASH_MISMATCH")


# --------------------------------------------------------------------------
# Instrument params (MSZZ_SCREENING_INSTRUMENT_PARAMS_V2) — integer 1e-8 units
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class InstrumentParams:
    params_version: str
    symbol: str
    timeframe: int
    point_size_1e8: int
    tick_size_1e8: int
    stops_level_points: int
    freeze_level_points: int
    minimum_distance_points: int
    params_sha256: str

    @property
    def point_size(self) -> float:
        return self.point_size_1e8 / PRICE_SCALE_1E8

    @property
    def tick_size(self) -> float:
        return self.tick_size_1e8 / PRICE_SCALE_1E8

    @property
    def tick_ratio_points(self) -> int:
        return self.tick_size_1e8 // self.point_size_1e8

    @property
    def minimum_distance_price(self) -> float:
        return self.minimum_distance_points * self.point_size

    def price(self, points: int) -> float:
        """Reconstruct an actual price from an integer point count."""
        return points * self.point_size


def instrument_params_bytes(
    symbol: str,
    timeframe: int,
    point_size_1e8: int,
    tick_size_1e8: int,
    stops_level_points: int,
    freeze_level_points: int,
) -> bytes:
    minimum = max(stops_level_points, freeze_level_points)
    fields = [
        INSTRUMENT_PARAMS_VERSION,
        symbol,
        str(timeframe),
        str(point_size_1e8),
        str(tick_size_1e8),
        str(stops_level_points),
        str(freeze_level_points),
        str(minimum),
    ]
    return (
        ",".join(INSTRUMENT_PARAMS_HEADER) + "\r\n" + _canonical_record(fields) + "\r\n"
    ).encode("utf-8")


def parse_instrument_params(data: bytes) -> InstrumentParams:
    text = _decode_utf8(data)
    rows = _records(text)
    if len(rows) != 2 or rows[0] != INSTRUMENT_PARAMS_HEADER:
        raise MarketTransportError("INSTRUMENT_PARAMS_SHAPE_MISMATCH")
    _require_quoted_canonical(text, rows[1], 1)
    values = rows[1]
    if len(values) != len(INSTRUMENT_PARAMS_HEADER):
        raise MarketTransportError("INSTRUMENT_PARAMS_SHAPE_MISMATCH")
    timeframe = _integer_exact(values[2])
    point_size_1e8 = _integer_exact(values[3])
    tick_size_1e8 = _integer_exact(values[4])
    stops = _integer_exact(values[5])
    freeze = _integer_exact(values[6])
    minimum = _integer_exact(values[7])
    if values[0] != INSTRUMENT_PARAMS_VERSION or not values[1]:
        raise MarketTransportError("INVALID_INSTRUMENT_PARAMS_FIELD")
    if point_size_1e8 <= 0 or tick_size_1e8 <= 0:
        raise MarketTransportError("INVALID_INSTRUMENT_PARAMS_FIELD")
    if stops < 0 or freeze < 0 or minimum < 0:
        raise MarketTransportError("INVALID_INSTRUMENT_PARAMS_FIELD")
    if minimum != max(stops, freeze):
        raise MarketTransportError("INSTRUMENT_MINIMUM_DISTANCE_MISMATCH")
    if tick_size_1e8 % point_size_1e8 != 0:
        raise MarketTransportError("INSTRUMENT_GRID_INCOMPATIBLE")
    return InstrumentParams(
        values[0], values[1], timeframe, point_size_1e8, tick_size_1e8, stops, freeze, minimum,
        sha256_hex(data),
    )


def verify_instrument_params(params: InstrumentParams, symbol: str, timeframe: int) -> None:
    if params.symbol != symbol or params.timeframe != timeframe:
        raise MarketTransportError("INSTRUMENT_PARAMS_MARKET_MISMATCH")


def verify_candidate_point_size(
    params: InstrumentParams, risk_price: float, stop_distance_points: float
) -> None:
    """Cross-check the frozen point_size against candidate-derived geometry."""
    if stop_distance_points <= 0 or risk_price <= 0:
        raise MarketTransportError("INSTRUMENT_POINT_SIZE_UNVERIFIABLE")
    derived = risk_price / stop_distance_points
    if abs(derived - params.point_size) > max(1.0e-12, params.point_size * 1.0e-6):
        raise MarketTransportError("INSTRUMENT_POINT_SIZE_MISMATCH")


# --------------------------------------------------------------------------
# Producer helpers (decimal price -> integer points, grid-checked)
# --------------------------------------------------------------------------
def point_size_1e8_from_decimal(point_size: float) -> int:
    """Convert a decimal point size to exact integer 1e-8 units (grid-checked)."""
    scaled = round(point_size * PRICE_SCALE_1E8)
    if scaled <= 0 or abs(scaled - point_size * PRICE_SCALE_1E8) > 1.0e-3:
        raise MarketTransportError("POINT_SIZE_NOT_ON_1E8_GRID")
    return int(scaled)


def points_from_price(price: float, point_size_1e8: int) -> int:
    """Convert a decimal price to an exact integer point count, or reject off-grid.

    points = price / point_size, computed as (price * 1e8) / point_size_1e8 so the
    only division is by an integer; the result must be an exact integer.
    """
    scaled = price * PRICE_SCALE_1E8
    ratio = scaled / point_size_1e8
    nearest = round(ratio)
    if abs(ratio - nearest) > 1.0e-6:
        raise MarketTransportError("PRICE_NOT_ON_POINT_GRID")
    return int(nearest)


def read_bytes(path: Path) -> bytes:
    return Path(path).read_bytes()
