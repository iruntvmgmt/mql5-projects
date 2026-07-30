# Strategy Family Test Standard

No full-history screening precedes these deterministic gates.

## Required matrix

- Economic events: fresh event, reevaluation, fresh after reset, same-bar re-arm, still-true re-arm, post-expiry/invalidation without reset, and day/session reset.
- Ownership: break event matches stored level; amplitude matches impulse; copied pivot IDs remain immutable; later snapshots do not mutate the setup; missing ownership fails closed.
- Boundaries: below, equal, and above every threshold.
- Real history: positive, near miss, expiry, invalidation, reset, and session/day transition.
- Reachability: each synthetic input lies within observed distributions and the combined state occurred historically, or the fixture is marked artificial and cannot certify reachability.
- Identity: same origin/same lifecycle, same origin/new lifecycle, different origin, timestamp collision, cross-session/day, and duplicate evaluation.
- Simulator: hand-calculated target-first, stop-first, both-touched, neither, expiry, test-end, opposite signal, same-family open, and spread adjustment.
- Production parity: identical research/production candidate, cluster identity, consumed key, ownership, exit policy, and fail-closed canonical settings.

## Evidence

Each test records fixture provenance, input hashes, expected transition/output, actual output, raw log path and timestamp. A summary without fresh raw logs is insufficient. Real-history fixtures identify symbol, timeframe, data hash, and closed-bar interval.

## Certification

All invariant tests, real replay tests, complete regression, P4 parity, accounting, ownership, and the declared promotion gates must pass. Tooling no-ops, stale logs, malformed journal rows, or unexplained differences are failures.

