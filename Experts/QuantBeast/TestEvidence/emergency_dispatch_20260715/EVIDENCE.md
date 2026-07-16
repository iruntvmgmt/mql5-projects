# Emergency Broker-Action Dispatcher — 2026-07-15

## Defects

1. Persistent cancel/flatten requests were serviced only from `OnTick()`. With no ticks during disconnect, rollover, or market closure, emergency broker work could remain stranded.
2. When ticks were active, the same request could call the broker on every tick with no retry throttle.
3. The prior non-Shadow branch included Diagnostic mode, contradicting the requirement that Diagnostic mode transmit no broker actions.
4. The immediate protection-emergency path did not explicitly persist its newly latched emergency state.

**Severity:** High; the Diagnostic transmission path is a destructive-action safety defect.

## Repair

- Centralized cancel/flatten servicing in `ProcessKillSwitchActions()` and called it from both `OnTick()` and the one-second `OnTimer()`.
- Added a shared one-second monotonic retry cadence across both event paths.
- Added `QBModeAllowsBrokerActions()`: only Conservative Live and Challenge Live may transmit broker cancel/close requests.
- Diagnostic and Shadow modes cannot reach broker transmission through the dispatcher or immediate protection emergency.
- Immediate protection emergency now persists the kill state.
- Extended Test 31 with mode and retry policy fixtures.

## Verification

- Compile: `0 errors, 0 warnings, 14859 ms`, X64 Regular.
- Test 31: `broker_mode=live-only retry=bounded`.
- Full suite: `33 passed, 0 failed`.
- One-day Shadow run: `5520 ticks`, `276 bars`, `10.726 s`.
- Final balance unchanged: `10000.00 USD`.

## Boundary

This proves dispatcher wiring and pure mode/retry policies without broker transmissions. An actual failed close/delete, disconnect/reconnect, and timer-driven broker retry still require a controlled fault adapter or demo scenario.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
