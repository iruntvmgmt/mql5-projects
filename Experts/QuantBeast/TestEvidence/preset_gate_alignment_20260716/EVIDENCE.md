# Preset gate alignment evidence — 2026-07-16

## Defect

`XAUUSD_Challenge_Example.set` was safe by default because `InpAcknowledgeChallengeRisk=false`, but if an operator manually acknowledged Challenge risk later it inherited default BO/TP/MR and pending-order settings that fail the current live/challenge gates.

Severity: Medium configuration safety/operability defect. No broker exposure was created.

## Fix

- Kept `InpAcknowledgeChallengeRisk=false`.
- Made the Challenge example explicit FBO-only.
- Made the Challenge example explicit market-only with `InpMaxPendingOrders=0`.
- Enabled persistence/global variables and unknown-position quarantine for the example.

## Validation

- Static preset key validation: PASS.
- Conservative Live and Challenge example presets both match current FBO-only, market-only, no-pending, unknown-quarantine gates.
- Compile sanity: `0 errors, 0 warnings`, 2026-07-16 11:17:40.
- No tester run was required because no source behavior changed.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`
- EX5 SHA-256: `a2d735399ab7682dddc72efbd34fda09cea776b86591c1f7b4f4d4b3c7b74744`
- Challenge preset SHA-256: `1c5a1f88d38459aa0e9b8eebd40f7b3a94edc76731260fb916872e7f96bccaf4`
