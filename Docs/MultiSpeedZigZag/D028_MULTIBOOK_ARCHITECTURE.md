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
