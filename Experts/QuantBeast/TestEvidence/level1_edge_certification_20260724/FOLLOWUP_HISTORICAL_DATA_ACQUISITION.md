# Follow-up ticket: independent historical XAUUSD tick data acquisition

**Status: proposed, not started. Not part of the Level-1 Edge Certification
Sprint's verdict** (see `TIER_C_REAL_TICK_TEST.md`) -- this is a separate
engineering/research effort, tracked here so it isn't lost, not mixed into
the current sprint's evidence or conclusions.

## Problem this would solve

This project's real-tick historical data is only as deep as Coinexx-Demo's
own retention window -- confirmed empirically (Level-1 Sprint, Stage 3) at
~7 weeks back from "now" (`real ticks begin from 2026.06.05`), of which
only ~10 clean trading days survive after excluding windows this project
has already touched (`RESEARCH_TRIAL_LEDGER.md`). This makes real-tick
certification (Tier C) structurally underpowered no matter how the
available days are used, and the number gets *worse*, not better, as more
of this project's own work touches recent calendar dates going forward.
Bar-level history (`get_chart_history`) goes back to 2018, but that
resolution cannot support tick-accurate spread/slippage/fill simulation,
and Model=1 generated-tick simulation was found unreliable as a proxy
(Tier B, `MODEL1_PROXY_UNRELIABLE`).

## Proposed scope

Evaluate importing an independent, high-quality XAUUSD bid/ask tick
dataset (e.g. a commercial or research-grade tick data vendor) into MT5 as
a **custom symbol**, so the Strategy Tester can run genuine Model=4-style
tick-accurate backtests over a multi-year history independent of this
broker's retention limits.

## Explicit prerequisites before this touches the certification sprint

Per instruction, do **not** mix an externally-sourced dataset into the
current or any future certification pass until all of the following are
validated and documented:

1. **Provenance**: where the data comes from, its licensing terms, and
   whether it's redistributable/usable for this purpose at all.
2. **Symbol economics**: contract size, point/tick value, minimum
   stop/freeze levels, and how they compare to Coinexx's actual XAUUSD
   contract -- a custom symbol with different economics would silently
   invalidate any position-sizing/risk-percent math that assumes Coinexx's
   values.
3. **Timezone**: the dataset's timestamp convention (broker time, UTC,
   exchange time) must be reconciled against `InpBrokerUTCOffsetHours`/
   `InpBrokerIsDST` and the session-boundary logic (`SessionEngine.mqh`) --
   a timezone mismatch would silently misclassify sessions and corrupt
   every session-conditioned strategy check.
4. **Spread**: real historical bid/ask spread behavior (not a synthetic
   constant) must be present and validated against Coinexx's own typical
   spread (`InpMaxSpreadPoints=20` and the broker-diagnostics-logged
   typical spread) -- an unrealistically tight or wide spread would bias
   entry/exit economics in either direction.
5. **Coinexx mapping**: confirm the imported symbol's price level and
   quoting convention (digits, point size) match `XAUUSD` on Coinexx-Demo
   closely enough that strategy thresholds tuned against this project's
   existing evidence remain meaningful, or explicitly re-derive them if
   not.

## Suggested next step (not started)

A bounded, time-boxed research pass (mirroring this sprint's own Phase-0
diagnostic methodology) to: identify 1-2 candidate data sources, confirm
MT5 custom-symbol tick import mechanics work at all in this Wine
environment, and produce a short go/no-go writeup addressing the five
prerequisites above -- before committing to a full purchase/import/
validation cycle.

## Explicitly not authorized by this note

This ticket's existence is not authorization to purchase, download, or
import any dataset. It is a scoped placeholder so the idea and its real
prerequisites are recorded, per the user's explicit instruction to keep it
separate from and not mixed into the current sprint's evidence or
verdict.
