# Consecutive broker-submission rejection counter — 2026-07-15

## Finding

The production kill-switch call received a constant `false` for repeated broker rejection. No runtime counter existed, so the documented repeated-rejection lock could never activate from live submission results.

## Repair

- Added `InpMaxConsecutiveBrokerFailures` with a default threshold of three failed submission cycles.
- Count only cycles in which a broker submission was actually attempted and ended rejected. Local pre-transmission displacement rejection does not increment the counter.
- Reset the streak after a server-confirmed accepted submission.
- Latch the entry kill when the threshold is reached.
- Persist the counter and advance the fail-closed state schema from v3 to v4.
- Added deterministic pure-policy coverage to Test 27.

Retries belonging to one signal count as one failed submission cycle. This prevents a single transient retry burst from consuming the entire streak threshold.

## Evidence

- Compile: `0 errors, 0 warnings, 9995 ms`.
- Shadow fixture: `33 passed, 0 failed`.
- Test 27: `reject_counter=latched`.
- Tester: `5520 ticks`, `276 bars`, final balance unchanged at `10000.00`.
- No broker orders were transmitted.

## Hashes

- `QuantBeastEA.mq5`: `2460ed69599a441e998bd7085180677230465490f2c19dd889aa7075aee6d50d`
- `QuantBeastEA.ex5`: `3142919aa1cff8cfe38e04a0259fdeba4f394f7abdacd0cfd06f85a0130198c9`
- `Configuration.mqh`: `d0174adbdc4e562e094e4b5afc73d357cc189aa0b2b2f28038fc16cd3213cf76`
- `StateStore.mqh`: `6ea9d80f94f3cb5143a1ca330dabe9c3636e3c88d2f97118e673a047dd9c55ac`
- `BrokerAdapter.mqh`: `d3e7a50ec977d4424a6ae64716135593a44c504e61904d8bfd2e2834341799a6`
- `SafetyTests.mqh`: `b6376f5d995262cb5e80580811eacd0b32199f28d6933c7caa0c1c7cbcf4e683`

## Boundary

This proves counter semantics, production wiring, persistence representation, and a broker-free runtime regression. It does not prove behavior under actual broker rejection, requote, disconnect, or restart. Conservative Live and Challenge modes remain prohibited.

