# Six-Family Component Contracts

## Engine to family

`CMSZZTripleZigZagEngine::Rebuild()` rebuilds three `MSZZSpeedSnapshot` values from chronological `MqlRates`. Pivots carry immutable IDs, pivot/confirmation times, price, and label. ATR, leg direction, current extreme, projected support/resistance, break flags, and break IDs are current rebuild outputs. A break ID embeds the last pivot ID, but does not freeze the projected break price or the opposite pivot. Families may copy pivot records. They may not infer that `resistance_now`, `support_now`, a regime amplitude, and a break ID share one event owner.

Missing validity, an empty event ID, or an ownership relationship not represented by the type must fail closed.

## Family to candidate

A lifecycle emits at most once. Candidate geometry is finite and directionally valid. Origin, sequence, and event identities are nonempty and typed metadata is complete. All mutable family state needed for audit is copied at emission.

## Candidate to journal

The schema has an explicit version, fixed typed columns, one RFC-4180-compatible escaping rule, deterministic time/number formats, row count and file hash. Required fields never live only in free text. A malformed row, column-count mismatch, duplicate event ID, unsupported schema, or unescaped delimiter fails the study; parsers never reconstruct evidence heuristically.

## Candidate to simulator

The simulator validates geometry and next-entry bar availability, uses the declared next-executable entry and cost model, enforces one-family occupancy/stacking/opposite policy, applies a frozen same-bar stop/target rule, and declares expiry and end-of-data behavior. Every rejection and exit is journaled.

## Research to production parity

Before integration, compare signal time, direction, origin/sequence/event IDs, entry/stop/target, expiry, stacking, and opposite-signal behavior. Equality is required unless a difference was approved before screening. Any undeclared difference blocks promotion.

## Candidate to cluster

The family declares which immutable identity is the cluster origin. Only candidates representing the same economic opportunity may cluster. Distinct lifecycles remain distinct. Cluster and consumed-key persistence scope, restart behavior, and namespace are explicit.

## Cluster to StrategyBook

The selected cluster names one owner strategy. Routing validates book state and strategy, same-direction open behavior, opposite-direction behavior, pending transition, and logical position identity. A book can act only on its own ticket.

## StrategyBook to broker

The book requests risk; sizing normalizes down to broker volume constraints and proves actual initial risk does not exceed the request. `PrepareMarketCandidate` normalizes the stop and reconstructs target under the frozen target policy. Portfolio risk, ownership, margin and protection must approve before a persisted execution intent reaches `ExecutionCoordinator`. Failed submission rolls intent/book state back or enters explicit recovery.

## Broker to reconciliation

Position ticket, entry and every exit/partial deal are attributed to the persisted intent and logical position. Weighted exit includes all volumes. Commission and swap are reported separately. Closed-book R uses initial risk and reconciled weighted exit. Unknown or cross-family exits, volume imbalance, duplicate IDs, or unresolved logical positions fail certification.

## Restart

`EventStore`, `ExecutionIntentStore`, `StrategyBook`, and `VirtualNettingLedger` persistence are loaded and reconciled to broker history/positions before new entry. Corruption or ambiguity enters recovery-required state; it never guesses ownership.
