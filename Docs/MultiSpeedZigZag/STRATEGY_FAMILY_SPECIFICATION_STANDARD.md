# Strategy Family Specification Standard

This standard is mandatory before research or production logic is written.

## Required specification

1. **Economic hypothesis:** behavior, persistence rationale, confirmation, disproof, expected and failure regimes.
2. **Economic opportunity:** deterministic start/end, freshness and neutral-reset prerequisites, same-bar/still-true re-arm permissions, day/session reset, and maximum lifecycles per structural origin.
3. **Input ownership:** field, object and producer, represented bar/event, arm-time copy rule, post-arm mutability, and fail-closed behavior.
4. **Canonical sequence:** Prerequisite, Arm, Observe, Trigger, Emit, Expire, Invalidate, Reset, Re-arm. Each states guard, before/after state, timestamp, captured/updated values, and journal record.
5. **Transition table:** every state covers trigger, opposite structure, expiry, session/day boundary, missing input, invalid geometry, and same-bar competition. It explicitly states whether the same call may re-arm.
6. **Bar order:** active evaluation versus arming, terminal/re-arm ordering, current-bar window membership, trigger/window relationship, and next-bar versus next-tick entry.
7. **Structural ownership:** level type/ID/price/confirmation/source event, immutability, staleness, test count, and replacement.
8. **Executable geometry:** exact entry, stop, target, and invalidation formulas and their evaluation time.
9. **Identity:** exact `origin_id`, `sequence_id`, and `event_id` constructions.
10. **Typed metadata:** required fields have dedicated versioned columns; free text is supplemental only.
11. **Simulator:** entry, exit, opposite signal, stacking, same-bar collision, costs, occupancy, and end-of-data.
12. **Production:** IDs, book, magic, risk, target/exit policy, stacking, opposite behavior, cluster/consumed identity, and restart persistence.

## Identity invariants

One lifecycle retains one `sequence_id`; a new lifecycle receives a new one. One final emission has one stable `event_id`. Reevaluation cannot create a new event. Distinct economic events cannot share an event ID. `origin_id` may group related lifecycles but may not accidentally become execution suppression. `cluster_id`, `consumed_key`, and `logical_position_id` are downstream identities and are never aliases.

## No silent interpretation

Qualitative terms such as meaningful, major, shallow, broad, controlled, mature, stable, confirmed, over-tested, stale, excessive, near, toward value, and structural coherence require an explicit formula or remain `SPECIFICATION_GAP`.

Any proxy must state the original concept, proxy, information lost, expected false positives/negatives, selection reason, and required test.

## Stop conditions

Stop when common event ownership is unproven, a structural level cannot be tied to its event ID, required data is unavailable, an event cannot be deterministic, audit metadata is unavailable, bar ordering or resets are undefined, a positive fixture is unreachable, the schema is unsafe, or simulator and production policy differ.

