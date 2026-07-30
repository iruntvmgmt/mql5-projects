# D033 — SSR integration-defect remediation

## Verdict

**Integration defect repaired; corrected frozen SSR is `REJECTED`.
D034 is not authorized.**

Production strategy 1090 now supplies its existing timestamped
`sequence_id` as the cluster origin. The shared cluster engine, research
family 1200, frozen SSR thresholds, signal geometry, risk, and execution
policy are unchanged. Separately, strategy 1090 was added to the
strategy-qualified consumed-key routing allowlist.

## Identity-only scope

The preserved pre-backtest journal contains exactly 2,650 production
candidates. Signal times, directions, event IDs, entries, stops, and
targets are unchanged. The old daily reference yielded only 395 origin
identities; the corrected event-scoped origin yields 2,650 identities.
Repeated evaluation of one sequence still forms one deterministic cluster,
while separate same-day and cross-session arms form distinct clusters.

## Compilation and regression

Bash/Wine plus fresh UTF-16LE logs are authoritative. The EA compiled at
`2026.07.30 01:08:38.882` with 0 errors and 0 warnings; affected tests
also compiled 0/0.

The final full regression is **32/32 PASS**, including SSR identity 17/17
and PortfolioRouting 13/13. The two legacy suites were verified from
their raw pass markers. There were no test tooling no-ops.

## P4 parity

P4 reran at 330 trades, +47.6083R, and PF 1.2472. Its canonical journal
SHA-256 is byte-identical to certification:
`9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.

## Corrected standalone result

| Metric | Corrected D033 |
|---|---:|
| Production candidates | 2,650 |
| Unique event-scoped clusters | 2,650 |
| True duplicate-cluster rejections | 0 |
| Same-book-open rejections | 1,730 |
| Spread / expiry / risk rejections | 7 / 7 / 0 |
| Broker trades | 906 |
| PF | 0.9961 |
| Expectancy | -0.00255R |
| Total | -2.3099R |
| Maximum drawdown | 41.6167R |
| Win rate | 34.11% |
| Average win / loss | +1.9062R / -0.9905R |
| Own-family opposite closes | 30 |

The funnel changed as expected: duplicate-cluster rejection fell from
2,249 to zero, executions rose from 389 to 906, and ownership rejection
rose from 9 to 1,730 because distinct events now reach the frozen
same-family stacking rule.

## Robustness and integrity

Development was -0.0001R, validation +11.3056R, holdout -13.6154R,
top-three exclusion -8.3284R, and best-quarter exclusion -25.6184R.
Long and short totals were both negative.

All 906 trades reconcile through deals, weighted exits, StrategyBook
closure, and reported R. There are zero unresolved positions, duplicate
identities/intents, unknown exits, cross-family actions, ownership
violations, volume mismatches, weighted-exit mismatches, reported-R
mismatches, risk overruns, or portfolio-cap overruns.

PF, expectancy, development, holdout, top-three exclusion, and
best-quarter exclusion fail. No tuning or gate relaxation was performed.
The source-level defect is closed, but production SSR is `REJECTED`;
D034 remains unauthorized. Machine-readable evidence is under
`Tools/D033/Remediation/`.
