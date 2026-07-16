# TradingView Indicator Conversion Audit

Last updated: 2026-07-10 (Phase 1 — GT VP core feature parity)

## Latest Update: GT Volume Profile v3.0

`GT_VP_v9.9.6_STRAT/GT_Volume_Profile.mq5` expanded from 668 → 1,154 lines (v2.1 → v3.0).

### Phase 1 — Core VP Enhancements (completed 2026-07-10)

| Feature | Status |
| --- | --- |
| Volume Profile (VAH/VAL/POC) | ✅ Existing |
| Volume Histogram (heatmap) | ✅ Existing |
| LVN Markers | ✅ Existing |
| FVG Detection | ✅ Enhanced (ATR-filtered) |
| Developing VP (VWAP + ATR) | ✅ Existing |
| Dashboard | ✅ Expanded (flow, CVD, VA state, prior VA, binning) |
| ATR-Based Dynamic Binning | ✅ New — TF-aware granularity scaling |
| Session Management (Daily/Weekly/Monthly/Tokyo/London/NY) | ✅ New |
| Ghost Trails (POC stepline) | ✅ New — directional coloring |
| VA Cloud Tiles | ✅ New — adaptive ring buffer, delta-tinted, price-exit colors, reclaim/rejection borders |
| VA Breathing Metrics | ✅ New — Expanding/Contracting/Stable |
| Prior Session VA Reference | ✅ New — dotted VAH/VAL/POC from prior session |
| Buy/Sell Volume Classification | ✅ New — per-bin buy/sell volume |
| CVD / Flow Pressure | ✅ New — cumulative delta + flow direction |
| Session Box | ✅ New — boundary rectangle + label |
| Profile Shape Analysis | ✅ Enhanced (P/b/D-Shape) |

### Remaining for Phase 2-6
- Phase 2: Order flow signals (absorption, iceberg, exhaustion, divergence, SMD)
- Phase 3: Market structure (ZigZag, HH/HL/LH/LL, BOS/CHoCH, sweeps)
- Phase 4: Advanced FVG (mitigation scanning, IFVG polarity flip, split-box rendering)
- Phase 5: Stacked imbalances, fast lanes, bubbles, performance monitoring
- Phase 6: Triple MA system integration

## Fixed In This Pass

| File | Fix |
| --- | --- |
| `Tripple_MA/Elite_Triple_MA_Suite.mq5` | Reworked `DRAW_COLOR_LINE` buffer layout so each MA data buffer is immediately followed by its color-index buffer. Reduced plot count from 10 to 7 because color-index buffers are not standalone plots. |
| `SQUEEZE_MOMENTUM_pro/SQZ_PRO.mq5` | Reworked `DRAW_COLOR_HISTOGRAM` buffer layout for momentum and secondary momentum. Reduced plot count from 10 to 8 and fixed the empty-value loop to match the new plot count. |
| `CRSI/CRSI_Prestige_Strategy.mq5` | Fixed declared buffer/plot count from 22 to 21 to match the actual buffers and plot definitions. |
| `NQ_ORB/NQ_Opening_Range_Retest.mq5` | Removed invalid VWAP indicator handle creation. The EA now uses its `CalcVWAP()` function directly for VWAP filtering. |
| `SMC/Smart_Money_Concepts_LuxAlgo.mq5` | Changed hidden plotted OB buffers from calculation buffers to data buffers so the declared `DRAW_NONE` plots have readable data buffers. |
| `GT_VP_v9.9.6_STRAT/GT_Volume_Profile.mq5` | Changed hidden plotted FVG buffer from calculation buffer to data buffer so the declared `DRAW_NONE` plot has a readable data buffer. |
| `SQUEEZE_MOMENTUM_pro/SQZ_PRO.mq5` | Fixed helper signatures so MetaEditor can pass `const` series arrays into math helpers. |
| `PIVOT_G_TIER/PVTG-TIER.mq5` | Fixed helper signatures so MetaEditor can pass `const` series arrays into MA helpers. |
| `CRSI/CRSI_Prestige_Strategy.mq5` | Fixed helper signatures and removed a stray self-referential `upRMA` line that blocked compilation. |

## Current Converted Files

| File | Type | Status | Notes |
| --- | --- | --- | --- |
| `Tripple_MA/Elite_Triple_MA_Suite.mq5` | Indicator | Compiles cleanly | `.ex5` generated. Color plot layout fixed. Buffer indices changed because MT5 requires paired color-index buffers. |
| `WAVETREND/WaveTrend_MAX.mq5` | Indicator | Compiles cleanly | `.ex5` generated. |
| `SQUEEZE_MOMENTUM_pro/SQZ_PRO.mq5` | Indicator | Compiles cleanly | `.ex5` generated. Color histogram layout fixed. Buffer indices changed because MT5 requires paired color-index buffers. |
| `PIVOT_G_TIER/PVTG-TIER.mq5` | Indicator | Compiles cleanly | `.ex5` generated. |
| `CRSI/CRSI_Prestige_Strategy.mq5` | Indicator | Compiles cleanly | `.ex5` generated. Count mismatch fixed. |
| `NQ_ORB/NQ_Opening_Range_Retest.mq5` | EA | Compiles with warnings | `.ex5` generated. This is an EA, not an `iCustom` indicator. VWAP placeholder handle removed. Remaining warnings are about a `datetime` to `int` conversion and unchecked `OrderSend()` return values. |
| `HURST_SUITE/Hurst_Cycle_Oscillator.mq5` | Indicator | Compiles cleanly | `.ex5` generated. Only oscillator conversion is present, not full channel indicator. |
| `MULTI_SPEED_ZIGZAG/MS-ZZ-BO-V2.mq5` | Indicator | Compiles cleanly | `.ex5` generated. Strategy/EA variant is separate and not converted here. |
| `PATTERNFORGE/PATTERNFORGE_Pro.mq5` | Indicator | Partial parity | Much simpler than the Pine source. Treat as a scaffold/simplified conversion until feature parity is checked. |
| `PATTERNFORGE/PATTERNFORGE_Pro.mq5` | Indicator | Compiles cleanly, partial parity | `.ex5` generated. Much simpler than the Pine source. Treat as a scaffold/simplified conversion until feature parity is checked. |
| `SMC/Smart_Money_Concepts_LuxAlgo.mq5` | Indicator | Compiles cleanly, partial parity | `.ex5` generated. Simplified indicator conversion, not the full strategy engine from the Pine source. Hidden plotted buffers fixed. |
| `GT_VP_v9.9.6_STRAT/GT_Volume_Profile.mq5` | Indicator | Stable v7.1 | v7.1 (~2,600 lines). Full port with audit fixes: bounded first-load backfill (2k bars), clamped fixed-bin input (10-200), FVG list compaction, full ZigZag session reset, renderer validity guards, historical FVG object churn eliminated, DevVP backfill gated. |

## MTApi Buffer Notes

These buffers are the ones to prefer for `CopyBuffer()` after compilation. Color-index and calculation buffers are omitted unless useful.

### Elite Triple MA

| Buffer | Meaning |
| --- | --- |
| 0 | Fast MA |
| 2 | Mid MA |
| 4 | Slow MA |
| 6 | ATR upper cloud |
| 7 | ATR lower cloud |
| 8 | Buy signal |
| 9 | Sell signal |

### SQZ PRO

| Buffer | Meaning |
| --- | --- |
| 0 | Momentum |
| 2 | Zero line |
| 3 | Secondary momentum |
| 5 | Compression pressure |
| 6 | Quality score |
| 7 | Squeeze state |
| 8 | Long entry |
| 9 | Short entry |

### CRSI Prestige

| Buffer | Meaning |
| --- | --- |
| 0 | CRSI |
| 1 | Smoothed CRSI |
| 2 | Dynamic low |
| 3 | Dynamic high |
| 12 | BB upper |
| 13 | BB middle |
| 14 | BB lower |
| 15 | Buy signal |
| 16 | Sell signal |
| 17 | SQZ momentum |
| 18 | SQZ on |
| 20 | Normalized price |

## Next Validation Steps

1. Load each indicator/EA on a chart and confirm it initializes visually.
2. For indicators, call `iCustom()` and read the documented buffers with `CopyBuffer()`.
3. Fix the remaining `NQ ORB` warnings if you want the EA tightened before live use.
4. For partial parity files, decide whether to expand them toward full Pine behavior or keep them as simplified MT5 versions.
