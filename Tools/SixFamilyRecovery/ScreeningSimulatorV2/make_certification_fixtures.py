#!/usr/bin/env python3
"""Emit the language-neutral certification fixture transport files consumed by
the three focused MQL5 harnesses (F / JB / OR). Reproducible from the Python
fixture source modules (single source of truth). F01-F58 are emitted by
make_simulator_fixtures.py; this script emits:

  ordering_fixtures.csv                 OR candidate rows + expected rank
  journal_binding_fixture_index.csv     canonical JB control (explicit filenames,
                                        tamper stage/field/value, manifest
                                        overrides, expected journal/projection
                                        SHAs, expected status + outcome count)
  cert_jb_<ID>_journal.csv              per-JB canonical journal bytes
  cert_run_id.txt                       fixture-set identity shared by F/JB/OR

Canonical bytes: UTF-8 no BOM, CRLF after every record incl. final, a bare
version-token first line, then a header line, then QUOTE_ALL data records.
"""
from __future__ import annotations

import csv
import hashlib
import io
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "JournalTransportV2"))
sys.path.insert(0, str(HERE.parent / "ScreeningExecutionV2"))

import journal_binding_fixtures as jbf
import ordering_fixtures as orf
import research_journal_transport_v2 as jt
import verified_candidate_journal_v2 as adapt

ORDERING_VERSION = "MSZZ_SCREENING_ORDERING_FIXTURES_V2"
BINDING_INDEX_VERSION = "MSZZ_SCREENING_JB_INDEX_V2"
CERT_RUN_PREFIX = "MSZZ_SCREENING_CERT_RUN_V2"
HEADER = jbf.header_line().split(",")

FILES_DIRS = [
    pathlib.Path("/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/"
                 "drive_c/Program Files/MetaTrader 5/MQL5/Files"),
    pathlib.Path("/Users/matt/MT5-MSZZ-TEST/MQL5/Files"),
]

_CANDIDATE_TAMPERS = {
    "MUTATE_ENTRY", "MUTATE_STOP", "MUTATE_TARGET", "MUTATE_TARGET_R",
    "MUTATE_SIGNAL", "MUTATE_EXPIRY", "MUTATE_EVENT_ID", "MUTATE_SEQUENCE_ID",
    "ADD_CANDIDATE", "REMOVE_CANDIDATE", "DUP_CANDIDATE",
}
_IDENTITY_TAMPERS = {"BUNDLE_VERSION", "TRANSPORT_VERSION", "PROJECTION_VERSION", "SCHEMA_VERSION"}


def _quoted_record(fields: list[str]) -> str:
    out = io.StringIO()
    csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return out.getvalue()


def _canon_doc(header_token: str, header_cols: list[str], rows: list[list[str]]) -> bytes:
    # bare version token line, bare comma-joined column header, then QUOTE_ALL data
    # rows (matching the market-transport convention: unquoted header, quoted data).
    lines = [header_token, ",".join(header_cols)] + [_quoted_record(r) for r in rows]
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def _honest_shas(jbytes: bytes):
    """(invalid, journal_sha, projection_sha) for a candidate journal."""
    try:
        v = jt.reconstruct_verified_rows(jbytes, HEADER)
    except jt.TransportError:
        return "1", "", ""
    return "0", v.journal_sha256, adapt.projection_sha256(v.rows)


def _tamper_stage_field_value(fx: jbf.JBFixture, invalid: str):
    if invalid == "1":
        return "PRE_TRANSPORT_BYTES", "invalid_journal", ""
    if fx.tamper in _CANDIDATE_TAMPERS:
        return "POST_BUNDLE_CANDIDATE", fx.tamper, ""
    if fx.tamper in _IDENTITY_TAMPERS:
        return "POST_BUNDLE_IDENTITY", fx.tamper, ""
    if fx.manifest_row_count is not None:
        return "POST_BUNDLE_MANIFEST", "manifest_row_count", str(fx.manifest_row_count)
    if fx.manifest_journal_sha is not None:
        return "POST_BUNDLE_MANIFEST", "manifest_journal_sha", fx.manifest_journal_sha
    if fx.stale_manifest_after_permute:
        stale = jt.reconstruct_verified_rows(jbf.journal_bytes(list(fx.rows)), HEADER).journal_sha256
        return "POST_BUNDLE_MANIFEST", "manifest_journal_sha", stale
    if fx.manifest_source_sha is not None:
        return "POST_BUNDLE_MANIFEST", "manifest_source_sha", fx.manifest_source_sha
    if fx.manifest_symbol is not None:
        return "POST_BUNDLE_MANIFEST", "manifest_symbol", fx.manifest_symbol
    if fx.manifest_timeframe is not None:
        return "POST_BUNDLE_MANIFEST", "manifest_timeframe", str(fx.manifest_timeframe)
    return "NONE", "", ""


def build_ordering() -> bytes:
    rows: list[list[str]] = []
    for fx in orf.FIXTURES:
        ranks = orf.expected_ranks(fx)
        for i, c in enumerate(fx.cands):
            rows.append([fx.id, str(i), str(c.signal), str(c.family),
                         c.event_id, c.sequence_id, str(ranks[i])])
    return _canon_doc(ORDERING_VERSION,
                      ["fixture_id", "idx", "signal", "family", "event_id", "sequence_id", "expected_rank"],
                      rows)


def build_binding_index_and_journals():
    control: list[list[str]] = []
    journals: dict[str, bytes] = {}
    for fx in jbf.FIXTURES:
        rows = list(fx.rows)
        used = list(reversed(rows)) if fx.permute_rows else rows
        jbytes = jbf.journal_bytes(used)
        fname = f"cert_jb_{fx.id}_journal.csv"
        journals[fname] = jbytes
        invalid, jsha, psha = _honest_shas(jbytes)
        stage, field, value = _tamper_stage_field_value(fx, invalid)
        control.append([
            fx.id, fx.behavior, fname, invalid, stage, field, value,
            str(len(used)), jsha, psha,
            fx.expect_run_status,
            "0" if fx.expect_run_status != "RUN_OK" else str(len(used)),
        ])
    idx = _canon_doc(BINDING_INDEX_VERSION,
                     ["fixture_id", "behavior", "journal_filename", "invalid_journal",
                      "tamper_stage", "tamper_field", "tamper_value", "journal_rows",
                      "expected_journal_sha256", "expected_projection_sha256",
                      "expected_status", "expected_outcomes"],
                     control)
    return idx, journals


def cert_run_id(order_bytes: bytes, index_bytes: bytes) -> str:
    sim_fixtures = (HERE / "simulator_fixtures.csv").read_bytes()
    h = hashlib.sha256(sim_fixtures + index_bytes + order_bytes).hexdigest()[:16]
    return f"{CERT_RUN_PREFIX}_{h}"


def generate() -> dict[str, bytes]:
    order = build_ordering()
    index, journals = build_binding_index_and_journals()
    run_id = cert_run_id(order, index)
    artifacts = {
        "ordering_fixtures.csv": order,
        "journal_binding_fixture_index.csv": index,
        "cert_run_id.txt": (run_id + "\r\n").encode("utf-8"),
    }
    artifacts.update(journals)
    return artifacts


def write_all(artifacts: dict[str, bytes]):
    for name, data in artifacts.items():
        (HERE / name).write_bytes(data)
        for d in FILES_DIRS:
            d.mkdir(parents=True, exist_ok=True)
            (d / name).write_bytes(data)


def main() -> int:
    artifacts = generate()
    write_all(artifacts)
    for name in ("ordering_fixtures.csv", "journal_binding_fixture_index.csv", "cert_run_id.txt"):
        print(f"{name:38} sha256={hashlib.sha256(artifacts[name]).hexdigest()}")
    print(f"per-JB journals: {sum(1 for k in artifacts if k.startswith('cert_jb_'))}")
    print("cert_run_id:", artifacts['cert_run_id.txt'].decode().strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
