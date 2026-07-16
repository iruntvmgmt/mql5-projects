# QuantBeast repair evidence — 2026-07-15

## Final compile

- MetaEditor build: 6002
- Target: X64 Regular
- Result: `0 errors, 0 warnings`
- Elapsed compile time: 38148 ms
- Main source SHA-256: `7aecd6513625614583c50ffdb29f90abf7316a4dbe1438aa3f10c7730520726b`
- Compiled EX5 SHA-256: `0793fc040c74ccb083cb172ac076f130cb3d01223bfedac3286eca706e4eb0da`

The exact UTF-16 MetaEditor transcript is preserved as `QuantBeastEA.log`.

## Diagnostic runtime attempt

The trading-disabled configuration `QuantBeast.Diagnostic.XAUUSD.M5.20260601_20260605.ini` was created with `InpMode=0`, persistence disabled, and startup self-tests enabled.

The native MT5 MCP endpoint returned `{ "ok": false, "job_id": 0 }` before starting the test. Starting the local `metatester64.exe` agent did not change that result. No EA runtime result, trade result, or performance result is claimed from this attempt.

The active MT5 terminal was not restarted or repurposed because it contained an existing demo-account position. The bridge failure is recorded as a test-infrastructure blocker, not an EA pass or failure.

## Built-in deterministic fixtures

The compiled source contains startup checks for:

- newest-first regression direction;
- forming-bar versus closed-bar ordering;
- a fixed Wednesday London-session boundary;
- broker-aware position sizing bounded by the configured risk budget.

These fixtures compile but still require an actual Diagnostic attachment to produce runtime pass/fail logs.
