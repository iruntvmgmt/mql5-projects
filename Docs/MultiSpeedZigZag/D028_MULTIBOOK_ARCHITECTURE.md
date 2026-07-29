# D028 — Multi-Book Portfolio Architecture

## Decision status

**Stage 0B complete; Stage 1 architecture implemented default-off on
2026-07-28.**

D028 begins at `dc14d99f9cc97404b93ec17aa9dc6b589e41b9b4` on
`feature/d028-multibook-portfolio`. The isolated tester is a **HEDGING**
account, so it can represent separate physical strategy positions. A virtual
netting ledger remains a required architectural component for portability.

The standalone controls reproduced exactly. Stage 0B repaired the pre-existing
candidate-array indexing defect and established the corrected 372-trade legacy
combined control. Historical D027 combined evidence remains preserved but
invalidated for combined-baseline comparison.

## Non-negotiable design

The eventual architecture remains:

```text
causal strategy signal engines
        ↓
independent logical strategy books
        ↓
portfolio risk manager
        ↓
hedging/netting execution coordinator
        ↓
broker positions
```

Each book will own its strategy/family identity, magic, logical position,
entry, stop, target, trailing/partial/time-stop state, opposite-signal policy,
risk allocation, persistence, and accounting. Cross-family mutation will be
disabled under independent-books research. The portfolio manager—not an
unrelated strategy signal—will determine whether additional exposure is
allowed.

New behavior will be disabled by default. Legacy behavior will remain the
default until an explicit research configuration selects another policy.
Canonical A, canonical E, SweepReclaim entry logic, and all D027 decisions
remain unchanged.

## Account-mode audit

- Environment: `/Users/matt/MT5-MSZZ-TEST`
- Symbol/timeframe: XAUUSD M5
- History window: 2025-03-01 through 2026-07-24
- Execution model: MT5 `Model=2`
- Detected mode: `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`
- Tester log label: `MSZZ OWNERSHIP REFRESHED mode=HEDGING`
- Physical simultaneous positions: supported by the isolated tester
- Virtual books: not required for this tester, but required by the D028 design
- Live account: not used

The current ownership layer already queries `ACCOUNT_MARGIN_MODE` in
`Include/MultiSpeedZigZag/Execution/PositionOwnership.mqh`; D028 must preserve
explicit hedging/netting/exchange handling rather than infer account behavior.

## Stage 0 control audit

Fresh runs used configs tracked in `Tools/D028/` and results stored externally
under `/Users/matt/MT5-MSZZ-TEST/D028_Stage0_Results`.

| Control | Trades | Cumulative R | Expectancy R | PF | Max DD R | Result |
|---|---:|---:|---:|---:|---:|---|
| FastMedConfluence A 2R | 224 | 28.2447 | 0.1261 | 1.2446 | 15.1583 | exact |
| SweepReclaim 2R | 190 | 28.6117 | 0.1506 | 1.2688 | 18.2941 | exact |
| Legacy A + Sweep 2R, fresh | 372 | 23.0157 | 0.0619 | 1.1253 | 25.2800 | mismatch |
| Legacy A + Sweep 2R, D027 certified | 371 | 20.7400 | 0.0559 | 1.1129 | 25.2798 | reference |

The A and SweepReclaim trade-analytics rows are byte-equivalent as parsed CSV
records to their certified standalone controls. The combined control differs
in two FastMedConfluence entries and adds one FastMedConfluence trade.

## Baseline defect

`CMSZZStrategySuite::AddCandidate` grows its output array in blocks:

```cpp
if(count>=ArraySize(out)) ArrayResize(out,count+16);
```

The EA then appends D027 candidates at allocated size rather than logical
count:

```cpp
int at=ArraySize(candidates);
ArrayResize(candidates,at+1);
candidates[at]=d027_candidates[i];
candidate_count++;
```

When A emits one candidate, the legacy array has logical count 1 and allocated
size 16. SweepReclaim is written at index 16, while the subsequent loop
processes indices 0 and 1. Index 1 is uninitialized. The D027 and fresh D028
signal journals contain malformed `RAW_CANDIDATE` rows with impossible
strategy IDs/prices, directly confirming the invalid read.

Different uninitialized values changed whether the real A candidate executed:

- 2025-12-19 17:00 versus 17:30
- an additional execution on 2026-05-28 19:40

This is not a market-data, account-mode, strategy-trigger, or standalone
equivalence failure. It is undefined combined-candidate arbitration behavior.

## Required resolution before Stage 1

Do not implement multi-book architecture until the owner selects how to
rebaseline the invalid legacy control. The defensible route is:

1. Fix the append/indexing defect without changing any signal definition.
2. Add a deterministic regression covering a legacy candidate plus a D027
   candidate in the same bar.
3. Compile with zero errors/warnings and run every existing MSZZ suite.
4. Re-run A, SweepReclaim, and combined controls.
5. Preserve standalone exact equivalence.
6. Declare the corrected deterministic combined result as a superseding D028
   control while leaving historical D027 artifacts untouched.

That route cannot honestly reproduce the invalid 371-trade path exactly. It
requires explicit authorization because the D028 specification says not to
proceed when baseline parity fails.

## Planned layers after resolution

1. `StrategyBook.mqh`: independent logical ownership and per-book exits.
2. `PortfolioRiskManager.mqh`: fixed portfolio, strategy, family, direction,
   symbol, loss, drawdown, and book-count caps.
3. `ExecutionCoordinator.mqh`: ticket isolation on hedging accounts and broker
   net-difference execution on netting/exchange accounts.
4. `VirtualNettingLedger.mqh`: virtual basis, quantity, synthetic stops,
   realized/unrealized R, and proportional cost attribution.
5. Portfolio journals: book state, risk decisions, execution allocations, and
   logical trade analytics.

No D028 strategy or exit result is claimed by this checkpoint.

## Stage 1 architecture checkpoint — 2026-07-28

Stage 1 adds the portfolio abstractions without routing any live or historical
trade through them:

- `StrategyBook.mqh` defines independently owned book identity, tickets,
  logical position identity, risk, and per-book exit configuration.
- `PortfolioRiskManager.mqh` fail-closes on total, book, family, directional,
  physical-position, logical-book, daily-loss, drawdown, and symbol limits.
- `CrossFamilyPolicy.mqh` makes legacy reverse, ignore, flatten-only,
  regime-exclusive, and independent-book behavior explicit.
- `ExecutionCoordinator.mqh` detects the account margin mode. It plans
  ticket-isolated physical actions for hedging and net-difference actions with
  synthetic protection for netting/exchange accounts.
- `VirtualNettingLedger.mqh` maintains attributable logical allocations and
  broker net-difference calculations. Persistence/restart reconciliation and
  synthetic-stop processing remain Stage 2 test-gated work.
- `PortfolioJournals.mqh` defines the four required book, risk, allocation, and
  logical-trade journals.

The EA inputs default to `InpEnableMultiBookPortfolio=false`. When explicitly
enabled at this checkpoint, initialization deliberately fails closed after
validating the architecture and reporting the detected account mode. Broker
transmission is intentionally not wired until Stage 2 deterministic tests and
Stage 3 single-book equivalence are complete. This prevents a partially
implemented research mode from silently falling back to legacy shared
ownership.

The isolated account remains `HEDGING`, so the first portfolio experiment can
use real ticket/magic isolation. The virtual netting abstraction is retained
for portability but is not being presented as production-ready; netting
synthetic stops require an uninterrupted EA and do not provide broker-hosted
protection.

Stage 1 changes no signal, score, cluster priority, entry, stop, exit, cost,
window, canonical A/E definition, or SweepReclaim trigger. Legacy shared
ownership remains the default comparison control. Stage 2 must provide the
full deterministic unit/integration suite before any architecture activation.

## Stage 2 deterministic portfolio tests — 2026-07-28

Stage 2 hardened and tested the architecture without activating portfolio
execution. Five required suites add 68 deterministic assertions:

- strategy-book identity, ownership, transition, and non-mutation checks;
- portfolio book/strategy/family/direction/physical/risk limit checks;
- deterministic hedging, netting, and exchange execution plans;
- cross-family legacy, ignore, flatten-only, regime-exclusive, and independent
  policy decisions;
- virtual netting increases, reductions, offset-to-flat, reversal-through
  zero, partial-close attribution, proportional costs, simultaneous synthetic
  stop/target observations, persistence, restart reconciliation, and malformed
  state rejection.

`ExecutionCoordinator::ConfigureForMode()` is a deterministic abstraction seam
only. Production configuration continues to read `ACCOUNT_MARGIN_MODE` from
the terminal. It does not allow the EA input surface to spoof account mode.

The virtual ledger now persists exact logical allocations and rejects unknown,
truncated, wrong-symbol, wrong-schema, and malformed records before replacing
in-memory state. Synthetic stop and target methods only identify causal
triggers; broker submission and simultaneous-event ordering remain execution
work for Stage 3 integration and equivalence.

The EA and all 27 `Test_MSZZ_*` scripts compiled with zero errors and zero
warnings in `/Users/matt/MT5-MSZZ-TEST`. All 27 runtime suites passed with zero
failures. Final default-off shadows remained exact:

| Window | Raw candidates | Clusters | Malformed | Trades |
|---|---:|---:|---:|---:|
| short | 113 | 46 | 0 | 0 |
| long | 431 | 178 | 0 | 0 |

Stage 0B's certified A and SweepReclaim standalone controls were reused rather
than regenerated: no signal/execution path is reachable while the new mode is
disabled, and exact shadow parity proves the legacy default remains unchanged.
Stage 3 must now reproduce A, E, and SweepReclaim through the new single-book
path before any combined portfolio test.

Stage 2 does not claim single-book portfolio equivalence, a combined portfolio
result, a SweepReclaim management result, production readiness, or approval to
remove the activation block.

## Stage 3 single-book equivalence — 2026-07-28

Stage 3 activates exactly one logical book on the isolated HEDGING tester.
Activation requires:

- `InpEnableMultiBookPortfolio=true`;
- `INDEPENDENT_BOOKS`;
- exactly one enabled strategy;
- FastMedConfluence or SweepReclaim;
- detected physical ticket isolation.

Every other Stage 3 combination fails initialization. The active book reuses
the run's certified `InpMagic` so ownership, intent persistence, protection,
deal reconciliation, and established analytics remain directly comparable.
Distinct simultaneous book magics remain Stage 4 work.

The book now approves each entry through the portfolio risk manager, binds its
logical position ID to the durable cluster ID, validates a hedging physical
execution plan, owns the returned order/position ticket, supplies its own
target R, and returns flat only when its own ticket closes. All logical trades,
including opposite-signal closures, reconcile into
`MSZZ_PortfolioTradeAnalytics.csv`.

Exact full-history results:

| Book | Target | Trades | Cumulative R | Expectancy R | PF | Max DD R | Long | Short |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FastMedConfluence A | 2R | 224 | 28.2447 | 0.1261 | 1.2446 | 15.1581 | 107 | 117 |
| FastMedConfluence E | 3R | 213 | 31.2465 | 0.1467 | 1.2532 | 16.9204 | 101 | 112 |
| SweepReclaim | 2R | 190 | 28.6117 | 0.1506 | 1.2688 | 18.2941 | 96 | 94 |

Each new `MSZZ_TradeAnalytics.csv` is byte-identical to its certified control.
The 627 portfolio logical-trade rows have zero missing, unexpected, or
duplicate IDs; direction, entry time, and exit time have zero mismatches.
Computed R differs from the certified four-decimal field by less than 0.00005R,
which is solely the certified CSV's display rounding.

All 27 scripts compiled with zero errors/warnings and all 27 runtime suites
passed. Default-off shadows remain 113/46 and 431/178 candidates/clusters,
zero malformed candidates, and zero trades.

No combined configuration was run. This proves single-book equivalence and
per-book target selection in isolation; it does not yet prove simultaneous
FastMed 3R plus SweepReclaim 2R execution. Stage 4 remains the first combined
portfolio test.

## Stage 0B integrity addendum — 2026-07-28

The owner authorized a bounded repair of the candidate-index defect. Historical
D027 artifacts and commits were not changed.

### Root cause and affected scope

`CMSZZStrategySuite::AddCandidate()` grew its internal array in blocks of 16.
The EA treated `ArraySize(candidates)` as the next logical index when appending
a D027-family candidate, even though `candidate_count` could be 1. In an
A+SweepReclaim bar, SweepReclaim was placed at physical index 16 while the
processing loop read logical index 1. That uninitialized slot could pass or
fail unpredictably depending on its incidental memory contents.

The defect affected combined execution whenever at least one legacy-suite
candidate and one D027-family candidate shared a handoff. It did not affect:

- canonical A alone, because only the legacy candidate at logical index 0 was
  processed;
- SweepReclaim alone, because the empty legacy array had physical size zero
  and the D027 candidate occupied index 0;
- certified standalone A, E, and SweepReclaim evidence.

The full audit covered `StrategySuite`, `D027StrategyFamilies`, the EA combined
append/filter loop, `OpportunityClusterEngine`, and every candidate
count/index handoff found by repository search. D027's emitter already returned
an exact-size array. The faulty cross-suite append was the only path mixing
allocated size with logical count.

### Correction

`Include/MultiSpeedZigZag/Core/CandidateHandoff.mqh` now defines the subsystem
boundary contract:

- collections must be compact (`logical_count == ArraySize`);
- append uses and returns the logical appended index;
- every processed candidate must be explicitly valid and carry a known
  strategy, family, direction, event/origin identity, finite score, and
  positive entry/stop/target;
- negative, oversized, or sparse counts fail closed with deterministic
  diagnostics.

`StrategySuite::Evaluate()` shrinks internal capacity to its exact logical
count before returning. The EA validates both source collections, appends D027
candidates through the handoff contract, validates the filtered collection,
and checks the returned index. `OpportunityClusterEngine::Build()` validates
the complete collection before reading it and returns `-1` plus
`LastDiagnostic()` on failure. Newly allocated cluster records are explicitly
zero-initialized.

The validator deliberately does not require provisional signal-close geometry
to match final fill geometry. Existing candidates can carry a structural stop
on the other side of the signal close and are normalized later by the
unchanged execution preparation path. Enforcing that additional assumption
changed the standing shadow count and was removed before final testing.

No trigger, score, clustering priority, execution preparation, cost, exit,
window, A/E definition, or standalone configuration changed.

### Deterministic tests

`Test_MSZZ_CandidateHandoff.mq5` adds 36 passing assertions covering:

- first append and real index 16 append;
- sparse/uninitialized rejection;
- exact initialized/logical counts;
- two-strategy identity and enabled-order independence;
- preservation of strategy, family, direction, event, origin, score, entry,
  stop, and target;
- invalid required identities;
- count beyond array size;
- cluster-boundary rejection and deterministic diagnostics.

The EA and all 22 `Test_MSZZ_*` scripts compiled in the isolated instance with
zero errors and zero warnings. All 22 runtime suites passed with zero
assertion failures. Final shadows reproduced 113/46 (short) and 431/178 (long)
raw candidates/unique clusters, with zero malformed candidates and zero
trades.

### Corrected baselines

| Result set | Trades | Deals | Cumulative R | Expectancy R | PF | Max DD R |
|---|---:|---:|---:|---:|---:|---:|
| B0 canonical A 2R | 224 | 448 | 28.2447 | 0.1261 | 1.2446 | 15.1581 |
| B1 SweepReclaim 2R | 190 | 380 | 28.6117 | 0.1506 | 1.2688 | 18.2941 |
| B2 corrected legacy A+Sweep 2R | 372 | 744 | 23.0157 | 0.0619 | 1.1253 | 25.2798 |

B0 and B1 match their certified trade-analytics rows exactly.

B2 contains 1,093 raw candidates: 717 A and 376 SweepReclaim. All 1,093 are
valid and initialized. There are 1,018 selected-cluster events, 867 unique
cluster IDs, 372 executions/trades, and 744 deals. A owns 246 trades and
SweepReclaim owns 126. Exit attribution is 153 SL, 97 TP, 56 own-family
opposite exits, 66 cross-family opposite exits, and zero unknown exits. Against
B0, the shared lifecycle retains 215 core clusters, displaces 9, and newly
executes 31.

Frozen-window B2 results are:

- Development: 229 trades, +13.3638R, 0.0584R expectancy.
- Validation: 79 trades, +1.5663R, 0.0198R expectancy.
- Final holdout: 64 trades, +8.0856R, 0.1263R expectancy.

All analytics/native-report trade counts, deal counts, window totals, owner
counts, candidate outcomes, and exit classes reconcile.

### Historical status and forward gate

D027 Stage 6's historical A+Sweep result remains stored exactly as originally
produced: 371 trades and +20.7400R. Its journal contains 19 malformed raw
candidates caused by undefined index reads. A separate fresh pre-fix D028 run
contains 24 malformed rows, demonstrating the memory-dependent path.

The D027 Stage 6 combined result is therefore formally:

`INVALIDATED_FOR_COMBINED_BASELINE_COMPARISON`

It is not deleted, regenerated, rewritten, or retroactively replaced. B2 is the
new authoritative D028 legacy shared-ownership control. Standalone D027 A, E,
and SweepReclaim evidence remains valid and unchanged.

Stage 1 is now unblocked. It was not started in the Stage 0B change set.

## Stage 4 independent-book portfolio tests — 2026-07-28

Stage 4 extends the exact Stage 3 single-book path to the supported
FastMedConfluence plus SweepReclaim pair. On the isolated HEDGING account each
book has its own physical ticket and magic:

- FastMedConfluence: `27084001`;
- SweepReclaim: `27124002`.

The direct path processes FastMed first and Sweep second, clusters each
strategy independently, consumes a strategy-qualified durable event key, and
allows a book to close only its own ticket. Portfolio approval is applied
after any own-family close. The fixed research limits are 0.25% recorded
initial risk per book, 0.50% total, two books, and one book per strategy.
Cross-family close and reverse actions are disabled.

Per-book target selection is active in one actual combined run:
FastMedConfluence E retains 3R while SweepReclaim retains 2R. Legacy/default-off
execution and the corrected shared-ownership policy remain unchanged.

### Actual combined results

| Run | Trades | Cumulative R | Expectancy R | PF | Max DD R |
|---|---:|---:|---:|---:|---:|
| P1 corrected legacy A2R + Sweep2R | 372 | 23.0157 | 0.0619 | 1.1253 | 25.2798 |
| P2 independent A2R + Sweep2R, no opposing | 292 | 21.9900 | 0.0753 | 1.1381 | 18.1583 |
| P3 independent A2R + Sweep2R, opposing | 343 | 39.9275 | 0.1164 | 1.2132 | 23.5883 |
| P4 independent E3R + Sweep2R, opposing | 331 | 45.9294 | 0.1388 | 1.2389 | 24.2455 |

These are actual EA results, not arithmetic sums. Portfolio constraints change
which standalone opportunities execute.

P3 contributes 209 FastMed trades/+23.4386R and 134 Sweep trades/+16.4889R.
It exceeds A alone by +11.6828R, with 8.4302R more drawdown. Against P1 it
adds +16.9118R while drawdown is 1.6915R lower.

P4 contributes 199 FastMed trades/+27.4405R and 132 Sweep trades/+18.4889R.
It exceeds E alone by +14.6829R, with 7.3251R more drawdown. P4 proves that
different fixed targets coexist in one executed portfolio.

P2's no-opposing constraint leaves SweepReclaim nearly flat: 77 trades and
+0.3146R. P3 permits 69 simultaneous-book episodes (57.2964 hours); P4
permits 74 (60.7944 hours). Every simultaneous interval is opposing, none is
same-direction, and maximum recorded initial risk is 0.50%. P2 has no
simultaneous exposure and reaches 0.25%.

Development, validation, and final holdout cumulative R are positive for all
three independent configurations. P3 is +20.5393R/+5.8524R/+13.5358R; P4 is
+17.1392R/+12.8524R/+15.9378R.

### Integrity and reconciliation

Native reports reconcile exactly:

| Run | Native trades | Native deals | Logical closes | Allocation opens |
|---|---:|---:|---:|---:|
| P2 | 292 | 584 | 292 | 292 |
| P3 | 343 | 686 | 343 | 343 |
| P4 | 331 | 662 | 331 | 331 |

All logical IDs are unique. There are zero per-book target errors, zero
own-book reconciliation rejects, and zero cross-family actions. Own-family
opposite exits are 70/70/71 for P2/P3/P4.

During integrity review, an April 10 Sweep own-family close was initially
recorded one bar late because MT5 history was not visible immediately after a
successful `PositionClose`. This produced a generic exit label and rejected
the replacement entry. The implementation now journals the successful close
directly from the trade result before risk evaluation. P2–P4 were rerun; the
event is explicitly `OWN_FAMILY_OPPOSITE`, the replacement is independently
rejected by the configured same-direction rule, and no reconciliation reject
remains. This was not a cross-family close.

Each final run reports one broker `ORDER_FAILED` candidate with an
`invalid stops` retcode. It creates no trade or deal and does not break any
reconciliation. Six spread rejects and the unchanged stop-preparation rejects
are also preserved in the signal journals.

The EA and all 28 test scripts compile with zero errors/warnings. All 28
runtime suites pass, including routing 11/11, portfolio risk 15/15, strategy
book 16/16, and virtual netting 18/18. Default-off shadows remain 113/46 and
431/178 candidates/clusters, zero malformed candidates, and zero trades.
The Stage 4 analyzer ran twice with byte-identical outputs.

Tracked evidence is under `Tools/D028/Stage4`; exact raw reports and journals
remain under `/Users/matt/MT5-MSZZ-TEST/D028_Stage4_Results`.

### Stage decision

Independent hedging books preserve ticket ownership, eliminate unauthorized
cross-family exits, respect the fixed risk cap, and materially improve the
actual A and E portfolio results when opposing books are permitted. This
passes the Stage 4 engineering/research gate only. It does not approve
production use, select an architecture category, or promote SweepReclaim.

Stage 5 remains the bounded SweepReclaim exit-management study. No Stage 5
variant was implemented or run in this checkpoint.

## Stage 5A — bounded per-book exit-policy architecture

Continuation picked up via a Codex-to-Claude handoff after Codex's usage
expired (`D028_Continuation_Handoff_Stages_5_6_Final.md`). Starting SHA
`346e20a` audited first: branch, local/remote HEAD, and D028 paths all
matched the handoff exactly; unrelated Quant Beast/platform files were the
same pre-existing untouched noise present throughout this whole branch.
Stage 4's P1-P4 numbers were independently cross-checked against
`Tools/D028/Stage4/portfolio_summary.csv` to full floating-point precision
(not rounded) before being accepted as a checkpoint.

### Design

`ENUM_MSZZ_SWEEP_EXIT_POLICY` (SR0-SR5) is selected per book via the
already-existing `MSZZBookExitConfig.trailing_policy_id` field (Stage 4 had
declared but never populated it) — no new struct field was needed for the
selector itself. `MSZZStrategyBookState` gained the minimal bookkeeping SR1-
SR5 actually need (`max_favorable_r`, `breakeven_activated`,
`structure_activated`, `highest/lowest_since_activation`, `effective_stop`,
`time_stop_evaluated_done`), reset on every new entry and reseeded from the
current broker-side stop (never a remembered value) if ever found missing —
the identical restart-safety pattern D026's trailing-stop research already
established and this branch has reused ever since.

`Include/MultiSpeedZigZag/Portfolio/BookExitManager.mqh`
(`CMSZZBookExitManager`) is the pure per-book dispatcher. It deliberately
reuses `CMSZZResearchTrailPolicy` (D026) directly for favorable-R,
monotonic-tightening, and confirmed-swing-candidate logic rather than
duplicating it — the same "no future pivot access, only confirmed pivots,
monotonic tightening only, broker-distance-valid only" contract already
proven in D026 and D024's Bug-1 fix applies unchanged here. SR0 is always a
provable no-op (`Evaluate()` returns `false` immediately). Every threshold
below is frozen here, before any SR1-SR5 backtest result is inspected, per
the handoff's own anti-overfitting instruction:

- **SR1 breakeven**: activates once, the first closed bar `fav_r>=1.0R`,
  moving the stop to **exactly** entry (no cost offset — the handoff's own
  wording is "move stop to entry," not "entry plus costs," followed
  literally rather than importing D026's own different convention for its
  own, textually distinct research variants).
- **SR2 structural trail**: activates once `fav_r>=1.0R`, then trails behind
  the latest confirmed Fast-speed swing every bar, monotonic tightening
  only. The fixed +2R target is never touched.
- **SR3 partial fixed**: one-shot at `fav_r>=1.0R` — closes exactly 50% of
  logical volume, moves the remainder's stop to exactly entry, and leaves
  the +2R target active for the remainder.
- **SR4 partial + runner**: identical activation/partial to SR3, but removes
  the fixed target for the remainder and trails it behind confirmed Fast
  swings (SR2's trail logic, reused) from that point forward — the only
  uncapped-runner variant authorized, per instruction.
- **SR5 time stop**: force-closes at exactly 48 closed M5 bars (4 hours)
  since entry if the position's `max_favorable_r` has never yet reached
  `+0.5R`. Reasoning for `N=48`: picked from structural session reasoning
  (half of one 8-hour trading session) before any SR5 result was inspected,
  per instruction — not tuned. Once `+0.5R` has ever been reached, the time
  stop never applies again for that position, exactly as specified
  ("retain canonical 2R management").

Same-bar ordering matches this branch's established discipline (D026):
`DetectClosedPortfolioBooks()` (prior-bar closure) -> engine rebuild ->
regime label -> `ProcessBookExitManagement()` (this bar's confirmed
exit-management update) -> candidate evaluation / opposite-signal exit.
Failed broker calls (`PositionModify`/`PositionClosePartial`) never desync
in-memory bookkeeping from broker truth — state is only persisted via
`CMSZZStrategyBook::UpdateExitManagementState()` after a successful call is
confirmed, mirroring D025's same discipline for partial closes.

Only the Sweep book's exit policy varies (`InpSweepExitPolicy`, default `0`
= SR0, validated fail-closed to `0`-`5` in `OnInit()`). FastMedConfluence's
book is never touched by Stage 5 — its `exit_config.trailing_policy_id`
stays `0` in every Stage 5 config, per the handoff's "Do not change
FastMedConfluence A or E."

### Rejected alternatives

- **A single global exit-policy input covering both books**: rejected per
  the handoff's own explicit instruction ("Do not introduce a global exit
  input that changes both books").
- **Adding a cost offset to the breakeven moves** (matching D026's own T1
  convention): rejected — the D028 handoff's literal wording differs from
  D026's, and this entry follows the instruction as given rather than
  silently importing a different research track's convention.
- **Duplicating D026's trailing-stop math inside a new Stage-5-specific
  class**: rejected as unnecessary risk — `CMSZZResearchTrailPolicy` is
  already causal, tested, and proven; Stage 5 reuses it directly.

### Stage 5A checkpoint verification

30 deterministic `Test_MSZZ_*`/`Export_MSZZ_Parity` suites compile and pass
at 0 failures/0 errors on the new binary (live tree and isolated instance,
hash-verified identical), including the 16 new `Test_MSZZ_BookExitManager`
cases (SR0 no-op; SR1 one-shot exact-entry breakeven with no re-fire; SR2
stale/wrong-side-swing rejection, valid-swing tightening, and never-widen;
SR3 one-shot partial+breakeven-remainder with no re-fire; SR4 target removal
on partial and runner-trail-only-after-partial; SR5 no-fire-before-window,
fire-exactly-at-window, and never-fire-once-threshold-reached; two
`CMSZZStrategyBook` restart-safety/rejection-when-not-open cases).

Both `shadow_d027_short.ini`/`shadow_d027_long.ini` runs reproduce the exact
same **113 candidates/46 clusters (short)** and **431 candidates/178
clusters (long)** with **zero orders/zero deals** as every prior shadow
baseline on this branch — `InpSweepExitPolicy=0` (SR0, the default) is a
proven no-op. Standalone full-window reproductions all match the certified
numbers exactly: **A: 224 trades/+0.1261R/PF 1.2446**; **E: 213
trades/+0.1467R/PF 1.2532**; **SweepReclaim SR0 (legacy single-strategy
path, untouched by the new book architecture): 190 trades/+0.1506R/PF
1.2688/18.2941R max DD**.

One operational bug found and fixed while running this checkpoint, worth
recording for future batch scripts on this machine (the third time this
exact class of bug has appeared on this branch — D026 and D027 both hit
variants of it): MT5's `/config:` argument parser splits on `/`, silently
truncating a relative path at the first forward slash inside a subdirectory
component. A batch script step using `${WINROOT}\\D026_Configs/file.ini`
(backslash before the directory, forward slash before the filename) left
the isolated terminal idle for 17 minutes with no Tester job ever loaded,
not a crash or an error — caught by noticing the process had produced no
new journal activity, not by any test failing. Fixed by using backslashes
throughout every path segment. No data was lost; the affected step was
rerun cleanly with the fix.

Tracked evidence: `Include/MultiSpeedZigZag/Portfolio/BookExitManager.mqh`,
`Tests/MultiSpeedZigZag/Test_MSZZ_BookExitManager.mq5`. Raw reproduction
reports: `/Users/matt/MT5-MSZZ-TEST/D028_Stage5A_Checkpoint_Results`.

Stage 5A is accepted. Stage 5's actual SR0-SR5 comparison batch follows in
a separate commit.

### Stage 5 wiring bug found and fixed before any result was accepted

The first full SR0-SR5 batch (all six configs) produced `MSZZ_RunSummary.csv`
rows that were byte-identical across every variant — same 190 trades, same
`+0.1506R` expectancy, same `PF 1.2688`, same `18.2941R` max DD for SR1
through SR5 as for SR0 — and `MSZZ_SweepExitManagementJournal.csv` was never
created by any of the six runs (confirmed genuinely absent, not merely
uncollected, by checking all three Tester agents' `MQL5/Files/` directly).
Cross-checking `MSZZ_TradeAnalytics.csv` ruled out the innocent explanation
(SweepReclaim trades rarely reaching `+1.0R`) — 96 of 190 trades (50%) reach
`mfe_r>=1.0R`, more than enough for SR1/SR2/SR3/SR5 to have fired repeatedly
if the code path were actually running.

Root cause: `ProcessBookExitManagement()` gated only on
`g_portfolio_multi_book_active`. Every Stage 5 config enables SweepReclaim
alone (`ConfigurePortfolioArchitecture()`'s single-supported-strategy path),
which sets `g_portfolio_single_book_active=true` and
`g_portfolio_multi_book_active=false` — the exact opposite flag. The whole
exit-management call was therefore skipped every bar for all six runs,
regardless of `InpSweepExitPolicy`. SR0's numbers came out correct anyway
only because SR0's own dispatcher branch (`policy==SR0_FIXED2R`) is a
no-op by design, and because position-closure detection for single-book mode
runs through the pre-existing, separate `DetectClosedPositions()`/intent-store
path (D008/D009), not through the multi-book-only `DetectClosedPortfolioBooks()`
that `ProcessBookExitManagement()` sits next to — so SR0's fixed-2R baseline
looked identical to the certified numbers by coincidence of two independent
paths, not because exit management ran and did nothing.

Fix: widened the gate to `if(!g_portfolio_multi_book_active &&
!g_portfolio_single_book_active) return;`, matching the existing
`!single && !multi` convention already used by `PortfolioTargetR()`
elsewhere in the same file. `ProcessOneBookExit()`'s own per-book guards
(`book.valid`, `status==MSZZ_BOOK_OPEN`, `position_open`) make calling it for
an unconfigured book (e.g. `g_fastmed_book` in a SweepReclaim-only run) a
safe no-op, so no further branching was needed. The fix is provably a no-op
for every previously certified path in this branch: the FastMedConfluence
book's `trailing_policy_id` is never set to anything but `0` by any config
family (A/E/P1-P4), and every existing SweepReclaim config other than Stage
5's SR1-SR5 also defaults `InpSweepExitPolicy=0`, which short-circuits
`CMSZZBookExitManager::Evaluate()` before any of this matters. Only the six
Stage 5 SR1-SR5 configs are affected.

Verification after the fix: recompiled (`0 errors, 0 warnings`), hash-synced
to the isolated instance, and reran the full SR0-SR5 batch. See below for the
corrected results.

### Second bug found during the same verification pass: duplicate portfolio-journal rows

The corrected batch's `MSZZ_TradeAnalytics.csv` (190/194/195/194/182/190 rows
across SR0-SR5, matching each `MSZZ_RunSummary.csv` trade count exactly) was
clean, but `MSZZ_PortfolioTradeAnalytics.csv` was not: SR5 had 192 rows for
190 trades, with the two duplicated `logical_position_id`s matching its two
`TIME_STOP` force-closes exactly. Cause: `ProcessOneBookExit()`'s SR5
force-close branch calls `ExportClosedPortfolioBookFromTrade()`, which
journals and flattens the book immediately; `DetectClosedPositions()` then
independently re-detects the same now-closed ticket on a later bar and wrote
a second, unconditional row.

A first fix attempt gated the `DetectClosedPositions()` write on
`ActivePortfolioBookState()` still matching the closed ticket. This was
wrong and was caught before being accepted: it reduced every variant's
`MSZZ_PortfolioTradeAnalytics.csv` row count well below its trade count
(e.g. SR0 190->166, a 24-row deficit matching its 24 `OTHER`-exit-reason
trades exactly) — because the far more common own-family-opposite-close
path (`ApplyOwnershipPreflight` -> `PortfolioMarkFlat("own-book opposite
close")`) reassigns the book to a new position mid-bar, before
`DetectClosedPositions()` ever revisits the old intent, so the active-book
identity is *expected* to have moved on by then. Gating on it produced
silent data loss for the common case while fixing only the rare one.

Correct fix: an explicit `g_portfolio_journaled_tickets[]` set (mirroring
the existing `g_partial_closed_tickets[]` pattern already used for D025's
partial-close tracking). Both write sites — `ExportClosedPortfolioBookFromTrade()`
(SR5's immediate force-close journal) and `DetectClosedPositions()`'s
single-book block — mark/check the ticket instead of any book-state
snapshot. Reran the full SR0-SR5 batch a third time; `MSZZ_TradeAnalytics.csv`
and `MSZZ_PortfolioTradeAnalytics.csv` row counts now match exactly for
every variant (190/190, 194/194, 195/195, 194/194, 182/182, 190/190), zero
duplicate `logical_position_id`s anywhere, and every `MSZZ_RunSummary.csv`
number is byte-identical to the pre-this-fix batch (expected: this fix only
changes a secondary journal's write conditions, never a trading decision).

### Stage 5 results — SR0-SR5

SR0 reproduces the certified SweepReclaim-in-independent-book-path baseline
exactly: **190 trades, +28.6117R, expectancy +0.1506R, PF 1.2688, max DD
18.2941R** — matches the D028 handoff's ground truth and the Stage 5A
checkpoint's own reproduction to the fourth decimal. All analysis below is
computed from each variant's `MSZZ_TradeAnalytics.csv` via
`d028_stage5_analysis.py` (development `2025.03.01`-`2025.12.31`, validation
`2026.01.01`-`2026.04.30`, holdout `2026.05.01`-`2026.07.24`, per D027's
frozen window declaration). Full per-quarter tables and raw output are
preserved in `/Users/matt/MT5-MSZZ-TEST/D028_Stage5_Results/`.

| | SR0 (ctrl) | SR1 BE | SR2 trail | SR3 partial | SR4 runner | SR5 time-stop |
|---|---|---|---|---|---|---|
| trades | 190 | 194 | 195 | 194 | 182 | 190 |
| cum R | +28.6117 | +16.4340 | +18.4149 | +16.4340 | +3.4882 | +27.1420 |
| expectancy | 0.1506 | 0.0847 | 0.0944 | 0.0847 | 0.0192 | 0.1429 |
| PF | 1.2688 | 1.1854 | 1.1804 | 1.1854 | 1.0421 | 1.2562 |
| max DD | 18.2941 | 19.7531 | 22.9263 | 19.7531 | 40.8095 | 17.6732 |
| win rate | 0.3684 | 0.2835 | 0.3282 | 0.2835 | 0.1319 | 0.3632 |
| mean/median/p90 hold (bars) | 23.65/5/40 | 20.58/4/36 | 22.01/4/38 | 20.58/4/36 | 141.90/5/82 | 20.18/5/40 |
| Dev exp (n) | 0.1430 (123) | 0.1113 (126) | 0.1233 (127) | 0.1113 (126) | -0.0604 (116) | 0.1310 (123) |
| Val exp (n) | **0.1541** (29) | **-0.0384** (30) | **-0.0860** (30) | **-0.0384** (30) | 0.0973 (29) | **0.1541** (29) |
| Holdout exp (n) | 0.1726 (38) | 0.0937 (38) | 0.1404 (38) | 0.0937 (38) | 0.2075 (37) | 0.1726 (38) |
| top-3-removed exp | 0.1209 | 0.0546 | 0.0647 | 0.0546 | **-0.2651** | 0.1131 |
| best-quarter-removed exp | 0.0845 | 0.0073 | 0.0061 | 0.0073 | **-0.1612** | 0.0752 |
| avg MFE / avg giveback | 1.3003/1.1497 | 1.1772/1.0925 | 1.2339/1.1394 | 1.1772/1.0925 | 2.0176/1.9984 | 1.2909/1.1481 |
| exit SL/TP/OTHER | 100/66/24 | 83/51/60 | 87/58/50 | 83/51/60 | 78/8/96 | 99/65/26 |
| `MSZZ_TradeAnalytics.csv` SHA-256 | `2e57ec92...` | `48844336...` | `37b85f2c...` | `48844336...` | `ba0491a1...` | `df014636...` |

(Long/short and full quarterly breakdowns are in the raw analysis output,
not reproduced here; SR0's own pre-existing long/short asymmetry — long exp
0.0808 vs short exp 0.2219 — is a characteristic of the frozen SweepReclaim
entry logic itself, not something any SRx exit policy introduces or fixes,
and every SRx preserves the same direction of asymmetry.)

Exit reasons are the coarse `SL`/`TP`/`OTHER` buckets `MSZZ_TradeAnalytics.csv`
already records (`OTHER` covers own-family-opposite exits and, for SR5,
forced `TIME_STOP` closes — cross-checked exactly: SR5's `OTHER` count is
SR0's 24 plus its own 2 `TIME_STOP` journal entries). Reproducing the
handoff's full 11-category exit inventory (`BREAKEVEN_STOP`,
`STRUCTURAL_TRAIL`, `PARTIAL_AT_1R`, `RUNNER_TRAIL`, etc. as distinct from a
plain `SL`) is not possible from this field alone — the fine cause of an
`SL`-exit (original stop vs. a modified/trailed one) is only recoverable by
cross-referencing `MSZZ_SweepExitManagementJournal.csv`, which was done for
integrity checking below but not folded into a trade-by-trade reconciled
export. Recorded here as an honest limitation of the current instrumentation
rather than a fabricated fine-grained breakdown.

**Integrity audit** (all six variants): zero duplicate `logical_position_id`s
in `MSZZ_TradeAnalytics.csv` or `MSZZ_PortfolioTradeAnalytics.csv`;
`MSZZ_TradeAnalytics.csv` row count exactly equals each variant's
`MSZZ_RunSummary.csv` trade count; `MSZZ_PortfolioTradeAnalytics.csv` row
count now exactly matches `MSZZ_TradeAnalytics.csv` for every variant
(post the fix above); no `UNKNOWN` exit reason ever appears; no cross-family
exits are possible in this single-strategy configuration; SR0's numbers are
byte-identical to the certified baseline; deterministic output hashes
recorded above.

**SR1 (breakeven) — REJECTED.** Cumulative R, expectancy, and PF all worse
than SR0 on the identical entry stream, max DD worse (19.75R vs 18.29R), and
validation-window expectancy is **negative** (-0.0384R), which alone
disqualifies it under the Stage 5 decision rules ("positive validation and
holdout" is required). Moving the stop to breakeven at +1R converts a
meaningful fraction of trades that would have reached the fixed +2R target
into scratch trades once price pulls back through entry before continuing —
visible directly in the exit mix (`OTHER` count jumps from 24 to 60, `TP`
count drops from 66 to 51) and in the mean holding time actually
*shortening* (23.65 -> 20.58 bars) despite giving trades more room to
survive a pullback.

**SR2 (structural trail) — REJECTED.** Same failure mode as SR1 and for the
same underlying reason (this frozen SweepReclaim entry's edge depends more
on reaching its full +2R target than on protecting partial gains early):
worse cumulative R, worse expectancy, **worse max DD than the control**
(22.93R vs 18.29R — trailing behind confirmed swings gave back more room
than the fixed stop it replaced on this entry style), and negative
validation-window expectancy (-0.0860R).

**SR3 (partial 50% + breakeven remainder) — REDESIGN_REQUIRED, not a valid
test of the SR3 mechanism.** `MSZZ_SweepExitManagementJournal.csv` shows
every single partial-close attempt (194/194) logged
`PARTIAL_CLOSE_SKIPPED_VOLUME`, `modify_ok=false`, "requested partial volume
clamps to full position" — because every position here trades at
`InpFixedLots=0.01`, the account/symbol's minimum tradable size, and 50% of
the minimum lot cannot be represented at the broker's lot step. Every SR3
decision therefore degenerates to exactly its breakeven-modify half with no
volume ever actually banked — and SR3's results are not merely similar to
SR1's, they are **byte-identical**: same 194 trades, same every statistic to
four decimals, and an identical `MSZZ_TradeAnalytics.csv` SHA-256 hash
(`48844336...`) to SR1. SR3 as designed (a genuine partial-close-then-manage-
the-remainder policy) was never actually exercised by this backtest and
cannot be, until either the base position size is increased or the broker
supports finer-grained partial closes. Its numbers must not be read as "SR3
performs like SR1" in any causal sense — they are the same trades because
the mechanism collapsed to the same trades.

**SR4 (partial 50% + structural runner) — REDESIGN_REQUIRED, and actively
harmful under the current lot-size constraint; do not deploy or extend
without fixing the underlying issue first.** The same lot-size floor blocks
every partial close here too (15974/15974 `PARTIAL_CLOSE_SKIPPED_VOLUME`
entries), but SR4's dispatcher gates its structural-trail phase on
`partial_close_done`, which — because the partial can never actually
succeed — never becomes true. The position instead re-enters the "attempt
partial, move stop to breakeven, remove the fixed target" branch on every
single bar it remains favorable, forever: the target is discarded (`remove_
target=true` fires unconditionally) but no real trailing protection ever
engages, since the code never reaches the trail branch. The result is a
target-less position sitting behind a static breakeven stop with no active
management at all — visible directly in the numbers: mean holding time
balloons to **141.90 bars** (vs. 23.65 for the control), max DD nearly
triples to **40.81R**, and full-window results are dominated by a handful of
outliers to the point that **removing just the top 3 trades flips the whole
result from +3.49R to -47.45R** (expectancy -0.2651R) and removing the best
quarter flips it to -25.15R — the exact "dependence on a tiny runner
subgroup" pattern the Stage 5 decision rules explicitly disqualify, on top
of the mechanism never having been genuinely tested. The development window
alone is net negative (-7.01R). This is the clearest finding of the whole
study: SR4 as currently wired should not be considered even directionally
informative about a real partial+runner policy, and should not be rerun
until the partial-close volume floor is fixed at the architecture level.

**SR5 (time stop, N=48 bars / 4h, threshold +0.5R) — PORTFOLIO_TEST_ELIGIBLE.**
Only 2 of 190 trades were ever force-closed (`MSZZ_SweepExitManagementJournal.csv`:
exactly 2 `TIME_STOP` rows, both `modify_ok=true`), so SR5 is essentially SR0
with a narrow, low-frequency safety rule layered on top — every required
criterion is met: full-window expectancy positive (+0.1429R), validation
expectancy positive and **identical to the control** (+0.1541R, meaning
neither of the 2 affected trades falls in the validation window), holdout
expectancy positive and identical to the control (+0.1726R), remains
positive excluding the top 3 trades (+0.1131R) and excluding the best
quarter (+0.0752R), no unknown exits, exact accounting, max DD **improves**
on the control (17.6732R vs 18.2941R). The tradeoff is genuinely marginal
rather than a clear win — cumulative R is very slightly lower than SR0
(+27.14R vs +28.61R, a ~1.47R cost concentrated in exactly 2 trades that
would otherwise have run to a worse outcome) — so this should be reported to
Stage 6 as a modest, low-risk drawdown-shaving tweak, not as a materially
better SweepReclaim, and Stage 6 should judge it on whether that small DD
improvement matters at the portfolio level once combined with FastMedConfluence.

**Stage 5 summary decision:** only **SR5** advances to Stage 6, alongside
SR0 as the mandatory control. SR1 and SR2 are REJECTED on their own
evidence. SR3 and SR4 are REDESIGN_REQUIRED — neither's underlying mechanism
was actually exercised by this account's position sizing, and re-running
either without first fixing the partial-close volume floor (e.g. a larger
base lot size, or broker/account support for finer lot steps) would not
produce genuine evidence either way.

## Stage 6 — independent-book portfolio comparison

Only SR5 qualified as PORTFOLIO_TEST_ELIGIBLE from Stage 5, so Stage 6's
scope is two actual EA portfolio runs — **C-A-SR5** (FastMedConfluence A 2R +
SweepReclaim SR5, opposing enabled) and **C-E-SR5** (FastMedConfluence E 3R +
SweepReclaim SR5, opposing enabled) — built from the certified `Tools/D028/Stage4`
P3/P4 configs with only `InpSweepExitPolicy=5` added and a new magic/report
name (`Tools/D028/Stage6/d028_stage6_C_A_SR5.ini`,
`d028_stage6_C_E_SR5.ini`). Every other required control (C0=A alone, C1=E
alone, C2=SweepReclaim SR0 alone, C3=P3, C4=P4) is already certified —
respectively D026's baseline A/E, this document's own Stage 5 SR0 run, and
D028 Stage 4's P3/P4 — and is reused rather than rerun, per "do not rerun
certified work unnecessarily." No combined result below is constructed by
arithmetic addition; both C-A-SR5 and C-E-SR5 are actual executed EA runs.

| | C0 (A alone) | C3 (P3, ctrl) | **C-A-SR5** | C1 (E alone) | C4 (P4, ctrl) | **C-E-SR5** |
|---|---|---|---|---|---|---|
| trades | 224 | 343 | **344** | 213 | 331 | **332** |
| cum R | +28.2447 | +39.9275 | **+39.8369** | +31.2465 | +45.9294 | **+42.8388** |
| expectancy | 0.1261 | 0.1164 | **0.1158** | 0.1467 | 0.1388 | **0.1290** |
| PF | 1.2446 | 1.2132 | **1.2126** | 1.2532 | 1.2389 | **1.2216** |
| max DD | ~15.158 | 23.5883 | **23.5883** | ~16.920 | 24.2455 | **24.2455** |
| FastMedConfluence contribution | — | 209/+23.4386 | **210/+25.4386** | — | 199/+27.4405 | **200/+26.4405** |
| SweepReclaim contribution | — | 134/+16.4889 | **134/+14.3983** | — | 132/+18.4889 | **132/+16.3983** |
| Dev cum R | — | +20.5393 | **+20.4486** | — | +17.1392 | **+15.0485** |
| Val cum R | — | +5.8524 | **+6.8524** | — | +12.8524 | **+12.8524** |
| Holdout cum R | — | +13.5358 | **+12.5358** | — | +15.9378 | **+14.9378** |
| simultaneous-book episodes / hours | — | 69 / 57.30 | **70 / 57.71** | — | 74 / 60.79 | **75 / 61.21** |

(C2, SweepReclaim SR0 alone: 190 trades/+28.6117R/PF 1.2688/18.2941R DD — not
directly comparable to a matched-core row above since it has no
FastMedConfluence leg; included for completeness as the mandatory control.)

**The central finding: SR5's standalone drawdown improvement does not carry
through to the executed portfolio.** In both matched comparisons, max DD in
the actual portfolio run is **exactly identical, to four decimal places**,
to the P3/P4 control (23.5883R and 24.2455R respectively) — not merely
similar, identical — while cumulative R is **lower** than the control in
both cases (-0.0906R for C-A-SR5, a materially larger **-3.0906R** for
C-E-SR5). SweepReclaim's own contribution is lower in both portfolios
despite an equal or matching trade count (134/+14.3983R vs P3's
134/+16.4889R; 132/+16.3983R vs P4's 132/+18.4889R) — consistent with SR5's
standalone finding that it trades roughly -1.5R of edge for a DD
improvement, except here the DD improvement never materializes at the
portfolio level, so the trade only shows its cost. FastMedConfluence's own
contribution also shifts (+1 trade, +2.0000R in C-A-SR5; +1 trade, -1.0000R
in C-E-SR5) purely from occupancy path-dependence — SweepReclaim's book
closing at a different time than it would under SR0 changes which signals
are available when a portfolio slot frees up, even though FastMedConfluence's
own exit policy never changed. This is exactly the kind of interaction
effect the handoff's "do not construct combined results by arithmetic
addition" requirement exists to catch: a policy can look strictly better in
isolation and still fail to help, or even mildly hurt, once it is actually
executed inside the real two-book system.

**Integrity audit:** zero duplicate `logical_position_id`s in either run's
`MSZZ_PortfolioTradeAnalytics.csv`; max recorded portfolio open risk
`0.5%` in both runs, never exceeding the `InpPortfolioMaxTotalRiskPct=0.50`
cap; every `MSZZ_PortfolioRiskJournal.csv` action is `OPEN` (108/114
correctly rejected in C-A-SR5/C-E-SR5 respectively, all against the
one-book-per-strategy/two-book-max/risk-cap rules, none against a
cross-family rule since none applies here); `MSZZ_SweepExitManagementJournal.csv`
shows exactly **one** `TIME_STOP` firing in each portfolio run (vs. two in
SR5's standalone run) — a legitimate, honestly-reported occupancy
difference: the second standalone time-stop candidate's signal did not
result in the same trade inside the portfolio's shared-risk/occupancy
dynamics, not a bug. Account mode remains `HEDGING` throughout (unchanged
from Stage 4).

**Stage 6 classification: C-A-SR5 and C-E-SR5 are both REJECTED** against
the Stage 6 success criteria — the first and most basic requirement,
"exceeds matched core on cumulative R," fails for both, and the DD
improvement that motivated advancing SR5 out of Stage 5 does not appear in
either actual portfolio. Neither is being recommended for further use.
**P3 and P4 (SR0-based, unmodified SweepReclaim exit management) remain the
best independently-executed portfolios found in D028.**
