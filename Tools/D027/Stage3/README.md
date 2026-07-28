# D027 Stage 3 — Default-Off Strategy Families

Stage 3 implements the five predeclared strategy-family hypotheses without
screening or promoting them. Every new EA input defaults to `false`; canonical
A, canonical E, and all existing-eight strategy inputs remain unchanged.

## Implemented hypotheses

| Strategy | ID | Family | Fixed Stage 3 definition |
|---|---:|---|---|
| Aligned Fast Pullback | 1031 | PULLBACK | Slow direction, non-neutral medium context, confirmed fast HL/LH, then close-confirmed reversal break |
| Breakout Retest | 1040 | RETEST | Compatible fast break, frozen level, 12-bar wait, 0.15 fast-ATR touch/reclaim tolerance, 0.30 fast-ATR close invalidation |
| Sweep and Reclaim | 1050 | REVERSAL | Confirmed fast pivot shelf, 0.10 fast-ATR excursion, 0.05 fast-ATR closed-bar reclaim, 0.50 fast-ATR failure, six-bar wait |
| Compression Breakout | 1060 | COMPRESSION | Three consecutive causal `COMPRESSION` bars, frozen fast boundaries, close outside within six bars with medium/slow context |
| Structure Transition | 1070 | REVERSAL | Strict four-pivot `LL,LH,HL,HH` or inverse sequence from the classifier, with medium validation |

These constants were declared before any Stage 4 strategy result and are not
optimizer inputs. `FAILED_BREAK` remains deliberately unimplemented at
classifier level.

## Architecture and auditability

- `MSZZCandidate` carries an explicit family ID; the existing eight are mapped
  explicitly rather than inferred from display names.
- Clusters retain unique supporting strategy and family IDs.
- Signal rows include family, entry-time regime snapshot, cluster owner,
  overlapping strategies/families, execution status, and rejection reason.
- Retest, sweep, and compression sequences write state transitions to
  `MSZZ_SequenceJournal.csv`.
- Nonterminal sequence state is serialized by symbol, timeframe, and magic and
  restored fail-closed when any D027 family is enabled.
- `RESEARCH_FILTER` can reject only D027 candidates in this stage. It cannot
  gate canonical A/E or any existing-eight candidate.

## Verification

The deterministic suite is
`Tests/MultiSpeedZigZag/Test_MSZZ_D027Strategies.mq5`. It covers long and
short triggers, premature/invalidation paths, expiry, exact restart
continuity, cross-family clustering, explicit existing-family assignment, and
default-off behavior.

All runtime verification uses `/Users/matt/MT5-MSZZ-TEST`. Raw tester reports,
CSV journals, and terminal logs remain in that isolated instance rather than
being duplicated in the repository. Final compile, regression, shadow, and
canonical reproduction results are recorded in the D027 decision-log Stage 3
addendum.

Stage 4, not this checkpoint, performs the standalone fixed-2R screen.
