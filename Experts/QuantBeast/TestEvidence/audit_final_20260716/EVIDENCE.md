# Audit Final Evidence - 2026-07-16

## Build

- Compiler: MetaEditor build 6002.
- Compile result: `0 errors, 0 warnings`.
- Final source SHA-256: `220577a689c55b7ee263e0bae779752b610e0c75ca3f5ff528d2bb473a0ce30a`.
- Final EX5 SHA-256: `fca02855e1396c768c974b3ce2650beb45f4af51f81f9d14f4ed714be8590040`.
- EX5 size: 442028 bytes.
- EX5 timestamp: 2026-07-16 00:12:49 EDT.

## Deterministic writer regression

- Config: `QuantBeast.FinalWriter.XAUUSD.M5.20260518_20260519.ini` (content uses Model 1 and 2026.05.18 to 2026.05.22).
- Pre-run `SignalJournal.csv` size: 91044 bytes.
- Post-run `SignalJournal.csv` size: 92892 bytes.
- Appended bytes: 1848.
- Agent log start offset: 199106.
- Result: `38 passed, 0 failed`; test passed in 0:00:10.206; 22080 ticks, 1104 bars.
- Test 35: `PASS: Signal journal final-decision writer`.
- Test 36: `PASS: Performance without file journal trades=1 net=9.00 avgR=1.00 file=disabled`.

## CSV suffix rows

```csv
2026.05.18 00:00:00,XAUUSD,1,FIX_STRATEGY_LONG_REJECT,BUY,FIX_STRATEGY_LONG_REJECT_BUY_1779062400,0,0,REJECTED,23,Fixture: strategy rejection,...
2026.05.18 00:00:00,XAUUSD,1,FIX_STRATEGY_SHORT_REJECT,SELL,FIX_STRATEGY_SHORT_REJECT_SELL_1779062400,0,0,REJECTED,23,Fixture: strategy rejection,...
2026.05.18 00:00:00,XAUUSD,1,FIX_ARBITRATION_LOSER,BUY,FIX_ARBITRATION_LOSER_BUY_1779062400,0,0,REJECTED,22,Fixture: arbitration loser,...
2026.05.18 00:00:00,XAUUSD,1,FIX_RISK_REJECT,SELL,FIX_RISK_REJECT_SELL_1779062400,0,0,REJECTED,8,Fixture: central risk rejection,...
2026.05.18 00:00:00,XAUUSD,1,FIX_ACCEPTED,BUY,FIX_ACCEPTED_BUY_1779062400,0,0,ACCEPTED,0,Fixture: final accepted decision,...
```

## Boundaries

- The shared Common `SignalJournal.csv` contains historical pre-repair rows and a pre-fix corrupted prefix from the journal append defect proof. It was not rewritten. Only byte-bounded suffixes are used as current evidence.
- The deterministic writer proof is generated-tick evidence and does not replace the organic true-tick proof in `organic_true_ticks_20260716`.

