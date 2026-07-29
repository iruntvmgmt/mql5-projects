# D029 Audit Remediation — Evidence Certification and Partial-Exit State Safety

Branch `feature/d029-audit-remediation`, forked from D029's final SHA
`64f2e29f20a20f3fe362e073c8873262f2183d3e`. This is not a new strategy
study — it does not optimize entries, exits, thresholds, partial
fractions, targets, stops, or portfolio rules. Its purpose: verify D029's
evidence claims independently, repair a real execution-safety defect found
in the process, and issue a corrected certification.

## Finding A — candidate-stream identity: proven, not merely counted

`Tools/D029/Audit/analyze_candidate_streams.py` compares every
`RAW_CANDIDATE` row across SR0/SR3_PCT/SR4_PCT field-by-field (time,
strategy_id, setup, direction, score, entry, stop, target, origin_id,
event_id, strategy_family — every stable field actually present in
`MSZZ_SignalJournal.csv`), with frozen tolerances (prices <=1e-8, score
<=1e-10, timestamps/IDs exact), deterministic canonical serialization, and
a SHA-256 hash per run.

**Result: all three streams are byte-for-byte identical** — 376/376/376
rows, three matching canonical hashes, zero first-differing row. D029's
original claim ("RAW_CANDIDATE=376 for all three, proving zero effect on
candidate generation") was correct, and is now independently proven rather
than inferred from equal counts alone.

**Disclosed schema gap**: `MSZZ_SignalJournal.csv` does not export
`evaluation_time` or `expiry_time` as distinct fields at the RAW_CANDIDATE
stage — only `time` is captured. The comparison above uses every field
that genuinely exists; it does not fabricate the two requested-but-absent
fields.

**Extended check (not required by the handoff, same-class risk, cheap to
verify)**: applied the identical method to D029 Phase 2's D29-A vs D29-E
claim. Their candidate streams are **not** byte-identical — `target`
differs starting at the very first row (2.0R vs 3.0R, as configured) — but
every field upstream of target (time, strategy_id, setup, direction,
score, entry, stop) matches exactly. This is structurally expected (A and
E use different configured R-multiples) and does not contradict D029's
original Phase 2 language, which only compared candidate *counts* between
A and E, never claimed row-level identity. Documented here to preempt any
future misreading.

## Finding C — historical atomicity audit: one real, confirmed defect

`Tools/D029/Audit/audit_partial_atomicity.py` checks every historical
partial-close event in SR3_PCT, SR4_PCT, P3_SR3, and P4_SR3 for a matching
successful protection modify at the same book_id and timestamp (the EA
labels this action `STOP_MODIFY` for SR1/SR3 and `STRUCTURAL_TRAIL` for
SR2/SR4 — both checked).

**Result: exactly one unprotected partial in each of the four runs, all
at the identical timestamp `2025.03.25 15:25:00`** — the same underlying
SweepReclaim trade across all four variants (proven identical by Finding
A). The raw journal:

```text
2025.03.25 15:25:00;2;3;PARTIAL_CLOSE;1.0264;3018.70;3016.43;0.55;true;...
2025.03.25 15:25:00;2;3;STOP_MODIFY;1.0264;3018.70;3016.43;0.00;false;...
```

The partial close succeeded (0.55 lots closed at broker confirmation), but
the breakeven `PositionModify()` call was rejected by the broker. The
current (pre-remediation) code has no retry and no protection-state
check — it marks the partial "done" purely on the partial's own success,
leaving that remainder running at its **original** stop instead of
breakeven for the rest of its life. This is exactly the non-atomic failure
mode Finding C predicted, now confirmed as a real, reproducible historical
event (not hypothetical) — 1 out of 86/82/64/63 partials respectively.

**Per the handoff's own rerun-decision rule** ("No full rerun is required
only if all are true: ... all historical partials had successful matching
protection ...") — this condition is **false**. A full rerun of all seven
affected runs (`D29_SR0`, `SR3_PCT`, `SR4_PCT`, `D29_P3`, `D29_P4`,
`P3_SR3`, `P4_SR3`) is required once the architecture patch below lands,
per "do not selectively rerun favorable variants."

## Finding C — partial-protection state machine (architecture patch, partial)

Added `ENUM_MSZZ_PARTIAL_PROTECTION_STATE` (`MSZZ_PARTIAL_NOT_STARTED`,
`MSZZ_PARTIAL_CLOSE_PENDING`, `MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING`,
`MSZZ_PARTIAL_PROTECTED`, `MSZZ_PARTIAL_PROTECTION_FAILED`) and four new
`MSZZStrategyBookState` fields (`protection_state`,
`protection_retry_count`, `protection_target_stop`,
`protection_remove_target`) in `StrategyBook.mqh`, persisted via a new
`UpdatePartialProtectionState()` method guarded identically to the
existing `UpdateExitManagementState()`.

`MultiSpeedZigZagEA.mq5`'s partial-close handling now attempts the
protection `PositionModify()` (or `STRUCTURAL_TRAIL` removal for SR4)
**immediately inline** after a successful `PositionClosePartial()`, in the
same decision-bar call — this is what the historical journal already did,
just without a state to fall back on when the modify failed. On modify
failure the book now enters `MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING`
instead of being silently marked complete. A new `ProcessPendingProtection()`
function retries the modify on every subsequent closed bar
(`MSZZ_PROTECTION_MAX_RETRIES=3`, frozen), journaling every attempt via the
existing `JournalExitManagement()` call with a new `PROTECTION_RETRY`
action label. `ProcessOneBookExit()` skips calling
`CMSZZBookExitManager::Evaluate()` entirely while a book is in
`EXECUTED_PROTECTION_PENDING` — this blocks SR4's runner-phase progression
by construction, without any change to the already-tested pure
`CMSZZBookExitManager` class. After retry exhaustion, the remainder is
emergency-closed via `g_trade.PositionClose()`
(`PROTECTION_EMERGENCY_CLOSE` journal action); if that close also fails,
`g_recovery_required` is set and a `CRITICAL` journal line is written —
new entries are blocked project-wide via the existing D009
`g_recovery_required` mechanism.

**Side-effect gap found and fixed**: `ExecutePortfolioBookCandidate()`
(the multi-book path used by P3-SR3/P4-SR3) never checked
`g_recovery_required` at all — only the single-book `ExecuteCluster()`
path did. Since P3-SR3/P4-SR3 run exclusively through the multi-book path,
the new emergency-close-failure block would have been silently
unenforceable for exactly the configs Finding C targets. Fixed by adding
the identical guard to the top of `ExecutePortfolioBookCandidate()`.

**Restart persistence — investigated, and a real pre-existing architecture
gap found**: `ReconstructProtectionStateOnRestart()` is implemented on
`CMSZZStrategyBook` exactly per the handoff's spec (fails closed to
`EXECUTED_PROTECTION_PENDING` whenever the recorded protection target is
unavailable; only resolves to `PROTECTED` when the current broker stop
matches a *known* recorded target within tolerance). Its own branch logic
is unit-tested in isolation (7 scenarios, 19 assertions, see
`Test_MSZZ_StrategyBook.mq5`) and is correct.

However, wiring it into `OnInit()` turned out to be moot: `CMSZZStrategyBook::Configure()`
unconditionally `ZeroMemory(m_state)`s on every call, and `Configure()` is
called fresh in `OnInit()` on every EA (re)start. There is **no broker-side
rehydration of `MSZZStrategyBookState` at all** in the multi-book
architecture — `position_open`, `status`, `direction`, `entry_price`,
`logical_volume`, etc. all reset to their zero/FLAT values on restart, and
nothing reconstructs them from broker positions (`PortfolioMarkOpen()`/
`PortfolioBookMarkOpenFor()` are only ever called from the entry-execution
paths, never from `OnInit()`). `ProcessOneBookExit()`'s very first guard
(`if(!book.valid || book.status!=MSZZ_BOOK_OPEN || !book.position_open)
return;`) means a book with a genuinely open broker position, after a
restart, is simply never touched again by any exit-management or
protection logic — the position runs entirely unmanaged from that point
until the next restart-free session (or a Tester's end-of-window
force-close) resolves it.

This is not a defect newly introduced by this patch — `StrategyBook.mqh`'s
own existing comment (D028 Stage 5) already documents that this whole
category of exit-management bookkeeping is "not itself persisted... an
explicit, documented research-scope limitation." What this audit adds is
the explicit confirmation that the limitation is total (not just
`effective_stop`, as the comment's phrasing might suggest, but
`position_open`/`status` themselves), and the observation that it makes
`ReconstructProtectionStateOnRestart()` currently **unreachable in the
live EA** — it is correct, tested, ready code with no caller, because the
broader book-state restart reconstruction it depends on does not exist.
Building that reconstruction (deriving strategy/family attribution,
entry price/time, initial stop, and logical volume for an already-open
position purely from broker + journal data) is a materially larger change
than "restart persistence for the protection sub-state" — it touches
entry/portfolio bookkeeping the handoff explicitly said not to redesign.
It is listed as a required production gap in the final report rather than
built here.

**Does this affect D029's certification?** No — every D029/D029-audit run
is a single continuous Strategy Tester session; none involved an EA
restart mid-position, so this gap has zero effect on any collected
evidence. It is a live/demo-deployment blocker, not a backtest-evidence
problem, and is flagged as such.

**Still open for Finding C**: the remaining runtime tests that require a
live/demo broker connection rather than pure-class unit tests — retry
exhaustion against a real rejected `PositionModify()`, emergency-close
success/failure, SR4 target-removal confirmation, own-family/broker SL-TP
races during pending protection. These will be exercised as part of the
eventual rerun on the isolated demo account (`MT5-MSZZ-TEST`, Coinexx-Demo
870012) rather than as standalone synthetic tests, since they require
genuine broker round-trips this project's established testing pattern
does not simulate offline.

## Finding D — generic volume-min vs volume-step eligibility, fixed

`CMSZZPositionSizing::ComputePartialSplit()` previously took only
`volume_step` and silently assumed `volume_min==volume_step` — wrong
whenever a broker's minimum tradable size exceeds its step (e.g.
`min=0.10, step=0.01`), a case the original code never rejected. The
signature now requires `volume_min` and returns a `reason` string;
**both** legs (partial and remaining) are independently checked against
`volume_min`, not just the whole position against `2*volume_step`.
`Calculate()`'s `partial_capable` flag and the EA's
`ComputeSizedVolume()`/`ProcessOneBookExit()` call sites were updated to
fetch `SYMBOL_VOLUME_MIN` and use the corrected logic; the EA's
skipped-volume journal entry now records the actual rejection reason
instead of a generic hardcoded string.

All ten required test cases from the handoff (min==step splits, min>step
valid/invalid at two different step sizes, fraction 0/1 rejection, full-
consumption rejection, remainder-below-minimum isolated from
partial-below-minimum, odd-step determinism under min>step) were added to
`Tests/MultiSpeedZigZag/Test_MSZZ_PositionSizing.mq5` and pass:
`Test_MSZZ_PositionSizing: failures=0` (75 assertions total, including the
pre-existing D029 Phase 1/3 suite). XAUUSD's actual broker metadata has
`volume_min==volume_step==0.01`, so this fix changes no behavior for any
run XAUUSD ever produced under D029 — it only closes a latent correctness
gap for brokers/symbols where the two differ. Since no D029 volumes
change, this alone does not trigger a rerun; the rerun trigger is Finding
C's historical atomicity failure (see above).

**Regression**: all 29 `Test_MSZZ_*`/`Export_MSZZ_Parity` suites compiled
clean and passed on the isolated instance after this commit (`failures=0`
across the board, including `Test_MSZZ_StrategyBook` and
`Test_MSZZ_PositionSizing`), and `MultiSpeedZigZagEA.mq5` compiles with 0
errors/0 warnings.

## Finding E — broker-authoritative loss-per-lot via OrderCalcProfit()

`CMSZZPositionSizing::Calculate()` previously derived `loss_per_lot`
internally from a generic `(stop_distance/tick_size)*tick_value` linear
formula — wrong for any instrument whose P&L is not a strict linear
function of price distance (FX crosses needing account-currency
conversion, tiered tick values, etc). `Calculate()` now takes
`loss_per_lot` as a required parameter supplied by the caller;
`tick_size`/`tick_value` remain inputs purely for the existing
`MSZZ_SizingJournal.csv` schema (unchanged column layout), no longer used
in the arithmetic. A new EA function, `CalculateBrokerLossPerLot()`, computes
the real value via `OrderCalcProfit(ORDER_TYPE_BUY/SELL, symbol, 1.0,
entry, stop, profit)` (loss = `-profit`), naturally handling long/short via
order type and any account-currency conversion the broker applies
internally. Fails closed (rejects the entry, `reject_reason` populated)
on an `OrderCalcProfit()` failure or a nonpositive resulting loss — never
silently falls back to the old formula. Fixed-lot mode (`MSZZ_SIZE_FIXED_LOT`)
never calls `Calculate()` at all and is untouched.

**Empirically verified, not just architecturally argued**: a new
read-only probe script, `FindingE_LossPerLotProbe.mq5`
(`Scripts/MultiSpeedZigZagTools/`), ran on the isolated demo terminal
against live XAUUSD quotes and compared the old formula's result to
`OrderCalcProfit()`'s result for both a long and a short 10-point stop:

```text
FindingE probe LONG:  formula_loss=1000.000000 broker_loss=1000.000000 abs_diff=0.00000000
FindingE probe SHORT: formula_loss=1000.000000 broker_loss=1000.000000 abs_diff=0.00000000
```

**Result: zero difference.** XAUUSD/Coinexx-Demo is a linear instrument
for this broker (`tick_value` is constant, no currency-conversion step
applies), so Finding E's fix produces **byte-identical** `loss_per_lot`,
and therefore byte-identical sizing volumes, to every existing D029 run.
This closes the correctness gap for any future non-linear
instrument/symbol without requiring a rerun of any existing D029 evidence
— confirmed empirically, not merely assumed from the architecture.

10 tests updated/added in `Test_MSZZ_PositionSizing.mq5`: every existing
`Calculate()` call site now supplies a precomputed `loss_per_lot` via a
local `LossPerLot()` helper reproducing the old formula (preserving every
prior numeric expectation exactly), and a new `TestUsesProvidedLossPerLot()`
proves `Calculate()` uses exactly whatever `loss_per_lot` it is given
(not a recomputed value) and rejects zero/negative supplied values. Full
75-assertion suite passes: `Test_MSZZ_PositionSizing: failures=0`.

**Regression**: all 29 `Test_MSZZ_*`/`Export_MSZZ_Parity` suites pass
(`failures=0`) on the isolated instance, `MultiSpeedZigZagEA.mq5` compiles
0 errors/0 warnings.

## Next: Finding F/G, rerun decision, final certification

See later sections of this document (added incrementally as each finding
is remediated) and `D029_AUDIT_FINAL_REPORT.md` for the full certification.
