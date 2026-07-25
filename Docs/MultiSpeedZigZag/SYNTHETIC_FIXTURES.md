# Synthetic Structural Fixtures

These fixtures are the canonical deterministic test cases for the ATR ZigZag engine. They are intentionally simple and independent of broker history.

## Fixture format

Each fixture defines:

- ordered OHLC bars
- fixed ATR assumption or precomputed ATR series
- speed multiplier
- minimum bars between pivots
- expected candidate-extreme updates
- expected confirmed pivots
- expected confirmation bars
- expected structure labels
- expected line and breakout events

The first implementation may use a helper that injects precomputed ATR values to isolate pivot logic from ATR calculation. A separate ATR fixture set must test true-range and rolling-average behavior.

## F01 — Single bullish leg then bearish reversal

Purpose: confirm one high pivot only after reversal threshold is reached.

- Fixed threshold: 2.0
- High sequence: 10, 11, 13, 14, 13, 12
- Low sequence: 9, 10, 11, 12, 11, 10

Expected:

- Candidate high moves to 14.
- No confirmed high at the bar where 14 occurs.
- High at 14 confirms only when subsequent low reaches 12 or lower.
- `pivot_time` equals the 14-high bar.
- `confirmed_time` equals the first qualifying reversal bar.

## F02 — Candidate high replacement

Purpose: prove an unconfirmed extreme can move without creating multiple pivots.

- Threshold: 2.0
- Highs: 10, 12, 13, 15, 14, 13
- Lows remain above reversal threshold until after 15.

Expected:

- Candidate high progresses 12 → 13 → 15.
- Only 15 becomes the confirmed pivot.
- Earlier candidates have no stable pivot IDs.

## F03 — Equal highs

Purpose: define tie handling.

- Threshold: 2.0
- Highs: 10, 13, 13, 12, 11

Canonical rule:

- Latest equal extreme replaces earlier equal extreme because the current engine uses `>=` for high updates.
- Confirmed pivot time is the second 13 bar.

Any change to first-equal-wins requires a decision-log entry and fixture update.

## F04 — Equal lows

Mirror of F03.

Canonical rule:

- Latest equal low replaces earlier equal low because the current engine uses `<=`.

## F05 — Minimum bars between pivots

Purpose: verify consolidation filter.

- Threshold: 1.0
- Construct alternating reversals every bar.
- `min_bars_between = 3`.

Expected:

- A reversal occurring fewer than three pivot-index bars after the previous pivot cannot confirm a new pivot.
- Candidate leg state continues until a valid spacing and reversal exist.

## F06 — HH/LH classification

Expected high sequence:

- First high: UNKNOWN
- Second high above first: HH
- Third high below second: LH

Classification uses confirmed same-kind pivots only.

## F07 — HL/LL classification

Expected low sequence:

- First low: UNKNOWN
- Second low above first: HL
- Third low below second: LL

## F08 — Projected resistance breakout

Purpose: verify last-two-high geometry and close-cross semantics.

- Two confirmed descending highs define resistance.
- Previous close is at or below previous-bar projected resistance.
- Current close is strictly above current projected resistance.

Expected:

- One bullish breakout event on current closed bar.
- Event ID is stable across rebuilds.
- No second event on the following bar if price remains above the line without a new cross.

## F09 — Wick-only line violation

- High trades above resistance.
- Close remains below resistance.

Expected under milestone-1 behavior:

- No bullish breakout.

## F10 — Forming-bar exclusion

Purpose: prove that a temporary intrabar breach does not generate a closed-bar event.

Expected:

- Rebuild count excludes the current forming bar.
- Signal timestamp cannot reference the current chart bar.

## F11 — History extension stability

Run engine on bars 1–100, then on bars 1–120 where bars 101–120 occur later.

Expected:

- Every pivot confirmed by bar 100 retains price, pivot time, confirmation time, label, and ID.
- Newer bars may add pivots but cannot rewrite prior confirmed pivots.

## F12 — Data-gap behavior

Introduce a time gap while preserving ordered bars.

Expected:

- Pivot logic remains bar-sequential.
- Trendline projection uses elapsed seconds under current geometry, so the time gap changes projected line value.
- This behavior must be documented and compared with Pine's bar-index projection. If Pine uses bar index, parity may require a bar-index geometry mode.

## Critical parity warning

The current MQL5 engine projects by elapsed seconds. Pine trendlines commonly use bar indices. Irregular sessions or missing bars can therefore produce different line values. The parity harness must explicitly test this and may force a design change to bar-index-based geometry.