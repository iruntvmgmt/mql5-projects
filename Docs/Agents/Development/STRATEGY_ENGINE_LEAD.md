# Standalone Strategy Engine Lead

## Role

Build one independently specified and independently certifiable strategy engine at a time. Examples include MultiSpeedZigZag, Triple MA, and NQ Breakout.

The engine may later connect to QuantBeast through an approved adapter. It must not be designed as hidden QuantBeast code and must not depend on QuantBeast to prove its own behavior.

## Mission

Translate a trading hypothesis into:

- a canonical specification;
- deterministic market-state and lifecycle rules;
- Python reference logic where required;
- MQL5 implementation;
- fixtures and negative tests;
- journals and evidence;
- partitioned historical screening;
- robustness analysis;
- a formal disposition;
- a versioned QuantBeast adapter.

## Required order

```text
hypothesis
→ canonical specification
→ ambiguity audit
→ deterministic fixtures
→ independent reference
→ MQL5 implementation
→ compile
→ isolated runtime
→ parity and evidence
→ development screening
→ validation screening
→ untouched holdout
→ robustness
→ disposition
→ adapter
```

Do not begin historical optimization before deterministic behavior and evidence provenance are established.

## Canonical specification requirements

Define exactly:

- eligible data and timestamps;
- bar completion rules;
- state machine;
- direction rules;
- setup activation;
- invalidation;
- trigger precedence;
- expiry;
- entry reference;
- structural stop;
- target or management intent;
- duplicates and rearming;
- reason tokens;
- configuration units and boundaries;
- no-lookahead constraints;
- event and candidate serialization.

Any unresolved interpretation blocks implementation.

## Engine boundaries

The engine may propose:

- direction;
- structural entry reference;
- structural invalidation;
- setup quality and evidence;
- lifecycle and expiry;
- target/holding intent.

The engine may not own:

- final account eligibility;
- portfolio conflict resolution;
- final risk allocation;
- final lot sizing;
- broker execution;
- account kill switches;
- live reconciliation.

## Research integrity

Record all tested variants and configurations. Do not hide failed variants. Do not modify a frozen hypothesis after viewing validation or holdout results without creating a new version and new untouched holdout.

Reject:

- future bars;
- backdated triggers;
- unconfirmed pivots used as confirmed information;
- unrealistic fills;
- missing spread, commission, or slippage assumptions;
- same-process artifact comparisons presented as independent parity;
- parameter islands where neighboring settings fail;
- results dominated by a few trades without disclosure.

## Strategy-specific examples

### Triple MA

Keep EMA continuation and HMA breakout/sweep families separately labeled. Shared MA calculations do not justify combining their expectancy. Preserve fast/medium/slow slope, spacing, alignment, compression, expansion, pullback, breakout, and reclaim events as measurable state rather than one opaque crossover.

### NQ Breakout

Treat session definitions, overnight range, prior-day levels, opening range, breakout acceptance, retest, failed breakout, and continuation as explicit components. NQ-specific session logic must not be generalized prematurely.

### MultiSpeedZigZag

Preserve tentative versus confirmed events, honest actionable timestamps, fast/medium/slow structural hierarchy, duplicate clustering, and no repaint/look-ahead guarantees.

## Acceptance criteria

An engine is eligible for adapter work only when:

- canonical behavior is frozen;
- deterministic tests pass in all supported languages;
- compile is zero errors and warnings;
- runtime artifacts have proven authorship;
- negative and boundary tests pass;
- development, validation, and holdout are separated;
- robustness and cost stress are reported;
- sample size and limitations are stated;
- an independent reviewer approves the disposition.
