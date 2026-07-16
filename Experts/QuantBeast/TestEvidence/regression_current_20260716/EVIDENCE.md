# Current-build deterministic Shadow regression — 2026-07-16

- MetaEditor build 6002: `0 errors, 0 warnings`.
- EA source SHA-256: `6a4f83c34b4cd27d89739e4df760347994ba7a28f9aaae41990eb4bfcc2052be`.
- EA EX5 SHA-256: `cf3bceae2ee37841487684e974e29e2c246f521c9deb62a942136e28747f5fd7`.
- Unique configuration: `QuantBeast.CurrentRegression.XAUUSD.M5.20260518_20260522.ini`.
- Model: generated 1-minute OHLC; this is not true-real-tick evidence.
- Result: `36 passed, 0 failed`; tester completed normally.
- Broker orders transmitted: none.

This is the full non-journal deterministic suite on the repaired build. The
real file-writer Test 35 is isolated in the adjacent signal-journal evidence
directory so this run cannot mutate operational journals.
