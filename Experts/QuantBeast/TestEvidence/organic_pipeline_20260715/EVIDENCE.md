# Organic pipeline and rejected-signal direction — 2026-07-15

## Confirmed defect

**Severity: Medium (audit integrity).** `CStrategyBase::MakeRejected()` zero-initialized `StrategySignal.direction` without accepting the direction being evaluated. In MQL5, the zero enum value is `ORDER_TYPE_BUY`, so every rejected short evaluation was journaled as BUY. The duplicated BUY rows made the signal audit trail unable to distinguish long and short eligibility failures.

This did not itself transmit an incorrect order because rejected signals never entered the candidate array, but it corrupted rejection analytics and could mislead strategy/filter diagnosis.

## Repair

- `MakeRejected()` now requires an explicit `ENUM_ORDER_TYPE` and stores it.
- All BO, FBO, TP, and MR long rejection paths pass `ORDER_TYPE_BUY`.
- All short rejection paths pass `ORDER_TYPE_SELL`.
- Existing deterministic Tests 16–19 now require the rejected short signal to retain `ORDER_TYPE_SELL`.

## Compile and regression evidence

- Final compile: `0 errors, 0 warnings, 10309 ms`.
- Final Shadow regression: `36 passed, 0 failed`.
- Strategy Tests 16–19 all passed with valid long, valid short, and direction-preserving short rejection.
- Test 33 classified a healthy strong-up/normal-volatility/good-liquidity/accepted-breakout state as safe and a volatility shock as unsafe.
- Test 34 selected the stronger FBO SELL candidate, rejected its duplicate after commit, and rejected opposing candidates under conflict policy.
- Tester: `22080 ticks`, `1104 bars`, final balance unchanged at `10000.00`.
- No broker orders were transmitted.

## Organic pipeline evidence and boundary

A completed Model 4 run on 2026-03-02 used MT5's generated-tick fallback because the terminal explicitly reported that real ticks begin on 2026-06-19. That run organically reached:

```text
market data -> closed-bar features -> regime -> FBO long/short
-> arbitration -> central risk rejection
```

The journal contained one valid FBO BUY candidate at 16:35 and one valid FBO SELL candidate at 18:05. Central risk correctly rejected both because their stops exceeded the configured 1000-point maximum. This is useful reachability evidence, but it is not true-real-tick, trade-lifecycle, or performance evidence.

A separate Model 4 boundary probe started at 2026-06-19, the first advertised real-tick date. It initialized successfully and reported the boundary, but no test ticks advanced before shutdown. Therefore true-real-tick organic coverage remains blocked by local history availability.

The existing shared `SignalJournal.csv` still contains the pre-repair BUY/BUY rejection rows. No completed post-repair organic run appended rows, so that historical file must not be used to judge the repaired direction contract.

## Hashes

- `StrategyBase.mqh`: `03d1998c51c83224dff65572a990bea97586ea13160bd7af9228a61b73dbb480`
- `BreakoutEngine.mqh`: `22647fed22bb9e4d750a52cf6ff14f0bb4ee350f3bb14e07eecfbe15e610e0c2`
- `FailedBreakoutEngine.mqh`: `7ff133cd3658ddcb4c2c8947042d1fb7b4d31f63e361a709571ae0787fdc6ba8`
- `TrendPullbackEngine.mqh`: `01cc488dffc62688a410323b80ff5e496b3e01380b68eb7b8d954b4da3e0e919`
- `MeanReversionEngine.mqh`: `47ef8c2e3e45eedd5c8ee8622d82e67db4009f560e03d490f8e62279d3bdbb69`
- `SafetyTests.mqh`: `3bb30514021bbb8afab8ccb1962c7f825c084d8179f3673ff3b17e02839c2228`
- `QuantBeastEA.mq5`: `e5e87b4431e57f4481fc7078f735ea46d7ae489335023528af721509587af52f`
- `QuantBeastEA.ex5`: `24e9400a1a98edb83470d43bbc3b2316982d4875a1e059f649d4e00a1a3c7503`

## Readiness

Readiness remains `READY FOR SHADOW MODE`. This evidence does not establish a trading edge, true-real-tick behavior, broker execution safety, normal-terminal restart recovery, or live readiness.
