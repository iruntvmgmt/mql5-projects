# Broker Failure Policy Evidence — 2026-07-15

## Confirmed defects

1. A retryable market-order rejection caused the next attempt to use a fresh quote as its new execution anchor while retaining the original stop and size. Adverse quote drift plus the configured `CTrade` deviation could exceed the entry movement budget charged by sizing.
2. Non-emergency flatten/cancel requests were cleared after one broker call even when owned positions or orders remained. A rejection could therefore leave exposure behind with no active action request.

## Repair

- Every market attempt now compares the live quote with the risk-approved entry. Favorable movement is allowed; adverse movement beyond half-tick tolerance is rejected before submission.
- Displacement rejection is journaled as `TRADE_RETCODE_PRICE_CHANGED` without an uninitialized execution record.
- Live flatten and cancel actions recount owned positions/orders after broker calls.
- Requests clear only when no applicable broker-owned exposure remains; otherwise they remain latched for the next tick/timer cycle.

## Evidence

- Compile: `0 errors, 0 warnings, 9102 ms`, X64 Regular
- Source SHA-256: `ffe906ff9a0ad219bfb455be2d04895ea609c2bbbac2a2264beac486e17bc8d6`
- EX5 SHA-256: `2f0bf9fa89bea5a3e7b1121d09a1a6d15b771d2eee890bb2c8e149bd136e2755`
- BrokerAdapter SHA-256: `11332e22f22e2c78edf323fef83d762df0d77e50c4fdf6ca3be87a7541e09855`
- SafetyTests SHA-256: `1374b5024ba66e68a27e39f1ebe8023385d5d20f7b0960bfd4e64a6c4fb9a069`
- New fixture: `TEST 27 PASS: Broker failure policy entry=bounded broker_action=retained`
- Complete suite: `29 passed, 0 failed`
- Tester: `49073` ticks, `2455` bars, `43.771 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic retry-anchor and action-retention policy. No actual requote, delete rejection, close rejection, network interruption, or freeze-level failure was induced at a broker. The live callback and repeated-action path still requires controlled demo/fault-injection evidence.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
