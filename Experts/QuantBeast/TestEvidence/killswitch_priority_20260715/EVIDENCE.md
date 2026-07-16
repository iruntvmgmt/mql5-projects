# Kill-Switch Hard-Risk Priority — 2026-07-15

## Defect

`CKillSwitch::CheckConditions()` handled terminal disconnection first and returned immediately. When disconnection coincided with an emergency equity-floor breach, daily/weekly loss lock, stop-placement failure, or repeated broker rejection, the persistent hard-risk decision was never evaluated or latched.

**Severity:** Critical — hard account protection could be suppressed during connectivity loss.

## Repair

- Persistent hard-risk conditions now execute before transient connectivity handling.
- Equity-floor breach still receives highest priority and activates emergency, cancel-all, flatten-all, and entry lock.
- Daily/weekly loss, stop-failure, and repeated-rejection locks latch before a disconnect return.
- Connectivity-only blocking remains transient and clears after recovery.
- Added `QBTestKillSwitchFailurePriority()` using isolated local kill-switch instances; it transmits no broker orders.

## Verification

- Compile: `0 errors, 0 warnings, 14509 ms`, X64 Regular.
- Test 31: `floor=emergency rejection=latched connectivity=transient`.
- Full suite: `33 passed, 0 failed`.
- One-day Shadow run: `5520 ticks`, `276 bars`, `6.529 s`.
- Final balance unchanged: `10000.00 USD`.

## Boundary

This proves condition priority and latch/recovery semantics. It does not reproduce a real network outage or prove broker actions after reconnection. Controlled disconnect and failed-close scenarios remain required.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
