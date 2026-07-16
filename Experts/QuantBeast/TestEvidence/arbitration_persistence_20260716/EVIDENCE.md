# Arbitration Persistence Evidence — 2026-07-16

## Defect

Arbitration duplicate and cooldown state was memory-only. After a live terminal restart, an already accepted setup inside the configured duplicate/cooldown window could be accepted again because `CSignalArbitrator` restored neither `m_lastAcceptTime` nor recent signal IDs.

Severity: **High**. Affected path: signal arbitration/restart recovery. Safety consequence: restart could bypass duplicate/cooldown throttles while other account-level locks persisted.

## Repair

- Added stable hash-based duplicate persistence to `CSignalArbitrator`.
- Added bounded arbitration persistence slots to `StateStore.mqh` (`QB_ARB_PERSIST_MAX=20`).
- Restores only fresh, non-future cooldown/duplicate timestamps. Expired, missing, and future entries are rejected.
- Runtime now persists immediately after accepted arbitration commits.
- Deterministic self-tests now prove restored duplicate and restored cooldown rejection.

## Validation

- Compile: MetaEditor build 6002, 0 errors, 0 warnings, 2026-07-16 11:38:27.
- Fixture: generated-tick Shadow regression, XAUUSD M5, 2026-05-18 through 2026-05-22.
- Config: `QuantBeast.ArbitrationPersistence.XAUUSD.M5.20260518_20260522.ini`.
- New tester-agent boundary: `11167432` bytes before run; `1115796` bytes appended.
- Regression: `Self-tests complete: 50 passed, 0 failed`.
- Footer: final balance `10000.00 USD`; `OnTester result 0`; generated-tick tester footer `Test passed`.

## Key runtime proof

```text
CS	0	11:39:02.684	QuantBeastEA (XAUUSD,M5)	2026.05.18 00:00:00   QuantBeast[INFO] TEST 34 PASS: Arbitration policy best=FBO/SELL lower=rejected duplicate=rejected restoredDuplicate=rejected conflict=rejected exposure=rejected regime=selected confluence=selected noConfluence=rejected restoredCooldown=rejected
CS	0	11:39:02.684	QuantBeastEA (XAUUSD,M5)	2026.05.18 00:00:00   QuantBeast[INFO] TEST 48 PASS: Arbitration restore policy fresh=restore expired=reject missing=reject future=reject
CS	0	11:39:02.684	QuantBeastEA (XAUUSD,M5)	2026.05.18 00:00:00   QuantBeast[INFO] Self-tests complete: 50 passed, 0 failed
CS	0	11:39:26.268	Tester	final balance 10000.00 USD
CS	0	11:39:26.268	Tester	OnTester result 0
CS	0	11:39:26.277	Tester	XAUUSD,M5: 22080 ticks, 1104 bars generated. Environment synchronized in 0:00:00.029. Test passed in 0:00:24.048 (including ticks preprocessing 0:00:00.001).
CS	0	11:39:26.282	Tester	test Experts\QuantBeast\QuantBeastEA.ex5 on XAUUSD,M5 thread finished
```

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5	sha256=b9d2950a56a94838fc4765ca418f8f9c40e1d59006ad1dcef760f99c44276d20	bytes=99454
MQL5/Include/QuantBeast/Portfolio/SignalArbitrator.mqh	sha256=065b90c2f9170a80d90cb00a24e1eeba6277fede42a77d7a5f724e54f0906086	bytes=18434
MQL5/Include/QuantBeast/Core/StateStore.mqh	sha256=90d6c738b3bac5ab6154fa8909c7cc1ff73adf9be16f891b37f0c78282a52598	bytes=20697
MQL5/Include/QuantBeast/Testing/SafetyTests.mqh	sha256=cb411da45233d1adb767dd0be3c012d7f051d6e50454475504da84bebca58549	bytes=59263
MQL5/Experts/QuantBeast/QuantBeastEA.ex5	sha256=f32f2df50f3c6c76fe64a5df5419a68a1f2d3fe30559f9c6f6c4c6641e2140c5	bytes=482994
```

## Boundaries

No broker orders were transmitted. This is deterministic generated-tick Shadow evidence, not true-real-tick evidence and not live-terminal restart proof with broker exposure. Readiness remains `READY FOR SHADOW MODE`.
