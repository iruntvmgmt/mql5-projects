# D032 — Standalone Synthetic Screening

Simulates all six D031 shadow families' real candidate stream through one
shared, frozen simulator and applies the handoff's frozen screening gates.
No family definitions or thresholds were changed based on these results
(anti-overfitting rule: freeze before inspecting).

## Inputs (all real, not synthetic)

- `D032_SixFamilyResearchJournal_source.csv` — the 3,234 real candidates
  D031's certification Config B run actually generated (shadow research
  enabled, full P4 backtest, 2025.03.03–2026.07.24, XAUUSD M5). Copied
  from `/Users/matt/MT5-MSZZ-TEST/D031_Cert_B_Results/`.
- `D032_Rates_XAUUSD_M5.csv` — 99,117 closed M5 bars over the same window,
  exported via a dedicated read-only script
  (`Scripts/MultiSpeedZigZagTools/D032_ExportRates.mq5`, `CopyRates` only,
  never touches a position/order) run against the isolated instance.
- `D032_RegimeJournal_source.csv` — bar-level regime census from the same
  Config B run, for regime attribution.
- `D032_P4_TradeAnalytics_reference.csv` — the certified P4 trade stream
  (Config A, byte-identical to `D029_Audit_Results/D29_P4`), for overlap
  analysis.

## A real bug found and fixed while building this

`MSZZ_SixFamilyResearchJournal.csv`'s `structural_context` field embeds
its own `;`-separated sub-fields (e.g. `compression_high=X;compression_low=Y`),
which collided with the CSV's own `;` delimiter — MQL5's `FileWrite` does
not quote/escape delimiter characters inside a field, so every non-empty
`structural_context` misaligned that row's trailing columns by however
many extra `;` it contained. All six `Research/Families/*.mqh` files were
fixed to use `|` instead (matching this codebase's own existing
convention for composite IDs elsewhere, e.g. `origin_id`/`event_id`).
`simulate_and_screen.py`'s `load_candidates()` works around the
already-generated (real, not re-run) evidence for this analysis by
reconstructing the correct field boundaries from the known fixed-position
header/trailer, documented in the function's own docstring.

## Simulator — frozen assumptions

- **Entry**: the family's own emitted `entry` price (bar-close at signal
  confirmation) — the same execution model the production strategies
  already use (`D027StrategyFamilies.mqh`'s `Emit()` uses `bar.close`
  directly too), not a new, undocumented shifted-entry model.
- **Canonical stop / canonical target**: the family's own emitted
  stop/target verbatim. No re-optimization, no sweep.
- **Same-bar stop/target ambiguity**: if a single bar's range contains
  both, the stop is assumed hit first (conservative — per
  `RESEARCH_JOURNAL_SCHEMA.md`'s own rule, "do not assume the favorable
  outcome").
- **One logical position per family, no same-family stacking**: candidates
  processed in `signal_time` order per family; a new candidate is rejected
  while that family already has an unresolved open position.
- **No future leakage**: outcomes resolved by walking the closed-bar price
  series strictly forward from the bar after `signal_time`.
- Trades still open when the price series ends are excluded from
  closed-trade statistics (reported separately as `still_open_excluded`),
  never scored as a win or loss.

## Outputs (`out/`)

```text
screening_summary.csv        — one row per family: every required D032 metric + frozen gate pass/fail
simulated_trades.csv         — every resolved trade (all 6 families), with realized_r/MFE/MAE/holding time
session_attribution.csv      — per family x session
regime_attribution.csv       — per family x market_phase
redundancy_overlap.csv       — pairwise trade-window overlap: the 6 families vs each other, and vs P4's two production books individually
```

See `Docs/MultiSpeedZigZag/D032_SIX_FAMILY_SCREENING.md` for the narrative
findings and promotion decision.
