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

## Finding G — corrected partial-fraction terminology

The original Phase 3 analyzer (`Tools/D029/Phase3/analyze_partials.py`)
computed `abs(f-0.5)<0.02` and stored it in a variable named `exact_50` —
a 2-percentage-point *tolerance* bucket, not floating-point exactness. Its
own printed label ("within_2pct_of_50%") was more honest than the variable
name, but the underlying bucketing itself still collapsed everything from
a perfect 50.0000% split down to a 48.00% split into one undifferentiated
number, and no report anywhere separated "landed exactly on 50%" from
"came close because of step-rounding" from "meaningfully skewed."

`Tools/D029/Audit/corrected_partial_fraction_analysis.py` reprocesses the
same `MSZZ_PartialCloseJournal.csv` data (SR3_PCT, SR4_PCT, P3_SR3, P4_SR3)
with the categories the handoff requires: exact 50.0000% (floating
tolerance 1e-6), within 1 percentage point (excluding exact), within 2
percentage points (excluding within-1pp), outside 2 percentage points, and
min/max/mean/median of the executed fraction. Output:
`corrected_partial_fraction_summary.csv`.

| variant | n | exact 50.0000% | within 1pp | within 2pp | outside 2pp | min | max | mean | median |
|---|---|---|---|---|---|---|---|---|---|
| SR3_PCT | 86 | 42 (48.84%) | 26 (30.23%) | 9 (10.47%) | 9 (10.47%) | 0.4444 | 0.5000 | 0.4932 | 0.4980 |
| SR4_PCT | 82 | 36 (43.90%) | 25 (30.49%) | 9 (10.98%) | 12 (14.63%) | 0.4444 | 0.5000 | 0.4918 | 0.4967 |
| P3_SR3  | 64 | 37 (57.81%) | 15 (23.44%) | 9 (14.06%) | 3 (4.69%)   | 0.4706 | 0.5000 | 0.4955 | 0.5000 |
| P4_SR3  | 63 | 32 (50.79%) | 16 (25.40%) | 11 (17.46%) | 4 (6.35%)   | 0.4706 | 0.5000 | 0.4946 | 0.5000 |

The finer breakdown reveals something the collapsed bucket hid: 10-15% of
partials in every variant land **outside** even a 2pp tolerance of 50%
(e.g. SR4_PCT's minimum observed fraction is 44.44%, not "approximately
50%"). This is expected and benign — volume-step rounding on small
positions can legitimately produce splits well short of 50/50 (the same
phenomenon Phase 3's own doc already described qualitatively, e.g. "a
0.07-lot position splits 0.03/0.04, not 0.035/0.035") — but the original
collapsed "within 2%" number obscured the actual shape of the
distribution. No conclusion in D029 rested on the exact fraction
distribution (the frozen decision was always "50% target, broker-clamped
by volume step," never "exactly 50% achieved"), so this is a
terminology/reporting correction, not a finding that changes any D029
result.

## Finding F — production-gap disclosure (documentation only, nothing built)

Per the handoff: "Do not optimize these" / build these — document only.
Percentage-of-equity sizing (`MSZZ_SIZE_PERCENT_EQUITY`) is
**research-validated only**. Before any live/demo deployment beyond the
isolated sandbox, the following production-grade guards are required and
do **not** currently exist anywhere in this codebase:

- **Max lots per order** — no ceiling independent of the risk-percent
  calculation; a sizing bug or extreme equity/stop-distance combination
  could request an arbitrarily large single order (bounded today only by
  `SYMBOL_VOLUME_MAX`, which is a broker limit, not a risk control).
- **Max gross lots per symbol** — no aggregate cap across all open
  books/positions for one symbol; `CMSZZPortfolioRiskManager` caps
  *percentage risk*, not raw volume exposure.
- **Max gross notional exposure** — no dollar/account-currency notional
  ceiling independent of percentage risk (percentage risk assumes the
  stop is honored; notional exposure is what's actually at stake between
  now and the stop being hit).
- **Max margin utilization** — `MarginGuard.mqh` (D012) checks margin
  *before an individual order*, not aggregate portfolio-wide utilization
  as a standing limit.
- **Max expected slippage guard** — no check that a fill's actual price
  didn't move the realized risk materially beyond what was sized for.
- **Stop-distance anomaly guard** — no sanity check rejecting a
  candidate whose stop distance is implausibly tiny (produces an
  oversized volume) or implausibly huge (produces a near-zero, barely
  meaningful position) relative to the instrument's typical range.

These are standing gaps, not defects introduced by D029 or this audit —
percentage sizing was always scoped as research-only
(`DUAL_MODE_RECOMMENDED`, per D029's final decision). Listed here so the
final certification's "remaining production gaps" section has a concrete,
itemized list rather than a vague caveat.

## Finding H — portfolio-integrity check battery (pre-rerun baseline)

`Tools/D029/Audit/audit_portfolios.py` checks, for each of SR3_PCT,
SR4_PCT, P3_SR3, P4_SR3: native-vs-logical trade count consistency,
duplicate `logical_position_id` values, strategy/family attribution
consistency, partial-close counts, risk-cap sequence integrity (every
approved action's resulting portfolio risk checked against the frozen
0.50% cap), an exit-management action inventory checked against a
whitelist grounded in the EA's actual `JournalExitManagement()` action
labels (not guessed — verified against real observed values first;
`MSZZ_TradeAnalytics.csv`'s own `exit_reason` field turned out to be a
generic MT5-level string for the single-book runs, not a per-policy
classification, so the real check uses
`MSZZ_SweepExitManagementJournal.csv`'s `action` field instead), top-1/3/5
exclusion, best-quarter exclusion, dev/val/holdout split, long/short
split, and a SHA-256 hash of every input file read. Produces
`portfolio_integrity_audit.csv` and `output_hashes.csv`.

**Result on the current (pre-rerun) evidence: `overall_integrity_ok =
True`** — no duplicate IDs, no attribution mismatches, no risk-cap
violations, no unknown exit-management actions, native/logical counts
consistent, across all four variants. This confirms Finding C's defect
(one unprotected partial per run) is an isolated execution-safety gap, not
a symptom of broader portfolio-bookkeeping corruption — but per the rerun
decision below, **this is a pre-rerun baseline, not certification
evidence**, and must be re-run against the rerun's fresh output once that
lands (`ROOTS` in the script point at the original Phase 3/4 directories
and will need updating).

`analyze_d029_audit.py` (the remaining Finding H script — a single
umbrella script tying together A/C/G/H's individual outputs into one
pass/fail summary) and `reconcile_deals_and_r.py` (Finding B) are still
open; see "Next" below.

## Finding B instrumentation — deal-level journal (minimum needed for independent reconciliation)

Added `CMSZZPortfolioJournals::JournalDeal()` (`MSZZ_DealJournal.csv`:
`time;book_id;strategy_id;position_ticket;deal_ticket;entry_type;volume;
price;commission;swap;profit`) and wired it into the three places a
position's closing deals are already read from broker history:
`ExportAndFlattenPortfolioBook()` (the common broker-SL/TP/test-end path),
`DetectClosedPositions()` (the single-book intent path), and
`ExportClosedPortfolioBookFromTrade()` (own-book-opposite/protection-
emergency-close/time-stop paths, which added their own `HistorySelect()`
deal scan for this purpose since they previously received only a
pre-computed exit price).

**This is a read-only, post-hoc journal — it changes no execution
timing or decision logic.** Every call site already performs a
`HistoryDealsTotal()`/`HistoryDealGetTicket()` scan to compute
`exit_price`/`realized_r` from broker history; `JournalDeal()` is called
once per deal already being read in that same scan, strictly after the
position has closed. `exit_price` and `realized_r` are computed exactly
as before, from the same values — the new journal calls do not
participate in that computation at all, only observe and record it.
Compiled clean (0 errors/0 warnings); full 29-suite regression re-run and
confirmed `failures=0` across every suite (no test file exercises these
functions or `PortfolioJournals.mqh` directly, so this was expected, but
verified rather than assumed).

This is the minimum instrumentation needed for `reconcile_deals_and_r.py`
to independently verify sum(exit volumes)==opening filled volume, the
volume-weighted exit price, and price-based R — the original Phase 3/4
runs never captured per-deal detail, so this could not be checked
independently until now. It only takes effect on **new** runs; the
original (pre-rerun) evidence has no `MSZZ_DealJournal.csv` and cannot be
retroactively reconciled at the deal level — another reason, alongside
Finding C's confirmed defect, that a full rerun is required.

## Next: rerun execution, independent reconciliation, final certification

See later sections of this document (added incrementally as each finding
is remediated) and `D029_AUDIT_FINAL_REPORT.md` for the full certification.
