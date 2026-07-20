# Organic true-tick multi-window coverage (2026-07-19)

## Purpose

HANDOFF "Next task" item 3 remainder: broaden organic true-tick coverage beyond
the already-tested mid-June/early-July 2026 span (`organic_true_ticks_20260716`,
`organic_true_ticks_20260718`, `performance_readiness_20260716`) to test whether
BO/TP/MR can reach ACCEPTED signal state in windows with a visibly different
market regime. Read-only evidence gathering; no source, parameter, or preset
changes were made in this task per HANDOFF's "do not touch" list for this item.

## Preliminary analysis (before running new windows)

Re-examined the existing `performance_readiness_20260716` isolated per-strategy
SignalJournal CSVs (BO/TP/MR each run alone, `InpFBO_Enabled=false` etc., train
window 2026.06.22-06.26, holdout window 2026.06.29-07.03):

- TP: 938/940 (train) and 1124/1130 (holdout) rejections are the generic
  "TP: not eligible". Only a handful ever reach trigger evaluation; none reach
  the risk stage.
- MR: 882/940 and 1094/1130 rejections are "MR: not eligible", same pattern.
- BO: ~88% "Breakout: not eligible", but the remaining ~12% DID pass eligibility
  and reach a trigger, and a handful reached the risk stage only to be rejected
  with `Risk: Stop too far: <1000-5081> > 1000` (`InpMaxStopPoints=1000`). This
  is a real, previously-uncharacterized finding from the ISOLATED BO-only test:
  when BO fires, its structural+ATR stop calculation for XAUUSD can be several
  times wider than the fixed 1000-point risk cap.

## Window selection

Selected from actual XAUUSD D1 history (`get_chart_history`, 2026-01-01 to
2026-07-17), choosing regimes visibly distinct from the already-tested
2026-06-15 to 2026-07-03 span:

| Window | Dates | Target strategy | Regime rationale |
|---|---|---|---|
| A | 2026.02.16-02.20 | BO | Tight Feb 19 (67-pt range) followed by a Feb 20 breakout close near the day high; compression-then-expansion without shock/extreme volatility |
| B | 2026.04.20-04.24 | MR | Choppy, alternating up/down days, mild net weekly move; balanced/non-trending |
| C | 2026.03.30-04.07 | TP | Impulse up (Mar 31-Apr 1), pullback (Apr 2/6), resumption (Apr 7); impulse-pullback-continuation shape |

All three runs: XAUUSD M5, Model=4 (real ticks), all 4 strategies enabled,
self-tests disabled, `InpEnableSignalJournal/OrderJournal/TradeJournal=true`,
`InpJournalTesterPrefix=true` (routes journals to
`Common/Files/QuantBeast/Tester/` to avoid the live-terminal file-lock issue
fixed 2026-07-19), no persistence/global vars, Shadow mode (`InpMode=1`), no
live/Challenge acknowledgement.

Tester configs preserved in this folder:
`QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260216_20260220.ini`,
`QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260420_20260424.ini`,
`QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260330_20260407.ini`.

## Results

All three runs completed normally (`OnTester result 0`, final balance
10000.00 USD unchanged, normal tester footer, no broker orders transmitted —
confirmed via local Tester Agent log
`Tester/Agent-127.0.0.1-3000/logs/20260719.log`, since the native tester MCP
returned the known-unreliable `job_id: 0` for all three runs per AGENTS.md).

| Window | Ticks/bars | Test duration | FBO | BO | TP | MR |
|---|---|---|---|---|---|---|
| A (Feb 16-20) | 1,030,228 / 1,074 | 0:09:56 | 1 ACCEPTED, 4 Shadow trades | 110 REJECTED, 0 accepted | 110 REJECTED, 0 accepted | 110 REJECTED, 0 accepted |
| B (Apr 20-24) | 1,492,019 / 1,104 | 0:15:12 | 1 ACCEPTED, 9 Shadow trades | 108 REJECTED, 0 accepted | 108 REJECTED, 0 accepted | 107 REJECTED, 0 accepted |
| C (Mar 30-Apr 7) | 2,005,023 / 1,379 | 0:21:32 | 1 ACCEPTED, 2 Shadow trades | 110 REJECTED, 0 accepted | 108 REJECTED, 0 accepted | 108 REJECTED, 0 accepted |

(Counts are SignalJournal.csv rows matching each window's date range via
`search_regex` anchored on the row's leading timestamp, e.g.
`^2026\.02\.(1[6-9]|20)`; per-strategy status tallied from columns 4 (Strategy)
and 9 (Status). Full accepted rows below; full row sets remain in the shared,
non-source `Common/Files/QuantBeast/Tester/SignalJournal.csv` /
`OrderJournal.csv` / `TradeJournal.csv`, distinguishable by these three windows'
non-overlapping date ranges since the files are cumulative across runs.)

**Rejection reason breakdown (all three windows, BO/TP/MR):** 97-100% of all
BO/TP/MR rows are the generic `<Strategy>: not eligible` — i.e. the eligibility
gate itself (compression/ATR-percentile for BO, trend/persistence for TP,
balanced-regime/deviation for MR) essentially never returns true in any of
these three additional real-market windows, regardless of the regime chosen.
A small remainder (1-3 rows per strategy per window) reaches trigger-level
rejections (e.g. `TP Long: not uptrend`, `MR Short: insufficient deviation,
sd=-0.65`, `FBO Short: no upside failed auction`), consistent with prior
evidence.

**Correction to a mid-session finding:** during this session a `Signal
rejected by risk engine: Stop too far` warning pattern was observed repeatedly
in the Experts-tab log during all three combined-strategy runs (up to 15 times
in one run) and was initially assumed to reflect BO's stop-distance problem
recurring here too. Checking the SignalJournal CSV (which preserves
`strategy_id` on the arbitration winner per
`QuantBeastEA.mq5:1254-1256`) shows this is NOT reliably true: window A
attributed its 4 journaled stop-too-far rows to FBO, window B attributed 2 to
BO, and window C's 435 sampled rows contained zero stop-too-far rows despite
~15 Experts-log warnings for that run. The SignalJournal row count for this
reason is measurably smaller than the live Experts-log warning count in every
combined run, suggesting a duplicate/cooldown suppression at the journal-write
level that the live `QBLogWarn` call is not subject to. **This is a
journal-fidelity gap, not a strategy-attribution finding** — do not treat
combined-run "Stop too far" attribution as reliable; the isolated
single-strategy BO test (`performance_readiness_20260716`) remains the clean
evidence for BO's own stop-distance problem.

## Accepted rows (verbatim, 1 per window, all FBO)

```
2026.02.16 09:15:00,XAUUSD,1,FBO,SELL,FBO_SELL_1771233300,200,210,ACCEPTED,0,FBO Short: reclaim below 4997.78 targetMidR=1.00 targetVWAPR=1.50,2,1,3,22.0,440.9,4996.39000,5002.24000,4987.29000,1.56,0.625
2026.04.20 06:20:00,XAUUSD,1,FBO,BUY,FBO_BUY_1776666000,201,210,ACCEPTED,0,FBO Long: reclaim above 4790.50 targetMidR=1.00 targetVWAPR=1.50,3,0,1,19.0,416.6,4791.93000,4784.72000,4802.74000,1.50,0.681
2026.03.30 13:40:00,XAUUSD,1,FBO,SELL,FBO_SELL_1774878000,200,210,ACCEPTED,0,FBO Short: reclaim below 4533.55 targetMidR=1.00 targetVWAPR=1.50,2,0,6,17.0,567.9,4531.27000,4539.38000,4519.11000,1.50,0.688
```

OrderJournal confirms 24 total orders across all three windows, all tagged
`QB_FBO_SHADOW` — zero BO/TP/MR orders. TradeJournal shows the corresponding
closed FBO trades (mix of `EXIT_STOP_LOSS`/`EXIT_TARGET_HIT`).

## Finding

Across all 6 distinct organic windows now tested (2 isolated single-strategy
windows for BO/TP/MR each, plus the mid-June/early-July combined windows, plus
these 3 new combined windows spanning Feb/Mar/Apr 2026 in visibly different
regimes), **BO, TP, and MR have never reached ACCEPTED signal state in a
combined (all-4-strategies) run; only FBO has.** The blocker is overwhelmingly
the eligibility gate itself, not window selection — broadening window
coverage further is unlikely by itself to produce different results. Per
HANDOFF's "do not touch" list, no eligibility/regime parameters were changed
in this task. Whether the eligibility gates are miscalibrated (too strict) or
correctly modeling genuinely rare conditions is unresolved and requires a
dedicated strategy-parameter review task, out of scope here.

## Compile / build state

No source changed in this task. Build unchanged from prior session:
- Source SHA-256: `7ac32f8db9c8b16d2fe797ad890f6403ae7877ca38a7fdef24b0c5c5ab797ec9`
- EX5 SHA-256: `cb91e10507047433646c6927a17c7bf242ab7e6f2d50910f89c77333f359d2c9`

No broker orders were transmitted (Shadow mode, `InpMode=1`, no live/Challenge
acknowledgement). Readiness remains exactly `READY FOR SHADOW MODE`.
