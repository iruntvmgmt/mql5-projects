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

## Rerun execution — all 7 configs, patched binary

Executed `D29_SR0`, `SR3_PCT`, `SR4_PCT`, `D29_P3`, `D29_P4`, `P3_SR3`,
`P4_SR3` on the isolated MT5-MSZZ-TEST instance, output to
`/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/<variant>/` — the original
`D029_Phase{2,3,4}_Results/` evidence was never overwritten. Trade counts
reproduce the certified pre-audit numbers closely for the unaffected
controls (`D29_SR0`: 190 trades, matching D029's "190 trades" exactly;
`D29_P4`: 330 vs. the certified 331) — expected, since none of Findings
C/D/E change anything for configs with no partial-close policy or no
volume-min/step mismatch or (as confirmed empirically) no loss-per-lot
difference for XAUUSD.

## Finding B — independent deal-level reconciliation: found and fixed a second real defect

`reconcile_deals_and_r.py` independently reconstructs every trade from
`MSZZ_DealJournal.csv` (Finding B's new instrumentation) and checks
sum(exit volumes)==opening volume, volume-weighted exit price==reported
blended exit price, and price-based recomputed R==reported realized_r,
for all 7 reruns.

**Result: 5 of 7 variants reconciled perfectly (zero mismatches).
`P3_SR3` and `P4_SR3` each had exactly one trade fail reconciliation** —
the *same* underlying signal in both runs (a SweepReclaim short opened
2026.05.28 21:35, partially closed 2026.05.28 22:55, remainder closed via
`OWN_FAMILY_OPPOSITE` 2026.05.29 01:05). Root cause, confirmed by reading
`ExportClosedPortfolioBookFromTrade()`: this function — used for
own-family-opposite closes, protection emergency-closes, and time-stop
force-closes — computed `realized_r` from `book.entry_price` to a single
caller-supplied `exit_price` (the closing deal's own price), silently
ignoring any earlier partial-close deal's price/profit. For this trade,
the partial closed at 4499.19 and the remainder at 4497.53; the true
volume-weighted exit price is 4498.35, but the EA reported 4497.53 (the
remainder-only price), overstating `realized_r` by ~0.186R (reported
1.0433 vs. true 0.857). **This is a pre-existing defect, not introduced by
this audit's other patches — it was already present in D029's original,
certified P3-SR3/P4-SR3 evidence**, just never caught because no prior
check compared the EA's own R computation against independently
reconstructed broker deal data.

**Fixed**: `ExportClosedPortfolioBookFromTrade()` now computes the same
volume-weighted exit price `ExportAndFlattenPortfolioBook()` already used
correctly, from the exact deal scan Finding B's instrumentation added —
reducing to the previous behavior whenever there was only one exit deal
(the common case), and correcting it whenever an earlier partial close
existed. Compiled clean, `Test_MSZZ_Determinism` re-verified clean (no
test file exercises this integration-only function directly, so this is
the applicable regression signal). **All 7 configs were rerun again on
this final, fully-patched binary** (not just P3_SR3/P4_SR3) to keep every
reported number from the same binary — see `trade_level_r_reconciliation.csv`,
`r_reconciliation_summary.csv`, `portfolio_r_reconciliation.csv` for the
final (post-fix) reconciliation, which shows 0 mismatches across all 7
variants once regenerated.

**Materiality**: this affected exactly one trade in each of two 335-345
trade portfolios, changing `P3_SR3`'s and `P4_SR3`'s total portfolio R by
approximately -0.19R each out of totals of +29.85R and +35.62R
respectively (pre-fix, pre-final-rerun figures) — under 1%, not enough to
change either portfolio's standing relative to its matched core (P3/P4
with unmodified fixed-2R SweepReclaim), but a genuine evidence-integrity
defect that had to be found and fixed regardless of its size, per this
audit's own "do not accept compromised runs" standard.

## Final reconciliation, on the final (post-Finding-B-fix) rerun

`reconcile_deals_and_r.py` was re-run against the second (final) rerun
batch — all 7 configs, on the binary with the Finding B fix applied.
Result: **zero mismatches in all 7 variants** (`r_reconciliation_summary.csv`):

| variant | trades checked | volume mismatches | price mismatches | R mismatches | reconciliation_ok |
|---|---|---|---|---|---|
| D29_SR0 | 190 | 0 | 0 | 0 | True |
| D29_P3 | 341 | 0 | 0 | 0 | True |
| D29_P4 | 329 | 0 | 0 | 0 | True |
| SR3_PCT | 194 | 0 | 0 | 0 | True |
| SR4_PCT | 186 | 0 | 0 | 0 | True |
| P3_SR3 | 345 | 0 | 0 | 0 | True |
| P4_SR3 | 333 | 0 | 0 | 0 | True |

("trades checked" is slightly below each variant's total portfolio-row
count because the script only checks broker tickets it can match to
both an entry deal and an exit deal in `MSZZ_DealJournal.csv`; positions
still open at test end, or without a resolvable ticket-to-logical
mapping, are excluded from the denominator rather than counted as
mismatches — this is a coverage limit of the check, not a defect.)

`P3_SR3`'s `reported_total_r` changed from the pre-fix `35.6172`-style
figure to the fix-verified value once recomputed against the same deal
data (see below); `P4_SR3` likewise. Both now agree with the
independently reconstructed value within the script's `R_TOL=1e-3`.

## Control-variant diff investigation (required per the audit instruction: "any difference outside expected timestamp/metadata additions needs investigation")

Direct `diff` of `MSZZ_PortfolioTradeAnalytics.csv` between the ORIGINAL
D029 evidence and the FINAL patched rerun, per variant:

- **`D29_SR0`, `SR3_PCT`, `SR4_PCT`: byte-identical, 0 diff lines.** These
  three never call `ExportClosedPortfolioBookFromTrade()` (`D29_SR0` uses
  the single-book `DetectClosedPositions()` path; `SR3_PCT`/`SR4_PCT` run
  SweepReclaim alone, which also stays on that old D009-era path), so
  neither Finding B's instrumentation nor its fix can touch them, and
  they don't.
- **`D29_P3`: 5 trades differ. `D29_P4`: 6 trades differ. `P3_SR3`: 7
  trades differ. `P4_SR3`: 8 trades differ.** Investigated every diffed
  row by hand: **every single one has `exit_reason=OWN_FAMILY_OPPOSITE`**,
  and every diff is `exit_price`/`realized_r` changing at the
  ~1e-13-relative-magnitude level — e.g. `2922.85` → `2922.8499999999995`,
  `realized_r` `0.43806921675773564` → `0.4380692167576942`. This is
  IEEE-754 floating-point noise, not a logic change: the Finding B fix
  makes `ExportClosedPortfolioBookFromTrade()` always compute
  `weighted_exit_price = Σ(price·volume)/Σ(volume)` from the new deal
  scan, even for the common single-exit-deal case (weight=1), instead of
  passing the caller-supplied price literal straight through. Mathematically
  a weighted average of one term equals that term; numerically, dividing
  `(price·volume)/volume` in double precision does not always reproduce
  the exact original bit pattern of `price`, so the last 1-2 ULPs differ.
  The resulting `realized_r` deltas (~1e-13 to 1e-16) are **8-13 orders of
  magnitude below** both the CSV's own 4-decimal-place precision and the
  reconciliation script's `R_TOL=1e-3` — immaterial at any precision a
  human or downstream aggregate would ever read (confirmed above: the
  rounded headline stats for `D29_P3`/`D29_P4` are identical to 4 decimal
  places pre- vs. post-fix). One of `P3_SR3`'s 7 and `P4_SR3`'s 8 diffed
  rows is **not** float noise — it is the genuine Finding B trade
  (`2026.05.28 21:35` → `2026.05.29 01:05`, logical id containing
  `1779996000`), covered in full below. All other diffed rows in every
  variant are the immaterial float-noise pattern described above — **no
  further, undisclosed defect was found**.

## Headline pre-patch vs. patched-rerun comparison (all 7 variants, portfolio-level, computed identically both eras from `MSZZ_PortfolioTradeAnalytics.csv`)

`headline_pre_post_comparison.csv`:

| variant | era | trades | win rate | expectancy R | PF(R) | total R | max DD (R) |
|---|---|---|---|---|---|---|---|
| D29_SR0 | PRE / POST | 190 / 190 | .3684 / .3684 | .1506 / .1506 | 1.2688 / 1.2688 | 28.6117 / 28.6117 | 18.2941 / 18.2941 |
| D29_P3 | PRE / POST | 342 / 342 | .3655 / .3655 | .1217 / .1217 | 1.2218 / 1.2218 | 41.6064 / 41.6064 | 23.9365 / 23.9365 |
| D29_P4 | PRE / POST | 330 / 330 | .3303 / .3303 | .1443 / .1443 | 1.2472 / 1.2472 | 47.6083 / 47.6083 | 24.2455 / 24.2455 |
| SR3_PCT | PRE / POST | 194 / 194 | .4897 / .4897 | .0807 / .0807 | 1.1776 / 1.1776 | 15.6564 / 15.6564 | 14.9477 / 14.9477 |
| SR4_PCT | PRE / POST | 186 / 186 | .4892 / .4892 | .0795 / .0795 | 1.1752 / 1.1752 | 14.7804 / 14.7804 | 19.5857 / 19.5857 |
| P3_SR3 | PRE / POST | 347 / 347 | .4150 / .4150 | .0860 / **.0855** | 1.1709 / **1.1698** | 29.8514 / **29.6655** | 20.8497 / 20.8497 |
| P4_SR3 | PRE / POST | 335 / 335 | .3791 / .3791 | .1063 / **.1058** | 1.1972 / **1.1961** | 35.6172 / **35.4281** | 22.6597 / 22.6597 |

Trade counts, win rates, and max drawdown are unchanged in every single
variant (rounded figures shown; controls are exactly identical to full
float precision as shown above). Only `P3_SR3` and `P4_SR3` show any
headline movement, and only in `expectancy_r`/`profit_factor_r`/`total_r`
— exactly the metrics the one Finding B trade's R correction feeds into
— by an amount (~-0.186R / ~-0.189R out of totals of ~30R/~36R,
respectively) matching the single trade's R correction almost exactly,
confirming no other change bled into these totals.

## Trade-by-trade: the two confirmed affected trades

### 1. Finding C retry trade (2025.03.25 15:20-15:34, SweepReclaim short) — present in `SR3_PCT`/`SR4_PCT`/`P3_SR3`/`P4_SR3`

- **Old behavior (pre-patch)**: a partial-close protection order (stop-to-breakeven
  modify) failed once and was never retried — a silent, undetected
  protection gap (this is exactly what Finding C's atomicity audit was
  built to catch).
- **New behavior (patched)**: `MSZZ_SweepExitManagementJournal.csv` now
  shows a `PROTECTION_RETRY` event for this exact position (`attempt 2 of
  3`) on the same bar sequence, in all four variants — proving the
  state-machine patch fires. The retry itself also fails (`success=false`)
  — a genuine, still-visible protection-repair failure, not swept under
  the rug.
- **New exit outcome**: **unchanged from the old outcome.** The position
  closes via `BROKER_SL_TP_OR_TEST_END` shortly afterward — an unrelated,
  independent broker-side trigger — before a 3rd retry attempt or the
  emergency-close path could matter. Confirmed byte-identical
  `exit_reason`/`exit_price`/`realized_r` (`r_result≈-0.5372` in
  `P3_SR3`/`P4_SR3`, `≈-0.533` in `SR3_PCT`/`SR4_PCT`) in both the
  original and final-rerun `MSZZ_PortfolioTradeAnalytics.csv` for this
  trade, in all four variants.
- **R difference: 0.** **Occupancy difference: none** — the position's
  open/close timestamps are unchanged, so no later signal's
  eligibility window shifts because of this trade.
- **Downstream cascade: none detected.** No later entry in any of the 4
  variants was blocked or newly enabled as a result of this trade's
  timing, because its timing didn't change.
- **What the patch actually proves here**: the system's protection layer
  now *attempts* recovery and *logs* failure explicitly instead of
  silently doing nothing — a real architectural improvement — even though
  this specific historical trade's realized numbers don't move.

### 2. Finding B R-computation trade (2026.05.28 21:35 → 2026.05.29 01:05, SweepReclaim short, own-family-opposite exit) — present in `P3_SR3`/`P4_SR3` only

- **Old outcome (pre-patch, original certified D029 evidence)**:
  `exit_price=4497.53` (the remainder-close deal's price only, ignoring an
  earlier partial-close deal at 4499.19), `realized_r=1.043280182232252`
  in both `P3_SR3` and `P4_SR3`.
- **New outcome (patched rerun)**:
  - `P3_SR3`: `exit_price=4498.346393442623` (volume-weighted across both
    exit deals), `realized_r=0.8573135666006167`.
  - `P4_SR3`: `exit_price=4498.36`, `realized_r=0.85421412300677`.
  - Both match `reconcile_deals_and_r.py`'s independently-computed values
    to within its `R_TOL=1e-3` (small residual differences are the CSV's
    own 4-decimal rounding, not a discrepancy).
- **R difference**: `P3_SR3`: `1.0433 → 0.8573` (Δ≈-0.186R).
  `P4_SR3`: `1.0433 → 0.8542` (Δ≈-0.189R).
- **Occupancy difference: none.** The position's entry/exit timestamps
  are byte-identical pre/post-fix — only the *reported price and R* of
  the already-recorded exit changed, because the fix corrects a
  computation on data already captured, not the timing of when the
  position closed.
- **Downstream cascade: none detected.** No later entry's eligibility
  window shifts, since occupancy timing is unchanged.
- **Portfolio-level cascade**: this single trade's correction fully
  explains `P3_SR3`'s and `P4_SR3`'s total-R, expectancy, and
  profit-factor movement in the headline table above; max drawdown is
  unaffected (this trade's revised R, while smaller, wasn't the local
  peak-to-trough driver).

## Downstream occupancy cascades — explicit finding: none

Both confirmed affected trades leave their open/close timestamps
unchanged (Finding C's retry attempt happens strictly *within* an
already-open position's lifetime; Finding B's fix corrects a *reported*
price/R on an already-closed position, not the closing event's timing).
Since MSZZ's one-owned-position-per-book occupancy model keys off
open/close timestamps, neither fix could have blocked or newly enabled
any later signal, in any of the 7 variants. This was verified, not
assumed: no other row differs between pre- and post-fix
`MSZZ_PortfolioTradeAnalytics.csv` in any variant beyond the float-noise
rows (explained above) and the one real Finding B trade in `P3_SR3`/`P4_SR3`.

See `D029_AUDIT_FINAL_REPORT.md` for the full 21-point certification.
