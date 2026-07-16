# QuantBeast unknown-position unmanaged evidence — 2026-07-16

## Defect

Startup reconstruction could add a QuantBeast-range broker position with unknown strategy ownership to `CPositionManager`. Once tracked, normal position management could later trail stops, perform partial closes, or otherwise modify a position whose strategy context was not proven.

## Severity

High for live/restart safety. Unknown ownership must not be actively managed as if it were a fully reconstructed QuantBeast position.

## Fix

Added `QBUnknownPositionShouldBeManaged()` and changed `CPositionManager::ReconstructFromBroker()` so unknown positions are reported/quarantined/ignored without being adopted into active management. `UNKNOWN_FLATTEN` also remains unmanaged if the close is not confirmed.

## Validation

- Compile: `0 errors, 0 warnings` at `2026-07-16 10:17:38`
- Shadow regression: `42 passed, 0 failed`
- Model: generated ticks, broker-free Shadow only
- Ticks/bars: `22080` ticks, `1104` bars
- Final balance: `10000.00 USD`
- Tester result: `OnTester result 0`

## Hashes

- Source SHA-256: `12488268def53445f064bcb2c92369446dee14a396b478074aeb8d0fc4717b07`
- PositionManager SHA-256: `f1eb5c8f75a5342015029488cc57f02bb312f8a8877b04fee4feee59be48eb72`
- EX5 SHA-256: `277379e14b902d0bc1fcf48eb2dbaa75e76cb3f090358b7be6f5d9835b5440f9`

No broker orders were transmitted.
