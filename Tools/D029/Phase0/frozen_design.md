# D029 Phase 0 — Frozen Design

Frozen before any D029 backtest result is inspected. Full narrative in
`Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md`; this file is the
compact machine/human-readable record.

```text
sizing_mode: PERCENT_EQUITY
risk_per_fastmed_book_pct: 0.25
risk_per_sweep_book_pct: 0.25
max_total_portfolio_initial_risk_pct: 0.50
max_active_books: 2
max_books_per_strategy: 1

partial_fraction: 0.50
sr3_first_partial_trigger_r: 1.0
sr3_remaining_target_r: 2.0
sr3_remaining_stop_after_partial: entry_price
sr4_first_partial_trigger_r: 1.0
sr4_runner_stop_after_partial: entry_price
sr4_fixed_target_after_partial: none
sr4_trailing_source: confirmed_causal_structural_pivots_only

opposing_books: allowed
cross_family_close: disabled
cross_family_reverse: disabled

tester_balance_usd: 100000
volume_normalization_rule: normalize_down_never_up
partial_ineligible_policy: reject_as_PARTIAL_VOLUME_INELIGIBLE
partial_ineligible_max_acceptable_pct: 5.0
risk_tolerance: actual_risk_never_exceeds_requested_risk_underrisk_permitted
```

## Symbol metadata (XAUUSD, Coinexx-Demo, captured via SymbolMetadataProbe.mq5)

```text
volume_min: 0.01
volume_max: 100.00
volume_step: 0.01
tick_size: 0.01
tick_value: 1.00
contract_size: 100
point: 0.01
digits: 2
account_currency: USD
account_login: 870012 (isolated demo, per standing authorization)
```

## Tester balance selection (pre-result, volume-resolution-only)

Projected against D028's certified SweepReclaim SR0 stop-distance
distribution (190 trades; min 0.54, median 5.44, mean 8.25, p95 25.78,
max 112.59, all in XAUUSD price units):

| candidate balance | % trades >=0.02 lots | % exact 50/50 split | % non-exact split | % below minimum |
|---|---|---|---|---|
| $10,000 | 82.63% | 43.68% | 38.95% | 5.26% |
| $25,000 | 98.42% | 57.37% | 41.05% | 0.53% |
| $50,000 | 99.47% | 53.68% | 45.79% | 0.00% |
| $75,000 | 99.47% | 54.74% | 44.74% | 0.00% |
| **$100,000** | **100.00%** | 45.79% | 54.21% | 0.00% |
| $150,000 | 100.00% | 51.05% | 48.95% | 0.00% |

**Frozen tester balance: $100,000** -- the handoff's own suggested starting
candidate, verified (not assumed) to clear the required 95% partial-capable
threshold with the maximum available margin (100%, not merely 95%+).
Honest tradeoff disclosed here before any performance result is seen: a
majority of trades at $100,000 (54.21%) will split into a non-exact-50/50
partial (e.g. 0.07 lots -> 0.03/0.04, not 0.035/0.035) because normalized
raw volumes at this balance land on varied values, not only multiples of
0.02 -- every such split will be separately categorized per the handoff's
own tolerance rule, not silently treated as a clean 50/50.
