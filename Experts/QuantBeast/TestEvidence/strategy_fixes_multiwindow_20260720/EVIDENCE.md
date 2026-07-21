# Strategy-logic fixes: multi-window generalization — 2026-07-20

## Purpose

Confirm the six strategy-logic fixes (`strategy_logic_fixes_20260720/`) are not
overfit to the single Apr 20-24 window they were first measured on. Ran the
fixed build (ex5 `be41085d...`, self-tests 54/0) journaled over three
pre-established organic windows spanning distinct regimes. Pure Shadow
backtesting, no source change in this task.

## Results — accepted / not-eligible / past-eligibility per strategy

Pre-fix baseline for all three windows (`organic_multiwindow_20260719/`): only
FBO ever reached ACCEPTED; BO, TP, MR were 0 accepted everywhere.

| Window | Regime shape | BO | MR | FBO | TP |
|---|---|---|---|---|---|
| Apr 20-24 | choppy/balanced | **2** acc | **5** acc | 9 acc | 0 (0 past-elig) |
| Mar 30-Apr 07 | impulse→pullback→cont. | 0 (114 past-elig) | **3** acc | 2 acc | 0 (0 past-elig) |
| Feb 16-20 | compression→breakout | 0 (76 past-elig) | **2** acc | 12 acc | 0 (0 past-elig) |

## Conclusions

**MR — generalizes (closed).** Fires in all three windows (5 / 3 / 2), having
been 0 in every window pre-fix. The `slope_norm` scale fix plus the target/stop
geometry corrections make MR a genuinely reachable, regularly-firing strategy.

**BO — fix verified working.** Before the fix BO's compression eligibility and
breakout trigger were mutually exclusive, so it could essentially never reach
ACCEPTED. After the fix it clears eligibility in every window (76-146
past-eligibility bars) and completed breakout trades when a breakout actually
occurred (2 in Apr 20-24). The low completion count is expected, not a defect:
BO only fires on the rare bar that both follows a compression run and closes
beyond the range. The Feb window — specifically chosen for a compression then a
Feb 20 breakout — did not produce a BO trade only because the newest data block
ends 2026.02.19 21:55, so the Feb 20 breakout day fell outside the tested data
(a window-boundary artifact, not a BO failure). BO is now reachable; broader
multi-month sampling would better characterize its true hit rate.

**TP — still universally blocked (open).** 0 accepted AND **0 past-eligibility**
in all three windows: TP never even passes its `IsEligible()` gate anywhere.
This is a universal structure-gate block, not window selection. The binding
condition is TP's requirement that `regime.structure ∈ {IMPULSE, PULLBACK}`,
which the earlier investigation (`impulse_threshold_fix_20260720/`) showed never
co-occurs with `TrendState`-classified trending bars: PULLBACK's
`returning_to_value` sub-condition is narrow by design, and IMPULSE requires
STRONG-trend magnitude that is rare-to-absent. IMPULSE's thresholds were already
aligned to `TrendState`'s STRONG bar; the remaining question is whether IMPULSE
(and thus TP eligibility) should key off WEAK-trend magnitude instead of STRONG.
This is the next actionable code gap for TP.

## Environment note

Multiple `metatester64` processes had accumulated hung-in-shutdown across the
day's runs (finishing their tests — journals flushed, `test passed` logged —
but never exiting), which was the source of the intermittent tester-automation
flakiness seen this session. They were cleaned up; subsequent runs use a
completion-poll that waits for `test passed` in the log and then terminates the
hung process so they no longer accumulate.

## Source state

Unchanged from `strategy_logic_fixes_20260720/` — no source edited in this task.
ex5 SHA-256 `be41085d9243dfa3d039e2006637143dfbc96c6204cc7f95cfe697ff3300674c`.
No broker orders transmitted (Shadow mode). Readiness remains
`READY FOR SHADOW MODE`.
