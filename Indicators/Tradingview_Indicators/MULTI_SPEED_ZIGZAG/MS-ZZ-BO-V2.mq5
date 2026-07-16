//+------------------------------------------------------------------+
//|                              Multi-Speed ZigZag Breakouts Ind.mq5 |
//|                    Ported from Pine Script v6 → MQL5              |
//|                    Original: MS-ZZ-BO-V2-STRAT.pine              |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: Multi-Speed ZigZag Trendline Breakouts ::"
#property description "Three-speed ZigZag detection (Fast/Med/Slow) with"
#property description "trendline drawing, pivot markers, and breakout signals."

#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots   9

// ── Plots ───────────────────────────────────────────────────────────────────
#property indicator_label1  "Fast Pivot High"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'0x08,0x99,0x81'  // Teal-green
#property indicator_width1  1

#property indicator_label2  "Fast Pivot Low"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'0xF2,0x36,0x45'  // Red
#property indicator_width2  1

#property indicator_label3  "Med Pivot High"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'0x29,0x62,0xFF'  // Blue
#property indicator_width3  1

#property indicator_label4  "Med Pivot Low"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'0xFF,0x6D,0x00'  // Orange
#property indicator_width4  1

#property indicator_label5  "Slow Pivot High"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  C'0x9C,0x27,0xB0'  // Purple
#property indicator_width5  1

#property indicator_label6  "Slow Pivot Low"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  C'0xE9,0x1E,0x63'  // Pink
#property indicator_width6  1

#property indicator_label7  "Fast Break Buy"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrLime
#property indicator_width7  2

#property indicator_label8  "Fast Break Sell"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrRed
#property indicator_width8  2

#property indicator_label9  "Med Break Buy"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrLime
#property indicator_width9  2

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Fast Speed ═══"
input bool                         InpFastEnable   = true;               // Enable Fast Speed
input int                          InpFastATRLen   = 14;                 // Fast ATR Length
input double                       InpFastATRMult  = 1.0;                // Fast ATR Multiplier

input group                        "═══ Medium Speed ═══"
input bool                         InpMedEnable    = true;               // Enable Medium Speed
input int                          InpMedATRLen    = 14;                 // Medium ATR Length
input double                       InpMedATRMult   = 2.0;                // Medium ATR Multiplier

input group                        "═══ Slow Speed ═══"
input bool                         InpSlowEnable   = true;               // Enable Slow Speed
input int                          InpSlowATRLen   = 14;                 // Slow ATR Length
input double                       InpSlowATRMult  = 3.5;                // Slow ATR Multiplier

input group                        "═══ Quality & Filters ═══"
input bool                         InpRequireConf  = true;               // Require Multi-Speed Confluence
input bool                         InpAlignTrend   = true;               // Align with Slow Trend
input int                          InpMinBarsBtwn  = 3;                  // Min Bars Between Pivots

input group                        "═══ Visuals ═══"
input bool                         InpShowPivots   = true;               // Show Pivot Markers
input bool                         InpShowLines    = true;               // Show Trendlines
input bool                         InpShowBreaks   = true;               // Show Breakout Signals
input bool                         InpShowAlerts   = true;               // Enable Alerts

input group                        "═══ Trendline Management ═══"
input int                          InpMaxLineLength = 500;               // Max Trendline Length in bars (0=unlimited)
input bool                         InpBreakOnClose  = true;              // Freeze Line When Price Closes Through Extension
input int                          InpMaxActiveLines = 200;              // Max Simultaneous Trendlines (perf safeguard)
input color                        InpBrokenLineColor = clrGray;         // Broken Trendline Color
input bool                         InpDimBrokenLines  = true;            // Dim Broken Trendlines

input group                        "═══ Line Aging / Fading ═══"
input bool                         InpEnableFade      = true;            // Enable Age-Based Fading
input int                          InpFadeStartBars   = 50;              // Bars After Finalization Before Fade Begins
input int                          InpFadeDurationBars = 100;            // Bars Over Which Fade Completes
input color                        InpFadeToColor     = clrNONE;         // Fade-To Color (clrNONE = auto-detect background)

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_fastPH[];    // 0  Fast pivot high markers
double g_fastPL[];    // 1  Fast pivot low markers
double g_medPH[];     // 2
double g_medPL[];     // 3
double g_slowPH[];    // 4
double g_slowPL[];    // 5
double g_fastBuy[];   // 6
double g_fastSell[];  // 7
double g_medBuy[];    // 8
// Calc buffers
double g_atrFast[];   // 9
double g_atrMed[];    // 10
double g_atrSlow[];   // 11

string g_prefix = "MSZZ_";
bool   g_prevBuy, g_prevSell;

// ── Trendline state tracking ────────────────────────────────────────────────
struct TrendLineState
{
   int      startIdx;
   double   startPrice;
   int      endIdx;
   double   endPrice;
   int      lastScannedIdx;
   bool     finalized;
   string   objName;
   bool     isActive;
   color    originalColor;  // preserved for fade calculations
};

TrendLineState g_lines[];
int            g_lineCount = 0;

struct PivotState
{
   int    lastPHIdx, lastPLIdx;
   double lastPHVal, lastPLVal;
};

PivotState g_fastPivot, g_medPivot, g_slowPivot;

//+------------------------------------------------------------------+
//| ATR helper                                                        |
//+------------------------------------------------------------------+
double ATR(const double &h[], const double &l[], const double &c[], int p, int idx)
{
   if(idx < p) return 0;
   double sum = 0;
   for(int i = idx-p+1; i <= idx; i++)
      sum += MathMax(h[i]-l[i], MathMax(MathAbs(h[i]-c[i-1]), MathAbs(l[i]-c[i-1])));
   return sum/p;
}

//+------------------------------------------------------------------+
//| Check if bar is a pivot high (ZigZag style)                       |
//+------------------------------------------------------------------+
bool IsZZHigh(const double &h[], int idx, double threshold)
{
   int sz = ArraySize(h);
   if(idx <= 0 || idx >= sz-1) return false;
   double val = h[idx];
   for(int i = idx-1; i >= MathMax(0, idx-100); i--)
   {
      if(h[i] > val) return false;
      if(val - h[i] >= threshold) break;
   }
   for(int i = idx+1; i < MathMin(sz, idx+100); i++)
   {
      if(h[i] > val) return false;
      if(val - h[i] >= threshold) break;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a pivot low (ZigZag style)                        |
//+------------------------------------------------------------------+
bool IsZZLow(const double &l[], int idx, double threshold)
{
   int sz = ArraySize(l);
   if(idx <= 0 || idx >= sz-1) return false;
   double val = l[idx];
   for(int i = idx-1; i >= MathMax(0, idx-100); i--)
   {
      if(l[i] < val) return false;
      if(l[i] - val >= threshold) break;
   }
   for(int i = idx+1; i < MathMin(sz, idx+100); i++)
   {
      if(l[i] < val) return false;
      if(l[i] - val >= threshold) break;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trendline helpers (forward declarations for OnCalculate)          |
//+------------------------------------------------------------------+
void CreateTrendLine(string name, int i1, double v1, int i2, double v2,
                     const datetime &time[], color clr, ENUM_LINE_STYLE st, int w)
{
   int size = ArraySize(time);
   if(i1 < 0 || i1 >= size || i2 < 0 || i2 >= size) return;
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectCreate(0, name, OBJ_TREND, 0, time[i1], v1, time[i2], v2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void ExtendTrendLine(string name, int endIdx, double endPrice, const datetime &time[])
{
   if(endIdx < 0 || endIdx >= ArraySize(time)) return;
   ObjectMove(0, name, 1, time[endIdx], endPrice);
}

void RegisterTrendLine(int startIdx, double startPrice, int endIdx, double endPrice,
                       string objName, bool isActive, int maxLines, color origColor)
{
   if(g_lineCount >= maxLines)
   {
      int oldestFinalized = -1, oldestIdx = -1;
      for(int i = 0; i < g_lineCount; i++)
      {
         if(!g_lines[i].isActive && g_lines[i].finalized &&
            (g_lines[i].startIdx < oldestIdx || oldestIdx == -1))
         { oldestFinalized = i; oldestIdx = g_lines[i].startIdx; }
      }
      if(oldestFinalized >= 0)
      {
         if(ObjectFind(0, g_lines[oldestFinalized].objName) >= 0)
            ObjectDelete(0, g_lines[oldestFinalized].objName);
         for(int i = oldestFinalized; i < g_lineCount - 1; i++)
            g_lines[i] = g_lines[i + 1];
         g_lineCount--;
      }
   }
   TrendLineState tl;
   tl.startIdx = startIdx; tl.startPrice = startPrice;
   tl.endIdx = endIdx; tl.endPrice = endPrice;
   tl.lastScannedIdx = endIdx; tl.finalized = false;
   tl.objName = objName; tl.isActive = isActive;
   tl.originalColor = origColor;
   if(g_lineCount >= ArraySize(g_lines)) ArrayResize(g_lines, g_lineCount + 64);
   g_lines[g_lineCount] = tl; g_lineCount++;
}

void FinalizeActiveLinesForSpeed(string speedPrefix)
{
   int prefixLen = StringLen(g_prefix);
   for(int i = 0; i < g_lineCount; i++)
   {
      if(g_lines[i].isActive &&
         StringFind(g_lines[i].objName, speedPrefix) == prefixLen)
      { g_lines[i].isActive = false; g_lines[i].finalized = true; }
   }
}

void AdvanceActiveLines(const double &close[], const datetime &time[],
                        int lastIdx, const double &high[], const double &low[])
{
   for(int i = 0; i < g_lineCount; i++)
   {
      if(!g_lines[i].isActive || g_lines[i].finalized) continue;
      int scanFrom = g_lines[i].lastScannedIdx + 1;
      bool broken = false; int breakBar = -1;
      if(InpBreakOnClose && scanFrom <= lastIdx)
      {
         bool isRising = (g_lines[i].endPrice > g_lines[i].startPrice);
         for(int j = scanFrom; j <= lastIdx; j++)
         {
            double span = (double)(g_lines[i].endIdx - g_lines[i].startIdx);
            if(span <= 0) break;
            double frac = (double)(j - g_lines[i].startIdx) / span;
            double linePriceAtJ = g_lines[i].startPrice +
                                  (g_lines[i].endPrice - g_lines[i].startPrice) * frac;
            bool crossed = isRising ? (low[j] <= linePriceAtJ)
                                    : (high[j] >= linePriceAtJ);
            if(crossed) { broken = true; breakBar = j; break; }
         }
      }
      int barSpan = lastIdx - g_lines[i].endIdx;
      bool capped = (InpMaxLineLength > 0 && barSpan >= InpMaxLineLength);
      if(broken || capped)
      {
         g_lines[i].finalized = true; g_lines[i].isActive = false;
         int freezeIdx = broken ? breakBar : g_lines[i].endIdx + InpMaxLineLength;
         if(freezeIdx > lastIdx) freezeIdx = lastIdx;
         if(freezeIdx >= 0 && freezeIdx < ArraySize(time))
         {
            double span2 = (double)(g_lines[i].endIdx - g_lines[i].startIdx);
            double frac2 = (span2 > 0) ? (double)(freezeIdx - g_lines[i].startIdx) / span2 : 1.0;
            double freezePrice = g_lines[i].startPrice +
                                 (g_lines[i].endPrice - g_lines[i].startPrice) * frac2;
            ExtendTrendLine(g_lines[i].objName, freezeIdx, freezePrice, time);
         }
         if(InpDimBrokenLines && !InpEnableFade)
            ObjectSetInteger(0, g_lines[i].objName, OBJPROP_COLOR, InpBrokenLineColor);
      }
      else
      {
         double span2 = (double)(g_lines[i].endIdx - g_lines[i].startIdx);
         double frac2 = (span2 > 0) ? (double)(lastIdx - g_lines[i].startIdx) / span2 : 1.0;
         double linePrice = g_lines[i].startPrice +
                            (g_lines[i].endPrice - g_lines[i].startPrice) * frac2;
         ExtendTrendLine(g_lines[i].objName, lastIdx, linePrice, time);
      }
      g_lines[i].lastScannedIdx = lastIdx;
   }
}

//+------------------------------------------------------------------+
//| Linearly interpolate between two RGB colors                       |
//+------------------------------------------------------------------+
color LerpColor(color fromColor, color toColor, double t)
{
   if(t <= 0.0) return fromColor;
   if(t >= 1.0) return toColor;

   int r1 = (fromColor >> 16) & 0xFF;
   int g1 = (fromColor >> 8)  & 0xFF;
   int b1 =  fromColor        & 0xFF;

   int r2 = (toColor >> 16) & 0xFF;
   int g2 = (toColor >> 8)  & 0xFF;
   int b2 =  toColor        & 0xFF;

   int r = r1 + (int)((r2 - r1) * t);
   int g = g1 + (int)((g2 - g1) * t);
   int b = b1 + (int)((b2 - b1) * t);

   return (color)((r << 16) | (g << 8) | b);
}

//+------------------------------------------------------------------+
//| Apply age-based color fading to all finalized lines               |
//+------------------------------------------------------------------+
void ApplyFading(int currentBar, color fadeToColor)
{
   if(!InpEnableFade) return;
   int fadeEnd = InpFadeStartBars + InpFadeDurationBars;
   if(fadeEnd <= 0) return;

   for(int i = 0; i < g_lineCount; i++)
   {
      if(!g_lines[i].finalized || g_lines[i].isActive) continue;

      int age = currentBar - g_lines[i].endIdx;
      if(age < 0) age = 0;

      double t = 0.0;
      if(age > InpFadeStartBars)
      {
         if(InpFadeDurationBars > 0)
            t = (double)(age - InpFadeStartBars) / (double)InpFadeDurationBars;
         else
            t = 1.0;
         if(t > 1.0) t = 1.0;
      }

      color fadedColor = LerpColor(g_lines[i].originalColor, fadeToColor, t);
      ObjectSetInteger(0, g_lines[i].objName, OBJPROP_COLOR, fadedColor);
   }
}

//+------------------------------------------------------------------+
//| Prune off-screen finalized lines                                  |
//+------------------------------------------------------------------+
void PruneOffScreenLines(int currentBar, int retentionBars)
{
   for(int i = g_lineCount - 1; i >= 0; i--)
   {
      if(!g_lines[i].finalized || g_lines[i].isActive) continue;
      if(currentBar - g_lines[i].endIdx > retentionBars)
      {
         if(ObjectFind(0, g_lines[i].objName) >= 0)
            ObjectDelete(0, g_lines[i].objName);
         for(int j = i; j < g_lineCount - 1; j++) g_lines[j] = g_lines[j + 1];
         g_lineCount--;
      }
   }
}

void CleanAllLines()
{
   for(int i = 0; i < g_lineCount; i++)
      if(ObjectFind(0, g_lines[i].objName) >= 0)
         ObjectDelete(0, g_lines[i].objName);
   g_lineCount = 0; ArrayFree(g_lines);
}

void CleanupObjects()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   { string n = ObjectName(0, i); if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n); }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_fastPH,   INDICATOR_DATA);
   SetIndexBuffer(1, g_fastPL,   INDICATOR_DATA);
   SetIndexBuffer(2, g_medPH,    INDICATOR_DATA);
   SetIndexBuffer(3, g_medPL,    INDICATOR_DATA);
   SetIndexBuffer(4, g_slowPH,   INDICATOR_DATA);
   SetIndexBuffer(5, g_slowPL,   INDICATOR_DATA);
   SetIndexBuffer(6, g_fastBuy,  INDICATOR_DATA);
   SetIndexBuffer(7, g_fastSell, INDICATOR_DATA);
   SetIndexBuffer(8, g_medBuy,   INDICATOR_DATA);
   SetIndexBuffer(9, g_atrFast,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,g_atrMed,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,g_atrSlow,  INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(0, PLOT_ARROW, 108); PlotIndexSetInteger(1, PLOT_ARROW, 108);
   PlotIndexSetInteger(2, PLOT_ARROW, 108); PlotIndexSetInteger(3, PLOT_ARROW, 108);
   PlotIndexSetInteger(4, PLOT_ARROW, 108); PlotIndexSetInteger(5, PLOT_ARROW, 108);
   PlotIndexSetInteger(6, PLOT_ARROW, 241); PlotIndexSetInteger(7, PLOT_ARROW, 242);
   PlotIndexSetInteger(8, PLOT_ARROW, 241);
   for(int p = 0; p < 9; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "MS-ZZ-BO V2");
   g_prevBuy = false; g_prevSell = false;
   ZeroMemory(g_fastPivot); ZeroMemory(g_medPivot); ZeroMemory(g_slowPivot);
   g_fastPivot.lastPHIdx = -1; g_fastPivot.lastPLIdx = -1;
   g_medPivot.lastPHIdx  = -1; g_medPivot.lastPLIdx  = -1;
   g_slowPivot.lastPHIdx = -1; g_slowPivot.lastPLIdx = -1;
   ArrayResize(g_lines, 64); g_lineCount = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   CleanupObjects();
   g_lineCount = 0; ArrayFree(g_lines);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calc,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &v[], const int &sp[])
{
   int minB = MathMax(InpSlowATRLen, MathMax(InpFastATRLen, InpMedATRLen)) + 100;
   if(rates_total < minB) return 0;
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   if(start < minB) start = minB;

   // Reset state on chart reload
   if(prev_calc == 0)
   {
      ZeroMemory(g_fastPivot); ZeroMemory(g_medPivot); ZeroMemory(g_slowPivot);
      g_fastPivot.lastPHIdx = -1; g_fastPivot.lastPLIdx = -1;
      g_medPivot.lastPHIdx  = -1; g_medPivot.lastPLIdx  = -1;
      g_slowPivot.lastPHIdx = -1; g_slowPivot.lastPLIdx = -1;
      CleanAllLines(); CleanupObjects();
      g_prevBuy = false; g_prevSell = false;
   }

   int lastIdx = rates_total - 1;

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      double atrF = ATR(h, l, c, InpFastATRLen, i);
      double atrM = ATR(h, l, c, InpMedATRLen, i);
      double atrS = ATR(h, l, c, InpSlowATRLen, i);
      g_atrFast[i] = atrF; g_atrMed[i] = atrM; g_atrSlow[i] = atrS;
      double threshF = atrF * InpFastATRMult;
      double threshM = atrM * InpMedATRMult;
      double threshS = atrS * InpSlowATRMult;

      // ── Fast Speed ──
      if(InpFastEnable)
      {
         if(IsZZHigh(h, i, threshF) &&
            (i - g_fastPivot.lastPHIdx > InpMinBarsBtwn || g_fastPivot.lastPHIdx < 0))
         {
            g_fastPH[i] = h[i];
            g_fastPivot.lastPHIdx = i; g_fastPivot.lastPHVal = h[i];
            if(g_fastPivot.lastPLIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("F_");
               string nm = g_prefix + "F_SUP_" + IntegerToString(i);
               CreateTrendLine(nm, g_fastPivot.lastPLIdx, g_fastPivot.lastPLVal,
                               i, h[i], t, C'0x08,0x99,0x81', STYLE_SOLID, 1);
               RegisterTrendLine(g_fastPivot.lastPLIdx, g_fastPivot.lastPLVal,
                                 i, h[i], nm, true, InpMaxActiveLines, C'0x08,0x99,0x81');
            }
         }
         if(IsZZLow(l, i, threshF) &&
            (i - g_fastPivot.lastPLIdx > InpMinBarsBtwn || g_fastPivot.lastPLIdx < 0))
         {
            g_fastPL[i] = l[i];
            g_fastPivot.lastPLIdx = i; g_fastPivot.lastPLVal = l[i];
            if(g_fastPivot.lastPHIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("F_");
               string nm = g_prefix + "F_RES_" + IntegerToString(i);
               CreateTrendLine(nm, g_fastPivot.lastPHIdx, g_fastPivot.lastPHVal,
                               i, l[i], t, C'0xF2,0x36,0x45', STYLE_SOLID, 1);
               RegisterTrendLine(g_fastPivot.lastPHIdx, g_fastPivot.lastPHVal,
                                 i, l[i], nm, true, InpMaxActiveLines, C'0xF2,0x36,0x45');
            }
         }
      }

      // ── Medium Speed ──
      if(InpMedEnable)
      {
         if(IsZZHigh(h, i, threshM) &&
            (i - g_medPivot.lastPHIdx > InpMinBarsBtwn || g_medPivot.lastPHIdx < 0))
         {
            g_medPH[i] = h[i];
            g_medPivot.lastPHIdx = i; g_medPivot.lastPHVal = h[i];
            if(g_medPivot.lastPLIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("M_");
               string nm = g_prefix + "M_SUP_" + IntegerToString(i);
               CreateTrendLine(nm, g_medPivot.lastPLIdx, g_medPivot.lastPLVal,
                               i, h[i], t, C'0x29,0x62,0xFF', STYLE_DASH, 1);
               RegisterTrendLine(g_medPivot.lastPLIdx, g_medPivot.lastPLVal,
                                 i, h[i], nm, true, InpMaxActiveLines, C'0x29,0x62,0xFF');
            }
         }
         if(IsZZLow(l, i, threshM) &&
            (i - g_medPivot.lastPLIdx > InpMinBarsBtwn || g_medPivot.lastPLIdx < 0))
         {
            g_medPL[i] = l[i];
            g_medPivot.lastPLIdx = i; g_medPivot.lastPLVal = l[i];
            if(g_medPivot.lastPHIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("M_");
               string nm = g_prefix + "M_RES_" + IntegerToString(i);
               CreateTrendLine(nm, g_medPivot.lastPHIdx, g_medPivot.lastPHVal,
                               i, l[i], t, C'0xFF,0x6D,0x00', STYLE_DASH, 1);
               RegisterTrendLine(g_medPivot.lastPHIdx, g_medPivot.lastPHVal,
                                 i, l[i], nm, true, InpMaxActiveLines, C'0xFF,0x6D,0x00');
            }
         }
      }

      // ── Slow Speed ──
      if(InpSlowEnable)
      {
         if(IsZZHigh(h, i, threshS) &&
            (i - g_slowPivot.lastPHIdx > InpMinBarsBtwn || g_slowPivot.lastPHIdx < 0))
         {
            g_slowPH[i] = h[i];
            g_slowPivot.lastPHIdx = i; g_slowPivot.lastPHVal = h[i];
            if(g_slowPivot.lastPLIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("S_");
               string nm = g_prefix + "S_SUP_" + IntegerToString(i);
               CreateTrendLine(nm, g_slowPivot.lastPLIdx, g_slowPivot.lastPLVal,
                               i, h[i], t, C'0x9C,0x27,0xB0', STYLE_DOT, 1);
               RegisterTrendLine(g_slowPivot.lastPLIdx, g_slowPivot.lastPLVal,
                                 i, h[i], nm, true, InpMaxActiveLines, C'0x9C,0x27,0xB0');
            }
         }
         if(IsZZLow(l, i, threshS) &&
            (i - g_slowPivot.lastPLIdx > InpMinBarsBtwn || g_slowPivot.lastPLIdx < 0))
         {
            g_slowPL[i] = l[i];
            g_slowPivot.lastPLIdx = i; g_slowPivot.lastPLVal = l[i];
            if(g_slowPivot.lastPHIdx >= 0 && InpShowLines)
            {
               FinalizeActiveLinesForSpeed("S_");
               string nm = g_prefix + "S_RES_" + IntegerToString(i);
               CreateTrendLine(nm, g_slowPivot.lastPHIdx, g_slowPivot.lastPHVal,
                               i, l[i], t, C'0xE9,0x1E,0x63', STYLE_DOT, 1);
               RegisterTrendLine(g_slowPivot.lastPHIdx, g_slowPivot.lastPHVal,
                                 i, l[i], nm, true, InpMaxActiveLines, C'0xE9,0x1E,0x63');
            }
         }
      }

      // ── Breakout Signals ──
      if(InpShowBreaks && InpFastEnable && i > 5)
      {
         if(g_fastPivot.lastPHIdx >= 0 && c[i] > g_fastPivot.lastPHVal &&
            c[i-1] <= g_fastPivot.lastPHVal)
            g_fastBuy[i] = l[i] * 0.998;
         if(g_fastPivot.lastPLIdx >= 0 && c[i] < g_fastPivot.lastPLVal &&
            c[i-1] >= g_fastPivot.lastPLVal)
            g_fastSell[i] = h[i] * 1.002;
         if(g_medPivot.lastPHIdx >= 0 && c[i] > g_medPivot.lastPHVal &&
            g_fastPivot.lastPHIdx >= 0 && c[i] > g_fastPivot.lastPHVal)
            g_medBuy[i] = l[i] * 0.995;
         if(InpShowAlerts && i == lastIdx)
         {
            bool b = (c[i] > g_fastPivot.lastPHVal && c[i-1] <= g_fastPivot.lastPHVal);
            bool s = (c[i] < g_fastPivot.lastPLVal && c[i-1] >= g_fastPivot.lastPLVal);
            if(b && !g_prevBuy)
               Alert("MS-ZZ BREAK LONG | ", _Symbol, " | ", DoubleToString(c[i], _Digits));
            if(s && !g_prevSell)
               Alert("MS-ZZ BREAK SHORT | ", _Symbol, " | ", DoubleToString(c[i], _Digits));
            g_prevBuy = b; g_prevSell = s;
         }
      }
   }

   // ── Trendline Lifecycle ──
   if(InpShowLines)
   {
      AdvanceActiveLines(c, t, lastIdx, h, l);

      // Apply age-based fading to finalized lines
      if(InpEnableFade)
      {
         color fadeTo = InpFadeToColor;
         if(fadeTo == clrNONE)
            fadeTo = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
         ApplyFading(lastIdx, fadeTo);
      }

      int retentionBars = InpMaxLineLength > 0 ? (InpMaxLineLength * 3) : 2000;
      PruneOffScreenLines(lastIdx, retentionBars);
   }
   else
   {
      if(g_lineCount > 0) CleanAllLines();
   }

   return rates_total;
}
//+------------------------------------------------------------------+
