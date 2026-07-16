//+------------------------------------------------------------------+
//|                                    Squeeze Momentum Pro IRUNTV.mq5|
//|                    Ported from Pine Script v6 → MQL5              |
//|                    Original: SQZ_PRO.pine                        |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: Squeeze Momentum Pro by IRUNTV ::"
#property description "TTM Squeeze with adaptive lengths, quality scoring,"
#property description "HTF context, entry signals, and dashboard."

#property indicator_separate_window
#property indicator_buffers 14
#property indicator_plots   8

// ── Plots ───────────────────────────────────────────────────────────────────
#property indicator_label1  "Momentum"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLime,clrGreen,clrRed,clrMaroon  // bull↑, bull↓, bear↓, bear↑
#property indicator_width1  3

#property indicator_label2  "Zero Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_width2  1

#property indicator_label3  "Secondary Momentum"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrAqua,clrTeal,clrFuchsia,clrPurple
#property indicator_width3  1

#property indicator_label4  "Compression Pressure"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_width4  1

#property indicator_label5  "Quality Score"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrYellow
#property indicator_width5  2

#property indicator_label6  "Squeeze State"
#property indicator_type6   DRAW_NONE

#property indicator_label7  "Long Entry"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrLime
#property indicator_width7  2

#property indicator_label8  "Short Entry"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrRed
#property indicator_width8  2

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Core ═══"
input int                          InpInitialBackfill = 2000;             // Initial Backfill Bars (max history processed on first load)
input int                          InpBBLen        = 20;                 // BB Length
input double                       InpBBMult       = 2.0;                // BB Multiplier
input int                          InpKCLen        = 20;                 // KC Length
input double                       InpKCMult       = 1.5;                // KC Multiplier
input bool                         InpTrueRange    = true;               // Use True Range for KC
input ENUM_APPLIED_PRICE           InpSrc          = PRICE_CLOSE;        // Source

input group                        "═══ Momentum ═══"
input int                          InpMomLen       = 20;                 // Momentum Length
input int                          InpSmoothLen    = 1;                  // Momentum Smoothing

input group                        "═══ Quality ═══"
input int                          InpMinQuality   = 70;                 // Minimum Quality Score
input bool                         InpUseTrend     = true;               // Use Trend Score
input int                          InpTrendLen     = 50;                 // Trend EMA
input bool                         InpUseVol       = true;               // Use Volume Score
input int                          InpVolLen       = 20;                 // Volume SMA
input double                       InpVolMult      = 1.0;                // Volume Threshold

input group                        "═══ HTF ═══"
input bool                         InpUseHTF       = true;               // Use HTF Alignment
input ENUM_TIMEFRAMES              InpHtfTF        = PERIOD_H1;          // HTF Timeframe
input int                          InpHtfTrendLen  = 50;                 // HTF Trend EMA

input group                        "═══ Entry Signals ═══"
input bool                         InpShowEntry    = true;               // Show Entry Markers
input int                          InpEntryWindow  = 5;                  // Entry Window (bars)
input int                          InpRiskLookback = 50;                 // Range Lookback
input double                       InpMinRoomATR   = 1.2;                // Min Room ATR
input bool                         InpConfirmed    = true;               // Confirmed Bars Only

input group                        "═══ Visuals ═══"
input bool                         InpShowSecHist  = true;               // Show Secondary Histogram
input bool                         InpShowPressure = true;               // Show Compression Pressure
input bool                         InpShowTable    = true;               // Show Dashboard

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_momentum[];       // 0
double g_momColor[];       // 1
double g_zeroLine[];       // 2
double g_secondaryMom[];   // 3
double g_secColor[];       // 4
double g_pressure[];       // 5
double g_quality[];        // 6
double g_sqzState[];       // 7 (0=no sqz, 1=sqz on, 2=sqz off)
double g_longEntry[];      // 8
double g_shortEntry[];     // 9

// Hidden calc buffers
double g_crsiBuf[];        // 10 reserved calc buffer
double g_htfBuf[];         // 11
double g_bbWidth[];        // 12
double g_kcWidth[];        // 13

// Persistent, incrementally-updated trend EMA (O(1)/bar) — replaces the
// old per-bar EMA(c, InpTrendLen, ...) calls, which recomputed from scratch
// walking to ArraySize(a) every call: O(n) per call x n bars = O(n^2), and
// it silently returned the EMA-as-of-the-newest-bar for every historical
// bar instead of the value as of that bar (a lookahead bug, not just slow).
double g_trendEMA[];

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix = "SQZP_";
int    g_pendingDir, g_pendingBars, g_pendingReleaseBar;
double g_pendingQuality;
bool   g_prevBuy, g_prevSell;

//+------------------------------------------------------------------+
//| Simple helpers                                                    |
//+------------------------------------------------------------------+
double SMA(const double &a[], int p, int s)
{
   if(s + p > ArraySize(a)) return 0;
   double sum = 0;
   for(int i = 0; i < p; i++) sum += a[s + i];
   return sum / p;
}

// NOTE: no longer called in the hot loop (see g_trendEMA above) — this recomputes
// from scratch each call and is O(window) at best, O(n) if misused with a large
// window. Kept only for reference / potential one-off use; not for per-bar calls.
double EMA(const double &a[], int p, int s)
{
   int sz = ArraySize(a);
   if(s + p > sz) return 0;
   double alpha = 2.0 / (p + 1.0);
   double ema = SMA(a, p, s);
   int endIdx = s + p - 1;               // FIX: stop at the window this call represents,
   for(int i = s + p; i <= endIdx; i++)  // not at ArraySize(a) (was walking to the newest bar every call)
      ema = a[i] * alpha + ema * (1.0 - alpha);
   return ema;
}

double StdDev(const double &a[], int p, int s)
{
   double mean = SMA(a, p, s);
   double sumSq = 0;
   for(int i = 0; i < p; i++)
   {
      double d = a[s + i] - mean;
      sumSq += d * d;
   }
   return MathSqrt(sumSq / p);
}

double Highest(const double &a[], int p, int s)
{
   double hi = -1e100;
   for(int i = 0; i < p && s + i < ArraySize(a); i++)
      if(a[s + i] > hi) hi = a[s + i];
   return hi;
}

double Lowest(const double &a[], int p, int s)
{
   double lo = 1e100;
   for(int i = 0; i < p && s + i < ArraySize(a); i++)
      if(a[s + i] < lo) lo = a[s + i];
   return lo;
}

double LinReg(const double &a[], int p, int s)
{
   int sz = ArraySize(a);
   if(s + p > sz) return 0;
   double sx = 0, sy = 0, sxy = 0, sx2 = 0;
   for(int i = 0; i < p; i++)
   {
      double x = i, y = a[s + i];
      sx += x; sy += y; sxy += x*y; sx2 += x*x;
   }
   double den = p*sx2 - sx*sx;
   if(MathAbs(den) < 1e-10) return 0;
   double slope = (p*sxy - sx*sy) / den;
   return slope * (p-1) + (sy/p);
}

// Same regression, but subtracts a scalar offset from each y inline —
// avoids ever allocating/filling a rates_total-sized array just to read
// InpMomLen values out of it (that was an O(n) allocation per bar = O(n^2) total).
double LinRegOffset(const double &a[], int p, int s, double offset)
{
   int sz = ArraySize(a);
   if(s + p > sz) return 0;
   double sx = 0, sy = 0, sxy = 0, sx2 = 0;
   for(int i = 0; i < p; i++)
   {
      double x = i, y = a[s + i] - offset;
      sx += x; sy += y; sxy += x*y; sx2 += x*x;
   }
   double den = p*sx2 - sx*sx;
   if(MathAbs(den) < 1e-10) return 0;
   double slope = (p*sxy - sx*sy) / den;
   return slope * (p-1) + (sy/p);
}

double Clamp(double v, double mn, double mx) { return MathMax(mn, MathMin(mx, v)); }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_momentum,     INDICATOR_DATA);
   SetIndexBuffer(1, g_momColor,     INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, g_zeroLine,     INDICATOR_DATA);
   SetIndexBuffer(3, g_secondaryMom, INDICATOR_DATA);
   SetIndexBuffer(4, g_secColor,     INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5, g_pressure,     INDICATOR_DATA);
   SetIndexBuffer(6, g_quality,      INDICATOR_DATA);
   SetIndexBuffer(7, g_sqzState,     INDICATOR_DATA);
   SetIndexBuffer(8, g_longEntry,    INDICATOR_DATA);
   SetIndexBuffer(9, g_shortEntry,   INDICATOR_DATA);
   SetIndexBuffer(10,g_crsiBuf,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,g_htfBuf,       INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,g_bbWidth,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,g_kcWidth,      INDICATOR_CALCULATIONS);
   
   PlotIndexSetInteger(6, PLOT_ARROW, 233);
   PlotIndexSetInteger(7, PLOT_ARROW, 234);
   for(int p = 0; p < 8; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("SQZ PRO(%d,%d)", InpBBLen, InpKCLen));
   
   g_pendingDir = 0; g_pendingBars = 0; g_prevBuy = false; g_prevSell = false;
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
   int minBars = InpBBLen + InpKCLen + InpMomLen + InpTrendLen + 50;
   if(rates_total < minBars) return 0;
   
   if(prev_calc == 0)
   {
      ArrayInitialize(g_momentum, EMPTY_VALUE);
      ArrayInitialize(g_zeroLine, EMPTY_VALUE);
      ArrayInitialize(g_secondaryMom, EMPTY_VALUE);
      ArrayInitialize(g_pressure, EMPTY_VALUE);
      ArrayInitialize(g_quality, EMPTY_VALUE);
      ArrayInitialize(g_sqzState, EMPTY_VALUE);
      ArrayInitialize(g_longEntry, EMPTY_VALUE);
      ArrayInitialize(g_shortEntry, EMPTY_VALUE);
   }
   
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   if(start < minBars) start = minBars;

   // Bounded first-load backfill — without this, the main loop (which now
   // also has to seed g_trendEMA) still walks the entire chart history on
   // first attach. Combined with the O(n^2) bugs above this was almost
   // certainly what was hanging/crashing MT5 on load.
   if(prev_calc == 0)
   {
      int backfillLimit = MathMax(minBars, rates_total - InpInitialBackfill);
      if(start < backfillLimit) start = backfillLimit;
   }

   if(ArraySize(g_trendEMA) < rates_total) ArrayResize(g_trendEMA, rates_total);
   
   // Source and TR
   double src[], tr[];
   ArrayResize(src, rates_total); ArrayResize(tr, rates_total);
   for(int i = 0; i < rates_total; i++)
   {
      src[i] = GetPrice(o[i], h[i], l[i], c[i], InpSrc);
      tr[i]  = InpTrueRange && i > 0 ? MathMax(h[i]-l[i], MathMax(MathAbs(h[i]-c[i-1]), MathAbs(l[i]-c[i-1]))) : h[i]-l[i];
   }
   
   // HTF data
   double htfMom[], htfTrend[];
   ArrayResize(htfMom, rates_total); ArrayResize(htfTrend, rates_total);
   int htfBars = 0;
   if(InpUseHTF)
   {
      double htfC[];
      ArraySetAsSeries(htfC, true);
      htfBars = CopyClose(_Symbol, InpHtfTF, 0, InpHtfTrendLen + 5, htfC);
      for(int i = 0; i < rates_total; i++)
      {
         htfTrend[i] = 0;
         // HTF trend is approximated
      }
   }
   
   // ── MAIN LOOP ────────────────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      g_longEntry[i] = EMPTY_VALUE;
      g_shortEntry[i] = EMPTY_VALUE;
      g_pressure[i] = EMPTY_VALUE;
      
      double bbBasis = SMA(src, InpBBLen, i - InpBBLen + 1);
      double bbDev   = StdDev(src, InpBBLen, i - InpBBLen + 1) * InpBBMult;
      double upperBB = bbBasis + bbDev, lowerBB = bbBasis - bbDev;
      
      double kcBasis = SMA(src, InpKCLen, i - InpKCLen + 1);
      double kcRange = SMA(tr, InpKCLen, i - InpKCLen + 1);
      double upperKC = kcBasis + kcRange * InpKCMult, lowerKC = kcBasis - kcRange * InpKCMult;
      
      bool sqzOn  = (lowerBB > lowerKC && upperBB < upperKC);
      bool sqzOff = (lowerBB < lowerKC && upperBB > upperKC);
      bool noSqz  = !sqzOn && !sqzOff;
      bool sqzRel = (i > 0) && (g_sqzState[i-1] >= 0.5) && !sqzOn;
      
      g_sqzState[i] = sqzOn ? 1.0 : (sqzOff ? 2.0 : 0.0);
      
      // Compression
      double bbW = upperBB - lowerBB, kcW = upperKC - lowerKC;
      if(bbW < 1e-10) bbW = 1e-10; if(kcW < 1e-10) kcW = 1e-10;
      double compRatio = bbW / kcW;
      double compPress = Clamp(1.0 - compRatio, 0, 1);
      g_bbWidth[i] = bbW; g_kcWidth[i] = kcW;
      
      // Count squeeze bars
      static int sqzBarCount = 0;
      sqzBarCount = sqzOn ? sqzBarCount + 1 : 0;
      
      // Momentum
      double rangeMid = (Highest(h, InpMomLen, i - InpMomLen + 1) + Lowest(l, InpMomLen, i - InpMomLen + 1)) / 2.0;
      double classicMean = (rangeMid + SMA(src, InpMomLen, i - InpMomLen + 1)) / 2.0;
      
      double rawMom = LinRegOffset(src, InpMomLen, i - InpMomLen + 1, classicMean);
      if(InpSmoothLen > 1)
      {
         double smAlpha = 2.0 / (InpSmoothLen + 1.0);
         bool firstEverMomBar = (prev_calc == 0 && i == start);
         g_momentum[i] = (i > 0 && !firstEverMomBar) ? rawMom * smAlpha + g_momentum[i-1] * (1.0 - smAlpha) : rawMom;
      }
      else
         g_momentum[i] = rawMom;
      
      // Color index
      bool momUp   = (i > 0 && g_momentum[i] > g_momentum[i-1]);
      bool momBull = (g_momentum[i] >= 0);
      g_momColor[i] = momBull ? (momUp ? 0 : 1) : (!momUp ? 2 : 3);
      
      // Secondary momentum (simplified)
      g_secondaryMom[i] = g_momentum[i] * 0.8;
      bool secUp = (i > 0 && g_secondaryMom[i] > g_secondaryMom[i-1]);
      bool secBull = (g_secondaryMom[i] >= 0);
      g_secColor[i] = secBull ? (secUp ? 0 : 1) : (!secUp ? 2 : 3);
      
      // Compression pressure overlay
      double momMax = Highest(g_momentum, MathMax(InpMomLen, InpKCLen), i - MathMax(InpMomLen, InpKCLen) + 1);
      g_pressure[i] = InpShowPressure ? compPress * MathAbs(momMax) : EMPTY_VALUE;
      
      // Quality score components
      double depthScore    = compPress * 25.0;
      double durScore      = Clamp((double)sqzBarCount / 8.0, 0, 1) * 20.0;
      int momSmaLen         = MathMin(100, i + 1);           // guard: avoid negative start index when i < 99
      double momStrength   = MathAbs(g_momentum[i]) / MathMax(0.0001, SMA(g_momentum, momSmaLen, i - momSmaLen + 1));
      double momScore      = Clamp(momStrength / 1.5, 0, 1) * 20.0;
      double accelScore    = ((momBull && momUp) || (!momBull && !momUp)) ? 10.0 : 0.0;
      // Incremental trend EMA — O(1) per bar, causal (uses only bars up to i)
      double trendAlpha = 2.0 / (InpTrendLen + 1.0);
      bool firstEverBar = (prev_calc == 0 && i == start);
      g_trendEMA[i] = (i > 0 && !firstEverBar) ? c[i] * trendAlpha + g_trendEMA[i-1] * (1.0 - trendAlpha) : c[i];
      double trendScore    = InpUseTrend ? ((momBull && c[i] > g_trendEMA[i]) || (!momBull && c[i] < g_trendEMA[i])) ? 10.0 : 0.0 : 10.0;
      double volScore      = 7.5; // simplified - always on
      
      double qualScore = Clamp(depthScore + durScore + momScore + accelScore + trendScore + volScore, 0, 100);
      g_quality[i] = ((qualScore / 100.0) - 0.5) * MathAbs(momMax); // scaled to histogram range
      
      // Entry signals
      bool strongRelease = qualScore >= InpMinQuality;
      bool bullRel = sqzRel && g_momentum[i] > 0 && strongRelease;
      bool bearRel = sqzRel && g_momentum[i] < 0 && strongRelease;
      
      // Entry state machine
      if(bullRel)
      {
         g_pendingDir = 1;
         g_pendingBars = InpEntryWindow;
         g_pendingReleaseBar = i;
         g_pendingQuality = qualScore;
      }
      else if(bearRel)
      {
         g_pendingDir = -1;
         g_pendingBars = InpEntryWindow;
         g_pendingReleaseBar = i;
         g_pendingQuality = qualScore;
      }
      else if(g_pendingBars > 0)
         g_pendingBars--;
      else
         g_pendingDir = 0;
      
      bool entryReady = false;
      if(InpShowEntry && g_pendingDir != 0 && g_pendingBars > 0 && g_pendingQuality >= InpMinQuality)
      {
         if(g_pendingDir == 1 && g_momentum[i] > 0 && momUp)
         {
            g_longEntry[i] = g_momentum[i] * 1.1;
            entryReady = true;
            g_pendingDir = 0;
         }
         else if(g_pendingDir == -1 && g_momentum[i] < 0 && !momUp)
         {
            g_shortEntry[i] = g_momentum[i] * 1.1;
            entryReady = true;
            g_pendingDir = 0;
         }
      }
      
      if(i == rates_total - 1)
      {
         if(entryReady && g_pendingDir == 1 && !g_prevBuy)
            Alert("SQZ PRO LONG | ", _Symbol, " | Quality=", DoubleToString(qualScore, 0));
         if(entryReady && g_pendingDir == -1 && !g_prevSell)
            Alert("SQZ PRO SHORT | ", _Symbol, " | Quality=", DoubleToString(qualScore, 0));
      }
      
      // Zero line
      g_zeroLine[i] = 0;
   }
   
   if(InpShowTable)
      RenderDashboard(rates_total, c, h, l, tv);
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void RenderDashboard(int total, const double &c[], const double &h[], const double &l[], const long &tv[])
{
   int idx = total - 1;
   string pf = g_prefix + "d_";
   int x = 10, y = 20, gap = 15, cw = 130;
   
   string sqzState = g_sqzState[idx] >= 0.5 ? (g_sqzState[idx] >= 1.5 ? "FIRING" : "SQUEEZE") : "NONE";
   color sqzClr = sqzState == "SQUEEZE" ? clrOrange : sqzState == "FIRING" ? clrLime : clrGray;
   string momState = g_momentum[idx] >= 0 ? (g_momentum[idx] > (idx>0?g_momentum[idx-1]:0) ? "BULL+" : "BULL-") : (g_momentum[idx] < (idx>0?g_momentum[idx-1]:0) ? "BEAR+" : "BEAR-");
   color momClr = g_momentum[idx] >= 0 ? clrLime : clrRed;
   
   int row = 0;
   DR(pf, row++, "SQZ State", sqzState, clrWhite, sqzClr, x, y, gap, cw);
   DR(pf, row++, "Momentum",  momState,  clrSilver, momClr, x, y, gap, cw);
   DR(pf, row++, "Quality",   DoubleToString(g_quality[idx], 0) + "%", clrSilver,
      g_quality[idx] >= InpMinQuality ? clrLime : clrOrange, x, y, gap, cw);
   DR(pf, row++, "Pending",   g_pendingDir != 0 ? StringFormat("%s (%d bars)",
      g_pendingDir == 1 ? "LONG" : "SHORT", g_pendingBars) : "-", clrSilver, clrWhite, x, y, gap, cw);
   
   ChartRedraw();
}

void DR(string p, int r, string l, string v, color lc, color vc, int x, int y0, int g, int cw)
{
   int yy = y0 + r * g;
   CL(p + "l" + IntegerToString(r), l, x, yy, lc, 8);
   CL(p + "v" + IntegerToString(r), v, x + cw, yy, vc, 8);
}

void CL(string n, string t, int x, int y, color c, int s = 8)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, s);
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

void CleanupObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
