# ResearchCandidateSchemaV2 Status

Implementation status: `RUNTIME_CERTIFIED`.

The additive typed record, derived-field policy, family extension validation,
full-record MSZZSE2 ownership binding, raw broker-clock contract, canonical
RFC-4180 serializer, focused deterministic test source, and documentation are
complete. An MSZZSE2-looking string alone is insufficient; MC, BRC and TP must
bind one validated structural record and their direction, references and
structural geometry must match it. Broker timestamps are serialized as raw
integers with an explicit domain/authority and are never falsely labeled UTC.
No family generator or production path was modified.

The isolated terminal runner was recovered after the demo account was
authenticated. The focused suite then exposed one late-failure defect:
`ZeroMemory()` did not clear reused string members. Explicit common, extension,
and bound-record string clearing now enforces the blank-invalid contract.

Fresh certification evidence now proves:

- EA and all 34 test sources compile with 0 errors and 0 warnings;
- the focused Schema V2 suite passes with zero failures;
- the structural-event control passes with 217 certified events, zero
  engine/replay mismatches, and zero duplicate IDs;
- the complete regression passes 32/32 with zero failures and zero tooling
  no-ops;
- P4 is byte-identical at 330 trades, `+47.6083336413R`, PF
  `1.2472234619`, and SHA-256
  `9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.

All six families remain unauthorized. D034 and D035 remain blocked.

The exact next authorized phase is the family-neutral journal manifest and
strict cross-language parser parity implementation.
