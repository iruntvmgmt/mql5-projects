# Screening Simulator V2 — Implementation

Family-neutral standalone historical screening simulator built on the certified
ResearchCandidateSchemaV2, JournalTransportV2, and ScreeningExecutionPolicyV2.
This document freezes the simulator input sub-layers and (once implemented) the
simulator itself. It does not authorize any family and does not touch a family
generator, production path, or P4.

Status: **market/instrument transport sub-layer frozen (commit 1)**; simulator
loop pending (commit 2).

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

## Known limitation — decimal precision vs. cross-language parity

The 16-fractional-digit canonical decimal (inherited from the certified research
transport) is only guaranteed byte-identical between `DoubleToString(v,16)`
(MQL5) and `f"{v:.16f}"` (Python) when 16 fractional digits stay within IEEE-754
double precision. For a small magnitude such as `0.01` that holds; for a
large-magnitude price such as `100.25` it holds only when the value is exactly
representable in binary (a multiple of a negative power of two). A
non-representable large-magnitude price (e.g. `100.20`) pushes past ~15-17
significant digits and the two formatters can disagree on the trailing noise
digits, which the fail-closed canonical-reserialization check then rejects.

The committed fixtures therefore use exactly-representable OHLC values (multiples
of 0.25). This surfaced during MQL5 runtime parity (`TEST_SUMMARY tests=29
failures=7` before the fix) and is exactly the kind of divergence the
cross-language byte-parity gate exists to catch. Downstream real-data producers
must emit market bars already on the broker tick grid; if a future dataset needs
non-representable prices, the canonical decimal precision must be reconsidered
(a follow-up item, not a blocker for this sublayer).

## MSZZ_SCREENING_MARKET_DATA_V2

Header:

```text
market_data_version,symbol,timeframe,clock_domain,time_authority_id,time_raw,open_bid,high_bid,low_bid,close_bid,spread_points
```

Rules: `market_data_version` constant; `symbol`/`timeframe` identical on every
row; `clock_domain` = `BROKER_SERVER_RAW`; `time_authority_id` =
`MSZZ_TIME_RAW_BROKER_V1`; `time_raw` strictly increasing, unique, positive;
OHLC are **bid** prices, finite and positive, with `high >= max(open,close)`,
`low <= min(open,close)`, `high >= low`; `spread_points` a nonnegative integer.
Ask is derived as `ask = bid + spread_points * point_size`. Any missing,
malformed, noncanonical, duplicate, or non-monotonic row fails the whole
dataset. `source_data_sha256` is the SHA-256 of these exact bytes.

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
params_version,symbol,timeframe,point_size,tick_size,stops_level_points,freeze_level_points,minimum_distance_points
```

`point_size`, `tick_size` finite and positive; `stops_level_points`,
`freeze_level_points`, `minimum_distance_points` nonnegative integers;
`minimum_distance_points = max(stops_level_points, freeze_level_points)` and the
stored value must match that derivation exactly; `tick_size/point_size` must be
a positive integer multiple within the frozen grid tolerance. At simulation
time the frozen `point_size` is cross-checked against candidate
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

Pending. Will freeze `MSZZ_SCREENING_OUTCOME_V2`, the additive status/rejection
taxonomy (R3), next-executable-bar entry, bid/ask construction, gap-fill
geometry (R5), one-position-per-family occupancy, stop-first collisions,
MFE/MAE, holding-bar convention, and test-end closure, with full MQL5/Python
outcome parity.
