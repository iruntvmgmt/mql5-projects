# Server-Acknowledgement Failure Policy — 2026-07-15

## Defect

`CBrokerAdapter::PlaceMarketOrder()` and `PlaceStopOrder()` correctly classified rejected server retcodes in their `ExecutionRecord`, but returned the raw `CTrade` boolean. Since that boolean only confirms local request construction/transmission, a locally successful call with a rejected server retcode could return `true`. The main controller would then register a phantom pending lifecycle or otherwise treat the rejected submission as accepted.

**Severity:** High — execution/accounting state could diverge from broker state.

## Repair

- Added pure order-class-specific acknowledgement policies:
  - `QBMarketTransmissionAccepted()` accepts only `DONE` or `DONE_PARTIAL` when the API boolean is true.
  - `QBPendingTransmissionAccepted()` accepts only `PLACED`, `DONE`, or `DONE_PARTIAL` when the API boolean is true.
- Both broker submission methods now return the policy result, not the raw API boolean.
- Extended Test 27 with injected mismatched outcomes. No broker order is transmitted by the fixture.

## Verification

- Current dependency build: `0 errors, 0 warnings, 13754 ms`, X64 Regular.
- Runtime Test 27: `PASS ... transmission=server-confirmed`.
- Full startup suite: `32 passed, 0 failed`.
- One-day Shadow run: `5520 ticks`, `276 bars`, `11.839 s`.
- Final balance unchanged: `10000.00 USD`.

## Boundary

This proves the pure return/retcode contract and its wiring into the compiled EA. It does not induce an actual broker rejection, disconnect, requote, stop-modification failure, or failed emergency close. Those live-path demo/fault-adapter scenarios remain required.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
