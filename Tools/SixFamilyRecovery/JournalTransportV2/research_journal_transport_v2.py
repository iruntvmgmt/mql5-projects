#!/usr/bin/env python3
"""Strict transport validation for MSZZ ResearchCandidateSchemaV2 journals."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
from dataclasses import asdict, dataclass
from pathlib import Path

SCHEMA_VERSION = "MSZZ_RESEARCH_CANDIDATE_V2"
WRITER_VERSION = "MSZZ_RESEARCH_CSV_WRITER_V2"
MANIFEST_VERSION = "MSZZ_RESEARCH_MANIFEST_V2"
TRANSPORT_VERSION = "MSZZ_RESEARCH_JOURNAL_TRANSPORT_V2"
MANIFEST_HEADER = [
    "manifest_version",
    "writer_version",
    "schema_version",
    "symbol",
    "timeframe",
    "row_count",
    "journal_sha256",
    "source_data_sha256",
]


class TransportError(ValueError):
    pass


@dataclass(frozen=True)
class Manifest:
    manifest_version: str
    writer_version: str
    schema_version: str
    symbol: str
    timeframe: int
    row_count: int
    journal_sha256: str
    source_data_sha256: str


@dataclass(frozen=True)
class VerifiedJournalRowsV2:
    """Immutable, already-validated journal rows produced by the certified
    validator. Additive read-only accessor for downstream consumers (e.g. the
    screening journal-binding adapter). Carries the transport-returned journal
    SHA (never a caller-supplied value) so callers cannot smuggle an alternate
    hash. This type is a projection of the certified validation output only; it
    does not change any parsing, canonicalization, or manifest rule."""

    transport_version: str
    schema_version: str
    journal_sha256: str
    row_count: int
    rows: tuple[tuple[str, ...], ...]  # data rows only, header excluded
    event_ids: tuple[str, ...]  # journal row order (column 7)
    sequence_ids: tuple[str, ...]  # journal row order (column 6)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(c in "0123456789abcdefABCDEF" for c in value)


def _decode_utf8(data: bytes) -> str:
    if data.startswith(b"\xef\xbb\xbf"):
        raise TransportError("UTF8_BOM_FORBIDDEN")
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        if "unexpected end of data" in exc.reason:
            raise TransportError("TRUNCATED_UTF8") from exc
        if "continuation" in exc.reason:
            raise TransportError("INVALID_UTF8_CONTINUATION") from exc
        raise TransportError("INVALID_UTF8") from exc


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
        raise TransportError("INVALID_INTEGER")
    return int(value)


def _double_exact(value: str) -> float:
    if not re.fullmatch(r"-?(0|[1-9][0-9]*)\.[0-9]{16}", value):
        raise TransportError("INVALID_NUMBER")
    parsed = float(value)
    if not math.isfinite(parsed) or f"{parsed:.16f}" != value:
        raise TransportError("INVALID_NUMBER")
    return parsed


def _validate_common(row: list[str], row_number: int) -> None:
    try:
        strategy = _integer_exact(row[1])
        family = _integer_exact(row[2])
        signal = _integer_exact(row[10])
        expiry = _integer_exact(row[11])
        arm = _integer_exact(row[20])
        trigger = _integer_exact(row[21])
        bars = _integer_exact(row[22])
        spread = _integer_exact(row[29])
        entry = _double_exact(row[13])
        stop = _double_exact(row[14])
        target = _double_exact(row[15])
        _double_exact(row[16])
        atr_arm = _double_exact(row[25])
        atr_trigger = _double_exact(row[26])
        stop_points = _double_exact(row[27])
        target_r = _double_exact(row[28])
        spread_ratio = _double_exact(row[30])
    except TransportError as exc:
        raise TransportError(f"{exc}:{row_number}") from exc
    if strategy <= 0 or family not in range(8, 14):
        raise TransportError(f"INVALID_ID_ALLOCATION:{row_number}")
    if not row[3] or not row[4]:
        raise TransportError(f"MISSING_HYPOTHESIS_IDENTITY:{row_number}")
    if row[8:10] != ["BROKER_SERVER_RAW", "MSZZ_TIME_RAW_BROKER_V1"]:
        raise TransportError(f"UNSUPPORTED_TIME_AUTHORITY:{row_number}")
    if signal <= 0 or signal != trigger or arm <= 0 or arm > trigger or expiry <= signal:
        raise TransportError(f"INVALID_LIFECYCLE_TIME:{row_number}")
    if row[12] not in {"LONG", "SHORT"}:
        raise TransportError(f"INVALID_DIRECTION:{row_number}")
    if entry <= 0 or stop <= 0 or target <= 0:
        raise TransportError(f"INVALID_GEOMETRY:{row_number}")
    if (row[12] == "LONG" and (stop >= entry or target <= entry)) or (
        row[12] == "SHORT" and (stop <= entry or target >= entry)
    ):
        raise TransportError(f"INVALID_DIRECTIONAL_GEOMETRY:{row_number}")
    if row[17] not in {
        "NONE",
        "SESSION_RANGE",
        "STRUCTURAL_EVENT",
        "COMPRESSION_WINDOW",
        "VALUE",
        "RANGE",
    }:
        raise TransportError(f"INVALID_REFERENCE_TYPE:{row_number}")
    if row[17] != "NONE" and not row[18]:
        raise TransportError(f"INVALID_REFERENCE:{row_number}")
    if bars < 0 or row[23] not in {
        "NONE",
        "EXPIRED",
        "INVALIDATED",
        "EMITTED",
        "SESSION_RESET",
        "DAY_RESET",
    } or row[24] not in {
        "NONE",
        "FRESH_CROSS",
        "NEUTRAL",
        "SESSION",
        "DAY",
        "NEW_STRUCTURE",
        "NEW_EPISODE",
    }:
        raise TransportError(f"INVALID_STATE_FIELD:{row_number}")
    if (
        atr_arm <= 0
        or atr_trigger <= 0
        or stop_points <= 0
        or target_r <= 0
        or spread < 0
        or spread_ratio < 0
    ):
        raise TransportError(f"INVALID_DERIVED_FIELD:{row_number}")
    if not row[31] or not row[32]:
        raise TransportError(f"MISSING_CONTEXT_ID:{row_number}")


def _validate_extensions(row: list[str], row_number: int) -> None:
    family = int(row[2])
    structural = family in {9, 10, 12}
    if structural == all(value == "" for value in row[34:74]):
        raise TransportError(f"STRUCTURAL_PARTITION_MISMATCH:{row_number}")
    ranges = [(74, 80), (80, 87), (87, 94), (94, 102), (102, 108), (108, 116)]
    for expected_family, (first, last) in enumerate(ranges, start=8):
        if family != expected_family and any(row[first:last]):
            raise TransportError(f"UNEXPECTED_FAMILY_EXTENSION:{row_number}")

    try:
        if family == 8:
            values = [_double_exact(row[index]) for index in range(76, 80)]
            if not row[74] or not row[75] or values[0] <= values[1] or min(values[2:]) <= 0:
                raise TransportError("INVALID_SSR_EXTENSION")
        elif family == 9:
            values = [_double_exact(row[index]) for index in (81, 82, 83, 84, 86)]
            pause = _integer_exact(row[85])
            if (
                not row[80]
                or min(values[:3]) <= 0
                or not 0 <= values[3] <= 1
                or pause < 0
                or not 0 <= values[4] <= 1
            ):
                raise TransportError("INVALID_MC_EXTENSION")
        elif family == 10:
            price = _double_exact(row[89])
            first_touch = _integer_exact(row[90])
            rejection = _integer_exact(row[91])
            penetration = _double_exact(row[92])
            tests = _integer_exact(row[93])
            if (
                not row[87]
                or not row[88]
                or price <= 0
                or first_touch <= int(row[20])
                or rejection < first_touch
                or penetration < 0
                or tests < 0
            ):
                raise TransportError("INVALID_BRC_EXTENSION")
        elif family == 11:
            start = _integer_exact(row[94])
            end = _integer_exact(row[95])
            values = [_double_exact(row[index]) for index in range(97, 102)]
            if (
                start <= 0
                or end <= start
                or end >= int(row[21])
                or not row[96]
                or min(values[:3]) <= 0
                or min(values[3:]) < 0
            ):
                raise TransportError("INVALID_CBR_EXTENSION")
        elif family == 12:
            values = [_double_exact(row[index]) for index in range(105, 108)]
            if (
                not row[102]
                or row[103] not in {"VWAP_SESSION", "ALMA"}
                or not row[104]
                or min(values) < 0
            ):
                raise TransportError("INVALID_TP_EXTENSION")
        elif family == 13:
            width = _double_exact(row[109])
            separation = _integer_exact(row[112])
            rotation = _double_exact(row[113])
            midpoint = _double_exact(row[115])
            if (
                not row[108]
                or width < 0
                or not row[110]
                or not row[111]
                or separation < 0
                or rotation < 0
                or row[114] != "true"
                or midpoint <= 0
            ):
                raise TransportError("INVALID_RR_EXTENSION")
    except TransportError as exc:
        raise TransportError(f"{exc}:{row_number}") from exc


def _records(text: str) -> list[list[str]]:
    if not text:
        raise TransportError("EMPTY_DOCUMENT")
    if not text.endswith("\r\n"):
        raise TransportError("MISSING_FINAL_CRLF")
    stream = io.StringIO(text, newline="")
    try:
        rows = list(csv.reader(stream, delimiter=",", quotechar='"', strict=True))
    except csv.Error as exc:
        raise TransportError("MALFORMED_RFC4180") from exc
    if not rows or any(not row for row in rows):
        raise TransportError("EMPTY_RECORD")
    return rows


def read_header(header_path: Path) -> list[str]:
    raw = header_path.read_bytes()
    text = _decode_utf8(raw)
    if "\r" in text or "\n" in text:
        text = text.rstrip("\r\n")
        if "\r" in text or "\n" in text:
            raise TransportError("HEADER_MULTILINE")
    header = next(csv.reader([text], strict=True))
    if not header or len(set(header)) != len(header):
        raise TransportError("INVALID_HEADER")
    return header


def _validated_parse(data: bytes, expected_header: list[str]) -> dict[str, object]:
    """Single certified validation + parse pass. Internal: shared by both
    public entry points so there is exactly one parser/validation
    implementation and no divergent second parse. Returns the certified fields
    plus the immutable validated rows; callers expose only what their contract
    permits."""
    text = _decode_utf8(data)
    rows = _records(text)
    if rows[0] != expected_header:
        raise TransportError("HEADER_MISMATCH")

    event_ids: set[str] = set()
    sequence_ids: set[str] = set()
    for row_number, row in enumerate(rows[1:], start=2):
        if len(row) != len(expected_header):
            raise TransportError(f"COLUMN_COUNT_MISMATCH:{row_number}")
        raw_record = text_record_at(text, row_number - 1)
        if not re.fullmatch(r'"(?:[^"]|"")*"(?:,"(?:[^"]|"")*")*', raw_record, re.S):
            raise TransportError(f"UNQUOTED_FIELD:{row_number}")
        if _canonical_record(row) != raw_record:
            raise TransportError(f"NONCANONICAL_RECORD:{row_number}")
        if row[0] != SCHEMA_VERSION:
            raise TransportError(f"UNSUPPORTED_SCHEMA:{row_number}")
        if not row[5] or not row[6] or not row[7]:
            raise TransportError(f"MISSING_IDENTITY:{row_number}")
        _validate_common(row, row_number)
        _validate_extensions(row, row_number)
        if row[7] in event_ids:
            raise TransportError(f"DUPLICATE_EVENT_ID:{row_number}")
        if row[6] in sequence_ids:
            raise TransportError(f"DUPLICATE_SEQUENCE_ID:{row_number}")
        event_ids.add(row[7])
        sequence_ids.add(row[6])

    return {
        "row_count": len(rows) - 1,
        "journal_sha256": _sha256(data),
        "column_count": len(expected_header),
        "event_ids": event_ids,
        "sequence_ids": sequence_ids,
        "rows": tuple(tuple(row) for row in rows[1:]),
    }


def validate_journal_bytes(data: bytes, expected_header: list[str]) -> dict[str, object]:
    # Certified return payload — the original key set only, unchanged. The
    # validated rows are available exclusively through reconstruct_verified_rows.
    parsed = _validated_parse(data, expected_header)
    return {
        "row_count": parsed["row_count"],
        "journal_sha256": parsed["journal_sha256"],
        "column_count": parsed["column_count"],
        "event_ids": parsed["event_ids"],
        "sequence_ids": parsed["sequence_ids"],
    }


def reconstruct_verified_rows(data: bytes, expected_header: list[str]) -> VerifiedJournalRowsV2:
    """Immutable already-validated rows from the same single certified
    validation pass as validate_journal_bytes(). Additive accessor: it does not
    re-parse with different semantics, alter accepted/rejected bytes, change
    canonical serialization, or repair input. The journal SHA is the one the
    certified validator computes over the exact bytes."""
    parsed = _validated_parse(data, expected_header)
    rows = parsed["rows"]
    return VerifiedJournalRowsV2(
        transport_version=TRANSPORT_VERSION,
        schema_version=SCHEMA_VERSION,
        journal_sha256=str(parsed["journal_sha256"]),
        row_count=int(parsed["row_count"]),
        rows=rows,
        event_ids=tuple(row[7] for row in rows),
        sequence_ids=tuple(row[6] for row in rows),
    )


def text_record_at(text: str, index: int) -> str:
    """Return one logical RFC-4180 record without its terminal CRLF."""
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
                raise TransportError("BARE_CR")
            if current == index:
                return text[start:i]
            current += 1
            i += 1
            start = i + 1
        elif char == "\n" and not quoted:
            raise TransportError("BARE_LF")
        i += 1
    raise TransportError("RECORD_INDEX_MISSING")


def build_manifest(
    journal: Path, header: Path, symbol: str, timeframe: int, source_data_sha256: str
) -> Manifest:
    if not symbol or not _is_sha256(source_data_sha256):
        raise TransportError("INVALID_MANIFEST_INPUT")
    result = validate_journal_bytes(journal.read_bytes(), read_header(header))
    return Manifest(
        manifest_version=MANIFEST_VERSION,
        writer_version=WRITER_VERSION,
        schema_version=SCHEMA_VERSION,
        symbol=symbol,
        timeframe=timeframe,
        row_count=int(result["row_count"]),
        journal_sha256=str(result["journal_sha256"]),
        source_data_sha256=source_data_sha256.lower(),
    )


def manifest_bytes(manifest: Manifest) -> bytes:
    fields = [
        manifest.manifest_version,
        manifest.writer_version,
        manifest.schema_version,
        manifest.symbol,
        str(manifest.timeframe),
        str(manifest.row_count),
        manifest.journal_sha256,
        manifest.source_data_sha256,
    ]
    return (",".join(MANIFEST_HEADER) + "\r\n" + _canonical_record(fields) + "\r\n").encode(
        "utf-8"
    )


def parse_manifest_bytes(data: bytes) -> Manifest:
    text = _decode_utf8(data)
    rows = _records(text)
    if len(rows) != 2 or rows[0] != MANIFEST_HEADER:
        raise TransportError("MANIFEST_SHAPE_MISMATCH")
    if _canonical_record(rows[1]) != text_record_at(text, 1) or len(rows[1]) != 8:
        raise TransportError("MANIFEST_RECORD_MISMATCH")
    values = rows[1]
    try:
        timeframe = int(values[4])
        row_count = int(values[5])
    except ValueError as exc:
        raise TransportError("INVALID_MANIFEST_FIELD") from exc
    if (
        values[0] != MANIFEST_VERSION
        or values[1] != WRITER_VERSION
        or values[2] != SCHEMA_VERSION
        or not values[3]
        or str(timeframe) != values[4]
        or str(row_count) != values[5]
        or row_count < 0
        or not _is_sha256(values[6])
        or not _is_sha256(values[7])
    ):
        raise TransportError("INVALID_MANIFEST_FIELD")
    return Manifest(
        values[0], values[1], values[2], values[3], timeframe, row_count, values[6], values[7]
    )


def verify_manifest(
    manifest: Manifest,
    journal: Path,
    header: Path,
    symbol: str,
    timeframe: int,
    source_data_sha256: str,
) -> dict[str, object]:
    if (
        manifest.manifest_version != MANIFEST_VERSION
        or manifest.writer_version != WRITER_VERSION
        or manifest.schema_version != SCHEMA_VERSION
    ):
        raise TransportError("MANIFEST_VERSION_MISMATCH")
    if manifest.symbol != symbol or manifest.timeframe != timeframe:
        raise TransportError("MANIFEST_MARKET_MISMATCH")
    if manifest.source_data_sha256 != source_data_sha256:
        raise TransportError("SOURCE_DATA_HASH_MISMATCH")
    result = validate_journal_bytes(journal.read_bytes(), read_header(header))
    if manifest.row_count != result["row_count"]:
        raise TransportError("ROW_COUNT_MISMATCH")
    if manifest.journal_sha256 != result["journal_sha256"]:
        raise TransportError("JOURNAL_HASH_MISMATCH")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["build", "verify"])
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--header", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--timeframe", type=int, required=True)
    parser.add_argument("--source-data-sha256", required=True)
    args = parser.parse_args()

    if args.command == "build":
        manifest = build_manifest(
            args.journal, args.header, args.symbol, args.timeframe, args.source_data_sha256
        )
        args.manifest.write_bytes(manifest_bytes(manifest))
        print(json.dumps(asdict(manifest), sort_keys=True))
        return 0

    manifest = parse_manifest_bytes(args.manifest.read_bytes())
    result = verify_manifest(
        manifest,
        args.journal,
        args.header,
        args.symbol,
        args.timeframe,
        args.source_data_sha256,
    )
    printable = {k: v for k, v in result.items() if not isinstance(v, set)}
    print(json.dumps(printable, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TransportError as exc:
        print(str(exc))
        raise SystemExit(2)
