# Opportunity Clustering Contract

## Purpose

Several strategy models may identify the same structural event. Clustering prevents duplicate trades and preserves the distinction between independent opportunities and supporting interpretations.

## Core entities

### Raw candidate

A strategy-specific interpretation with its own strategy ID, score, trigger, stop, and reason.

### Structural origin

The immutable event from which one or more candidates arise, such as:

- fast bullish line break
- medium bearish line break
- pivot-shelf sweep
- completed structure transition

### Opportunity cluster

A collection of compatible candidates sharing a structural origin, direction, and bounded time relationship.

## Cluster identity

Canonical format (version `MSZZC1`, effective 2026-07-25 — see DECISION_LOG.md D004):

```text
MSZZC1|<len>:<symbol>|<len>:<timeframe>|<len>:<direction>|<len>:<origin_type>|<len>:<origin_id>
```

Every field is length-prefixed (`<len>` is the exact character count of the value that follows the `:`). This is required because `origin_id` is frequently itself an already pipe-delimited breakout/pivot identity (e.g. `BO|XAUUSD|5|1|S|<time>|MSZZ|XAUUSD|5|1|-1|<time>|<time>`) and a naive `|`-delimited outer format cannot distinguish the outer cluster-ID delimiters from delimiters inside `origin_id`. Always construct and parse cluster IDs through `CMSZZOpportunityClusterEngine::EncodeClusterId()`/`DecodeClusterId()` — never by ad hoc string splitting.

The prior format (`MSZZC|symbol|timeframe|direction|origin_type|origin_id`, no version marker) is deprecated and was confirmed ambiguous in practice: real exported cluster IDs contained 17 `|` characters instead of the 5 the five-field description implied. IDs in that format are legacy evidence only; they are not compatibility-stable and a decoder for the new format correctly rejects them (different literal prefix).

Cluster IDs must not depend on strategy ranking or score. Adding a supporting strategy later must not change the cluster ID.

## Compatibility rules

Candidates may join one cluster when all are true:

- same symbol and timeframe
- same direction
- same explicit structural origin, or a documented parent-child origin relationship
- signal times fall inside the strategy-specific compatibility window
- stops express the same structural invalidation thesis

Candidates must remain separate when:

- directions conflict
- origins are independent breaks occurring after a new pivot cycle
- invalidation structures differ materially
- one is continuation and one is mean reversion against the same level
- combining would hide separate risk exposure

## Parent-child origin examples

- Fast breakout → later medium confirmation: same cluster.
- Fast breakout → retest of that exact broken line: same cluster, later execution phase.
- Fast breakout → unrelated slow breakout after a new slow pivot cycle: separate cluster.
- Shelf sweep/reclaim against an active bearish breakout: conflicting clusters.

## Cluster fields

A production cluster must contain:

- cluster ID
- symbol/timeframe
- direction
- origin type and ID
- origin time
- first and latest candidate times
- lifecycle state
- candidate strategy IDs
- candidate scores and feature vectors
- canonical structural stop
- stop disagreement measure
- combined evidence score
- preferred execution model
- expiry
- conflict IDs
- consumed/executed state
- order/position ownership IDs when applicable

## Lifecycle

```text
OPEN → STRENGTHENED → SELECTED → EXECUTED → MANAGED → CLOSED
   ↘ EXPIRED
   ↘ INVALIDATED
   ↘ CANCELLED_CONFLICT
```

A cluster may be strengthened by later evidence without creating another order unless staged entry is explicitly enabled.

## Evidence combination

Do not sum strategy scores directly because the models are correlated.

Milestone-1 combination rule:

1. Start with the highest raw candidate score.
2. Add a capped support bonus for each distinct evidence family:
   - trigger speed
   - higher-speed context
   - structure transition
   - momentum/volume quality
   - retest/sweep confirmation
3. Do not award multiple bonuses for several strategies using the same fact.
4. Record the evidence-family mask used in the combined score.

## Canonical strategy owner

Each cluster retains all supporting strategies, but one strategy becomes the reporting owner. Selection priority:

1. Most specific stateful interpretation
2. Strongest validated hypothesis version
3. Highest combined score
4. Stable strategy-ID tie break

Example: nested pullback should own a cluster over generic fast breakout when both describe the same event.

## Staged entries

Disabled by default.

When enabled, a cluster may permit stages such as:

- probe on fast break
- confirmation add on medium break
- retest add

Each stage must have:

- maximum cumulative cluster risk
- unique stage ID
- explicit prerequisites
- no duplicate stage after restart

## Conflict arbitration

A bullish and bearish cluster may coexist as research records, but execution arbitration must choose one of:

- reject both due to ambiguity
- retain existing position and reject opposite cluster
- close/reverse under an explicit reversal policy
- choose the stronger cluster if flat

Every rejection must be journaled.

## Migration from current implementation

The current suite selects the highest-scoring candidate directly. Replacement steps:

1. Add immutable structural-origin fields to `MSZZCandidate`.
2. Build `CMSZZOpportunityCluster` aggregation.
3. Group raw candidates before selection.
4. Persist open and consumed clusters.
5. Journal cluster membership and evidence masks.
6. Execute only selected clusters, never raw candidates directly.