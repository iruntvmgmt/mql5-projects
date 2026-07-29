# D029 — Percentage-Risk Sizing, Executable Partial-Leg Validation, and Portfolio Reconciliation

Branch `feature/d029-percent-risk-partials`, forked from D028's final SHA
`1ff69f918aefe43ce7c213992805be33a9c3be6a` on `feature/d028-multibook-portfolio`.
No merge to `main`. No live deployment. This is a new, bounded study — it
does not rewrite, reinterpret, or rerun D028's certified results.

## Why this study exists

D028 found no SweepReclaim exit-management variant that improved on the
original fixed-2R exit, including the two partial-close designs SR3 and
SR4. But SR3/SR4 were never actually tested as designed: the account's
fixed `0.01`-lot position size equals the broker's minimum tradable size
and volume step, so every attempted 50% partial close clamped back to the
full position and was skipped. SR3 silently collapsed into SR1's exact
trade sequence (byte-identical output hash); SR4 collapsed into a broken,
repeated no-op loop. **D028's SR3/SR4 status remains `REDESIGN_REQUIRED` —
not disproven, not validly tested.** D029 exists to resolve that gap
correctly, by sizing positions as a percentage of equity (rather than a
fixed lot) so partial closes become numerically possible, then testing
whether a genuinely executable partial or runner design improves
SweepReclaim standalone and the actual independent-book portfolio.

## Research questions

**Primary**: can a percentage-of-equity position-sizing engine produce
executable, risk-normalized partial exits for SweepReclaim without changing
its entries, structural stop, signal logic, portfolio architecture, or
causal assumptions?

**Secondary**: once partials execute correctly, do any partial or runner
designs improve standalone SweepReclaim and the actual independent-book
P3/P4 portfolios relative to percentage-sized fixed-exit controls?

The goal is a valid, causal, auditable answer — not a result above `50R`.

## Non-negotiable constraints (unchanged from the handoff, restated for the record)

No changes to: FastMedConfluence A or E entry logic, SweepReclaim entry
logic, candidate generation, clustering, event identity, signal timing,
structural initial stops. No optimization of risk percentage, portfolio-risk
caps, partial fractions, or runner thresholds after results are seen. No
merge to `main`, no live deployment, no changes to Quant Beast, no rewriting
of D027 or D028 evidence.

D028's independent-book architecture is preserved unchanged: HEDGING
account, separate physical tickets, separate magics, own-book-only closing,
cross-family close/reverse disabled, opposing books allowed, one book per
strategy, total portfolio risk enforced.

## Phase 0 — frozen rules

All values below are frozen **before** any D029 backtest is run or any
result is inspected. Full machine-readable copy: `Tools/D029/Phase0/frozen_design.md`.

```text
Sizing mode:                          PERCENT_EQUITY
Risk per FastMed book:                0.25%
Risk per SweepReclaim book:           0.25%
Maximum total portfolio initial risk: 0.50%
Maximum active books:                 2
Maximum books per strategy:           1

Partial fraction:                     50%
SR3 first partial trigger:            +1R
SR3 remaining target:                 +2R
SR3 remaining stop after partial:     entry price
SR4 first partial trigger:            +1R
SR4 runner stop after partial:        entry price
SR4 fixed target after partial:       none
SR4 trailing source:                  confirmed causal structural pivots only

Opposing books:                       allowed
Cross-family close/reversal:          disabled
```

### Symbol metadata (XAUUSD, Coinexx-Demo)

Captured read-only via `Scripts/MultiSpeedZigZagTools/SymbolMetadataProbe.mq5`
(no trading action; `SymbolInfo*`/`AccountInfo*` calls only), run once on
the isolated instance:

```text
volume_min:     0.01
volume_max:     100.00
volume_step:    0.01
tick_size:      0.01
tick_value:     1.00
contract_size:  100
point:          0.01
digits:         2
account_currency: USD
```

### Tester balance selection

Sizing formula (see Phase 1 below for the exact frozen calculation):
`raw_volume = (equity * risk_pct/100) / (stop_distance_price * (tick_value/tick_size))`.
For a 0.02-lot minimum partial-capable position at 0.25% risk, this reduces
to `balance >= 800 * stop_distance_price`.

D028's certified SweepReclaim SR0 run (`MSZZ_TradeAnalytics.csv`, 190
trades, no new backtest needed) gives the canonical stop-distance
distribution: min 0.54, median 5.44, mean 8.25, p95 25.78, max 112.59
(XAUUSD price units). Projecting six candidate balances against this
distribution (`Tools/D029/Phase0/volume_resolution_analysis.py`,
`volume_resolution_summary.csv`):

| candidate | % trades >=0.02 lots | % exact 50/50 | % non-exact split | % below minimum |
|---|---|---|---|---|
| $10,000 | 82.63% | 43.68% | 38.95% | 5.26% |
| $25,000 | 98.42% | 57.37% | 41.05% | 0.53% |
| $50,000 | 99.47% | 53.68% | 45.79% | 0.00% |
| $75,000 | 99.47% | 54.74% | 44.74% | 0.00% |
| **$100,000** | **100.00%** | 45.79% | 54.21% | 0.00% |
| $150,000 | 100.00% | 51.05% | 48.95% | 0.00% |

**Frozen tester balance: $100,000** — the handoff's own suggested starting
candidate, verified rather than assumed to clear the required 95% threshold
(it clears at 100%, the maximum possible margin). This choice was made
purely from stop-distance/volume-resolution projection, never from any
profitability figure. Honest disclosure made here, before any D029 result
exists: at $100,000, the majority of trades (54.21%) will split into a
non-exact 50/50 partial (e.g. a 0.07-lot position splits 0.03/0.04, not
0.035/0.035) rather than a clean even halves — every such case will be
separately categorized in Phase 3's accounting, per the handoff's own
tolerance rule, not silently treated as a clean split. This is a real
property of percentage sizing at this account's volume step and is
disclosed rather than hidden.

Same $100,000 balance is used for every D029 control and portfolio run.

## Phase 0 verification

`Scripts/MultiSpeedZigZagTools/SymbolMetadataProbe.mq5` compiled (`0
errors, 0 warnings`), synced to the isolated instance (hash-verified), and
run once via `[Common] Login=870012` / `[StartUp] Script=...` — confirmed
in the terminal journal (`script SymbolMetadataProbe (XAUUSD,M5) loaded
successfully` / `removed` / `closes terminal with code 0`). Output written
to Wine's shared `Common/Files` folder (a `FILE_COMMON` fallback path in
the probe script, not the portable instance's own `MQL5/Files`) —
documented here since it took two failed attempts to locate: the first two
launches hung because the config lacked the `[Common] Login=870012` section
required for a live-attached (non-Tester) script run, distinct from every
other config used across D026–D028 which all used `[Tester]`-based
backtest launches instead. No trading account state was affected by any of
these attempts (read-only script, `InpAllowLiveExecution`/`InpAcknowledgeRisk`
not applicable to a plain script).

This document, `Tools/D029/Phase0/README.md`, `frozen_design.md`, and
`volume_resolution_summary.csv` are committed as `D029 Phase 0: freeze
percentage-risk and partial-leg study` before any Phase 1 implementation
begins.

## Phase 1 — percentage-equity sizing engine

### Design

New pure module `Include/MultiSpeedZigZag/Portfolio/PositionSizing.mqh`
(`CMSZZPositionSizing::Calculate()`), no MT5 API calls, following the same
discipline as every other pure-calculation module in this project (e.g.
D026's `CMSZZResearchTrailPolicy`). Computes and returns the full
`MSZZSizingResult` struct (equity snapshot, requested/actual risk money and
percent, stop distance, loss per lot, raw and normalized volume,
normalization error, minimum-volume and partial-capable flags, sizing
result, reject reason) exactly per the frozen Phase 0 formula: `raw_volume =
(equity * risk_pct/100) / ((stop_distance/tick_size)*tick_value)`, normalized
DOWN only to the nearest broker volume step, never up, never silently
substituting the minimum lot if that would exceed requested risk. Fails
closed on: invalid equity/risk percent, invalid tick or volume metadata,
zero/negative stop distance, nonpositive loss-per-lot, normalized volume
below the broker minimum, and (defense-in-depth, unreachable by
construction given the normalize-down rule) normalized risk exceeding
requested risk.

New EA input `InpSizingMode` (`ENUM_MSZZ_POSITION_SIZING_MODE`, default
`MSZZ_SIZE_FIXED_LOT=0`). **Design decision, disclosed rather than silently
deviating from the handoff's suggested input list**: the handoff suggested
two additional new inputs, `InpRiskPercentPerBook` and
`InpMaxPortfolioRiskPercent`. These were not added — D028 already has
`InpPortfolioRiskPerBookPct` (0.25%, already frozen in Phase 0) and
`InpPortfolioMaxTotalRiskPct` (0.50%, already frozen in Phase 0) serving
exactly these roles (the "requested per-book risk percent" used for
risk-cap bookkeeping, and the portfolio-wide cap), already wired into
`CMSZZPortfolioRiskManager`'s config. Adding parallel inputs with the same
meaning would create two knobs that must always agree rather than one
source of truth. `InpSizingMode` is the only new input.

A single shared helper, `ComputeSizedVolume()` in the EA, is called from
both execution paths (`ExecuteCluster()` for single-book mode,
`ExecutePortfolioBookCandidate()` for multi-book mode) — the two call sites
that previously each called `g_execution_guard.NormalizeVolume(InpFixedLots)`
directly. In `MSZZ_SIZE_FIXED_LOT` mode this is exactly that same call,
byte-identical; `risk_pct_for_book` returns `InpPortfolioRiskPerBookPct`
unchanged, matching every certified run's existing (assumed, not computed)
bookkeeping value. In `MSZZ_SIZE_PERCENT_EQUITY` mode, it calls
`CMSZZPositionSizing::Calculate()` with live `SymbolInfoDouble`/
`AccountInfoDouble` metadata, journals the decision (accepted or rejected)
via a new `MSZZ_SizingJournal.csv` (`CMSZZPortfolioJournals::JournalSizing()`),
and returns the **actual** normalized risk percent — never the flat
requested percent — for downstream risk-cap approval
(`CMSZZPortfolioRiskManager::ApproveOpen()`, unmodified) and book
bookkeeping (`allocated_risk_pct`), per the handoff's explicit "portfolio
approval must use actual normalized initial risk" requirement. Rejected
sizing decisions surface as `JournalCandidate(...,"REJECT_SIZING",...)`,
parallel to the existing `REJECT_VOLUME` used in fixed-lot mode.

`CMSZZPortfolioRiskManager` itself is unmodified — it was already
generic (accepts any `risk_pct` number, has no fixed-lot-specific
assumption), so no changes were needed there; only the caller-supplied
value changes between sizing modes.

### Tests

`Tests/MultiSpeedZigZag/Test_MSZZ_PositionSizing.mq5`, 41 assertions:
long/short symmetry, exact stop-distance calculation, correct tick-value
use, correct percent-to-money conversion, normalize-down (never up),
minimum-volume rejection (never silently forced up), invalid
tick/volume/equity/risk-percent metadata rejection, zero-stop-distance
rejection, actual risk never exceeds requested across 6 stop-distance
cases, volume_max clamping, the partial-capable flag boundary at 0.02 lots
— plus 7 integration cases proving the sizing engine's output composes
correctly with the existing, unmodified `CMSZZPortfolioRiskManager`: one
book at actual risk approved, a second 0.25% book approved up to the exact
0.50% cap, anything above the cap rejected, actual (under-allocated, not
flat-requested) risk is what gets summed into the portfolio snapshot, a
closed book contributes zero risk, opposing-direction books allowed,
same-strategy second book rejected. All 41 pass (`failures=0`).

### Backward-compatibility verification

Per the handoff's explicit gate ("stop if any fixed-lot certified result
changes"):
- All 31 pre-existing deterministic `Test_MSZZ_*`/`Export_MSZZ_Parity`
  suites recompiled and rerun on the new binary: **0 failures across every
  suite**.
- Shadow regression, both windows, reproduced exactly: short **113
  candidates / 46 clusters / 0 executed**; long **431 candidates / 178
  clusters / 0 executed** — `InpSizingMode` defaulting to `MSZZ_SIZE_FIXED_LOT`
  is confirmed a true no-op for candidate generation and clustering.
- SweepReclaim SR0 (D028's certified fixed-lot standalone baseline)
  reproduced fresh on the new binary, config unchanged, `InpSizingMode` not
  set (defaults to fixed-lot): **190 trades, +0.1506R expectancy, PF
  1.2688, 18.2941R max DD** — exact match to the certified number to every
  decimal place.

No certified pre-D029 result changed. Committed as `D029 Phase 1:
percentage-equity sizing engine`.

## Phase 2 — percentage-sized controls

Five new apples-to-apples controls at the frozen $100,000 balance, all
entries/stops/costs/architecture unchanged from D028: `D29-A` (A alone,
fixed 2R), `D29-E` (E alone, fixed 3R), `D29-SR0` (SweepReclaim alone,
fixed 2R), `D29-P3` (A 2R + SweepReclaim 2R, independent books), `D29-P4`
(E 3R + SweepReclaim 2R, independent books). Configs derived from D028's
own certified Stage 3/Stage 4 single-book and multi-book templates with
only `Deposit=100000` and `InpSizingMode=1` changed. Full detail:
`Tools/D029/Phase2/README.md`, results CSVs in the same directory, raw
evidence in `/Users/matt/MT5-MSZZ-TEST/D029_Phase2_Results/`.

### Bug found and fixed before accepting any Phase 2 result

The first Phase 2 batch produced only 15 trades for D29-A (vs. D028's
certified 224) and 1 trade for D29-SR0 (vs. 190) — most sizing decisions
were themselves correct (524/531 `OK` for D29-A), but 432 of 717 raw
candidates were rejected downstream with `"symbol exposure cap exceeded"`.
Root cause: `ConfigurePortfolioArchitecture()` set
`risk.symbol_exposure_cap_lots=InpFixedLots*InpPortfolioMaxBooks`
unconditionally — a leftover fixed-lot-mode assumption (0.01 lots x 2
books = 0.02 lots max exposure) that was never updated for percent-equity
mode, where normalized volumes routinely reach 0.1-15+ lots. This gap
existed through all of Phase 1's backward-compatibility testing because
that testing exercised only fixed-lot mode (by design, to prove the
default path was unchanged) — exactly why Phase 2's real backtests exist:
to exercise percent-equity mode against real data for the first time.

Fix: `risk.symbol_exposure_cap_lots` is now `0.0` (disabled) when
`InpSizingMode==MSZZ_SIZE_PERCENT_EQUITY`, `InpFixedLots*InpPortfolioMaxBooks`
unchanged otherwise. This is not a safety regression — portfolio risk is
already fully bounded by the mode-aware `max_total_initial_risk_pct`
(0.50%) and `max_risk_per_book_pct` (0.25%) checks in the same function,
which use ACTUAL computed risk regardless of position size; the lot-count
cap was redundant with (and, in percent-equity mode, far stricter than
intended by) those percent-based caps. Recompiled (`0 errors, 0 warnings`),
reconfirmed shadow-short still reproduces exactly (113/46/0), then reran
the full Phase 2 batch.

### Results

| control | trades | cum R | expectancy | PF | max DD | Dev cum R | Val cum R | Holdout cum R |
|---|---|---|---|---|---|---|---|---|
| D29-A | 221 | +28.9237 | 0.1309 | 1.2520 | 14.9204 | +14.5886 | +7.9115 | +6.4236 |
| D29-E | 210 | +31.9255 | 0.1520 | 1.2601 | 16.9204 | +9.1884 | +14.9115 | +7.8256 |
| D29-SR0 | 190 | +28.6117 | 0.1506 | 1.2688 | 18.2941 | +17.5830 | +4.4695 | +6.5592 |
| D29-P3 | 342 | +41.6064 | 0.1217 | 1.2218 | 23.9365 | +22.1910 | +6.8796 | +12.5358 |
| D29-P4 | 330 | +47.6083 | 0.1443 | 1.2472 | 24.2455 | +19.7909 | +12.8796 | +14.9378 |

**D29-SR0 reconciles exactly** to D028's certified fixed-lot SweepReclaim
baseline: 190/190 trades, identical R statistics to four decimal places.
`MSZZ_SizingJournal.csv` shows zero `MIN_VOLUME_REJECT` events and 100% of
positions partial-capable (>=0.02 lots) — exactly matching Phase 0's
pre-result projection that $100,000 clears SweepReclaim's stop-distance
distribution with full margin. Because R-multiples are computed from
entry/stop/exit prices only, never from position size, this is expected
once volume resolution is sufficient — not a coincidence, a structural
proof that percent-equity sizing is R-neutral when it works.

D29-A, D29-E, D29-P3, and D29-P4 each show a small trade-count deficit
versus their D028 fixed-lot counterparts (-3, -3, -1, -1 respectively — a
maximum 1.4% delta). Every difference reconciles to the handoff's own
allowed categories: **7 genuine `MIN_VOLUME_REJECT` events** in every A/E-
touching run (`MSZZ_SizingJournal.csv`: `"normalized volume below broker
minimum -- not silently forced up"` — a handful of FastMedConfluence
signals have stop distances tight enough that even $100,000 at 0.25% risk
floors to below 0.01 lots) plus **`BOOK_ALREADY_OPEN` cascading occupancy
shifts** (a few percent-equity trades close at slightly different times
than their fixed-lot counterparts purely from the different R-realized
path of trades that were sized differently, which shifts which signal
"wins" a later occupancy race — the same class of effect D028 Stage 6
already documented for exit-policy changes). One `ORDER_FAILED`
(`retcode=10016 invalid stops`) appears in both A and E, matching the
exact benign category D028's own Stage 4 checkpoint already documented.
A's and E's `RAW_CANDIDATE`/`REJECT_STOPS` counts are identical between
the two runs (717/180 each) — since A and E share identical entries and
differ only in target R, this is a strong internal proof that sizing mode
has zero effect on upstream candidate generation, consistent with the
shadow-regression proof from Phase 1.

**Volume distribution** (`volume_distribution.csv`): median position size
ranges 0.10-0.49 lots depending on the strategy's typical stop width;
maximum observed volume reaches **15.04-15.56 lots** for A/E/P3/P4 (their
tightest-stop trades) and 4.90 lots for SR0. This is mathematically correct
given the frozen 0.25%-risk/$100,000-balance formula, but is disclosed
honestly as a real-world consideration this backtest does not model:
canonical costs/execution are held constant regardless of position size,
while a genuine 15-lot XAUUSD order would carry materially different
slippage and liquidity characteristics than a 0.01-lot order. This does
not invalidate the R-multiple comparisons (which are the basis for every
D029 decision), but it means the *absolute* dollar/percentage figures in
this report should not be read as a literal live-execution forecast at
this exact balance without further liquidity-stress analysis — a gap
explicitly out of scope for this bounded study, consistent with D029's own
anti-overfitting disclosure requirements.

**Integrity audit** (`integrity_audit.csv`): actual risk percent never
exceeded the 0.25% requested cap in any of the 2,802 sizing decisions
across all five controls; zero unknown exits; zero cross-run candidate
divergence for the A/E pair.

Committed as `D029 Phase 2: risk-normalized control equivalence`.

## Phase 3A — executable partial-leg architecture

### Physical implementation decision: broker `PositionClosePartial()`, not child tickets

The handoff asks whether two physical child tickets (a "realization leg" and
a "remainder/runner leg") would be more reliable than a single ticket with
a native partial close, framed as an evaluation ("evaluate whether... if
implemented"), not a requirement. Decision:
**`BROKER_PARTIAL_CLOSE_RECOMMENDED`** — the existing single-ticket
`PositionClosePartial()` approach, unchanged from D028 Stage 5A's
architecture. Reasoning:

- `PositionClosePartial()` is a standard, universally-supported MT5
  operation on HEDGING accounts — nothing about hedging mode makes it less
  reliable than on netting accounts; the handoff's own phrasing ("because
  the account is HEDGING, evaluate...") reads as "this is now *possible*,"
  not "this is now *necessary*."
- D028 Stage 5A already built and tested this exact mechanism
  (`CMSZZBookExitManager`'s SR3/SR4 dispatch, `Test_MSZZ_BookExitManager.mq5`'s
  16 passing cases including one-shot partial firing, no re-fire, and
  partial+breakeven-remainder combined decisions) — zero partial-close
  *reliability* defects were ever found in that testing. The only D028
  defect was a *volume* problem (0.01 lots can't split), which percent-equity
  sizing (Phase 1) already solves without touching the close mechanism at
  all.
- A child-ticket architecture would duplicate substantial existing
  infrastructure (per-leg ownership, journaling, reconciliation, portfolio-
  book-count accounting) to solve a reliability problem that testing shows
  does not exist, for a "preferred if implemented" option the handoff itself
  does not mandate. Building it would be new, uncontained risk for no
  demonstrated benefit.

Consequently, the Phase 3 required test cases specific to a child-ticket
design (child-ticket mode preserves parent risk; partial children do not
consume two portfolio books) do not apply and are not written — there are
no children. Every other Phase 3 required case is covered below or was
already covered by D028's existing, unmodified `CMSZZBookExitManager` tests.

### What changed

The core partial-close decision logic (`CMSZZBookExitManager::Evaluate()`,
the SR3/SR4 activation/target/breakeven rules) is **completely unchanged**
from D028. What Phase 3A adds:

1. **`CMSZZPositionSizing::ComputePartialSplit()`** (new, pure,
   `PositionSizing.mqh`): the single place the 50%-split arithmetic is
   defined, reused by both the new pre-entry eligibility check and the
   EA's existing `ProcessOneBookExit()` partial-close handling (which
   previously computed the split ad hoc via
   `NormalizeVolume(volume*fraction)` — now delegates here). Rejects
   (returns `false`, both outputs zero) rather than clamping whenever the
   split would produce a zero-size leg or consume the entire position —
   "no full-close masquerading as partial" is enforced by construction.
2. **Pre-entry `PARTIAL_VOLUME_INELIGIBLE` rejection** (new,
   `RequiresPartialEligibility()` + a check at both `ExecuteCluster()` and
   `ExecutePortfolioBookCandidate()`'s sizing call sites): if
   SweepReclaim's active exit policy is SR3-PCT or SR4-PCT and the sized
   entry volume cannot support a valid 50% split
   (`sizing.partial_capable==false`), the **entry itself is rejected** --
   `JournalCandidate(...,"REJECT_PARTIAL_VOLUME_INELIGIBLE",...)`, no
   trade opens at all. This is the literal fix for D028's original defect:
   instead of silently opening the trade and then discovering the partial
   can't fire (which is exactly how SR3/SR4 were invalidly tested at fixed
   0.01 lots), an ineligible signal is now excluded from the sample
   entirely, honestly, before any position exists. Every other
   strategy/policy combination is completely unaffected by this check.
3. **`MSZZ_PartialCloseJournal.csv`** (new, `CMSZZPortfolioJournals::JournalPartialClose()`):
   one row per executed partial close with original volume, requested
   fraction, requested/normalized/executed partial volume, remaining
   volume, the actual broker partial-close deal ticket, and fill price.
   Partial/remainder realized-R and weighted-total-R are deliberately
   computed downstream in the Phase 3 analysis script from this
   price/volume data plus the already-proven D025 volume-weighted blended
   close price already present in `MSZZ_TradeAnalytics.csv`/
   `MSZZ_PortfolioTradeAnalytics.csv`, rather than duplicating R-calculation
   logic inside the EA.

### Tests

`Test_MSZZ_PositionSizing.mq5` extended with 6 new test functions (25 new
assertions) for `ComputePartialSplit()`: the handoff's own named examples
(0.02→0.01/0.01, 0.04→0.02/0.02), odd-step determinism (0.03→0.01/0.02,
0.05→0.02/0.03, repeated-call stability), no-full-close-masquerading (a
single-step 0.01 volume is rejected, not clamped), invalid-input rejection
(zero volume/step/fraction, fraction>=1.0), and a large-volume sanity check
at realistic percent-equity position sizes (15.04 lots, matching Phase 2's
observed maximum) confirming `partial+remaining` reconciles exactly to the
original volume. All pass (`failures=0`).

Per-trade partial-execution-once/never-refire, restart-safety, remaining-
stop-moves-only-after-successful-partial, and cross-family-zero guarantees
are D028 Stage 5A properties this pass does not touch, already proven by
`Test_MSZZ_BookExitManager.mq5`'s existing 16 cases (unchanged).

### Backward-compatibility verification

All 31 pre-existing deterministic suites recompiled and rerun: **0
failures across every suite**, including the freshly extended
`Test_MSZZ_PositionSizing.mq5` (41 Phase 1 assertions + 25 new Phase 3
assertions, all pass). Shadow-short reproduced exactly (113/46/0). D29-SR0
(percent-equity, Phase 2's own control) reproduced fresh on the new binary:
**190 trades, +0.1506R, PF 1.2688, 18.2941R max DD** — exact match, proving
Phase 3A's changes (which only activate for SweepReclaim under an SR3-PCT/
SR4-PCT policy) have zero effect on SR0 or any other previously certified
path.

Committed as `D029 Phase 3A: executable partial-leg architecture`.

## Phase 3 — executable partial and runner study

SR0, SR3-PCT, SR4-PCT each run exactly once at the frozen $100,000
balance, SweepReclaim only, canonical entries/stop unchanged. Full detail:
`Tools/D029/Phase3/README.md`, results CSVs in the same directory, raw
evidence in `/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/`.

### Volume resolution and same-signal proof

Zero `REJECT_PARTIAL_VOLUME_INELIGIBLE` events across 203 (SR3-PCT) and 207
(SR4-PCT) sizing decisions — SweepReclaim's volume resolution at $100,000
remains perfect, exactly matching Phase 0's projection and Phase 2's
empirical confirmation. `RAW_CANDIDATE` count is **identical (376)** across
all three variants — proof, not assumption, that neither partial policy
alters signal generation in any way.

### Partial accounting

Both variants produced genuine, mechanically real partial closes this
time: **86 for SR3-PCT, 82 for SR4-PCT**, with **100% exact volume
reconciliation** (`executed_partial_volume + remaining_volume ==
original_volume` in every single case, verified via the new
`MSZZ_PartialCloseJournal.csv`). Executed partial fraction averages
49.3%/49.2% (range 44.4%-50.0%) — never exactly 50.0% in every case because
of volume-step rounding on odd-step original volumes, exactly the
"non-exact split" behavior Phase 0 disclosed in advance; every such case is
captured in the journal's `executed_partial_volume` field, not silently
assumed to be a clean half.

### Results

| | SR0 (ctrl) | SR3-PCT | SR4-PCT |
|---|---|---|---|
| trades | 190 | 194 | 186 |
| cum R | +28.6117 | +15.6561 | +14.7800 |
| expectancy | 0.1506 | 0.0807 | 0.0795 |
| PF | 1.2688 | 1.1776 | 1.1752 |
| max DD | 18.2941 | **14.9477** | 19.5860 |
| win rate | 0.3684 | 0.4897 | 0.4892 |
| mean hold (bars) | 23.65 | 20.58 | **131.38** |
| Val expectancy | 0.1541 | 0.0207 | 0.1208 |
| Holdout expectancy | 0.1726 | 0.0943 | 0.1616 |
| top-3-removed exp | 0.1209 | 0.0506 | **-0.0721** |
| top-5-removed exp | 0.1006 | 0.0299 | **-0.1155** |
| best-quarter-removed exp | 0.0845 | 0.0263 | **-0.0333** |
| long / short expectancy | 0.0808 / 0.2219 | -0.0035 / 0.1684 | 0.0704 / 0.0883 |

**SR3-PCT — `PORTFOLIO_TEST_ELIGIBLE`.** Every explicit decision-rule gate
passes: positive full-window, validation, and holdout expectancy; remains
positive excluding the top 3 trades (0.0506) and excluding the best
quarter (0.0263); no extreme runner dependence (top-5-removed still
positive at 0.0299); zero unknown exits; exact accounting; zero signal
mismatch. Max drawdown improves a genuine **18.3%** versus SR0 (14.95R vs
18.29R) — this is not an artifact of a handful of trades, since the result
survives top-3/top-5/best-quarter exclusion throughout. The honest
tradeoff: cumulative R, expectancy, and PF are all lower than SR0, and
long-direction expectancy turns slightly negative (-0.0035, essentially
breakeven). This is a real DD-for-edge tradeoff, not a free improvement —
reported as such, not oversold.

**SR4-PCT — `REJECTED`.** Fails three explicit gates simultaneously:
removing the top 3 trades flips the entire result from **+14.78R to
-13.20R**; removing the top 5 goes further to -20.90R; removing the best
quarter also goes negative (-5.23R). `avg_mfe_r` (1.9826) and mean holding
time (131.38 bars, 5.7x SR0's) both point to the same cause — a small
number of very large structural-trail runners are propping up an otherwise
losing result. This is precisely the "extreme runner subgroup dependence"
pattern the decision rules are designed to catch, and unlike D028's SR4
(where the mechanism never genuinely fired), this is a real finding about
a genuinely-executing runner design: on SweepReclaim's entries, letting the
remainder ride behind confirmed structural pivots with no fixed target
does not produce a robust edge. Also notable: max DD does not even improve
over SR0 here (19.586R vs 18.294R, slightly worse) — SR4-PCT offers neither
the return of SR0 nor the drawdown benefit of SR3-PCT.

Both `MSZZ_TradeAnalytics.csv` outputs are hashed (`output_hashes.csv`) for
deterministic reproducibility.

**Only SR3-PCT advances to Phase 4**, alongside SR0 as the mandatory
control. Committed as `D029 Phase 3: executable partial and runner study`.

## Phase 4 — percentage-sized portfolio comparison

Only SR3-PCT qualified from Phase 3, so Phase 4 required exactly two new
actual EA portfolio runs: `P3-SR3` (A 2R + SweepReclaim SR3-PCT) and
`P4-SR3` (E 3R + SweepReclaim SR3-PCT), both at $100,000. The controls
(`D29-P3`, `D29-P4`, both SweepReclaim SR0) were already certified in
Phase 2 and reused, not rerun — consistent with "do not rerun certified
work unnecessarily." Full detail: `Tools/D029/Phase4/README.md`, results
CSVs in the same directory, raw evidence in
`/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/`.

### Results

| | D29-P3 (ctrl) | P3-SR3 | D29-P4 (ctrl) | P4-SR3 |
|---|---|---|---|---|
| trades | 342 | 347 | 330 | 335 |
| cum R | +41.6064 | +29.8514 | +47.6083 | +35.6172 |
| expectancy | 0.1217 | 0.0860 | 0.1443 | 0.1063 |
| PF | 1.2218 | 1.1709 | 1.2472 | 1.1972 |
| max DD | 23.9365 | **20.8497** | 24.2455 | **22.6597** |
| Sweep trades / cum R | 136 / +17.4889 | 139 / **+4.7340** | 134 / +19.4889 | 137 / **+5.4978** |
| simultaneous episodes / hours | 69 / 57.05 | 67 / 49.63 | 74 / 60.54 | 72 / 53.04 |

### The central finding: SR3-PCT's drawdown improvement partially survives the portfolio, but SweepReclaim's own edge collapses far more than the standalone test predicts

This is a materially different result than D028's SR5, where the
standalone DD improvement was exactly canceled at the portfolio level (max
DD came out byte-identical to control). Here, DD genuinely improves in
both portfolios — **-12.9% for P3** (23.94R -> 20.85R) and **-6.5% for
P4** (24.25R -> 22.66R), a real, non-trivial reduction, not an artifact.
But the cost is much larger than Phase 3's standalone SR3-PCT result would
suggest: SweepReclaim's own portfolio contribution collapses from
**+17.49R to +4.73R** in P3 (almost the same trade count, 136 vs 139 —
this is not fewer trades, it's the *same trades resolving far worse*), and
from **+19.49R to +5.50R** in P4. This is a genuine, portfolio-specific
interaction effect that only appears once a real opposing FastMedConfluence
book is competing for the same account's risk budget and occupancy — it is
invisible from Phase 3's standalone-only test, and is exactly the class of
effect the handoff's "do not construct combined results by arithmetic
addition" requirement exists to catch. (Investigating the precise
mechanism — e.g., whether breakeven-stopped remainder legs are more
frequently caught by cross-book risk-cap timing than fixed-2R positions —
is a natural follow-on question but is out of scope for this bounded
study; the finding itself, that the interaction exists and is large, is
what matters for the decision below.)

### Weak-core-month behavior

Of FastMedConfluence A's 5 negative-expectancy months, P3-SR3 improves 3
(2025-05, 2025-11, 2026-03) and worsens 2 (2025-07, 2026-06) relative to
the P3 control — a mixed, not clearly favorable, pattern. Full table:
`weak_core_months.csv`.

### Integrity

Zero duplicate logical IDs, zero cross-family actions, maximum observed
portfolio risk 0.4997% (P3-SR3) / 0.4997% (P4-SR3), both safely under the
0.50% cap; account mode HEDGING throughout; 64 and 63 partial-close events
respectively, matching the per-book exit-management journals exactly.

### Classification

**P3-SR3: REJECTED. P4-SR3: REJECTED.** The primary Phase 4 gate —
"exceeds matched core on cumulative R" — fails decisively for both (-28%
and -25% respectively). The genuine drawdown improvement is real but far
too small to offset the much larger loss of SweepReclaim's own
portfolio-level edge. Combined with D028's SR5 finding (a different
failure mode — zero DD effect rather than a large R cost — but the same
ultimate verdict), this is now the **second independent exit-management
study, under two different sizing regimes, to find that no tested
SweepReclaim exit-management variant improves the actual executed
independent-book portfolio.** D29-P3 and D29-P4 (both SweepReclaim SR0,
original unmodified exit management) remain the best percentage-sized
portfolios found anywhere in D029.

Committed as `D029 Phase 4: percentage-sized portfolio comparison`.
