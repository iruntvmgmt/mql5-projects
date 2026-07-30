# Screening Execution Contract v2

Policy ID: `MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST`. Both Python screening and MQL5 production adapters must implement this policy from the same versioned fixture data. This document freezes semantics; it does not authorize production integration.

## Entry and geometry

- A signal is confirmed at a closed bar. Entry occurs at the first executable tick/bar open strictly after `signal_time`.
- Candidate entry is diagnostic. Executable long entry is next raw ask; short entry is next raw bid. Historical bar screening uses next bar open plus recorded spread for long and next bar open for short, matching the declared bid-bar data model.
- `spread_price = spread_points * point_size`. No invented fallback spread is permitted.
- The raw family stop is normalized away from entry to the broker tick-size grid: long stop rounds downward; short stop rounds upward. It is then moved farther away if required by the frozen stop/freeze distance captured in the dataset. It is never moved closer.
- Target is reconstructed **after** executable entry and normalized stop: `risk = abs(entry-stop)` and fixed-R families use `entry +/- target_r*risk`. Explicit-level families use their frozen level only if the resulting R meets their specification. Target rounds toward the conservative side: long downward, short upward.
- A geometry change that cannot retain the declared policy is rejected, not silently repaired.

## Occupancy and signals

One open position per family. Same-family stacking is disabled. Every same-direction or opposite-direction signal arriving while that family has an open position is classified `REJECT_FAMILY_OPEN`. No opposite-signal close and no immediate reversal occur.

## Exits and ambiguity

Only normalized stop, normalized/reconstructed target, or test-end closes a trade. On a bar touching both stop and target, stop wins (`STOP_FIRST_CONSERVATIVE`) because intrabar order is unavailable. A gap beyond an exit fills at the first executable adverse price: long stop at `min(open,stop)`, short stop at `max(open,stop)`; favorable target is capped at target. Expiry governs entry eligibility only: a candidate must obtain its executable entry at or before expiry; expiry does not close an open trade.

At test end, an open long exits at final bid close and an open short at final ask close. The exit reason is `TEST_END`, and the trade participates in all metrics.

## Measurement and accounting

- MFE/MAE begin at executable entry and include every bar from the entry bar through the exit bar, capped at the actual exit price on the exit side.
- Holding bars count entry bar as one and exit bar inclusively.
- `initial_risk_price = abs(executable_entry-normalized_stop)`.
- Gross `R = direction_sign * (exit-entry) / initial_risk_price`.
- Screening headline R is gross price R. Commission and swap are dedicated monetary fields and are not silently converted to R. Net-R reporting is optional only when account currency, tick value and volume are all available and must be labeled.
- Spread is already embodied in entry/short test-end prices and is never subtracted twice.

## Shared policy object

The canonical serialized policy contains: policy/schema version; entry timing/data-side; spread rule; stop grid/minimum-distance rule; target rule; occupancy and signal policy; ambiguity rule; expiry/test-end rules; MFE/MAE/holding/R/cost rules.

Python and MQL5 may use native structs/classes, but their values must be loaded or generated from the same committed registry and verified against `cross_language_parity_fixtures.csv`. Independent defaults are prohibited.

## Parity gate

Each implementation consumes identical fixture columns and emits status, normalized geometry, entry/exit time and price, exit reason, holding bars, MFE, MAE and R. Decimal comparison tolerance is `1e-9` in price/R after tick normalization. Any differing expectation is a contract failure and blocks screening and production.
