# Recovery-State Regression Evidence — 2026-07-15

## Scope

This gate verifies two deterministic contracts added after the transaction/recovery static audit:

1. persisted state versions are accepted only when empty/uninitialized or exactly current; incompatible nonzero versions are rejected without being overwritten;
2. persisted risk state restores the daily, weekly, and high-water drawdown locks, consecutive-loss count, start-equity baselines, and high-water mark into a fresh risk-engine instance.

This is **not** proof of a real terminal/VPS restart with live broker positions or pending orders. Those scenarios remain untested.

## Build

- MetaEditor result: `0 errors, 0 warnings`
- Elapsed: `7923 ms`
- CPU target: `X64 Regular`
- Source SHA-256: `7f447b9b8655aacf982e7bf81aee1496b582efbfb5456c843c390eb72c5b9828`
- EX5 SHA-256: `38ef3bf58812fae81cb86b47f0cb1d405df3220b7390dbb1552f9b96de2bcfbc`
- StateStore SHA-256: `c7e98a7720f1f4364ad3e2691a6bcdfcc801be1320bdbbdad4e9485b036190b0`
- SafetyTests SHA-256: `1b485acacdb36ebf932c51a897c811d96f9eb36d70acf8d7e5f498daaceabbea`

## Runtime

- Mode: `QB_MODE_SHADOW`
- Symbol/timeframe: `XAUUSD`, `M5`
- Period: `2026.05.18` through `2026.05.23`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`
- Ticks/bars: `27600` / `1380`
- Self-tests: `23 passed, 0 failed`
- Recovery additions:
  - `TEST 20 PASS: State version policy empty=true current=true old=rejected future=rejected`
  - `TEST 21 PASS: Risk state restore daily=locked weekly=locked dd=locked losses=4`
- Runtime: `25.806 s`

The direct terminal launch and local MetaTester agent log are authoritative for this run. The native tester MCP was not used because it previously returned unreliable stopped/zero-job status.

## Verdict

PASS for deterministic state-version quarantine and risk-state restoration contracts. Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
