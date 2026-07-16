# Challenge Safety-Flattten Evidence — 2026-07-15

## Confirmed defect

Challenge profit-lock and stage-drawdown failures stopped future entries but did not request liquidation of existing EA-owned exposure. An open losing position could therefore continue pushing equity below the floor that Challenge Mode claimed to protect.

## Repair

- Challenge safety breaches now transition the Challenge to failed/inactive with zero risk.
- Stage-drawdown failure and profit-lock breach expose a one-shot safety reason to the main controller.
- The main controller routes that reason through the existing centralized `FlattenAll` path, preserving broker ownership and persistent retry policy.
- The sizer is no longer updated from inactive Challenge state after a breach.

## Evidence

- Compile: `0 errors, 0 warnings, 13706 ms`, X64 Regular
- Source SHA-256: `25f27121bfaa9995b7e6a1d3e6ea5d55969c828538101e1b2c9bd389910724d7`
- EX5 SHA-256: `90eab1db4cea7a3821f7294d61b14faa042cbae7c60eb519d86cadb5308b39f6`
- ChallengeMode SHA-256: `39341f17b081cd1cc7d92f44ce4bbf2fba98f7294ed3be04c3d3e66db0a29867`
- SafetyTests SHA-256: `11ebacd65cb685649babd40b9135f88411fb7d5146c709efa979300c88aba4f8`
- New fixture: `TEST 29 PASS: Challenge safety flatten profit_lock=flatten drawdown=flatten`
- Complete suite: `31 passed, 0 failed`
- Tester: `54593` ticks, `2731` bars, `49.130 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic breach-to-flatten policy. No live position was liquidated, and real broker close rejection remains unproven. Deposits/withdrawals, attempts/reset, profit-lock calibration, and Challenge performance remain unvalidated.

Readiness remains `READY FOR SHADOW MODE`; Challenge research/live remain prohibited.
