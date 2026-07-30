# D033 SSR integration-defect root cause

Audited baseline: `b18ca13fbf1dd96945d6e60d6b05fc04b6e649c4`.

The production SSR strategy created a timestamped `sequence_id` for every
armed sweep but emitted the daily Asian reference (`ASIA_LOW|YYYYMMDD` or
`ASIA_HIGH|YYYYMMDD`) as the candidate `origin_id`. The shared cluster engine
intentionally prefers a nonempty `origin_id`, so distinct same-direction
re-arms on one day collapsed into one persistent cluster.

The repair is local to the SSR production adapter: candidate `origin_id` now
uses the existing timestamped `sequence_id`, while `event_id` remains
`sequence_id + "|FINAL"`. The shared cluster engine and frozen signal geometry
are unchanged.

Separately, production portfolio routing omitted strategy 1090 from
`ConsumedKey()`. Adding it repairs strategy-qualified persistence and the
portfolio-routing regression. That omission did not cause the standalone
2,249 duplicate-cluster rejections because standalone mode persisted the raw
selected cluster ID through `EventConsumed()`.
