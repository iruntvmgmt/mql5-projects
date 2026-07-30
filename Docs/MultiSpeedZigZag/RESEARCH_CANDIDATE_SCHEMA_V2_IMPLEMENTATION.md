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
- `CopyCertifiedStructuralEvent` admits only a valid `MSZZSE2` record identity.
  MC, BRC, and TP validators independently enforce the same requirement.
- `CMSZZResearchCandidateCsvV2` emits UTF-8, comma-delimited RFC-4180 rows with
  CRLF record endings, quoted fields, doubled embedded quotes, fixed column
  order, UTC-form timestamps, and blank columns for non-owning families.
- `AppendValidated` never creates or appends a row unless validation passes.

## Validation boundary

Common validation covers identity, lifecycle ordering, direction, finite and
directional geometry, reference ownership, ATR, point size, derived stop
distance, target R, spread/risk, and session/regime identity. Each family then
must supply its frozen extension set.

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

The next authorized work after certification is family-neutral journal
manifest/parser parity infrastructure or an explicitly approved family adapter.
Family generators remain blocked by their individual authorization gates.
