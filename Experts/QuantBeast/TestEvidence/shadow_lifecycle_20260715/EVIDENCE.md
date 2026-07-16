# QuantBeast Shadow lifecycle evidence — 2026-07-15

## Build

- MetaEditor build: 6002
- Target: X64 Regular
- Result: `0 errors, 0 warnings, 8223 ms`
- Source SHA-256: `824408fc5f6f645a0ed1c0484a1ed7967894805dc56d07a5ea737996c659c885`
- EX5 SHA-256: `776a8ec184aaea6801e08bcd0ce1e0f818154abad08a329525cee6be3d343abf`
- Shadow module SHA-256: `05885359c865d3c56d738a7ededcd13a49b46b3c8d74dc07c7d040ebece560bb`
- Kill-switch module SHA-256: `aff5b0931372822b659aa8d5f2365116c7d473a1fe6eecffc74d33a0d924710b`
- Compiler log: `QuantBeastEA.log`
- Runtime excerpt: `runtime_excerpt.txt`

## Runtime fixture

- Config: `MQL5\Profiles\Tester\QuantBeast.ShadowFinal.XAUUSD.M5.20260518_20260522.ini`
- Symbol/timeframe: XAUUSD M5
- Dates: 2026-05-18 through 2026-05-22
- Deposit: USD 10,000
- Mode: `QB_MODE_SHADOW`
- Tester launch API returned `job_id: 0` and a contradictory `tester stopped` status, but the local agent log proves the final test ran from 12:04:43 through 12:04:54.

Relevant agent-log evidence:

```text
TEST 9 PASS: Shadow lifecycle net=2.00 balance=10002.00
TEST 10 PASS: Shadow stop/flatten stop=-1.20 flatten=closed
TEST 11 PASS: Shadow partial/breakeven net=0.50
TEST 12 PASS: Shadow trail/time trailNet=1.00 time=closed
TEST 13 PASS: Shadow costs/multi cost=0.10 multi=2
TEST 14 PASS: Shadow drawdown lock equity=9400.00 dd=6.0
TEST 15 PASS: Transient entry gate spread=true recovered=true manual=true
Self-tests complete: 17 passed, 0 failed
Mode: QB_MODE_SHADOW | Symbol: XAUUSD | TF: PERIOD_M5
Tester final balance 10000.00 USD
```

The test section contains no `deal #`, `order #`, `market buy`, or `market sell` lines. The unchanged broker/tester balance confirms that the self-test's virtual profit was isolated inside `CShadowPortfolio` and did not place a broker order.

## What this proves

- Shadow mode can construct a virtual market entry from bid/ask data.
- A target hit closes exactly one virtual position.
- A stop hit realizes a virtual loss and forced flatten closes exactly one position.
- A partial exit can occur before breakeven without suppressing the later breakeven stop.
- ATR trailing locks positive P/L and the time-stop accepts deterministic evaluation time.
- Configured commission/slippage is charged and two simultaneous virtual positions are accounted and flattened.
- Synthetic open-equity drawdown activates the central drawdown lock.
- Transient spread/connectivity/quote gates auto-clear, while explicit manual kills stay latched.
- Virtual P/L changes virtual balance.
- Startup self-tests execute in Strategy Tester and all current fixtures pass.
- Shadow mode remains broker-order-free in this fixture.

## What this does not prove

- Strategy profitability or signal reachability.
- Realistic long-run drawdown or execution-cost calibration.
- Pending-order simulation; Shadow currently rejects pending intents.
- Restart persistence for virtual positions.
- Live broker execution, partial-fill, recovery, or emergency-protection behavior.
