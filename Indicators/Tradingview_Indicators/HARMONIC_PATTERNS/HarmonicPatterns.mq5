//+------------------------------------------------------------------+
//|                                                HarmonicPatterns.mq5 |
//|                              Advanced Harmonic Pattern Detector    |
//|                                   Ported from Pine → MQL5 (v2.00) |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script — IRUNTV"
#property version     "2.00"
#property description ":: Harmonic Pattern Detector ::"
#property description "Detects Gartley, Bat, Butterfly, Crab, Shark"
#property description "with PRZ zones and full leg drawing."
#property description "v2.00: Production-ready — all audit findings resolved"

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Bullish Pattern"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "Bearish Pattern"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ ZigZag Settings ═══"
input int                          InpZZDepth     = 12;                 // ZigZag Depth
input int                          InpZZDeviation = 5;                  // ZigZag Deviation
input int                          InpZZBackstep  = 3;                  // ZigZag Backstep

input group                        "═══ Pattern Detection ═══"
input double                       InpTolerance   = 0.05;               // Ratio Tolerance (e.g., 0.05 = ±5%)
input int                          InpMaxLegBars  = 200;                // Max Leg Bars
input int                          InpMinLegBars  = 3;                  // Min Leg Bars
input int                          InpConfirmationBars = 3;              // Bars to confirm D pivot (anti-repaint)

input group                        "═══ Pattern Selection ═══"
input bool                         InpGartley      = true;              // Detect Gartley
input bool                         InpBat          = true;              // Detect Bat
input bool                         InpButterfly    = true;              // Detect Butterfly
input bool                         InpCrab         = true;              // Detect Crab
input bool                         InpShark        = true;              // Detect Shark

input group                        "═══ Visuals ═══"
input bool                         InpShowLegs     = true;              // Show Pattern Legs
input bool                         InpShowPRZ      = true;              // Show PRZ Zone
input bool                         InpShowLabels   = true;              // Show Labels
input color                        InpBullColor    = clrLime;            // Bullish Color
input color                        InpBearColor    = clrRed;             // Bearish Color
input int                          InpLineWidth    = 2;                  // Line Width
input ENUM_LINE_STYLE              InpLineStyle    = STYLE_SOLID;        // Line Style

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_bullBuf[];     // Bullish signal buffer
double g_bearBuf[];     // Bearish signal buffer

// ── ZigZag handle ───────────────────────────────────────────────────────────
int g_zzHandle = INVALID_HANDLE;

// ── Instance-specific object prefix ─────────────────────────────────────────
string g_prefix;

// ── Last-drawn pattern ID to avoid duplicate objects on every tick ──────────
string   g_lastPatternId   = "";
string   g_lastPatternType = "";
datetime g_lastDTime       = 0;

// ── Pivot candidate structure (declared BEFORE first use — audit #1) ────────
struct PivCandidate
{
   bool     isHigh;
   double   price;
   datetime time;
   int      idx;
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // ── Input validation (audit #25) ──────────────────────────────────────
   if(InpZZDepth <= 0)
   {
      Print("HarmonicPatterns: InpZZDepth must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpZZBackstep < 0)
   {
      Print("HarmonicPatterns: InpZZBackstep must be >= 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinLegBars < 1)
   {
      Print("HarmonicPatterns: InpMinLegBars must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMaxLegBars < InpMinLegBars)
   {
      Print("HarmonicPatterns: InpMaxLegBars must be >= InpMinLegBars");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTolerance < 0.0 || InpTolerance >= 1.0)
   {
      Print("HarmonicPatterns: InpTolerance must be >= 0 and < 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpConfirmationBars < 1)
   {
      Print("HarmonicPatterns: InpConfirmationBars must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // ── Instance-specific object prefix (audit #21) ───────────────────────
   g_prefix = StringFormat("HP_%I64d_%s_%d_",
                            ChartID(), _Symbol, (int)_Period);

   // ── Register indicator buffers (audit #3) ─────────────────────────────
   SetIndexBuffer(0, g_bullBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_bearBuf, INDICATOR_DATA);

   ArraySetAsSeries(g_bullBuf, true);
   ArraySetAsSeries(g_bearBuf, true);

   ArrayInitialize(g_bullBuf, EMPTY_VALUE);
   ArrayInitialize(g_bearBuf, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);               // thumbs up
   PlotIndexSetInteger(1, PLOT_ARROW, 234);               // thumbs down
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // ── Create ZigZag indicator handle ────────────────────────────────────
   g_zzHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag",
                         InpZZDepth, InpZZDeviation, InpZZBackstep);
   if(g_zzHandle == INVALID_HANDLE)
   {
      Print("HarmonicPatterns: Failed to create ZigZag handle. Trying built-in ZigZag...");
      g_zzHandle = iCustom(_Symbol, _Period, "ZigZag",
                            InpZZDepth, InpZZDeviation, InpZZBackstep);
      if(g_zzHandle == INVALID_HANDLE)
      {
         Print("HarmonicPatterns: ZigZag not available. Using manual pivot detection.");
      }
   }

   // Clean up any leftover objects from previous run
   CleanupObjects();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_zzHandle != INVALID_HANDLE)
      IndicatorRelease(g_zzHandle);
   CleanupObjects();
}

//+------------------------------------------------------------------+
//| Clean up all pattern objects for this instance                   |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < InpZZDepth + InpMaxLegBars) return(0);

   // ── Establish series orientation for all price/time arrays (audit #4) ──
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   // open, close, tick_volume, volume, spread not used; left as-is

   // ── Initialize buffers with EMPTY_VALUE for new bars (audit #3) ───────
   for(int i = prev_calculated; i < rates_total; i++)
   {
      g_bullBuf[i] = EMPTY_VALUE;
      g_bearBuf[i] = EMPTY_VALUE;
   }

   // ── Check if ZigZag has calculated (audit #17) ────────────────────────
   if(g_zzHandle != INVALID_HANDLE)
   {
      int zzCalculated = BarsCalculated(g_zzHandle);
      if(zzCalculated <= 0)
         return(prev_calculated);
   }

   // ── Get ZigZag values — limited scope (audit #16) ─────────────────────
   double zzBuf[];
   int zzLookback = MathMin(rates_total, InpMaxLegBars * 5 + InpZZDepth + 20);

   if(g_zzHandle != INVALID_HANDLE)
   {
      ResetLastError();
      ArraySetAsSeries(zzBuf, true);
      int copied = CopyBuffer(g_zzHandle, 0, 0, zzLookback, zzBuf);
      if(copied <= 0)
      {
         // Diagnose and throttle error logging (audit #18)
         static int zzFailCount = 0;
         if(zzFailCount < 3)
         {
            int err = GetLastError();
            PrintFormat("[%s %s] ZigZag CopyBuffer failed: error=%d",
                        _Symbol, EnumToString(_Period), err);
            zzFailCount++;
         }
         ArrayFree(zzBuf);
      }
   }

   // ── Find last 5 swing points with bar indices ─────────────────────────
   int swingCount = 0;
   double swingPrice[5];
   datetime swingTime[5];
   int swingIdx[5];           // bar indices for leg-length validation

   if(ArraySize(zzBuf) > 0)
   {
      // ZigZag buffer is series: index 0 = newest bar
      int lookback = MathMin(rates_total, InpMaxLegBars * 5 + InpZZDepth + 10);
      double prevVal = 0.0;

      for(int i = 2; i < lookback && swingCount < 5; i++)
      {
         double val = zzBuf[i];

         // Tolerance-based comparison instead of exact equality (audit #26, #27)
         if(val != 0.0 && val != EMPTY_VALUE && MathIsValidNumber(val)
            && MathAbs(val - prevVal) > _Point * 0.5)
         {
            swingPrice[swingCount] = val;
            swingTime[swingCount] = time[i];   // series: time[i] ↔ zzBuf[i] (audit #4 fix)
            swingIdx[swingCount]  = i;
            swingCount++;
            prevVal = val;
         }
      }
   }

   // If ZigZag failed or didn't find enough points, use manual pivots
   if(swingCount < 5)
   {
      swingCount = 0;
      // No ArrayResize on static arrays (audit #2 fix)
      FindManualSwingPoints(rates_total, time, high, low,
                            swingPrice, swingTime, swingIdx, swingCount);
   }

   if(swingCount < 5) return(rates_total);

   // Last 5 points: most recent = D (0), then C (1), B (2), A (3), X (4)
   double   X = swingPrice[4], A = swingPrice[3], B = swingPrice[2],
            C = swingPrice[1], D = swingPrice[0];
   datetime tX = swingTime[4],  tA = swingTime[3],  tB = swingTime[2],
            tC = swingTime[1],  tD = swingTime[0];
   int      iX = swingIdx[4],   iA = swingIdx[3],   iB = swingIdx[2],
            iC = swingIdx[1],   iD = swingIdx[0];

   // ── Validate leg bar distances (audit #11) ────────────────────────────
   int barsXA = MathAbs(iX - iA);
   int barsAB = MathAbs(iA - iB);
   int barsBC = MathAbs(iB - iC);
   int barsCD = MathAbs(iC - iD);

   if(barsXA < InpMinLegBars || barsXA > InpMaxLegBars ||
      barsAB < InpMinLegBars || barsAB > InpMaxLegBars ||
      barsBC < InpMinLegBars || barsBC > InpMaxLegBars ||
      barsCD < InpMinLegBars || barsCD > InpMaxLegBars)
   {
      return(rates_total);
   }

   // ── Validate zigzag pattern: X→A→B→C→D alternating ────────────────────
   bool isBullishPattern = (X < A && A > B && B < C && C > D);
   bool isBearishPattern = (X > A && A < B && B > C && C < D);

   if(!isBullishPattern && !isBearishPattern) return(rates_total);

   // ── Anti-repaint: D must be confirmed (audit #12) ─────────────────────
   if(iD < InpConfirmationBars)
   {
      // D is too recent — ZigZag may still repaint. Skip.
      return(rates_total);
   }

   // ── Check and draw patterns ───────────────────────────────────────────
   CheckAndDrawPattern(X, A, B, C, D,
                       tX, tA, tB, tC, tD,
                       iX, iA, iB, iC, iD,
                       isBullishPattern, rates_total);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Manual pivot detection (fallback)                                |
//+------------------------------------------------------------------+
void FindManualSwingPoints(int total,
                           const datetime &timeArr[],
                           const double &h[],
                           const double &l[],
                           double &price[],
                           datetime &t[],
                           int &idxArr[],
                           int &count)
{
   int lookback = MathMin(total - 2, InpMaxLegBars * 5 + InpZZDepth + 10);

   // Skip very recent bars for anti-repaint
   int startSearch = InpMinLegBars;

   // Collect raw pivots (audit #14: gather many, then normalize)
   PivCandidate rawPivots[];
   ArrayResize(rawPivots, 0);

   for(int i = startSearch; i < lookback; i++)
   {
      bool isH = IsPivotHigh(h, InpZZDepth, i, total);
      bool isL = IsPivotLow(l, InpZZDepth, i, total);

      if(isH || isL)
      {
         int sz = ArraySize(rawPivots);
         ArrayResize(rawPivots, sz + 1);
         rawPivots[sz].isHigh = isH;
         rawPivots[sz].price  = isH ? h[i] : l[i];
         rawPivots[sz].time   = timeArr[i];
         rawPivots[sz].idx    = i;
      }
   }

   int rawCount = ArraySize(rawPivots);
   if(rawCount == 0)                        // audit #6: empty-array guard
   {
      count = 0;
      return;
   }

   // Sort by index ascending (most recent first in series arrays — audit #5 fix)
   SortPivotsByIndex(rawPivots);

   // ── Normalize: when consecutive same-type pivots, keep the more extreme (audit #15) ──
   PivCandidate normalized[];
   ArrayResize(normalized, 0);

   int ri = 0;
   while(ri < rawCount)
   {
      bool   curType   = rawPivots[ri].isHigh;
      double bestPrice = rawPivots[ri].price;
      datetime bestTime = rawPivots[ri].time;
      int    bestIdx   = rawPivots[ri].idx;

      // Look ahead while same type continues
      int rj = ri + 1;
      while(rj < rawCount && rawPivots[rj].isHigh == curType)
      {
         if(curType)
         {
            if(rawPivots[rj].price > bestPrice)   // keep higher high
            {
               bestPrice = rawPivots[rj].price;
               bestTime  = rawPivots[rj].time;
               bestIdx   = rawPivots[rj].idx;
            }
         }
         else
         {
            if(rawPivots[rj].price < bestPrice)   // keep lower low
            {
               bestPrice = rawPivots[rj].price;
               bestTime  = rawPivots[rj].time;
               bestIdx   = rawPivots[rj].idx;
            }
         }
         rj++;
      }

      int nsz = ArraySize(normalized);
      ArrayResize(normalized, nsz + 1);
      normalized[nsz].isHigh = curType;
      normalized[nsz].price  = bestPrice;
      normalized[nsz].time   = bestTime;
      normalized[nsz].idx    = bestIdx;

      ri = rj;
   }

   // ── Take alternating pivots ───────────────────────────────────────────
   int normCount = ArraySize(normalized);
   if(normCount == 0)
   {
      count = 0;
      return;
   }

   bool expectHigh = normalized[0].isHigh;
   count = 0;
   for(int i = 0; i < normCount && count < 5; i++)
   {
      if(normalized[i].isHigh == expectHigh)
      {
         price[count]  = normalized[i].price;
         t[count]      = normalized[i].time;
         idxArr[count] = normalized[i].idx;
         count++;
         expectHigh = !expectHigh;
      }
   }
}

//+------------------------------------------------------------------+
//| Sort pivots by index ascending (most recent first in series)     |
//| audit #5: was descending = oldest first; now ascending           |
//+------------------------------------------------------------------+
void SortPivotsByIndex(PivCandidate &arr[])
{
   int n = ArraySize(arr);
   for(int i = 0; i < n - 1; i++)
   {
      for(int j = 0; j < n - i - 1; j++)
      {
         if(arr[j].idx > arr[j+1].idx)   // ascending: smaller index first
         {
            PivCandidate tmp = arr[j];
            arr[j] = arr[j+1];
            arr[j+1] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if bar is a pivot high                                     |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], int lr, int idx, int total)
{
   if(idx - lr < 0 || idx + lr >= total) return false;
   double v = h[idx];
   for(int i = idx - lr; i < idx; i++)
      if(h[i] > v) return false;
   for(int i = idx + 1; i <= idx + lr; i++)
      if(h[i] >= v) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a pivot low                                      |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &l[], int lr, int idx, int total)
{
   if(idx - lr < 0 || idx + lr >= total) return false;
   double v = l[idx];
   for(int i = idx - lr; i < idx; i++)
      if(l[i] < v) return false;
   for(int i = idx + 1; i <= idx + lr; i++)
      if(l[i] <= v) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check Fibonacci ratios and draw pattern                          |
//+------------------------------------------------------------------+
void CheckAndDrawPattern(double X, double A, double B, double C, double D,
                         datetime tX, datetime tA, datetime tB, datetime tC, datetime tD,
                         int iX, int iA, int iB, int iC, int iD,
                         bool isBullish,
                         int rates_total)
{
   double XA = MathAbs(A - X);
   double AB = MathAbs(B - A);
   double BC = MathAbs(C - B);
   double CD = MathAbs(D - C);
   double AD = MathAbs(D - A);
   double XD = MathAbs(D - X);

   if(XA == 0 || AB == 0 || BC == 0 || CD == 0) return;

   // audit #30: accurate ratio names
   double retXA_AB  = AB / XA;   // AB retracement of XA
   double retAB_BC  = BC / AB;   // BC retracement of AB
   double extBC_CD  = CD / BC;   // CD extension of BC
   double retXA_AD  = AD / XA;   // AD retracement of XA (D completion — audit #8)
   double extXA_XD  = XD / XA;   // XD extension of XA

   string patternName = "";
   color patColor = isBullish ? InpBullColor : InpBearColor;

   // ── Pattern definitions using ratio ranges (audit #9, #10) ───────────
   //
   // Standard harmonic ratios (Carney / Pesavento conventions):
   //   Gartley:    XA→AB=0.618,       AB→BC=0.382–0.886,  BC→CD=1.272–1.618,  AD=0.786*XA
   //   Bat:        XA→AB=0.382–0.50,  AB→BC=0.382–0.886,  BC→CD=1.618–2.618,  AD=0.886*XA
   //   Butterfly:  XA→AB=0.786,       AB→BC=0.382–0.886,  BC→CD=1.618–2.24,   AD=1.272–1.618*XA
   //   Crab:       XA→AB=0.382–0.618, AB→BC=0.382–0.886,  BC→CD=2.618–3.618,  AD=1.618*XA
   //   Shark (5-0): XA→AB=1.13–1.618, AB→BC=1.618–2.24,   BC→CD=0.50

   if(InpGartley &&
      InRatioRange(retXA_AB, 0.618, 0.618) &&
      InRatioRange(retAB_BC, 0.382, 0.886) &&
      InRatioRange(extBC_CD, 1.272, 1.618) &&
      InRatioRange(retXA_AD, 0.786, 0.786))
   {
      patternName = (isBullish ? "Bullish" : "Bearish") + " Gartley";
   }
   else if(InpBat &&
           InRatioRange(retXA_AB, 0.382, 0.50) &&
           InRatioRange(retAB_BC, 0.382, 0.886) &&
           InRatioRange(extBC_CD, 1.618, 2.618) &&
           InRatioRange(retXA_AD, 0.886, 0.886))
   {
      patternName = (isBullish ? "Bullish" : "Bearish") + " Bat";
   }
   else if(InpButterfly &&
           InRatioRange(retXA_AB, 0.786, 0.786) &&
           InRatioRange(retAB_BC, 0.382, 0.886) &&
           InRatioRange(extBC_CD, 1.618, 2.24) &&
           InRatioRange(retXA_AD, 1.272, 1.618))
   {
      patternName = (isBullish ? "Bullish" : "Bearish") + " Butterfly";
   }
   else if(InpCrab &&
           InRatioRange(retXA_AB, 0.382, 0.618) &&
           InRatioRange(retAB_BC, 0.382, 0.886) &&
           InRatioRange(extBC_CD, 2.618, 3.618) &&
           InRatioRange(retXA_AD, 1.618, 1.618))
   {
      patternName = (isBullish ? "Bullish" : "Bearish") + " Crab";
   }
   else if(InpShark &&
           InRatioRange(retXA_AB, 1.13, 1.618) &&
           InRatioRange(retAB_BC, 1.618, 2.24) &&
           InRatioRange(extBC_CD, 0.50, 0.50))
   {
      // Shark (5-0) uses distinct conventions; this is a simplified model (audit #10)
      patternName = (isBullish ? "Bullish" : "Bearish") + " Shark";
   }

   if(patternName == "") return;

   // ── Deterministic pattern ID (audit #7) ──────────────────────────────
   string patternId = StringFormat("%I64d_%I64d_%I64d_%I64d_%I64d",
                                   (long)tX, (long)tA, (long)tB, (long)tC, (long)tD);

   // Skip if this exact pattern was already drawn
   if(patternId == g_lastPatternId && patternName == g_lastPatternType)
      return;

   // Clean up previous pattern objects if pattern changed
   if(g_lastPatternId != "" && g_lastPatternId != patternId)
      CleanupPatternObjects(g_lastPatternId);

   g_lastPatternId   = patternId;
   g_lastPatternType = patternName;
   g_lastDTime       = tD;

   // ── Publish signal to indicator buffer (audit #3, #8) ─────────────────
   // iD is the bar index of D in the series arrays
   if(isBullish)
      g_bullBuf[iD] = D;
   else
      g_bearBuf[iD] = D;

   // ── Draw the pattern ─────────────────────────────────────────────────
   string suffix = "_" + patternId;

   if(InpShowLegs)
   {
      DrawTrendLine(g_prefix + "XA" + suffix, tX, X, tA, A, patColor, InpLineWidth, InpLineStyle);
      DrawTrendLine(g_prefix + "AB" + suffix, tA, A, tB, B, patColor, InpLineWidth, InpLineStyle);
      DrawTrendLine(g_prefix + "BC" + suffix, tB, B, tC, C, patColor, InpLineWidth, InpLineStyle);
      DrawTrendLine(g_prefix + "CD" + suffix, tC, C, tD, D, patColor, InpLineWidth, InpLineStyle);
   }

   // ── PRZ Zone from actual completion projections (audit #20) ───────────
   if(InpShowPRZ)
   {
      DrawPRZZone(X, A, B, C, D, tD, CD, isBullish, suffix, patColor);
   }

   // ── Arrow at D point with offset (audit #24) ─────────────────────────
   double arrowOffset = MathMax(CD * 0.03, 10 * _Point);
   double arrowPrice  = isBullish ? D - arrowOffset : D + arrowOffset;

   string arrowName = g_prefix + "ARR" + suffix;
   if(!ObjectCreate(0, arrowName, isBullish ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,
                    0, tD, arrowPrice))
   {
      PrintFormat("[%s %s] Failed to create arrow %s. Error=%d",
                  _Symbol, EnumToString(_Period), arrowName, GetLastError());
   }
   else
   {
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                       isBullish ? InpBullColor : InpBearColor);
   }

   // ── Label (audit #24: proper offset) ─────────────────────────────────
   if(InpShowLabels)
   {
      double labelOffset = MathMax(CD * 0.08, 20 * _Point);
      double labelY = isBullish ? D - labelOffset : D + labelOffset;

      string lblName = g_prefix + "LBL" + suffix;
      if(!ObjectCreate(0, lblName, OBJ_TEXT, 0, tD, labelY))
      {
         PrintFormat("[%s %s] Failed to create label %s. Error=%d",
                     _Symbol, EnumToString(_Period), lblName, GetLastError());
      }
      else
      {
         ObjectSetString(0, lblName, OBJPROP_TEXT, patternName);
         ObjectSetInteger(0, lblName, OBJPROP_COLOR, patColor);
         ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 10);
         ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_CENTER);
         ObjectSetString(0, lblName, OBJPROP_FONT, "Arial");
      }
   }

   // ── Log with accurate ratio names (audit #29, #30) ───────────────────
   PrintFormat("[%s %s] %s | AB/XA=%.4f BC/AB=%.4f CD/BC=%.4f AD/XA=%.4f | D=%.5f @ %s",
               _Symbol, EnumToString(_Period), patternName,
               retXA_AB, retAB_BC, extBC_CD, retXA_AD,
               D, TimeToString(tD));
}

//+------------------------------------------------------------------+
//| Draw PRZ zone from actual harmonic completion projections        |
//| audit #20: convergence-based instead of arbitrary CD-based box   |
//+------------------------------------------------------------------+
void DrawPRZZone(double X, double A, double B, double C, double D,
                 datetime tD, double CD, bool isBullish,
                 string suffix, color patColor)
{
   int dir = isBullish ? -1 : 1;

   // Multiple completion projections
   double XA_len  = MathAbs(A - X);
   double BC_len  = MathAbs(C - B);
   double AB_len  = MathAbs(B - A);

   double projXA_786  = A + dir * XA_len * 0.786;
   double projXA_886  = A + dir * XA_len * 0.886;
   double projXA_1272 = A + dir * XA_len * 1.272;
   double projXA_1618 = A + dir * XA_len * 1.618;

   double projBC_1272 = C + dir * BC_len * 1.272;
   double projBC_1618 = C + dir * BC_len * 1.618;
   double projBC_2618 = C + dir * BC_len * 2.618;
   double projBC_3618 = C + dir * BC_len * 3.618;

   // AB=CD projection
   double abcdProj = A + dir * AB_len;

   // Alternate AB=CD: BC extension of 1.272 or 1.618 applied from C
   double altABCD_1272 = C + dir * AB_len * 1.272;
   double altABCD_1618 = C + dir * AB_len * 1.618;

   // Collect all projections
   double projections[11];
   int projCount = 0;
   projections[projCount++] = projXA_786;
   projections[projCount++] = projXA_886;
   projections[projCount++] = projXA_1272;
   projections[projCount++] = projXA_1618;
   projections[projCount++] = projBC_1272;
   projections[projCount++] = projBC_1618;
   projections[projCount++] = projBC_2618;
   projections[projCount++] = projBC_3618;
   projections[projCount++] = abcdProj;
   projections[projCount++] = altABCD_1272;
   projections[projCount++] = altABCD_1618;

   // Find min/max of projections (properly ordered)
   double przTop  = projections[0];
   double przBot  = projections[0];
   for(int i = 1; i < projCount; i++)
   {
      if(projections[i] > przTop) przTop = projections[i];
      if(projections[i] < przBot) przBot = projections[i];
   }

   // Add 5% buffer
   double buffer = MathAbs(przTop - przBot) * 0.05;
   przTop += buffer;
   przBot -= buffer;

   // Period-based time offset (audit #19)
   int seconds = PeriodSeconds(_Period);
   if(seconds <= 0) seconds = 60;
   datetime przEnd = tD + seconds * 30;

   // Draw PRZ rectangle
   string przName = g_prefix + "PRZ" + suffix;
   if(!ObjectCreate(0, przName, OBJ_RECTANGLE, 0, tD, przTop, przEnd, przBot))
   {
      PrintFormat("[%s %s] Failed to create PRZ %s. Error=%d",
                  _Symbol, EnumToString(_Period), przName, GetLastError());
      return;
   }
   ObjectSetInteger(0, przName, OBJPROP_COLOR, patColor);
   ObjectSetInteger(0, przName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, przName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, przName, OBJPROP_FILL, true);
   ObjectSetInteger(0, przName, OBJPROP_BACK, true);

   // D-level: bounded trend segment instead of infinite HLINE (audit #23)
   string dlName = g_prefix + "D_LVL" + suffix;
   datetime dlEnd = tD + seconds * 15;
   if(!ObjectCreate(0, dlName, OBJ_TREND, 0, tD, D, dlEnd, D))
   {
      PrintFormat("[%s %s] Failed to create D-level %s. Error=%d",
                  _Symbol, EnumToString(_Period), dlName, GetLastError());
      return;
   }
   ObjectSetInteger(0, dlName, OBJPROP_COLOR, patColor);
   ObjectSetInteger(0, dlName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, dlName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, dlName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, dlName, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Clean up objects for a specific pattern ID                       |
//+------------------------------------------------------------------+
void CleanupPatternObjects(string patternId)
{
   string suffix = "_" + patternId;
   string names[8];
   names[0] = g_prefix + "XA"    + suffix;
   names[1] = g_prefix + "AB"    + suffix;
   names[2] = g_prefix + "BC"    + suffix;
   names[3] = g_prefix + "CD"    + suffix;
   names[4] = g_prefix + "PRZ"   + suffix;
   names[5] = g_prefix + "D_LVL" + suffix;
   names[6] = g_prefix + "ARR"   + suffix;
   names[7] = g_prefix + "LBL"   + suffix;

   for(int i = 0; i < 8; i++)
   {
      if(ObjectFind(0, names[i]) >= 0)
         ObjectDelete(0, names[i]);
   }
}

//+------------------------------------------------------------------+
//| Draw a trend line object (audit #22: check return values)        |
//+------------------------------------------------------------------+
void DrawTrendLine(string name, datetime t1, double p1, datetime t2, double p2,
                   color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      PrintFormat("[%s %s] Failed to create trend line %s. Error=%d",
                  _Symbol, EnumToString(_Period), name, GetLastError());
      return;
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Ratio range check: is actual within [min*(1-tol), max*(1+tol)]?  |
//| audit #9: replaces isolated point targets with continuous ranges |
//+------------------------------------------------------------------+
bool InRatioRange(double actual, double minimum, double maximum)
{
   double lo = minimum * (1.0 - InpTolerance);
   double hi = maximum * (1.0 + InpTolerance);
   return (actual >= lo && actual <= hi);
}

//+------------------------------------------------------------------+
//| Legacy single-point tolerance check (retained for compatibility) |
//+------------------------------------------------------------------+
bool IsRatio(double expected, double actual)
{
   if(expected == 0) return false;
   return MathAbs(actual / expected - 1.0) <= InpTolerance;
}
