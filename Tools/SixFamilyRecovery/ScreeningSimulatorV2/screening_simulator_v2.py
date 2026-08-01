#!/usr/bin/env python3
"""Family-neutral standalone historical screening simulator (MSZZ_SCREENING_OUTCOME_V2).

Consumes certified inputs only:
  * validated ResearchCandidateSchemaV2 candidates + their journal manifest,
  * the integer market transport (screening_market_v2) + its manifest,
  * the integer instrument params,
  * the frozen policy id MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST.

Semantic authority is the certified ScreeningExecutionPolicyV2 (resolve_bar for
the exit decision, normalize_stop/normalize_target for geometry, gross_r for R).
The canonical outcome record is encoded in integers so the outcome hash is
byte-identical across MQL5/Python:
  * every price is a signed integer POINT count (price = points * point_size),
  * every R is a signed integer in 1e-9 R units, computed by exact integer
    arithmetic from integer points and cross-checked against policy.gross_r
    within the frozen 1e-9 tolerance,
  * times are raw broker integers, enums are canonical tokens, booleans true/false.

Dataset-level integrity failures abort the whole run (a run-status record); no
fabricated per-candidate outcomes are emitted.
"""

from __future__ import annotations

import csv
import hashlib
import io
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ScreeningExecutionV2"))
import screening_execution_v2 as policy  # noqa: E402

from screening_market_v2 import (  # noqa: E402
    InstrumentParams,
    MarketData,
    MarketManifest,
    verify_candidate_point_size,
    verify_market_manifest,
)

OUTCOME_VERSION = "MSZZ_SCREENING_OUTCOME_V2"
POLICY_ID = "MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST"
R_SCALE = 1_000_000_000  # 1e-9 R units
R_TOLERANCE = 1.0e-9

# Per-candidate status / rejection tokens (additive; embeds the policy tokens).
ACCEPTED = "ACCEPTED"
REJECT_FAMILY_OPEN = "REJECT_FAMILY_OPEN"
REJECT_EXPIRED = "REJECT_EXPIRED"
REJECT_INVALID_GEOMETRY = "REJECT_INVALID_GEOMETRY"
REJECT_CANDIDATE_OFF_GRID = "REJECT_CANDIDATE_OFF_GRID"
REJECT_NO_NEXT_EXECUTABLE_BAR = "REJECT_NO_NEXT_EXECUTABLE_BAR"
REJECT_ENTRY_AFTER_TEST_END = "REJECT_ENTRY_AFTER_TEST_END"

# Dataset-level run-status tokens (abort the run before iteration).
RUN_OK = "RUN_OK"
REJECT_UNSUPPORTED_POLICY = "REJECT_UNSUPPORTED_POLICY"
REJECT_SOURCE_HASH_MISMATCH = "REJECT_SOURCE_HASH_MISMATCH"
REJECT_MARKET_HASH_MISMATCH = "REJECT_MARKET_HASH_MISMATCH"
REJECT_JOURNAL_MANIFEST_INVALID = "REJECT_JOURNAL_MANIFEST_INVALID"
REJECT_SYMBOL_MISMATCH = "REJECT_SYMBOL_MISMATCH"
REJECT_TIMEFRAME_MISMATCH = "REJECT_TIMEFRAME_MISMATCH"
REJECT_CLOCK_DOMAIN_MISMATCH = "REJECT_CLOCK_DOMAIN_MISMATCH"
REJECT_TIME_AUTHORITY_MISMATCH = "REJECT_TIME_AUTHORITY_MISMATCH"
REJECT_INSTRUMENT_PARAMS_MISMATCH = "REJECT_INSTRUMENT_PARAMS_MISMATCH"
# Journal-binding failure on the certified public entry point: the supplied
# bundle's candidates are not exactly those reconstructed from the verified
# journal bytes / manifest (SHA, row count, projection digest, mutation, or
# unsupported version). Dataset-level abort with no outcomes.
REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH = "REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH"

GRID_TOL = 1.0e-6  # point-grid alignment tolerance (in points)


class _OffGrid(ValueError):
    pass

EXIT_STOP = "STOP"
EXIT_TARGET = "TARGET"
EXIT_TEST_END = "TEST_END"

CLOCK_DOMAIN = "BROKER_SERVER_RAW"
TIME_AUTHORITY = "MSZZ_TIME_RAW_BROKER_V1"


class ScreeningRunError(ValueError):
    def __init__(self, run_status: str):
        super().__init__(run_status)
        self.run_status = run_status


@dataclass(frozen=True)
class Candidate:
    strategy_id: int
    family_id: int
    hypothesis_version: str
    canonical_variant_id: str
    origin_id: str
    sequence_id: str
    event_id: str
    clock_domain: str
    time_authority_id: str
    signal_time: int
    expiry_time: int
    direction: int  # +1 long, -1 short
    entry: float
    stop: float
    target: float
    target_r: float
    stop_distance_points: float


@dataclass(frozen=True)
class CandidateManifest:
    symbol: str
    timeframe: int
    journal_sha256: str
    source_data_sha256: str


@dataclass(frozen=True)
class Outcome:
    outcome_version: str
    policy_id: str
    strategy_id: int
    family_id: int
    hypothesis_version: str
    canonical_variant_id: str
    origin_id: str
    sequence_id: str
    event_id: str
    signal_time_raw: int
    expiry_time_raw: int
    entry_time_raw: int
    exit_time_raw: int
    direction: str
    candidate_entry_points: int
    candidate_stop_points: int
    candidate_target_points: int
    candidate_target_r_1e9: int
    executable_entry_points: int
    normalized_stop_points: int
    reconstructed_target_points: int
    executable_exit_points: int
    initial_risk_points: int
    spread_points_at_entry: int
    spread_points_at_exit: int
    status: str
    rejection_reason: str
    exit_reason: str
    stop_first_collision: str
    gross_r_1e9: int
    mfe_r_1e9: int
    mae_r_1e9: int
    holding_bars: int
    symbol: str
    timeframe: int
    clock_domain: str
    time_authority_id: str
    source_data_sha256: str
    candidate_journal_sha256: str
    market_data_sha256: str
    instrument_params_sha256: str


OUTCOME_FIELDS = list(Outcome.__annotations__.keys())


def _round_ratio(num: int, den: int) -> int:
    """round(num/den) half away from zero, exact integer arithmetic. den>0."""
    if den <= 0:
        raise ValueError("denominator must be positive")
    if num >= 0:
        return (num + den // 2) // den
    return -((-num + den // 2) // den)


def _round_scale(x: float) -> int:
    """Deterministic round half away from zero (identical in MQL5)."""
    return int(x + 0.5) if x >= 0 else -int(-x + 0.5)


def _dir_token(direction: int) -> str:
    return "LONG" if direction > 0 else "SHORT"


def _points_round(price: float, point_size: float) -> int:
    """Snap a price to the nearest integer point count (used only for policy-normalized,
    already-on-grid outputs and off-grid diagnostic fallback)."""
    ratio = price / point_size
    return int(ratio + 0.5) if ratio >= 0 else -int(-ratio + 0.5)


def _points_exact(price: float, point_size: float) -> int:
    """Convert a price to integer points, requiring exact grid alignment.

    Reconstructs the price and requires equality within the frozen tolerance;
    raises _OffGrid otherwise. Never silently repairs off-grid evidence.
    """
    ratio = price / point_size
    nearest = _points_round(price, point_size)
    if abs(ratio - nearest) > GRID_TOL:
        raise _OffGrid()
    return nearest


def _sort_key(c: Candidate):
    # signal_time asc, family_id asc, event_id bytewise asc, sequence_id bytewise asc.
    return (c.signal_time, c.family_id, c.event_id.encode("utf-8"), c.sequence_id.encode("utf-8"))


@dataclass(frozen=True)
class _Diag:
    entry_points: int
    stop_points: int
    target_points: int
    target_r_1e9: int


def _blank_reject(c: Candidate, cm: CandidateManifest, params: InstrumentParams,
                  market: MarketData, status: str, diag: _Diag) -> Outcome:
    return Outcome(
        OUTCOME_VERSION, POLICY_ID, c.strategy_id, c.family_id, c.hypothesis_version,
        c.canonical_variant_id, c.origin_id, c.sequence_id, c.event_id,
        c.signal_time, c.expiry_time, 0, 0, _dir_token(c.direction),
        diag.entry_points, diag.stop_points, diag.target_points, diag.target_r_1e9,
        0, 0, 0, 0, 0, 0, 0,
        status, status, "", "false", 0, 0, 0, 0,
        cm.symbol, cm.timeframe, CLOCK_DOMAIN, TIME_AUTHORITY,
        cm.source_data_sha256, cm.journal_sha256, market.market_data_sha256, params.params_sha256,
    )


def run_screening(
    bundle,
    market: MarketData,
    market_manifest: MarketManifest,
    params: InstrumentParams,
    policy_id: str,
    test_end_time_raw: int | None = None,
) -> tuple[str, list[Outcome]]:
    """Certified public entry point. Accepts ONLY a VerifiedCandidateJournalV2
    bundle produced by the journal-binding adapter. It re-derives candidates
    from the bundle's own verified journal bytes and proves every claimed field
    matches the re-derivation, the manifest binding, and the market dataset; any
    discrepancy is REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH with no outcomes.
    An unbound candidate run is structurally impossible on this path.

    Execution mechanics live in _run_screening_core (test-only / internal), which
    the EXECUTION_CORE fixtures (F01-F58) exercise directly."""
    # Lazy import breaks the transport->adapter->simulator cycle at load time.
    from verified_candidate_journal_v2 import (
        JournalBindingError, VerifiedCandidateJournalV2, rederive_and_check,
    )
    from research_journal_transport_v2 import TransportError

    if not isinstance(bundle, VerifiedCandidateJournalV2):
        return (REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH, [])
    try:
        candidates = list(rederive_and_check(bundle, market.market_data_sha256))
    except (JournalBindingError, TransportError):
        return (REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH, [])

    candidate_manifest = CandidateManifest(
        bundle.symbol, bundle.timeframe, bundle.journal_sha256, bundle.source_data_sha256
    )
    return _run_screening_core(
        candidates, candidate_manifest, market, market_manifest, params, policy_id,
        test_end_time_raw,
    )


def _run_screening_core(
    candidates: list[Candidate],
    candidate_manifest: CandidateManifest,
    market: MarketData,
    market_manifest: MarketManifest,
    params: InstrumentParams,
    policy_id: str,
    test_end_time_raw: int | None = None,
) -> tuple[str, list[Outcome]]:
    """Execution-mechanics core (TEST-ONLY / internal — not the certified entry).
    Owns ordering, occupancy, entry, policy-owned geometry, exits, MFE/MAE,
    holding bars, and outcome serialization. Identical to the pre-binding
    behavior so EXECUTION_CORE fixtures keep byte-identical outcome SHAs."""
    status = _dataset_identity(candidates, candidate_manifest, market, market_manifest,
                               params, policy_id)
    if status != RUN_OK:
        return (status, [])

    point_size = params.point_size
    tick_size = params.tick_size
    bars = market.bars
    test_end = bars[-1].time_raw if test_end_time_raw is None else test_end_time_raw

    ordered = sorted(candidates, key=_sort_key)
    busy_until: dict[int, int] = {}
    outcomes: list[Outcome] = []

    for c in ordered:
        # candidate diagnostic geometry must be exactly on the point grid (no silent repair)
        try:
            diag = _Diag(
                _points_exact(c.entry, point_size), _points_exact(c.stop, point_size),
                _points_exact(c.target, point_size), _round_scale(c.target_r * R_SCALE),
            )
        except _OffGrid:
            fallback = _Diag(
                _points_round(c.entry, point_size), _points_round(c.stop, point_size),
                _points_round(c.target, point_size), _round_scale(c.target_r * R_SCALE),
            )
            outcomes.append(_blank_reject(c, candidate_manifest, params, market,
                                          REJECT_CANDIDATE_OFF_GRID, fallback))
            continue

        # occupancy: reject if the family position is still open at signal arrival
        if c.family_id in busy_until and c.signal_time <= busy_until[c.family_id]:
            outcomes.append(_blank_reject(c, candidate_manifest, params, market,
                                          REJECT_FAMILY_OPEN, diag))
            continue

        # first executable bar strictly after signal
        entry_i = next((i for i, b in enumerate(bars) if b.time_raw > c.signal_time), None)
        if entry_i is None:
            outcomes.append(_blank_reject(c, candidate_manifest, params, market,
                                          REJECT_NO_NEXT_EXECUTABLE_BAR, diag))
            continue
        entry_bar = bars[entry_i]
        if entry_bar.time_raw > test_end:
            outcomes.append(_blank_reject(c, candidate_manifest, params, market,
                                          REJECT_ENTRY_AFTER_TEST_END, diag))
            continue
        if entry_bar.time_raw > c.expiry_time:
            outcomes.append(_blank_reject(c, candidate_manifest, params, market,
                                          REJECT_EXPIRED, diag))
            continue

        outcome = _simulate(c, candidate_manifest, market, params, bars, entry_i, test_end,
                            point_size, tick_size, diag)
        outcomes.append(outcome)
        if outcome.status == ACCEPTED:
            busy_until[c.family_id] = outcome.exit_time_raw

    return (RUN_OK, outcomes)


def _dataset_identity(candidates, candidate_manifest, market, market_manifest,
                      params, policy_id) -> str:
    """Complete dataset identity chain. Any mismatch aborts the whole run."""
    if policy_id != POLICY_ID:
        return REJECT_UNSUPPORTED_POLICY
    policy.validate(policy.canonical())
    # market manifest self-consistency vs the market dataset
    if market_manifest.symbol != market.symbol:
        return REJECT_SYMBOL_MISMATCH
    if market_manifest.timeframe != market.timeframe:
        return REJECT_TIMEFRAME_MISMATCH
    if market_manifest.row_count != market.row_count:
        return REJECT_MARKET_HASH_MISMATCH
    if market_manifest.market_data_sha256 != market.market_data_sha256:
        return REJECT_MARKET_HASH_MISMATCH
    if market_manifest.clock_domain != CLOCK_DOMAIN:
        return REJECT_CLOCK_DOMAIN_MISMATCH
    if market_manifest.time_authority_id != TIME_AUTHORITY:
        return REJECT_TIME_AUTHORITY_MISMATCH
    # candidate manifest binding
    if candidate_manifest.symbol != market.symbol:
        return REJECT_SYMBOL_MISMATCH
    if candidate_manifest.timeframe != market.timeframe:
        return REJECT_TIMEFRAME_MISMATCH
    if not _is_sha256(candidate_manifest.journal_sha256):
        return REJECT_JOURNAL_MANIFEST_INVALID
    if not _is_sha256(candidate_manifest.source_data_sha256):
        return REJECT_JOURNAL_MANIFEST_INVALID
    if candidate_manifest.source_data_sha256 != market.market_data_sha256:
        return REJECT_SOURCE_HASH_MISMATCH
    # instrument params binding
    if params.symbol != market.symbol or params.timeframe != market.timeframe:
        return REJECT_INSTRUMENT_PARAMS_MISMATCH
    if not _is_sha256(params.params_sha256):
        return REJECT_INSTRUMENT_PARAMS_MISMATCH
    # every candidate: clock/authority + frozen point-size consistency
    for c in candidates:
        if c.clock_domain != CLOCK_DOMAIN:
            return REJECT_CLOCK_DOMAIN_MISMATCH
        if c.time_authority_id != TIME_AUTHORITY:
            return REJECT_TIME_AUTHORITY_MISMATCH
        if abs(c.entry - c.stop) > 0 and c.stop_distance_points > 0:
            try:
                verify_candidate_point_size(params, abs(c.entry - c.stop), c.stop_distance_points)
            except Exception:
                return REJECT_INSTRUMENT_PARAMS_MISMATCH
    return RUN_OK


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def _simulate(c, cm, market, params, bars, entry_i, test_end, point_size, tick_size,
              diag: _Diag) -> Outcome:
    entry_bar = bars[entry_i]
    direction = c.direction
    min_dist_price = params.minimum_distance_points * point_size

    # policy is the eligibility authority for this accepted entry
    assert policy.candidate_status(False, entry_bar.time_raw, c.expiry_time) == policy.Reject.ACCEPT

    # executable entry: long at ask (open+spread), short at bid (open)
    if direction > 0:
        entry_points = entry_bar.open_points + entry_bar.spread_points
    else:
        entry_points = entry_bar.open_points
    entry_price = entry_points * point_size

    # stop normalization via the certified policy (enforce minimum distance in raw)
    raw_stop = c.stop
    if direction > 0:
        raw_stop = min(raw_stop, entry_price - min_dist_price)
    else:
        raw_stop = max(raw_stop, entry_price + min_dist_price)
    normalized_stop = policy.normalize_stop(direction, raw_stop, entry_price, tick_size)
    normalized_stop_points = _points_exact(normalized_stop, point_size)  # policy output on grid
    initial_risk_points = abs(entry_points - normalized_stop_points)
    if initial_risk_points <= 0:
        return _blank_reject(c, cm, params, market, REJECT_INVALID_GEOMETRY, diag)

    # target reconstruction after executable entry + normalized stop
    risk_price = abs(entry_price - normalized_stop)
    raw_target = entry_price + direction * c.target_r * risk_price
    reconstructed_target = policy.normalize_target(direction, raw_target, entry_price, tick_size)
    reconstructed_target_points = _points_exact(reconstructed_target, point_size)

    stop_price = normalized_stop_points * point_size
    target_price = reconstructed_target_points * point_size

    # exit scan from entry bar through the last eligible bar (<= test_end)
    exit_reason = EXIT_TEST_END
    exit_i = entry_i
    stop_first_collision = False
    for i in range(entry_i, len(bars)):
        b = bars[i]
        if b.time_raw > test_end:
            break
        exit_i = i
        if direction > 0:
            hi = b.high_points * point_size
            lo = b.low_points * point_size
        else:
            hi = (b.high_points + b.spread_points) * point_size
            lo = (b.low_points + b.spread_points) * point_size
        res = policy.resolve_bar(direction, stop_price, target_price, hi, lo)
        if res == policy.Exit.TEST_END:
            continue
        hit_stop = lo <= stop_price if direction > 0 else hi >= stop_price
        hit_target = hi >= target_price if direction > 0 else lo <= target_price
        if res == policy.Exit.STOP:
            exit_reason = EXIT_STOP
            stop_first_collision = bool(hit_stop and hit_target)
        else:
            exit_reason = EXIT_TARGET
        break
    exit_bar = bars[exit_i]

    # exit fill in points (contract gap rules / test-end sides)
    if exit_reason == EXIT_STOP:
        if direction > 0:
            exit_points = min(exit_bar.open_points, normalized_stop_points)
        else:
            exit_points = max(exit_bar.open_points + exit_bar.spread_points, normalized_stop_points)
    elif exit_reason == EXIT_TARGET:
        exit_points = reconstructed_target_points
    else:  # TEST_END
        if direction > 0:
            exit_points = exit_bar.close_points
        else:
            exit_points = exit_bar.close_points + exit_bar.spread_points

    # gross R: policy authority (double) cross-checked against exact integer encoding
    exit_price = exit_points * point_size
    gross_r_policy = policy.gross_r(direction, entry_price, exit_price, stop_price)
    gross_r_1e9 = _round_ratio(direction * (exit_points - entry_points) * R_SCALE, initial_risk_points)
    assert abs(gross_r_1e9 / R_SCALE - gross_r_policy) <= R_TOLERANCE, "gross_r parity"

    # MFE/MAE entry->exit inclusive, exit bar capped at exit price
    fav_points = entry_points
    adv_points = entry_points
    for i in range(entry_i, exit_i + 1):
        b = bars[i]
        if i == exit_i:
            hi_p = lo_p = exit_points
        elif direction > 0:
            hi_p, lo_p = b.high_points, b.low_points
        else:
            hi_p, lo_p = b.high_points + b.spread_points, b.low_points + b.spread_points
        if direction > 0:
            fav_points = max(fav_points, hi_p)
            adv_points = min(adv_points, lo_p)
        else:
            fav_points = min(fav_points, lo_p)
            adv_points = max(adv_points, hi_p)
    if direction > 0:
        mfe_num = (fav_points - entry_points) * R_SCALE
        mae_num = (entry_points - adv_points) * R_SCALE
    else:
        mfe_num = (entry_points - fav_points) * R_SCALE
        mae_num = (adv_points - entry_points) * R_SCALE
    mfe_r_1e9 = _round_ratio(mfe_num, initial_risk_points)
    mae_r_1e9 = _round_ratio(mae_num, initial_risk_points)

    holding_bars = (exit_i - entry_i) + 1

    return Outcome(
        OUTCOME_VERSION, POLICY_ID, c.strategy_id, c.family_id, c.hypothesis_version,
        c.canonical_variant_id, c.origin_id, c.sequence_id, c.event_id,
        c.signal_time, c.expiry_time, entry_bar.time_raw, exit_bar.time_raw, _dir_token(direction),
        diag.entry_points, diag.stop_points, diag.target_points, diag.target_r_1e9,
        entry_points, normalized_stop_points, reconstructed_target_points, exit_points,
        initial_risk_points, entry_bar.spread_points, exit_bar.spread_points,
        ACCEPTED, "", exit_reason, "true" if stop_first_collision else "false",
        gross_r_1e9, mfe_r_1e9, mae_r_1e9, holding_bars,
        cm.symbol, cm.timeframe, CLOCK_DOMAIN, TIME_AUTHORITY,
        cm.source_data_sha256, cm.journal_sha256, market.market_data_sha256, params.params_sha256,
    )


# --------------------------------------------------------------------------
# Canonical outcome serialization (integer/string/bool -> byte-exact hashable)
# --------------------------------------------------------------------------
def _canonical_record(fields: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="", doublequote=True).writerow(fields)
    return stream.getvalue()


def outcome_fields(o: Outcome) -> list[str]:
    return [str(getattr(o, name)) for name in OUTCOME_FIELDS]


def outcomes_document(run_status: str, outcomes: list[Outcome]) -> bytes:
    header = "run_status," + ",".join(OUTCOME_FIELDS)
    lines = [header]
    for o in outcomes:
        lines.append(_canonical_record([run_status] + outcome_fields(o)))
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def outcomes_sha256(run_status: str, outcomes: list[Outcome]) -> str:
    return hashlib.sha256(outcomes_document(run_status, outcomes)).hexdigest()
