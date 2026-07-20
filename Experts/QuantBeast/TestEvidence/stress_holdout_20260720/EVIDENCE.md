# Stress and holdout backtests — 2026-07-20

## Purpose

Closes another item from the "long tail of unclosed evidence":
`LIVE_DEPLOYMENT_CHECKLIST.md` section J requires high-volatility,
quiet-market, and non-overlapping holdout backtests, none of which had been
run. Pure Strategy Tester backtesting against real historical XAUUSD ticks;
no live broker risk, no source changes.

## Window selection

Chosen from the same D1 volatility survey already gathered for
`organic_multiwindow_20260719` (`get_chart_history`, 2026-01-01 to
2026-07-17), picking regimes and calendar weeks not yet used by any prior
test this project:

| Window | Dates | Rationale |
|---|---|---|
| High-volatility/shock | 2026.01.26-01.30 | Genuine extreme event: XAUUSD ran 5007->5597 then crashed to 4682 within the same week (Jan 29-30), the single largest volatility spike in the surveyed history |
| Quiet/range | 2026.04.06-04.10 | Two of five days with visibly tight D1 ranges (~60-65 points) vs the ~150-200+ typical elsewhere in the series |
| Fresh holdout | 2026.05.04-05.08 | A full calendar week never touched by any prior test (`performance_readiness_20260716` used 06.22-06.26/06.29-07.03; `organic_multiwindow_20260719` used 02.16-02.20/03.30-04.07/04.20-04.24) |

All three: XAUUSD M5, Model=4 (real ticks), Shadow mode, all 4 strategies
enabled, self-tests disabled, journals enabled with
`InpJournalTesterPrefix=true`.

## Results

All three completed cleanly (`OnTester result 0`, normal tester footer, no
kill-switch/lock activations, no broker orders transmitted since Shadow
mode never touches the real account):

| Window | Ticks/bars | Duration | FBO trades | Net Shadow PnL | Notable |
|---|---|---|---|---|---|
| High-vol (Jan 26-30) | 1,740,398 / 1,104 | 0:14:00 | 1 (+95.46) | +95.46 | Hundreds of entries correctly blocked by the price-jump preflight gate during the Jan 29-30 crash (jumps up to 1093 points) rather than trading through chaotic/gapping price action |
| Quiet (Apr 6-10) | 1,458,491 / 1,104 | 0:11:39 | 5 | -149.20 | No anomalies; ordinary FBO signal/exit cadence |
| Holdout (May 4-8) | 1,464,816 / 1,104 | 0:11:34 | 17 | +206.07 | Busiest of the three windows; mixed win/loss sequence, no locks triggered despite volume |

Only FBO reached accepted trade state in all three windows, consistent
with every other organic evidence run to date
(`organic_multiwindow_20260719`, `organic_true_ticks_20260716/20260718`).
**These net PnL figures are not a profitability claim** -- single windows,
small trade counts, no statistical significance, and Shadow-mode cost
modeling only. They are evidence that the mechanism produces sane,
non-anomalous behavior across a genuinely fresh calendar week and two
distinct volatility regimes, per `TESTING_GUIDE.md` Stage 6's
recommendation to test dev/holdout/high-vol/quiet conditions.

## Finding: entry-preflight price-jump gate behaves correctly under real stress

The Jan 26-30 window is the first time this project has organically
exercised the price-jump preflight control (`InpMaxPriceJumpPoints`) against
a genuine large real-tick gap event, rather than a synthetic/injected one.
It fired correctly and repeatedly (jumps from ~200 to over 1000 points)
throughout the crash period, and no signal was accepted while price was
moving abnormally. This is useful positive evidence for `TESTING_GUIDE.md`
Stage 6's "spread-stress and delayed-execution variants" and gap-stress
requirements -- the gate that exists for exactly this scenario was proven
against a real instance of it.

## Scope note

- Spread-stress specifically was not isolated as a separate synthetic test;
  real-tick Model=4 backtesting inherently includes actual historical
  spread variation, and the high-volatility window in particular would have
  included whatever spread widening the broker's historical feed recorded
  during the crash.
- Slippage-stress was not separately isolated either; this would require a
  live/demo-forward test (see the still-open 2-week demo-forward
  requirement) rather than backtesting, since Strategy Tester spread/
  execution modeling is a broker-feed approximation, not a live fill.

## Verification

- No source or configuration changed. Source SHA-256
  `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`, EX5
  SHA-256 `f4107718ee637356cf4c2131daedd6da80e27bf317e9c41f49df264dffa29642`
  (both unchanged from the prior session).
- No broker orders were transmitted (Shadow mode throughout).
- Readiness remains exactly `READY FOR SHADOW MODE`.
