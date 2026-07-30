# Six-Family Recovery Master

Status: specification-first recovery at audit base `d742a9e45b2404b19ca2496212aa6f52c9101053`.

No family is authorized for implementation. D034 and D035 are blocked. Existing D031-D033 results remain historical evidence, but are not certification of the original six hypotheses.

## Governing workflow

```text
economic hypothesis -> executable specification -> input ownership
-> state machine -> identity -> research candidate -> versioned journal
-> simulator -> promotion decision -> production adapter -> handoff
-> cluster -> eligibility -> StrategyBook -> risk -> intent -> broker
-> deals -> reconciliation
```

Every arrow is a fail-closed contract. Ambiguous economic terms are `SPECIFICATION_GAP`; unavailable event ownership is `INPUT_OWNERSHIP_GAP`; research/production policy disagreement is `METHODOLOGY_MISMATCH`.

## Program findings

The accepted findings are: SSR used incomplete session semantics, same-call re-arms, initially coarse clustering, and mismatched exit policy; MC mixes current snapshot values without a common event owner and has zero real candidates; BRC does not freeze the broken projected level; CBR substitutes medium-or-slow alignment and omits required invalidations; TP does not require movement toward value; RR proxies stability, touches, and containment. The shared journal was delimiter-unsafe and the tests did not establish reachability, ownership, reset semantics, immutable reference attribution, or simulator/production parity.

## Authorization rule

`Tools/SixFamilyRecovery/implementation_authorization.csv` is authoritative. A family may change to `implementation_authorized=true` only after every preceding column is true and an explicit review freezes every ambiguity. No current family satisfies that rule.

## Exact next action

Review and freeze the alternatives in `family_ambiguities.csv`, beginning with the shared time/session/DST authority and structural-event ownership model. Then enrich the engine with event-owned fields only if the approved specifications require data the current snapshots cannot provide. Family implementation remains prohibited until its row is fully authorized.
