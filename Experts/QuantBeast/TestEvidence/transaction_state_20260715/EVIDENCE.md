# Pending Partial-Fill State Evidence — 2026-07-15

## Defect

The first `DEAL_ENTRY_IN` from a partially filled pending order set `g_OrderPending=false`. The unfilled broker remainder was therefore orphaned from local expiry/status tracking, and the entry pipeline could admit another order while that remainder still existed.

## Repair

- A pending order remains tracked while its broker state is working and `ORDER_VOLUME_CURRENT` is positive.
- First and subsequent partial fills enrich the same position context.
- Per-strategy trade counting occurs once for the order, not once per partial deal.
- Tracking retires only after no working remainder remains, or after cancellation/rejection/expiry.

## Build and runtime

- Compile: `0 errors, 0 warnings, 7665 ms`, X64 Regular
- Source SHA-256: `f52b7295ee950015c037efd7009b52dac02e42735e57bbdb32b1bfd6cdb33738`
- EX5 SHA-256: `94dbc75cb8dec25acade850578ec1e784ab4303fd402e96dfd5bc4a355aba398`
- BrokerAdapter SHA-256: `6532a6a95266926994a488c55009eae13c0d1cca4af99523ab28b220bbe688ee`
- SafetyTests SHA-256: `8b593631f28088194f681bb943dc3549bb8dfd6f2b1b60881212abc989330e2e`
- Self-tests: `24 passed, 0 failed`
- New fixture: `TEST 22 PASS: Pending partial fill first=tracked second=tracked final=closed once=true`
- Tester: `27600` ticks, `1380` bars, `13.384 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for the deterministic state transition and count-once contract. This does not prove broker-specific partial-fill callback ordering or a real IOC/FOK/RETURN partial fill. Those require live-path fault injection or controlled demo evidence.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
