//+------------------------------------------------------------------+
//|                                          Elite Triple MA Suite.mq5 |
//|                    Ported from Pine Script v6 → MQL5 (Full)       |
//|                    Original: Elite_Triple_MA_Suite.pine           |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: Elite Triple MA Suite [MTF + ATR Cloud] ::"
#property description "Triple MA with dynamic slope coloring, ATR volatility cloud,"
#property description "volume-filtered crossover signals, MTF context & live dashboard."

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   7

// ── Plot 0: Fast MA (DRAW_COLOR_LINE = value buffer + color buffer) ─────────
#property indicator_label1  "Fast MA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'0x00,0xFF,0xBB',C'0xFF,0x00,0x55'  // #00ffbb up / #ff0055 down
#property indicator_width1  2

// ── Plot 1: Mid MA ──────────────────────────────────────────────────────────
#property indicator_label2  "Mid MA"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  C'0x21,0x96,0xF3',C'0x3F,0x51,0xB5'  // #2196f3 up / #3f51b5 down
#property indicator_width2  2

// ── Plot 2: Slow MA ─────────────────────────────────────────────────────────
#property indicator_label3  "Slow MA"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  clrWhite,C'0x78,0x7B,0x86'            // white up / #787b86 down
#property indicator_width3  3

// ── Plot 3: ATR Upper Cloud ─────────────────────────────────────────────────
#property indicator_label4  "ATR Upper"
#property indicator_type4   DRAW_LINE
#property indicator_color4  C'0x80,0x80,0x80'
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

// ── Plot 4: ATR Lower Cloud ─────────────────────────────────────────────────
#property indicator_label5  "ATR Lower"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'0x80,0x80,0x80'
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

// ── Plot 5: Buy Signal Arrow ────────────────────────────────────────────────
#property indicator_label6  "Buy Signal"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  2

// ── Plot 6: Sell Signal Arrow ───────────────────────────────────────────────
#property indicator_label7  "Sell Signal"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrRed
#property indicator_width7  2

// ── Custom MA Type Enum ─────────────────────────────────────────────────────
enum ENUM_ELITE_MA_TYPE
{
   ELITE_MA_SMA  = 0,  // SMA
   ELITE_MA_EMA  = 1,  // EMA
   ELITE_MA_WMA  = 2,  // WMA (LWMA)
   ELITE_MA_HMA  = 3,  // Hull MA
   ELITE_MA_VWMA = 4   // Volume-Weighted MA
};

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ MA Settings ═══"
input ENUM_APPLIED_PRICE           InpSrc          = PRICE_CLOSE;          // Source price
input int                          InpFastLen      = 9;                    // Fast MA Length (>= 1)
input int                          InpMidLen       = 21;                   // Medium MA Length (>= 1)
input int                          InpSlowLen      = 55;                   // Slow MA Length (>= 1)
input ENUM_ELITE_MA_TYPE           InpMaType       = ELITE_MA_SMA;         // MA Type

input group                        "═══ Volatility Cloud ═══"
input int                          InpAtrLen       = 14;                   // ATR Length (>= 1)
input double                       InpAtrMult      = 2.0;                  // ATR Multiplier (>= 0.1)
input bool                         InpShowCloud    = true;                 // Show ATR Cloud
input bool                         InpCloudFill    = true;                 // Fill ATR Cloud Area

input group                        "═══ Signals ═══"
input bool                         InpShowSignals  = true;                 // Show Volume-Filtered Signals
input bool                         InpShowAlerts   = true;                 // Enable Popup Alerts on Signals
input bool                         InpShowBgColor  = true;                 // Highlight Signal Bars

input group                        "═══ Elite Dashboard ═══"
input bool                         InpShowTable    = true;                 // Show Elite Analytics Dashboard
input ENUM_BASE_CORNER             InpTableCorner  = CORNER_RIGHT_UPPER;   // Dashboard Position
input int                          InpTableX       = 10;                   // Dashboard X Offset (pixels)
input int                          InpTableY       = 20;                   // Dashboard Y Offset (pixels)

// ── Indicator Buffers ───────────────────────────────────────────────────────
// Plot buffers. DRAW_COLOR_LINE plots require a color-index buffer directly
// after their data buffer in MT5.
double g_fastMA[];        // 0
double g_fastColor[];     // 1
double g_midMA[];         // 2
double g_midColor[];      // 3
double g_slowMA[];        // 4
double g_slowColor[];     // 5
double g_upperCloud[];    // 6
double g_lowerCloud[];    // 7
double g_buySignal[];     // 8
double g_sellSignal[];    // 9

// ── Runtime State ───────────────────────────────────────────────────────────
string   g_prefix      = "EliteTMA_";   // Object name prefix for cleanup
bool     g_prevBuy     = false;
bool     g_prevSell    = false;
string   g_htfLabel;                    // "D1" or "W1"

//+------------------------------------------------------------------+
//| MA Calculator: SMA                                                |
//+------------------------------------------------------------------+
double SMA(double &arr[], int period, int startIdx)
{
   if(period <= 0 || startIdx < 0) return 0;
   if(startIdx + period > ArraySize(arr)) return 0;
   double sum = 0;
   for(int i = 0; i < period; i++) sum += arr[startIdx + i];
   return sum / period;
}

//+------------------------------------------------------------------+
//| MA Calculator: EMA (recursive from seed)                          |
//+------------------------------------------------------------------+
double EMA(double &arr[], int period, int startIdx)
{
   int size = ArraySize(arr);
   if(period <= 0 || startIdx < 0) return 0;
   if(startIdx + period > size) return 0;
   
   double alpha = 2.0 / (period + 1.0);
   double ema = arr[startIdx + period - 1];
   for(int i = startIdx + period - 2; i >= startIdx; i--)
      ema = arr[i] * alpha + ema * (1.0 - alpha);
   
   return ema;
}

//+------------------------------------------------------------------+
//| MA Calculator: WMA (LWMA)                                        |
//+------------------------------------------------------------------+
double WMA(double &arr[], int period, int startIdx)
{
   if(period <= 0 || startIdx < 0) return 0;
   if(startIdx + period > ArraySize(arr)) return 0;
   double sum = 0, weightSum = 0;
   for(int i = 0; i < period; i++)
   {
      double w = (double)(period - i); // newest bar at startIdx gets highest weight
      sum += arr[startIdx + i] * w;
      weightSum += w;
   }
   return (weightSum > 0) ? sum / weightSum : 0;
}

//+------------------------------------------------------------------+
//| MA Calculator: Hull Moving Average                                |
//| HMA(n) = WMA( 2*WMA(n/2) - WMA(n), sqrt(n) )                    |
//+------------------------------------------------------------------+
double HMA(double &arr[], int period, int startIdx)
{
   if(period <= 0 || startIdx < 0) return 0;
   int half  = (int)MathFloor(period / 2.0);
   int root  = (int)MathFloor(MathSqrt(period));
   if(half < 2) half = 2;
   if(root < 1) root = 1;
   
   int size = ArraySize(arr);
   if(startIdx + period > size) return 0;
   
   // Precompute WMA(n/2) and WMA(n) for needed range
   double wmaHalf[], wmaFull[], diff[];
   int need = startIdx + root + 1;
   ArrayResize(wmaHalf, need);
   ArrayResize(wmaFull, need);
   ArrayResize(diff,   need);
   
   for(int i = 0; i < need && i + half <= size; i++)
      wmaHalf[i] = WMA(arr, half, i);
   for(int i = 0; i < need && i + period <= size; i++)
      wmaFull[i] = WMA(arr, period, i);
   for(int i = 0; i < need; i++)
      diff[i] = 2.0 * wmaHalf[i] - wmaFull[i];
   
   return WMA(diff, root, startIdx);
}

//+------------------------------------------------------------------+
//| MA Calculator: VWMA (volume-weighted)                             |
//+------------------------------------------------------------------+
double VWMA(double &price[], double &vol[], int period, int startIdx)
{
   if(period <= 0 || startIdx < 0) return 0;
   if(startIdx + period > ArraySize(price)) return 0;
   double sumPV = 0, sumV = 0;
   for(int i = 0; i < period; i++)
   {
      double v = (startIdx + i < ArraySize(vol)) ? vol[startIdx + i] : 1.0;
      if(v <= 0) v = 1.0;
      sumPV += price[startIdx + i] * v;
      sumV  += v;
   }
   return (sumV > 0) ? sumPV / sumV : 0;
}

//+------------------------------------------------------------------+
//| MA Router                                                        |
//+------------------------------------------------------------------+
double GetMA(ENUM_ELITE_MA_TYPE t, double &price[], double &vol[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   switch(t)
   {
      case ELITE_MA_SMA:  return SMA(price, period, shift);
      case ELITE_MA_EMA:  return EMA(price, period, shift);
      case ELITE_MA_WMA:  return WMA(price, period, shift);
      case ELITE_MA_HMA:  return HMA(price, period, shift);
      case ELITE_MA_VWMA: return VWMA(price, vol, period, shift);
      default:            return EMA(price, period, shift);
   }
}

//+------------------------------------------------------------------+
//| ATR (Wilder's smoothing)                                         |
//+------------------------------------------------------------------+
double ATR(const double &h[], const double &l[], const double &c[], int period, int idx)
{
   if(idx < period) return 0;
   double trSum = 0;
   for(int i = idx - period + 1; i <= idx; i++)
   {
      double tr = MathMax(h[i] - l[i],
                   MathMax(MathAbs(h[i] - c[i-1]), MathAbs(l[i] - c[i-1])));
      trSum += tr;
   }
   return trSum / period;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Bind buffers
   SetIndexBuffer(0, g_fastMA,      INDICATOR_DATA);
   SetIndexBuffer(1, g_fastColor,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, g_midMA,       INDICATOR_DATA);
   SetIndexBuffer(3, g_midColor,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, g_slowMA,      INDICATOR_DATA);
   SetIndexBuffer(5, g_slowColor,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, g_upperCloud,  INDICATOR_DATA);
   SetIndexBuffer(7, g_lowerCloud,  INDICATOR_DATA);
   SetIndexBuffer(8, g_buySignal,   INDICATOR_DATA);
   SetIndexBuffer(9, g_sellSignal,  INDICATOR_DATA);
   
   // Arrow codes (233=thumbs up, 234=thumbs down in Wingdings)
   PlotIndexSetInteger(5, PLOT_ARROW, 233);
   PlotIndexSetInteger(6, PLOT_ARROW, 234);
   
   // EMPTY_VALUE for all plots
   for(int p = 0; p < 7; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   // Short name
   static string maNames[] = {"SMA","EMA","WMA","HMA","VWMA"};
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("EliteMA(%d,%d,%d %s)", InpFastLen, InpMidLen, InpSlowLen,
                   (InpMaType >= 0 && InpMaType <= 4) ? maNames[InpMaType] : "EMA"));
   
   // Higher TF string
   g_htfLabel = (Period() <= PERIOD_H1) ? "D1" : "W1";
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
}

//+------------------------------------------------------------------+
//| OnCalculate (main entry)                                          |
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
   // ── Minimum bars check ──
   int minBars = MathMax(InpSlowLen, MathMax(InpFastLen, InpMidLen)) + InpAtrLen + 25;
   if(rates_total < minBars)
      return 0;
   
   if(prev_calculated == 0)
   {
      ArrayInitialize(g_fastMA, EMPTY_VALUE);
      ArrayInitialize(g_fastColor, 0.0);
      ArrayInitialize(g_midMA, EMPTY_VALUE);
      ArrayInitialize(g_midColor, 0.0);
      ArrayInitialize(g_slowMA, EMPTY_VALUE);
      ArrayInitialize(g_slowColor, 0.0);
      ArrayInitialize(g_upperCloud, EMPTY_VALUE);
      ArrayInitialize(g_lowerCloud, EMPTY_VALUE);
      ArrayInitialize(g_buySignal, EMPTY_VALUE);
      ArrayInitialize(g_sellSignal, EMPTY_VALUE);
   }
   
   // ── Calculate start position ──
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start < minBars)
      start = minBars;
   
   // ── Build source price array ──
   double src[];
   ArrayResize(src, rates_total);
   for(int i = 0; i < rates_total; i++)
   {
      switch(InpSrc)
      {
         case PRICE_OPEN:    src[i] = open[i];                                          break;
         case PRICE_HIGH:    src[i] = high[i];                                          break;
         case PRICE_LOW:     src[i] = low[i];                                           break;
         case PRICE_MEDIAN:  src[i] = (high[i] + low[i]) / 2.0;                        break;
         case PRICE_TYPICAL: src[i] = (high[i] + low[i] + close[i]) / 3.0;             break;
         case PRICE_WEIGHTED:src[i] = (high[i] + low[i] + close[i]*2) / 4.0;           break;
         default:            src[i] = close[i];                                         break;
      }
   }
   
   // ── Build volume double array ──
   double volArr[];
   ArrayResize(volArr, rates_total);
   for(int i = 0; i < rates_total; i++)
      volArr[i] = (double)((tick_volume[i] > 0) ? tick_volume[i] : 1);
   
   // ── Higher-timeframe close data for MTF ──
   ENUM_TIMEFRAMES htf = (Period() <= PERIOD_H1) ? PERIOD_D1 : PERIOD_W1;
   double htfClose[];
   ArraySetAsSeries(htfClose, true);
   int htfBars = CopyClose(_Symbol, htf, 0, InpSlowLen + 5, htfClose);
   
   // ── MAIN CALCULATION LOOP ─────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      g_upperCloud[i] = EMPTY_VALUE;
      g_lowerCloud[i] = EMPTY_VALUE;
      g_buySignal[i] = EMPTY_VALUE;
      g_sellSignal[i] = EMPTY_VALUE;
      
      // --- Compute MAs ---
      g_fastMA[i] = GetMA(InpMaType, src, volArr, InpFastLen, i - InpFastLen + 1);
      g_midMA[i]  = GetMA(InpMaType, src, volArr, InpMidLen,  i - InpMidLen + 1);
      g_slowMA[i] = GetMA(InpMaType, src, volArr, InpSlowLen, i - InpSlowLen + 1);
      
      // --- Dynamic Slope Color Index ---
      // Index 0 = color[0] (bullish/up), Index 1 = color[1] (bearish/down)
      g_fastColor[i] = (i > 0 && g_fastMA[i] > g_fastMA[i-1]) ? 0.0 : 1.0;
      g_midColor[i]  = (i > 0 && g_midMA[i]  > g_midMA[i-1])  ? 0.0 : 1.0;
      g_slowColor[i] = (i > 0 && g_slowMA[i] > g_slowMA[i-1]) ? 0.0 : 1.0;
      
      // --- ATR Cloud ---
      double atrVal = ATR(high, low, close, InpAtrLen, i);
      if(InpShowCloud)
      {
         g_upperCloud[i] = g_slowMA[i] + (atrVal * InpAtrMult);
         g_lowerCloud[i] = g_slowMA[i] - (atrVal * InpAtrMult);
      }
      else
      {
         g_upperCloud[i] = EMPTY_VALUE;
         g_lowerCloud[i] = EMPTY_VALUE;
      }
      
      // --- Volume Confirmation ---
      double volSMA20 = SMA(volArr, 20, i - 19);
      bool volConfirm = (volArr[i] > volSMA20);
      
      // --- Trend Alignment ---
      bool bullAlign = (g_fastMA[i] > g_midMA[i] && g_midMA[i] > g_slowMA[i]);
      bool bearAlign = (g_fastMA[i] < g_midMA[i] && g_midMA[i] < g_slowMA[i]);
      
      // --- MTF Context ---
      bool htfTrendBull = true;
      if(htfBars >= InpSlowLen)
      {
         double htfSlow = 0;
         if(InpMaType == ELITE_MA_EMA)
         {
            double alpha = 2.0 / (InpSlowLen + 1.0);
            htfSlow = htfClose[InpSlowLen - 1];
            for(int h = InpSlowLen - 2; h >= 0; h--)
               htfSlow = htfClose[h] * alpha + htfSlow * (1.0 - alpha);
         }
         else if(InpMaType == ELITE_MA_WMA)
         {
            double wSum = 0.0, sum = 0.0;
            for(int h = 0; h < InpSlowLen && h < htfBars; h++)
            {
               double w = (double)(InpSlowLen - h);
               sum += htfClose[h] * w;
               wSum += w;
            }
            htfSlow = wSum > 0.0 ? sum / wSum : 0.0;
         }
         else
         {
            double sum = 0;
            for(int h = 0; h < InpSlowLen && h < htfBars; h++)
               sum += htfClose[h];
            htfSlow = sum / MathMin(InpSlowLen, htfBars);
         }
         htfTrendBull = (close[i] > htfSlow);
      }
      
      // --- Crossover Signals ---
      bool buySig = false, sellSig = false;
      if(i > 0 && InpShowSignals)
      {
         bool crossUp   = (g_fastMA[i] > g_midMA[i] && g_fastMA[i-1] <= g_midMA[i-1]);
         bool crossDown = (g_fastMA[i] < g_midMA[i] && g_fastMA[i-1] >= g_midMA[i-1]);
         
         buySig  = crossUp   && g_midMA[i] > g_slowMA[i] && volConfirm;
         sellSig = crossDown && g_midMA[i] < g_slowMA[i] && volConfirm;
      }
      
      g_buySignal[i]  = buySig  ? low[i]  - (atrVal * 0.5) : EMPTY_VALUE;
      g_sellSignal[i] = sellSig ? high[i] + (atrVal * 0.5) : EMPTY_VALUE;
      
      // --- Signal Bar Background Highlight ---
      if(InpShowBgColor && (buySig || sellSig) && i < rates_total - 1)
      {
         string bgName = g_prefix + "bg_" + IntegerToString(i);
         ObjectDelete(0, bgName);
         color bgClr = buySig ? C'0x00,0xFF,0x00' : C'0xFF,0x00,0x00';
         DrawRect(bgName, time[i], high[i], time[i] + PeriodSeconds(), low[i],
                  bgClr, true);
      }
      
      // --- Cloud Fill (rectangles between upper/lower cloud lines) ---
      if(InpShowCloud && InpCloudFill && i > 0 &&
         g_upperCloud[i] != EMPTY_VALUE && g_lowerCloud[i] != EMPTY_VALUE)
      {
         string cloudName = g_prefix + "cloud_" + IntegerToString(i);
         ObjectDelete(0, cloudName);
         color cloudClr = bullAlign ? C'0x20,0x6B,0x3E' :
                          bearAlign ? C'0x6B,0x20,0x20' :
                                      C'0x24,0x36,0x58';
         DrawRect(cloudName, time[i], g_upperCloud[i],
                  time[i] + PeriodSeconds(), g_lowerCloud[i],
                  cloudClr, true);
      }
      
      // --- Alert Trigger ---
      if(InpShowAlerts && i == rates_total - 1)
      {
         if(buySig && !g_prevBuy)
            Alert("BUY Signal | ", _Symbol, " | Elite MA Suite | TF: ",
                  EnumToString(Period()), " | Price: ", DoubleToString(close[i], _Digits));
         if(sellSig && !g_prevSell)
            Alert("SELL Signal | ", _Symbol, " | Elite MA Suite | TF: ",
                  EnumToString(Period()), " | Price: ", DoubleToString(close[i], _Digits));
         g_prevBuy  = buySig;
         g_prevSell = sellSig;
      }
   }
   
   // ── Dashboard (drawn once at the end on the latest bar) ──
   if(InpShowTable)
      RenderDashboard(rates_total, close, high, low, tick_volume, htf, htfClose, htfBars);
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Render Elite Dashboard (OBJ_LABEL-based table)                    |
//+------------------------------------------------------------------+
void RenderDashboard(int total, const double &c[], const double &h[], const double &l[],
                     const long &tv[], ENUM_TIMEFRAMES htf, double &htfClose[], int htfBars)
{
   int idx = total - 1;
   
   // Current values
   double atrVal    = ATR(h, l, c, InpAtrLen, idx);
   bool   bullAlign = (g_fastMA[idx] > g_midMA[idx] && g_midMA[idx] > g_slowMA[idx]);
   bool   bearAlign = (g_fastMA[idx] < g_midMA[idx] && g_midMA[idx] < g_slowMA[idx]);
   string dirText   = bullAlign ? "Strong Bullish" : bearAlign ? "Strong Bearish" : "Neutral/Consolidation";
   color  dirClr    = bullAlign ? clrLime : bearAlign ? clrRed : clrGray;
   
   // Volume surge
   double volArr[];
   ArrayResize(volArr, total);
   for(int i = 0; i < total; i++) volArr[i] = (double)tv[i];
   bool volConfirm = (volArr[idx] > SMA(volArr, 20, idx - 19));
   
   // HTF trend
   bool htfBull = true;
   if(htfBars >= InpSlowLen)
   {
      double htfSlow = 0;
      if(InpMaType == ELITE_MA_EMA)
      {
         double alpha = 2.0 / (InpSlowLen + 1.0);
         htfSlow = htfClose[InpSlowLen - 1];
         for(int i2 = InpSlowLen - 2; i2 >= 0; i2--)
            htfSlow = htfClose[i2] * alpha + htfSlow * (1.0 - alpha);
      }
      else
      {
         double sum = 0;
         for(int i2 = 0; i2 < InpSlowLen && i2 < htfBars; i2++)
            sum += htfClose[i2];
         htfSlow = sum / MathMin(InpSlowLen, htfBars);
      }
      htfBull = (c[idx] > htfSlow);
   }
   
   string rec      = (bullAlign && htfBull) ? "LONG ONLY" :
                     (bearAlign && !htfBull) ? "SHORT ONLY" : "WAIT";
   color  recClr   = (bullAlign && htfBull) ? clrLime :
                     (bearAlign && !htfBull) ? clrRed : clrYellow;
   
   // Layout constants
   int x0    = InpTableX;
   int y0    = InpTableY;
   int gap   = 16;
   int colW  = 155;
   int col2X = x0 + colW;
   color bg  = C'0x13,0x17,0x22';   // #131722
   color bdr = C'0x36,0x3C,0x4E';   // #363c4e
   
   // --- Row rendering ---
   int row = 0;
   
   // Macro-like row renderer using local function
   RenderRow(g_prefix, "ELITE ANALYSIS", _Symbol, clrWhite, x0, col2X, y0, gap, row++,
             InpTableCorner, colW);
   RenderRow(g_prefix, "Trend State", dirText, dirClr, x0, col2X, y0, gap, row++,
             InpTableCorner, colW);
   RenderRow(g_prefix, "Higher TF (" + g_htfLabel + ")",
             htfBull ? "BULLISH" : "BEARISH",
             htfBull ? clrLime : clrRed, x0, col2X, y0, gap, row++,
             InpTableCorner, colW);
   RenderRow(g_prefix, "ATR (Volatility)", DoubleToString(atrVal, _Digits), clrWhite,
             x0, col2X, y0, gap, row++, InpTableCorner, colW);
   RenderRow(g_prefix, "Volume Surge", volConfirm ? "YES" : "NO",
             volConfirm ? clrLime : clrOrange, x0, col2X, y0, gap, row++,
             InpTableCorner, colW);
   RenderRow(g_prefix, "Recommendation", rec, recClr, x0, col2X, y0, gap, row++,
             InpTableCorner, colW);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: Render a single dashboard row                             |
//+------------------------------------------------------------------+
void RenderRow(string prefix, string label, string value, color valClr,
               int x, int col2X, int y0, int gap, int row, int corner, int colW)
{
   int yy = y0 + row * gap;
   // Label
   CreateLabel(prefix + "l" + IntegerToString(row), label, x, yy, clrGray, 8, "Arial", corner);
   // Value
   CreateLabel(prefix + "v" + IntegerToString(row), value, col2X, yy, valClr, 8, "Arial Bold", corner);
}

//+------------------------------------------------------------------+
//| Helper: Create/Update OBJ_LABEL                                   |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size = 8,
                 string font = "Arial", int corner = CORNER_RIGHT_UPPER)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0,  name, OBJPROP_FONT, font);
}

//+------------------------------------------------------------------+
//| Helper: Draw a filled rectangle                                   |
//+------------------------------------------------------------------+
void DrawRect(string name, datetime t1, double p1, datetime t2, double p2,
              color clr, bool background)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, background);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Cleanup all indicator-created chart objects                       |
//+------------------------------------------------------------------+
void CleanupObjects()
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
//| OnChartEvent                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      ChartRedraw();
}
//+------------------------------------------------------------------+
