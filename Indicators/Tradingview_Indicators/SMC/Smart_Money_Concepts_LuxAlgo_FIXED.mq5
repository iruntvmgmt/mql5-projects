//+------------------------------------------------------------------+
//|                              Smart Money Concepts Suite v4.10              |
//|                     Ground-up rebuild — dual structure engine     |
//|                     Chronological non-series architecture         |
//+------------------------------------------------------------------+
#property copyright   "SMC LuxAlgo v3 — dual-structure rebuild"
#property version     "4.10"
#property description ":: Smart Money Concepts Suite v4.10 ::"
#property description "Dual Internal/Swing Structure, BOS/CHoCH,"
#property description "Order Blocks, FVGs, EQH/EQL, PDH/PWH/PMH,"
#property description "Premium/Discount Zones, Candle Coloring."

#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   14

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

#property indicator_label6  "OB High"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "OB Low"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "FVG Bull Size"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "FVG Bear Size"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "Bias Signal"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "PDH"
#property indicator_type11  DRAW_NONE
#property indicator_label12 "PDL"
#property indicator_type12  DRAW_NONE
#property indicator_label13 "PWH"
#property indicator_type13  DRAW_NONE
#property indicator_label14 "PWL"
#property indicator_type14  DRAW_NONE

// ═════════════════════════════════════════════════════════════════════════════
// ENUMS  (must precede inputs)
// ═════════════════════════════════════════════════════════════════════════════
enum ENUM_DISPLAY_MODE     { DISPLAY_ALL, DISPLAY_PRESENT };
enum ENUM_STRUCTURE_SOURCE { SOURCE_INTERNAL, SOURCE_SWING };
enum ENUM_OB_MITIGATION    { OB_MIT_TOUCH, OB_MIT_MIDPOINT, OB_MIT_CLOSE, OB_MIT_FULL };
enum ENUM_FVG_MITIGATION   { FVG_MIT_TOUCH, FVG_MIT_MID, FVG_MIT_CLOSE, FVG_MIT_FULL };
enum ENUM_OB_FILTER        { OB_FILTER_NONE, OB_FILTER_ATR, OB_FILTER_CUMULATIVE };
enum ENUM_SMC_THEME        { THEME_COLORED, THEME_MONOCHROME };

// ═════════════════════════════════════════════════════════════════════════════
// INPUTS
// ═════════════════════════════════════════════════════════════════════════════
input group                          "═══ Internal Structure ═══"
input int                            InpIntSwingLen   = 5;            // Internal Pivot Length
input bool                           InpShowIntStruct = true;         // Show Internal Structure
input bool                           InpShowIntBOS    = true;         // Show Internal BOS
input bool                           InpShowIntCHoCH  = true;         // Show Internal CHoCH
input bool                           InpInternalConfluence = false;   // Filter weak internal breaks

input group                          "═══ Swing Structure ═══"
input int                            InpSwSwingLen    = 10;           // Swing Pivot Length
input bool                           InpShowSwStruct  = true;         // Show Swing Structure
input bool                           InpShowSwBOS     = true;         // Show Swing BOS
input bool                           InpShowSwCHoCH   = true;         // Show Swing CHoCH

input group                          "═══ Order Blocks ═══"
input bool                           InpShowIntOB     = true;         // Show Internal OBs
input bool                           InpShowSwOB      = true;         // Show Swing OBs
input int                            InpMaxIntOB      = 3;            // Max Internal OBs
input int                            InpMaxSwOB       = 3;            // Max Swing OBs
input ENUM_OB_MITIGATION             InpOBMitigation  = OB_MIT_MIDPOINT;// OB Mitigation Mode
input bool                           InpFillOrderBlocks = false;      // Fill OB rectangles
input bool                           InpShowOnlyActiveZones = true;   // Hide mitigated/invalidated zones
input int                            InpSwingOBWidth  = 2;            // Swing OB outline width
input int                            InpInternalOBWidth = 1;          // Internal OB outline width
input ENUM_LINE_STYLE                InpSwingOBStyle  = STYLE_SOLID;
input ENUM_LINE_STYLE                InpInternalOBStyle = STYLE_DOT;
input bool                           InpOBFromBOS     = true;         // Create OBs from BOS too
input bool                           InpConfirmStateOnClose = true;   // Confirm mitigation/sweeps on closed bars
input ENUM_OB_FILTER                 InpOBFilter      = OB_FILTER_ATR;// Volatility filter
input int                            InpOBFilterPeriod= 200;          // Volatility lookback
input double                         InpOBMaxRange    = 2.0;          // Maximum range x volatility

input group                          "═══ Fair Value Gaps ═══"
input bool                           InpShowFVG       = true;         // Show FVGs
input ENUM_FVG_MITIGATION            InpFVGMitigation = FVG_MIT_MID; // FVG Mitigation Mode
input int                            InpMaxFVGs       = 5;            // Max chart-timeframe FVGs
input int                            InpMaxHTFFVGs    = 5;            // Max higher-timeframe FVGs
input bool                           InpFillFVGs      = false;        // Fill FVG rectangles
input int                            InpFVGWidth      = 1;            // FVG outline width
input ENUM_LINE_STYLE                InpFVGStyle      = STYLE_DASH;
input double                         InpFVGMinSize    = 0.0;          // Min FVG Size (points)
input bool                           InpFVGAutoThreshold = true;      // Dynamic ATR gap threshold
input int                            InpFVGATRPeriod  = 100;          // Auto threshold period
input double                         InpFVGATRFactor  = 0.15;         // Minimum gap x ATR
input bool                           InpShowHTFFVG    = false;        // Show higher-timeframe FVGs
input ENUM_TIMEFRAMES                InpFVGTimeframe  = PERIOD_H4;    // FVG source timeframe
input int                            InpHTFFVGLookback= 300;          // HTF bars to scan

input group                          "═══ EQH / EQL ═══"
input bool                           InpShowEQ        = true;         // Show EQH/EQL
input double                         InpEQTolerance   = 0.05;         // EQ Tolerance (%)
input int                            InpEQMinPivotSeparation = 3;     // Minimum bars between pivots

input group                          "═══ Previous Highs/Lows ═══"
input bool                           InpShowPDH       = true;         // Show Prev Day High/Low
input bool                           InpShowPWH       = true;         // Show Prev Week High/Low
input bool                           InpShowPMH       = true;         // Show Prev Month High/Low
input bool                           InpUseBrokerPeriods = true;      // Use broker D1/W1/MN1 for live levels

input group                          "═══ Premium / Discount ═══"
input bool                           InpShowPDZ       = true;         // Show Premium/Discount
input bool                           InpFillPDZ       = false;        // Fill compact PDZ bands
input double                         InpPDZBandPercent= 5.0;          // Extreme band size (% of range)
input int                            InpPDZWidth      = 1;            // PDZ boundary width
input bool                           InpShowStrongWeak= true;         // Trailing strong/weak extremes

input group                          "═══ Candle Coloring ═══"
input bool                           InpColorCandles  = true;         // Color Candles by Structure
input ENUM_STRUCTURE_SOURCE          InpColorSource   = SOURCE_SWING; // Coloring Source

input group                          "═══ Display ═══"
input ENUM_DISPLAY_MODE              InpDisplayMode   = DISPLAY_PRESENT;// Display Mode
input bool                           InpShowLabels    = true;         // Show Labels
input ENUM_SMC_THEME                 InpTheme         = THEME_COLORED;// Color theme
input bool                           InpDeleteMitigatedPresent = true;// Remove inactive zones in Present mode
input color                          InpBullColor     = C'0x08,0x99,0x81';
input color                          InpBearColor     = C'0xF2,0x36,0x45';
input color                          InpNeutralColor  = clrGray;
input color                          InpEQHColor      = clrOrange;
input color                          InpEQLColor      = clrDodgerBlue;
input color                          InpPDColor       = clrGoldenrod;
input color                          InpPWColor       = clrLightSalmon;
input color                          InpPMColor       = clrPlum;
input color                          InpSwingBullOBColor = C'0x00,0x66,0x44';
input color                          InpSwingBearOBColor = C'0xA8,0x00,0x00';
input color                          InpInternalBullOBColor = C'0x42,0xA5,0x8A';
input color                          InpInternalBearOBColor = C'0xD9,0x68,0x70';
input color                          InpBullFVGColor  = C'0x26,0xA6,0x9A';
input color                          InpBearFVGColor  = C'0xEC,0x70,0x86';
input ENUM_LINE_STYLE                InpStructureStyle= STYLE_DOT;
input ENUM_LINE_STYLE                InpEQStyle       = STYLE_SOLID;
input ENUM_LINE_STYLE                InpPeriodStyle   = STYLE_DASH;

input group                          "═══ Alerts ═══"
input bool                           InpAlertsActive  = true;         // Enable Alerts
input bool                           InpAlertPopup    = true;         // Terminal Popup
input bool                           InpAlertSound    = false;        // Sound
input bool                           InpAlertPush     = false;        // Push Notification
input bool                           InpAlertStructure= true;         // BOS / CHoCH alerts
input bool                           InpAlertOB       = true;         // OB mitigation alerts
input bool                           InpAlertFVG      = true;         // FVG mitigation alerts
input bool                           InpAlertEQ       = true;         // EQ sweep alerts

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
   int      trendDir;       // +1 bullish, -1 bearish, 0 unknown
   bool     biasEstablished; // true once direction is derived or a break establishes it
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
   int       lastCheckedBar;
};

struct FVGRecord {
   datetime  formTime;
   double    top;
   double    bottom;
   bool      isBullish;
   bool      mitigated;
   int       lastCheckedBar;  // avoid full rescan
   ENUM_TIMEFRAMES sourceTF;
};

struct EQPair {
   datetime  timeA, timeB;
   double    priceA, priceB;
   double    level;
   bool      isHigh;         // true=EQH, false=EQL
   bool      swept;
   datetime  sweepTime;
   int       lastCheckedBar;
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
double           g_dayCurHigh, g_dayCurLow;
double           g_weekCurHigh, g_weekCurLow;
double           g_monthCurHigh, g_monthCurLow;
bool             g_dayInit, g_weekInit, g_monthInit;
bool             g_isNewBar, g_isFullRebuild;
datetime         g_pdzPremTime, g_pdzDiscTime, g_pdzEqTime;// for single PDZ update
int              g_instanceId;      // unique instance (based on GetTickCount at init)
datetime         g_lastBarTime;     // for new-bar detection
datetime         g_lastAlertBar;
string           g_lastAlertType;
datetime         g_lastCalcDay, g_lastCalcWeek, g_lastCalcMonth;  // prev-HL markers
datetime         g_lastHTFBarTime;

// ═════════════════════════════════════════════════════════════════════════════
// FORWARD DECLARATIONS
// ═════════════════════════════════════════════════════════════════════════════
bool   IsPivotHigh(const double &h[], int len, int i, int total);
bool   IsPivotLow(const double &l[], int len, int i, int total);
bool   StorePivot(PivotRec &buf[], int &cnt, int bar, double price, datetime t);
void   ConfirmOnePivotCandidate(StructureState &st, int pivotLen, bool isSwing,
                                const double &h[], const double &l[], const datetime &t[],
                                int candidate, int total, double pointSize);
void   UpdateTrendFromPivots(StructureState &st);
datetime DayStart(datetime barTime);
datetime WeekStart(datetime barTime);
datetime MonthStart(datetime barTime);
void   UpdatePrevHLChrono(int i, const double &h[], const double &l[], const datetime &t[], int total);
void   ProcessBarHistory(const double &o[], const double &h[], const double &l[],
                        const double &c[], const datetime &t[], int i, int total,
                        double pointSize);
void   ProcessBarLive(const double &o[], const double &h[], const double &l[],
                      const double &c[], const datetime &t[], int i, int total,
                      double pointSize, bool isLiveClosedBar);
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
void   ManageEQCollection(bool isHigh, const double &h[], const double &l[],
                           const datetime &t[], int total);
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
void   AddFVGForTF(datetime formTime, double top, double bottom, bool isBullish, ENUM_TIMEFRAMES sourceTF);
void   ManageHTFFVGs();
string MakeFVGName(const FVGRecord &fvg);
string MakeEQName(datetime timeA, datetime timeB, bool isHigh);
void   RegisterEQPairsForPivot(PivotRec &pivs[], int cnt, bool isHigh,
                               const double &h[], const double &l[], const datetime &t[], int total);
void   DrawPeriodLine(string label, double price, datetime fromTime, color clr);
void   ResetAllState();
string MakeOBName(const OBRecord &ob);
void   ManageOBCollection(OBRecord &obs[], int maxCount, const double &h[],
                           const double &l[], const double &c[], const datetime &t[], int total);
void   DrawPivotLabel(int barIdx, bool isHigh, bool isSwing, double price, double pointSize,
                      const double &h[], const double &l[], const datetime &t[], const StructureState &st);
double AverageTrueRangeAt(const double &h[], const double &l[], const double &c[], int bar, int period);
double AverageRangeAt(const double &h[], const double &l[], int bar, int period);
bool   PassInternalConfluence(bool bullish, int bar, const double &o[], const double &h[],
                              const double &l[], const double &c[]);
bool   PassOBVolatility(int bar, const double &h[], const double &l[], const double &c[]);
bool   PassFVGThreshold(int bar, double gap, const double &h[], const double &l[],
                        const double &c[], double pointSize);
color  BullColor();
color  BearColor();
color  NeutralColor();
color  EqualColor(bool isHigh);
color  OBColor(bool isBullish, bool isSwing);
color  FVGColor(bool isBullish);
void   ManageTrailingExtremes(const datetime &t[], int total);

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
   if(InpMaxHTFFVGs < 0)   return INIT_PARAMETERS_INCORRECT;
   if(InpOBFilterPeriod < 2 || InpFVGATRPeriod < 2) return INIT_PARAMETERS_INCORRECT;
   if(InpOBMaxRange <= 0 || InpFVGATRFactor < 0 || InpHTFFVGLookback < 10) return INIT_PARAMETERS_INCORRECT;
   if(InpSwingOBWidth < 1 || InpInternalOBWidth < 1 || InpFVGWidth < 1 || InpPDZWidth < 1) return INIT_PARAMETERS_INCORRECT;
   if(InpPDZBandPercent <= 0 || InpPDZBandPercent > 25) return INIT_PARAMETERS_INCORRECT;

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

   for(int p = 0; p < 14; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Candle coloring: 2 colors (bull=0 lime, bear=1 red) — plot index 4
   PlotIndexSetInteger(4, PLOT_DRAW_BEGIN, 0);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, BullColor());
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, BearColor());
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, BearColor());
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, BullColor());
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, BearColor());
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, BullColor());

   ZeroMemory(g_int);  ZeroMemory(g_sw);
   g_int.trendDir = 0;  g_sw.trendDir = 0;
   g_int.biasEstablished = false;  g_sw.biasEstablished = false;

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Suite v4.10");
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

   int minB = InpSwSwingLen * 2 + 2;
   if(rates_total < minB) return 0;

   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   bool fullRebuild = (prev_calculated == 0);
   g_isFullRebuild = fullRebuild;
   g_isNewBar = false;

   if(fullRebuild)
   {
      CleanupAll();
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
      for(int i = 0; i < rates_total; i++)
         UpdatePrevHLChrono(i, h, l, t, rates_total);

      for(int i = minB; i <= rates_total - 2; i++)
         ProcessBarHistory(o, h, l, c, t, i, rates_total, pointSize);
   }
   else
   {
      // Detect new bar BEFORE processing
      bool isNewBar = (rates_total > 1 && t[rates_total-1] != g_lastBarTime);
      g_isNewBar = isNewBar;
      if(isNewBar)
         g_lastBarTime = t[rates_total-1];

      if(prev_calculated == rates_total && !isNewBar)
      {
         ManageOrderBlocks(h, l, o, c, t, rates_total);
         ManageFVGs(h, l, c, t, rates_total);
         ManagePrevHL(h, l, t, rates_total);
         ManageEQLevels(h, l, t, rates_total, pointSize);
         ManagePDZ(h, l, t, rates_total);
         ManageTrailingExtremes(t, rates_total);
         return rates_total;
      }

      // Process the newly closed bar (rates_total-2) and any bars not yet calculated
      int lastClosed = rates_total - 2;
      int startBar   = (prev_calculated > 0) ? prev_calculated - 1 : minB;
      if(startBar < minB) startBar = minB;
      if(startBar > lastClosed) startBar = lastClosed;  // guard against empty range

      // Pivot confirmation is performed inside EvalStructure at the current
      // closed bar, using candidate = currentBar - pivotLen.

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
         UpdatePrevHLChrono(i, h, l, t, rates_total);
         ProcessBarLive(o, h, l, c, t, i, rates_total, pointSize, isLiveClosedBar);
      }
   }

   ManageOrderBlocks(h, l, o, c, t, rates_total);
   ManageHTFFVGs();
   ManageFVGs(h, l, c, t, rates_total);
   ManagePrevHL(h, l, t, rates_total);
   ManageEQLevels(h, l, t, rates_total, pointSize);
   ManagePDZ(h, l, t, rates_total);
   ManageTrailingExtremes(t, rates_total);

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
      int biasDir = (InpColorSource == SOURCE_SWING ? g_sw.trendDir : g_int.trendDir);
      DrawCandleColor(i, biasDir);
   }
   // FVG: only closed bars, no forming
   if(InpShowFVG && i >= 2 && i < total - 1)
   {
      if(l[i] > h[i-2] && PassFVGThreshold(i, l[i]-h[i-2], h, l, c, pointSize))
      { g_fvgBull[i] = l[i]-h[i-2]; AddFVG(t[i], l[i], h[i-2], true); }
      if(h[i] < l[i-2] && PassFVGThreshold(i, l[i-2]-h[i], h, l, c, pointSize))
      { g_fvgBear[i] = l[i-2]-h[i]; AddFVG(t[i], h[i], l[i-2], false); }
   }
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
      int biasDir = (InpColorSource == SOURCE_SWING ? g_sw.trendDir : g_int.trendDir);
      DrawCandleColor(i, biasDir);
   }
   if(InpShowFVG && i >= 2 && i < total - 1)
   {
      if(l[i] > h[i-2] && PassFVGThreshold(i, l[i]-h[i-2], h, l, c, pointSize))
      { g_fvgBull[i] = l[i]-h[i-2]; AddFVG(t[i], l[i], h[i-2], true); }
      if(h[i] < l[i-2] && PassFVGThreshold(i, l[i-2]-h[i], h, l, c, pointSize))
      { g_fvgBear[i] = l[i-2]-h[i]; AddFVG(t[i], h[i], l[i-2], false); }
   }
}

// ── Confirm exactly one newly eligible pivot candidate (live path) ──
void ConfirmOnePivotCandidate(StructureState &st, int pivotLen, bool isSwing,
                              const double &h[], const double &l[], const datetime &t[],
                              int candidate, int total, double pointSize)
{
   if(candidate < pivotLen || candidate + pivotLen >= total) return;

   if(IsPivotHigh(h, pivotLen, candidate, total))
   {
      bool added = StorePivot(st.pivotsHi, st.pivHiCnt, candidate, h[candidate], t[candidate]);
      if(added)
      {
         if(st.pivHiCnt >= 2)
            st.strongHigh = (st.pivotsHi[st.pivHiCnt-1].price > st.pivotsHi[st.pivHiCnt-2].price);
         st.activeHigh = h[candidate];
         st.activeHighBar = candidate;
         st.activeHighTime = t[candidate];
         if(h[candidate] > st.trailHigh || st.trailHigh == 0)
         { st.trailHigh = h[candidate]; st.trailHighBar = candidate; }
         DrawPivotLabel(candidate, true, isSwing, h[candidate], pointSize, h, l, t, st);
         if(isSwing) { if(InpShowSwStruct) g_swSwHi[candidate] = h[candidate]; }
         else        { if(InpShowIntStruct) g_intSwHi[candidate] = h[candidate]; }
         if(st.pivHiCnt >= 2)
            RegisterEQPairsForPivot(st.pivotsHi, st.pivHiCnt, true, h, l, t, total);
      }
   }
   if(IsPivotLow(l, pivotLen, candidate, total))
   {
      bool added = StorePivot(st.pivotsLo, st.pivLoCnt, candidate, l[candidate], t[candidate]);
      if(added)
      {
         if(st.pivLoCnt >= 2)
            st.strongLow = (st.pivotsLo[st.pivLoCnt-1].price < st.pivotsLo[st.pivLoCnt-2].price);
         st.activeLow = l[candidate];
         st.activeLowBar = candidate;
         st.activeLowTime = t[candidate];
         if(l[candidate] < st.trailLow || st.trailLow == 0)
         { st.trailLow = l[candidate]; st.trailLowBar = candidate; }
         DrawPivotLabel(candidate, false, isSwing, l[candidate], pointSize, h, l, t, st);
         if(isSwing) { if(InpShowSwStruct) g_swSwLo[candidate] = l[candidate]; }
         else        { if(InpShowIntStruct) g_intSwLo[candidate] = l[candidate]; }
         if(st.pivLoCnt >= 2)
            RegisterEQPairsForPivot(st.pivotsLo, st.pivLoCnt, false, h, l, t, total);
      }
   }
   UpdateTrendFromPivots(st);
}

void UpdateTrendFromPivots(StructureState &st)
{
   if(st.trendDir != 0 || st.pivHiCnt < 2 || st.pivLoCnt < 2) return;
   double hi0 = st.pivotsHi[st.pivHiCnt-2].price;
   double hi1 = st.pivotsHi[st.pivHiCnt-1].price;
   double lo0 = st.pivotsLo[st.pivLoCnt-2].price;
   double lo1 = st.pivotsLo[st.pivLoCnt-1].price;
   if(hi1 > hi0 && lo1 > lo0) st.trendDir = 1;
   else if(hi1 < hi0 && lo1 < lo0) st.trendDir = -1;
   st.biasEstablished = (st.trendDir != 0);
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

   // Confirm a pivot only when its right-side window has actually closed.
   // This removes historical look-ahead and matches the live path.
   int candidate = i - pivotLen;
   ConfirmOnePivotCandidate(st, pivotLen, isSwing, h, l, t, candidate, total, pointSize);
   UpdateTrendFromPivots(st);

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
         (i == 0 || c[i-1] <= priorHi) &&
         (isSwing || PassInternalConfluence(true, i, o, h, l, c)))
      {
         // Mark consumed
         for(int j = st.pivHiCnt - 1; j >= 0; j--)
         {
            if(st.pivotsHi[j].barIdx == priorBar)
               st.pivotsHi[j].consumed = true;
         }

         bool isCHoCH = (st.trendDir < 0);
         if(!isCHoCH)
         {
            // BOS — continuation
            if(showBOS)
            {
               DrawStructureLine(priorTime, priorHi, t[i], prefix, "BOS ▲", BullColor());
               FireAlert(isSwing ? "Swing" : "Internal", "BOS Bullish", t[i], c[i], isLiveClosedBar);
            }
            st.lastBOSBar = i;
            st.trendDir = 1;
            st.biasEstablished = true;
            g_biasSig[i] = 1;
            if(InpOBFromBOS)
               CreateOrderBlock(true, isSwing, i, priorBar, h, l, o, c, t, total);
         }
         else
         {
            // CHoCH — reversal
            if(showCHoCH)
            {
               DrawStructureLine(priorTime, priorHi, t[i], prefix, "CHoCH ▲", BullColor());
               FireAlert(isSwing ? "Swing" : "Internal", "CHoCH Bullish", t[i], c[i], isLiveClosedBar);
            }
            st.lastCHoCHBar = i;
            st.trendDir = 1;
            st.biasEstablished = true;
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
         (i == 0 || c[i-1] >= priorLo) &&
         (isSwing || PassInternalConfluence(false, i, o, h, l, c)))
      {
         for(int j = st.pivLoCnt - 1; j >= 0; j--)
         {
            if(st.pivotsLo[j].barIdx == priorBar)
               st.pivotsLo[j].consumed = true;
         }

         bool isCHoCH = (st.trendDir > 0);
         if(!isCHoCH)
         {
            if(showBOS)
            {
               DrawStructureLine(priorTime, priorLo, t[i], prefix, "BOS ▼", BearColor());
               FireAlert(isSwing ? "Swing" : "Internal", "BOS Bearish", t[i], c[i], isLiveClosedBar);
            }
            st.lastBOSBar = i;
            st.trendDir = -1;
            st.biasEstablished = true;
            g_biasSig[i] = -1;
            if(InpOBFromBOS)
               CreateOrderBlock(false, isSwing, i, priorBar, h, l, o, c, t, total);
         }
         else
         {
            if(showCHoCH)
            {
               DrawStructureLine(priorTime, priorLo, t[i], prefix, "CHoCH ▼", BearColor());
               FireAlert(isSwing ? "Swing" : "Internal", "CHoCH Bearish", t[i], c[i], isLiveClosedBar);
            }
            st.lastCHoCHBar = i;
            st.trendDir = -1;
            st.biasEstablished = true;
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
      if(!PassOBVolatility(j, h, l, c)) continue;

      if(isBullOB && isBear) { obBar = j; break; }
      if(!isBullOB && isBull) { obBar = j; break; }
   }
   if(obBar < 0) return;

   // Duplicate check must use the actual origin candle, not the broken pivot.
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
   rec.mitigationTime = 0;
   rec.lastCheckedBar = breakBar;

   FireAlert(isSwing ? "Swing OB" : "Internal OB",
             isBullOB ? "Bullish Created" : "Bearish Created",
             t[breakBar], rec.midpoint, g_isNewBar && !g_isFullRebuild);

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
   if(InpDisplayMode == DISPLAY_PRESENT)
   {
      string family = g_prefix + "OB_" + (isSwing ? "SW_" : "INT_") + (isBullOB ? "B_" : "S_");
      for(int oi = ObjectsTotal(0)-1; oi >= 0; oi--)
      {
         string on = ObjectName(0, oi);
         if(StringFind(on, family) == 0 && on != nm) ObjectDelete(0, on);
      }
   }
   if(ObjectFind(0, nm) < 0)
   {
      datetime tEnd = t[total - 1] + PeriodSeconds() * 5;
      color clr = OBColor(isBullOB, isSwing);
      if(ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t[obBar], h[obBar], tEnd, l[obBar]))
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_FILL, InpFillOrderBlocks);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, isSwing ? InpSwingOBWidth : InpInternalOBWidth);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, isSwing ? InpSwingOBStyle : InpInternalOBStyle);
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
   int stateLastBar = InpConfirmStateOnClose ? total - 2 : total - 1;
   if(lastBar < 0 || stateLastBar < 0) return;

   // Process both OB collections — explicit calls, no conditional references
   ManageOBCollection(g_swOBs, InpMaxSwOB, h, l, c, t, total);
   ManageOBCollection(g_intOBs, InpMaxIntOB, h, l, c, t, total);
}

// ── OB collection helper (avoids conditional array reference) ──
void ManageOBCollection(OBRecord &obs[], int maxCount, const double &h[],
                         const double &l[], const double &c[], const datetime &t[], int total)
{
   int lastBar = total - 1;
   int stateLastBar = InpConfirmStateOnClose ? total - 2 : total - 1;
   if(lastBar < 0 || stateLastBar < 0) return;

   for(int k = ArraySize(obs) - 1; k >= 0; k--)
   {
      if(obs[k].mitigated || obs[k].invalidated) continue;

      // Consistent OB name from origin timestamp
      string nm = MakeOBName(obs[k]);
      // Check only bars not previously evaluated.
      int startBar = obs[k].lastCheckedBar + 1;
      if(startBar < 0) startBar = 0;
      for(int bar = startBar; bar <= stateLastBar; bar++)
      {
         if(t[bar] <= obs[k].eventTime) { obs[k].lastCheckedBar = bar; continue; }
         bool hit = false;
         switch(InpOBMitigation)
         {
            case OB_MIT_TOUCH:
               hit = (l[bar] <= obs[k].top && h[bar] >= obs[k].bottom);
               break;
            case OB_MIT_MIDPOINT:
               // Wick penetrates at least halfway into the block.
               if(obs[k].isBullish) hit = (l[bar] <= obs[k].midpoint);
               else                 hit = (h[bar] >= obs[k].midpoint);
               break;
            case OB_MIT_CLOSE:
               // Direction-aware close mitigation
               if(obs[k].isBullish)
                  hit = (c[bar] <= obs[k].midpoint);
               else
                  hit = (c[bar] >= obs[k].midpoint);
               break;
            case OB_MIT_FULL:
               // Full = invalidation: close beyond the block in the wrong direction
               if(obs[k].isBullish)
                  hit = (c[bar] < obs[k].bottom);  // close below = invalidated
               else
                  hit = (c[bar] > obs[k].top);     // close above = invalidated
               break;
         }
         obs[k].lastCheckedBar = bar;
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
               ObjectSetInteger(0, nm, OBJPROP_COLOR, NeutralColor());
            }
            FireAlert(obs[k].isSwing ? "Swing OB" : "Internal OB",
                      obs[k].invalidated ? "Invalidated" : "Mitigated",
                      t[bar], c[bar], g_isNewBar && !g_isFullRebuild);
            if(InpShowOnlyActiveZones ||
               (InpDisplayMode == DISPLAY_PRESENT && InpDeleteMitigatedPresent))
               ObjectDelete(0, nm);
            break;
         }
      }
      // Extend active OB rectangle to current bar
      if(!obs[k].mitigated && !obs[k].invalidated && ObjectFind(0, nm) >= 0)
         ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[lastBar] + PeriodSeconds() * 5);
   }
}

// ── Consistent OB object name generator ──
string MakeOBName(const OBRecord &ob)
{
   return g_prefix + "OB_" + (ob.isSwing ? "SW_" : "INT_") +
          (ob.isBullish ? "B_" : "S_") + IntegerToString((int)ob.originTime);
}

// ═════════════════════════════════════════════════════════════════════════════
// FVG ENGINE
// ═════════════════════════════════════════════════════════════════════════════
void AddFVG(datetime formTime, double top, double bottom, bool isBullish)
{
   AddFVGForTF(formTime, top, bottom, isBullish, (ENUM_TIMEFRAMES)_Period);
}

void AddFVGForTF(datetime formTime, double top, double bottom, bool isBullish,
                 ENUM_TIMEFRAMES sourceTF)
{
   bool isHTF = (sourceTF != (ENUM_TIMEFRAMES)_Period);
   int limit = isHTF ? InpMaxHTFFVGs : InpMaxFVGs;
   if(limit <= 0) return;

   // Dedup: skip if already exists in records
   for(int k = ArraySize(g_fvgs)-1; k >= 0; k--)
      if(g_fvgs[k].formTime == formTime && g_fvgs[k].sourceTF == sourceTF) return;

   int sz = ArraySize(g_fvgs);
   int familyCount = 0;
   int oldestFamily = -1;
   for(int k = 0; k < sz; k++)
   {
      bool recordIsHTF = (g_fvgs[k].sourceTF != (ENUM_TIMEFRAMES)_Period);
      if(recordIsHTF == isHTF)
      {
         if(oldestFamily < 0) oldestFamily = k;
         familyCount++;
      }
   }
   if(familyCount >= limit && oldestFamily >= 0)
   {
      string oldNm = MakeFVGName(g_fvgs[oldestFamily]);
      if(ObjectFind(0, oldNm) >= 0) ObjectDelete(0, oldNm);
      for(int k = oldestFamily; k < sz-1; k++) g_fvgs[k] = g_fvgs[k+1];
      ArrayResize(g_fvgs, sz-1);
      sz--;
   }
   FVGRecord rec;
   rec.formTime = formTime;  rec.top = top;  rec.bottom = bottom;
   rec.isBullish = isBullish;  rec.mitigated = false;
   rec.lastCheckedBar = -1;
   rec.sourceTF = sourceTF;
   datetime latestClosedTF = iTime(_Symbol, sourceTF, 1);
   bool latestFormation = (latestClosedTF > 0 && formTime >= latestClosedTF);
   FireAlert("FVG", isBullish ? "Bullish Created" : "Bearish Created",
             formTime, (top + bottom) / 2.0,
             g_isNewBar && !g_isFullRebuild && latestFormation);
   ArrayResize(g_fvgs, sz+1);
   g_fvgs[sz] = rec;

   string nm = MakeFVGName(rec);
   if(InpDisplayMode == DISPLAY_PRESENT)
   {
      string family = g_prefix + "FVG_" + IntegerToString((int)sourceTF) + "_" + (isBullish ? "B_" : "S_");
      for(int oi = ObjectsTotal(0)-1; oi >= 0; oi--)
      {
         string on = ObjectName(0, oi);
         if(StringFind(on, family) == 0 && on != nm) ObjectDelete(0, on);
      }
   }
   if(ObjectFind(0, nm) < 0)
   {
      datetime currentBar = iTime(_Symbol, (ENUM_TIMEFRAMES)_Period, 0);
      datetime tEnd = currentBar + PeriodSeconds() * 5;
      if(ObjectCreate(0, nm, OBJ_RECTANGLE, 0, formTime, top, tEnd, bottom))
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, FVGColor(isBullish));
         ObjectSetInteger(0, nm, OBJPROP_FILL, InpFillFVGs);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, InpFVGWidth);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, InpFVGStyle);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
   }
}

string MakeFVGName(const FVGRecord &fvg)
{
   return g_prefix + "FVG_" + IntegerToString((int)fvg.sourceTF) + "_" +
          (fvg.isBullish ? "B_" : "S_") + IntegerToString((int)fvg.formTime);
}

void ManageHTFFVGs()
{
   if(!InpShowFVG || !InpShowHTFFVG || InpMaxHTFFVGs <= 0) return;
   if(PeriodSeconds(InpFVGTimeframe) <= PeriodSeconds((ENUM_TIMEFRAMES)_Period)) return;

   datetime currentHTFBar = iTime(_Symbol, InpFVGTimeframe, 0);
   if(currentHTFBar <= 0 || currentHTFBar == g_lastHTFBarTime) return;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpFVGTimeframe, 0, InpHTFFVGLookback, rates);
   if(copied < 4) return;
   g_lastHTFBarTime = currentHTFBar;
   ArraySetAsSeries(rates, false);

   double atr = 0.0;
   int atrCount = 0;
   int atrStart = MathMax(1, copied - InpFVGATRPeriod - 2);
   for(int i = atrStart; i < copied - 1; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - rates[i-1].close),
                          MathAbs(rates[i].low - rates[i-1].close)));
      atr += tr;
      atrCount++;
   }
   if(atrCount > 0) atr /= atrCount;

   for(int i = 2; i <= copied - 2; i++)
   {
      if(rates[i].low > rates[i-2].high)
      {
         double gap = rates[i].low - rates[i-2].high;
         if((InpFVGMinSize <= 0 || gap >= InpFVGMinSize * _Point) &&
            (!InpFVGAutoThreshold || atr <= 0 || gap >= atr * InpFVGATRFactor))
            AddFVGForTF(rates[i].time, rates[i].low, rates[i-2].high, true, InpFVGTimeframe);
      }
      if(rates[i].high < rates[i-2].low)
      {
         double gap = rates[i-2].low - rates[i].high;
         if((InpFVGMinSize <= 0 || gap >= InpFVGMinSize * _Point) &&
            (!InpFVGAutoThreshold || atr <= 0 || gap >= atr * InpFVGATRFactor))
            AddFVGForTF(rates[i].time, rates[i].high, rates[i-2].low, false, InpFVGTimeframe);
      }
   }
}

void ManageFVGs(const double &h[], const double &l[], const double &c[],
                 const datetime &t[], int total)
{
   int lastBar = total - 1;
   int stateLastBar = InpConfirmStateOnClose ? total - 2 : total - 1;
   if(lastBar < 0 || stateLastBar < 0) return;

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

      for(int bar = startBar; bar <= stateLastBar; bar++)
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
               // Direction-aware: close beyond the midpoint counts as mitigation.
               if(isBull)
                  hit = (c[bar] <= mid);
               else
                  hit = (c[bar] >= mid);
               break;
            case FVG_MIT_FULL:
               // Full mitigation means price reaches the far edge of the original gap.
               if(isBull) hit = (l[bar] <= gapLo);
               else       hit = (h[bar] >= gapHi);
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
               ObjectSetInteger(0, nm, OBJPROP_COLOR, NeutralColor());
            }
            FireAlert("FVG", isBull ? "Bullish Mitigated" : "Bearish Mitigated",
                      t[bar], c[bar], g_isNewBar && !g_isFullRebuild);
            if(InpShowOnlyActiveZones ||
               (InpDisplayMode == DISPLAY_PRESENT && InpDeleteMitigatedPresent))
               ObjectDelete(0, nm);
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
   ManageEQCollection(true, h, l, t, total);
   ManageEQCollection(false, h, l, t, total);
}

// EQ creation happens only when a new swing pivot confirms. This manager owns
// lifecycle transitions and visual extension, keeping reload/live behavior equal.
void ManageEQCollection(bool isHigh, const double &h[], const double &l[],
                         const datetime &t[], int total)
{
   int lastBar = total - 1;
   int stateLastBar = InpConfirmStateOnClose ? total - 2 : total - 1;
   if(lastBar < 0 || stateLastBar < 0) return;

   // First update existing pairs in place.
   for(int k = ArraySize(g_eqPairs) - 1; k >= 0; k--)
   {
      if(g_eqPairs[k].isHigh != isHigh) continue;

      string nm = MakeEQName(g_eqPairs[k].timeA, g_eqPairs[k].timeB, g_eqPairs[k].isHigh);
      if(!g_eqPairs[k].swept)
      {
         int startBar = g_eqPairs[k].lastCheckedBar + 1;
         if(startBar < 0) startBar = 0;
         for(int bar = startBar; bar <= stateLastBar; bar++)
         {
            if(bar <= 0) { g_eqPairs[k].lastCheckedBar = bar; continue; }
            if(t[bar] <= g_eqPairs[k].timeB) { g_eqPairs[k].lastCheckedBar = bar; continue; }
            bool sweptNow = (isHigh && h[bar] > g_eqPairs[k].level) || (!isHigh && l[bar] < g_eqPairs[k].level);
            g_eqPairs[k].lastCheckedBar = bar;
            if(sweptNow)
            {
               g_eqPairs[k].swept = true;
               g_eqPairs[k].sweepTime = t[bar];
               if(ObjectFind(0, nm) >= 0)
               {
                  ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[bar]);
                  ObjectSetInteger(0, nm, OBJPROP_COLOR, NeutralColor());
                  ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
                  ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
               }
               string lnm = nm + "_LBL";
               if(ObjectFind(0, lnm) >= 0)
                  ObjectSetInteger(0, lnm, OBJPROP_COLOR, NeutralColor());
               FireAlert(isHigh ? "EQH" : "EQL", "Liquidity Swept", t[bar],
                         g_eqPairs[k].level, g_isNewBar && !g_isFullRebuild);
               if(InpDisplayMode == DISPLAY_PRESENT)
               {
                  ObjectDelete(0, nm);
                  ObjectDelete(0, lnm);
               }
               break;
            }
         }
      }

      if(!g_eqPairs[k].swept && ObjectFind(0, nm) >= 0)
         ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t[lastBar] + PeriodSeconds() * 5);
   }

}

string MakeEQName(datetime timeA, datetime timeB, bool isHigh)
{
   return g_prefix + "EQ_" + (isHigh ? "H_" : "L_") +
          IntegerToString((int)timeA) + "_" + IntegerToString((int)timeB);
}

void RegisterEQPairsForPivot(PivotRec &pivs[], int cnt, bool isHigh,
                             const double &h[], const double &l[], const datetime &t[], int total)
{
   if(cnt < 2) return;

   int newIdx = cnt - 1;
   int lookback = MathMin(cnt - 1, 60);
   for(int a = newIdx - 1; a >= 0 && a >= newIdx - lookback; a--)
   {
      double denom = MathMax(MathAbs(pivs[a].price), 0.00001);
      if(pivs[newIdx].barIdx - pivs[a].barIdx < InpEQMinPivotSeparation) continue;
      if(MathAbs(pivs[a].price - pivs[newIdx].price) / denom >= InpEQTolerance / 100.0)
         continue;

      datetime timeA = pivs[a].time;
      datetime timeB = pivs[newIdx].time;
      string nm = MakeEQName(timeA, timeB, isHigh);
      if(ObjectFind(0, nm) >= 0) continue;

      if(InpDisplayMode == DISPLAY_PRESENT)
      {
         string family = g_prefix + "EQ_" + (isHigh ? "H_" : "L_");
         for(int oi = ObjectsTotal(0)-1; oi >= 0; oi--)
         {
            string on = ObjectName(0, oi);
            if(StringFind(on, family) == 0) ObjectDelete(0, on);
         }
      }

      bool exists = false;
      for(int k = ArraySize(g_eqPairs) - 1; k >= 0; k--)
      {
         if(g_eqPairs[k].isHigh == isHigh && g_eqPairs[k].timeA == timeA && g_eqPairs[k].timeB == timeB)
         {
            exists = true;
            break;
         }
      }
      if(exists) continue;

      EQPair rec;
      rec.timeA = timeA;
      rec.timeB = timeB;
      rec.priceA = pivs[a].price;
      rec.priceB = pivs[newIdx].price;
      rec.level = (rec.priceA + rec.priceB) / 2.0;
      rec.isHigh = isHigh;
      rec.swept = false;
      rec.sweepTime = 0;
      rec.lastCheckedBar = pivs[newIdx].barIdx;

      int eqCount = ArraySize(g_eqPairs);
      ArrayResize(g_eqPairs, eqCount + 1);
      g_eqPairs[eqCount] = rec;
      FireAlert(isHigh ? "EQH" : "EQL", "Liquidity Pool Confirmed", timeB,
                rec.level, g_isNewBar && !g_isFullRebuild);

      double level = rec.level;
      datetime tEnd = t[total - 1] + PeriodSeconds() * 500;
      color clr = EqualColor(isHigh);
      if(ObjectCreate(0, nm, OBJ_TREND, 0, timeA, level, tEnd, level))
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, InpEQStyle);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      if(InpShowLabels)
      {
         string lnm = nm + "_LBL";
         if(ObjectCreate(0, lnm, OBJ_TEXT, 0, timeB, level))
         {
            ObjectSetString(0, lnm, OBJPROP_TEXT, isHigh ? "EQH" : "EQL");
            ObjectSetInteger(0, lnm, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE, false);
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

   datetime today = DayStart(barTime);
   datetime thisWeek = WeekStart(barTime);
   datetime thisMonth = MonthStart(barTime);

   if(InpUseBrokerPeriods)
   {
      double dh = iHigh(_Symbol, PERIOD_D1, 1), dl = iLow(_Symbol, PERIOD_D1, 1);
      double wh = iHigh(_Symbol, PERIOD_W1, 1), wl = iLow(_Symbol, PERIOD_W1, 1);
      double mh = iHigh(_Symbol, PERIOD_MN1, 1), ml = iLow(_Symbol, PERIOD_MN1, 1);
      if(dh > 0 && dl > 0) { g_dh = dh; g_dl = dl; }
      if(wh > 0 && wl > 0) { g_wh = wh; g_wl = wl; }
      if(mh > 0 && ml > 0) { g_mh = mh; g_ml = ml; }
   }

   if(InpShowPDH && g_dh != EMPTY_VALUE)
   {
      DrawPeriodLine("PDH", g_dh, today, InpPDColor);
      DrawPeriodLine("PDL", g_dl, today, InpPDColor);
   }
   if(InpShowPWH && g_wh != EMPTY_VALUE)
   {
      DrawPeriodLine("PWH", g_wh, thisWeek, InpPWColor);
      DrawPeriodLine("PWL", g_wl, thisWeek, InpPWColor);
   }
   if(InpShowPMH && g_mh != EMPTY_VALUE)
   {
      DrawPeriodLine("PMH", g_mh, thisMonth, InpPMColor);
      DrawPeriodLine("PML", g_ml, thisMonth, InpPMColor);
   }

   if(InpShowPDH) g_pdh[lastBar] = g_dh;
   if(InpShowPDH) g_pdl[lastBar] = g_dl;
   if(InpShowPWH) g_pwh[lastBar] = g_wh;
   if(InpShowPWH) g_pwl[lastBar] = g_wl;
}

datetime DayStart(datetime barTime)
{
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   return StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
}

datetime WeekStart(datetime barTime)
{
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   datetime day = DayStart(barTime);
   int dow = dt.day_of_week;
   int daysBack = (dow == 0 ? 6 : dow - 1);
   return day - daysBack * 86400;
}

datetime MonthStart(datetime barTime)
{
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   return StringToTime(StringFormat("%04d.%02d.01", dt.year, dt.mon));
}

void UpdatePrevHLChrono(int i, const double &h[], const double &l[], const datetime &t[], int total)
{
   if(i < 0 || i >= total) return;

   datetime dayKey   = DayStart(t[i]);
   datetime weekKey  = WeekStart(t[i]);
   datetime monthKey = MonthStart(t[i]);

   if(!g_dayInit)
   {
      g_dayInit = true;
      g_lastCalcDay = dayKey;
      g_dh = EMPTY_VALUE;
      g_dl = EMPTY_VALUE;
      g_dayCurHigh = h[i];
      g_dayCurLow  = l[i];
   }
   else if(dayKey != g_lastCalcDay)
   {
      g_dh = g_dayCurHigh;
      g_dl = g_dayCurLow;
      g_lastCalcDay = dayKey;
      g_dayCurHigh = h[i];
      g_dayCurLow  = l[i];
   }
   else
   {
      if(h[i] > g_dayCurHigh) g_dayCurHigh = h[i];
      if(l[i] < g_dayCurLow)  g_dayCurLow  = l[i];
   }

   if(!g_weekInit)
   {
      g_weekInit = true;
      g_lastCalcWeek = weekKey;
      g_wh = EMPTY_VALUE;
      g_wl = EMPTY_VALUE;
      g_weekCurHigh = h[i];
      g_weekCurLow  = l[i];
   }
   else if(weekKey != g_lastCalcWeek)
   {
      g_wh = g_weekCurHigh;
      g_wl = g_weekCurLow;
      g_lastCalcWeek = weekKey;
      g_weekCurHigh = h[i];
      g_weekCurLow  = l[i];
   }
   else
   {
      if(h[i] > g_weekCurHigh) g_weekCurHigh = h[i];
      if(l[i] < g_weekCurLow)  g_weekCurLow  = l[i];
   }

   if(!g_monthInit)
   {
      g_monthInit = true;
      g_lastCalcMonth = monthKey;
      g_mh = EMPTY_VALUE;
      g_ml = EMPTY_VALUE;
      g_monthCurHigh = h[i];
      g_monthCurLow  = l[i];
   }
   else if(monthKey != g_lastCalcMonth)
   {
      g_mh = g_monthCurHigh;
      g_ml = g_monthCurLow;
      g_lastCalcMonth = monthKey;
      g_monthCurHigh = h[i];
      g_monthCurLow  = l[i];
   }
   else
   {
      if(h[i] > g_monthCurHigh) g_monthCurHigh = h[i];
      if(l[i] < g_monthCurLow)  g_monthCurLow  = l[i];
   }

   if(InpShowPDH) { g_pdh[i] = g_dh; g_pdl[i] = g_dl; }
   if(InpShowPWH) { g_pwh[i] = g_wh; g_pwl[i] = g_wl; }
}

void DrawPeriodLine(string label, double price, datetime fromTime, color clr)
{
   string nm = g_prefix + label;
   // Remove old object, create new one
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   if(ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, InpPeriodStyle);
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

void DrawPivotLabel(int barIdx, bool isHigh, bool isSwing, double price, double pointSize,
                    const double &h[], const double &l[], const datetime &t[], const StructureState &st)
{
   if(!InpShowLabels) return;
   if(barIdx < 0 || barIdx >= ArraySize(t)) return;

   string label = isHigh ? "HH" : "LL";
   if(isHigh && st.pivHiCnt >= 2)
      label = (st.pivotsHi[st.pivHiCnt - 1].price > st.pivotsHi[st.pivHiCnt - 2].price) ? "HH" : "LH";
   if(!isHigh && st.pivLoCnt >= 2)
      label = (st.pivotsLo[st.pivLoCnt - 1].price > st.pivotsLo[st.pivLoCnt - 2].price) ? "HL" : "LL";

   string family = isSwing ? "SW" : "INT";
   string suffix = family + "_PIV_" + label + "_" + IntegerToString((int)t[barIdx]);
   if(InpDisplayMode == DISPLAY_PRESENT)
   {
      string objectFamily = g_prefix + "LBL_" + family + "_PIV_";
      for(int oi = ObjectsTotal(0)-1; oi >= 0; oi--)
      {
         string on = ObjectName(0, oi);
         if(StringFind(on, objectFamily) == 0) ObjectDelete(0, on);
      }
   }
   double y = isHigh ? (price + pointSize * 3.0) : (price - pointSize * 3.0);
   color clr = isHigh ? BearColor() : BullColor();
   DrawLabel(t[barIdx], y, label, clr, suffix);
}

color BullColor()    { return InpTheme == THEME_MONOCHROME ? C'0x75,0x75,0x75' : InpBullColor; }
color BearColor()    { return InpTheme == THEME_MONOCHROME ? C'0xB0,0xB0,0xB0' : InpBearColor; }
color NeutralColor() { return InpTheme == THEME_MONOCHROME ? C'0x90,0x90,0x90' : InpNeutralColor; }
color EqualColor(bool isHigh)
{
   if(InpTheme == THEME_MONOCHROME) return C'0x90,0x90,0x90';
   return isHigh ? InpEQHColor : InpEQLColor;
}

color OBColor(bool isBullish, bool isSwing)
{
   if(InpTheme == THEME_MONOCHROME)
      return isSwing ? C'0x70,0x70,0x70' : C'0xA0,0xA0,0xA0';
   if(isSwing) return isBullish ? InpSwingBullOBColor : InpSwingBearOBColor;
   return isBullish ? InpInternalBullOBColor : InpInternalBearOBColor;
}

color FVGColor(bool isBullish)
{
   if(InpTheme == THEME_MONOCHROME) return C'0x90,0x90,0x90';
   return isBullish ? InpBullFVGColor : InpBearFVGColor;
}

double AverageTrueRangeAt(const double &h[], const double &l[], const double &c[],
                          int bar, int period)
{
   if(bar < 1) return 0.0;
   int first = MathMax(1, bar - period + 1);
   double sum = 0.0;
   int count = 0;
   for(int i = first; i <= bar; i++)
   {
      sum += MathMax(h[i] - l[i], MathMax(MathAbs(h[i] - c[i-1]), MathAbs(l[i] - c[i-1])));
      count++;
   }
   return count > 0 ? sum / count : 0.0;
}

double AverageRangeAt(const double &h[], const double &l[], int bar, int period)
{
   if(bar < 0) return 0.0;
   int first = MathMax(0, bar - period + 1);
   double sum = 0.0;
   int count = 0;
   for(int i = first; i <= bar; i++) { sum += h[i] - l[i]; count++; }
   return count > 0 ? sum / count : 0.0;
}

bool PassInternalConfluence(bool bullish, int bar, const double &o[], const double &h[],
                            const double &l[], const double &c[])
{
   if(!InpInternalConfluence) return true;
   double bodyTop = MathMax(o[bar], c[bar]);
   double bodyBottom = MathMin(o[bar], c[bar]);
   double upperWick = h[bar] - bodyTop;
   double lowerWick = bodyBottom - l[bar];
   return bullish ? lowerWick >= upperWick : upperWick >= lowerWick;
}

bool PassOBVolatility(int bar, const double &h[], const double &l[], const double &c[])
{
   if(InpOBFilter == OB_FILTER_NONE) return true;
   double baseline = InpOBFilter == OB_FILTER_ATR
                     ? AverageTrueRangeAt(h, l, c, bar, InpOBFilterPeriod)
                     : AverageRangeAt(h, l, bar, InpOBFilterPeriod);
   return baseline <= 0 || h[bar] - l[bar] <= baseline * InpOBMaxRange;
}

bool PassFVGThreshold(int bar, double gap, const double &h[], const double &l[],
                      const double &c[], double pointSize)
{
   if(InpFVGMinSize > 0 && gap < InpFVGMinSize * pointSize) return false;
   if(!InpFVGAutoThreshold) return true;
   double atr = AverageTrueRangeAt(h, l, c, bar, InpFVGATRPeriod);
   return atr <= 0 || gap >= atr * InpFVGATRFactor;
}

void ManageTrailingExtremes(const datetime &t[], int total)
{
   if(!InpShowStrongWeak || !InpShowLabels || total < 2 || g_sw.pivHiCnt < 1 || g_sw.pivLoCnt < 1) return;
   int hi = g_sw.pivHiCnt - 1;
   int lo = g_sw.pivLoCnt - 1;
   string hiName = g_prefix + "TRAIL_HIGH";
   string loName = g_prefix + "TRAIL_LOW";
   string hiText = g_sw.trendDir > 0 ? "Weak High" : "Strong High";
   string loText = g_sw.trendDir < 0 ? "Weak Low" : "Strong Low";
   datetime endTime = t[total-1];

   if(ObjectFind(0, hiName) < 0) ObjectCreate(0, hiName, OBJ_TEXT, 0, endTime, g_sw.pivotsHi[hi].price);
   ObjectMove(0, hiName, 0, endTime, g_sw.pivotsHi[hi].price);
   ObjectSetString(0, hiName, OBJPROP_TEXT, hiText);
   ObjectSetInteger(0, hiName, OBJPROP_COLOR, BearColor());
   ObjectSetInteger(0, hiName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, hiName, OBJPROP_SELECTABLE, false);

   if(ObjectFind(0, loName) < 0) ObjectCreate(0, loName, OBJ_TEXT, 0, endTime, g_sw.pivotsLo[lo].price);
   ObjectMove(0, loName, 0, endTime, g_sw.pivotsLo[lo].price);
   ObjectSetString(0, loName, OBJPROP_TEXT, loText);
   ObjectSetInteger(0, loName, OBJPROP_COLOR, BullColor());
   ObjectSetInteger(0, loName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, loName, OBJPROP_SELECTABLE, false);
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
   double range = swHi - swLo;
   double band = range * InpPDZBandPercent / 100.0;
   double premiumBottom = swHi - band;
   double discountTop = swLo + band;
   datetime zoneStart = (tHi > tLo) ? tHi : tLo;
   datetime zoneEnd   = t[total-1] + PeriodSeconds() * 5;

   // Update or create premium zone — update ALL coordinates
   string nmP = g_prefix + "PDZ_Prem";
   if(ObjectFind(0, nmP) < 0)
   {
      if(ObjectCreate(0, nmP, OBJ_RECTANGLE, 0, zoneStart, swHi, zoneEnd, premiumBottom))
      {
         ObjectSetInteger(0, nmP, OBJPROP_COLOR, BearColor());
         ObjectSetInteger(0, nmP, OBJPROP_FILL, InpFillPDZ);
         ObjectSetInteger(0, nmP, OBJPROP_WIDTH, InpPDZWidth);
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
      ObjectSetDouble (0, nmP, OBJPROP_PRICE, 1, premiumBottom);
   }

   // Update or create discount zone — update ALL coordinates
   string nmD = g_prefix + "PDZ_Disc";
   if(ObjectFind(0, nmD) < 0)
   {
      if(ObjectCreate(0, nmD, OBJ_RECTANGLE, 0, zoneStart, discountTop, zoneEnd, swLo))
      {
         ObjectSetInteger(0, nmD, OBJPROP_COLOR, BullColor());
         ObjectSetInteger(0, nmD, OBJPROP_FILL, InpFillPDZ);
         ObjectSetInteger(0, nmD, OBJPROP_WIDTH, InpPDZWidth);
         ObjectSetInteger(0, nmD, OBJPROP_BACK, true);
         ObjectSetInteger(0, nmD, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nmD, OBJPROP_HIDDEN, true);
      }
   }
   else
   {
      ObjectSetInteger(0, nmD, OBJPROP_TIME,  0, zoneStart);
      ObjectSetDouble (0, nmD, OBJPROP_PRICE, 0, discountTop);
      ObjectSetInteger(0, nmD, OBJPROP_TIME,  1, zoneEnd);
      ObjectSetDouble (0, nmD, OBJPROP_PRICE, 1, swLo);
   }

   // Update or create equilibrium line — update ALL coordinates
   string nmE = g_prefix + "PDZ_EQ";
   if(ObjectFind(0, nmE) < 0)
   {
      if(ObjectCreate(0, nmE, OBJ_TREND, 0, zoneStart, eq, zoneEnd, eq))
      {
         ObjectSetInteger(0, nmE, OBJPROP_COLOR, NeutralColor());
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

   if(InpShowLabels)
   {
      string labels[3] = { "Premium", "Equilibrium", "Discount" };
      double prices[3] = { swHi, eq, swLo };
      color colors[3] = { BearColor(), NeutralColor(), BullColor() };
      for(int p = 0; p < 3; p++)
      {
         string labelName = g_prefix + "PDZ_LBL_" + IntegerToString(p);
         if(ObjectFind(0, labelName) < 0)
            ObjectCreate(0, labelName, OBJ_TEXT, 0, zoneEnd, prices[p]);
         ObjectMove(0, labelName, 0, zoneEnd, prices[p]);
         ObjectSetString(0, labelName, OBJPROP_TEXT, labels[p]);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, colors[p]);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_RIGHT);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
      }
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

bool StorePivot(PivotRec &buf[], int &cnt, int bar, double price, datetime t)
{
   for(int i = cnt - 1; i >= 0; i--)
   {
      if(buf[i].barIdx == bar || buf[i].time == t) return false;
      if(buf[i].barIdx < bar) break;
   }
   if(cnt < MAX_PIVOTS)
   {
      buf[cnt].barIdx = bar;
      buf[cnt].price = price;
      buf[cnt].time = t;
      buf[cnt].consumed = false;
      cnt++;
   }
   else
   {
      for(int i = 0; i < MAX_PIVOTS - 1; i++) buf[i] = buf[i+1];
      buf[MAX_PIVOTS-1].barIdx = bar;
      buf[MAX_PIVOTS-1].price = price;
      buf[MAX_PIVOTS-1].time = t;
      buf[MAX_PIVOTS-1].consumed = false;
   }
   return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═════════════════════════════════════════════════════════════════════════════
void DrawStructureLine(datetime fromTime, double level, datetime toTime,
                        string prefix, string label, color clr)
{
   if(!InpShowLabels && InpDisplayMode == DISPLAY_PRESENT) return;

   if(InpDisplayMode == DISPLAY_PRESENT)
   {
      string family = g_prefix + "LINE_" + prefix;
      for(int oi = ObjectsTotal(0)-1; oi >= 0; oi--)
      {
         string on = ObjectName(0, oi);
         if(StringFind(on, family) == 0 || StringFind(on, g_prefix + "LBL_" + prefix) == 0)
            ObjectDelete(0, on);
      }
   }

   string nm = g_prefix + "LINE_" + prefix + "_" + label + "_" +
               IntegerToString((int)fromTime) + "_" + IntegerToString((int)toTime);
   if(ObjectFind(0, nm) >= 0) return;

   if(ObjectCreate(0, nm, OBJ_TREND, 0, fromTime, level, toTime, level))
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, InpStructureStyle);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }

   // Midpoint label
   if(InpShowLabels)
   {
      datetime midTime = fromTime + (toTime - fromTime) / 2;
      DrawLabel(midTime, level, label, clr, prefix + "_LBL_" + IntegerToString((int)fromTime) + "_" + IntegerToString((int)toTime));
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
   if(biasDir > 0)      g_candleCol[i] = 0.0;
   else if(biasDir < 0) g_candleCol[i] = 1.0;
   else                 g_candleCol[i] = EMPTY_VALUE;
}

// ═════════════════════════════════════════════════════════════════════════════
// ALERTS
// ═════════════════════════════════════════════════════════════════════════════
void FireAlert(string type, string detail, datetime barTime, double price,
               bool isNewBar)
{
   if(!InpAlertsActive) return;
   if(!isNewBar) return; // only alert on live bars
   if(StringFind(type, "OB") >= 0 && !InpAlertOB) return;
   if(type == "FVG" && !InpAlertFVG) return;
   if((type == "EQH" || type == "EQL") && !InpAlertEQ) return;
   if((type == "Swing" || type == "Internal") && !InpAlertStructure) return;

   // One alert per bar per type
   string key = type + "_" + detail;
   if(barTime == g_lastAlertBar && key == g_lastAlertType) return;
   g_lastAlertBar = barTime;
   g_lastAlertType = key;

   string msg = StringFormat("[SMC Suite] %s %s | %s %s | %.5f",
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
   g_int.trendDir = 0;  g_sw.trendDir = 0;
   g_int.biasEstablished = false;  g_sw.biasEstablished = false;
   ArrayFree(g_intOBs);  ArrayFree(g_swOBs);
   ArrayFree(g_fvgs);    ArrayFree(g_eqPairs);
   g_lastBarTime = 0;
   g_lastHTFBarTime = 0;
   g_lastAlertBar = 0;  g_lastAlertType = "";
   g_lastCalcDay = 0;  g_lastCalcWeek = 0;  g_lastCalcMonth = 0;
   g_dh = EMPTY_VALUE; g_dl = EMPTY_VALUE; g_wh = EMPTY_VALUE; g_wl = EMPTY_VALUE; g_mh = EMPTY_VALUE; g_ml = EMPTY_VALUE;
   g_dayCurHigh = 0; g_dayCurLow = 0;
   g_weekCurHigh = 0; g_weekCurLow = 0;
   g_monthCurHigh = 0; g_monthCurLow = 0;
   g_dayInit = false; g_weekInit = false; g_monthInit = false;
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
