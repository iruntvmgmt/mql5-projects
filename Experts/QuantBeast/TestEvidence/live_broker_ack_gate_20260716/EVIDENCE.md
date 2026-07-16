# Live Broker Acknowledgement Gate Evidence — 2026-07-16

## Defect

Conservative Live and acknowledged Challenge Live had strategy, execution, and recovery gates, but no independent acknowledgement that the operator intended QuantBeast to transmit broker orders. A live preset loaded accidentally could proceed to broker-transmission mode if the other gates passed.

Severity: **High** configuration/safety defect. Affected path: live EA initialization before broker transmission. Safety consequence: accidental live-mode attachment could permit broker orders without a dedicated live-broker acknowledgement.

## Repair

- Added `InpAcknowledgeLiveBrokerRisk=false` default input.
- Live modes now fail initialization unless `InpAcknowledgeLiveBrokerRisk=true`.
- Challenge acknowledgement remains separate; `InpAcknowledgeChallengeRisk` was not enabled.
- All QuantBeast presets explicitly set `InpAcknowledgeLiveBrokerRisk=false`.
- Added deterministic `TEST 40b` coverage for missing-ack rejection and explicit-ack acceptance.

## Validation

- Compile: MetaEditor build 6002, `0 errors, 0 warnings`, 2026-07-16 11:57:46.
- Fixture: generated-tick Shadow regression, XAUUSD M5, 2026-05-18 through 2026-05-22.
- New tester-agent boundary: `12283228` bytes before run; `1116084` bytes appended.
- Regression: `Self-tests complete: 51 passed, 0 failed`.
- Footer: final balance `10000.00 USD`; `OnTester result 0`; generated-tick tester footer `Test passed`.

## Key runtime proof

```text
CS	0	11:58:10.298	QuantBeastEA (XAUUSD,M5)	2026.05.18 00:00:00   QuantBeast[INFO] TEST 40b PASS: Live broker transmission acknowledgement gate
CS	0	11:58:10.298	QuantBeastEA (XAUUSD,M5)	2026.05.18 00:00:00   QuantBeast[INFO] Self-tests complete: 51 passed, 0 failed
CS	0	11:58:31.380	Tester	final balance 10000.00 USD
CS	0	11:58:31.380	Tester	OnTester result 0
CS	0	11:58:31.388	Tester	XAUUSD,M5: 22080 ticks, 1104 bars generated. Environment synchronized in 0:00:00.043. Test passed in 0:00:21.731 (including ticks preprocessing 0:00:00.003).
CS	0	11:58:31.390	Tester	test Experts\QuantBeast\QuantBeastEA.ex5 on XAUUSD,M5 thread finished
```

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5	sha256=8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49	bytes=100657
MQL5/Include/QuantBeast/Core/Configuration.mqh	sha256=287d8f29198bd829367fcc49650c849afafd5fe95b289411c77a92ab2a9635e6	bytes=21932
MQL5/Experts/QuantBeast/QuantBeastEA.ex5	sha256=191b36f1bd4195ea4296941de941b7b202e5394e8c15380a2a13d6f2d8d225f7	bytes=484202
```

## Boundaries

No broker order was transmitted by QuantBeast during this regression. Manual/MCP demo order lifecycle evidence remains separate under `TestEvidence/demo_broker_lifecycle_20260716/`. This gate must be deliberately overridden for any future EA-controlled demo/live validation. Readiness remains `READY FOR SHADOW MODE`.
