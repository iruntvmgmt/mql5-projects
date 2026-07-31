#!/usr/bin/env python3

from __future__ import annotations

import csv
import io
import tempfile
import unittest
from pathlib import Path

from research_journal_transport_v2 import (
    MANIFEST_VERSION,
    SCHEMA_VERSION,
    TransportError,
    build_manifest,
    manifest_bytes,
    parse_manifest_bytes,
    read_header,
    validate_journal_bytes,
    verify_manifest,
)

ROOT = Path(__file__).resolve().parent
HEADER_PATH = ROOT / "candidate_header_v2.csv"
SOURCE_HASH = "0123456789abcdef" * 4


def canonical(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(
        stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True
    ).writerow(fields)
    return stream.getvalue()


def row(sequence: str = "SEQUENCE|1", event: str = "EVENT|1|FINAL") -> list[str]:
    fields = [""] * len(read_header(HEADER_PATH))
    fields[0] = SCHEMA_VERSION
    fields[1] = "1200"
    fields[2] = "8"
    fields[3] = "SSR-V2"
    fields[4] = "CANONICAL"
    fields[5] = "ASIA_LOW|20260105"
    fields[6] = sequence
    fields[7] = event
    fields[8] = "BROKER_SERVER_RAW"
    fields[9] = "MSZZ_TIME_RAW_BROKER_V1"
    fields[10] = "1767607200"
    fields[11] = "1767608100"
    fields[12] = "LONG"
    fields[13] = "100.0000000000000000"
    fields[14] = "99.0000000000000000"
    fields[15] = "102.0000000000000000"
    fields[16] = "1.0000000000000000"
    fields[17] = "SESSION_RANGE"
    fields[18] = "ASIA|20260105"
    fields[19] = "99.5000000000000000"
    fields[20] = "1767606900"
    fields[21] = "1767607200"
    fields[22] = "1"
    fields[23] = "NONE"
    fields[24] = "FRESH_CROSS"
    fields[25] = "2.0000000000000000"
    fields[26] = "2.1000000000000001"
    fields[27] = "100.0000000000000000"
    fields[28] = "2.0000000000000000"
    fields[29] = "10"
    fields[30] = "0.1000000000000000"
    fields[31] = "SESSION|LONDON"
    fields[32] = "REGIME|1"
    fields[33] = '{"evidence":"comma,quote\\""}'
    fields[74] = "SESSION_TABLE_V1"
    fields[75] = "ASIA|20260105"
    fields[76] = "101.0000000000000000"
    fields[77] = "99.0000000000000000"
    fields[78] = "98.7999999999999972"
    fields[79] = "100.0000000000000000"
    return fields


def journal(*rows: list[str], final_crlf: bool = True) -> bytes:
    header = HEADER_PATH.read_text(encoding="utf-8").rstrip("\r\n")
    text = header + "\r\n" + "\r\n".join(canonical(value) for value in rows)
    if final_crlf:
        text += "\r\n"
    return text.encode("utf-8")


class JournalTransportV2Tests(unittest.TestCase):
    def test_valid_round_trip(self) -> None:
        data = journal(row())
        result = validate_journal_bytes(data, read_header(HEADER_PATH))
        self.assertEqual(result["row_count"], 1)
        self.assertEqual(len(result["journal_sha256"]), 64)

    def test_malformed_matrix(self) -> None:
        cases: list[tuple[str, bytes, str]] = [
            ("invalid_utf8", b"\xc3(", "INVALID_UTF8_CONTINUATION"),
            ("missing_final_crlf", journal(row(), final_crlf=False), "MISSING_FINAL_CRLF"),
            (
                "wrong_columns",
                journal(row() + ["EXTRA"]),
                "COLUMN_COUNT_MISMATCH",
            ),
            (
                "duplicate_event",
                journal(row(), row("SEQUENCE|2", "EVENT|1|FINAL")),
                "DUPLICATE_EVENT_ID",
            ),
            (
                "duplicate_sequence",
                journal(row(), row("SEQUENCE|1", "EVENT|2|FINAL")),
                "DUPLICATE_SEQUENCE_ID",
            ),
            (
                "unsupported_schema",
                journal(["UNKNOWN"] + row()[1:]),
                "UNSUPPORTED_SCHEMA",
            ),
            (
                "invalid_enum",
                journal(row()[:12] + ["SIDEWAYS"] + row()[13:]),
                "INVALID_DIRECTION",
            ),
            (
                "invalid_number",
                journal(row()[:13] + ["100x"] + row()[14:]),
                "INVALID_NUMBER",
            ),
            (
                "invalid_time",
                journal(row()[:11] + [row()[10]] + row()[12:]),
                "INVALID_LIFECYCLE_TIME",
            ),
        ]
        for name, data, reason in cases:
            with self.subTest(name=name):
                with self.assertRaisesRegex(TransportError, reason):
                    validate_journal_bytes(data, read_header(HEADER_PATH))

    def test_noncanonical_unquoted_row_rejected(self) -> None:
        data = journal(row()).replace(
            b'"MSZZ_RESEARCH_CANDIDATE_V2"', b"MSZZ_RESEARCH_CANDIDATE_V2", 1
        )
        with self.assertRaisesRegex(TransportError, "UNQUOTED_FIELD"):
            validate_journal_bytes(data, read_header(HEADER_PATH))

    def test_manifest_round_trip_and_verification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            journal_path = root / "journal.csv"
            journal_path.write_bytes(journal(row()))
            manifest = build_manifest(journal_path, HEADER_PATH, "XAUUSD", 5, SOURCE_HASH)
            self.assertEqual(manifest.manifest_version, MANIFEST_VERSION)
            parsed = parse_manifest_bytes(manifest_bytes(manifest))
            result = verify_manifest(
                parsed, journal_path, HEADER_PATH, "XAUUSD", 5, SOURCE_HASH
            )
            self.assertEqual(result["row_count"], 1)

            with self.assertRaisesRegex(TransportError, "SOURCE_DATA_HASH_MISMATCH"):
                verify_manifest(parsed, journal_path, HEADER_PATH, "XAUUSD", 5, "f" * 64)


if __name__ == "__main__":
    unittest.main(verbosity=2)
