# Transaction Ownership Evidence — 2026-07-15

## Confirmed defect

The transaction handler required every deal—including exits—to carry the QuantBeast magic range. A manual partial or final close of a tracked QuantBeast position can carry magic `0`. Such exits were discarded, the context was later removed silently, and manual partial PnL/commission/swap was omitted from final aggregation.

## Repair

- New entries remain strictly magic-owned.
- Exit and close-by deals are owned when either their magic is owned or their stable position identifier is already tracked by QuantBeast.
- Foreign untracked exits remain ignored.
- Once a tracked position is finalized, all deals sharing its stable identifier are included in gross PnL, commission, and swap aggregation regardless of the closing order's magic.
- `DEAL_ENTRY_INOUT` remains rejected; live netting/exchange accounts are already blocked at initialization.

## Evidence

- Compile: `0 errors, 0 warnings, 7852 ms`, X64 Regular
- Source SHA-256: `d9962e520687aa1d267afac508f54e2e6383f6e517ab4f6c85b50442f93496cb`
- EX5 SHA-256: `610ff7ef2f59ce61d7139d60f370931908a25f4884fb13b679daa02969eed8f8`
- TransactionState SHA-256: `6d90f7c158ba40ec1d3c09efb32c9304d25db6a05390be5e158a11cb7a2d4c96`
- SafetyTests SHA-256: `646ee0ee40990ef9fde1dcb0cafbbb95a238e9828f51cc013ac1e996f4be5c92`
- New fixture: `TEST 24 PASS: Transaction ownership entry=strict exit=position-owned inout=rejected`
- Complete suite: `26 passed, 0 failed`
- Tester: `32521` ticks, `1627` bars, `15.971 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic ownership policy. A controlled broker-side manual partial/final close remains required to prove actual deal metadata and callback ordering.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
