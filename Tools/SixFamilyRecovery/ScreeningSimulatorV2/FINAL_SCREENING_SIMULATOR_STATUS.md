# Screening Simulator V2 — Status

**Phase status: `IN_PROGRESS` — commit 1 of 2 (market/instrument transport
sub-layer) RUNTIME-CERTIFIED; simulator loop pending (commit 2).**

The overall standalone screening simulator is **not** certified yet. Do not
treat this as `SCREENING_SIMULATOR_V2_RUNTIME_CERTIFIED`.

## Commit 1 — market/instrument transport sub-layer (this commit)

- Starting HEAD: `784d2493429282ee83147ea948294cf5884fd6b7`
- Branch: `recovery/research-journal-manifest-parser-v2`
- Policy consumed (unchanged): `MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST`

Frozen sub-layers (user-approved 2026-07-30): `MSZZ_SCREENING_MARKET_DATA_V2`,
`MSZZ_SCREENING_MARKET_MANIFEST_V2`, `MSZZ_SCREENING_INSTRUMENT_PARAMS_V2`, and
the frozen candidate iteration order. Instrument geometry lives only in the
instrument-params file (manifest/params reconciliation — see the implementation
doc); the certified JournalTransportV2 manifest is untouched.

### Files added (no existing file modified)

```text
MQL5/Include/MultiSpeedZigZag/Research/ScreeningMarketV2.mqh
MQL5/Tests/MultiSpeedZigZag/Test_MSZZ_ScreeningMarketV2.mq5
Docs/MultiSpeedZigZag/SCREENING_SIMULATOR_V2_IMPLEMENTATION.md
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/screening_market_v2.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/test_screening_market_v2.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/make_market_fixtures.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/*_fixture.csv (3)
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/cross_language_market_hashes.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/Test_MSZZ_ScreeningMarketV2.ini
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/{compile,test}_summary.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/cross_language_parity.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/output_hashes.csv
```

### Representation — integer transport (real-data-safe)

OHLC are signed integer point counts; instrument sizes are integer 1e-8 units.
Ordinary decimal prices (100.20, 2000.37, 1.23456, ...) are exact; nothing in
the transport or the SHA-256 uses float formatting. This replaced an earlier
16-digit float draft whose cross-language parity depended on values being
binary-exact (the MQL5 runtime gate caught the divergence). See the
implementation doc.

### Evidence (fresh, this session)

- MQL5 compile (`wine start /Unix metaeditor64 /compile /log`): market test
  `0 errors, 0 warnings` (2026.07.30 23:55:18, fresh ex5 51676 B).
- MQL5 runtime (isolated `/portable` terminal, demo login 870012, fresh
  `OnStart`): `TEST_SUMMARY tests=30 failures=0` at 2026.07.30 23:55:45.
- Python: `test_screening_market_v2` 22 tests, 0 failures.
- Cross-language byte parity: MQL5-reconstructed SHA-256 equals the Python
  fixtures — market `78067caf…`, manifest `32322955…`, params `fe608f32…`.

## Not yet done (commit 2)

Simulator loop, `MSZZ_SCREENING_OUTCOME_V2`, additive status/rejection taxonomy,
next-executable-bar entry, bid/ask + gap-fill geometry, occupancy, MFE/MAE,
holding bars, test-end closure, full ~50-case fixture matrix, MQL5/Python
outcome parity, full 32-suite regression, and fresh canonical P4 parity
(`330 / +47.6083336413R / PF 1.2472234619 / SHA 9ebf2f41…eb5f`).

## Family authorization / D034-D035

Unchanged. All six families remain `implementation_authorized=false`. No family
generator, production path, or P4 logic was touched. D034 and D035 remain
unauthorized.
