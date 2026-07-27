# D025 — Canonical Strategy Decomposition and Full-EA Equivalence

Answers: is Stage B's canonical FastMedConfluence result (`+0.1261R`, PF `1.2446`,
224 trades) actually "fixed 2R," or does the `InpExitOwnedOpposite=true`
mechanism (unconditionally closing an owned opposite position and reversing
into a new qualifying signal, inside `ApplyOwnershipPreflight()`) account for
a material part of it? See `DECISION_LOG.md` D025 for full design rationale,
two real bugs found and fixed during implementation, and the complete
21-point results writeup.

## Headline finding

**The opposite-signal-close/reverse mechanism is not a minor detail — it is
the difference between a working strategy and a losing one.** Disabling it
(`InpExitOwnedOpposite=false`, variant B) drops the same entries from
+0.1261R/PF 1.245/224 trades to **-0.0562R/PF 0.918/89 trades**, driven by a
catastrophic short-side breakdown (-0.40R average). The mechanism's value is
primarily **cutting adverse positions early** (retaining the close but
suppressing the reversal, variant C, keeps 72-85% of canonical's edge with
zero reversal trades), with immediately re-entering the new direction a real
but smaller secondary contributor.

## Variants (all full-EA Tester runs, not offline replay)

| Variant | Config | Trades | Expectancy_R | PF | Cumulative_R |
|---|---|---|---|---|---|
| A — CANONICAL_2R_REVERSE | (unmodified Stage B canonical) | 224 | +0.1261 | 1.245 | +28.24 |
| B — PURE_FIXED_2R | `InpExitOwnedOpposite=false` | 89 | -0.0562 | 0.918 | -5.00 |
| C — EXIT_ON_OPPOSITE_NO_REVERSE | `InpSuppressReversalEntry=true` | 189 | +0.1074 | 1.208 | +20.30 |
| D — REVERSE_ON_OPPOSITE | = A, re-analyzed via the exit classifier (no separate run) | — | — | — | — |
| E — CANONICAL_3R_REVERSE | `InpRiskReward=3.0` | 213 | +0.1467 | 1.253 | +31.25 |
| F — NO_FIXED_TP_REVERSE | `InpDisableFixedTarget=true` | 184 | **+0.9976** | 2.471 | +183.56 |
| G — PARTIAL_2R_RUNNER_REVERSE | `InpDisableFixedTarget=true, InpPartialCloseAtR=2.0, InpPartialCloseFraction=0.5` | 184 | +0.5477 | 2.044 | +100.78 |
| H — PARTIAL_3R_RUNNER_REVERSE | same, `InpPartialCloseAtR=3.0` | 184 | +0.5639 | 1.964 | +103.76 |

**F's headline number is fragile, not robust**: 2025Q1 + 2025Q4 alone account
for ~97% of its entire cumulative profit (from 47 of 184 trades), while three
of seven quarters are net negative. Canonical (A) is well-distributed by
comparison (best quarter 31.7% of total, worst -8.9%). F/G/H are explicitly
**not** recommended for out-of-sample validation on this evidence alone —
canonical (A) and 3R-with-reversal (E) are.

## Two real bugs found and fixed during implementation

1. A partial close of a `InpFixedLots=0.01` position (the project's standard
   lot size, which equals XAUUSD's own broker minimum) silently never fired
   — the requested 50% (0.005 lots) was clamped back up to the full 0.01 by
   `NormalizeVolume()`, which the code's own safety check correctly refused
   as "would close 100%." Fixed by using `InpFixedLots=0.02` for variants
   G/H only (an execution-mechanics necessity, not a parameter tune —
   R-multiples are lot-size-invariant).
2. `DetectClosedPositions()` computed every trade's R-multiple from only the
   *last* exit deal's price, silently discarding any profit already banked
   at an earlier partial close. Fixed by using the volume-weighted average
   price across every exit deal for a position (mathematically exact for
   R-multiple purposes, since R is linear in price for a fixed entry/risk).
   Provable no-op for every normal single-exit trade — confirmed by an exact
   byte-identical canonical reproduction after the fix.

## Tick coverage

Real-tick coverage for the full `2025.03.01-2026.07.24` study window is
**2% real ticks** (MT5's own "History Quality" metric) — quantifying D021's
earlier informal finding precisely. A short, recent 4-day window shows 100%
real ticks, confirming the isolated instance's tick cache only covers recent
activity. Per instruction, decisions here are based on `Model=2` (the
historical reproduction anchor), not a 98%-synthetic "real tick" run.

## Reproducing

1. Rerun `Tools/StageB/stageB_FastMedConfluence_canonical.ini` (unmodified)
   for the canonical baseline; this entry's fresh journal capture is under
   `results/canonical/`.
2. Rerun each `d025_variant*.ini` config in this directory for the other
   seven variants; results are under `results/variant*/`.
3. Cross-reference each variant's `MSZZ_TradeAnalytics.csv` against its
   `MSZZ_SignalJournal.csv` to classify every exit (SL/TP/opposite-signal
   close, matched to the triggering cluster and any immediate reversal) —
   see `DECISION_LOG.md` D025's classifier design.
