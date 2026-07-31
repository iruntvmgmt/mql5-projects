# Screening Execution Contract V2 Status

Status: `POLICY_LAYER_CERTIFIED`.

The shared, side-effect-free policy object is implemented in MQL5 and Python
with the frozen policy ID `MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST`. Both sides use
the same committed parity fixtures for conservative tick normalization,
family-open and expiry rejection, stop-first same-bar resolution, and gross R.

Evidence:

- MQL5 compile: 0 errors, 0 warnings.
- MQL5 isolated runtime: 10 tests, 0 failures.
- Python parity tests: 2 tests, 0 failures.
- No family generator or production execution path was modified.

This does not certify the full historical simulator. Candidate iteration,
next-bar market entry, spread/bid/ask history, MFE/MAE windows, test-end
closure, and family adapters remain the next implementation work. No family
is authorized and D034/D035 remain blocked.
