# D028 Stage 2 — Deterministic Portfolio Tests

This checkpoint tests and hardens the default-disabled architecture. It does
not activate broker routing or begin Stage 3 single-book equivalence.

## Results

- EA compile: 0 errors, 0 warnings
- Test-script compiles: 27/27, 0 errors, 0 warnings
- Runtime suites: 27/27 passed
- New D028 assertions: 68, 0 failures
- Short shadow: 113 candidates, 46 clusters, 0 malformed, 0 trades
- Long shadow: 431 candidates, 178 clusters, 0 malformed, 0 trades
- Account: isolated HEDGING tester only
- Live deployment: none

The Stage 0B A and SweepReclaim controls were reused rather than rerun because
the new mode remains unreachable by default. Stage 3 is responsible for exact
A, E, and SweepReclaim reproduction through the new single-book path.

## Boundaries

The deterministic account-mode seam is not an EA input and cannot override the
terminal's detected production mode. Netting synthetic protection remains
EA-managed and therefore operationally weaker than broker-hosted ticket stops.
Actual transmission, restart-to-broker reconciliation, and new-path
single-book equivalence remain blocked.

See `test_coverage.csv` for the requirement-to-suite mapping.
