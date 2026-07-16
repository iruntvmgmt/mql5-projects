//+------------------------------------------------------------------+
//|                                                PIVOT G-TIER.mq5  |
//|                    Ported from Pine Script v5 → MQL5 (Full)       |
//|                    Original: PVTG-TEIR.pine                      |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: PIVOT G-TIER ::"
#property description "Advanced pivot detection with 11 MA types, S/R levels,"
#property description "HH/HL/LH/LL markers, fractal break signals, chaos channel."

#property indicator_chart_window
#property indicator_buffers 14
#property indicator_plots   14

// ── Plot 0-1: Pivot High/Low markers ────────────────────────────────────────
#property indicator_label1  "Pivot High"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGreen
#property indicator_width1  2

#property indicator_label2  "Pivot Low"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMaroon
#property indicator_width2  2

// ── Plot 2-3: S/R Level Extensions ──────────────────────────────────────────
#property indicator_label3  "Resistance Level"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMaroon
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

#property indicator_label4  "Support Level"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGreen
#property indicator_width4  1
#property indicator_style4  STYLE_DOT

// ── Plot 4-7: HH/HL/LH/LL markers ──────────────────────────────────────────
#property indicator_label5  "Higher High"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrGreen

#property indicator_label6  "Lower High"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrMaroon

#property indicator_label7  "Higher Low"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrGreen

#property indicator_label8  "Lower Low"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrMaroon

// ── Plot 8-9: Fractal Break signals ─────────────────────────────────────────
#property indicator_label9  "Fractal Break Buy"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrLime
#property indicator_width9  2

#property indicator_label10 "Fractal Break Sell"
#property indicator_type10  DRAW_ARROW
#property indicator_color10 clrRed
#property indicator_width10 2

// ── Plot 10-11: MA lines ────────────────────────────────────────────────────
#property indicator_label11 "Fast MA"
#property indicator_type11  DRAW_LINE
#property indicator_color11 clrLime
#property indicator_width11 2
#property indicator_style11 STYLE_DOT

#property indicator_label12 "Slow MA"
#property indicator_type12  DRAW_LINE
#property indicator_color12 clrGray
#property indicator_width12 2
#property indicator_style12 STYLE_DOT

// ── Plot 12-13: Chaos Channel ───────────────────────────────────────────────
#property indicator_label13 "Chaos Top"
#property indicator_type13  DRAW_LINE
#property indicator_color13 clrGreen
#property indicator_width13 1

#property indicator_label14 "Chaos Bottom"
#property indicator_type14  DRAW_LINE
#property indicator_color14 clrMaroon
#property indicator_width14 1

// ── MA Type Enum ────────────────────────────────────────────────────────────
enum ENUM_PVTG_MA_TYPE
{
   PVTG_MA_SMA,            // SMA
   PVTG_MA_EMA,            // EMA
   PVTG_MA_WMA,            // WMA
   PVTG_MA_VWMA,           // VWMA
   PVTG_MA_SMOOTH,         // Smooth SMA
   PVTG_MA_DEMA,           // DEMA (Double EMA)
   PVTG_MA_TEMA,           // TEMA (Triple EMA)
   PVTG_MA_HULL,           // Hull MA
   PVTG_MA_ZLEMA,          // ZeroLag EMA
   PVTG_MA_TRIANGULAR,     // Triangular MA
   PVTG_MA_SUPERSMOOTH     // SuperSmooth MA (Ehlers)
};

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Pivot Settings ═══"
input bool                         InpShowPivots   = true;              // Show Pivot Points
input bool                         InpAutoStrength = false;             // Use Auto Strength Pivots
input int                          InpLeft         = 5;                 // Pivot Left Bars (>=1)
input int                          InpRight        = 5;                 // Pivot Right Bars (>=1)
input bool                         InpRenko        = false;             // Renko Style (open/close as high/low)
input bool                         InpIdeal        = false;             // Show Only Ideal Pivots
input int                          InpShunt        = 1;                 // Wait bars (0=immediate, 1=wait close)
input bool                         InpClrBar       = false;             // Highlight Pivot Bars (via arrow)

input group                        "═══ S/R Level Extensions ═══"
input bool                         InpShowLevels   = true;              // Show S/R Level Extensions
input bool                         InpShowChannel  = false;             // Show as Fractal Chaos Channel
input int                          InpMaxLevelLen  = 0;                 // Max Level Length (0=unlimited)

input group                        "═══ HH/HL/LH/LL ═══"
input bool                         InpShowHHLL     = false;             // Show HH/LL/LH/HL Markers
input bool                         InpSwing3Levels = false;             // Filter to 3rd Level Swings

input group                        "═══ Fractal Break Alerts ═══"
input bool                         InpShowFB       = false;             // Show Fractal Break Signals
input bool                         InpFilterFB     = false;             // Apply MA Filter to Break Signals
input bool                         InpShowAlerts   = true;              // Enable Popup Alerts

input group                        "═══ MA Filter ═══"
input bool                         InpUseMAFilter  = false;             // Use MA Filter on Pivots
input ENUM_PVTG_MA_TYPE            InpFastMAType   = PVTG_MA_EMA;       // Fast MA Type
input int                          InpFastMALen    = 21;                // Fast MA Length
input ENUM_APPLIED_PRICE           InpFastMASrc    = PRICE_CLOSE;       // Fast MA Source
input ENUM_PVTG_MA_TYPE            InpSlowMAType   = PVTG_MA_EMA;       // Slow MA Type
input int                          InpSlowMALen    = 55;                // Slow MA Length
input ENUM_APPLIED_PRICE           InpSlowMASrc    = PRICE_CLOSE;       // Slow MA Source
input bool                         InpShowMAs      = false;             // Show MA Lines

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_pvthi[];       // 0  Pivot High markers
double g_pvtlo[];       // 1  Pivot Low markers
double g_resLevel[];    // 2  S/R resistance level extension
double g_supLevel[];    // 3  S/R support level extension
double g_hh[];          // 4  Higher High markers
double g_lh[];          // 5  Lower High markers
double g_hl[];          // 6  Higher Low markers
double g_ll[];          // 7  Lower Low markers
double g_fbBuy[];       // 8  Fractal Break Buy
double g_fbSell[];      // 9  Fractal Break Sell
double g_fastMA[];      // 10 Fast MA
double g_slowMA[];      // 11 Slow MA
double g_chaosTop[];    // 12 Chaos Channel Top
double g_chaosBot[];    // 13 Chaos Channel Bottom

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix = "PVTG_";
int    g_totalBars;
bool   g_prevBuy, g_prevSell;

//+------------------------------------------------------------------+
//| MA: SMA                                                           |
//+------------------------------------------------------------------+
double CalcSMA(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double sum = 0;
   for(int i = 0; i < period; i++) sum += arr[shift + i];
   return sum / period;
}

//+------------------------------------------------------------------+
//| MA: EMA                                                           |
//+------------------------------------------------------------------+
double CalcEMA(const double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   double alpha = 2.0 / (period + 1.0);
   double ema = CalcSMA(arr, period, shift);
   for(int i = shift + period; i < size; i++)
      ema = arr[i] * alpha + ema * (1.0 - alpha);
   return ema;
}

//+------------------------------------------------------------------+
//| MA: WMA                                                           |
//+------------------------------------------------------------------+
double CalcWMA(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double sum = 0, wSum = 0;
   for(int i = 0, w = 1; i < period; i++, w++)
   { sum += arr[shift + i] * w; wSum += w; }
   return (wSum > 0) ? sum / wSum : 0;
}

//+------------------------------------------------------------------+
//| MA: VWMA                                                          |
//+------------------------------------------------------------------+
double CalcVWMA(const double &price[], const double &vol[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(price)) return 0;
   double sumPV = 0, sumV = 0;
   for(int i = 0; i < period; i++)
   {
      double v = (shift + i < ArraySize(vol)) ? vol[shift + i] : 1.0;
      if(v <= 0) v = 1.0;
      sumPV += price[shift + i] * v; sumV += v;
   }
   return (sumV > 0) ? sumPV / sumV : 0;
}

//+------------------------------------------------------------------+
//| MA: Smooth SMA (recursive)                                        |
//+------------------------------------------------------------------+
double CalcSmoothSMA(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   double smaInit = CalcSMA(arr, period, shift);
   double result = smaInit;
   for(int i = shift + period; i < size; i++)
      result = (result * (period - 1) + arr[i]) / period;
   return result;
}

//+------------------------------------------------------------------+
//| MA: DEMA (Double EMA)                                             |
//+------------------------------------------------------------------+
double CalcDEMA(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   
   double ema1[], ema2[];
   ArrayResize(ema1, size);
   ArrayResize(ema2, size);
   
   for(int i = 0; i + period <= size; i++)
      ema1[i] = CalcEMA(arr, period, i);
   for(int i = 0; i + period <= size; i++)
      ema2[i] = CalcEMA(ema1, period, i);
   
   double v = CalcEMA(arr, period, shift);
   double v2 = CalcEMA(ema1, period, shift);
   return 2.0 * v - v2;
}

//+------------------------------------------------------------------+
//| MA: TEMA (Triple EMA)                                             |
//+------------------------------------------------------------------+
double CalcTEMA(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   
   double ema1[], ema2[], ema3[];
   ArrayResize(ema1, size);
   ArrayResize(ema2, size);
   ArrayResize(ema3, size);
   
   for(int i = 0; i + period <= size; i++)
      ema1[i] = CalcEMA(arr, period, i);
   for(int i = 0; i + period <= size; i++)
      ema2[i] = CalcEMA(ema1, period, i);
   for(int i = 0; i + period <= size; i++)
      ema3[i] = CalcEMA(ema2, period, i);
   
   double e1 = CalcEMA(arr, period, shift);
   double e2 = CalcEMA(ema1, period, shift);
   double e3 = CalcEMA(ema2, period, shift);
   return 3.0 * (e1 - e2) + e3;
}

//+------------------------------------------------------------------+
//| MA: HULL                                                          |
//+------------------------------------------------------------------+
double CalcHullMA(double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   int half = (int)MathFloor(period / 2.0);
   int root = (int)MathFloor(MathSqrt(period));
   if(half < 2) half = 2; if(root < 1) root = 1;
   
   int size = ArraySize(arr);
   if(shift + period > size) return 0;
   
   double wmaHalf[], wmaFull[], diff[];
   int need = shift + root + 1;
   ArrayResize(wmaHalf, need); ArrayResize(wmaFull, need); ArrayResize(diff, need);
   
   for(int i = 0; i < need && i + half <= size; i++)
      wmaHalf[i] = CalcWMA(arr, half, i);
   for(int i = 0; i < need && i + period <= size; i++)
      wmaFull[i] = CalcWMA(arr, period, i);
   for(int i = 0; i < need; i++)
      diff[i] = 2.0 * wmaHalf[i] - wmaFull[i];
   
   return CalcWMA(diff, root, shift);
}

//+------------------------------------------------------------------+
//| MA: ZeroLag EMA                                                   |
//+------------------------------------------------------------------+
double CalcZLEMA(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   int lag = (period - 1) / 2;
   if(shift + period + lag > size) return 0;
   
   double zlemaArr[];
   ArrayResize(zlemaArr, size);
   for(int i = 0; i + lag < size; i++)
      zlemaArr[i] = 2.0 * arr[i] - arr[i + lag];
   
   return CalcEMA(zlemaArr, period, shift);
}

//+------------------------------------------------------------------+
//| MA: Triangular (SMA of SMA)                                       |
//+------------------------------------------------------------------+
double CalcTriangularMA(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period * 2 > size) return 0;
   
   double sma1[];
   ArrayResize(sma1, size);
   for(int i = 0; i + period <= size; i++)
      sma1[i] = CalcSMA(arr, period, i);
   
   return CalcSMA(sma1, period, shift);
}

//+------------------------------------------------------------------+
//| MA: SuperSmooth (Ehlers)                                          |
//+------------------------------------------------------------------+
double CalcSuperSmooth(double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 2) return 0;
   
   double a1 = MathExp(-1.414 * M_PI / period);
   double b1 = 2.0 * a1 * MathCos(1.414 * M_PI / period);
   double c2 = b1;
   double c3 = -a1 * a1;
   double c1 = 1.0 - c2 - c3;
   
   // Calculate recursively forward from oldest to newest
   double result = 0;
   for(int i = size - 1; i >= shift; i--)
   {
      double src = arr[i];
      double srcPrev = (i + 1 < size) ? arr[i + 1] : src;
      result = c1 * (src + srcPrev) / 2.0 + c2 * result + c3 * (i + 2 < size ? result : 0);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| MA Router                                                        |
//+------------------------------------------------------------------+
double GetMA(ENUM_PVTG_MA_TYPE t, double &price[], double &vol[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   switch(t)
   {
      case PVTG_MA_SMA:         return CalcSMA(price, period, shift);
      case PVTG_MA_EMA:         return CalcEMA(price, period, shift);
      case PVTG_MA_WMA:         return CalcWMA(price, period, shift);
      case PVTG_MA_VWMA:        return CalcVWMA(price, vol, period, shift);
      case PVTG_MA_SMOOTH:      return CalcSmoothSMA(price, period, shift);
      case PVTG_MA_DEMA:        return CalcDEMA(price, period, shift);
      case PVTG_MA_TEMA:        return CalcTEMA(price, period, shift);
      case PVTG_MA_HULL:        return CalcHullMA(price, period, shift);
      case PVTG_MA_ZLEMA:       return CalcZLEMA(price, period, shift);
      case PVTG_MA_TRIANGULAR:  return CalcTriangularMA(price, period, shift);
      case PVTG_MA_SUPERSMOOTH: return CalcSuperSmooth(price, period, shift);
      default:                  return CalcEMA(price, period, shift);
   }
}

//+------------------------------------------------------------------+
//| Pivot High detection (standard - allows equal on left)            |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   
   double val = arr[idx];
   // Check left side (allow equal)
   for(int i = idx - left; i < idx; i++)
      if(arr[i] > val) return false;
   // Check right side (strictly greater)
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] >= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Pivot Low detection (standard - allows equal on left)             |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   
   double val = arr[idx];
   for(int i = idx - left; i < idx; i++)
      if(arr[i] < val) return false;
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] <= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Ideal Pivot High (strict - must be true highest)                  |
//+------------------------------------------------------------------+
bool IsIdealPivotHigh(double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   
   double val = arr[idx];
   for(int i = idx - left; i <= idx + right; i++)
      if(i != idx && arr[i] >= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Ideal Pivot Low (strict - must be true lowest)                    |
//+------------------------------------------------------------------+
bool IsIdealPivotLow(double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   
   double val = arr[idx];
   for(int i = idx - left; i <= idx + right; i++)
      if(i != idx && arr[i] <= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| ValueWhen: get value at nth non-NA occurrence of condition        |
//+------------------------------------------------------------------+
double ValueWhen(double &cond[], double &vals[], int occurrence, int fromIdx)
{
   int count = 0;
   for(int i = fromIdx; i >= 0; i--)
   {
      if(cond[i] != EMPTY_VALUE && cond[i] != 0)
      {
         if(count == occurrence)
            return vals[i];
         count++;
      }
   }
   return EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,  g_pvthi,     INDICATOR_DATA);
   SetIndexBuffer(1,  g_pvtlo,     INDICATOR_DATA);
   SetIndexBuffer(2,  g_resLevel,  INDICATOR_DATA);
   SetIndexBuffer(3,  g_supLevel,  INDICATOR_DATA);
   SetIndexBuffer(4,  g_hh,        INDICATOR_DATA);
   SetIndexBuffer(5,  g_lh,        INDICATOR_DATA);
   SetIndexBuffer(6,  g_hl,        INDICATOR_DATA);
   SetIndexBuffer(7,  g_ll,        INDICATOR_DATA);
   SetIndexBuffer(8,  g_fbBuy,     INDICATOR_DATA);
   SetIndexBuffer(9,  g_fbSell,    INDICATOR_DATA);
   SetIndexBuffer(10, g_fastMA,    INDICATOR_DATA);
   SetIndexBuffer(11, g_slowMA,    INDICATOR_DATA);
   SetIndexBuffer(12, g_chaosTop,  INDICATOR_DATA);
   SetIndexBuffer(13, g_chaosBot,  INDICATOR_DATA);
   
   // Arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 108);  // ● circle for pivot high
   PlotIndexSetInteger(1, PLOT_ARROW, 108);  // ● circle for pivot low
   PlotIndexSetInteger(4, PLOT_ARROW, 241);  // ▲ HH
   PlotIndexSetInteger(5, PLOT_ARROW, 242);  // ▼ LH
   PlotIndexSetInteger(6, PLOT_ARROW, 241);  // ▲ HL
   PlotIndexSetInteger(7, PLOT_ARROW, 242);  // ▼ LL
   PlotIndexSetInteger(8, PLOT_ARROW, 233);  // ▲ Buy
   PlotIndexSetInteger(9, PLOT_ARROW, 234);  // ▼ Sell
   
   // EMPTY_VALUE
   for(int p = 0; p < 14; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("PVTG-TIER(%d,%d)", InpLeft, InpRight));
   
   g_totalBars = 0;
   g_prevBuy = false; g_prevSell = false;
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int limit = InpLeft + InpRight + InpShunt + 25;
   if(rates_total < limit) return 0;
   
   // Rebuild the full visual state each pass so shelves stay aligned with
   // confirmed pivots instead of inheriting stale object/buffer state.
   if(prev_calculated == 0)
   {
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringFind(name, g_prefix) == 0)
            ObjectDelete(0, name);
      }
   }
   
   ArrayInitialize(g_pvthi, EMPTY_VALUE);
   ArrayInitialize(g_pvtlo, EMPTY_VALUE);
   ArrayInitialize(g_resLevel, EMPTY_VALUE);
   ArrayInitialize(g_supLevel, EMPTY_VALUE);
   ArrayInitialize(g_hh, EMPTY_VALUE);
   ArrayInitialize(g_lh, EMPTY_VALUE);
   ArrayInitialize(g_hl, EMPTY_VALUE);
   ArrayInitialize(g_ll, EMPTY_VALUE);
   ArrayInitialize(g_fbBuy, EMPTY_VALUE);
   ArrayInitialize(g_fbSell, EMPTY_VALUE);
   ArrayInitialize(g_fastMA, EMPTY_VALUE);
   ArrayInitialize(g_slowMA, EMPTY_VALUE);
   ArrayInitialize(g_chaosTop, EMPTY_VALUE);
   ArrayInitialize(g_chaosBot, EMPTY_VALUE);
   
   int start = limit;
   
   // ── Build custom high/low for Renko mode ──
   double highSrc[], lowSrc[];
   ArrayResize(highSrc, rates_total);
   ArrayResize(lowSrc, rates_total);
   for(int i = 0; i < rates_total; i++)
   {
      if(InpRenko)
      {
         highSrc[i] = MathMax(close[i], open[i]);
         lowSrc[i]  = MathMin(close[i], open[i]);
      }
      else
      {
         highSrc[i] = high[i];
         lowSrc[i]  = low[i];
      }
   }
   
   // ── Build price source arrays for MAs ──
   double fastSrc[], slowSrc[], volArr[];
   ArrayResize(fastSrc, rates_total);
   ArrayResize(slowSrc, rates_total);
   ArrayResize(volArr, rates_total);
   for(int i = 0; i < rates_total; i++)
   {
      fastSrc[i] = GetPrice(open[i], high[i], low[i], close[i], InpFastMASrc);
      slowSrc[i] = GetPrice(open[i], high[i], low[i], close[i], InpSlowMASrc);
      volArr[i]  = (double)((tick_volume[i] > 0) ? tick_volume[i] : 1);
   }
   
   // ── MA filter EMA(21) for auto-strength ──
   double ema21[];
   ArrayResize(ema21, rates_total);
   for(int i = 0; i < rates_total; i++)
      ema21[i] = (i >= 20) ? CalcEMA(close, 21, i - 20) : 0.0;
   
   // ── MAIN LOOP ────────────────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // --- Compute MAs ---
      int fastShift = i - InpFastMALen + 1;
      int slowShift = i - InpSlowMALen + 1;
      g_fastMA[i] = (fastShift >= 0) ? GetMA(InpFastMAType, fastSrc, volArr, InpFastMALen, fastShift) : EMPTY_VALUE;
      g_slowMA[i] = (slowShift >= 0) ? GetMA(InpSlowMAType, slowSrc, volArr, InpSlowMALen, slowShift) : EMPTY_VALUE;
      
      if(!InpShowMAs)
      {
         g_fastMA[i] = EMPTY_VALUE;
         g_slowMA[i] = EMPTY_VALUE;
      }
      
      // --- Auto-strength pivot lengths ---
      int pvtLenL = InpLeft;
      int pvtLenR = InpRight;
      if(InpAutoStrength)
      {
         pvtLenL = (close[i] > ema21[i]) ? InpLeft : InpLeft + 1;
         pvtLenR = (close[i] < ema21[i]) ? InpRight : InpRight + 1;
      }
      
      int pivotIdx = i - pvtLenR - InpShunt;  // The bar where the pivot actually is
      if(pivotIdx < 0 || pivotIdx >= rates_total)
         continue;
      
      // --- Detect pivots ---
      bool isPhi = false, isPlo = false;
      
      if(InpIdeal)
      {
         isPhi = IsIdealPivotHigh(highSrc, pvtLenL, pvtLenR, pivotIdx);
         isPlo = IsIdealPivotLow(lowSrc, pvtLenL, pvtLenR, pivotIdx);
      }
      else
      {
         isPhi = IsPivotHigh(highSrc, pvtLenL, pvtLenR, pivotIdx);
         isPlo = IsPivotLow(lowSrc, pvtLenL, pvtLenR, pivotIdx);
      }
      
      // MA filter override
      if(InpUseMAFilter)
      {
         if(InpFastMALen > InpSlowMALen ||
            g_fastMA[pivotIdx] == EMPTY_VALUE || g_slowMA[pivotIdx] == EMPTY_VALUE ||
            g_fastMA[pivotIdx] < g_slowMA[pivotIdx])
            isPhi = false;
         if(InpFastMALen > InpSlowMALen ||
            g_fastMA[pivotIdx] == EMPTY_VALUE || g_slowMA[pivotIdx] == EMPTY_VALUE ||
            g_fastMA[pivotIdx] > g_slowMA[pivotIdx])
            isPlo = false;
      }
      
      // --- Set pivot markers (at the pivot bar, not current bar) ---
      double phiVal = isPhi ? highSrc[pivotIdx] : EMPTY_VALUE;
      double ploVal = isPlo ? lowSrc[pivotIdx]  : EMPTY_VALUE;
      
      if(InpShowPivots)
      {
         if(pivotIdx >= 0 && pivotIdx < rates_total)
         {
            g_pvthi[pivotIdx] = isPhi ? highSrc[pivotIdx] : g_pvthi[pivotIdx];
            g_pvtlo[pivotIdx] = isPlo ? lowSrc[pivotIdx]  : g_pvtlo[pivotIdx];
         }
      }
      
      // --- HH/HL/LH/LL detection ---
      if(InpShowHHLL && pivotIdx >= 0 && pivotIdx < rates_total)
      {
         double H0 = ValueWhen(g_pvthi, highSrc, 0, pivotIdx);
         double H1 = ValueWhen(g_pvthi, highSrc, 1, pivotIdx);
         double H2 = ValueWhen(g_pvthi, highSrc, 2, pivotIdx);
         double H3 = ValueWhen(g_pvthi, highSrc, 3, pivotIdx);
         
         double L0 = ValueWhen(g_pvtlo, lowSrc, 0, pivotIdx);
         double L1 = ValueWhen(g_pvtlo, lowSrc, 1, pivotIdx);
         double L2 = ValueWhen(g_pvtlo, lowSrc, 2, pivotIdx);
         double L3 = ValueWhen(g_pvtlo, lowSrc, 3, pivotIdx);
         
         bool isHH = false, isLH = false, isHL = false, isLL = false;
         
         if(isPhi && H0 != EMPTY_VALUE && H1 != EMPTY_VALUE)
         {
            if(InpSwing3Levels)
            {
               if(H2 != EMPTY_VALUE && H3 != EMPTY_VALUE)
               {
                  isHH = (H1 < H0 && H2 < H0 && H3 < H0);
                  isLH = (H1 > H0 && H2 > H0 && H3 > H0);
               }
            }
            else
            {
               isHH = (H1 < H0);
               isLH = (H1 > H0);
            }
         }
         
         if(isPlo && L0 != EMPTY_VALUE && L1 != EMPTY_VALUE)
         {
            if(InpSwing3Levels)
            {
               if(L2 != EMPTY_VALUE && L3 != EMPTY_VALUE)
               {
                  isHL = (L1 < L0 && L2 < L0 && L3 < L0);
                  isLL = (L1 > L0 && L2 > L0 && L3 > L0);
               }
            }
            else
            {
               isHL = (L1 < L0);
               isLL = (L1 > L0);
            }
         }
         
         g_hh[pivotIdx] = isHH ? highSrc[pivotIdx] : EMPTY_VALUE;
         g_lh[pivotIdx] = isLH ? highSrc[pivotIdx] : EMPTY_VALUE;
         g_hl[pivotIdx] = isHL ? lowSrc[pivotIdx]  : EMPTY_VALUE;
         g_ll[pivotIdx] = isLL ? lowSrc[pivotIdx]  : EMPTY_VALUE;
      }
      
      // --- Fractal Break Signals ---
      if(InpShowFB && i > 0)
      {
         double pvthis = EMPTY_VALUE;
         double pvtlos = EMPTY_VALUE;
         for(int j = i; j < rates_total; j++)
         {
            if(pvthis == EMPTY_VALUE && g_pvthi[j] != EMPTY_VALUE)
               pvthis = highSrc[j];
            if(pvtlos == EMPTY_VALUE && g_pvtlo[j] != EMPTY_VALUE)
               pvtlos = lowSrc[j];
            if(pvthis != EMPTY_VALUE && pvtlos != EMPTY_VALUE)
               break;
         }
         
         bool buy  = (pvthis != EMPTY_VALUE && close[i] > pvthis && open[i] <= pvthis);
         bool sell = (pvtlos != EMPTY_VALUE && close[i] < pvtlos && open[i] >= pvtlos);
         
         if(InpFilterFB)
         {
            bool maBull = (InpFastMALen > InpSlowMALen || g_fastMA[i] > g_slowMA[i]);
            bool maBear = (InpFastMALen > InpSlowMALen || g_fastMA[i] < g_slowMA[i]);
            buy  = buy  && maBull && close[i] > g_fastMA[i];
            sell = sell && maBear && close[i] < g_fastMA[i];
         }
         
         g_fbBuy[i]  = buy  ? low[i]  * 0.998 : EMPTY_VALUE;
         g_fbSell[i] = sell ? high[i] * 1.002 : EMPTY_VALUE;
         
         // Alerts
         if(InpShowAlerts && i == rates_total - 1)
         {
            if(buy && !g_prevBuy)
               Alert("PVTG BUY | ", _Symbol, " | Fractal Break | TF: ",
                     EnumToString(Period()), " | ", DoubleToString(close[i], _Digits));
            if(sell && !g_prevSell)
               Alert("PVTG SELL | ", _Symbol, " | Fractal Break | TF: ",
                     EnumToString(Period()), " | ", DoubleToString(close[i], _Digits));
            g_prevBuy = buy; g_prevSell = sell;
         }
      }
      
      // --- Pivot Bar Highlight (colored bar via a marker) ---
      if(InpClrBar && pivotIdx >= 0 && (isPhi || isPlo))
      {
         string barObj = g_prefix + "bar_" + IntegerToString(pivotIdx);
         if(ObjectFind(0, barObj) < 0)
         {
            ObjectCreate(0, barObj, OBJ_RECTANGLE, 0,
                        time[pivotIdx], highSrc[pivotIdx],
                        time[pivotIdx] + PeriodSeconds(), lowSrc[pivotIdx]);
            ObjectSetInteger(0, barObj, OBJPROP_COLOR, C'0xFF,0xA5,0x00');  // Orange
            ObjectSetInteger(0, barObj, OBJPROP_FILL, true);
            ObjectSetInteger(0, barObj, OBJPROP_BACK, true);
            ObjectSetInteger(0, barObj, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, barObj, OBJPROP_HIDDEN, true);
         }
      }
   }
   
   // --- Build shelves from confirmed pivots, oldest to newest ---
   double lastRes = EMPTY_VALUE;
   double lastSup = EMPTY_VALUE;
   int    resCount = 0;
   int    supCount = 0;
   
   for(int i = rates_total - 1; i >= 0; i--)
   {
      bool newRes = false;
      bool newSup = false;
      
      if(g_pvthi[i] != EMPTY_VALUE)
      {
         lastRes = highSrc[i];
         resCount = 0;
         newRes = true;
      }
      else if(lastRes != EMPTY_VALUE)
      {
         resCount++;
      }
      
      if(g_pvtlo[i] != EMPTY_VALUE)
      {
         lastSup = lowSrc[i];
         supCount = 0;
         newSup = true;
      }
      else if(lastSup != EMPTY_VALUE)
      {
         supCount++;
      }
      
      bool showRes = (InpMaxLevelLen == 0 || resCount <= InpMaxLevelLen);
      bool showSup = (InpMaxLevelLen == 0 || supCount <= InpMaxLevelLen);
      
      if(InpShowLevels && !InpShowChannel)
      {
         g_resLevel[i] = (lastRes != EMPTY_VALUE && showRes && !newRes) ? lastRes : EMPTY_VALUE;
         g_supLevel[i] = (lastSup != EMPTY_VALUE && showSup && !newSup) ? lastSup : EMPTY_VALUE;
      }
      
      if(InpShowLevels && InpShowChannel)
      {
         g_chaosTop[i] = (lastRes != EMPTY_VALUE) ? lastRes : EMPTY_VALUE;
         g_chaosBot[i] = (lastSup != EMPTY_VALUE) ? lastSup : EMPTY_VALUE;
      }
   }
   
   // ── Clean up old bar highlights ──
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix + "bar_") == 0)
      {
         // Keep only last 200 bar highlights
         int barNum = (int)StringToInteger(StringSubstr(name, StringLen(g_prefix) + 4));
         if(barNum < rates_total - 200)
            ObjectDelete(0, name);
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Get price from ENUM_APPLIED_PRICE                                 |
//+------------------------------------------------------------------+
double GetPrice(double o, double h, double l, double c, ENUM_APPLIED_PRICE ap)
{
   switch(ap)
   {
      case PRICE_OPEN:    return o;
      case PRICE_HIGH:    return h;
      case PRICE_LOW:     return l;
      case PRICE_CLOSE:   return c;
      case PRICE_MEDIAN:  return (h + l) / 2.0;
      case PRICE_TYPICAL: return (h + l + c) / 3.0;
      case PRICE_WEIGHTED:return (h + l + c * 2.0) / 4.0;
      default:            return c;
   }
}
//+------------------------------------------------------------------+
