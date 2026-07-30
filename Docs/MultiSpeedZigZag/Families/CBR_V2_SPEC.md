# Compression Breakout v2 — Prospective Specification

Status: `SPECIFICATION_GAP`; implementation prohibited.

## Hypothesis and opportunity

A completed compression episode aligned with **medium** structure breaks its prior boundary without excessive extension or major opposing obstruction. One event begins when compression maturity is first satisfied and ends on breakout, loss of compression, obstruction, expiry, or reset. Continued compression belongs to the same episode.

## Window and sequence

The compression measurement window must contain only bars preceding the trigger bar. Short/long ATR definitions, range width and duration are frozen before arming. Slow structure is metadata unless an explicitly reviewed alternate variant is created; it cannot satisfy medium alignment.

| State | Guard | Next | Emit | Same-call re-arm |
|---|---|---|---|---|
| WAIT | compression first matures | ARMED | no | no |
| ARMED | remains compressed | ARMED | no | no |
| ARMED | medium-aligned valid breakout, extension/obstruction/cost pass | EMITTED | once | no |
| ARMED | decompression/opposition/expiry | WAIT_RESET | no | no |
| WAIT_RESET | noncompressed interval then new episode | WAIT | no | no |

## Gaps and identity

Short/long ATR, compression ratio, width, maturity, maximum extension, opposing structure and reset are unresolved. Spread/risk and geometry rejection are mandatory but unfrozen.

```text
origin_id   = CBR2|symbol|tf|compression_start|window_hash
sequence_id = origin_id|ARM|maturity_time
event_id    = sequence_id|BREAK|trigger_time|direction
```

Metadata types every window endpoint/hash, ATR/range statistic, medium event/alignment, boundaries, extension, obstruction and geometry. Simulator/production must use the same bar window, next-entry, occupancy, exits and costs. V2 production allocation is deferred.

