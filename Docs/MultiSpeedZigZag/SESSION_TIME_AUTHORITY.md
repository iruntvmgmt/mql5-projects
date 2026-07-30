# Session Time Authority

Authority ID: `MSZZ_TIME_AUTH_C1`. Selected model: **C — explicit broker offset schedule supplied and committed per test dataset**.

Runtime must not consult the host timezone database. A dataset is invalid for session research unless its manifest names a committed transition-table SHA-256 covering every timestamp.

## Time model

All journal timestamps are UTC. Each source broker timestamp is converted using a half-open offset row:

```text
utc = broker_time - broker_utc_offset_seconds
```

US Eastern is derived from a committed half-open transition row, never from the operating system:

```text
eastern = utc + eastern_utc_offset_seconds
```

The dataset transition file contains `start_utc`, `end_utc`, broker offset, Eastern offset, rule source/version and row ID. Intervals must be contiguous, nonoverlapping, and cover the entire dataset. Broker DST is not inferred from US or European DST.

## Frozen SSR windows

These windows were selected as clock/economic definitions without inspecting performance:

- Asian range: `[00:00, 08:00)` UTC. Bars whose **open UTC time** lies in the interval construct the range. The range freezes at 08:00 UTC.
- London sweep eligibility: `[08:00, 12:00)` UTC.
- New York sweep eligibility: `[08:30, 12:00)` US Eastern, converted per committed transition row.
- No other time is SSR-eligible.

Session IDs are `ASIA_RANGE`, `LONDON_SWEEP`, `NEW_YORK_SWEEP`, or `INELIGIBLE`, suffixed by authority ID and the UTC trading-day date. If London and New York overlap, the event receives both typed eligibility flags and the primary session is the window whose opening time was most recent; ties resolve `LONDON_SWEEP` before `NEW_YORK_SWEEP`.

The SSR trading day is the UTC calendar day beginning 00:00. Asian range, resets and range IDs use that day. A lifecycle cannot carry across 00:00 UTC; it terminates `DAY_BOUNDARY` and requires the new day’s range to freeze.

## DST and holidays

Eastern transition instants come from a generated IANA `America/New_York` table whose tzdb release is recorded, then are committed as data. Broker offsets are supplied from broker/server evidence, not inferred. Generated values become authoritative only after review and hashing.

Holidays do not alter clock windows. Missing bars merely reduce observations; no synthetic bars are created. A minimum completeness rule must be frozen in the SSR range specification before implementation. Holiday labels may be metadata but cannot silently suppress a day.

Missing, ambiguous, overlapping, noncontiguous or unhashed transition data causes `TIME_AUTHORITY_UNAVAILABLE` and fails closed for every affected candidate/day. Ambiguous broker local timestamps during an offset transition are invalid unless the source data includes an unambiguous UTC mapping.

## Reproducibility tests

Tests cover both sides and exact instants of every offset/window/day boundary, spring/fall Eastern changes, broker offset changes independent of Eastern, overlap precedence, missing rows, gaps/overlaps, ambiguous local time, holiday with sparse bars, and identical UTC/session IDs across Python and MQL5.
