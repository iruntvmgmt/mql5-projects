//+------------------------------------------------------------------+
//|                                          WaveTrend MAX Ind.mq5    |
//|                    Ported from Pine Script v5 → MQL5 (Indicator)  |
//|                    Original: WaveTrend_MAX.pine                   |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: WaveTrend MAX :: LazyBear WT + Divergence + BB + Fibs"
#property description "Core WT oscillator with dynamic bands, Bollinger Bands,"
#property description "Fibonacci levels, and divergence engine."

#property indicator_separate_window
#property indicator_buffers 20
#property indicator_plots   16

// ── Plot 0-1: WT1 & WT2 ────────────────────────────────────────────────────
#property indicator_label1  "WT1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'0x00,0xBF,0xFF'
#property indicator_width1  2

#property indicator_label2  "WT2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  1

// ── Plot 2-3: Dynamic Bands ────────────────────────────────────────────────
#property indicator_label3  "Dynamic Upper"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrFuchsia
#property indicator_width3  1

#property indicator_label4  "Dynamic Lower"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrYellow
#property indicator_width4  1

// ── Plot 4-6: BB Bands ─────────────────────────────────────────────────────
#property indicator_label5  "BB Upper"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'0x80,0x80,0x80'
#property indicator_width5  1

#property indicator_label6  "BB Middle"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrYellow
#property indicator_width6  1

#property indicator_label7  "BB Lower"
#property indicator_type7   DRAW_LINE
#property indicator_color7  C'0x80,0x80,0x80'
#property indicator_width7  1

// ── Plot 7: Fib 50 ─────────────────────────────────────────────────────────
#property indicator_label8  "Fib 50"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrOrange
#property indicator_width8  1

// ── Plot 8-9: Zero & Fixed Levels ──────────────────────────────────────────
#property indicator_label9  "Zero Line"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrWhite
#property indicator_width9  1

#property indicator_label10 "Level +60"
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrGreen
#property indicator_width10 1

#property indicator_label11 "Level -60"
#property indicator_type11  DRAW_LINE
#property indicator_color11 clrRed
#property indicator_width11 1

// ── Plot 12-13: Buy/Sell Divergence Markers ────────────────────────────────
#property indicator_label12 "Buy Div"
#property indicator_type12  DRAW_ARROW
#property indicator_color12 clrLime
#property indicator_width12 2

#property indicator_label13 "Sell Div"
#property indicator_type13  DRAW_ARROW
#property indicator_color13 clrRed
#property indicator_width13 2

// ── Plot 14-15: Signal markers ─────────────────────────────────────────────
#property indicator_label14 "Long Signal"
#property indicator_type14  DRAW_ARROW
#property indicator_color14 clrLime
#property indicator_width14 2

#property indicator_label15 "Short Signal"
#property indicator_type15  DRAW_ARROW
#property indicator_color15 clrRed
#property indicator_width15 2

#property indicator_label16 "Histogram"
#property indicator_type16  DRAW_HISTOGRAM
#property indicator_color16 clrDodgerBlue
#property indicator_width16 2

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ WaveTrend ═══"
input ENUM_APPLIED_PRICE           InpSrc          = PRICE_TYPICAL;       // Source
input int                          InpN1           = 10;                  // Channel Length
input int                          InpN2           = 21;                  // Average Length
input ENUM_MA_METHOD               InpMAType       = MODE_EMA;            // MA Type

input group                        "═══ Dynamic Bands ═══"
input int                          InpCycMem       = 20;                  // Dynamic Bands Lookback
input int                          InpLeveling     = 10;                  // Band Percentile (1-49)

input group                        "═══ Bollinger Bands ═══"
input bool                         InpShowBB       = true;                // Show BB
input int                          InpBBLen        = 14;                  // BB Length
input double                       InpBBMult       = 0.8;                 // BB Multiplier

input group                        "═══ Divergence ═══"
input int                          InpDivLeft      = 5;                   // Pivot Left
input int                          InpDivRight     = 3;                   // Pivot Right
input int                          InpMaxPivBars   = 100;                 // Max Bars Between
input bool                         InpShowDivLines = true;                // Show Div Lines
input int                          InpMaxDivLines  = 5;                   // Max Lines

input group                        "═══ Signals & Alerts ═══"
input bool                         InpShowSignals  = true;                // Show Signals
input bool                         InpShowAlerts   = true;                // Enable Alerts

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_wt1[];            // 0
double g_wt2[];            // 1
double g_ub[];             // 2
double g_db[];             // 3
double g_bbUpper[];        // 4
double g_bbMiddle[];       // 5
double g_bbLower[];        // 6
double g_fib50[];          // 7
double g_zeroLine[];       // 8
double g_plus60[];         // 9
double g_minus60[];        // 10
double g_buyDiv[];         // 11
double g_sellDiv[];        // 12
double g_longSig[];        // 13
double g_shortSig[];       // 14
double g_hist[];           // 15
// Hidden calc buffers
double g_esaBuf[];         // 16
double g_dBuf[];           // 17
double g_ciBuf[];          // 18
double g_rangeBuf[];       // 19

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix = "WTMAX_";
bool   g_prevBuy, g_prevSell;

// ── Helpers ─────────────────────────────────────────────────────────────────
double GetMA(double &a[], int p, int s, ENUM_MA_METHOD m)
{
   int sz = ArraySize(a);
   if(p <= 0 || s < 0 || s + p > sz) return 0;
   
   if(m == MODE_SMA)
   {
      double sum = 0;
      for(int i = 0; i < p; i++) sum += a[s + i];
      return sum / p;
   }
   
   if(m == MODE_LWMA)
   {
      double weighted = 0.0;
      double weightSum = 0.0;
      for(int i = 0; i < p; i++)
      {
         double w = (double)(p - i); // newest bar at s gets highest weight
         weighted += a[s + i] * w;
         weightSum += w;
      }
      return weightSum > 0.0 ? weighted / weightSum : 0.0;
   }
   
   if(m == MODE_EMA)
   {
      double alpha = 2.0 / (p + 1.0);
      double ema = a[s + p - 1]; // oldest bar in the lookback window
      for(int i = s + p - 2; i >= s; i--)
         ema = a[i] * alpha + ema * (1.0 - alpha);
      return ema;
   }
   
   if(m == MODE_SMMA)
   {
      double smma = a[s + p - 1]; // oldest bar in the lookback window
      for(int i = s + p - 2; i >= s; i--)
         smma = (smma * (p - 1) + a[i]) / p;
      return smma;
   }
   
   // Fallback to SMA for any unsupported method.
   double sum = 0.0;
   for(int i = 0; i < p; i++) sum += a[s + i];
   return sum / p;
}

double StdDev(double &a[], int p, int s)
{
   double mean = GetMA(a, p, s, MODE_SMA);
   double ss = 0;
   for(int i = 0; i < p; i++) { double d = a[s+i]-mean; ss += d*d; }
   return MathSqrt(ss/p);
}

double PercentileLI(double &a[], int p, double pct, int s)
{
   int sz = ArraySize(a);
   if(s + p > sz || p < 2) return 0;
   double sorted[];
   ArrayResize(sorted, p);
   for(int i = 0; i < p; i++) sorted[i] = a[s + i];
   ArraySort(sorted);
   double pos = pct / 100.0 * (p - 1);
   int lo = (int)MathFloor(pos), hi = (int)MathCeil(pos);
   if(lo < 0) lo = 0; if(hi >= p) hi = p-1;
   if(lo == hi) return sorted[lo];
   double frac = pos - lo;
   return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
}

bool IsPivotHigh(double &a[], int l, int r, int idx)
{
   if(idx-l < 0 || idx+r >= ArraySize(a)) return false;
   double v = a[idx];
   for(int i = idx-l; i < idx; i++) if(a[i] > v) return false;
   for(int i = idx+1; i <= idx+r; i++) if(a[i] >= v) return false;
   return true;
}

bool IsPivotLow(double &a[], int l, int r, int idx)
{
   if(idx-l < 0 || idx+r >= ArraySize(a)) return false;
   double v = a[idx];
   for(int i = idx-l; i < idx; i++) if(a[i] < v) return false;
   for(int i = idx+1; i <= idx+r; i++) if(a[i] <= v) return false;
   return true;
}

double GetPrice(double o, double h, double l, double c, ENUM_APPLIED_PRICE ap)
{
   switch(ap)
   {
      case PRICE_OPEN: return o; case PRICE_HIGH: return h; case PRICE_LOW: return l;
      case PRICE_MEDIAN: return (h+l)/2; case PRICE_TYPICAL: return (h+l+c)/3;
      case PRICE_WEIGHTED: return (h+l+c*2)/4; default: return c;
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,  g_wt1,       INDICATOR_DATA);
   SetIndexBuffer(1,  g_wt2,       INDICATOR_DATA);
   SetIndexBuffer(2,  g_ub,        INDICATOR_DATA);
   SetIndexBuffer(3,  g_db,        INDICATOR_DATA);
   SetIndexBuffer(4,  g_bbUpper,   INDICATOR_DATA);
   SetIndexBuffer(5,  g_bbMiddle,  INDICATOR_DATA);
   SetIndexBuffer(6,  g_bbLower,   INDICATOR_DATA);
   SetIndexBuffer(7,  g_fib50,     INDICATOR_DATA);
   SetIndexBuffer(8,  g_zeroLine,  INDICATOR_DATA);
   SetIndexBuffer(9,  g_plus60,    INDICATOR_DATA);
   SetIndexBuffer(10, g_minus60,   INDICATOR_DATA);
   SetIndexBuffer(11, g_buyDiv,    INDICATOR_DATA);
   SetIndexBuffer(12, g_sellDiv,   INDICATOR_DATA);
   SetIndexBuffer(13, g_longSig,   INDICATOR_DATA);
   SetIndexBuffer(14, g_shortSig,  INDICATOR_DATA);
   SetIndexBuffer(15, g_hist,      INDICATOR_DATA);
   SetIndexBuffer(16, g_esaBuf,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, g_dBuf,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(18, g_ciBuf,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(19, g_rangeBuf,  INDICATOR_CALCULATIONS);
   
   PlotIndexSetInteger(11, PLOT_ARROW, 233);
   PlotIndexSetInteger(12, PLOT_ARROW, 234);
   PlotIndexSetInteger(13, PLOT_ARROW, 241);
   PlotIndexSetInteger(14, PLOT_ARROW, 242);
   
   for(int p = 0; p < 16; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("WT MAX(%d,%d)", InpN1, InpN2));
   
   g_prevBuy = false; g_prevSell = false;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r) { CleanupObjects(); }

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calc,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &v[], const int &sp[])
{
   int minB = InpN1 + InpN2 + InpCycMem + InpBBLen + InpDivLeft + InpDivRight + 50;
   if(rates_total < minB) return 0;
   
   if(prev_calc == 0)
   {
      ArrayInitialize(g_wt1, EMPTY_VALUE);
      ArrayInitialize(g_wt2, EMPTY_VALUE);
      ArrayInitialize(g_ub, EMPTY_VALUE);
      ArrayInitialize(g_db, EMPTY_VALUE);
      ArrayInitialize(g_bbUpper, EMPTY_VALUE);
      ArrayInitialize(g_bbMiddle, EMPTY_VALUE);
      ArrayInitialize(g_bbLower, EMPTY_VALUE);
      ArrayInitialize(g_fib50, EMPTY_VALUE);
      ArrayInitialize(g_zeroLine, EMPTY_VALUE);
      ArrayInitialize(g_plus60, EMPTY_VALUE);
      ArrayInitialize(g_minus60, EMPTY_VALUE);
      ArrayInitialize(g_buyDiv, EMPTY_VALUE);
      ArrayInitialize(g_sellDiv, EMPTY_VALUE);
      ArrayInitialize(g_longSig, EMPTY_VALUE);
      ArrayInitialize(g_shortSig, EMPTY_VALUE);
      ArrayInitialize(g_hist, EMPTY_VALUE);
   }
   
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   if(start < minB) start = minB;
   
   double src[], diff[];
   ArrayResize(src, rates_total);
   ArrayResize(diff, rates_total);
   for(int i = 0; i < rates_total; i++)
      src[i] = GetPrice(o[i], h[i], l[i], c[i], InpSrc);
   
   // ── MAIN LOOP ────────────────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      g_buyDiv[i] = EMPTY_VALUE;
      g_sellDiv[i] = EMPTY_VALUE;
      g_longSig[i] = EMPTY_VALUE;
      g_shortSig[i] = EMPTY_VALUE;
      g_bbUpper[i] = EMPTY_VALUE;
      g_bbMiddle[i] = EMPTY_VALUE;
      g_bbLower[i] = EMPTY_VALUE;
      
      // WT Core: esa = MA(src, n1), d = MA(|src - esa|, n1)
      g_esaBuf[i] = GetMA(src, InpN1, i - InpN1 + 1, InpMAType);
      
      for(int j = 0; j <= i; j++)
         diff[j] = MathAbs(src[j] - g_esaBuf[j]);
      g_dBuf[i] = GetMA(diff, InpN1, i - InpN1 + 1, InpMAType);
      
      // ci = (src - esa) / (0.015 * d)
      if(g_dBuf[i] > 1e-10)
         g_ciBuf[i] = (src[i] - g_esaBuf[i]) / (0.015 * g_dBuf[i]);
      else
         g_ciBuf[i] = 0;
      
      // wt1 = MA(ci, n2), wt2 = SMA(wt1, 4)
      g_wt1[i] = GetMA(g_ciBuf, InpN2, i - InpN2 + 1, InpMAType);
      g_wt2[i] = GetMA(g_wt1, 4, i - 3, MODE_SMA);
      
      // Histogram = wt1 - wt2 (for direction visualization)
      g_hist[i] = g_wt1[i] - g_wt2[i];
      
      // Bollinger Bands on wt1
      g_bbMiddle[i] = GetMA(g_wt1, InpBBLen, i - InpBBLen + 1, MODE_SMA);
      double bbStd = StdDev(g_wt1, InpBBLen, i - InpBBLen + 1);
      if(InpShowBB)
      {
         g_bbUpper[i] = g_bbMiddle[i] + bbStd * InpBBMult;
         g_bbLower[i] = g_bbMiddle[i] - bbStd * InpBBMult;
      }
      
      // Dynamic Bands (percentile-based)
      g_ub[i] = PercentileLI(g_wt1, InpCycMem, 100 - InpLeveling, MathMax(0, i - InpCycMem + 1));
      g_db[i] = PercentileLI(g_wt1, InpCycMem, InpLeveling, MathMax(0, i - InpCycMem + 1));
      
      double rangeVal = g_ub[i] - g_db[i];
      g_fib50[i] = (g_ub[i] + g_db[i]) / 2;
      
      // Static levels
      g_zeroLine[i] = 0;
      g_plus60[i]  = 60;
      g_minus60[i] = -60;
      
      // ── Divergence Detection ──
      if(i >= InpDivLeft + InpDivRight)
      {
         int pIdx = i - InpDivRight;
         if(IsPivotHigh(g_wt1, InpDivLeft, InpDivRight, pIdx))
            DetectDiv(true, pIdx, i, g_wt1, t);
         if(IsPivotLow(g_wt1, InpDivLeft, InpDivRight, pIdx))
            DetectDiv(false, pIdx, i, g_wt1, t);
      }
      
      // ── Simple Signals (Dynamic Cross) ──
      if(InpShowSignals && i > 0)
      {
         bool longSig  = (g_wt1[i-1] <= g_db[i-1] && g_wt1[i] > g_db[i]) ||
                         (g_wt1[i-1] <= g_bbLower[i-1] && g_wt1[i] > g_bbLower[i]);
         bool shortSig = (g_wt1[i-1] >= g_ub[i-1] && g_wt1[i] < g_ub[i]) ||
                         (g_wt1[i-1] >= g_bbUpper[i-1] && g_wt1[i] < g_bbUpper[i]);
         
         double markerOffset = 4.0;
         g_longSig[i]  = longSig  ? g_wt1[i] - markerOffset : EMPTY_VALUE;
         g_shortSig[i] = shortSig ? g_wt1[i] + markerOffset : EMPTY_VALUE;
         
         if(InpShowAlerts && i == rates_total - 1)
         {
            if(longSig && !g_prevBuy)
               Alert("WT LONG | ", _Symbol, " | WT1=", DoubleToString(g_wt1[i], 2));
            if(shortSig && !g_prevSell)
               Alert("WT SHORT | ", _Symbol, " | WT1=", DoubleToString(g_wt1[i], 2));
            g_prevBuy = longSig; g_prevSell = shortSig;
         }
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Divergence Detection                                              |
//+------------------------------------------------------------------+
void DetectDiv(bool isHi, int pIdx, int curIdx, double &wt[], const datetime &t[])
{
   static double lastHiPrice=0, lastHiOsc=0;
   static int    lastHiIdx=-1;
   static double lastLoPrice=0, lastLoOsc=0;
   static int    lastLoIdx=-1;
   static int    divCount=0;
   
   if(divCount >= InpMaxDivLines * 4) return;
   
   if(isHi)
   {
      double curOsc = wt[pIdx];
      if(lastHiIdx >= 0 && (pIdx - lastHiIdx) < InpMaxPivBars)
      {
         // Regular Bearish Divergence
         if(curOsc < lastHiOsc)
            DrawDivLine("RB_", lastHiIdx, lastHiOsc, pIdx, curOsc, clrRed, STYLE_SOLID, 2, t, divCount);
         // Hidden Bearish
         if(curOsc > lastHiOsc)
            DrawDivLine("HB_", lastHiIdx, lastHiOsc, pIdx, curOsc, clrMaroon, STYLE_DASH, 2, t, divCount);
      }
      lastHiOsc = curOsc; lastHiIdx = pIdx;
   }
   else
   {
      double curOsc = wt[pIdx];
      if(lastLoIdx >= 0 && (pIdx - lastLoIdx) < InpMaxPivBars)
      {
         // Regular Bullish Div
         if(curOsc > lastLoOsc)
         {
            g_buyDiv[pIdx] = wt[pIdx] * 0.85;
            DrawDivLine("RB_", lastLoIdx, lastLoOsc, pIdx, curOsc, clrLime, STYLE_SOLID, 2, t, divCount);
         }
         // Hidden Bullish
         if(curOsc < lastLoOsc)
            DrawDivLine("HB_", lastLoIdx, lastLoOsc, pIdx, curOsc, C'0x32,0xCD,0x32', STYLE_DASH, 2, t, divCount);
      }
      lastLoOsc = curOsc; lastLoIdx = pIdx;
   }
}

//+------------------------------------------------------------------+
//| Draw divergence trend line                                        |
//+------------------------------------------------------------------+
void DrawDivLine(string typ, int i1, double v1, int i2, double v2,
                 color clr, ENUM_LINE_STYLE st, int w, const datetime &t[], int &cnt)
{
   if(!InpShowDivLines) return;
   
   string nm = g_prefix + typ + IntegerToString(i2);
   if(ObjectFind(1, nm) >= 0) return;
   
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   int s1 = totalBars - i1 - 1, s2 = totalBars - i2 - 1;
   
   datetime barT[];
   ArraySetAsSeries(barT, true);
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, totalBars, barT) <= 0) return;
   if(s1 >= ArraySize(barT) || s2 >= ArraySize(barT)) return;
   
   ObjectCreate(1, nm, OBJ_TREND, 1, barT[s1], v1, barT[s2], v2);
   ObjectSetInteger(1, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(1, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(1, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(1, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(1, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(1, nm, OBJPROP_HIDDEN, true);
   cnt++;
}

void CleanupObjects()
{
   for(int i = ObjectsTotal(1) - 1; i >= 0; i--)
   {
      string n = ObjectName(1, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(1, n);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
