# D028 Stage 0B

This checkpoint fixes the combined candidate-index handoff and establishes the
authoritative corrected legacy shared-ownership baseline.

## External evidence

Raw MT5 artifacts remain outside Git:

```text
/Users/matt/MT5-MSZZ-TEST/D028_Stage0B_Results
/Users/matt/MT5-MSZZ-TEST/D028_Stage0B_ShadowResults
/Users/matt/MT5-MSZZ-TEST/D028_Stage0B_TestResults
```

Historical D027 evidence remains unchanged under:

```text
/Users/matt/MT5-MSZZ-TEST/D027_Stage6_Results
```

## Reproduction

Run:

```bash
python3 Tools/D028/Stage0B/analyze_stage0b.py
```

The tool validates native HTML/CSV counts, deal counts, standalone trade-row
parity, frozen windows, candidate identities, owners, and exit attribution. It
then writes:

- `candidate_index_audit.csv`
- `corrected_legacy_baseline.csv`
- `stage0b_findings.md`

## Verification

- EA compile: 0 errors, 0 warnings.
- 22 test-script compiles: 0 errors, 0 warnings.
- 22 runtime `Test_MSZZ_*` suites: all pass.
- New candidate-handoff suite: 36 assertions, 0 failures.
- Short shadow: 113 raw candidates, 46 unique clusters, 0 malformed, 0 trades.
- Long shadow: 431 raw candidates, 178 unique clusters, 0 malformed, 0 trades.
- B0: exact 224-trade/+28.2447R A parity.
- B1: exact 190-trade/+28.6117R SweepReclaim parity.
- B2: 372 trades, 744 deals, +23.0157R, 0 malformed candidates.

Historical D027 Stage 6 A+Sweep is preserved but marked
`INVALIDATED_FOR_COMBINED_BASELINE_COMPARISON`. Stage 1 is unblocked and was
not started here.
