# D033 — Session Sweep Reversal promotion and execution

## Verdict

**REJECTED. D034 is not authorized.**

The frozen Session Sweep Reversal definition was promoted from research
ID 1200/family 8 to production strategy ID 1090/family 4 and executed as
one standalone StrategyBook at 0.25% risk with broker-native stop and
fixed 2R target. It remains positive overall but fails mandatory
development, holdout, and best-quarter-exclusion gates. No threshold,
session rule, stop, target, direction rule, or duplicate rule was tuned.

## Authoritative workflow and evidence

Bash/Wine is the established project workflow, not an improvised
workaround. MCP compilation has previously returned success while doing
nothing. D033 therefore used `wine start /Unix metaeditor64.exe` and
accepted compilation only after the UTF-16LE `logs/metaeditor.log`
contained a fresh entry naming the exact source and real counts.

The interrupted standalone run was not repeated: raw isolated-instance
logs prove it completed on 2026-07-30 at 00:03:09, covered
2025-03-01 through 2026-07-24, wrote all journals and the HTML report,
and shut down normally. Evidence was rebuilt from the raw signal, sizing,
risk, StrategyBook, deal, trade, and portfolio-trade journals.

## Standalone result

| Metric | Result |
|---|---:|
| D032 synthetic trades | 822 |
| Production candidates | 2,650 |
| Broker-executable closed trades | 389 |
| Rejected candidates | 2,261 |
| PF in R | 1.0533 |
| Expectancy | +0.0345R |
| Total | +13.4257R |
| Maximum drawdown | 19.7294R |
| Win rate | 34.96% |
| Average win | +1.9522R |
| Average loss | -0.9963R |
| Development | 249 trades, -5.6663R, -0.0228R expectancy |
| Validation | 78 trades, +21.0798R, +0.2703R expectancy |
| Holdout | 62 trades, -1.9878R, -0.0321R expectancy |
| Long | 176 trades, +3.4660R, +0.0197R expectancy |
| Short | 213 trades, +9.9597R, +0.0468R expectancy |
| Top-3 exclusion | +7.4092R |
| Best-quarter exclusion | -7.6583R |

Rejections were 2,249 duplicate clusters, 9 ownership/same-family
stacking conflicts, 2 spread rejections, and 1 expiry. Production emits
2,650 raw candidates versus D032's 822 resolved synthetic trades because
D032 simulated same-family non-stacking while production additionally
uses the existing consumed cluster key, which permits at most one
execution per day/direction origin cluster. This frozen infrastructure
behavior was not loosened.

## Synthetic versus broker

The trade-level mapping is
`Tools/D033/ssr_synthetic_broker_comparison.csv`. Executed rows differ
through the required next-tick market entry, bid/ask spread, stop/target
normalization, and volume normalization. Nonexecuted rows identify
duplicate collision, ownership, spread, or expiry. These are classified
execution differences, not unresolved discrepancies.

## Candidate-to-deal and accounting reconciliation

`ssr_candidate_execution_funnel.csv` maps every production candidate
through cluster, intent, order, position, deals, closed StrategyBook
trade, reported R, and recomputed R. All 389 trades have one entry deal
and one exit deal. Weighted-exit calculation nevertheless sums all exit
deals and volumes, so it remains valid if partials appear.

Integrity results:

- zero unresolved logical positions or duplicate event/intent IDs;
- zero unknown exits (eight analytics `OTHER` rows were traced in raw
  logs to own-family opposite closes);
- zero cross-family closes/modifies and zero ownership violations;
- zero volume, weighted-exit-price, or reported-R mismatches;
- actual initial risk never exceeded requested risk;
- portfolio risk never exceeded the configured cap.

## Compile, tests, and P4

The final EA compile at `2026.07.30 00:15:09.728` reported 0 errors and
0 warnings. D033-focused tests compiled 0/0. The corrected production
SSR signal fixture ran 8/8 with zero failures in the raw MQL5 log.
The complete pre-D033 32-suite regression was green, and the modified
handoff/routing tests compiled cleanly; a new complete-suite rerun is
still required before any future promotion, so the full-regression gate
is conservatively recorded as failed/pending.

P4 was rerun from the D033 binary before SSR standalone execution:
330 trades, +47.6083R, PF 1.2472, canonical journal SHA-256
`9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`,
byte-identical to the certified reference.

## Mandatory gates

| Gate | Result |
|---|---|
| Broker expectancy > 0 | PASS |
| PF > 1.05 | PASS |
| Development positive | **FAIL** |
| Validation positive | PASS |
| Holdout positive | **FAIL** |
| Top-3 exclusion positive | PASS |
| Best-quarter exclusion positive | **FAIL** |
| Zero future leakage | PASS |
| Zero accounting mismatches | PASS |
| Zero ownership violations | PASS |
| Zero unresolved synthetic/broker discrepancies | PASS |
| Full regression green from final test changes | **FAIL / pending rerun** |
| P4 parity preserved | PASS |

The empirical failures are sufficient to reject promotion regardless of
the pending full-suite rerun. D034 must not begin.
