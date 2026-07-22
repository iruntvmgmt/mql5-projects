# Eligibility diagnostics — 2026-07-22

## Change

BO, FBO, TP, and MR now journal the first failed eligibility predicate instead
of the generic `not eligible` message. Numeric threshold context is retained in
the journal, while `acceptance_funnel_report.py` groups those messages into
stable research categories.

## Verification

- MetaEditor compile through the documented Wine `/Unix` route: **0 errors,
  0 warnings**.
- Combined Shadow regression: **65 passed, 0 failed**; 22,080 ticks and 1,104
  bars; no broker orders transmitted.
- Combined all-strategy true-tick diagnostic: XAUUSD M5, 2026-06-22,
  417,423 ticks and 276 bars. The exact SignalJournal byte range is
  `3,350,692..3,920,024`, containing **880 rows** (220 per strategy).

## Result

The first-failure distribution identifies different reachability constraints:

- **BO:** preceding compression dominates (176/220), followed by HTF direction
  or alignment. Stop/risk is not the reason BO is absent in this window.
- **TP:** the market is usually not classified as directional (178/220).
  Directional efficiency is the second constraint (28/220). TP never reaches
  central risk here.
- **MR:** most strategy-stage failures occur after eligibility because VWAP
  deviation is insufficient (158/220); non-balanced structure blocks 46/220.
- **FBO:** absence of a failed-breakout/reclaim event dominates (182/220).
  Five accepted trades and two stop-too-far risk rejects remain.

These are ordered first-failure counts, not independent predicate frequencies:
later predicates are observable only when earlier predicates pass. The result
supports targeted eligibility experiments, not global filter relaxation.
