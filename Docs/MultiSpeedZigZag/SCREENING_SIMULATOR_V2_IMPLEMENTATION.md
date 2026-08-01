# Screening Simulator V2 — Implementation

Family-neutral standalone historical screening simulator built on the certified
ResearchCandidateSchemaV2, JournalTransportV2, and ScreeningExecutionPolicyV2.
This document freezes the simulator input sub-layers and (once implemented) the
simulator itself. It does not authorize any family and does not touch a family
generator, production path, or P4.

Status: **CORRECTION_IN_PROGRESS** — market/instrument transport, simulator
loop, and the certification-hardening correction (verified journal binding,
UTF-8 ordering, fail-closed evidence) are implemented; final certification is
pending the full regression + exact P4 (see the status file).

## Frozen decisions (user-approved 2026-07-30)

The certified execution contract resolved OHLC-side representation (bid-bar
model) but did **not** freeze (B1) the market-bar/spread byte format the
`source_data_sha256` covers, or (B2) the broker instrument geometry required by
`NormalizeStop`. Those were frozen here with explicit user approval, plus the
additive simulator taxonomy (R3), candidate ordering (R4), and exit-fill
geometry (R5). See `CLAUDE_MSZZ_SCREENING_SIMULATOR_HANDOFF.md` §6-9.

### Manifest / params reconciliation

The B1 answer listed instrument geometry inside the market manifest while the
B2 answer carved it into a dedicated instrument-params file and called that the
"cleanest dependency boundary." Carrying the same hash-verified derivation in
two files creates a consistency-failure surface, so instrument geometry lives
in **exactly one** place — `MSZZ_SCREENING_INSTRUMENT_PARAMS_V2` — and the
market manifest is limited to market-data descriptors. The certified
JournalTransportV2 manifest is not modified.

## Canonical byte conventions (identical to the certified research transport)

- UTF-8, no BOM.
- CRLF after every record including the final one.
- Header line is a plain unquoted comma list; every data field is double-quoted,
  embedded quotes doubled.
- Integers: `-?(0|[1-9][0-9]*)`. Decimals: `-?(0|[1-9][0-9]*)\.[0-9]{16}`
  (`DoubleToString(v,16)` == Python `f"{v:.16f}"`).
- Every accepted record must reserialize byte-for-byte. No alternate RFC-4180
  spelling is accepted and normalized; nothing is repaired, inferred,
  forward-filled, or interpolated.
- SHA-256 is over the exact document bytes, lowercase hex.

## Real-data-safe integer representation (resolved)

An earlier draft stored OHLC as 16-fractional-digit decimals (mirroring the
research transport). That is unsafe for real prices: even `0.01` is not
binary-exact, and a large-magnitude non-representable price (e.g. `100.20`)
pushes past ~15-17 significant digits, so `DoubleToString(v,16)` (MQL5) and
`f"{v:.16f}"` (Python) can disagree on the trailing digits. The MQL5 runtime
parity gate caught this directly (`TEST_SUMMARY tests=29 failures=7`).

The transport is therefore **integer**:

- OHLC are signed canonical integer **point counts** (`price = points *
  point_size`); the finest quote grid, so ordinary decimal prices are exact.
- Spread is an integer number of points.
- Instrument sizes are integer **1e-8 units** (`point_size_1e8`,
  `tick_size_1e8`); `point_size = point_size_1e8 / 1e8`.
- Grid alignment is an exact integer check (`tick_size_1e8 % point_size_1e8 == 0`);
  the producer converts a decimal price to points and rejects any off-grid value.
- Nothing in the canonical transport or the SHA-256 uses float formatting.

Precisely:

- canonical transport bytes are integer-exact;
- hashes and parser parity do not depend on floating-point formatting;
- reconstructed runtime prices (`points * point_size`) may still be
  non-binary-exact — e.g. `0.01` is not exactly representable — so the
  reconstructed decimal value is not claimed to be exact;
- MQL5/Python numerical parity on reconstructed prices and derived metrics is
  enforced **after tick normalization**, using the frozen `1e-9` comparison
  tolerance and identical operation order in both languages.

## MSZZ_SCREENING_MARKET_DATA_V2

Header:

```text
market_data_version,symbol,timeframe,clock_domain,time_authority_id,time_raw,open_points,high_points,low_points,close_points,spread_points
```

Rules: `market_data_version` constant; `symbol`/`timeframe` identical on every
row; `clock_domain` = `BROKER_SERVER_RAW`; `time_authority_id` =
`MSZZ_TIME_RAW_BROKER_V1`; `time_raw` strictly increasing, unique, positive.
`open/high/low/close_points` are integer **bid** point counts, all `> 0`, with
`high >= max(open,close)`, `low <= min(open,close)`, `high >= low`;
`spread_points` a nonnegative integer. Bid price = `points * point_size`; ask =
`(points + spread_points) * point_size`. Any missing, malformed, noncanonical,
duplicate, or non-monotonic row fails the whole dataset. The candidate manifest's
`source_data_sha256` is the SHA-256 of these exact bytes.

## MSZZ_SCREENING_MARKET_MANIFEST_V2

Header:

```text
manifest_version,market_data_version,symbol,timeframe,clock_domain,time_authority_id,row_count,market_data_sha256
```

`market_data_sha256` must equal the market CSV hash; `symbol`, `timeframe`,
`clock_domain`, `time_authority_id`, and `row_count` must match the parsed
market dataset. A separate reject reason distinguishes a market-manifest hash
mismatch (`MARKET_HASH_MISMATCH`) from the candidate manifest's
`source_data_sha256` mismatch (`SOURCE_HASH_MISMATCH`); both hash the same bytes
and both must agree.

## MSZZ_SCREENING_INSTRUMENT_PARAMS_V2

Header:

```text
params_version,symbol,timeframe,point_size_1e8,tick_size_1e8,stops_level_points,freeze_level_points,minimum_distance_points
```

`point_size_1e8`, `tick_size_1e8` positive integers (price size in 1e-8 units);
`stops_level_points`, `freeze_level_points`, `minimum_distance_points`
nonnegative integers; `minimum_distance_points = max(stops_level_points,
freeze_level_points)` and the stored value must match that derivation exactly;
grid compatibility is the exact integer check `tick_size_1e8 % point_size_1e8 ==
0`. `point_size = point_size_1e8 / 1e8`, `tick_size = tick_size_1e8 / 1e8`. At
simulation time the reconstructed `point_size` is cross-checked against candidate
`|entry-stop| / stop_distance_points` within tolerance. No live `SymbolInfo*`
value, default, or inference is ever used. `minimum_distance_price =
minimum_distance_points * point_size`. `params_sha256` is the SHA-256 of the
exact file bytes and participates in the simulator run identity.

## Candidate iteration order (frozen)

`signal_time` ascending, then `family_id` ascending, then `event_id` bytewise
ascending, then `sequence_id` bytewise ascending. Identical stable comparator in
MQL5 and Python; string comparison is bytewise/canonical UTF-8, not locale
aware. Duplicate `event_id`/`sequence_id` already fail at JournalTransportV2 and
are never deduplicated or repaired here.

## Implementations (commit 1)

- `Include/MultiSpeedZigZag/Research/ScreeningMarketV2.mqh`
- `Tools/SixFamilyRecovery/ScreeningSimulatorV2/screening_market_v2.py`
- `Tests/MultiSpeedZigZag/Test_MSZZ_ScreeningMarketV2.mq5`
- `Tools/SixFamilyRecovery/ScreeningSimulatorV2/test_screening_market_v2.py`
- Shared fixtures + `make_market_fixtures.py` + `cross_language_market_hashes.csv`

## Simulator loop and outcome record (commit 2)

Implemented. `MSZZ_SCREENING_OUTCOME_V2`, the additive status/rejection taxonomy,
next-executable-bar entry, bid/ask construction, gap-fill geometry,
one-position-per-family occupancy, stop-first collisions, MFE/MAE, holding-bar
convention and test-end closure, with full MQL5/Python outcome parity.

## Certification-hardening correction

### Verified candidate→journal binding

The certified public entry accepts **only** a transport-produced verified
bundle:
- Python `verified_candidate_journal_v2.VerifiedCandidateJournalV2` /
  `screening_simulator_v2.run_screening(bundle, ...)`;
- MQL5 `MSZZVerifiedScreeningJournalV2` /
  `CMSZZScreeningJournalBindingV2::RunScreening(bundle, ...)`.

The adapter reconstructs the simulator candidate projection from the exact
canonical journal bytes verified by JournalTransportV2 (additive accessor
`reconstruct_verified_rows` / `ReconstructVerifiedRecords`; the certified
`validate_journal_bytes` payload is unchanged). The public entry **re-derives**
candidates from the bundle's own journal bytes and proves journal SHA,
projection SHA, row count, manifest binding, market binding, and candidate
identity before executing; any discrepancy is
`REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH` with zero outcomes. Ownership: Python
frozen dataclasses/tuples; MQL5 bundle-owned arrays copied locally after
verification. Precedence: binding failures win over the market-identity tokens,
which the execution core still returns for otherwise-valid re-derived data.

**Projection** `MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2` preserves the
journal-owned candidate evidence verbatim (17 fields incl. both `target` and
`target_r`, no recomputation); its SHA is byte-identical across languages and
recorded alongside the journal SHA (the mutation guard).

### Access boundary

The MQL5 execution core is private `RunScreeningCore`; arbitrary-candidate
access exists only behind compile-time gates
(`MSZZ_SCREENING_BOUND_ADAPTER_ACCESS` for the certified adapter,
`MSZZ_SCREENING_FIXTURE_ACCESS` for fixture builds). An ordinary research
include exposes only the bundle-only entry — proven by a negative compile probe.
Python's core is the module-private `_run_screening_core`.

### Canonical ID ordering

Candidate order is `signal_time`, `family_id`, `event_id`, `sequence_id`, the
last two by explicit **UTF-8 bytewise** comparison (schema IDs are printable
UTF-8). MQL5 `Utf8Compare` replaces `StringCompare`; parity is proven including
the U+1F600 vs U+F900 case where UTF-16 code-unit order diverges.

### Fixture groups, counts, and fail-closed evidence

- `EXECUTION_CORE` F01–F58, `JOURNAL_BINDING` JB01–JB24, `ORDERING` OR01–OR13 —
  total **95**. Three fail-closed MQL5 harnesses each emit exactly one
  `FIXTURE_RESULT [id] PASS|FAIL` marker per fixture plus `HARNESS_FAILURE`
  diagnostics, and a strict summary
  (`... f=.. jb=.. or=.. markers=.. fixture_failures=.. harness_failures=.. cert_run=..`).
  All three share one content-derived `cert_run` id.
- `collect_mql5_results.py` (`MSZZ_MQL5_RESULT_COLLECTOR_V2`) aggregates the
  three latest suite runs, requiring the shared cert run, exact marker ID sets,
  zero failures/harness/fixture failures, atomic output — never PASS-by-absence.
- `make_coverage_v2.py` (`MSZZ_SCREENING_COVERAGE_V2`) writes coverage only when
  the Python suites pass and the validated MQL results match the inventory
  exactly, with provenance (cert run, source-log SHA, fixture-source SHAs).

### Policy tick-boundary helpers

Policy rounding uses explicit `_floor_ticks` / `_ceil_ticks` (the removed
`_ticks` helper is gone); the epsilon sign is hard-bound to the direction.
