# D028 tools

Stage 0 is currently blocked by a reproducible integrity mismatch in the
legacy combined-strategy candidate append path. See
`Docs/MultiSpeedZigZag/D028_MULTIBOOK_ARCHITECTURE.md`.

The three configs here are exact copies of their certified D027 controls except
for the descriptive comment, report name, and unique magic:

- `d028_stage0_A_2R.ini`
- `d028_stage0_SweepReclaim_2R.ini`
- `d028_stage0_Legacy_A_plus_Sweep_2R.ini`

Raw reports and journals are intentionally retained outside Git at:

```text
/Users/matt/MT5-MSZZ-TEST/D028_Stage0_Results
```

This follows the established D027 repository-size policy: tracked analysis and
configuration, external native MT5 run artifacts.
