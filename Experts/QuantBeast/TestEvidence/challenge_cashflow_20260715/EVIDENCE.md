# Challenge Cash-Flow Evidence — 2026-07-15

## Defect and repair

Challenge Mode ignored account cash flows, so a deposit could advance absolute-dollar stages and change risk without attribution to trading. The initial funding is now baselined. Later balance, credit, charge, correction, or bonus deals fail the Challenge closed, zero risk, and route through central flattening. A millisecond/ticket history cursor is persisted; state schema advanced from v2 to v3 so older state is quarantined rather than guessed.

## Evidence

- Compile: `0 errors, 0 warnings, 8962 ms`, X64 Regular
- Source SHA-256: `88c6704888654c4842b57539794fa6bd524734cd9e072644e83271618c245e83`
- EX5 SHA-256: `0b43846cad920af97ad716fb6221fa9c8316d93ca8acc81ef2f40a578da119de`
- ChallengeMode SHA-256: `81665010406310e3b8b4ee410587fbddf2c14ee4a73aa7680390a05663e13532`
- StateStore SHA-256: `a1abb0212dd387fc9aa3aeb095bb78bc5b7a9ce1fe188537d2336ae2f47111e3`
- Fixture: `TEST 30 PASS: Challenge cash-flow policy types=classified deposit=fail-closed`
- Suite: `32 passed, 0 failed`
- Tester: `60113` ticks, `3007` bars, `50.114 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

The classification/fail-closed policy is deterministic; an actual broker deposit/withdrawal and terminal restart cursor recovery have not yet been induced. Challenge attempts/reset and profitability remain unvalidated. Readiness remains `READY FOR SHADOW MODE`.
