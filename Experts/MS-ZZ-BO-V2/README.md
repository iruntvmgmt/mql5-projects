# MS-ZZ-BO-V2 EA scaffold

This folder now contains an EA scaffold built around the mature `MS-ZZ-BO-V2` indicator.

## Source chosen

Use the `TRADINGVIEW_MCP` copy of `MS-ZZ-BO-V2.mq5` as the authoritative source. It is the more mature version.

## Signal buffer mapping

- Buffer 6: fast break buy
- Buffer 7: fast break sell
- Buffer 8: med break buy
- Buffer 9: med break sell

## EA behavior

- Default signal mode: medium signals only
- One position at a time
- Session filter on by default
- Spread filter on by default
- ATR-based SL/TP sizing
- Breakeven and trailing stop enabled by default

## Notes

- The EA reads the indicator with `iCustom` from:
  `Tradingview_Indicators\\MULTI_SPEED_ZIGZAG\\MS-ZZ-BO-V2`
- If the indicator is later changed to expose explicit parameters, the EA will need to pass them into `iCustom`.
- The source is in place; next step is a clean MetaEditor compile and then a short tester pass.
