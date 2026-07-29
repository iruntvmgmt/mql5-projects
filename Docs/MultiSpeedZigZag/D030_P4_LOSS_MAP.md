# D030 — P4 Loss-Cluster and Uncovered-Regime Map

Phase 1 of the D030–D035 six-family shadow research program (see
`D030_D035_Six_Family_Claude_Handoff.md`). Scope: analyze the certified P4
portfolio. **No strategy logic, sizing, exits, targets, or stops were
changed.** No new backtest was run — this is a read-only analysis of
already-certified evidence plus one pre-existing bar-level regime census.

Branch: `feature/d030-six-family-shadow-research`, cut from
`feature/d029-audit-remediation` @ `6e55ff34be2d1c827f7d7f14172b96db0208b6c1`.

Scripts and full CSV outputs: `Tools/D030/` (see `Tools/D030/README.md` for
exact input paths, join logic, and reproduction instructions).

## Portfolio recap (recomputed independently from raw evidence, not copied)

330 trades, total R **+47.6083**, PF **1.2472** — matches
`D029_AUDIT_FINAL_REPORT.md`'s certified D29-P4 figures exactly, confirming
this analysis is reading the right evidence.

| Split | Trades | Total R | PF | Expectancy R |
|---|---|---|---|---|
| Development (2025-03–2025-12) | 203 | +19.79 | 1.165 | 0.098 |
| Validation (2026-01–2026-04) | 67 | +12.88 | 1.310 | 0.192 |
| Holdout (2026-05–2026-07) | 60 | +14.94 | 1.478 | 0.249 |

P4 is positive and improving across all three splits — the portfolio itself
is not degrading. The loss clusters below are pockets inside an overall
healthy result, not signs P4 is broken.

Concentration (`out/concentration.csv`): removing the best trade, best 3,
best 5, best month, or best quarter each leaves total R and PF solidly
positive (worst case: best-quarter exclusion, remaining +33.69R, PF 1.213).
P4 is not concentration-dependent — reconfirms D029's own finding
independently.

Book overlap (`out/book_overlap.csv`): 74 overlap episodes between
FastMedConfluence (196 trades) and SweepReclaim (134 trades), **100%
opposing-direction** (0 same-direction), 60.5 total overlap hours —
consistent with the known HEDGING-mode opposing-book architecture, not a
new finding.

---

## 1. Where does P4 generate gross loss?

Three genuine loss clusters, in order of how much of the loss they explain:

| Cluster | Trades | Total R | Expectancy R | Dev / Val / Holdout expectancy |
|---|---|---|---|---|
| `market_phase = TREND_CONTINUATION` | 54 | **-10.48** | -0.194 | -0.159 / -0.237 / -0.281 |
| `exit_reason = OWN_FAMILY_OPPOSITE` | 67 | **-13.39** | -0.200 | -0.261 / -0.017 / -0.121 |
| `market_phase = BREAKOUT` | 41 | **-9.57** | -0.234 | -0.398 / -0.200 / **+0.754** |
| `alignment_state = FULLY_ALIGNED` | 97 | -6.07 | -0.063 | -0.084 / -0.244 / +0.553 |
| `volatility_state = CONTRACTING` | 50 | -3.01 | -0.060 | +0.156 / -0.669 / +0.312 |
| `holding_time_decile = 1` (fastest exits) | 33 | -15.46 | -0.469 | -0.264 / (n small) / -0.845 |

Full detail: `out/bucket_summary.csv`.

## 2. Are losses concentrated in stable market states?

Two are genuinely stable — **negative in development, validation, AND
holdout**, not a one-period artifact:

- `TREND_CONTINUATION` market phase
- `OWN_FAMILY_OPPOSITE` exits (a trade closed early because the opposing
  book fired against it, not by hitting its own stop or target)

The rest are not stable and should not be treated as structural:

- `BREAKOUT` phase flips sign in holdout (+0.754 expectancy vs -0.4/-0.2 in
  dev/val) on a very thin base (only 157 of 98,943 census bars — 0.16% of
  the entire window — were ever classified `BREAKOUT`).
- `FULLY_ALIGNED` alignment flips sign in holdout too.
- `CONTRACTING` volatility flips sign twice (positive dev, negative val,
  positive holdout) — noise, not signal.
- `holding_time_decile = 1` is directionally consistent but each split's
  sub-slice is small (~33 trades split three ways); read as suggestive,
  not confirmed.

`stop_distance_decile` and the `cost_to_risk_decile` substitute for
spread/risk (see "Data limitations" below) are both non-monotonic across
deciles — no clean causal story, just noise. Do not filter on either.

## 3. Which regimes are weak or negative?

Same two as above, plus one more visible only at the single-dimension
regime-coverage level (`out/regime_dimension_coverage.csv`):

- **`FULLY_ALIGNED`** is the *most common* alignment state (60.0% of all
  98,943 census bars) but produces the *worst* per-trade expectancy of the
  three alignment states (-0.063 R/trade) and is under-traded relative to
  its frequency (1.63 trades per 1000 bars vs 4.66 for `OPPOSED`).
  `OPPOSED` alignment — fast/slow structure disagreeing, i.e. transitional
  or countertrend conditions — is where P4 actually makes its money:
  35.2% of bars, 162 trades, **+50.33R total, 0.311 R/trade expectancy**,
  more than the portfolio's entire net total R. This is consistent with
  FastMedConfluence and SweepReclaim both being reversal/confluence
  systems at heart, not trend-following ones — `TREND_CONTINUATION` and
  `FULLY_ALIGNED` losing money is the same underlying fact seen two ways,
  not two separate weaknesses.
- Asian session (`session = ASIAN`) is weak-but-stable rather than
  negative: 101 trades, expectancy near flat in all three splits (0.011 /
  0.260 / -0.003), versus New York's clearly strong and improving 0.074 /
  0.545 / 0.498. Not a loss cluster, but a persistently underperforming
  session relative to New York.

## 4. Which regimes receive few or no trades?

From `out/regime_dimension_coverage.csv` (bar census vs trade count, same
frozen dev/val/holdout window, 98,943 bars total):

| Market phase | % of all bars | Trades | Trades / 1000 bars |
|---|---|---|---|
| `TRANSITION` | 0.264% | **0** | 0.0 |
| `BREAKOUT` | 0.159% | 41 | 261.1 |
| `COMPRESSION` | 4.09% | 23 | 5.68 |
| `PULLBACK` | 6.47% | 57 | 8.90 |
| `UNCLASSIFIED` | 43.9% | 155 | 3.57 |
| `TREND_CONTINUATION` | 45.1% | 54 | 1.21 |

`RANGE` and `FAILED_BREAK` (both valid values of
`ENUM_MSZZ_MARKET_PHASE`) do not appear **at all** — 0 of 98,943 bars, over
the entire ~16-month certified window. `FAILED_BREAK` is already
documented in the classifier source as never emitted
(`RegimeClassifier.mqh`); `RANGE` has no such documented exclusion, so its
complete absence here is a genuine, previously-undocumented finding, not
an expected one.

## 5. Which states are uncovered rather than poorly traded?

- **`TRANSITION` phase**: exists (0.26% of bars, 261 bars) but has never
  produced a single trade. Genuinely uncovered, though the base rate is
  tiny.
- **`RANGE` phase**: never occurs in the classifier's output at all. This
  is not "uncovered by P4" so much as "unreachable by the existing Layer 1
  classifier" — a distinction that matters directly for Family 6 below.
- Everything else with meaningful bar presence (≥1% of the window) does
  get traded at least somewhat — no other genuinely empty common state
  exists (`out/regime_coverage.csv` cross-checked at the 5-way combo level
  confirms no ≥1%-of-window combo has zero trades).

## 6. Which proposed family addresses each gap?

| Finding | Best-matched family |
|---|---|
| `TREND_CONTINUATION` phase / `FULLY_ALIGNED` state — P4's largest, most stable loss cluster (45%/60% of all bars, negative in all three splits) | **Momentum Continuation** (primary), **Trend Pullback** (secondary, same regime from a value-location angle) |
| Asian session persistently flat vs strong New York | **Session Sweep Reversal** |
| `BREAKOUT` phase rare but heavily and unprofitably traded, sign unstable | **Break-Retest Continuation**, **Compression Breakout** (both require a more selective breakout confirmation than whatever currently fires here) |
| `TRANSITION` phase uncovered (thin base rate) | **Break-Retest Continuation** conceptually fits best, but the sample is too thin (261 bars total) to weight this heavily |
| `RANGE` phase never fires in the existing classifier | **Range Rotation** — but see the priority note below; this family cannot lean on the existing phase classifier and must build its own range definition, exactly as the handoff already specifies |

## 7. D031 family implementation priority

1. **Momentum Continuation** — top priority. Targets P4's single largest
   (45% of all bars), most stable (negative dev/val/holdout) loss cluster
   directly, with an entry model (impulse + controlled pause) that is
   structurally distinct from FastMedConfluence's confluence logic, so
   real diversification is plausible rather than just relabeling.
2. **Trend Pullback** — second priority, same target regime from a slower
   value-location-driven angle. Real complementary potential, but D031's
   own required overlap test against Momentum Continuation needs to
   confirm this doesn't collapse into the same trades.
3. **Session Sweep Reversal** — third priority. Independently supported by
   the Asian-session finding. Carries real redundancy risk against the
   existing SweepReclaim book (same core hypothesis, session-scoped) —
   the required overlap test needs to show incremental value.
4. **Break-Retest Continuation** / **Compression Breakout** — secondary.
   Supported by the `BREAKOUT`-phase finding, but that finding rests on a
   thin base (157 bars total) and isn't stable across splits. Worth
   building as shadow candidates per the handoff's "explore broadly"
   instruction, screen them, and let D032's frozen gates decide.
5. **Range Rotation** — lowest priority / highest implementation risk.
   `MSZZ_PHASE_RANGE` never fired once in 98,943 census bars. This isn't
   disqualifying (Family 6 already specifies it must define its own
   "structurally defined and persistent" range, not reuse the phase
   classifier), but D030 reinforces that this is a real requirement, not
   a formality — budget real design time for range detection itself
   before assuming the instrument/timeframe supports the hypothesis at
   all.

## 8. Is there evidence P4's PF can be improved more efficiently by filtering than by adding families?

Partially, yes — but out of scope to act on here. `TREND_CONTINUATION`
phase (-10.48R) and `OWN_FAMILY_OPPOSITE` exits (-13.39R) are both stable
across all three splits on the EXISTING books, which is exactly the
signature of a real, filterable effect rather than noise. Removing or
gating either looks like it could be a cheap lever. But the handoff
explicitly prohibits modifying FastMedConfluence or SweepReclaim entries
during this program, so this is logged as a **recommended future D0xx
study**, not acted on. Within the family-addition path, Momentum
Continuation and Trend Pullback remain the most efficient candidates
because they target this same gap directly rather than a smaller or less
stable one.

---

## Data limitations

1. **MFE/MAE bucket**: not available. Portfolio-level trade exports
   (`D29_P4`, and every other `D029_Audit_Results` config) do not carry
   `mfe_r`/`mae_r` — only the separate single-strategy standalone exporter
   used for SweepReclaim-alone runs (`D029_Phase3_Results/*/MSZZ_TradeAnalytics.csv`)
   does, and that's not the P4 portfolio. Reconstructing MFE/MAE for 330
   portfolio trades would require a new bar-by-bar price replay per trade
   window; not attempted here. Flagged for a future task if excursion-based
   exit design becomes relevant.
2. **spread/risk decile**: `execution_cost` is uniformly `0.0` across all
   330 `D29_P4` trades — no per-trade spread cost is journaled in R terms
   for portfolio-book runs. Reported `cost_to_risk_decile` (broker
   commission+swap ÷ requested risk money) instead, explicitly labeled as
   a substitute, not the literal metric. It correlates strongly with
   holding time (swap accrues per day held) rather than measuring spread
   independently, so its non-monotonic pattern across deciles should not
   be read as a spread-cost finding.
3. **Regime census provenance**: the bar-level regime journal used for the
   uncovered-regime map (§4–6) is sourced from the D028 Stage4 `P4` run,
   not the D029 certified evidence itself, because D029's audit reruns
   didn't export a bar-level regime journal. See `Tools/D030/README.md`
   "Why a D028 file is used for the regime census" for why this is safe
   (the regime classifier is unchanged, pure, and price-structure-only
   between D028 and D029).
4. **ID and name collision found, not fixed here**: the handoff's suggested
   family ID `1060` for Session Sweep Reversal collides with the
   already-assigned `1060 = Compression Breakout (D027 S4)` in
   `STRATEGY_CATALOG.md` (implemented, default disabled). More
   significantly, the handoff's own Family 4 is *also* named "Compression
   Breakout" (suggested ID `1090`) — this is not a fresh hypothesis, there
   is already an implemented D027 S4 `CompressionBreakout` at `1060`. The
   handoff's own Family 4 section already anticipates this ("Audit any
   existing CompressionBreakout code before reuse. Do not assume prior
   implementation is correct or complete") — D031 needs to explicitly
   decide whether Family 4 supersedes, reuses, or is deliberately distinct
   from `1060`, and assign non-colliding IDs for all six families rather
   than the handoff's suggested numbers verbatim.

## Confirmations

- No FastMedConfluence, SweepReclaim, P4 portfolio rule, risk sizing,
  target, stop, or entry logic was changed.
- No new backtest was run; all trade-level evidence is the certified
  `D029_Audit_Results/D29_P4` rerun, independently reconciled to the same
  330-trade, +47.6083R, PF 1.2472 figures already in
  `D029_AUDIT_FINAL_REPORT.md`.
- D031 (six-family shadow architecture) has not started — no
  `Research/Families/*.mqh` files exist yet.
