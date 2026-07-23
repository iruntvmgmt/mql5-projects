# Phase 10 -- Analytics and observability audit

## `strategy_performance_report.py` supports all five strategies generically

The report groups exclusively by the literal `Strategy` string column
(`Strategy`, `Direction`, `Session`, `RegimeTrend`) -- there is no
hardcoded strategy list anywhere in the script (confirmed by reading the
full grouping logic: `by_strat_dir`, `by_sds`, `by_sdr` all key off
`t.get("Strategy", "")`). TP V1 (`"TP"`) and TP V2 (`"TPV2"`) are
distinct string values written by distinct code paths (`TrendPullbackEngine.mqh`
vs `TrendPullbackV2Engine.mqh`), so they **cannot be pooled accidentally**
-- confirmed directly against real data: Phase 5's re-analysis of
`TradeJournal.csv` showed TP V2's one real trade tagged exactly `"TPV2"`,
never `"TP"`, across all three re-examined windows.

## TP V2 traceability chain

Every TP V2 trade is traceable via the documented join key
`(Strategy, Direction, Timestamp==EntryTime)` -- **not** `TradeJournal.SignalID`,
because that field is `ctx.signal_id` (an internal numeric ID), a
different identifier from the `SignalJournal` string ID
(`TPV2_SELL_...`). This is a **pre-existing, already-documented** gap
(`STRATEGY_SPEC.md`: "Valid signals do not carry a durable numeric signal
ID beyond the journal string ID"), not new to TP V2 and not unique to
it -- every strategy has the same join-key limitation. The
`(Strategy, Direction, Timestamp)` key is reliable given the
architecture's own guarantees (at most one active position; arbitration
enforces unique per-bar-per-direction acceptance), and was empirically
proven reliable for TP V2's real trade in `run_p3_03_20260216_20260220.md`
("TradeJournal row present, fields internally consistent with the
originating SignalJournal row -- same entry/stop/target family, same
timestamp"). Per Phase 10's own instruction ("if a join cannot be
reconstructed reliably, fix the observability gap before calling TP V2
demo-ready") -- the join **was** reconstructed reliably, so no fix is
required; the pre-existing SignalID-numeric-join gap remains recorded as
a known limitation rather than a blocker.

## Conclusion

Phase 10's requirements are met without any code change: the analytics
pipeline was already strategy-agnostic before TP V2 existed, and TP V2's
one organic trade has already been used to empirically prove (not just
assert) that the entry->exit join key works for it.

---

# Phase 11 -- Resolve remaining evidence-retention gaps

## TP outcome-journal issue: resolved, cause confirmed

Read the live `TPOutcomeJournal.csv`
(`Terminal/Common/Files/QuantBeast/Tester/TPOutcomeJournal.csv`, current
size 50,722 bytes, 53 lines) directly. It contains:

- **Real production rows**: e.g. `TP_1736144100_down_1736145300,XAUUSD,2,1,2025.01.06 06:35:00,down,...`
  -- genuine V1 resume-candidate events from the 2025-01-06 evidence
  window, with real epoch-derived event IDs and real market prices/ATR
  values. **This proves the V1 passive tracker still produces real
  output when a genuine V1 resume event occurs** -- Phase 11's explicit
  requirement.
- **Self-test synthetic rows**: e.g. `TP_700_up_702,XAUUSD,2,1,1970.01.01 00:11:42,...`
  -- fixture rows from `SafetyTests.mqh`'s `QBTestTPOutcome*` tests
  (Tests 65-74), which deliberately use synthetic 1970-epoch timestamps.

Cross-referencing the tester journal, the `!!! QuantBeast[ERROR] Cannot
open journal file: QuantBeast\Tester\TPOutcomeJournal.csv error=5004`
lines seen during every self-test run correspond exactly to
**Decision D003** from the prior sprint (`DECISION_LOG.md`): ten
separate local `CTPOutcomeTracker` instances each calling `Init()`
back-to-back within Tests 65-74, a pattern unique to that self-test
block (every other tracker in this codebase is a single global instance,
`Init()`'d once per `OnInit()`). D003 already diagnosed this as a
self-test-only Wine/MQL5 file-handle artifact and fixed the resulting
real bug it exposed (`WriteRow()`'s bookkeeping order). This session's
evidence **confirms D003's conclusion empirically**: despite those
errors appearing in every self-test run, the file continues to
accumulate real rows correctly outside the self-test block (the
2025.01.06 production rows above were written in a normal, single-
global-tracker tester run, not during a self-test pass).

**Cause, definitively**: self-test interference (ten-instances-one-process
churn), not file-handle failure in the production path, not a tester
input quirk, not a journal path mismatch, and not a tracker regression.
No further fix required.

## Evidence package completeness

For every accepted TP V2 run this sprint (`run_p3_02/03/04`, the Phase 5
re-analysis, and the new `ce01` broker fixture), the following are
already recorded per the established manifest convention: tester
profile path, exact journal byte-slice `[offset, end_offset)`, completion
footer (tick/bar counts, "Test passed", "thread finished"), git commit
hash, whether the run was accepted or invalidated
(`run_p3_01..._INVALID.md` explicitly marked as such), and whether any
broker order was transmitted. `HASHES.sha256` and `FILE_INDEX.md` are
updated as part of this phase's commit (see below).

**Broker orders transmitted for this phase: none** (pure evidence
audit and documentation).
