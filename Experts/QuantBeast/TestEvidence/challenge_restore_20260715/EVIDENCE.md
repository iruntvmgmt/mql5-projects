# Challenge Restore Policy Evidence — 2026-07-15

## Confirmed defect

Challenge persistence restored `risk_percent` and `stage_target` directly from terminal globals. Corrupt, stale, or manually altered state could therefore silently escalate risk after restart (the deterministic fixture supplied `99%`). Structural corruption such as a peak below stage-start equity was also accepted.

## Repair

- Runtime configuration is now authoritative for stage risk, target, and maximum attempts after restore.
- Active-stage state is rejected if its enum, finite values, equity/peak relationship, attempt count, or profit-lock bounds are invalid.
- Rejected state becomes inactive/failed with zero risk; the real startup path latches entries off.
- Conservative Live no longer loads stale Challenge state; restore is limited to acknowledged Challenge Live.
- Expected corrupt-state testing suppresses only its deliberate error log; production rejection still logs.

## Evidence

- Compile: `0 errors, 0 warnings, 13480 ms`, X64 Regular
- Source SHA-256: `6286dd2986278ca311fa95d76e78fc31f0492c5b488a52667624e5e4b56d0b9d`
- EX5 SHA-256: `50c027f6d9d6a46e8a07c325c6f496afd9f0e27646a44a0c67fdee382e018ba4`
- ChallengeMode SHA-256: `64046bf93823ade54015c0da5bac1aa239454d488cfdb619126ede3e3306a70b`
- SafetyTests SHA-256: `9cc8a46bf6280c2096cef7d7022f3907d9cd7b41aa6c834589fbfd9b6622d045`
- New fixture: `TEST 28 PASS: Challenge restore policy risk=configured corrupt=rejected`
- Complete suite: `30 passed, 0 failed`
- Tester: `54593` ticks, `2731` bars, `48.559 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic restore validation and configuration authority. Challenge deposits/withdrawals, external cash-flow detection, attempts/reset workflow, profit-lock lifecycle, real restart, and any performance claim remain unproven.

Readiness remains `READY FOR SHADOW MODE`; Challenge research/live remain prohibited.
