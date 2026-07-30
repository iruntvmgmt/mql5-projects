# D033 post-verdict audit

## Outcome

**`D033_INTEGRATION_DEFECT`**

The 389-trade production configuration remains rejected exactly as
tested, and D034 remains unauthorized. The underlying frozen Session
Sweep Reversal hypothesis is not conclusively disproven because the
production identity layer suppressed timestamped re-arm events that D032
treated as distinct opportunities.

No strategy threshold, session window, sweep/reclaim rule, stop, target,
direction rule, or risk setting was changed in this audit.

## Final 32-suite regression from `ca0aef6`

All 32 `regress_Test_MSZZ_*.ini` suites were launched sequentially from
the isolated instance. Each suite recorded the raw MQL5-log baseline and
required newly appended lines. The two legacy formats were inspected
directly:

- Determinism: `TEST PASS: deterministic rebuild`
- PositionSizing: 99 `PASS:` assertions and
  `Test_MSZZ_PositionSizing: failures=0`

Normalized result: **31 passed, 1 failed, 0 tooling no-ops**.

`Test_MSZZ_PortfolioRouting` failed:

```text
FAIL: duplicate keys are strategy-qualified
TEST_SUMMARY tests=13 failures=1
```

`CMSZZPortfolioBookRouting::ConsumedKey()` allows only FastMedConfluence
and SweepReclaim; it does not allow production SSR strategy 1090. This is
a genuine incomplete D033 routing integration. The standalone runtime
still consumed the unqualified cluster through the outer single-book
path, which is why trades executed, but the intended strategy-qualified
contract is not satisfied.

## Cluster rejection classification

Production SSR assigns:

```text
origin_id = ASIA_HIGH|YYYYMMDD or ASIA_LOW|YYYYMMDD
event_id  = SSRP|origin_id|arm_timestamp|FINAL
```

The cluster engine builds identity from `origin_id`, not `event_id`, and
the single-book path permanently consumes that cluster ID. Consequently,
all re-armed events with the same direction and calendar day share one
consumption key.

Complete classification of the 2,249 rejections:

| Classification | Count |
|---|---:|
| Exact repeat of the consumed event ID | 0 |
| Distinct timestamped re-arm event ID | 2,249 |
| Occurred after the first broker trade had closed | 1,545 |
| Accepted as a distinct synthetic trade by D032 | 471 |
| Both after broker close and accepted by D032 | 461 |
| Crossed London/New York session boundary from first event | 637 |

Thus none of the 2,249 rows is a byte-identical or identity-identical
repeat of the consumed SSR event. Some are intentionally ineligible
under D032's no-same-family-stacking rule, but 471 were explicitly
accepted by D032 as separate trades, including 461 after the earlier
production position was already flat.

The row-level evidence is
`Tools/D033/ssr_cluster_rejection_audit.csv`.

## Interpretation

This is more than a neutral methodology mismatch. D032's simulator and
the frozen SSR state machine both preserve the arm timestamp as event
identity, while production clustering discards it and consumes only
day/direction identity. The production port therefore does not execute
the opportunity population that passed D032 screening.

The original result remains valid for this exact policy:

```text
one executable Asia-high event and one executable Asia-low event
per calendar day
```

It is not a conclusive performance test of:

```text
the frozen D032 SSR event stream with no same-family stacking
```

## Required remediation

Before another performance run:

1. Add SSR 1090 to the strategy-qualified consumed-key allowlist.
2. Define the cluster origin for SSR at the frozen setup/event level,
   preserving the arm timestamp rather than calendar-day direction only.
3. Add deterministic tests proving:
   - repeated evaluation of the same event is rejected;
   - a genuinely re-armed timestamped event receives a distinct key;
   - same-family stacking still rejects while an SSR book is open;
   - a re-armed event can execute after the prior SSR position closes.
4. Recompile and rerun all 32 suites.
5. Rerun standalone D033 unchanged and rebuild every reconciliation file.
6. Reverify byte-identical P4 parity.

This remediation changes identity plumbing, not the frozen research
definition. D034 remains blocked until the corrected D033 run passes all
mandatory promotion gates.
