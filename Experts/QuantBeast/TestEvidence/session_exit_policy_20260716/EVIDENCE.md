# QuantBeast session-exit policy evidence — 2026-07-16

## Defect

`InpCloseBeforeSessionEnd` and `InpCloseBeforeRollover` were declared but incomplete. The EA did not have a deterministic policy for acting on these controls.

## Severity

Medium safety/configuration defect. Operators could enable session/rollover close controls and assume positions would be flattened near configured boundaries when they were not.

## Fix

- Added `QBSessionExitPolicyTriggered()` to define deterministic session-end and rollover triggers.
- Added `ProcessSessionExitPolicy()` to close Shadow positions with `EXIT_SESSION_END` and to request the existing bounded live flatten path only when explicitly live modes and operator-enabled inputs are active.
- Added optional Shadow close reason support in `CShadowPortfolio::CloseAll()`.
- Added deterministic self-test coverage.

## Validation

- Compile: `0 errors, 0 warnings` at `2026-07-16 10:37:29`
- Shadow regression: `45 passed, 0 failed`
- Model: generated ticks, broker-free Shadow only
- Ticks/bars: `22080` ticks, `1104` bars
- Final balance: `10000.00 USD`
- Tester result: `OnTester result 0`

## Hashes

- Source SHA-256: `8312ffcd21e9e5a8d051315acd14398e3aba7b7488ab4a8888186957ffde34b8`
- ShadowPortfolio SHA-256: `964eab9205a42269b75eef4089d151070660fe7338e93b460bc569c955bfcf2e`
- EX5 SHA-256: `834e063c510e940e2ff366a8deea4edda32511b06f3ec8ff2cfb4b7d361bd5a7`

No broker orders were transmitted.
