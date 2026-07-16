//+------------------------------------------------------------------+
//|                              Smart Money Concepts [LuxAlgo] v3    |
//|                     Ground-up rebuild — dual structure engine     |
//|                     Chronological non-series architecture         |
//+------------------------------------------------------------------+
#property copyright   "SMC LuxAlgo v3 — dual-structure rebuild"
#property version     "3.00"
#property description ":: Smart Money Concepts [LuxAlgo] v3 ::"
#property description "Dual Internal/Swing Structure, BOS/CHoCH,"
#property description "Order Blocks, FVGs, EQH/EQL, PDH/PWH/PMH,"
#property description "Premium/Discount Zones, Candle Coloring."

#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   12

// ── Buffer plots ────────────────────────────────────────────────────────────
#property indicator_label1  "Int SwHigh"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'0xF2,0x36,0x45'
#property indicator_width1  1

#property indicator_label2  "Int SwLow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'0x08,0x99,0x81'
#property indicator_width2  1

#property indicator_label3  "Swing SwHigh"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'0xCC,0x00,0x00'
#property indicator_width3  2

#property indicator_label4  "Swing SwLow"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'0x00,0x66,0x44'
#property indicator_width4  2

#property indicator_label5  "Bull Candle"
#property indicator_type5   DRAW_COLOR_CANDLES
#property indicator_color5  clrLime,clrRed

#property indicator_label6  "Bear Candle"
#property indicator_type6   DRAW_NONE

#property indicator_label7  "OB High"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "OB Low"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "FVG Bull"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "FVG Bear"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "Bias Signal"
#property indicator_type11  DRAW_NONE
#property indicator_label12 "PDH Line"
#property indicator_type12  DRAW_NONE

// ═════════════════════════════════════════════════════════════════════════════
// ENUMS  (must precede inputs)
// ═════════════════════════════════════════════════════════════════════════════
enum ENUM_DISPLAY_MODE     { DISPLAY_ALL, DISPLAY_PRESENT };
enum ENUM_STRUCTURE_SOURCE { SOURCE_INTERNAL, SOURCE_SWING };
enum ENUM_OB_MITIGATION    { OB_MIT_TOUCH, OB_MIT_WICK, OB_MIT_CLOSE, OB_MIT_FULL };
enum ENUM_FVG_MITIGATION   { FVG_MIT_TOUCH, FVG_MIT_MID, FVG_MIT_CLOSE, FVG_MIT_FULL };

// ═════════════════════════════════════════════════════════════════════════════
// INPUTS
// ═════════════════════════════════════════════════════════════════════════════
input group                          "═══ Internal Structure ═══"
input int                            InpIntSwingLen   = 5;            // Internal Pivot Length
input bool                           InpShowIntStruct = true;         // Show Internal Structure
input bool                           InpShowIntBOS    = true;         // Show Internal BOS
input bool                           InpShowIntCHoCH  = true;         // Show Internal CHoCH

input group                          "═══ Swing Structure ═══"
input int                            InpSwSwingLen    = 10;           // Swing Pivot Length
input bool                           InpShowSwStruct  = true;         // Show Swing Structure
input bool                           InpShowSwBOS     = true;         // Show Swing BOS
input bool                           InpShowSwCHoCH   = true;         // Show Swing CHoCH

input group                          "═══ Order Blocks ═══"
input bool                           InpShowIntOB     = true;         // Show Internal OBs
input bool                           InpShowSwOB      = true;         // Show Swing OBs
input int                            InpMaxIntOB      = 10;           // Max Internal OBs
input int                            InpMaxSwOB       = 5;            // Max Swing OBs
input ENUM_OB_MITIGATION             InpOBMitigation  = OB_MIT_WICK;  // OB Mitigation Mode
input bool                           InpOBFromBOS     = true;         // Create OBs from BOS too

input group                          "═══ Fair Value Gaps ═══"
input bool                           InpShowFVG       = true;         // Show FVGs
input ENUM_FVG_MITIGATION            InpFVGMitigation = FVG_MIT_TOUCH;// FVG Mitigation Mode
input int                            InpMaxFVGs       = 20;           // Max FVGs
input double                         InpFVGMinSize    = 0.0;          // Min FVG Size (points)

input group                          "═══ EQH / EQL ═══"
input bool                           InpShowEQ        = true;         // Show EQH/EQL
input double                         InpEQTolerance   = 0.05;         // EQ Tolerance (%)
input int                            InpEQConfirmBars = 3;            // EQ Confirmation Bars

input group                          "═══ Previous Highs/Lows ═══"
input bool                           InpShowPDH       = true;         // Show Prev Day High/Low
input bool                           InpShowPWH       = true;         // Show Prev Week High/Low
input bool                           InpShowPMH       = true;         // Show Prev Month High/Low

input group                          "═══ Premium / Discount ═══"
input bool                           InpShowPDZ       = true;         // Show Premium/Discount

input group                          "═══ Candle Coloring ═══"
input bool                           InpColorCandles  = true;         // Color Candles by Structure
input ENUM_STRUCTURE_SOURCE          InpColorSource   = SOURCE_SWING; // Coloring Source

input group                          "═══ Display ═══"
input ENUM_DISPLAY_MODE              InpDisplayMode   = DISPLAY_ALL;  // Display Mode
input bool                           InpShowLabels    = true;         // Show Labels

input group                          "═══ Alerts ═══"
input bool                           InpAlertsActive  = true;         // Enable Alerts
input bool                           InpAlertPopup    = true;         // Terminal Popup
input bool                           InpAlertSound    = false;        // Sound
input bool                           InpAlertPush     = false;        // Push Notification

// ═════════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES
// ═════════════════════════════════════════════════════════════════════════════
#define MAX_PIVOTS 300
#define OB_SEARCH  25  // bars to search for OB origin candle

struct PivotRec {
   int      barIdx;       // bar index (non-series, 0=oldest)
   double   price;
   datetime time;
   bool     consumed;     // has this pivot been crossed?
};

struct StructureState {
   bool     trendBull;       // true=bullish, false=bearish
   bool     biasEstablished; // true once enough pivots exist to determine bias
   // Active protection levels
   double   activeHigh;
   double   activeLow;
   int      activeHighBar;
   int      activeLowBar;
   datetime activeHighTime;
   datetime activeLowTime;
   // Trailing extremes
   double   trailHigh;
   double   trailLow;
   int      trailHighBar;
   int      trailLowBar;
   // Strong/weak status
   bool     strongHigh;      // last high was a higher high
   bool     strongLow;       // last low was a lower low
   // Last break events
   int      lastBOSBar;
   int      lastCHoCHBar;
   // Pivot tracking
   PivotRec pivotsHi[MAX_PIVOTS];
   PivotRec pivotsLo[MAX_PIVOTS];
   int      pivHiCnt;
   int      pivLoCnt;
};

struct OBRecord {
   datetime  originTime;     // timestamp of OB candle
   datetime  eventTime;      // when structure break confirmed
   double    top;
   double    bottom;
   double    midpoint;
   bool      isBullish;      // true=bullish OB, false=bearish OB
   bool      isSwing;        // true=swing OB, false=internal OB
   bool      mitigated;
   bool      invalidated;
   datetime  mitigationTime;
};

struct FVGRecord {
   datetime  formTime;
   double    top;
   double    bottom;
   bool      isBullish;
   bool      mitigated;
   int       lastCheckedBar;  // avoid full rescan
};

struct EQPair {
   datetime  timeA, timeB;
   double    priceA, priceB;
   bool      isHigh;         // true=EQH, false=EQL
   bool      swept;
   datetime  sweepTime;
};

// ═════════════════════════════════════════════════════════════════════════════
// INDICATOR BUFFERS
// ═════════════════════════════════════════════════════════════════════════════
double g_intSwHi[];       // 0   Internal swing high markers
double g_intSwLo[];       // 1   Internal swing low markers
double g_swSwHi[];        // 2   Swing high markers
double g_swSwLo[];        // 3   Swing low markers
double g_candleO[];       // 4   Candle open  (for DRAW_COLOR_CANDLES)
double g_candleH[];       // 5   Candle high
double g_candleL[];       // 6   Candle low
double g_candleC[];       // 7   Candle close
double g_candleCol[];     // 8   Candle color index
double g_obHi[];          // 9   OB high (iCustom)
double g_obLo[];          // 10  OB low
double g_fvgBull[];       // 11  FVG bullish
double g_fvgBear[];       // 12  FVG bearish
double g_biasSig[];       // 13  Bias signal (+1 bull, -1 bear)
double g_pdh[];           // 14  Prev day high
double g_pdl[];           // 15  Prev day low (unused plot, drawn via objects)
double g_pwh[];           // 16  Prev week high
double g_pwl[];           // 17  Prev week low

// ═════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═════════════════════════════════════════════════════════════════════════════
string           g_prefix;           // SMC_<chartID>_<tf>__
StructureState   g_int;             // Internal structure
StructureState   g_sw;              // Swing structure
OBRecord         g_intOBs[];        // Internal order blocks
OBRecord         g_swOBs[];         // Swing order blocks
FVGRecord        g_fvgs[];          // Active FVGs
EQPair           g_eqPairs[];       // EQH/EQL pairs
datetime         g_prevDayHigh, g_prevDayLow;
datetime         g_prevWeekHigh, g_prevWeekLow;
datetime         g_prevMonthHigh, g_prevMonthLow;
double           g_dh, g_dl, g_wh, g_wl, g_mh, g_ml;  // previous period values
datetime         g_pdzPremTime, g_pdzDiscTime, g_pdzEqTime;// for single PDZ update
int              g_instanceId;      // unique instance (based on GetTickCount at init)
datetime         g_lastBarTime;     // for new-bar detection
datetime         g_lastAlertBar;
string           g_lastAlertType;
datetime         g_lastCalcDay, g_lastCalcWeek, g_lastCalcMonth;  // prev-HL markers

// ═════════════════════════════════════════════════════════════════════════════
// FORWARD DECLARATIONS
// ═════════════════════════════════════════════════════════════════════════════
bool   IsPivotHigh(const double &h[], int len, int i, int total);
bool   IsPivotLow(const double &l[], int len, int i, int total);
void   StorePivot(PivotRec &buf[], int &cnt, int bar, double price, datetime t);
void   ProcessBarHistory(const double &o[], const double &h[], const double &l[],
                        const double &c[], const datetime &t[], int i, int total,
                        double pointSize);
void   ProcessBarLive(const double &o[], const double &h[], const double &l[],
                      const double &c[], const datetime &t[], int i, int total,
                      double pointSize, bool isLiveClosedBar);
void   ConfirmPivotCandidates(const double &o[], const double &h[], const double &l[],
                               const double &c[], const datetime &t[], int fromBar,
                               int toBar, int total, double pointSize);
void   EvalStructure(StructureState &st, const double &o[], const double &h[],
                     const double &l[], const double &c[], const datetime &t[],
                     int i, int total, int pivotLen, bool isSwing,
                     double pointSize, bool isLiveClosedBar);
void   DrawStructureLine(datetime fromTime, double level, datetime toTime,
                          string prefix, string label, color clr);
void   ManageOrderBlocks(const double &h[], const double &l[], const double &o[],
                          const double &c[], const datetime &t[], int total);
void   ManageOBCollection(OBRecord &obs[], int maxCount, const double &h[],
                           const double &l[], const double &c[], const datetime &t[], int total);
void   ManageFVGs(const double &h[], const double &l[], const double &c[],
                   const datetime &t[], int total);
void   ManageEQLevels(const double &h[], const double &l[], const datetime &t[],
                       int total, double pointSize);
void   ManageEQCollection(PivotRec &pivs[], int cnt, bool isHigh, double tol,
                           const double &h[], const double &l[], const datetime &t[], int total);
void   ManagePrevHL(const double &h[], const double &l[], const datetime &t[],
                     int total);
void   ManagePDZ(const double &h[], const double &l[], const datetime &t[],
                  int total);
void   DrawCandleColor(int i, int biasDir);
void   DrawLabel(datetime barTime, double price, string text, color clr, string suffix);
void   FireAlert(string type, string detail, datetime barTime, double price, bool isNewBar);
void   CleanupAll();
void   CreateOrderBlock(bool isBullOB, bool isSwing, int breakBar, int priorPivotBar,
                         const double &h[], const double &l[], const double &o[],
                         const double &c[], const datetime &t[], int total);
void   AddFVG(datetime formTime, double top, double bottom, bool isBullish);
string MakeFVGName(const FVGRecord &fvg);
void   DrawPeriodLine(string label, double price, datetime fromTime, color clr);
void   ResetAllState();
string MakeOBName(const OBRecord &ob);
void   ManageOBCollection(OBRecord &obs[], int maxCount, const double &h[],
                           const double &l[], const double &c[], const datetime &t[], int total);
void   ManageEQCollection(PivotRec &pivs[], int cnt, bool isHigh, double tol,
                           const double &h[], const double &l[], const datetime &t[], int total);

// ═════════════════════════════════════════════════════════════════════════════
// ONINIT
// ═════════════════════════════════════════════════════════════════════════════
int OnInit()
{
   if(InpIntSwingLen < 2)  { Print("[SMC] Internal pivot length must be >= 2");  return INIT_PARAMETERS_INCORRECT; }
   if(InpSwSwingLen < 3)   { Print("[SMC] Swing pivot length must be >= 3");     return INIT_PARAMETERS_INCORRECT; }
   if(InpIntSwingLen >= InpSwSwingLen) { Print("[SMC] Internal length must be < Swing length"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxIntOB < 0)     { Print("[SMC] Max Internal OBs must be >= 0");       return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxSwOB < 0)      { Print("[SMC] Max Swing OBs must be >= 0");          return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxFVGs < 0)      { Print("[SMC] Max FVGs must be >= 0");               return INIT_PARAMETERS_INCORRECT; }

   g_instanceId = (int)GetTickCount();
   g_prefix = StringFormat("SMC_%d_%d_", ChartID(), g_instanceId);

   // ── Buffers: NON-SERIES (index 0 = oldest bar) ──
   SetIndexBuffer(0,  g_intSwHi,  INDICATOR_DATA);
   SetIndexBuffer(1,  g_intSwLo,  INDICATOR_DATA);
   SetIndexBuffer(2,  g_swSwHi,   INDICATOR_DATA);
   SetIndexBuffer(3,  g_swSwLo,   INDICATOR_DATA);
   SetIndexBuffer(4,  g_candleO,  INDICATOR_DATA);
   SetIndexBuffer(5,  g_candleH,  INDICATOR_DATA);
   SetIndexBuffer(6,  g_candleL,  INDICATOR_DATA);
   SetIndexBuffer(7,  g_candleC,  INDICATOR_DATA);
   SetIndexBuffer(8,  g_candleCol,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(9,  g_obHi,     INDICATOR_DATA);
   SetIndexBuffer(10, g_obLo,     INDICATOR_DATA);
   SetIndexBuffer(11, g_fvgBull,  INDICATOR_DATA);
   SetIndexBuffer(12, g_fvgBear,  INDICATOR_DATA);
   SetIndexBuffer(13, g_biasSig,  INDICATOR_DATA);
   SetIndexBuffer(14, g_pdh,      INDICATOR_DATA);
   SetIndexBuffer(15, g_pdl,      INDICATOR_DATA);
   SetIndexBuffer(16, g_pwh,      INDICATOR_DATA);
   SetIndexBuffer(17, g_pwl,      INDICATOR_DATA);

   // Arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 108);  PlotIndexSetInteger(1, PLOT_ARROW, 108);
   PlotIndexSetInteger(2, PLOT_ARROW, 108);  PlotIndexSetInteger(3, PLOT_ARROW, 108);

   for(int p = 0; p < 12; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Candle coloring: 2 colors (bull=0 lime, bear=1 red) — plot index 4
   PlotIndexSetInteger(4, PLOT_DRAW_BEGIN, 0);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, clrLime);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, clrRed);

   ZeroMemory(g_int);  ZeroMemory(g_sw);
   g_int.trendBull = true;  g_sw.trendBull = true;
   g_int.biasEstablished = false;  g_sw.biasEstablished = false;

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC LuxAlgo v3");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r) { CleanupAll(); }

// ═════════════════════════════════════════════════════════════════════════════
// ONCALCULATE — CHRONOLOGICAL, NON-SERIES, MODEL A (no replay)
// ═════════════════════════════════════════════════════════════════════════════
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[],
                const long &tv[], const long &v[], const int &sp[])
{
   ArraySetAsSeries(t, false);  ArraySetAsSeries(o, false);
   ArraySetAsSeries(h, false);  ArraySetAsSeries(l, false);
   ArraySetAsSeries(c, false);

   int minB = InpSwSwingLen * 3 + 10;
   if(rates_total < minB) return 0;

   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   bool fullRebuild = (prev_calculated == 0);

   if(fullRebuild)
   {
      ResetAllState();
      // Set lastBarTime BEFORE the historical loop (avoids isNewBar=true on rebuild)
      g_lastBarTime = t[rates_total-1];

      for(int i = 0; i < rates_total; i++)
      {
         g_candleO[i]  = o[i];   g_candleH[i]  = h[i];
         g_candleL[i]  = l[i];   g_candleC[i]  = c[i];
         g_candleCol[i] = EMPTY_VALUE;
         g_intSwHi[i]  = EMPTY_VALUE;  g_intSwLo[i]  = EMPTY_VALUE;
         g_swSwHi[i]   = EMPTY_VALUE;  g_swSwLo[i]   = EMPTY_VALUE;
         g_obHi[i]     = EMPTY_VALUE;  g_obLo[i]     = EMPTY_VALUE;
         g_fvgBull[i]  = EMPTY_VALUE;  g_fvgBear[i]  = EMPTY_VALUE;
         g_biasSig[i]  = 0;
         g_pdh[i]      = EMPTY_VALUE;  g_pdl[i]      = EMPTY_VALUE;
         g_pwh[i]      = EMPTY_VALUE;  g_pwl[i]      = EMPTY_VALUE;
      }
      for(int i = minB; i < rates_total; i++)
         ProcessBarHistory(o, h, l, c, t, i, rates_total, pointSize);
   }
   else
   {
      // Detect new bar BEFORE processing
      bool isNewBar = (rates_total > 1 && t[rates_total-1] != g_lastBarTime);
      if(isNewBar)
         g_lastBarTime = t[rates_total-1];

      // Process the newly closed bar (rates_total-2) and any bars not yet calculated
      int lastClosed = rates_total - 2;
      int startBar   = (prev_calculated > minB) ? prev_calculated : minB;
      if(startBar > lastClosed) startBar = lastClosed;  // guard against empty range

      // If a new bar just closed, also check for newly confirmed pivots
      if(isNewBar)
      {
         // Internal pivot candidate: lastClosed - InpIntSwingLen
         int intCand = lastClosed - InpIntSwingLen;
         if(intCand >= minB && intCand < startBar)
         {
            // Reprocess from candidate to catch the newly confirmed pivot
            // But only add pivots — don't re-evaluate breaks on old bars
            ConfirmPivotCandidates(o, h, l, c, t, intCand, startBar - 1, rates_total, pointSize);
         }
         // Swing pivot candidate
         int swCand = lastClosed - InpSwSwingLen;
         if(swCand >= minB && swCand < startBar && swCand != intCand)
         {
            ConfirmPivotCandidates(o, h, l, c, t, swCand, startBar - 1, rates_total, pointSize);
         }
      }

      for(int i = startBar; i <= lastClosed; i++)
      {
         g_candleO[i] = o[i];  g_candleH[i] = h[i];
         g_candleL[i] = l[i];  g_candleC[i] = c[i];
         g_intSwHi[i] = EMPTY_VALUE;  g_intSwLo[i] = EMPTY_VALUE;
         g_swSwHi[i]  = EMPTY_VALUE;  g_swSwLo[i]  = EMPTY_VALUE;
         g_obHi[i]    = EMPTY_VALUE;  g_obLo[i]    = EMPTY_VALUE;
         g_fvgBull[i] = EMPTY_VALUE;  g_fvgBear[i] = EMPTY_VALUE;
         g_biasSig[i] = 0;
         bool isLiveClosedBar = isNewBar && (i == lastClosed);
         ProcessBarLive(o, h, l, c, t, i, rates_total, pointSize, isLiveClosedBar);
      }
   }

   ManageOrderBlocks(h, l, o, c, t, rates_total);
   ManageFVGs(h, l, c, t, rates_total);
   ManagePrevHL(h, l, t, rates_total);
   ManageEQLevels(h, l, t, rates_total, pointSize);
   ManagePDZ(h, l, t, rates_total);

   return rates_total;
}

// ── History bar processor (no alerts, builds state) ──
void ProcessBarHistory(const double &o[], const double &h[], const double &l[],
                       const double &c[], const datetime &t[], int i, int total,
                       double pointSize)
{
   EvalStructure(g_int, o, h, l, c, t, i, total, InpIntSwingLen, false, pointSize, false);
   EvalStructure(g_sw,  o, h, l, c, t, i, total, InpSwSwingLen, true,  pointSize, false);
   if(InpColorCandles)
   {
      if(InpColorSource == SOURCE_SWING) DrawCandleColor(i, g_sw.trendBull ? 1 : -1);
      else                                DrawCandleColor(i, g_int.trendBull ? 1 : -1);
   }
   // FVG: only closed bars, no forming
   if(InpShowFVG && i >= 2 && i < total - 1)
   {
      if(l[i] > h[i-2] && (InpFVGMinSize <= 0 || l[i]-h[i-2] >= InpFVGMinSize*pointSize))
      { g_fvgBull[i] = l[i]-h[i-2]; AddFVG(t[i], l[i], h[i-2], true); }
      if(h[i] < l[i-2] && (InpFVGMinSize <= 0 || l[i-2]-h[i] >= InpFVGMinSize*pointSize))
      { g_fvgBear[i] = l[i-2]-h[i]; AddFVG(t[i], h[i], l[i-2], false); }
   }
   if(InpShowPDH) { g_pdh[i] = g_dh; g_pdl[i] = g_dl; }
   if(InpShowPWH) { g_pwh[i] = g_wh; g_pwl[i] = g_wl; }
}

// ── Live bar processor (alerts enabled for newest closed bar) ──
void ProcessBarLive(const double &o[], const double &h[], const double &l[],
                    const double &c[], const datetime &t[], int i, int total,
                    double pointSize, bool isLiveClosedBar)
{
   EvalStructure(g_int, o, h, l, c, t, i, total, InpIntSwingLen, false, pointSize, isLiveClosedBar);
   EvalStructure(g_sw,  o, h, l, c, t, i, total, InpSwSwingLen, true,  pointSize, isLiveClosedBar);
   if(InpColorCandles)
   {
      if(InpColorSource == SOURCE_SWING) DrawCandleColor(i, g_sw.trendBull ? 1 : -1);
      else                                DrawCandleColor(i, g_int.trendBull ? 1 : -1);
   }
   if(InpShowFVG && i >= 2 && i < total - 1)
   {
      if(l[i] > h[i-2] && (InpFVGMinSize <= 0 || l[i]-h[i-2] >= InpFVGMinSize*pointSize))
      { g_fvgBull[i] = l[i]-h[i-2]; AddFVG(t[i], l[i], h[i-2], true); }
      if(h[i] < l[i-2] && (InpFVGMinSize <= 0 || l[i-2]-h[i] >= InpFVGMinSize*pointSize))
      { g_fvgBear[i] = l[i-2]-h[i]; AddFVG(t[i], h[i], l[i-2], false); }
   }
   if(InpShowPDH) { g_pdh[i] = g_dh; g_pdl[i] = g_dl; }
   if(InpShowPWH) { g_pwh[i] = g_wh; g_pwl[i] = g_wl; }
}

// ── Confirm pivot candidates in a lookback range (pivot-only, no breaks) ──
void ConfirmPivotCandidates(const double &o[], const double &h[], const double &l[],
                             const double &c[], const datetime &t[], int fromBar,
                             int toBar, int total, double pointSize)
{
   for(int i = fromBar; i <= toBar && i < total; i++)
   {
      if(IsPivotHigh(h, InpIntSwingLen, i, total))
      {
         StorePivot(g_int.pivotsHi, g_int.pivHiCnt, i, h[i], t[i]);
         if(InpShowIntStruct) g_intSwHi[i] = h[i];
      }
      if(IsPivotLow(l, InpIntSwingLen, i, total))
      {
         StorePivot(g_int.pivotsLo, g_int.pivLoCnt, i, l[i], t[i]);
         if(InpShowIntStruct) g_intSwLo[i] = l[i];
      }
      if(IsPivotHigh(h, InpSwSwingLen, i, total))
      {
         StorePivot(g_sw.pivotsHi, g_sw.pivHiCnt, i, h[i], t[i]);
         if(InpShowSwStruct) g_swSwHi[i] = h[i];
      }
      if(IsPivotLow(l, InpSwSwingLen, i, total))
      {
         StorePivot(g_sw.pivotsLo, g_sw.pivLoCnt, i, l[i], t[i]);
         if(InpShowSwStruct) g_swSwLo[i] = l[i];
      }
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// STRUCTURE EVALUATION ENGINE (internal + swing)
// ═════════════════════════════════════════════════════════════════════════════
void EvalStructure(StructureState &st, const double &o[], const double &h[],
                   const double &l[], const double &c[], const datetime &t[],
                   int i, int total, int pivotLen, bool isSwing,
                   double pointSize, bool isLiveClosedBar)
{
   bool showStruct = isSwing ? InpShowSwStruct : InpShowIntStruct;
   bool showBOS    = isSwing ? InpShowSwBOS    : InpShowIntBOS;
   bool showCHoCH  = isSwing ? InpShowSwCHoCH  : InpShowIntCHoCH;
   string prefix   = isSwing ? "SW_" : "INT_";

   // ── PIVOT DETECTION ──
   if(IsPivotHigh(h, pivotLen, i, total))
   {
      StorePivot(st.pivotsHi, st.pivHiCnt, i, h[i], t[i]);

      // Mark swing point buffer
      if(showStruct)
      {
         if(isSwing) g_swSwHi[i] = h[i];
         else        g_intSwHi[i] = h[i];
      }

      // Update strong/weak tracking
      if(st.pivHiCnt >= 2)
      {
         int prev = st.pivHiCnt - 2;
         st.strongHigh = (st.pivotsHi[st.pivHiCnt-1].price > st.pivotsHi[prev].price);
      }

      // Set active high level
      st.activeHigh     = h[i];
      st.activeHighBar  = i;
      st.activeHighTime = t[i];

      // Trailing high
      if(h[i] > st.trailHigh || st.trailHigh == 0)
      {
         st.trailHigh     = h[i];
         st.trailHighBar  = i;
      }
   }

   if(IsPivotLow(l, pivotLen, i, total))
   {
      StorePivot(st.pivotsLo, st.pivLoCnt, i, l[i], t[i]);

      if(showStruct)
      {
         if(isSwing) g_swSwLo[i] = l[i];
         else        g_intSwLo[i] = l[i];
      }

      if(st.pivLoCnt >= 2)
      {
         int prev = st.pivLoCnt - 2;
         st.strongLow = (st.pivotsLo[st.pivLoCnt-1].price < st.pivotsLo[prev].price);
      }

      st.activeLow     = l[i];
      st.activeLowBar  = i;
      st.activeLowTime = t[i];

      if(l[i] < st.trailLow || st.trailLow == 0)
      {
         st.trailLow     = l[i];
         st.trailLowBar  = i;
      }
   }

   // ── PER-BAR STRUCTURE BREAK CHECK ──
   // Skip the forming bar (rightmost)
   if(i >= total - 1) return;

   // ── Bullish break: close above active swing high ──
   if(st.activeHigh > 0 && st.pivHiCnt >= 2)
   {
      // Find the prior un-consumed swing high
      double priorHi = 0;
      int    priorBar = -1;
      datetime priorTime = 0;
      for(int j = st.pivHiCnt - 1; j >= 0; j--)
      {
         if(!st.pivotsHi[j].consumed && st.pivotsHi[j].barIdx < i)
         {
            priorHi   = st.pivotsHi[j].price;
            priorBar  = st.pivotsHi[j].barIdx;
            priorTime = st.pivotsHi[j].time;
            break;
         }
      }
      // Explicit crossover: previous close was NOT above the level
      if(priorHi > 0 && c[i] > priorHi && i > priorBar + 1 &&
         (i == 0 || c[i-1] <= priorHi))
      {
         // Mark consumed
         for(int j = st.pivHiCnt - 1; j >= 0; j--)
         {
            if(st.pivotsHi[j].barIdx == priorBar)
               st.pivotsHi[j].consumed = true;
         }

         // Establish bias from first confirmed pivot pair
         if(!st.biasEstablished && st.pivHiCnt >= 2 && st.pivLoCnt >= 2)
            st.biasEstablished = true;

         if(!st.biasEstablished || st.trendBull)
         {
            // BOS — continuation
            if(showBOS)
            {
               DrawStructureLine(priorTime, priorHi, t[i], prefix, "BOS ▲", clrLime);
               FireAlert(isSwing ? "Swing" : "Internal", "BOS Bullish", t[i], c[i], isLiveClosedBar);
            }
            st.lastBOSBar = i;
            g_biasSig[i] = 1;
            if(InpOBFromBOS)
               CreateOrderBlock(true, isSwing, i, priorBar, h, l, o, c, t, total);
         }
         else
         {
            // CHoCH — reversal
            if(showCHoCH)
            {
               DrawStructureLine(priorTime, priorHi, t[i], prefix, "CHoCH ▲", clrAqua);
               FireAlert(isSwing ? "Swing" : "Internal", "CHoCH Bullish", t[i], c[i], isLiveClosedBar);
            }
            st.lastCHoCHBar = i;
            st.trendBull = true;
            g_biasSig[i] = 1;

            CreateOrderBlock(true, isSwing, i, priorBar, h, l, o, c, t, total);
         }
      }
   }

   // ── Bearish break: close below active swing low ──
   if(st.activeLow > 0 && st.pivLoCnt >= 2)
   {
      double priorLo = 0;
      int    priorBar = -1;
      datetime priorTime = 0;
      for(int j = st.pivLoCnt - 1; j >= 0; j--)
      {
         if(!st.pivotsLo[j].consumed && st.pivotsLo[j].barIdx < i)
         {
            priorLo   = st.pivotsLo[j].price;
            priorBar  = st.pivotsLo[j].barIdx;
            priorTime = st.pivotsLo[j].time;
            break;
         }
      }
      // Explicit crossover: previous close was NOT below the level
      if(priorLo > 0 && c[i] < priorLo && i > priorBar + 1 &&
         (i == 0 || c[i-1] >= priorLo))
      {
         for(int j = st.pivLoCnt - 1; j >= 0; j--)
         {
            if(st.pivotsLo[j].barIdx == priorBar)
               st.pivotsLo[j].consumed = true;
         }

         if(!st.biasEstablished && st.pivHiCnt >= 2 && st.pivLoCnt >= 2)
            st.biasEstablished = true;

         if(!st.biasEstablished || !st.trendBull)
         {
            if(showBOS)
            {
               DrawStructureLine(priorTime, priorLo, t[i], prefix, "BOS ▼", clrRed);
               FireAlert(isSwing ? "Swing" : "Internal", "BOS Bearish", t[i], c[i], isLiveClosedBar);
            }
            st.lastBOSBar = i;
            g_biasSig[i] = -1;
            if(InpOBFromBOS)
               CreateOrderBlock(false, isSwing, i, priorBar, h, l, o, c, t, total);
         }
         else
         {
            if(showCHoCH)
            {
               DrawStructureLine(priorTime, priorLo, t[i], prefix, "CHoCH ▼", clrOrange);
               FireAlert(isSwing ? "Swing" : "Internal", "CHoCH Bearish", t[i], c[i], isLiveClosedBar);
            }
            st.lastCHoCHBar = i;
            st.trendBull = false;
            g_biasSig[i] = -1;

            CreateOrderBlock(false, isSwing, i, priorBar, h, l, o, c, t, total);
         }
      }
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// ORDER BLOCK CREATION (triggered by validated CHoCH events)
// ═════════════════════════════════════════════════════════════════════════════
void CreateOrderBlock(bool isBullOB, bool isSwing, int breakBar, int priorPivotBar,
                       const double &h[], const double &l[], const double &o[],
                       const double &c[], const datetime &t[], int total)
{
   if(isSwing && !InpShowSwOB)  return;
   if(!isSwing && !InpShowIntOB) return;
   if(isSwing && InpMaxSwOB <= 0)  return;
   if(!isSwing && InpMaxIntOB <= 0) return;

   // Search between prior pivot and breakBar (constrained to structural leg)
   int obBar = -1;
   int searchStart = breakBar - 1;
   int searchEnd   = priorPivotBar + 1;
   if(searchEnd < 0) searchEnd = 0;
   for(int j = searchStart; j >= searchEnd; j--)
   {
      bool isBear = (c[j] < o[j]);
      bool isBull = (c[j] > o[j]);

      if(isBullOB && isBear) { obBar = j; break; }
      if(!isBullOB && isBull) { obBar = j; break; }
   }
   if(obBar < 0) return;

   // MQL5 cannot bind an array reference through a conditional expression.
   // Check each collection explicitly and deduplicate against the actual origin candle.
   if(isSwing)
   {
      for(int d = ArraySize(g_swOBs)-1; d >= 0; d--)
         if(g_swOBs[d].originTime == t[obBar] && g_swOBs[d].isBullish == isBullOB) return;
   }
   else
   {
      for(int d = ArraySize(g_intOBs)-1; d >= 0; d--)
         if(g_intOBs[d].originTime == t[obBar] && g_intOBs[d].isBullish == isBullOB) return;
   }

   OBRecord rec;
   rec.originTime = t[obBar];
   rec.eventTime  = t[breakBar];
   rec.top        = h[obBar];
   rec.bottom     = l[obBar];
   rec.midpoint   = (h[obBar] + l[obBar]) / 2.0;
   rec.isBullish  = isBullOB;
   rec.isSwing    = isSwing;
   rec.mitigated  = false;
   rec.invalidated = false;

   if(isSwing)
   {
      int sz = ArraySize(g_swOBs);
      // Remove oldest if at limit — also delete its chart object
      if(sz >= InpMaxSwOB && sz > 0)
      {
         string oldNm = MakeOBName(g_swOBs[0]);
         if(ObjectFind(0, oldNm) >= 0) ObjectDelete(0, oldNm);
         for(int k = 0; k < sz-1; k++) g_swOBs[k] = g_swOBs[k+1];
         ArrayResize(g_swOBs, sz-1);
         sz--;
      }
      ArrayResize(g_swOBs, sz+1);
      g_swOBs[sz] = rec;
   }
   else
   {
      int sz = ArraySize(g_intOBs);
      if(sz >= InpMaxIntOB && sz > 0)
      {
         string oldNm = MakeOBName(g_intOBs[0]);
         if(ObjectFind(0, oldNm) >= 0) ObjectDelete(0, oldNm);
         for(int k = 0; k < sz-1; k++) g_intOBs[k] = g_intOBs[k+1];
         ArrayResize(g_intOBs, sz-1);
         sz--;
      }
      ArrayResize(g_intOBs, sz+1);
      g_intOBs[sz] = rec;
   }

   // Populate buffer
   g_obHi[obBar] = h[obBar];
   g_obLo[obBar] = l[obBar];

   // Draw rectangle using consistent timestamp-based name
   string nm = MakeOBName(rec);
   if(ObjectFind(0, nm) < 0)
   {
      datetime tEnd = t[obBar] + PeriodSeconds() * 5000;
      color clr = isBullOB ? C'0x21,0x57,0xF3' : C'0xF2,0x36,0x45';
      if(ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t[obBar], h[obBar], tEnd, l[obBar]))
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_FILL, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
   }
}

void ManageOrderBlocks(const double &h[], const double &l[], const double &o[],
                        const double &c[], const datetime &t[], int total)
{
   int lastBar = total - 1;
   if(lastBar < 0) return;

   // Process both OB collections — explicit calls, no conditional references
   ManageOBCollection(g_swOBs, InpMaxSwOB, h, l, c, t, total);
   ManageOBCollection(g_intOBs, InpMaxIntOB, h, l, c, t, total);
}

// ── OB collection helper (avoids conditional array reference) ──
void ManageOBCollection(OBRecord &obs[], int maxCount, const double &h[],
                         const double &l[], const double &c[], const datetime &t[], int total)
{
   int lastBar = total - 1;
   if(lastBar < 0) return;

   for(int k = ArraySize(obs) - 1; k >= 0; k--)
   {
      if(obs[k].mitigated || obs[k].invalidated) continue;

      // Consistent OB name from origin timestamp
      string nm = MakeOBName(obs[k]);
      // Check mitigation
      for(int bar = 0; bar < total; bar++)
      {
         if(t[bar] <= obs[k].eventTime) continue;
         bool hit = false;
         switch(InpOBMitigation)
         {
            case OB_MIT_TOUCH:
               hit = (l[bar] <= obs[k].top && h[bar] >= obs[k].bottom);
               break;
            case OB_MIT_WICK:
               // Direction-aware wick test
               if(obs[k].isBullish)
                  hit = (l[bar] <= obs[k].midpoint);
               else
                  hit = (h[bar] >= obs[k].midpoint);
               break;
            case OB_MIT_CLOSE:
               // Direction-aware close mitigation
               if(obs[k].isBullish)
                  hit = (c[bar] <= obs[k].midpoint && c[bar] > obs[k].bottom);
               else
                  hit = (c[bar] >= obs[k].midpoint && c[bar] < obs[k].top);
               break;
            case OB_MIT_FULL:
               // Full = invalidation: close beyond the block in the wrong direction
               if(obs[k].isBullish)
                  hit = (c[bar] < obs[k].bottom);  // close below = invalidated
               else
                  hit = (c[bar] > obs[k].top);     // close above = invalidated
               break;
         }
         if(hit)
         {
            if(InpOBMitigation == OB_MIT_FULL)
               obs[k].invalidated = true;
            else
               obs[k].mitigated = true;
            obs[k].mitigationTime = t[bar];
            if(ObjectFind(0, nm) >= 0)
            {
               ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[bar]);
               ObjectSetInteger(0, nm, OBJPROP_COLOR, clrGray);
            }
            break;
         }
      }
      // Extend active OB rectangle to current bar
      if(!obs[k].mitigated && ObjectFind(0, nm) >= 0)
         ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[lastBar] + PeriodSeconds() * 5);
   }
}

// ── Consistent OB object name generator ──
string MakeOBName(const OBRecord &ob)
{
   return g_prefix + "OB_" + (ob.isSwing ? "SW_" : "INT_") +
          (ob.isBullish ? "B_" : "S_") + IntegerToString((long)ob.originTime);
}

// ═════════════════════════════════════════════════════════════════════════════
// FVG ENGINE
// ═════════════════════════════════════════════════════════════════════════════
void AddFVG(datetime formTime, double top, double bottom, bool isBullish)
{
   // Dedup: skip if already exists in records
   for(int k = ArraySize(g_fvgs)-1; k >= 0; k--)
      if(g_fvgs[k].formTime == formTime) return;

   int sz = ArraySize(g_fvgs);
   if(sz >= InpMaxFVGs && sz > 0)
   {
      // Delete chart object for the oldest FVG being evicted
      string oldNm = MakeFVGName(g_fvgs[0]);
      if(ObjectFind(0, oldNm) >= 0) ObjectDelete(0, oldNm);
      for(int k = 0; k < sz-1; k++) g_fvgs[k] = g_fvgs[k+1];
      ArrayResize(g_fvgs, sz-1);
      sz--;
   }
   FVGRecord rec;
   rec.formTime = formTime;  rec.top = top;  rec.bottom = bottom;
   rec.isBullish = isBullish;  rec.mitigated = false;
   ArrayResize(g_fvgs, sz+1);
   g_fvgs[sz] = rec;

   string nm = MakeFVGName(rec);
   if(ObjectFind(0, nm) < 0)
   {
      datetime tEnd = formTime + PeriodSeconds() * 5000;
      if(ObjectCreate(0, nm, OBJ_RECTANGLE, 0, formTime, top, tEnd, bottom))
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, isBullish ? C'0x08,0x99,0x81' : C'0xF2,0x36,0x45');
         ObjectSetInteger(0, nm, OBJPROP_FILL, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
   }
}

string MakeFVGName(const FVGRecord &fvg)
{
   return g_prefix + "FVG_" + (fvg.isBullish ? "B_" : "S_") + IntegerToString((long)fvg.formTime);
}

void ManageFVGs(const double &h[], const double &l[], const double &c[],
                 const datetime &t[], int total)
{
   int lastBar = total - 1;
   if(lastBar < 0) return;

   for(int k = ArraySize(g_fvgs) - 1; k >= 0; k--)
   {
      if(g_fvgs[k].mitigated) continue;

      double gapHi = MathMax(g_fvgs[k].top, g_fvgs[k].bottom);
      double gapLo = MathMin(g_fvgs[k].top, g_fvgs[k].bottom);
      double mid   = (gapHi + gapLo) / 2.0;
      bool   isBull = g_fvgs[k].isBullish;

      // Only scan bars after last checked
      int startBar = g_fvgs[k].lastCheckedBar + 1;
      if(startBar < 0) startBar = 0;

      for(int bar = startBar; bar < total; bar++)
      {
         if(t[bar] <= g_fvgs[k].formTime) continue;

         bool hit = false;
         switch(InpFVGMitigation)
         {
            case FVG_MIT_TOUCH:
               hit = (l[bar] <= gapHi && h[bar] >= gapLo);
               break;
            case FVG_MIT_MID:
               hit = (h[bar] >= mid && l[bar] <= mid);
               break;
            case FVG_MIT_CLOSE:
               // Direction-aware: bullish FVG mitigated by close below midpoint
               if(isBull)
                  hit = (c[bar] <= mid && c[bar] >= gapLo);
               else
                  hit = (c[bar] >= mid && c[bar] <= gapHi);
               break;
            case FVG_MIT_FULL:
               // Track deepest penetration cumulatively
               if(isBull)
               {
                  if(l[bar] < g_fvgs[k].bottom)
                     g_fvgs[k].bottom = l[bar];  // lower the bottom as price fills
                  hit = (g_fvgs[k].bottom <= g_fvgs[k].top + (gapHi-gapLo)*0.1);
               }
               else
               {
                  if(h[bar] > g_fvgs[k].top)
                     g_fvgs[k].top = h[bar];
                  hit = (g_fvgs[k].top >= g_fvgs[k].bottom - (gapHi-gapLo)*0.1);
               }
               break;
         }
         g_fvgs[k].lastCheckedBar = bar;

         if(hit)
         {
            g_fvgs[k].mitigated = true;
            string nm = MakeFVGName(g_fvgs[k]);
            if(ObjectFind(0, nm) >= 0)
            {
               ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[bar]);
               ObjectSetInteger(0, nm, OBJPROP_COLOR, clrGray);
            }
            break;
         }
      }

      // Extend active FVG rectangle to current bar
      if(!g_fvgs[k].mitigated)
      {
         string nm = MakeFVGName(g_fvgs[k]);
         if(ObjectFind(0, nm) >= 0)
            ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[lastBar] + PeriodSeconds() * 5);
      }
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// EQH / EQL
// ═════════════════════════════════════════════════════════════════════════════
void ManageEQLevels(const double &h[], const double &l[], const datetime &t[],
                     int total, double pointSize)
{
   if(!InpShowEQ) return;
   double tol = InpEQTolerance / 100.0;

   // Use SWING pivots for EQH/EQL — explicit calls, no conditional references
   ManageEQCollection(g_sw.pivotsHi, g_sw.pivHiCnt, true,  tol, h, l, t, total);
   ManageEQCollection(g_sw.pivotsLo, g_sw.pivLoCnt, false, tol, h, l, t, total);
}

// ── EQ collection helper (avoids conditional array reference) ──
void ManageEQCollection(PivotRec &pivs[], int cnt, bool isHigh, double tol,
                         const double &h[], const double &l[], const datetime &t[], int total)
{
   for(int a = 0; a < cnt - 1; a++)
   {
      for(int b = a + 1; b < cnt; b++)
      {
         if(pivs[a].consumed || pivs[b].consumed) continue;
         if(MathAbs(pivs[a].price - pivs[b].price) / MathMax(pivs[a].price, 0.00001) < tol)
         {
            if(total - 1 - pivs[b].barIdx < InpEQConfirmBars) continue;

            string nm = g_prefix + "EQ_" + (isHigh ? "H_" : "L_") +
                        IntegerToString((long)pivs[a].time) + "_" + IntegerToString((long)pivs[b].time);
            if(ObjectFind(0, nm) >= 0) continue;

            bool swept = false;
            double level = (pivs[a].price + pivs[b].price) / 2.0;
            for(int bar = pivs[b].barIdx + 1; bar < total; bar++)
            {
               if((isHigh && h[bar] > level) || (!isHigh && l[bar] < level))
               { swept = true; break; }
            }

            datetime t1 = pivs[a].time;
            datetime t2 = pivs[b].time;
            datetime tEnd = swept ? t[total-1] : t[total-1] + PeriodSeconds() * 500;
            color clr = swept ? clrGray : (isHigh ? clrOrange : clrDodgerBlue);

            if(ObjectCreate(0, nm, OBJ_TREND, 0, t1, level, tEnd, level))
            {
               ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
               ObjectSetInteger(0, nm, OBJPROP_STYLE, swept ? STYLE_DOT : STYLE_SOLID);
               ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, !swept);
               ObjectSetInteger(0, nm, OBJPROP_BACK, true);
               ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
            }
            if(InpShowLabels)
            {
               string lnm = nm + "_LBL";
               if(ObjectCreate(0, lnm, OBJ_TEXT, 0, t2, level))
               {
                  ObjectSetString(0, lnm, OBJPROP_TEXT, isHigh ? "EQH" : "EQL");
                  ObjectSetInteger(0, lnm, OBJPROP_COLOR, clr);
                  ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE, 7);
               }
            }
         }
      }
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// PREVIOUS D/W/M HIGHS & LOWS
// ═════════════════════════════════════════════════════════════════════════════
void ManagePrevHL(const double &h[], const double &l[], const datetime &t[],
                   int total)
{
   int lastBar = total - 1;
   if(lastBar < 2) return;

   datetime barTime = t[lastBar];
   MqlDateTime dt;
   TimeToStruct(barTime, dt);

   // ── Daily ──
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_lastCalcDay && InpShowPDH)
   {
      g_lastCalcDay = today;
      datetime yesterday = today - 86400;
      g_dh = -1; g_dl = 999999;
      for(int i = 0; i < total; i++)
      {
         if(t[i] >= yesterday && t[i] < today)
         {
            if(h[i] > g_dh) g_dh = h[i];
            if(l[i] < g_dl) g_dl = l[i];
         }
      }
      if(g_dh > 0)
         DrawPeriodLine("PDH", g_dh, today, clrGoldenrod);
      if(g_dl < 999999)
         DrawPeriodLine("PDL", g_dl, today, clrGoldenrod);
   }

   // ── Weekly ── (use time arithmetic, not day-of-week subtraction)
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   int dow = dt.day_of_week;  // 0=Sunday … 6=Saturday
   // Broker week typically starts Monday; adjust Sunday to previous Monday
   datetime thisWeek = todayStart - (dow == 0 ? 6 : dow - 1) * 86400;
   if(thisWeek != g_lastCalcWeek && InpShowPWH)
   {
      g_lastCalcWeek = thisWeek;
      datetime prevWeek = thisWeek - 604800;
      g_wh = -1; g_wl = 999999;
      for(int i = 0; i < total; i++)
      {
         if(t[i] >= prevWeek && t[i] < thisWeek)
         {
            if(h[i] > g_wh) g_wh = h[i];
            if(l[i] < g_wl) g_wl = l[i];
         }
      }
      if(g_wh > 0)
         DrawPeriodLine("PWH", g_wh, thisWeek, clrLightSalmon);
      if(g_wl < 999999)
         DrawPeriodLine("PWL", g_wl, thisWeek, clrLightSalmon);
   }

   // ── Monthly ──
   datetime thisMonth = StringToTime(StringFormat("%04d.%02d.01", dt.year, dt.mon));
   if(thisMonth != g_lastCalcMonth && InpShowPMH)
   {
      g_lastCalcMonth = thisMonth;
      datetime prevMonth = (dt.mon == 1) ?
         StringToTime(StringFormat("%04d.12.01", dt.year-1)) :
         StringToTime(StringFormat("%04d.%02d.01", dt.year, dt.mon-1));
      g_mh = -1; g_ml = 999999;
      for(int i = 0; i < total; i++)
      {
         if(t[i] >= prevMonth && t[i] < thisMonth)
         {
            if(h[i] > g_mh) g_mh = h[i];
            if(l[i] < g_ml) g_ml = l[i];
         }
      }
      if(g_mh > 0)
         DrawPeriodLine("PMH", g_mh, thisMonth, clrPlum);
      if(g_ml < 999999)
         DrawPeriodLine("PML", g_ml, thisMonth, clrPlum);
   }
}

void DrawPeriodLine(string label, double price, datetime fromTime, color clr)
{
   string nm = g_prefix + label;
   // Remove old object, create new one
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   if(ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   }
   if(InpShowLabels)
   {
      string lnm = nm + "_LBL";
      if(ObjectFind(0, lnm) >= 0) ObjectDelete(0, lnm);
      if(ObjectCreate(0, lnm, OBJ_TEXT, 0, fromTime, price))
      {
         ObjectSetString(0, lnm, OBJPROP_TEXT, label);
         ObjectSetInteger(0, lnm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE, 7);
      }
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// PREMIUM / DISCOUNT ZONE — single live range, updated in-place
// ═════════════════════════════════════════════════════════════════════════════
void ManagePDZ(const double &h[], const double &l[], const datetime &t[],
                int total)
{
   if(!InpShowPDZ) return;
   if(g_sw.pivHiCnt < 1 || g_sw.pivLoCnt < 1) return;

   // Find most recent swing high and low
   double swHi = 0, swLo = 999999;
   datetime tHi = 0, tLo = 0;

   for(int j = g_sw.pivHiCnt - 1; j >= 0; j--)
   {
      if(!g_sw.pivotsHi[j].consumed)
      { swHi = g_sw.pivotsHi[j].price; tHi = g_sw.pivotsHi[j].time; break; }
   }
   for(int j = g_sw.pivLoCnt - 1; j >= 0; j--)
   {
      if(!g_sw.pivotsLo[j].consumed)
      { swLo = g_sw.pivotsLo[j].price; tLo = g_sw.pivotsLo[j].time; break; }
   }
   if(swHi <= swLo || swHi <= 0 || swLo >= 999998) return;

   double eq = (swHi + swLo) / 2.0;
   datetime zoneStart = (tHi > tLo) ? tHi : tLo;
   datetime zoneEnd   = t[total-1] + PeriodSeconds() * 20;

   // Update or create premium zone — update ALL coordinates
   string nmP = g_prefix + "PDZ_Prem";
   if(ObjectFind(0, nmP) < 0)
   {
      if(ObjectCreate(0, nmP, OBJ_RECTANGLE, 0, zoneStart, swHi, zoneEnd, eq))
      {
         ObjectSetInteger(0, nmP, OBJPROP_COLOR, C'0xF2,0x36,0x45');
         ObjectSetInteger(0, nmP, OBJPROP_FILL, true);
         ObjectSetInteger(0, nmP, OBJPROP_BACK, true);
         ObjectSetInteger(0, nmP, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nmP, OBJPROP_HIDDEN, true);
      }
   }
   else
   {
      ObjectSetInteger(0, nmP, OBJPROP_TIME,  0, zoneStart);
      ObjectSetDouble (0, nmP, OBJPROP_PRICE, 0, swHi);
      ObjectSetInteger(0, nmP, OBJPROP_TIME,  1, zoneEnd);
      ObjectSetDouble (0, nmP, OBJPROP_PRICE, 1, eq);
   }

   // Update or create discount zone — update ALL coordinates
   string nmD = g_prefix + "PDZ_Disc";
   if(ObjectFind(0, nmD) < 0)
   {
      if(ObjectCreate(0, nmD, OBJ_RECTANGLE, 0, zoneStart, eq, zoneEnd, swLo))
      {
         ObjectSetInteger(0, nmD, OBJPROP_COLOR, C'0x08,0x99,0x81');
         ObjectSetInteger(0, nmD, OBJPROP_FILL, true);
         ObjectSetInteger(0, nmD, OBJPROP_BACK, true);
         ObjectSetInteger(0, nmD, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nmD, OBJPROP_HIDDEN, true);
      }
   }
   else
   {
      ObjectSetInteger(0, nmD, OBJPROP_TIME,  0, zoneStart);
      ObjectSetDouble (0, nmD, OBJPROP_PRICE, 0, eq);
      ObjectSetInteger(0, nmD, OBJPROP_TIME,  1, zoneEnd);
      ObjectSetDouble (0, nmD, OBJPROP_PRICE, 1, swLo);
   }

   // Update or create equilibrium line — update ALL coordinates
   string nmE = g_prefix + "PDZ_EQ";
   if(ObjectFind(0, nmE) < 0)
   {
      if(ObjectCreate(0, nmE, OBJ_TREND, 0, zoneStart, eq, zoneEnd, eq))
      {
         ObjectSetInteger(0, nmE, OBJPROP_COLOR, clrGray);
         ObjectSetInteger(0, nmE, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, nmE, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, nmE, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nmE, OBJPROP_BACK, true);
         ObjectSetInteger(0, nmE, OBJPROP_SELECTABLE, false);
      }
   }
   else
   {
      ObjectSetInteger(0, nmE, OBJPROP_TIME,  0, zoneStart);
      ObjectSetDouble (0, nmE, OBJPROP_PRICE, 0, eq);
      ObjectSetInteger(0, nmE, OBJPROP_TIME,  1, zoneEnd);
      ObjectSetDouble (0, nmE, OBJPROP_PRICE, 1, eq);
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER: PIVOT DETECTION (non-series, index 0 = oldest)
// ═════════════════════════════════════════════════════════════════════════════
bool IsPivotHigh(const double &h[], int len, int i, int total)
{
   if(i - len < 0 || i + len >= total) return false;
   double v = h[i];
   for(int j = i - len; j < i; j++)        if(h[j] > v) return false;
   for(int j = i + 1; j <= i + len; j++)   if(h[j] >= v) return false;
   return true;
}

bool IsPivotLow(const double &l[], int len, int i, int total)
{
   if(i - len < 0 || i + len >= total) return false;
   double v = l[i];
   for(int j = i - len; j < i; j++)        if(l[j] < v) return false;
   for(int j = i + 1; j <= i + len; j++)   if(l[j] <= v) return false;
   return true;
}

void StorePivot(PivotRec &buf[], int &cnt, int bar, double price, datetime t)
{
   if(cnt < MAX_PIVOTS)
   {
      buf[cnt].barIdx  = bar;
      buf[cnt].price   = price;
      buf[cnt].time    = t;
      buf[cnt].consumed = false;
      cnt++;
   }
   else
   {
      // Shift-left to evict oldest
      for(int i = 0; i < MAX_PIVOTS - 1; i++)
         buf[i] = buf[i+1];
      buf[MAX_PIVOTS-1].barIdx   = bar;
      buf[MAX_PIVOTS-1].price    = price;
      buf[MAX_PIVOTS-1].time     = t;
      buf[MAX_PIVOTS-1].consumed = false;
   }
}

// ═════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═════════════════════════════════════════════════════════════════════════════
void DrawStructureLine(datetime fromTime, double level, datetime toTime,
                        string prefix, string label, color clr)
{
   if(!InpShowLabels && InpDisplayMode == DISPLAY_PRESENT) return;

   string nm = g_prefix + "LINE_" + prefix + "_" + IntegerToString((int)(fromTime / 60));
   if(ObjectFind(0, nm) >= 0) return;

   if(ObjectCreate(0, nm, OBJ_TREND, 0, fromTime, level, toTime, level))
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }

   // Midpoint label
   if(InpShowLabels)
   {
      datetime midTime = fromTime + (toTime - fromTime) / 2;
      DrawLabel(midTime, level, label, clr, prefix + "_LBL_" + IntegerToString((int)(fromTime/60)));
   }
}

void DrawLabel(datetime barTime, double price, string text, color clr, string suffix)
{
   string nm = g_prefix + "LBL_" + suffix;
   if(ObjectFind(0, nm) >= 0) return;
   if(ObjectCreate(0, nm, OBJ_TEXT, 0, barTime, price))
   {
      ObjectSetString(0, nm, OBJPROP_TEXT, text);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
}

void DrawCandleColor(int i, int biasDir)
{
   // 0 = bullish (lime), 1 = bearish (red)
   g_candleCol[i] = (biasDir > 0) ? 0.0 : 1.0;
}

// ═════════════════════════════════════════════════════════════════════════════
// ALERTS
// ═════════════════════════════════════════════════════════════════════════════
void FireAlert(string type, string detail, datetime barTime, double price,
               bool isNewBar)
{
   if(!InpAlertsActive) return;
   if(!isNewBar) return; // only alert on live bars

   // One alert per bar per type
   string key = type + "_" + detail;
   if(barTime == g_lastAlertBar && key == g_lastAlertType) return;
   g_lastAlertBar = barTime;
   g_lastAlertType = key;

   string msg = StringFormat("[SMC v3] %s %s | %s %s | %.5f",
                             type, detail, _Symbol,
                             EnumToString(Period()), price);

   if(InpAlertPopup)  Alert(msg);
   if(InpAlertSound)  PlaySound("alert.wav");
   if(InpAlertPush)   SendNotification(msg);
}

// ═════════════════════════════════════════════════════════════════════════════
// STATE MANAGEMENT
// ═════════════════════════════════════════════════════════════════════════════
void ResetAllState()
{
   ZeroMemory(g_int);  ZeroMemory(g_sw);
   g_int.trendBull = true;  g_sw.trendBull = true;
   g_int.biasEstablished = false;  g_sw.biasEstablished = false;
   ArrayFree(g_intOBs);  ArrayFree(g_swOBs);
   ArrayFree(g_fvgs);    ArrayFree(g_eqPairs);
   g_lastBarTime = 0;
   g_lastAlertBar = 0;  g_lastAlertType = "";
   g_lastCalcDay = 0;  g_lastCalcWeek = 0;  g_lastCalcMonth = 0;
   g_dh = 0; g_dl = 0; g_wh = 0; g_wl = 0; g_mh = 0; g_ml = 0;
}

void CleanupAll()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n);
   }
   ArrayFree(g_intOBs);  ArrayFree(g_swOBs);
   ArrayFree(g_fvgs);    ArrayFree(g_eqPairs);
   ChartRedraw();
}

//+------------------------------------------------------------------+

