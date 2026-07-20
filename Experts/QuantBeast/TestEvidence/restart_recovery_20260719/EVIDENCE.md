# Normal-terminal restart recovery — 2026-07-19/20

## Purpose

HANDOFF "Next task" item 2: run an actual normal-terminal restart fixture
with owned positions, pending orders, unknown positions, and
incompatible/corrupt state. This supersedes the invalidated
`restart_recovery_20260716` attempt (which ran in `QB_MODE_SHADOW`, a mode
that by design never reaches `ReconstructFromBroker()`). This session ran
QuantBeastEA live in `QB_MODE_CONSERVATIVE_LIVE` on Coinexx-Demo
(account 871221) with `InpAcknowledgeLiveBrokerRisk=true` and the FBO-only,
market-only preset, using the operator-authorized real terminal restart
pattern (EA remove/reattach — functionally equivalent to a terminal restart
for `OnInit()`/reconciliation purposes, per TESTING_GUIDE Stage 7's
"Stop/restart terminal or remove/reattach EA").

## Method

The MCP trading tools available (`trade_send_market_order`,
`trade_send_pending_order`) have no `magic` parameter, and
`ReconstructFromBroker()` requires a magic number inside QuantBeast's range
(`QB_MAGIC_BASE`=20260701 to +999) to classify a position at all. A
pre-existing but unwired test asset, `MQL5/Scripts/QuantBeastRestartFixture.mq5`
(committed history: `41d56ba`, `d0ad085`, `ee43b29`), already implemented the
needed OrderSend-with-magic logic. It required a small scope exception
(operator-approved) since it lives outside `Experts/QuantBeast/**` /
`Include/QuantBeast/**`, and two corrections during this session (see
"Fixture tooling defects found and fixed" below) before its `CMD_PLACE_UNKNOWN`
and `CMD_WRITE_CORRUPT` commands actually exercised the code paths they were
meant to test.

Each scenario followed: detach EA (broker-free baseline) → run fixture
command → confirm broker-side fixture state → re-attach EA (fresh
`OnInit()`, i.e. the restart event) → read `MQL5/Logs/<date>.log` (the
Experts-tab journal, distinct from the terminal system log) for the
reconciliation outcome → clean up before the next scenario.

## Fixture tooling defects found and fixed (documentation/test-asset only, no EA source changed)

1. **`CMD_PLACE_UNKNOWN` used `FIXTURE_MAGIC_UNKNOWN=99999999`**, outside the
   QB magic range. Per `PositionManager.mqh:421-424`, `ReconstructFromBroker()`
   only classifies ownership (including "unknown") for positions whose magic
   IS in range; an out-of-range magic is skipped by the loop entirely and
   never reaches the unknown-ownership branch. This meant the scenario as
   originally written could never have exercised `InpUnknownPosPolicy` at
   all — a latent gap in the test asset, not in QuantBeast's own logic.
   Fixed: use `FIXTURE_MAGIC_OWNED` (in-range) with the existing
   non-`QB_`-prefixed comment `FIXTURE_UNKNOWN`, which correctly fails
   `StrategyFromComment()`'s prefix check (`PositionManager.mqh:65-72`) and
   reaches the unknown-ownership branch.
2. **`CMD_WRITE_CORRUPT` wrote `QB_FIX_SCHEMA`/`QB_FIX_MARKER`**, which are
   not the real state-version key QuantBeast reads. The actual key is
   `GV_ScopedName(GV_STATE_VERSION)` = `"QB_StateVer_" + login + "_" +
   effective_symbol` (`StateStore.mqh:59,76-79`). Writing only the fixture's
   own prefix never touched `IsSupportedStateVersion()`'s input, so the
   scenario as originally written would always pass through as if state were
   valid. Fixed: write `QB_StateVer_871221_XAUUSD=999` directly (and delete
   it in `DoCleanupAll()`/`DoDeleteCorrupt()`).

Both fixes are committed in `MQL5/Scripts/QuantBeastRestartFixture.mq5`.
Compile: `0 errors, 0 warnings` (MetaEditor build 6033, two incremental
compiles at 2026.07.19 23:00:38 and 23:01:06). Source SHA-256
`796efb349fa5817861e2d4348e2bf4de8b4afcebe234033ad456cd2749516aba`; EX5
SHA-256 `9f916ccf1495e612d51cafee985756b0a92499ee92b4dda0bb05330a9a36e913`.
QuantBeastEA's own source/EX5 were not touched (hashes unchanged:
source `7ac32f8db9c8b16d2fe797ad890f6403ae7877ca38a7fdef24b0c5c5ab797ec9`,
EX5 `cb91e10507047433646c6927a17c7bf242ab7e6f2d50910f89c77333f359d2c9`).

## Scenario 1 — owned protected position: PASS

Fixture: market BUY 0.01 XAUUSD, magic=20260701, comment=`QB_FBO_fixture`
(parses to strategy "FBO" — `StrategyFromComment` truncates at the first
`_` after the `QB_` prefix), entry=4008.27, SL=3958.01, TP=4108.01
(ticket 34679484).

After re-attach, `MQL5/Logs/20260719.log`:
```
Reconstructed position: ticket=34679484 strategy=FBO entry=4008.27 originalSL=3958.01
Startup reconciliation: 1 positions reconstructed
```
Strategy ownership, entry, and original stop were all correctly recovered
from broker order history. This is the first successful end-to-end proof of
`ReconstructFromBroker()` on a real owned position in a live-capable mode;
every prior attempt was invalidated by running in Shadow mode.

## Scenario 2 — pending order: PASS (documented fail-closed behavior confirmed)

Fixture: BUY LIMIT 0.01 XAUUSD @ 3971.93, magic=20260801, comment=
`QB_FBO_fixture_pending` (ticket 34680951).

After re-attach:
```
CancelAll: cancelled 1 pending orders
Startup pending reconciliation: found=1 cancelled=1 remaining=0
Startup reconciliation: 0 positions reconstructed
```
Confirms `QuantBeastEA.mq5`'s documented behavior: owned pending orders are
found and cancelled fail-closed at startup, not restored (this is intentional
design, not a defect — pending-order lifecycle state is not yet persisted).
Broker-side order was gone after restart (`get_trading_open_positions`
returned zero orders).

## Scenario 3 — unknown position: PASS

Fixture (post-fix): market BUY 0.01 XAUUSD, magic=20260701 (in QB range),
comment=`FIXTURE_UNKNOWN` (does not start with `QB_`) (ticket 34681029).

After re-attach:
```
Unknown QuantBeast position ownership: ticket=34681029 comment=FIXTURE_UNKNOWN
Unknown position left unmanaged by configured policy: ticket=34681029
Startup reconciliation: 0 positions reconstructed
```
The position was correctly classified as unknown ownership (in-range magic,
unparseable comment) and left unmanaged, matching the currently configured
`InpUnknownPosPolicy=UNKNOWN_REPORT` (value 1) — logged, not adopted, not
touched. No `KillEntries` call fired, which is correct: that only fires for
`UNKNOWN_QUARANTINE` (value 2), not `UNKNOWN_REPORT`. No destructive action
was taken on the position.

## Scenario 4 — incompatible/corrupt state: PASS

Fixture: `GlobalVariableSet("QB_StateVer_871221_XAUUSD", 999)` — the real
scoped state-version key, directly incompatible with `QB_STATE_VERSION_NUM=4`.

After re-attach:
```
!!! QuantBeast[ERROR] Persisted state version mismatch (found v999, expected v4). Entries remain quarantined until state is migrated or cleared.
QuantBeast KILL: Entry kill activated: Persisted state version mismatch; migration or explicit clear required
Startup reconciliation: 0 positions reconstructed
```
Confirms fail-closed quarantine of incompatible state versions on a real
terminal restart (previously only deterministically unit-tested, per
`KNOWN_LIMITATIONS.md`'s "no automatic migration workflow" note — this
scenario is that same policy proven against a real persisted Global Variable
rather than a synthetic in-process fixture).

## Cleanup and final broker state

`QuantBeastRestartFixture` `CMD_CLEANUP_ALL` closed all XAUUSD positions,
cancelled all pending orders, and deleted the real corrupt state-version
global plus fixture markers. Final state: 0 open positions, 0 pending
orders, `QB_StateVer_871221_XAUUSD` deleted (EA will re-seed a valid v4 on
next clean attach). No positions/orders belonging to any other EA or manual
trade were touched at any point (each fixture scenario placed exactly one
XAUUSD order/position and cleanup only ever targeted XAUUSD tickets it had
just created).

## Safety notes

- All four scenarios ran on Coinexx-Demo (account 871221), operator-owned
  disposable demo account, consistent with the 2026-07-16 authorization on
  file in HANDOFF.md.
- FBO-only, market-order-only Conservative Live gates were active throughout;
  no BO/TP/MR or pending-order live transmission occurred.
- No manual/other-EA broker state existed during this session; a single
  leftover fixture position from a prior session (`QB_FBO_fixture`, ticket
  34627175) was found at session start, confirmed as prior test debt (no
  EA had been attached for 3 days per terminal logs), and closed with
  explicit operator authorization before any new scenario work began.
- Readiness remains exactly `READY FOR SHADOW MODE`; this evidence advances
  the recovery gate in `LIVE_DEPLOYMENT_CHECKLIST.md` section H but does not
  by itself change overall readiness classification.
