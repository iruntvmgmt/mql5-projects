# QuantBeast entry preflight controls evidence — 2026-07-16

## Defect

`InpMaxPriceJumpPoints` and `InpBarWarmup` were declared configuration inputs but did not affect entry behavior.

## Severity

Medium safety/configuration defect. Operators could believe a price-jump filter and startup warmup were active when they were not.

## Fix

Added `QBEntryPreflightControlsAllow()` and wired it into `OnTick()` after quote/data validation and before feature calculation/strategy evaluation. Entries are now blocked when:

- the data-quality gate fails;
- primary timeframe bars are below `InpBarWarmup`;
- the current tick exceeds `InpMaxPriceJumpPoints`.

The change is conservative: it can only block entries and does not increase signal frequency.

## Validation

- Compile: `0 errors, 0 warnings` at `2026-07-16 10:31:51`
- Shadow regression: `44 passed, 0 failed`
- Model: generated ticks, broker-free Shadow only
- Ticks/bars: `22080` ticks, `1104` bars
- Final balance: `10000.00 USD`
- Tester result: `OnTester result 0`

## Hashes

- Source SHA-256: `51fa5531bde94f6b2f47af2d0ea5c4086c10bdae3cf08727f84bbab9371413ef`
- EX5 SHA-256: `ea722ed75340747dfd5487fa4ece3c37d760370ab84b8e3503c77ddba0e9dfef`

No broker orders were transmitted.
