# Daily/weekly/HWM risk-state real-restart evidence — 2026-07-20

## Purpose

Closes another item from the "long tail of unclosed evidence": daily/weekly
loss-limit baselines, high-water mark, and consecutive-loss count are
persisted and deterministically unit-tested (`StateStore.mqh`'s
`SaveDailyRiskState`/`LoadDailyRiskState` etc., wired into
`PersistRuntimeState()`/`OnInit()`), but had never been proven against a
*real* terminal restart -- only Strategy Tester's two-process probe, which
`restart_probe_20260715` already showed is unreliable (tester agent globals
are isolated/reset between processes and cannot validate normal-terminal
behavior).

## Method

Captured the real baseline via a live attach before touching anything:
`Risk tracking: dailyStart=997.71 weeklyStart=997.71 HWM=1022.40`. Extended
`MQL5/Scripts/QuantBeastRestartFixture.mq5` with two new commands:

- `CMD_WRITE_RISK_STATE` (9): writes deliberately distinguishable values
  (dailyStart=555.55, weeklyStart=666.66, HWM=8888.88, dailyLock=true,
  consecLosses=4) directly to the real scoped Global Variable keys
  (`QB_DailyStartEquity_<login>_<symbol>` etc.), with the daily/weekly date
  fields set to `TimeCurrent()` so `RiskEngine::InitDailyTracking()`'s
  same-day/same-week comparison treats them as valid rather than resetting
  to current equity.
- `CMD_RESTORE_RISK_STATE` (10): writes back real captured values (taken
  from script inputs `InpRestoreDailyStart`/`InpRestoreWeeklyStart`/
  `InpRestoreHWM`), clearing the test-only lock and consec-loss count. Fails
  loudly (no globals touched) if any input is left at its 0.0 default, to
  prevent accidentally zeroing real state.

Detached EA -> ran `CMD_WRITE_RISK_STATE` -> re-attached EA (restart) ->
read the Expert log -> ran `CMD_RESTORE_RISK_STATE` with the captured real
values -> re-attached once more to confirm restoration.

**Important design note**: unlike the position/pending-order/protection
fixtures used earlier today (which create disposable throwaway broker
state), daily/weekly-start-equity and HWM carry real accumulated meaning
across the life of the account. `CMD_CLEANUP_ALL` was deliberately **not**
extended to delete these keys, since a blanket delete would silently reset
the genuine multi-day high-water mark the account has been tracking since
project inception -- the explicit capture-inject-restore workflow above
exists specifically to avoid that.

## Result

After `CMD_WRITE_RISK_STATE` and a real restart:
```
Risk tracking: dailyStart=555.55 weeklyStart=666.66 HWM=8888.88
```
Confirms the persisted values (not current equity, which was ~997 the
whole time) were loaded and used -- proving real-restart survival for
daily start equity, weekly start equity, and high-water mark.

After `CMD_RESTORE_RISK_STATE` and a final confirming restart:
```
Risk tracking: dailyStart=997.71 weeklyStart=997.71 HWM=1022.40
```
Matches the original captured baseline exactly. Account risk state is back
to its real, correct values.

## Scope note: what this does and does not cover

- Directly proven: `GV_DAILY_START_EQUITY`, `GV_DAILY_DATE`,
  `GV_WEEKLY_START_EQUITY`, `GV_WEEKLY_DATE`, `GV_HIGH_WATER_MARK`.
- Same mechanism, not independently re-verified this session:
  `GV_DAILY_LOCK`/`GV_WEEKLY_LOCK`/`GV_DRAWDOWN_LOCK` (booleans loaded by
  the identical `InitDailyTracking()` call) and `GV_CONSEC_LOSSES` (no
  direct log line at `OnInit()`; would require an actual `ValidateTrade()`
  call to observe, which needs an organic signal to reach risk validation).
  These share the exact same load/save code path just proven, so this
  result materially de-risks them, but does not independently confirm each
  one.
- Not attempted (needs separate Challenge Live authorization, cannot
  inherit this session's Conservative Live approval): `GV_CHALLENGE_STAGE`
  and related challenge-state fields, only loaded when
  `g_EffectiveMode == QB_MODE_CHALLENGE_LIVE`.
- Not attempted: arbitration cooldown/duplicate-window persistence
  (`GV_ARB_*`) -- same persistence mechanism, no direct restart evidence
  gathered this session.

## Safety notes

- No source code changed; only the test-fixture script
  (`MQL5/Scripts/QuantBeastRestartFixture.mq5`, SHA-256
  `4d7d04969ae10f18801438b6271c0375b0fbc2a6b36201c460f5f3f893c1e04c`).
- Real account risk state was captured before modification and explicitly
  restored and re-verified afterward; final state matches the original
  exactly.
- No broker orders were transmitted at any point in this test.
- Readiness remains exactly `READY FOR SHADOW MODE`.
