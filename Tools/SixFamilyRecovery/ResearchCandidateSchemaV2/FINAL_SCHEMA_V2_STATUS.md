# ResearchCandidateSchemaV2 Status

Implementation status: `IMPLEMENTED_NOT_RUNTIME_CERTIFIED`.

The additive typed record, derived-field policy, family extension validation,
full-record MSZZSE2 ownership binding, raw broker-clock contract, canonical
RFC-4180 serializer, focused deterministic test source, and documentation are
complete. An MSZZSE2-looking string alone is insufficient; MC, BRC and TP must
bind one validated structural record and their direction, references and
structural geometry must match it. Broker timestamps are serialized as raw
integers with an explicit domain/authority and are never falsely labeled UTC.
No family generator or production path was modified.

Runtime certification is pending. The isolated Bash/Wine terminal loads both
the new focused script and the previously certified structural-event control
script but executes neither `OnStart`; neither produces fresh MQL5 log rows.
Both attempts are classified `TOOLING_NO_OP`. The available MCP discovery
surface exposes no MT5 compile or script-runner tool, so there is no independent
MCP route in this session.

Do not treat this status as a test pass. Full regression and fresh P4 parity
remain mandatory before this phase is certified or any family adapter consumes
the schema.

All six families remain unauthorized. D034 and D035 remain blocked.
