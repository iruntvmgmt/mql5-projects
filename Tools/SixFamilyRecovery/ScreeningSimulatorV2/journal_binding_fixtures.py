#!/usr/bin/env python3
"""Language-neutral JOURNAL_BINDING (JB) fixture source.

Each fixture is a real, canonical family-8 (SSR) ResearchCandidateSchemaV2
journal (one or more rows) plus a well-defined tamper applied at a specific
stage, with the expected certified public-simulator run status. The same
fixtures drive the Python JB test and (via journal_binding_fixtures.csv) the
MQL5 JB test, so both languages must reach the identical run-status token.

Family 8 is used because its schema requirements are satisfiable canonically
without StructuralEventRecord coupling (see the binding design record).

Tamper stages:
  * journal-level  -> baked into the journal bytes (permutation, bad clock/auth);
  * manifest-level -> manifest field overrides;
  * bundle-level   -> opcode applied to the built bundle before run_screening.
"""
from __future__ import annotations

import csv
import io
from dataclasses import dataclass, field

SCHEMA_VERSION = "MSZZ_RESEARCH_CANDIDATE_V2"
WRITER_VERSION = "MSZZ_RESEARCH_CSV_WRITER_V2"
MANIFEST_VERSION = "MSZZ_RESEARCH_MANIFEST_V2"

# Market binding shared by JB fixtures (0.01 point grid, tick 0.01).
SYMBOL = "XAUUSD"
TF = 5
POINT_SIZE_1E8 = 1_000_000
TICK_SIZE_1E8 = 1_000_000
# Bars: entry executes on the bar strictly after signal_time=100.
BARS = [
    (50, 10000, 10010, 9990, 10000, 2),
    (150, 10000, 10250, 9990, 10200, 2),
    (250, 10200, 10260, 10180, 10210, 2),
]

HEADER_COLS = 116


def _d(value: float) -> str:
    return f"{value:.16f}"


@dataclass(frozen=True)
class JRow:
    sequence_id: str = "SEQUENCE|1"
    event_id: str = "EVENT|1|FINAL"
    direction: str = "LONG"
    entry: float = 100.0
    stop: float = 99.0
    target: float = 102.0
    target_r: float = 2.0
    stop_distance_points: float = 100.0
    signal: int = 100
    expiry: int = 100000
    clock_domain: str = "BROKER_SERVER_RAW"
    time_authority_id: str = "MSZZ_TIME_RAW_BROKER_V1"


def row_fields(r: JRow) -> list[str]:
    f = [""] * HEADER_COLS
    f[0] = SCHEMA_VERSION
    f[1] = "1200"
    f[2] = "8"
    f[3] = "SSR-V2"
    f[4] = "CANONICAL"
    f[5] = "ASIA_LOW|20260105"
    f[6] = r.sequence_id
    f[7] = r.event_id
    f[8] = r.clock_domain
    f[9] = r.time_authority_id
    f[10] = str(r.signal)
    f[11] = str(r.expiry)
    f[12] = r.direction
    f[13] = _d(r.entry)
    f[14] = _d(r.stop)
    f[15] = _d(r.target)
    f[16] = _d(1.0)
    f[17] = "SESSION_RANGE"
    f[18] = "ASIA|20260105"
    f[19] = _d(99.5)
    f[20] = "90"
    f[21] = str(r.signal)  # trigger == signal
    f[22] = "1"
    f[23] = "NONE"
    f[24] = "FRESH_CROSS"
    f[25] = _d(2.0)
    f[26] = _d(2.1)
    f[27] = _d(r.stop_distance_points)
    f[28] = _d(r.target_r)
    f[29] = "10"
    f[30] = _d(0.1)
    f[31] = "SESSION|LONDON"
    f[32] = "REGIME|1"
    f[33] = '{"e":"x"}'
    # family-8 SSR extension (cols 74-79)
    f[74] = "SESSION_TABLE_V1"
    f[75] = "ASIA|20260105"
    f[76] = _d(101.0)
    f[77] = _d(99.0)
    f[78] = _d(98.8)
    f[79] = _d(100.0)
    return f


def canonical_record(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return stream.getvalue()


def header_line() -> str:
    # candidate_header_v2.csv column names, unquoted, comma-joined.
    import pathlib
    p = pathlib.Path(__file__).resolve().parent.parent / "JournalTransportV2" / "candidate_header_v2.csv"
    return p.read_text(encoding="utf-8").rstrip("\r\n")


def journal_bytes(rows: list[JRow], final_crlf: bool = True) -> bytes:
    text = header_line() + "\r\n" + "".join(canonical_record(row_fields(r)) + "\r\n" for r in rows)
    if not final_crlf:
        text = text[:-2]
    return text.encode("utf-8")


# Tamper opcodes applied to the built bundle (bundle-level), or NONE.
BUNDLE_TAMPERS = {
    "NONE", "MUTATE_ENTRY", "MUTATE_STOP", "MUTATE_TARGET", "MUTATE_TARGET_R",
    "MUTATE_SIGNAL", "MUTATE_EXPIRY", "MUTATE_EVENT_ID", "MUTATE_SEQUENCE_ID",
    "ADD_CANDIDATE", "REMOVE_CANDIDATE", "DUP_CANDIDATE",
    "BUNDLE_VERSION", "TRANSPORT_VERSION",
    "PROJECTION_VERSION", "SCHEMA_VERSION",
}


@dataclass(frozen=True)
class JBFixture:
    id: str
    behavior: str
    rows: tuple[JRow, ...]
    expect_run_status: str
    tamper: str = "NONE"                 # bundle-level opcode
    manifest_journal_sha: str | None = None   # override; None=honest
    manifest_row_count: int | None = None
    manifest_source_sha: str | None = None
    manifest_symbol: str | None = None
    manifest_timeframe: int | None = None
    permute_rows: bool = False           # permute journal rows but keep honest manifest? see stale_sha
    stale_manifest_after_permute: bool = False


A_LONG = JRow("SEQUENCE|1", "EVENT|1|FINAL")
B_LONG = JRow("SEQUENCE|2", "EVENT|2|FINAL", entry=100.0, stop=99.0, target=102.0)

_OK = "RUN_OK"
_BIND = "REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH"

FIXTURES: list[JBFixture] = [
    JBFixture("JB01", "valid verified bundle", (A_LONG,), _OK),
    JBFixture("JB02", "entry mutated after verification", (A_LONG,), _BIND, tamper="MUTATE_ENTRY"),
    JBFixture("JB03", "stop mutated", (A_LONG,), _BIND, tamper="MUTATE_STOP"),
    JBFixture("JB04", "target mutated", (A_LONG,), _BIND, tamper="MUTATE_TARGET"),
    JBFixture("JB05", "target_r mutated", (A_LONG,), _BIND, tamper="MUTATE_TARGET_R"),
    JBFixture("JB06", "signal_time mutated", (A_LONG,), _BIND, tamper="MUTATE_SIGNAL"),
    JBFixture("JB07", "expiry mutated", (A_LONG,), _BIND, tamper="MUTATE_EXPIRY"),
    JBFixture("JB08", "event_id mutated", (A_LONG,), _BIND, tamper="MUTATE_EVENT_ID"),
    JBFixture("JB09", "sequence_id mutated", (A_LONG,), _BIND, tamper="MUTATE_SEQUENCE_ID"),
    JBFixture("JB10", "candidate added", (A_LONG,), _BIND, tamper="ADD_CANDIDATE"),
    JBFixture("JB11", "candidate removed", (A_LONG, B_LONG), _BIND, tamper="REMOVE_CANDIDATE"),
    JBFixture("JB12", "duplicate candidate inserted", (A_LONG,), _BIND, tamper="DUP_CANDIDATE"),
    JBFixture("JB13", "manifest row_count high", (A_LONG,), _BIND, manifest_row_count=2),
    JBFixture("JB14", "manifest row_count low", (A_LONG, B_LONG), _BIND, manifest_row_count=1),
    JBFixture("JB15", "valid-looking wrong journal sha", (A_LONG,), _BIND,
              manifest_journal_sha="a" * 64),
    JBFixture("JB16", "wrong source-data sha", (A_LONG,), _BIND,
              manifest_source_sha="b" * 64),
    JBFixture("JB17", "wrong symbol", (A_LONG,), _BIND, manifest_symbol="EURUSD"),
    JBFixture("JB18", "wrong timeframe", (A_LONG,), _BIND, manifest_timeframe=15),
    JBFixture("JB19", "wrong clock domain in journal", (JRow(clock_domain="LOCAL"),), _BIND),
    JBFixture("JB20", "wrong time authority in journal", (JRow(time_authority_id="OTHER"),), _BIND),
    JBFixture("JB21", "unsupported schema/projection version", (A_LONG,), _BIND, tamper="PROJECTION_VERSION"),
    JBFixture("JB22", "unsupported transport version", (A_LONG,), _BIND, tamper="TRANSPORT_VERSION"),
    JBFixture("JB23", "row permutation with stale manifest sha", (A_LONG, B_LONG), _BIND,
              permute_rows=True, stale_manifest_after_permute=True),
    JBFixture("JB24", "row permutation honestly re-manifested", (A_LONG, B_LONG), _OK,
              permute_rows=True),
]


def fixture_ids() -> list[str]:
    return [f.id for f in FIXTURES]
