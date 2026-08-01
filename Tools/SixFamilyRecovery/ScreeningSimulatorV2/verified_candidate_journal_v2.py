#!/usr/bin/env python3
"""Journal-to-screening binding adapter (Layer between JournalTransportV2 and
ScreeningSimulatorV2).

Dependency direction: research_journal_transport_v2 -> this adapter ->
screening_simulator_v2. JournalTransportV2 never imports simulator types.

It reconstructs the simulator's candidate projection from the exact canonical
journal bytes verified by JournalTransportV2, computes a versioned, cross-
language-identical projection digest, and produces an immutable
VerifiedCandidateJournalV2 bundle. The certified public simulator entry point
accepts only this bundle and re-derives from the bundle's journal bytes, so an
unbound candidate run is structurally impossible.

Projection preserves the journal-owned candidate evidence verbatim (including
both the explicit `target` price and `target_r`); it never recomputes a
journal-owned field.
"""
from __future__ import annotations

import csv
import hashlib
import io
import pathlib
import sys
from dataclasses import dataclass

_HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "JournalTransportV2"))

import research_journal_transport_v2 as jt  # noqa: E402
import screening_simulator_v2 as sim  # noqa: E402

BUNDLE_VERSION = "MSZZ_VERIFIED_CANDIDATE_JOURNAL_V2"
PROJECTION_VERSION = "MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2"

# Journal column indices (by name in candidate_header_v2.csv), used only here.
_COL = {
    "strategy_id": 1,
    "family_id": 2,
    "hypothesis_version": 3,
    "canonical_variant_id": 4,
    "origin_id": 5,
    "sequence_id": 6,
    "event_id": 7,
    "clock_domain": 8,
    "time_authority_id": 9,
    "signal_time_raw": 10,
    "expiry_time_raw": 11,
    "direction": 12,
    "entry": 13,
    "stop": 14,
    "target": 15,
    "stop_distance_points": 27,
    "target_r": 28,
}

# Order of the 17 projection fields (frozen). direction is normalized to +-1;
# every other field is the journal string preserved verbatim.
_PROJECTION_ORDER = (
    "strategy_id", "family_id", "hypothesis_version", "canonical_variant_id",
    "origin_id", "sequence_id", "event_id", "clock_domain", "time_authority_id",
    "signal_time_raw", "expiry_time_raw", "direction", "entry", "stop",
    "target", "target_r", "stop_distance_points",
)


class JournalBindingError(ValueError):
    pass


@dataclass(frozen=True)
class VerifiedCandidateJournalV2:
    bundle_version: str
    transport_version: str
    schema_version: str
    projection_version: str
    symbol: str
    timeframe: int
    source_data_sha256: str
    journal_sha256: str
    projection_sha256: str
    row_count: int
    candidates: tuple[sim.Candidate, ...]
    journal_bytes: bytes
    header: tuple[str, ...]
    manifest: jt.Manifest


def _canonical_record(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(
        stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True
    ).writerow(fields)
    return stream.getvalue()


def _direction_token(value: str) -> str:
    if value == "LONG":
        return "1"
    if value == "SHORT":
        return "-1"
    raise JournalBindingError("INVALID_DIRECTION")


def _projection_fields(row: tuple[str, ...]) -> list[str]:
    out: list[str] = []
    for name in _PROJECTION_ORDER:
        if name == "direction":
            out.append(_direction_token(row[_COL["direction"]]))
        else:
            out.append(row[_COL[name]])
    return out


def projection_document(rows: tuple[tuple[str, ...], ...]) -> bytes:
    """Canonical, cross-language-identical projection bytes: version header line,
    then one QUOTE_ALL RFC-4180 record per candidate, CRLF-terminated including
    the final record, UTF-8 no BOM."""
    records = [_canonical_record(_projection_fields(row)) for row in rows]
    text = PROJECTION_VERSION + "\r\n" + "".join(rec + "\r\n" for rec in records)
    return text.encode("utf-8")


def projection_sha256(rows: tuple[tuple[str, ...], ...]) -> str:
    return hashlib.sha256(projection_document(rows)).hexdigest()


def project_candidate(row: tuple[str, ...]) -> sim.Candidate:
    """Project one validated journal row into the immutable simulator candidate.
    Rejects a row that cannot supply the projection without inference."""
    for name in _PROJECTION_ORDER:
        if name == "direction":
            continue
        if row[_COL[name]] == "":
            raise JournalBindingError(f"MISSING_PROJECTION_FIELD:{name}")
    direction = 1 if row[_COL["direction"]] == "LONG" else -1
    if row[_COL["direction"]] not in ("LONG", "SHORT"):
        raise JournalBindingError("INVALID_DIRECTION")
    return sim.Candidate(
        strategy_id=int(row[_COL["strategy_id"]]),
        family_id=int(row[_COL["family_id"]]),
        hypothesis_version=row[_COL["hypothesis_version"]],
        canonical_variant_id=row[_COL["canonical_variant_id"]],
        origin_id=row[_COL["origin_id"]],
        sequence_id=row[_COL["sequence_id"]],
        event_id=row[_COL["event_id"]],
        clock_domain=row[_COL["clock_domain"]],
        time_authority_id=row[_COL["time_authority_id"]],
        signal_time=int(row[_COL["signal_time_raw"]]),
        expiry_time=int(row[_COL["expiry_time_raw"]]),
        direction=direction,
        entry=float(row[_COL["entry"]]),
        stop=float(row[_COL["stop"]]),
        target=float(row[_COL["target"]]),
        target_r=float(row[_COL["target_r"]]),
        stop_distance_points=float(row[_COL["stop_distance_points"]]),
    )


def build_verified_bundle(
    journal_bytes: bytes,
    header: list[str],
    manifest: jt.Manifest,
    symbol: str,
    timeframe: int,
    source_data_sha256: str,
) -> VerifiedCandidateJournalV2:
    """Honest producer: verify the journal bytes + manifest binding through the
    certified transport, project candidates, and freeze the bundle. Raises
    JournalBindingError on any binding defect (callers that must fail-close on
    the simulator boundary use run_screening instead, which returns the reject
    token). The journal SHA is the transport's, never a caller value."""
    verified = jt.reconstruct_verified_rows(journal_bytes, header)
    _check_manifest_binding(manifest, verified, symbol, timeframe, source_data_sha256)
    candidates = tuple(project_candidate(row) for row in verified.rows)
    return VerifiedCandidateJournalV2(
        bundle_version=BUNDLE_VERSION,
        transport_version=verified.transport_version,
        schema_version=verified.schema_version,
        projection_version=PROJECTION_VERSION,
        symbol=symbol,
        timeframe=timeframe,
        source_data_sha256=source_data_sha256,
        journal_sha256=verified.journal_sha256,
        projection_sha256=projection_sha256(verified.rows),
        row_count=verified.row_count,
        candidates=candidates,
        journal_bytes=journal_bytes,
        header=tuple(header),
        manifest=manifest,
    )


def _check_manifest_binding(
    manifest: jt.Manifest,
    verified: jt.VerifiedJournalRowsV2,
    symbol: str,
    timeframe: int,
    source_data_sha256: str,
) -> None:
    if (
        manifest.manifest_version != jt.MANIFEST_VERSION
        or manifest.writer_version != jt.WRITER_VERSION
        or manifest.schema_version != jt.SCHEMA_VERSION
    ):
        raise JournalBindingError("MANIFEST_VERSION_MISMATCH")
    if manifest.symbol != symbol or manifest.timeframe != timeframe:
        raise JournalBindingError("MANIFEST_MARKET_MISMATCH")
    if manifest.source_data_sha256 != source_data_sha256:
        raise JournalBindingError("SOURCE_DATA_HASH_MISMATCH")
    if manifest.row_count != verified.row_count:
        raise JournalBindingError("ROW_COUNT_MISMATCH")
    if manifest.journal_sha256 != verified.journal_sha256:
        raise JournalBindingError("JOURNAL_HASH_MISMATCH")


def rederive_and_check(
    bundle: VerifiedCandidateJournalV2, market_data_sha256: str
) -> tuple[sim.Candidate, ...]:
    """Re-derive candidates from the bundle's own journal bytes and prove every
    claimed bundle field matches the re-derivation and the market binding.
    Returns the authoritative re-derived candidates. Raises JournalBindingError
    on ANY discrepancy — this is what makes a forged or mutated bundle
    unusable on the certified path."""
    if bundle.bundle_version != BUNDLE_VERSION:
        raise JournalBindingError("UNSUPPORTED_BUNDLE_VERSION")
    if bundle.transport_version != jt.TRANSPORT_VERSION:
        raise JournalBindingError("UNSUPPORTED_TRANSPORT_VERSION")
    if bundle.schema_version != jt.SCHEMA_VERSION:
        raise JournalBindingError("UNSUPPORTED_SCHEMA_VERSION")
    if bundle.projection_version != PROJECTION_VERSION:
        raise JournalBindingError("UNSUPPORTED_PROJECTION_VERSION")
    verified = jt.reconstruct_verified_rows(bundle.journal_bytes, list(bundle.header))
    _check_manifest_binding(
        bundle.manifest, verified, bundle.symbol, bundle.timeframe, bundle.source_data_sha256
    )
    if bundle.source_data_sha256 != market_data_sha256:
        raise JournalBindingError("SOURCE_DATA_MARKET_MISMATCH")
    if bundle.journal_sha256 != verified.journal_sha256:
        raise JournalBindingError("JOURNAL_SHA_MISMATCH")
    if bundle.row_count != verified.row_count:
        raise JournalBindingError("ROW_COUNT_MISMATCH")
    expected_projection = projection_sha256(verified.rows)
    if bundle.projection_sha256 != expected_projection:
        raise JournalBindingError("PROJECTION_SHA_MISMATCH")
    rederived = tuple(project_candidate(row) for row in verified.rows)
    if bundle.candidates != rederived:
        raise JournalBindingError("CANDIDATE_MUTATION")
    if len(rederived) != bundle.row_count:
        raise JournalBindingError("ROW_COUNT_MISMATCH")
    return rederived
