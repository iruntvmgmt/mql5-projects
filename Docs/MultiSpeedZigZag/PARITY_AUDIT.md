# Initial Source Parity Audit

## Sources

- Pine strategy: `MS-ZZ-BO-V2-STRAT.pine`
- Pine indicator: `MS-ZZ-BO-V2.pine`
- MQL5 indicator: `MS-ZZ-BO-V2.mq5`

## Findings

| Feature | Pine strategy | Existing MQL5 indicator | Standalone suite decision |
|---|---|---|---|
| Three ATR speeds | 14×1.0, 14×2.0, 14×3.5 defaults | Same defaults | Preserved |
| Reversal source selection | Wicks, close, Renko bodies | Simplified high/low arrays | First engine uses wick extremes; source modes deferred |
| Confirmed vs forming pivots | Explicit state distinction | Historical scanning obscures decision timing | Explicit pivot and confirmation times |
| HH/HL/LH/LL labels | Supported | Pivot state is simpler | Implemented in shared types/engine |
| Trendline modes | Last two pivots or volatility slope | Last-two-pivot style visual lines | First engine uses last two confirmed pivots |
| Breakout source | Close or wick selectable | Break/freeze behavior configurable | First EA uses close-confirmed breaks |
| Multi-speed confluence | Supported | Basic confluence inputs | Implemented as strategy IDs |
| Quality score | Distance, momentum, volume, age | Not fully equivalent | Simplified fixed strategy scores; full quality parity deferred |
| Volume filter | Optional | Not represented in core excerpt | Deferred |
| Momentum filter | Optional | Not fully represented | Deferred |
| Consolidation filter | Minimum bars between pivots | Minimum bars input | Preserved |
| Entry modes | Five research modes | Indicator buffers, not full strategy router | Expanded strategy suite |
| Event deduplication | Pine strategy pyramiding=0 | Visual signal state | Stable event IDs plus consumed-event memory |

## Canonical behavior for milestone 1

- Wicks determine leg extremes and ATR reversal confirmation.
- Closed prices determine projected-line breakouts.
- Only closed bars are processed.
- A pivot becomes usable at `confirmed_time`, not `pivot_time`.
- Last-two-confirmed-pivot geometry is the only active trendline model.
- Advanced quality, volume, momentum, Renko-body, volatility-slope, retest, sweep, and compression models remain explicitly deferred.

## Important limitation

The existing MQL5 indicator's `IsZZHigh` and `IsZZLow` functions scan both sides of a historical candidate. That can be valid for retrospective plotting but is not accepted as an execution-time contract. The standalone engine instead processes bars sequentially and confirms a candidate only when the reversal threshold is observed.