# Evidence and Checkpoint Standard

## 1. Purpose

This standard defines exactly what must exist before MC-CANON-2 checkpoint 2 may be declared green.

It prevents incomplete evidence from being upgraded by confidence, convenience, process exit, file existence, or identical artifacts with shared authorship.

## 2. Evidence principles

Evidence must be:

- fresh;
- reproducible;
- attributable;
- tied to exact source and binary identity;
- generated in the authorized environment;
- immutable after capture;
- independently reviewable.

A claim without an artifact or log reference is not evidence.

## 3. Checkpoint verdicts

Only these verdicts are permitted:

```text
MC_CHECKPOINT_2_CERTIFIED_JOURNAL_PARITY_GREEN
MC_CHECKPOINT_2_CERTIFIED_JOURNAL_PARITY_BLOCKED
MC_CHECKPOINT_2_CERTIFIED_JOURNAL_PARITY_IN_PROGRESS
```

The Independent Reviewer is the only recovery role authorized to issue the final token.

## 4. Gate group A — Git and source identity

Require:

- correct canonical working directory;
- expected branch or documented discrepancy;
- expected HEAD or documented discrepancy;
- protected recovery, main, and backup refs;
- full inherited dirty-tree inventory;
- no commit or push by recovery agents;
- no reset, clean, stash, branch switch, rebase, amend, or force operation;
- exact current hashes for active MC files;
- no unauthorized QuantBeast or other-family changes.

## 5. Gate group B — frozen specification

Require confirmation that recovery did not alter:

- structural authority;
- pause origin and path formula;
- efficiency rules;
- pause indexing;
- invalidation equality;
- precedence;
- pullback bounds;
- entry, stop, target;
- fixture meanings;
- reason tokens;
- schema ownership.

Any required canonical behavior change needs a separate authorized specification revision and invalidates automatic checkpoint continuation.

## 6. Gate group C — Layer A lifecycle parity

Require:

- MC001–MC023 exact inventory;
- Python lifecycle tests pass;
- fixture generator self-tests pass;
- MQL Layer-A compile 0 errors / 0 warnings;
- MQL Layer-A runtime completed naturally;
- exact transition traces;
- exact rejection tokens;
- exact candidate counts;
- exact pause-bar counts;
- duplicate-event non-rearm behavior;
- trigger-bar geometry exclusion;
- deterministic rerun behavior;
- zero harness and fixture failures.

## 7. Gate group D — Layer B certified projection

Require:

- exactly seven emitting fixtures;
- exact emitting IDs;
- certified SER generation recorded;
- MQL SER validation for every emitting fixture;
- Python SER-reference parity;
- MQL candidate-schema validation for every emitting fixture;
- Python schema-reference parity;
- exact 116-column candidate projection where currently specified;
- substitution table for all changed source fields;
- all behavior/economic changed flags false;
- exact candidate ordering.

## 8. Gate group E — independent MQL runtime

Require:

- authorized isolated runtime only;
- ticketed dependencies staged with manifest;
- current source compiled to a fresh EX5;
- explicit source-to-binary identity;
- fresh log boundary;
- exactly one launch;
- explicit start marker;
- explicit completion marker;
- expected assertions and fixture counts;
- zero failures;
- expected output paths;
- confirmed MQL authorship.

No main-terminal fallback is accepted.

## 9. Gate group F — journal parity

Require independently authored Python and MQL journals with:

- exact byte equality;
- exact length;
- exact SHA-256;
- exact row count;
- exact column count;
- exact row ordering;
- UTF-8 without BOM;
- CRLF only;
- final CRLF;
- transport validation pass.

If mismatch occurs, require a first-difference report rather than silent rewriting.

## 10. Gate group G — manifest and bundle

Require:

- accepted manifest version;
- accepted writer version;
- accepted schema version;
- exact symbol and timeframe;
- exact row count;
- exact journal SHA;
- explicit fixture-owned source-data SHA;
- clear distinction from historical market-data identity;
- manifest validation pass;
- verified fixture bundle build pass;
- deterministic bundle projection SHA;
- cross-language identity where both implementations exist.

## 11. Gate group H — negative mutation parity

For every required negative mutation require:

- named mutation ID;
- Python test or fixture;
- MQL test or fixture;
- same accept/reject result;
- same reason token;
- successful-journal exclusion.

Required categories include malformed IDs, wrong projected geometry, wrong ATR-derived relationships, invalid pivot fields/chronology, structural binding mismatches, MC origin/extreme/distance mismatches, efficiency below/above range, and illegal extension data where specified by the handoff.

## 12. Gate group I — scope integrity

Require proof that recovery did not begin:

- historical SER export;
- development screening;
- validation screening;
- holdout screening;
- robustness;
- optimization;
- adapter integration;
- QuantBeast changes;
- unauthorized strategy families;
- demo/live deployment.

## 13. Evidence index

The Lead must submit one index with direct paths to:

```text
session inventory
Git guardrail capture
active-file delta inventory
runtime ticket
staging manifest
compile report
source/binary identity report
fresh runtime log range
marker index
artifact manifest
Layer-A results
Layer-B results
journal parity report
manifest/bundle report
negative mutation matrix
scope-integrity statement
residual limitations
```

The index must state which evidence is inherited and which was generated during the recovery.

## 14. Findings-first reporting

Reports must lead with confirmed findings and blockers, not narrative reassurance.

Every failed or missing gate must include:

- gate ID;
- evidence present;
- evidence missing;
- consequence;
- responsible role;
- exact next action.

## 15. Green standard

`GREEN` requires every applicable gate above.

The following do not justify green:

- most gates pass;
- code compiles;
- Python tests pass;
- files are byte-identical but not independently authored;
- the process exited;
- an EX5 exists;
- no obvious failures appear;
- the result is likely correct.

## 16. Post-verdict stop

Even after green:

- no historical screening under this pack;
- no commit or push;
- no activation of paused agents;
- no QuantBeast integration;
- wait for explicit user authorization and higher-capability diff review.
