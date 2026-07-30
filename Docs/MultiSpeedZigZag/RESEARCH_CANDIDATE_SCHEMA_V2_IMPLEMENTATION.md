# Research Candidate Schema v2 Implementation

## Scope

This phase implements the shared evidence container and journal boundary. It
does not modify any family generator, strategy threshold, state machine,
screening result, simulator, production adapter, or broker path.

The legacy `MSZZResearchCandidate` and semicolon journal remain unchanged so
historical D031/D032 evidence is reproducible. They are not silently migrated
or treated as v2.

## Components

- `MSZZResearchCandidateV2` contains all common typed fields and six disjoint
  typed family extension records.
- `CMSZZResearchCandidateSchemaV2` initializes, derives, and validates records.
  Validation is fail-closed and sets `valid=true` only after common and
  family-specific evidence passes.
- `BindCertifiedStructuralEvent` validates and copies the complete immutable
  `MSZZStructuralEventRecord`. MC, BRC, and TP validators bind their direction,
  reference, pivots, projected level and impulse fields back to that copy.
- `CMSZZResearchCandidateCsvV2` emits UTF-8, comma-delimited RFC-4180 rows with
  CRLF record endings, quoted fields, doubled embedded quotes, fixed column
  order, raw integer time fields with explicit clock authority, full structural
  ownership evidence, and blank columns for non-owning families.
- `AppendValidated` never creates or appends a row unless validation passes.

## Validation boundary

Common validation covers identity, lifecycle ordering, direction, finite and
directional geometry, reference ownership, ATR, point size, derived stop
distance, target R, spread/risk, and session/regime identity. Each family then
must supply its frozen extension set.

Validation failure blanks the consumable record and retains only the schema
identifier and failure reason. This prevents callers from accidentally
serializing or consuming a populated-but-invalid attempt.

Runtime certification exposed that `ZeroMemory()` alone does not release
MQL5 string members when a candidate object is reused. The schema now clears
every common, extension, and bound-record string explicitly before applying
the invalid-record contract. A late lifecycle failure is covered by a runtime
test proving that no consumable identity or price survives.

The current writer accepts only `BROKER_SERVER_RAW` with authority
`MSZZ_TIME_RAW_BROKER_V1`. It does not claim UTC. `UTC_CONVERTED` remains
fail-closed until the committed `MSZZ_TIME_AUTH_C1` conversion service exists.

This infrastructure cannot by itself certify a family. Future adapters must
prove their state-machine, reset, clock/value, and event-ownership contracts
before constructing a v2 record. No family is authorized by this change.

## Journal policy

The row serializer is deterministic, but dataset certification still requires
an offline or session-level manifest containing row count, SHA-256, writer
version, symbol, timeframe, and data hash. A consumer must fail a study on
malformed CSV, unsupported schema, duplicate event IDs, validation failure, or
manifest mismatch. No heuristic repair or v1 string reconstruction is allowed.

## Authorization

Schema v2 was runtime-certified on 2026-07-30 in the isolated MT5 instance:
the focused suite and structural-event control both passed with fresh raw
logs, all 32 regression suites passed, and P4 reproduced 330 trades,
`+47.6083336413R`, PF `1.2472234619`, and canonical journal SHA-256
`9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.

The next authorized work is the family-neutral journal manifest and strict
MQL5/Python parser parity infrastructure. Family generators remain blocked by
their individual authorization gates.
