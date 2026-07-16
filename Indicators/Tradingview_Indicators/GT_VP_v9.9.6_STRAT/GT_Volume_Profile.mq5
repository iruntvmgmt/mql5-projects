//+------------------------------------------------------------------+
//|                                     God Tier Volume Profile.mq5   |
//|                    Ported from Pine Script v6 → MQL5              |
//|                    Original: GT_VP_v9.9.6_STRAT.pine             |
//|                    v7.4: Session-mode VP lookback, z-order layering,  |
//|                    200-bar FVG first-load window, stable             |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script — GT VP"
#property version     "7.42"
#property description ":: God Tier Volume Profile — v7.42 ::"
#property description "Volume Profile, histogram, LVN, FVG+IFVG, Ghost Trails,"
#property description "VA Cloud, Sessions, Prior VA, Signals, Market Structure."
#property description "v7.42: Closed-bar signals, session-init scan, split priorPOC, BOS counters"

#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   6

// ── Plots ───────────────────────────────────────────────────────────────────
#property indicator_label1  "VAH"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'0xF2,0x36,0x45'
#property indicator_width1  2
#property indicator_style1  STYLE_DASH

#property indicator_label2  "VAL"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'0x08,0x99,0x81'
#property indicator_width2  2
#property indicator_style2  STYLE_DASH

#property indicator_label3  "POC"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  2

#property indicator_label4  "Developing VAH"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_width4  1

#property indicator_label5  "Developing VAL"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrAqua
#property indicator_width5  1

#property indicator_label6  "FVG Display"
#property indicator_type6   DRAW_NONE

// ── VP lookback mode ────────────────────────────────────────────────────────
enum ENUM_VP_LOOKBACK_MODE
{
   VP_LB_FIXED_BARS,      // Fixed Bar Count (legacy — does NOT scale across timeframes)
   VP_LB_SESSION          // Auto-Scale to Session Type dropdown (Daily/Weekly/Monthly/Tokyo/London/NY)
};

// ── Session type enum ────────────────────────────────────────────────────────
enum ENUM_SESSION_TYPE
{
   SESSION_DAILY,
   SESSION_WEEKLY,
   SESSION_MONTHLY,
   SESSION_TOKYO,
   SESSION_LONDON,
   SESSION_NEWYORK
};

// ══════════════════════════════════════════════════════════════════════════════
// INPUTS
// ══════════════════════════════════════════════════════════════════════════════

input group                        "═══ Volume Profile ═══"
input ENUM_VP_LOOKBACK_MODE        InpVPLookbackMode = VP_LB_FIXED_BARS; // VP Lookback Mode — Session mode auto-scales to any timeframe
input int                          InpVPLookback   = 500;                // VP Lookback Bars (Fixed Bar Count mode only)
input int                          InpInitialBackfill = 2000;             // Initial Backfill Bars (max history to process on first load)
input int                          InpVPNumRows    = 40;                 // VP Resolution (rows)
input double                       InpVA_Pct       = 70.0;               // Value Area % (typical: 70)
input double                       InpVPWidthPct   = 25.0;               // Histogram Width (% of chart)
input bool                         InpShowHistogram= true;               // Show Volume Histogram
input bool                         InpShowLVN      = true;               // Show LVN Markers
input double                       InpLVNThreshold = 0.15;               // LVN Threshold (fraction of POC)
input bool                         InpHeatmap      = true;               // Gradient Heatmap Colors

input group                        "═══ Dynamic Binning ═══"
input bool                         InpDynamicBins  = true;               // ATR-Based Dynamic Bins
input int                          InpGranularity  = 40;                 // Granularity Factor (10-100)
input bool                         InpGranularityAuto = true;            // Auto-Scale Granularity (TF-Aware)
input int                          InpFixedBins    = 50;                 // Fixed Bins (if dynamic off)
input bool                         InpAdaptiveGran = true;               // Adaptive Granularity (session-expand)

input group                        "═══ Session ═══"
input ENUM_SESSION_TYPE            InpSessionType  = SESSION_DAILY;      // Session Type
input bool                         InpShowSessionBox = true;             // Show Session Box
input bool                         InpShowSessionLabels = true;          // Show Session Labels

input group                        "═══ Developing VP ═══"
input bool                         InpShowDevVP    = true;               // Show Developing VP
input int                          InpDevVPLen     = 50;                 // Dev VP Lookback Bars

input group                        "═══ Ghost Trails ═══"
input bool                         InpShowGhost    = true;               // POC Ghost Trails (Stepline)
input bool                         InpColoredGhost = true;               // Colored Ghost Trails
input double                       InpGhostATRFilt = 0.05;               // Ghost Trail Min ATR Move

input group                        "═══ VA Cloud ═══"
input bool                         InpShowVACloud  = true;               // Developing VA Cloud
input bool                         InpVADeltaTint  = true;               // Delta-Tinted Cloud
input bool                         InpVAReclaimBorder = true;            // VA Reclaim/Rejection Border
input int                          InpMaxCloudTiles = 100;               // Max Cloud Tiles

input group                        "═══ Prior VA ═══"
input bool                         InpShowPriorVA  = true;               // Prior Session VA Reference

input group                        "═══ FVG ═══"
input bool                         InpShowFVG      = true;               // Show Fair Value Gaps
input int                          InpFVGMaxAge    = 30;                 // Max FVG Age (bars)
input double                       InpFVGMinSizeATR= 0.3;                // FVG Min Size (ATR multiplier)
input bool                         InpShowIFVG     = true;               // Show Inverse FVGs (IFVG)
input int                          InpFVGMaxActive = 20;                 // Max Active FVGs
input int                          InpIFVGMaxActive = 15;                // Max Active IFVGs

input group                        "═══ Visuals ═══"
input bool                         InpShowDash     = true;               // Show Dashboard
input bool                         InpFillVA       = true;               // Fill Value Area
input bool                         InpShowProfileShape = true;           // Show Profile Shape Analysis
input bool                         InpShowVAMetrics = true;              // VA Breathing Metrics
input double                       InpVAExpansion  = 1.1;               // Expansion Threshold
input double                       InpVAContraction= 0.9;               // Contraction Threshold
input bool                         InpShowImbalances = true;             // Stacked Imbalances
input double                       InpImbalanceRatio = 3.0;              // Imbalance Threshold (buy/sell ratio)
input bool                         InpShowFastLanes = true;              // Fast Lanes (Liquidity Voids)
input double                       InpFastLaneThresh = 0.15;             // Fast Lane Threshold (vs max vol)
input int                          InpFastLaneMinWidth = 2;              // Fast Lane Min Zone Width (bins)
input bool                         InpShowPerf = true;                   // Performance Monitor in Dashboard
input double                       InpEmergencyCleanup = 85.0;            // Emergency Cleanup %

input group                        "═══ Order Flow & Signals ═══"
input bool                         InpShowFailedAuction = true;          // Failed Auctions
input double                       InpFAVolThreshold = 0.30;             // FA Vol Threshold (% of max vol)
input int                          InpFALookback     = 8;                // FA Breakout Lookback (bars)
input double                       InpFAMinPenATR    = 0.08;             // FA Min Penetration (ATR mult)
input double                       InpFADisplacementATR = 0.25;          // FA Displacement (ATR mult)
input int                          InpFAConfirmBars  = 2;                // FA Confirm Window (bars)
input int                          InpFACooldown     = 10;               // FA Cooldown (bars)
input bool                         InpShowAbsorption = true;              // Absorption Detection
input bool                         InpShowIceberg    = true;              // Iceberg Detection
input bool                         InpShowExhaustion = true;              // Exhaustion Signals
input bool                         InpShowDivergence = true;              // Delta Divergence
input bool                         InpShowSMD        = true;              // Smart Money Divergence
input int                          InpSMDLookback    = 10;                // SMD Lookback (bars)
input bool                         InpShowDeltaStrength = true;           // Delta Strength (CVD Momentum)
input int                          InpDeltaStrLen    = 20;                // Delta Strength Length
input bool                         InpShowRotation   = true;              // Rotation Factor
input bool                         InpShowFlowPressure = true;            // Flow Pressure in Dashboard

input group                        "═══ Market Structure ═══"
input bool                         InpShowMktStruct = true;               // Enable Market Structure Layer
input bool                         InpShowZZLines   = true;               // ZigZag Connecting Lines
input bool                         InpShowHHLL      = true;               // HH/HL/LH/LL Labels
input bool                         InpShowSwingLevels = true;             // Swing Resistance/Support Lines
input bool                         InpShowEquilibrium = true;             // Equilibrium Line
input bool                         InpShowBOSCHOCH  = true;               // BOS/CHoCH Markers
input int                          InpZZATRLen      = 14;                 // ZZ ATR Length
input double                       InpZZATRMult     = 1.5;                // ZZ ATR Reversal Multiplier
input int                          InpZZMinSwingBars = 3;                 // ZZ Min Bars Between Swings
input int                          InpBOSConfirmCandles = 2;              // BOS/CHoCH Confirm Candles
input bool                         InpBOSBodyBreak  = true;               // Body Break for BOS/CHoCH
input bool                         InpShowSweeps    = true;               // Show Liquidity Sweeps
input double                       InpSweepThresh   = 0.60;               // Sweep Rejection % (of bar range)
input double                       InpSweepMinPenATR = 0.08;              // Sweep Min Penetration ATR
input double                       InpSweepDispATR  = 0.25;               // Sweep Displacement ATR
input int                          InpSweepConfirmBars = 2;               // Sweep Confirm Window
input int                          InpSweepCooldown = 10;                 // Sweep Cooldown Bars
input bool                         InpSweepBodyReclaim = true;            // Sweep Requires Close Reclaim
input bool                         InpShowStructScore = true;             // Structure Score in Dashboard

// ── DBL_MAX helper ──────────────────────────────────────────────────────────
#define DBL_MAX_VAL 1.7976931348623157e+308

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_vah[];         // 0  VAH
double g_val[];         // 1  VAL
double g_poc[];         // 2  POC
double g_devVah[];      // 3  Developing VAH
double g_devVal[];      // 4  Developing VAL
double g_fvgDisp[];     // 5  FVG display (DRAW_NONE)
double g_volProfile[];  // 6  Calc

string g_prefix = "GTVP_";
int    g_fvgCount = 0;
int    g_maxFVG = 50;

// ── FVG/IFVG struct for mitigation tracking ────────────────────────────────
#define MAX_FVG_TRACK 30
#define MAX_IFVG_TRACK 20
struct FVGData
{
   string name;
   int    bias;        // 1=bull, -1=bear
   double highPrice;
   double lowPrice;
   datetime startTime;
   datetime endTime;
   bool   active;
};
FVGData g_fvgList[MAX_FVG_TRACK];
int     g_fvgListCount = 0;
FVGData g_ifvgList[MAX_IFVG_TRACK];
int     g_ifvgListCount = 0;
bool    g_ifvgFlipBull = false, g_ifvgFlipBear = false;

// ── Global VP state — computed on bar close, read on every tick ─────────────
double g_VAH, g_VAL, g_POC;
double g_vpLow, g_vpHigh, g_binSize;
double g_volBins[];
double g_buyBins[];       // buy-side volume per bin
double g_sellBins[];      // sell-side volume per bin
int    g_rows, g_pocBin, g_vahBin, g_valBin;
double g_totalVol, g_maxVol;
string g_profileShape;
int    g_vpStart, g_vpEnd;

// ── Session state ────────────────────────────────────────────────────────────
int    g_sessionStartBar = 0;
datetime g_sessionStartTime = 0;
int    g_sessionBarCount = 0;
int    g_prevSessionBars = 100;   // bootstrapped, then updated each zoneEnd
bool   g_isNewSession = false;

// ── Prior session VA ────────────────────────────────────────────────────────
double g_priorVAH = 0, g_priorVAL = 0, g_priorSessionPOC = 0;
bool   g_hasPriorVA = false;

// ── Ghost trail state ───────────────────────────────────────────────────────
double g_lastGhostPrice = 0;
int    g_lastGhostBar = 0;
color  g_lastGhostColor = clrGray;

// ── VA breathing ─────────────────────────────────────────────────────────────
double g_priorVAWidth = 0;
string g_vaState = "Neutral";
int    g_vaExpansionCount = 0;
int    g_vaContractionCount = 0;

// ── VA reclaim tracking ─────────────────────────────────────────────────────
bool   g_prevPriceInsideVA = true;

// ── CVD / flow tracking ─────────────────────────────────────────────────────
double g_cumulativeDelta = 0;
double g_sessionBuyVol = 0, g_sessionSellVol = 0;
double g_flowPressure = 0;

// ── Cloud tile arrays ───────────────────────────────────────────────────────
#define MAX_CLOUD_TILES 100
string g_cloudTileNames[MAX_CLOUD_TILES];
int    g_cloudTileCount = 0;
int    g_cloudSpawnBar = 0;

// ── Failed Auction state ────────────────────────────────────────────────────
bool   g_faBull = false, g_faBear = false;
bool   g_faBullPending = false, g_faBearPending = false;
double g_faBullLevel = 0, g_faBearLevel = 0;
int    g_faBullBar = 0, g_faBearBar = 0;
int    g_faLastBullBar = 0, g_faLastBearBar = 0;
double g_faLastBullLevel = 0, g_faLastBearLevel = 0;

// ── Absorption / Iceberg / Exhaustion ───────────────────────────────────────
bool   g_absorptionSignal = false;
bool   g_icebergSignal = false;
bool   g_exhaustionSignal = false;
string g_exhaustionType = "None";

// ── Delta Divergence ────────────────────────────────────────────────────────
bool   g_bullishDiv = false, g_bearishDiv = false;
double g_prevDivHigh = 0, g_prevDivLow = 0;
double g_prevDivHighDelta = 0, g_prevDivLowDelta = 0;

// ── Smart Money Divergence ──────────────────────────────────────────────────
bool   g_smdAccum = false, g_smdDist = false;

// ── Delta Strength / Rotation / VWAD ────────────────────────────────────────
double g_deltaStrength = 0;
double g_rotationFactor = 0;
double g_previousDevelopingPOC = 0;  // separate from g_priorSessionPOC (audit fix #3)
double g_vwad = 0;
int    g_rotationUp = 0, g_rotationDown = 0;

// ── Session CVD bounds ──────────────────────────────────────────────────────
double g_sessionCVDHigh = 0, g_sessionCVDLow = 0;
double g_normalizedCVD = 0;

// ── Market Structure — ZigZag swings ────────────────────────────────────────
double g_zzSwingHigh = 0, g_zzSwingLow = 0;
double g_zzPrevSwingHigh = 0, g_zzPrevSwingLow = 0;
int    g_zzSwingHighBar = 0, g_zzSwingLowBar = 0;
int    g_zzPrevSwingHighBar = 0, g_zzPrevSwingLowBar = 0;
double g_zzHighExtreme = 0, g_zzLowExtreme = DBL_MAX_VAL;
int    g_zzHighExtremeBar = 0, g_zzLowExtremeBar = 0;
bool   g_zzNewSwingHigh = false, g_zzNewSwingLow = false;

// ── Market Structure — Classification ───────────────────────────────────────
bool   g_msHH = false, g_msHL = false, g_msLH = false, g_msLL = false;
int    g_zzStructBias = 0;

// ── Market Structure — BOS/CHoCH ─────────────────────────────────────────────
bool   g_zzBullBOS = false, g_zzBearBOS = false;
bool   g_zzBullCHoCH = false, g_zzBearCHoCH = false;
int    g_zzBOSConfirmCount = 0;
int    g_zzBOSActiveType = 0;  // 0=none, 1=bullBOS, -1=bearBOS, 2=bullCHoCH, -2=bearCHoCH (audit fix #12)

// ── Market Structure — Liquidity Sweeps ─────────────────────────────────────
bool   g_zzBullSweep = false, g_zzBearSweep = false;
bool   g_zzBullSweepPending = false, g_zzBearSweepPending = false;
double g_zzSweepLevel = 0;
int    g_zzSweepBar = 0;
int    g_zzLastSweepBullBar = 0, g_zzLastSweepBearBar = 0;
double g_zzLastSweepBullLevel = 0, g_zzLastSweepBearLevel = 0;
bool   g_zzHighConvBull = false, g_zzHighConvBear = false;

// ── Market Structure — Scores ────────────────────────────────────────────────
double g_zzScoreLong = 50.0, g_zzScoreShort = 50.0;

//+------------------------------------------------------------------+
//| Helpers                                                           |
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
//| Session Detection — returns true on session boundary               |
//+------------------------------------------------------------------+
bool IsNewSession(datetime barTime, datetime prevBarTime)
{
   if(prevBarTime == 0) return false;
   MqlDateTime dt, dtPrev;
   TimeToStruct(barTime, dt);
   TimeToStruct(prevBarTime, dtPrev);
   switch(InpSessionType)
   {
      case SESSION_DAILY:    return (dt.day != dtPrev.day);
      case SESSION_WEEKLY:   return (dt.day_of_week < dtPrev.day_of_week || (dt.day - dtPrev.day) >= 7);
      case SESSION_MONTHLY:  return (dt.mon != dtPrev.mon);
      case SESSION_TOKYO:    return (dt.hour == 0 && dtPrev.hour != 0);
      case SESSION_LONDON:   return (dt.hour == 7 && dtPrev.hour != 7);
      case SESSION_NEWYORK:  return (dt.hour == 13 && dtPrev.hour != 13);
      default:               return (dt.day != dtPrev.day);
   }
}

//+------------------------------------------------------------------+
//| Get session name string                                           |
//+------------------------------------------------------------------+
string SessionName()
{
   switch(InpSessionType)
   {
      case SESSION_DAILY:    return "Daily";
      case SESSION_WEEKLY:   return "Weekly";
      case SESSION_MONTHLY:  return "Monthly";
      case SESSION_TOKYO:    return "Tokyo";
      case SESSION_LONDON:   return "London";
      case SESSION_NEWYORK:  return "New York";
      default:               return "Daily";
   }
}

//+------------------------------------------------------------------+
//| Calculate dynamic bin count based on ATR and session range         |
//+------------------------------------------------------------------+
int CalcDynamicRows(double vpRange, double atr, int tfMinutes)
{
   if(!InpDynamicBins) return MathMax(10, MathMin(200, InpFixedBins));
   double tfScale = 1.0;
   if(InpGranularityAuto)
   {
      if(tfMinutes <= 1)       tfScale = 1.40;
      else if(tfMinutes <= 5)  tfScale = 1.0;
      else if(tfMinutes <= 15) tfScale = 0.75;
      else if(tfMinutes <= 60) tfScale = 0.55;
      else                     tfScale = 0.35;
   }
   int baseRows = (int)(InpGranularity * tfScale);
   if(baseRows < 10) baseRows = 10;
   if(baseRows > 200) baseRows = 200;
   if(InpAdaptiveGran && atr > 0 && vpRange > 0)
   {
      double rangeInATR = vpRange / atr;
      double adaptFactor = MathMax(0.5, MathMin(2.0, rangeInATR / 20.0));
      baseRows = (int)(baseRows * adaptFactor);
      if(baseRows < 10) baseRows = 10;
      if(baseRows > 200) baseRows = 200;
   }
   return baseRows;
}

//+------------------------------------------------------------------+
//| DetectFailedAuction — probe beyond VA edge + displacement confirm  |
//+------------------------------------------------------------------+
void DetectFailedAuction(const double &h[], const double &l[], const double &c[],
                         const double &o[], int idx, double atr, int lookback)
{
   g_faBull = false; g_faBear = false;
   if(g_VAH <= 0 || g_VAL <= 0 || atr <= 0) return;
   
   double minPen = atr * InpFAMinPenATR;
   double displacement = atr * InpFADisplacementATR;
   double faMaxVolFrac = g_maxVol * InpFAVolThreshold;
   
   double recentHigh = h[idx], recentLow = l[idx];
   int lbStart = MathMax(0, idx - lookback);
   for(int i = lbStart; i < idx; i++)
   {
      if(h[i] > recentHigh) recentHigh = h[i];
      if(l[i] < recentLow)  recentLow  = l[i];
   }
   
   bool bearCooldownOK = (g_faLastBearBar == 0) || (idx - g_faLastBearBar > InpFACooldown)
                         || (g_VAH != g_faLastBearLevel);
   bool bearProbe = (h[idx] > recentHigh && h[idx] > g_VAH + minPen);
   int vahBin = (int)((g_VAH - g_vpLow) / g_binSize);
   if(vahBin < 0) vahBin = 0; if(vahBin >= g_rows) vahBin = g_rows - 1;
   bool bearThin = (g_volBins[vahBin] <= faMaxVolFrac);
   if(bearProbe && bearThin && bearCooldownOK && !g_faBearPending)
      { g_faBearPending = true; g_faBearLevel = g_VAH; g_faBearBar = idx; }
   
   bool bullCooldownOK = (g_faLastBullBar == 0) || (idx - g_faLastBullBar > InpFACooldown)
                         || (g_VAL != g_faLastBullLevel);
   bool bullProbe = (l[idx] < recentLow && l[idx] < g_VAL - minPen);
   int valBin = (int)((g_VAL - g_vpLow) / g_binSize);
   if(valBin < 0) valBin = 0; if(valBin >= g_rows) valBin = g_rows - 1;
   bool bullThin = (g_volBins[valBin] <= faMaxVolFrac);
   if(bullProbe && bullThin && bullCooldownOK && !g_faBullPending)
      { g_faBullPending = true; g_faBullLevel = g_VAL; g_faBullBar = idx; }
   
   if(g_faBearPending)
   {
      bool within = (idx - g_faBearBar <= InpFAConfirmBars);
      bool disp = within && c[idx] < g_faBearLevel - displacement && c[idx] < o[idx];
      bool reacc = g_faBearPending && c[idx] > g_faBearLevel;
      if(disp) { g_faBear = true; g_faBearPending = false; g_faLastBearBar = idx; g_faLastBearLevel = g_VAH; }
      else if(!within || reacc) g_faBearPending = false;
   }
   if(g_faBullPending)
   {
      bool within = (idx - g_faBullBar <= InpFAConfirmBars);
      bool disp = within && c[idx] > g_faBullLevel + displacement && c[idx] > o[idx];
      bool reacc = g_faBullPending && c[idx] < g_faBullLevel;
      if(disp) { g_faBull = true; g_faBullPending = false; g_faLastBullBar = idx; g_faLastBullLevel = g_VAL; }
      else if(!within || reacc) g_faBullPending = false;
   }
}

//+------------------------------------------------------------------+
//| DetectAbsorption — high volume defending a key level              |
//+------------------------------------------------------------------+
void DetectAbsorption(double vol, double range, double atr, double closePrice, double avgVol20)
{
   g_absorptionSignal = false;
   if(!InpShowAbsorption || atr <= 0) return;
   double volGate = avgVol20 * 2.5;
   if(vol < volGate) return;
   bool nearKey = false;
   if(g_VAH > 0) nearKey = nearKey || (MathAbs(closePrice - g_VAH) <= atr * 1.5);
   if(g_VAL > 0) nearKey = nearKey || (MathAbs(closePrice - g_VAL) <= atr * 1.5);
   if(g_POC > 0) nearKey = nearKey || (MathAbs(closePrice - g_POC) <= atr * 1.5);
   if(!nearKey) return;
   if(range / atr < 0.5) g_absorptionSignal = true;
}

//+------------------------------------------------------------------+
//| DetectIceberg — concentrated volume at single bin at key level     |
//+------------------------------------------------------------------+
void DetectIceberg(double closePrice, double atr)
{
   g_icebergSignal = false;
   if(!InpShowIceberg || g_binSize <= 0 || g_rows <= 0) return;
   int curBin = (int)((closePrice - g_vpLow) / g_binSize);
   if(curBin < 0) curBin = 0; if(curBin >= g_rows) curBin = g_rows - 1;
   double avgBinVol = (g_totalVol > 0 && g_rows > 0) ? g_totalVol / g_rows : 0;
   if(g_volBins[curBin] < avgBinVol * 3.0) return;
   bool nearKey = false;
   if(g_VAH > 0) nearKey = nearKey || (MathAbs(curBin - g_vahBin) <= 2);
   if(g_VAL > 0) nearKey = nearKey || (MathAbs(curBin - g_valBin) <= 2);
   if(g_POC > 0) nearKey = nearKey || (MathAbs(curBin - g_pocBin) <= 2);
   if(nearKey) g_icebergSignal = true;
}

//+------------------------------------------------------------------+
//| DetectExhaustion — price/delta disagreement at extremes            |
//+------------------------------------------------------------------+
void DetectExhaustion(double closePrice, double closePrice4, double cvdNow, double cvd4)
{
   g_exhaustionSignal = false; g_exhaustionType = "None";
   if(!InpShowExhaustion) return;
   double priceNet = closePrice - closePrice4;
   double deltaNet = cvdNow - cvd4;
   if(priceNet > 0 && deltaNet < 0)
      { g_exhaustionSignal = true; g_exhaustionType = "Buying Exhaustion"; }
   else if(priceNet < 0 && deltaNet > 0)
      { g_exhaustionSignal = true; g_exhaustionType = "Selling Exhaustion"; }
}

//+------------------------------------------------------------------+
//| DetectDivergence — pivot-level delta divergence                    |
//+------------------------------------------------------------------+
void DetectDivergence(const double &h[], const double &l[], int idx)
{
   g_bullishDiv = false; g_bearishDiv = false;
   if(!InpShowDivergence || idx < 20) return;
   double swingHigh = h[idx], swingLow = l[idx];
   for(int i = idx - 5; i <= idx; i++)
   {
      if(i < 0) continue;
      if(h[i] > swingHigh) swingHigh = h[i];
      if(l[i] < swingLow)  swingLow  = l[i];
   }
   if(swingHigh > g_prevDivHigh && g_prevDivHigh > 0)
   {
      if(g_cumulativeDelta < g_prevDivHighDelta && g_VAH > 0 && h[idx] >= g_VAH - g_binSize * 3)
         g_bearishDiv = true;
   }
   if(swingLow < g_prevDivLow && g_prevDivLow > 0)
   {
      if(g_cumulativeDelta > g_prevDivLowDelta && g_VAL > 0 && l[idx] <= g_VAL + g_binSize * 3)
         g_bullishDiv = true;
   }
   if(swingHigh > g_prevDivHigh || g_prevDivHigh == 0)
      { g_prevDivHigh = swingHigh; g_prevDivHighDelta = g_cumulativeDelta; }
   if(swingLow < g_prevDivLow || g_prevDivLow == 0)
      { g_prevDivLow = swingLow; g_prevDivLowDelta = g_cumulativeDelta; }
}

//+------------------------------------------------------------------+
//| DetectSMD — Smart Money Divergence (price/volume disagreement)     |
//+------------------------------------------------------------------+
void DetectSMD(const double &c[], int idx, int lookback, double atr)
{
   g_smdAccum = false; g_smdDist = false;
   if(!InpShowSMD || idx < lookback) return;
   double minMove = atr * 0.75;
   if(MathAbs(c[idx] - c[idx - lookback]) < minMove) return;
   bool priceRising  = c[idx] > c[idx - lookback];
   bool priceFalling = c[idx] < c[idx - lookback];
   double volNow = 0, volOld = 0; int cnt = 0;
   for(int i = MathMax(0, idx - 4); i <= idx; i++)      { volNow += (double)iVolume(_Symbol, _Period, i); cnt++; }
   volNow /= cnt; cnt = 0;
   for(int i = MathMax(0, idx - lookback - 4); i <= idx - lookback; i++) { volOld += (double)iVolume(_Symbol, _Period, i); cnt++; }
   volOld /= MathMax(1, cnt);
   if(volNow >= volOld) return;
   if(priceRising && g_VAH > 0 && c[idx] >= g_VAH - g_binSize * 3)  g_smdDist = true;
   if(priceFalling && g_VAL > 0 && c[idx] <= g_VAL + g_binSize * 3) g_smdAccum = true;
}

//+------------------------------------------------------------------+
//| CalcDeltaStrength — CVD rate-of-change normalized to -100/+100    |
//+------------------------------------------------------------------+
void CalcDeltaStrength(int idx, int len)
{
   g_deltaStrength = 0;
   if(!InpShowDeltaStrength || idx < len) return;
   double maxCVDChange = 0;
   for(int i = MathMax(g_sessionStartBar, idx - len); i <= idx; i++)
   {
      double vv = (double)iVolume(_Symbol, _Period, i);
      if(vv > maxCVDChange) maxCVDChange = vv;
   }
   maxCVDChange *= len * 0.3;
   if(maxCVDChange <= 0) maxCVDChange = 1;
   double cvdChange = g_sessionBuyVol - g_sessionSellVol;
   g_deltaStrength = MathMax(-100.0, MathMin(100.0, cvdChange / maxCVDChange * 100.0));
}

//+------------------------------------------------------------------+
//| CalcRotationFactor — directional confidence of POC migration       |
//+------------------------------------------------------------------+
void CalcRotationFactor()
{
   if(!InpShowRotation) { g_rotationFactor = 0; return; }
   if(g_previousDevelopingPOC > 0 && g_POC > 0)
   {
      if(g_POC > g_previousDevelopingPOC) g_rotationUp++;
      else if(g_POC < g_previousDevelopingPOC) g_rotationDown++;
   }
   g_previousDevelopingPOC = g_POC;
   int total = g_rotationUp + g_rotationDown;
   g_rotationFactor = (total > 0) ? (double)(g_rotationUp - g_rotationDown) / total : 0;
}

//+------------------------------------------------------------------+
//| UpdateZZSwingExtremes — track running high/low for swing detection |
//+------------------------------------------------------------------+
void UpdateZZSwingExtremes(const double &h[], const double &l[], int idx, double atr)
{
   g_zzNewSwingHigh = false; g_zzNewSwingLow = false;
   if(!InpShowMktStruct || idx < InpZZATRLen) return;
   
   double reversalThreshold = atr * InpZZATRMult;
   
   // Track running high extreme
   if(h[idx] > g_zzHighExtreme)
   {
      g_zzHighExtreme = h[idx];
      g_zzHighExtremeBar = idx;
   }
   // Confirm swing high: price retraces ATR*mult from extreme
   bool canConfirmHigh = (g_zzHighExtreme > 0 && l[idx] <= g_zzHighExtreme - reversalThreshold
      && idx - g_zzHighExtremeBar >= InpZZMinSwingBars);
   // Swing guard: if a low was just confirmed, suppress simultaneous high (audit fix #13)
   bool lowJustConfirmed = false;
   if(g_zzLowExtreme < DBL_MAX_VAL && h[idx] >= g_zzLowExtreme + reversalThreshold
      && idx - g_zzLowExtremeBar >= InpZZMinSwingBars)
   {
      lowJustConfirmed = true;
   }
   if(canConfirmHigh && !lowJustConfirmed)
   {
      g_zzPrevSwingHigh = g_zzSwingHigh;
      g_zzPrevSwingHighBar = g_zzSwingHighBar;
      g_zzSwingHigh = g_zzHighExtreme;
      g_zzSwingHighBar = g_zzHighExtremeBar;
      g_zzNewSwingHigh = true;
      g_zzHighExtreme = h[idx];
      g_zzHighExtremeBar = idx;
   }
   
   // Track running low extreme
   if(l[idx] < g_zzLowExtreme)
   {
      g_zzLowExtreme = l[idx];
      g_zzLowExtremeBar = idx;
   }
   // Confirm swing low: price rallies ATR*mult from extreme (suppressed if high just confirmed)
   if(g_zzLowExtreme < DBL_MAX_VAL && h[idx] >= g_zzLowExtreme + reversalThreshold
      && idx - g_zzLowExtremeBar >= InpZZMinSwingBars && !g_zzNewSwingHigh)
   {
      g_zzPrevSwingLow = g_zzSwingLow;
      g_zzPrevSwingLowBar = g_zzSwingLowBar;
      g_zzSwingLow = g_zzLowExtreme;
      g_zzSwingLowBar = g_zzLowExtremeBar;
      g_zzNewSwingLow = true;
      g_zzLowExtreme = l[idx];
      g_zzLowExtremeBar = idx;
   }
}

//+------------------------------------------------------------------+
//| ClassifyStructure — HH/HL/LH/LL from swing sequence                |
//+------------------------------------------------------------------+
void ClassifyStructure()
{
   g_msHH = false; g_msHL = false; g_msLH = false; g_msLL = false;
   if(!InpShowMktStruct || !InpShowHHLL) return;
   
   if(g_zzNewSwingHigh && g_zzPrevSwingHigh > 0 && g_zzSwingHigh > 0)
   {
      if(g_zzSwingHigh > g_zzPrevSwingHigh)
      {
         g_msHH = true;
         if(g_zzStructBias >= 0) g_zzStructBias = 1;
      }
      else
      {
         g_msLH = true;
         if(g_zzStructBias >= 0) g_zzStructBias = -1;
      }
   }
   
   if(g_zzNewSwingLow && g_zzPrevSwingLow > 0 && g_zzSwingLow > 0)
   {
      if(g_zzSwingLow > g_zzPrevSwingLow)
      {
         g_msHL = true;
         if(g_zzStructBias <= 0) g_zzStructBias = 1;
      }
      else
      {
         g_msLL = true;
         if(g_zzStructBias <= 0) g_zzStructBias = -1;
      }
   }
}

//+------------------------------------------------------------------+
//| DetectBOSCHOCH — break of structure / change of character          |
//+------------------------------------------------------------------+
void DetectBOSCHOCH(const double &h[], const double &l[], const double &c[],
                    const double &o[], int idx, double atr)
{
   g_zzBullBOS = false; g_zzBearBOS = false;
   g_zzBullCHoCH = false; g_zzBearCHoCH = false;
   if(!InpShowMktStruct || !InpShowBOSCHOCH) return;
   if(g_zzSwingHigh <= 0 || g_zzSwingLow <= 0) return;
   
   double breakPrice = InpBOSBodyBreak ? c[idx] : (g_zzStructBias >= 0 ? h[idx] : l[idx]);
   double breakPriceBear = InpBOSBodyBreak ? c[idx] : (g_zzStructBias <= 0 ? l[idx] : h[idx]);
   double refHigh = g_zzSwingHigh;
   double refLow = g_zzSwingLow;
   
   // Determine active candidate type this bar — reset counter if type changes (audit fix #12)
   int candidateType = 0;
   if(g_zzStructBias >= 0 && breakPrice > refHigh)
      candidateType = 1;   // bull BOS
   else if(g_zzStructBias >= 0 && breakPriceBear < refLow)
      candidateType = -2;  // bear CHoCH
   else if(g_zzStructBias <= 0 && breakPriceBear < refLow)
      candidateType = -1;  // bear BOS
   else if(g_zzStructBias <= 0 && breakPrice > refHigh)
      candidateType = 2;   // bull CHoCH
   
   if(candidateType != 0 && candidateType == g_zzBOSActiveType)
   {
      g_zzBOSConfirmCount++;
   }
   else if(candidateType != 0)
   {
      g_zzBOSActiveType = candidateType;
      g_zzBOSConfirmCount = 1;
   }
   else
   {
      g_zzBOSActiveType = 0;
      g_zzBOSConfirmCount = 0;
   }
   
   // Confirm when threshold reached for the active type
   if(g_zzBOSConfirmCount >= InpBOSConfirmCandles)
   {
      switch(g_zzBOSActiveType)
      {
         case  1: g_zzBullBOS = true;   break;
         case -1: g_zzBearBOS = true;   break;
         case  2: g_zzBullCHoCH = true; break;
         case -2: g_zzBearCHoCH = true; break;
      }
      g_zzBOSConfirmCount = 0;
      g_zzBOSActiveType = 0;
   }
}

//+------------------------------------------------------------------+
//| DetectLiquiditySweep — sweep of swing level + rejection            |
//+------------------------------------------------------------------+
void DetectLiquiditySweep(const double &h[], const double &l[], const double &c[],
                          const double &o[], int idx, double atr)
{
   g_zzBullSweep = false; g_zzBearSweep = false;
   g_zzHighConvBull = false; g_zzHighConvBear = false;
   if(!InpShowMktStruct || !InpShowSweeps) return;
   if(g_zzSwingHigh <= 0 || g_zzSwingLow <= 0 || atr <= 0) return;
   
   double minPen = atr * InpSweepMinPenATR;
   double displacement = atr * InpSweepDispATR;
   double barRange = h[idx] - l[idx];
   if(barRange <= 0) barRange = atr * 0.5;
   
   // ── Bearish Sweep: wick above swing high, close back below ─────────
   bool bearCooldownOK = (g_zzLastSweepBearBar == 0) || 
                         (idx - g_zzLastSweepBearBar > InpSweepCooldown)
                         || (g_zzSwingHigh != g_zzLastSweepBearLevel);
   // Penetration: high must pierce above swing high
   bool bearPenetration = h[idx] > g_zzSwingHigh + minPen;
   // Rejection: close must reclaim below swing high
   bool bearReclaim = !InpSweepBodyReclaim || c[idx] < g_zzSwingHigh;
   // Rejection fraction: how much did price reject
   double bearRejectFrac = (h[idx] - c[idx]) / barRange;
   
   if(bearPenetration && bearCooldownOK && !g_zzBearSweepPending)
   {
      g_zzBearSweepPending = true;
      g_zzSweepLevel = g_zzSwingHigh;
      g_zzSweepBar = idx;
   }
   
   // ── Bullish Sweep: wick below swing low, close back above ──────────
   bool bullCooldownOK = (g_zzLastSweepBullBar == 0) || 
                         (idx - g_zzLastSweepBullBar > InpSweepCooldown)
                         || (g_zzSwingLow != g_zzLastSweepBullLevel);
   bool bullPenetration = l[idx] < g_zzSwingLow - minPen;
   bool bullReclaim = !InpSweepBodyReclaim || c[idx] > g_zzSwingLow;
   double bullRejectFrac = (c[idx] - l[idx]) / barRange;
   
   if(bullPenetration && bullCooldownOK && !g_zzBullSweepPending)
   {
      g_zzBullSweepPending = true;
      g_zzSweepLevel = g_zzSwingLow;
      g_zzSweepBar = idx;
   }
   
   // ── Confirm bearish sweep ──────────────────────────────────────────
   if(g_zzBearSweepPending)
   {
      bool within = (idx - g_zzSweepBar <= InpSweepConfirmBars);
      bool disp = within && c[idx] < g_zzSweepLevel - displacement && c[idx] < o[idx];
      bool reacc = g_zzBearSweepPending && c[idx] > g_zzSweepLevel + displacement;
      if(disp && bearRejectFrac >= InpSweepThresh)
      {
         g_zzBearSweep = true;
         g_zzBearSweepPending = false;
         g_zzLastSweepBearBar = idx;
         g_zzLastSweepBearLevel = g_zzSwingHigh;
         if(g_faBear) g_zzHighConvBear = true;  // sweep + failed auction = high conviction
      }
      else if(!within || reacc) g_zzBearSweepPending = false;
   }
   
   // ── Confirm bullish sweep ──────────────────────────────────────────
   if(g_zzBullSweepPending)
   {
      bool within = (idx - g_zzSweepBar <= InpSweepConfirmBars);
      bool disp = within && c[idx] > g_zzSweepLevel + displacement && c[idx] > o[idx];
      bool reacc = g_zzBullSweepPending && c[idx] < g_zzSweepLevel - displacement;
      if(disp && bullRejectFrac >= InpSweepThresh)
      {
         g_zzBullSweep = true;
         g_zzBullSweepPending = false;
         g_zzLastSweepBullBar = idx;
         g_zzLastSweepBullLevel = g_zzSwingLow;
         if(g_faBull) g_zzHighConvBull = true;
      }
      else if(!within || reacc) g_zzBullSweepPending = false;
   }
}

//+------------------------------------------------------------------+
//| CalcStructureScore — composite 0-100 structure quality             |
//+------------------------------------------------------------------+
void CalcStructureScore(const double &h[], const double &l[], const double &c[],
                        int idx, double atr)
{
   g_zzScoreLong = 50.0; g_zzScoreShort = 50.0;
   if(!InpShowMktStruct || !InpShowStructScore) return;
   if(g_zzSwingHigh <= 0 || g_zzSwingLow <= 0 || atr <= 0) return;
   
   double range = g_zzSwingHigh - g_zzSwingLow;
   if(range <= 0) return;
   
   // Bias score (35 pts max)
   double biasLong = (g_zzStructBias >= 0) ? 35.0 : 5.0;
   double biasShort = (g_zzStructBias <= 0) ? 35.0 : 5.0;
   
   // Price location vs EQ (30 pts max)
   double eq = (g_zzSwingHigh + g_zzSwingLow) / 2.0;
   double posInRange = (c[idx] - g_zzSwingLow) / range;  // 0=at low, 1=at high
   double locLong = MathMax(0.0, 30.0 * (1.0 - posInRange));  // closer to support = better for longs
   double locShort = MathMax(0.0, 30.0 * posInRange);         // closer to resistance = better for shorts
   
   // Range quality vs ATR (30 pts max)
   double rangeInATR = range / atr;
   double rangeScore = MathMin(30.0, rangeInATR * 10.0);  // 3 ATR range = 30 pts
   
   // Trend continuation bonus (5 pts)
   double trendLong = (g_zzStructBias >= 0 && c[idx] > eq) ? 5.0 : 0;
   double trendShort = (g_zzStructBias <= 0 && c[idx] < eq) ? 5.0 : 0;
   
   g_zzScoreLong  = biasLong + locLong + rangeScore + trendLong;
   g_zzScoreShort = biasShort + locShort + rangeScore + trendShort;
   
   // Clamp
   g_zzScoreLong  = MathMax(0.0, MathMin(100.0, g_zzScoreLong));
   g_zzScoreShort = MathMax(0.0, MathMin(100.0, g_zzScoreShort));
}

//+------------------------------------------------------------------+
//| FindCurrentSessionStart — backward scan to actual session boundary |
//| (audit fix #2)                                                     |
//+------------------------------------------------------------------+
int FindCurrentSessionStart(const datetime &time[], int endBar)
{
   int start = endBar;
   while(start > 0)
   {
      if(IsNewSession(time[start], time[start - 1]))
         break;
      start--;
   }
   return MathMax(0, start);
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_vah,        INDICATOR_DATA);
   SetIndexBuffer(1, g_val,        INDICATOR_DATA);
   SetIndexBuffer(2, g_poc,        INDICATOR_DATA);
   SetIndexBuffer(3, g_devVah,     INDICATOR_DATA);
   SetIndexBuffer(4, g_devVal,     INDICATOR_DATA);
   SetIndexBuffer(5, g_fvgDisp,    INDICATOR_DATA);
   SetIndexBuffer(6, g_volProfile, INDICATOR_CALCULATIONS);
   
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
   for(int p = 0; p < 6; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "GT VP v7.42");
   g_fvgCount = 0;
   g_cloudTileCount = 0;
   
   // Clamp FVG/IFVG capacities to static arrays (audit fix #6)
   if(InpFVGMaxActive > MAX_FVG_TRACK)  InpFVGMaxActive = MAX_FVG_TRACK;
   if(InpIFVGMaxActive > MAX_IFVG_TRACK) InpIFVGMaxActive = MAX_IFVG_TRACK;
   
   int rows = InpVPNumRows;
   if(rows < 10) rows = 10;
   g_rows = rows;
   ArrayResize(g_volBins, rows);
   ArrayResize(g_buyBins, rows);
   ArrayResize(g_sellBins, rows);
   
   g_VAH = 0; g_VAL = 0; g_POC = 0;
   g_totalVol = 0; g_maxVol = 0;
   g_pocBin = 0; g_vahBin = 0; g_valBin = 0;
   g_profileShape = "Neutral";
   g_vpStart = 0; g_vpEnd = 0;
   g_sessionStartBar = 0;
   g_sessionStartTime = 0;
   g_sessionBarCount = 0;
   g_isNewSession = false;
   g_hasPriorVA = false;
   g_lastGhostPrice = 0;
   g_lastGhostBar = 0;
   g_lastGhostColor = clrGray;
   g_priorVAWidth = 0;
   g_vaState = "Neutral";
   g_cumulativeDelta = 0;
   g_sessionBuyVol = 0;
   g_sessionSellVol = 0;
   g_flowPressure = 0;
   g_faBull = false; g_faBear = false;
   g_faBullPending = false; g_faBearPending = false;
   g_faLastBullBar = 0; g_faLastBearBar = 0;
   g_absorptionSignal = false; g_icebergSignal = false;
   g_exhaustionSignal = false; g_exhaustionType = "None";
   g_bullishDiv = false; g_bearishDiv = false;
   g_prevDivHigh = 0; g_prevDivLow = 0;
   g_prevDivHighDelta = 0; g_prevDivLowDelta = 0;
   g_smdAccum = false; g_smdDist = false;
   g_deltaStrength = 0; g_rotationFactor = 0; g_vwad = 0;
   g_rotationUp = 0; g_rotationDown = 0; g_previousDevelopingPOC = 0; g_priorSessionPOC = 0;
   g_sessionCVDHigh = 0; g_sessionCVDLow = 0; g_normalizedCVD = 0;
   g_zzSwingHigh = 0; g_zzSwingLow = 0; g_zzPrevSwingHigh = 0; g_zzPrevSwingLow = 0;
   g_zzHighExtreme = 0; g_zzLowExtreme = DBL_MAX_VAL;
   g_zzStructBias = 0; g_zzBOSConfirmCount = 0; g_zzBOSActiveType = 0;
   g_zzScoreLong = 50.0; g_zzScoreShort = 50.0;
   for(int i = 0; i < MAX_CLOUD_TILES; i++) g_cloudTileNames[i] = "";
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r) { CleanupObjects(); }

//+------------------------------------------------------------------+
//| OnChartEvent — redraw histogram / cloud on zoom/scroll            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(g_rows < 1 || g_binSize <= 0 || g_vpHigh <= g_vpLow || g_POC <= 0) return;
      if(InpShowHistogram) DrawHistogram();
      if(InpShowVACloud)   DrawVACloud();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calc,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &v[], const int &sp[])
{
   if(rates_total < 15) return 0;  // bare minimum — session mode may need fewer bars
   int minRequired = (InpVPLookbackMode == VP_LB_FIXED_BARS) ? InpVPLookback + 15 : 30;
   if(rates_total < minRequired) return 0;
   
   // ── New-bar detection ────────────────────────────────────────────────
   static datetime lastBarTime = 0;
   bool isNewBar = (t[rates_total-1] != lastBarTime);
   if(isNewBar) lastBarTime = t[rates_total-1];
   bool forceFull = (prev_calc == 0);
   
   // ── Session boundary detection ──────────────────────────────────────
   datetime prevBarTime = (rates_total >= 2) ? t[rates_total-2] : 0;
   g_isNewSession = IsNewSession(t[rates_total-1], prevBarTime);  // forceFull no longer triggers session reset (audit fix #2)
   
   if(forceFull)
   {
      // On first load, scan backward for the actual session boundary
      // (audit fix #2: don't treat forceFull as a real session boundary)
      int closedBar = rates_total - 2;
      g_sessionStartBar = FindCurrentSessionStart(t, closedBar);
      g_sessionStartTime = t[g_sessionStartBar];
      g_sessionBarCount = closedBar - g_sessionStartBar;
   }
   
   if(g_isNewSession)
   {
      // Capture prior session VA before reset
      if(g_VAH > 0 && g_VAL > 0 && g_POC > 0)
      {
         g_priorVAH = g_VAH; g_priorVAL = g_VAL; g_priorSessionPOC = g_POC;
         g_hasPriorVA = true;
      }
      // Snapshot session bar count for cloud spawn calibration
      if(g_sessionStartBar > 0)
         g_prevSessionBars = MathMax(1, rates_total - 2 - g_sessionStartBar);
      // Reset session state — new session starts at the just-opened bar
      g_sessionStartBar = rates_total - 1;
      g_sessionStartTime = t[rates_total-1];
      g_sessionBarCount = 0;
      g_cumulativeDelta = 0; g_sessionBuyVol = 0; g_sessionSellVol = 0;
      g_flowPressure = 0;
      g_priorVAWidth = 0; g_vaState = "Neutral";
      g_vaExpansionCount = 0; g_vaContractionCount = 0;
      g_prevPriceInsideVA = true;
      g_lastGhostPrice = 0; g_lastGhostBar = 0;
      // Phase 2 signal resets
      g_faBull = false; g_faBear = false;
      g_faBullPending = false; g_faBearPending = false;
      g_faLastBullBar = 0; g_faLastBearBar = 0;
      g_absorptionSignal = false; g_icebergSignal = false;
      g_exhaustionSignal = false; g_exhaustionType = "None";
      g_bullishDiv = false; g_bearishDiv = false;
      g_prevDivHigh = 0; g_prevDivLow = 0;
      g_prevDivHighDelta = 0; g_prevDivLowDelta = 0;
      g_smdAccum = false; g_smdDist = false;
      g_deltaStrength = 0; g_rotationFactor = 0; g_vwad = 0;
      g_rotationUp = 0; g_rotationDown = 0; g_previousDevelopingPOC = 0;
      g_sessionCVDHigh = 0; g_sessionCVDLow = 0; g_normalizedCVD = 0;
      // Market Structure resets — full session-local reset
      g_zzSwingHigh = 0; g_zzSwingLow = 0;
      g_zzPrevSwingHigh = 0; g_zzPrevSwingLow = 0;
      g_zzSwingHighBar = 0; g_zzSwingLowBar = 0;
      g_zzPrevSwingHighBar = 0; g_zzPrevSwingLowBar = 0;
      g_zzHighExtreme = 0; g_zzLowExtreme = DBL_MAX_VAL;
      g_zzHighExtremeBar = 0; g_zzLowExtremeBar = 0;
      g_zzNewSwingHigh = false; g_zzNewSwingLow = false;
      g_msHH = false; g_msHL = false; g_msLH = false; g_msLL = false;
      g_zzStructBias = 0;
      g_zzBullBOS = false; g_zzBearBOS = false;
      g_zzBullCHoCH = false; g_zzBearCHoCH = false;
      g_zzBOSConfirmCount = 0;
      g_zzBOSActiveType = 0;
      g_zzBullSweep = false; g_zzBearSweep = false;
      g_zzBullSweepPending = false; g_zzBearSweepPending = false;
      g_zzHighConvBull = false; g_zzHighConvBear = false;
      ClearZZLines(); ClearSwingLevels(); ClearAllFVGs();
      ClearCloudTiles(); g_cloudSpawnBar = 0;
      ClearGhostTrails(); ClearPriorVA();
   }
   g_sessionBarCount = rates_total - 1 - g_sessionStartBar;
   
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   int minB = InpVPLookback + 10;
   if(start < minB) start = minB;
   
   // ── Bounded first-load backfill ───────────────────────────────────
   int fvgStart = start;
   if(forceFull)
   {
      int initialBackfill = MathMax(100, MathMin(20000, InpInitialBackfill));
      int backfillLimit = MathMax(14, rates_total - initialBackfill);
      if(start < backfillLimit) start = backfillLimit;
      fvgStart = MathMax(3, rates_total - MathMin(initialBackfill, 200));
   }
   
   // ── Reset VP line buffers for this pass ────────────────────────────
   for(int i = start; i < rates_total; i++)
   {
      g_vah[i] = EMPTY_VALUE; g_val[i] = EMPTY_VALUE; g_poc[i] = EMPTY_VALUE;
      g_devVah[i] = EMPTY_VALUE; g_devVal[i] = EMPTY_VALUE;
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // STATE BACKFILL — on first load, replay closed bars to rebuild market
   // structure state (audit fix #4)
   // ══════════════════════════════════════════════════════════════════════
   if(forceFull && InpShowMktStruct)
   {
      int replayStart = MathMax(g_sessionStartBar, rates_total - MathMax(100, MathMin(20000, InpInitialBackfill)));
      if(replayStart < g_sessionStartBar) replayStart = g_sessionStartBar;
      int replayEnd = rates_total - 3;  // stop before last closed bar (will be processed in main loop)
      if(replayEnd > replayStart)
      {
         double atrReplay = ATR(h, l, c, 14, replayStart + 14);
         for(int ri = replayStart + InpZZATRLen; ri <= replayEnd && !IsStopped(); ri++)
         {
            double atrR = ATR(h, l, c, 14, ri); if(atrR <= 0) atrR = atrReplay;
            atrReplay = atrR;
            UpdateZZSwingExtremes(h, l, ri, atrR);
            ClassifyStructure();
            DetectBOSCHOCH(h, l, c, o, ri, atrR);
            DetectLiquiditySweep(h, l, c, o, ri, atrR);
            CalcStructureScore(h, l, c, ri, atrR);
         }
         // Reset post-backfill: clear any pending state from the last replay bar
         g_zzBullBOS = false; g_zzBearBOS = false;
         g_zzBullCHoCH = false; g_zzBearCHoCH = false;
         g_zzBOSConfirmCount = 0; g_zzBOSActiveType = 0;
         g_zzBullSweep = false; g_zzBearSweep = false;
         g_zzBullSweepPending = false; g_zzBearSweepPending = false;
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // HEAVY WORK — on new-bar: uses closed bar (rates_total-2) for all signals
   // ══════════════════════════════════════════════════════════════════════
   if(isNewBar || forceFull)
   {
      int closedBar = rates_total - 2;  // audit fix #1 — never use live candle
      datetime now = t[closedBar];
      
      // ── FVG Aging (struct-based) ────────────────────────────────────
      AgeFVGs(now);
      
      // ── Volume Profile computation ───────────────────────────────────
      // Session mode reuses the session boundary tracker (g_sessionStartBar,
      // driven by IsNewSession()/InpSessionType) so the VP window always
      // represents "current Daily/Weekly/Monthly/Tokyo/London/NY session"
      // regardless of chart timeframe — no bar-count math, no per-TF scaling.
      int vpStart = (InpVPLookbackMode == VP_LB_SESSION)
                  ? MathMax(0, g_sessionStartBar)
                  : MathMax(0, rates_total - InpVPLookback);
      int vpEnd   = closedBar;  // audit fix #1
      g_vpStart = vpStart; g_vpEnd = vpEnd;
      
      double vpHigh = h[vpStart], vpLow = l[vpStart];
      for(int i = vpStart; i <= vpEnd; i++)
      {
         if(h[i] > vpHigh) vpHigh = h[i];
         if(l[i] < vpLow)  vpLow  = l[i];
      }
      double vpRange = vpHigh - vpLow;
      
      // Pre-compute ATR for dynamic binning
      double atrVal = ATR(h, l, c, 14, vpEnd);
      if(atrVal <= 0) atrVal = vpRange * 0.02;
      int tfMinutes = MathMax(1, PeriodSeconds() / 60);
      
      if(vpRange <= 0) { /* retain old VP globals */ }
      else
      {
         // ── Dynamic bin count ────────────────────────────────────────
         int rows = CalcDynamicRows(vpRange, atrVal, tfMinutes);
         if(rows != g_rows)
         {
            g_rows = rows;
            ArrayResize(g_volBins, rows);
            ArrayResize(g_buyBins, rows);
            ArrayResize(g_sellBins, rows);
         }
         
         g_vpLow = vpLow; g_vpHigh = vpHigh;
         double binSize = vpRange / rows;
         g_binSize = binSize;
         
         // Build volume + buy/sell histogram
         ArrayInitialize(g_volBins, 0);
         ArrayInitialize(g_buyBins, 0);
         ArrayInitialize(g_sellBins, 0);
         
         for(int i = vpStart; i <= vpEnd; i++)
         {
            double midPrice = (h[i] + l[i] + c[i]) / 3.0;
            int bin = (int)((midPrice - vpLow) / binSize);
            if(bin < 0) bin = 0; if(bin >= rows) bin = rows - 1;
            double vol = (double)tv[i];
            g_volBins[bin] += vol;
            if(c[i] > o[i])       g_buyBins[bin]  += vol;
            else if(c[i] < o[i])  g_sellBins[bin] += vol;
            else                  { g_buyBins[bin] += vol*0.5; g_sellBins[bin] += vol*0.5; }
         }
         
         // POC
         double maxVol = 0; int pocBin = 0;
         for(int b = 0; b < rows; b++)
            if(g_volBins[b] > maxVol) { maxVol = g_volBins[b]; pocBin = b; }
         g_maxVol = maxVol; g_pocBin = pocBin;
         
         // Value Area
         double totalVol = 0;
         for(int b = 0; b < rows; b++) totalVol += g_volBins[b];
         g_totalVol = totalVol;
         double targetVol = totalVol * InpVA_Pct / 100.0;
         if(targetVol <= 0) targetVol = 1;
         
         int vahBin = pocBin, valBin = pocBin;
         double vaVol = g_volBins[pocBin];
         while(vaVol < targetVol && (vahBin < rows - 1 || valBin > 0))
         {
            double volAbove = (vahBin < rows - 1) ? g_volBins[vahBin + 1] : -1;
            double volBelow = (valBin > 0) ? g_volBins[valBin - 1] : -1;
            if(volAbove >= volBelow) { vahBin++; vaVol += g_volBins[vahBin]; }
            else                    { valBin--; vaVol += g_volBins[valBin]; }
         }
         g_vahBin = vahBin; g_valBin = valBin;
         
         g_VAH = vpLow + (vahBin + 1) * binSize;
         g_VAL = vpLow + valBin * binSize;
         g_POC = vpLow + (pocBin + 0.5) * binSize;
         
         // ── Profile shape analysis ────────────────────────────────────
         g_profileShape = "Neutral";
         double volAbovePOC = 0, volBelowPOC = 0;
         for(int b = pocBin + 1; b < rows; b++) volAbovePOC += g_volBins[b];
         for(int b = 0; b < pocBin; b++)         volBelowPOC += g_volBins[b];
         if(volBelowPOC > 0 && volAbovePOC > 0)
         {
            double ratio = volBelowPOC / volAbovePOC;
            if(ratio > 1.5)       g_profileShape = "P-Shape (Bull)";
            else if(ratio < 0.67) g_profileShape = "b-Shape (Bear)";
            else if(maxVol > 0 && totalVol > 0)
            {
               double top10 = 0, bot10 = 0;
               int n10 = MathMax(1, rows / 10);
               for(int b = 0; b < n10; b++)          bot10 += g_volBins[b];
               for(int b = rows - n10; b < rows; b++) top10 += g_volBins[b];
               if((top10 + bot10) / totalVol > 0.55) g_profileShape = "D-Shape (Bal)";
            }
         }
         
         // ── VA Breathing ──────────────────────────────────────────────
         double currentVAWidth = g_VAH - g_VAL;
         if(g_priorVAWidth > 0 && currentVAWidth > 0)
         {
            double ratioW = currentVAWidth / g_priorVAWidth;
            if(ratioW > InpVAExpansion)       { g_vaState = "Expanding"; g_vaExpansionCount++; }
            else if(ratioW < InpVAContraction) { g_vaState = "Contracting"; g_vaContractionCount++; }
            else                               g_vaState = "Stable";
         }
         g_priorVAWidth = currentVAWidth;
         
         // ── CVD / Flow Pressure ───────────────────────────────────────
         double sessionBuy = 0, sessionSell = 0;
         for(int i = g_sessionStartBar; i <= vpEnd; i++)
         {
            double vv = (double)tv[i];
            if(c[i] > o[i])       sessionBuy  += vv;
            else if(c[i] < o[i])  sessionSell += vv;
            else                  { sessionBuy += vv*0.5; sessionSell += vv*0.5; }
         }
         g_sessionBuyVol = sessionBuy; g_sessionSellVol = sessionSell;
         g_cumulativeDelta = sessionBuy - sessionSell;
         g_flowPressure = (sessionBuy + sessionSell > 0) ? 
                          (sessionBuy - sessionSell) / (sessionBuy + sessionSell) * 100.0 : 0;
         
         // ── Session CVD bounds ────────────────────────────────────
         if(g_cumulativeDelta > g_sessionCVDHigh) g_sessionCVDHigh = g_cumulativeDelta;
         if(g_cumulativeDelta < g_sessionCVDLow)  g_sessionCVDLow  = g_cumulativeDelta;
         double cvdRange = g_sessionCVDHigh - g_sessionCVDLow;
         g_normalizedCVD = (cvdRange > 0) ? (g_cumulativeDelta - g_sessionCVDLow) / cvdRange * 100.0 : 50.0;
      }
      
      // ── Order Flow Signal Detection ─────────────────────────────────
      int lookbackIdx = closedBar;  // audit fix #1
      double avgVol20 = 0;
      for(int i = MathMax(0, lookbackIdx - 19); i <= lookbackIdx; i++)
         avgVol20 += (double)tv[i];
      avgVol20 /= 20.0;
      
      // Failed Auction
      if(InpShowFailedAuction)
         DetectFailedAuction(h, l, c, o, lookbackIdx, atrVal, InpFALookback);
      
      // Absorption
      if(InpShowAbsorption)
         DetectAbsorption((double)tv[lookbackIdx], h[lookbackIdx] - l[lookbackIdx], atrVal, c[lookbackIdx], avgVol20);
      
      // Iceberg
      if(InpShowIceberg)
         DetectIceberg(c[lookbackIdx], atrVal);
      
      // Exhaustion
      if(InpShowExhaustion && lookbackIdx >= 4)
      {
         double cvd4 = 0; int cvd4Idx = MathMax(g_sessionStartBar, lookbackIdx - 4);
         for(int i = g_sessionStartBar; i <= cvd4Idx; i++)
         {
            double vv = (double)tv[i];
            if(c[i] > o[i])       cvd4 += vv;
            else if(c[i] < o[i])  cvd4 -= vv;
         }
         DetectExhaustion(c[lookbackIdx], c[lookbackIdx - 4], g_cumulativeDelta, cvd4);
      }
      
      // Divergence
      if(InpShowDivergence)
         DetectDivergence(h, l, lookbackIdx);
      
      // Smart Money Divergence
      if(InpShowSMD)
         DetectSMD(c, lookbackIdx, InpSMDLookback, atrVal);
      
      // Delta Strength
      if(InpShowDeltaStrength)
         CalcDeltaStrength(lookbackIdx, InpDeltaStrLen);
      
      // Rotation Factor
      if(InpShowRotation)
         CalcRotationFactor();
      
      // VWAD
      if(g_sessionBuyVol + g_sessionSellVol > 0)
         g_vwad = (g_sessionBuyVol - g_sessionSellVol) / (g_sessionBuyVol + g_sessionSellVol) * g_totalVol;
      
      // ── Market Structure Detection ──────────────────────────────────
      if(InpShowMktStruct)
      {
         UpdateZZSwingExtremes(h, l, lookbackIdx, atrVal);
         ClassifyStructure();
         DetectBOSCHOCH(h, l, c, o, lookbackIdx, atrVal);
         DetectLiquiditySweep(h, l, c, o, lookbackIdx, atrVal);
         CalcStructureScore(h, l, c, lookbackIdx, atrVal);
      }
      
      // ── FVG/IFVG Mitigation & Invalidation ──────────────────────────
      if(InpShowFVG || InpShowIFVG)
      {
         ScanFVGMitigation(c[lookbackIdx], t[lookbackIdx]);
         ScanIFVGInvalidation(c[lookbackIdx], t[lookbackIdx]);
      }
      
      // ── Ghost trails ─────────────────────────────────────────────────
      if(InpShowGhost && g_POC > 0)
      {
         double ghostThreshold = atrVal * InpGhostATRFilt;
         if(tfMinutes <= 5)       ghostThreshold *= 0.3;
         else if(tfMinutes <= 15) ghostThreshold *= 0.5;
         else if(tfMinutes <= 60) ghostThreshold *= 0.7;
         
         if(g_lastGhostPrice == 0)
            { g_lastGhostPrice = g_POC; g_lastGhostBar = vpEnd; }
         else if(MathAbs(g_POC - g_lastGhostPrice) >= ghostThreshold)
         {
            DrawGhostSegment(g_lastGhostBar, g_lastGhostPrice, vpEnd, g_POC);
            g_lastGhostPrice = g_POC; g_lastGhostBar = vpEnd;
         }
      }
      
      // ── VA Cloud tiles ───────────────────────────────────────────────
      if(InpShowVACloud && g_VAH > 0 && g_VAL > 0)
         SpawnCloudTile(t, rates_total);
      
      // ── Render ───────────────────────────────────────────────────────
      if(InpShowHistogram) DrawHistogram();
      if(InpShowLVN && g_maxVol > 0) DrawLVN();
      
      if(InpFillVA)
      {
         string vaName = g_prefix + "VA_FILL";
         datetime vaLeft = t[MathMax(vpStart, g_sessionStartBar)];  // tight: current session only, not full lookback
         if(ObjectFind(0, vaName) < 0)
         {
            ObjectCreate(0, vaName, OBJ_RECTANGLE, 0, vaLeft, g_VAH, t[vpEnd], g_VAL);
            ObjectSetInteger(0, vaName, OBJPROP_COLOR, C'0x00,0x40,0xFF');
            ObjectSetInteger(0, vaName, OBJPROP_FILL, false);   // outline only — no MQL5 alpha, so fill=false is the "opacity" substitute
            ObjectSetInteger(0, vaName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, vaName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, vaName, OBJPROP_BACK, true);
            ObjectSetInteger(0, vaName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, vaName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, vaName, OBJPROP_ZORDER, 2);
         }
         else
         {
            ObjectSetInteger(0, vaName, OBJPROP_TIME,  0, vaLeft);
            ObjectSetDouble(0,  vaName, OBJPROP_PRICE, 0, g_VAH);
            ObjectSetInteger(0, vaName, OBJPROP_TIME,  1, t[vpEnd]);
            ObjectSetDouble(0,  vaName, OBJPROP_PRICE, 1, g_VAL);
         }
      }
      
      if(InpShowSessionBox && g_sessionStartBar > 0)
         DrawSessionBox(t, g_sessionStartBar, vpEnd);
      
      if(InpShowPriorVA && g_hasPriorVA)
         DrawPriorVA(t, vpStart, vpEnd);
      
      // ── Visual Overlays ──────────────────────────────────────────────
      if(InpShowImbalances) DrawStackedImbalances(t, vpEnd);
      if(InpShowFastLanes)  DrawFastLanes(t, vpEnd);
      
      if(InpShowDash) DrawDashboard(t, c, rates_total);
      
      // ── Signal Labels ────────────────────────────────────────────────
      int labelBar = closedBar;  // audit fix #1
      double labelOffset = (g_VAH - g_VAL) * 0.05;
      if(labelOffset <= 0) labelOffset = atrVal * 0.3;
      
      if(g_faBear)
         DrawSignalLabel("FA_BEAR_" + IntegerToString(labelBar), t[labelBar], h[labelBar] + labelOffset,
                         "◄ FAIL AUCTION ▼", C'0xF2,0x36,0x45');
      if(g_faBull)
         DrawSignalLabel("FA_BULL_" + IntegerToString(labelBar), t[labelBar], l[labelBar] - labelOffset,
                         "▲ FAIL AUCTION ►", C'0x08,0x99,0x81');
      if(g_absorptionSignal)
         DrawSignalLabel("ABS_" + IntegerToString(labelBar), t[labelBar], h[labelBar] + labelOffset * 1.5,
                         "ABSORB", clrYellow);
      if(g_icebergSignal)
         DrawSignalLabel("ICE_" + IntegerToString(labelBar), t[labelBar], h[labelBar] + labelOffset * 2.0,
                         "ICEBERG", C'0xCE,0x93,0xD8');
      if(g_exhaustionSignal)
         DrawSignalLabel("EXH_" + IntegerToString(labelBar), t[labelBar], 
                         g_exhaustionType == "Buying Exhaustion" ? l[labelBar] - labelOffset : h[labelBar] + labelOffset,
                         g_exhaustionType == "Buying Exhaustion" ? "▲ BUY EXH" : "▼ SELL EXH", clrOrange);
      if(g_bearishDiv)
         DrawSignalLabel("DIV_BEAR_" + IntegerToString(labelBar), t[labelBar], h[labelBar] + labelOffset * 2.5,
                         "▼ BEAR DIV", clrRed);
      if(g_bullishDiv)
         DrawSignalLabel("DIV_BULL_" + IntegerToString(labelBar), t[labelBar], l[labelBar] - labelOffset * 1.5,
                         "▲ BULL DIV", clrLime);
      if(g_smdDist)
         DrawSignalLabel("SMD_DIST_" + IntegerToString(labelBar), t[labelBar], h[labelBar] + labelOffset * 3.0,
                         "DIST", clrOrange);
      if(g_smdAccum)
         DrawSignalLabel("SMD_ACCUM_" + IntegerToString(labelBar), t[labelBar], l[labelBar] - labelOffset * 2.0,
                         "ACCUM", clrAqua);
      
      // Prune old signal labels (keep last 30)
      PruneSignalLabels(30);
      
      // ── Market Structure Labels ──────────────────────────────────────
      if(InpShowMktStruct && g_zzNewSwingHigh && InpShowHHLL)
      {
         string labelType = g_msHH ? "HH" : g_msLH ? "LH" : "HI";
         color labelClr = g_msHH ? C'0x00,0xE6,0x76' : C'0xFF,0x91,0x00';
         DrawSignalLabel("MS_H_" + IntegerToString(labelBar), t[labelBar], 
                         h[labelBar] + labelOffset * 4.0, labelType, labelClr);
      }
      if(InpShowMktStruct && g_zzNewSwingLow && InpShowHHLL)
      {
         string labelType = g_msHL ? "HL" : g_msLL ? "LL" : "LO";
         color labelClr = g_msHL ? C'0x00,0xC8,0x53' : C'0xFF,0x17,0x44';
         DrawSignalLabel("MS_L_" + IntegerToString(labelBar), t[labelBar],
                         l[labelBar] - labelOffset * 2.5, labelType, labelClr);
      }
      if(InpShowMktStruct && g_zzBullBOS && InpShowBOSCHOCH)
         DrawSignalLabel("BOS_BULL_" + IntegerToString(labelBar), t[labelBar],
                         h[labelBar] + labelOffset * 3.5, "BOS ▲", C'0x00,0xE5,0xFF');
      if(InpShowMktStruct && g_zzBearBOS && InpShowBOSCHOCH)
         DrawSignalLabel("BOS_BEAR_" + IntegerToString(labelBar), t[labelBar],
                         l[labelBar] - labelOffset * 3.0, "▼ BOS", C'0xFF,0x98,0x00');
      if(InpShowMktStruct && g_zzBullCHoCH && InpShowBOSCHOCH)
         DrawSignalLabel("CHoCH_BULL_" + IntegerToString(labelBar), t[labelBar],
                         l[labelBar] - labelOffset * 3.5, "CHoCH ▲", C'0xEA,0x00,0xFF');
      if(InpShowMktStruct && g_zzBearCHoCH && InpShowBOSCHOCH)
         DrawSignalLabel("CHoCH_BEAR_" + IntegerToString(labelBar), t[labelBar],
                         h[labelBar] + labelOffset * 4.5, "▼ CHoCH", C'0xEA,0x00,0xFF');
      if(InpShowMktStruct && g_zzBullSweep && InpShowSweeps)
         DrawSignalLabel("SWEEP_BULL_" + IntegerToString(labelBar), t[labelBar],
                         l[labelBar] - labelOffset * 4.0, g_zzHighConvBull ? "🎯 SWEEP+FA ▲" : "🎯 ZZ SWEEP ▲", clrLime);
      if(InpShowMktStruct && g_zzBearSweep && InpShowSweeps)
         DrawSignalLabel("SWEEP_BEAR_" + IntegerToString(labelBar), t[labelBar],
                         h[labelBar] + labelOffset * 5.0, g_zzHighConvBear ? "🎯 SWEEP+FA ▼" : "🎯 ZZ SWEEP ▼", clrRed);
      
      // ── Swing Level Lines ─────────────────────────────────────────────
      if(InpShowMktStruct && InpShowSwingLevels && g_zzSwingHigh > 0 && g_zzSwingLow > 0)
         DrawSwingLevels(t, lookbackIdx);
      
      // ── ZigZag Connecting Lines ───────────────────────────────────────
      if(InpShowMktStruct && InpShowZZLines && (g_zzNewSwingHigh || g_zzNewSwingLow))
         DrawZZLine(t, lookbackIdx);
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // PER-TICK WORK — cheap, runs every tick
   // ══════════════════════════════════════════════════════════════════════
   double atr14 = ATR(h, l, c, 14, rates_total-1);
   int vpStart = g_vpStart, vpEnd = g_vpEnd;
   
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      if(i >= vpStart && i <= vpEnd)
         { g_vah[i] = g_VAH; g_val[i] = g_VAL; g_poc[i] = g_POC; }
      
      // ── Developing VP (bounded to the same backfill window as start) ──
      if(InpShowDevVP)
      {
         double vwapSum = 0, volSum = 0;
         int dwStart = MathMax(0, i - InpDevVPLen);
         for(int j = dwStart; j <= i && j < rates_total; j++)
         {
            double tp = (h[j] + l[j] + c[j]) / 3.0;
            double vv = (double)tv[j]; if(vv <= 0) vv = 1;
            vwapSum += tp * vv; volSum += vv;
         }
         double vwap = (volSum > 0) ? vwapSum / volSum : c[i];
         double atrI = ATR(h, l, c, 14, i); if(atrI <= 0) atrI = atr14;
         g_devVah[i] = vwap + atrI; g_devVal[i] = vwap - atrI;
      }
      
      // FVG Detection (ATR-filtered, only on new bar close — not per-tick) — only scan from fvgStart on first load
      if(InpShowFVG && (isNewBar || forceFull) && i >= MathMax(3, fvgStart))
      {
         double atrI = ATR(h, l, c, 14, i); if(atrI <= 0) atrI = atr14;
         double fvgMinSize = atrI * InpFVGMinSizeATR;
         // Let DrawFVG()'s own oldest-eviction run on every candidate so the
         // most RECENT gaps are the ones retained once InpFVGMaxActive is hit.
         if(l[i] > h[i-2] && (l[i] - h[i-2]) >= fvgMinSize)
            DrawFVG("FVG_B_" + IntegerToString(i), t[i], l[i],
                    t[i]+PeriodSeconds()*InpFVGMaxAge, h[i-2], C'0x08,0x99,0x81', 1);
         if(h[i] < l[i-2] && (l[i-2] - h[i]) >= fvgMinSize)
            DrawFVG("FVG_S_" + IntegerToString(i), t[i], h[i],
                    t[i]+PeriodSeconds()*InpFVGMaxAge, l[i-2], C'0xF2,0x36,0x45', -1);
      }
      
      if(InpVAReclaimBorder && g_VAH > 0 && g_VAL > 0)
         g_prevPriceInsideVA = (c[i] >= g_VAL && c[i] <= g_VAH);
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| DrawHistogram — redraws HIST_* objects from g_volBins[] globals   |
//+------------------------------------------------------------------+
void DrawHistogram()
{
   // Validity guard: VP must have been built
   if(g_rows < 1 || ArraySize(g_volBins) < g_rows || g_binSize <= 0 || g_vpHigh <= g_vpLow || g_POC <= 0) return;
   
   // Note: still enumerates all chart objects (ObjectsTotal is chart-wide),
   // but only deletes ones matching this indicator's own prefix.
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "HIST_") == 0) ObjectDelete(0, nm);
   }
   
   int rows = g_rows;
   double maxVol = g_maxVol;
   double binSize = g_binSize;
   double vpLow = g_vpLow;
   int pocBin = g_pocBin;
   
   // Compute display width
   int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(visibleBars < 50) visibleBars = 100;
   double barWidthSec = PeriodSeconds();
   double histWidthSec = visibleBars * barWidthSec * InpVPWidthPct / 100.0;
   datetime tEnd = iTime(_Symbol, _Period, g_vpEnd);
   if(tEnd == 0) return;
   datetime histRight = tEnd + (int)(barWidthSec * 2);
   datetime histLeft  = histRight - (int)histWidthSec;
   
   for(int b = 0; b < rows; b++)
   {
      double binVol  = g_volBins[b];
      double binFrac = (maxVol > 0) ? binVol / maxVol : 0;
      double binPriceLow  = vpLow + b * binSize;
      double binPriceHigh = binPriceLow + binSize;
      
      color binColor;
      if(InpHeatmap)
      {
         if(binFrac < 0.1)
            binColor = C'0x1A,0x1A,0x3A';
         else if(binFrac < 0.25)
            binColor = C'0x15,0x36,0x8C';
         else if(binFrac < 0.45)
            binColor = C'0x00,0x96,0x88';
         else if(binFrac < 0.65)
            binColor = C'0x4C,0xAF,0x50';
         else if(binFrac < 0.80)
            binColor = C'0xFF,0x98,0x00';
         else if(binFrac < 0.95)
            binColor = C'0xF4,0x43,0x36';
         else
            binColor = C'0xFF,0xEB,0x3B';
      }
      else
      {
         binColor = (b == pocBin) ? clrYellow :
                    (b < pocBin)  ? C'0x21,0x96,0xF3' : C'0xF4,0x43,0x36';
      }
      
      double wFrac = MathMax(0.03, binFrac);
      datetime boxRight = histLeft + (int)(histWidthSec * wFrac);
      
      string histName = g_prefix + "HIST_" + IntegerToString(b);
      ObjectCreate(0, histName, OBJ_RECTANGLE, 0, histLeft, binPriceHigh, boxRight, binPriceLow);
      ObjectSetInteger(0, histName, OBJPROP_COLOR, binColor);
      ObjectSetInteger(0, histName, OBJPROP_FILL, true);
      ObjectSetInteger(0, histName, OBJPROP_BACK, true);
      ObjectSetInteger(0, histName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, histName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, histName, OBJPROP_WIDTH, 0);
      ObjectSetInteger(0, histName, OBJPROP_ZORDER, 1);
   }
   
   // POC highlight line
   string pocLine = g_prefix + "HIST_POC";
   ObjectCreate(0, pocLine, OBJ_TREND, 0, histLeft, g_POC, histRight, g_POC);
   ObjectSetInteger(0, pocLine, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, pocLine, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, pocLine, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, pocLine, OBJPROP_BACK, false);
   ObjectSetInteger(0, pocLine, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, pocLine, OBJPROP_HIDDEN, true);
   
   // VAH/VAL highlight lines on histogram
   for(int side = 0; side < 2; side++)
   {
      double pr = (side == 0) ? g_VAH : g_VAL;
      string ln = g_prefix + "HIST_VA" + IntegerToString(side);
      ObjectCreate(0, ln, OBJ_TREND, 0, histLeft, pr, histRight, pr);
      ObjectSetInteger(0, ln, OBJPROP_COLOR, (side == 0) ? C'0xF2,0x36,0x45' : C'0x08,0x99,0x81');
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ln, OBJPROP_BACK, false);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| DrawLVN — redraws LVN_* markers from g_volBins[] globals          |
//+------------------------------------------------------------------+
void DrawLVN()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "LVN_") == 0) ObjectDelete(0, nm);
   }
   
   double lvnThresh = g_maxVol * InpLVNThreshold;
   int rows = g_rows;
   double binSize = g_binSize;
   double vpLow = g_vpLow;
   
   for(int b = 0; b < rows; b++)
   {
      if(g_volBins[b] <= lvnThresh && g_volBins[b] > 0)
      {
         double lvnPrice = vpLow + (b + 0.5) * binSize;
         string lvnName = g_prefix + "LVN_" + IntegerToString(b);
         ObjectCreate(0, lvnName, OBJ_HLINE, 0, 0, lvnPrice);
         ObjectSetInteger(0, lvnName, OBJPROP_COLOR, C'0x80,0x00,0xEE');
         ObjectSetInteger(0, lvnName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, lvnName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lvnName, OBJPROP_BACK, true);
         ObjectSetInteger(0, lvnName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lvnName, OBJPROP_HIDDEN, true);
      }
   }
}

//+------------------------------------------------------------------+
//| DrawDashboard                                                     |
//+------------------------------------------------------------------+
void DrawDashboard(const datetime &t[], const double &c[], int rates_total)
{
   int idx = rates_total - 1;
   double vaRange = g_VAH - g_VAL;
   double pricePos = (vaRange > 0) ? (c[idx] - g_VAL) / vaRange * 100 : 50;
   string posText = pricePos > 100 ? "ABOVE VA" : pricePos < 0 ? "BELOW VA" : "IN VA";
   color posClr = pricePos > 70 ? clrLime : pricePos < 30 ? clrRed : clrYellow;
   
   double volInVA = 0;
   for(int b = g_valBin; b <= g_vahBin && b < g_rows; b++) volInVA += g_volBins[b];
   double vaConcentration = (g_totalVol > 0) ? volInVA / g_totalVol * 100 : 100;
   
   int x = 10, y = 20, gap = 15, cw = 135;
   int row = 0;
   
   DR(g_prefix+"d_", row++, "═══ GT VP v7.4 ═══", "", clrYellow, x, y, gap, cw);
   DR(g_prefix+"d_", row++, "Session", SessionName() + " (" + IntegerToString(g_sessionBarCount) + "b)", 
      C'0xFF,0x99,0x00', x, y, gap, cw);
   DR(g_prefix+"d_", row++, "VAH",   DoubleToString(g_VAH, _Digits),       clrRed,    x, y, gap, cw);
   DR(g_prefix+"d_", row++, "POC",   DoubleToString(g_POC, _Digits),       clrYellow, x, y, gap, cw);
   DR(g_prefix+"d_", row++, "VAL",   DoubleToString(g_VAL, _Digits),       clrGreen,  x, y, gap, cw);
   DR(g_prefix+"d_", row++, "VA Δ",  DoubleToString(vaRange, _Digits),     clrWhite,  x, y, gap, cw);
   DR(g_prefix+"d_", row++, "VA Vol",DoubleToString(vaConcentration,0)+"%",C'0xAA,0xAA,0xAA',x,y,gap,cw);
   DR(g_prefix+"d_", row++, "Pos",   posText+" "+IntegerToString((int)pricePos)+"%",posClr, x, y, gap, cw);
   DR(g_prefix+"d_", row++, "Shape", g_profileShape,                       C'0xCE,0x93,0xD8', x, y, gap, cw);
   
   if(InpShowVAMetrics)
   {
      color vaStateClr = (g_vaState == "Expanding")  ? clrOrange :
                         (g_vaState == "Contracting") ? clrAqua :
                         (g_vaState == "Stable")      ? C'0x8C,0xA0,0xC8' : C'0xB4,0x8C,0x3C';
      DR(g_prefix+"d_", row++, "VA State", g_vaState, vaStateClr, x, y, gap, cw);
   }
   
   string flowDir = g_flowPressure > 10 ? "▲ BULL" : g_flowPressure < -10 ? "▼ BEAR" : "◆ NEUT";
   color flowClr = g_flowPressure > 10 ? clrLime : g_flowPressure < -10 ? clrRed : clrGray;
   DR(g_prefix+"d_", row++, "Flow", flowDir + " " + DoubleToString(g_flowPressure,1) + "%", flowClr, x, y, gap, cw);
   
   color cvdClr = g_cumulativeDelta > 0 ? clrLime : g_cumulativeDelta < 0 ? clrRed : clrGray;
   DR(g_prefix+"d_", row++, "CVD", DoubleToString(g_cumulativeDelta,0), cvdClr, x, y, gap, cw);
   
   DR(g_prefix+"d_", row++, "Total Vol", DoubleToString(g_totalVol,0), C'0x78,0x90,0x9C', x, y, gap, cw);
   
   // ── Signal Status ──────────────────────────────────────────────────
   if(g_faBull || g_faBear || g_absorptionSignal || g_icebergSignal || 
      g_exhaustionSignal || g_bullishDiv || g_bearishDiv || g_smdAccum || g_smdDist)
   {
      DR(g_prefix+"d_", row++, "-- SIGNALS --", "", C'0xAA,0xAA,0xAA', x, y, gap, cw);
      if(g_faBull)       DR(g_prefix+"d_", row++, "FA",    "▲ BULL FAIL",   clrLime,   x, y, gap, cw);
      if(g_faBear)       DR(g_prefix+"d_", row++, "FA",    "▼ BEAR FAIL",   clrRed,    x, y, gap, cw);
      if(g_absorptionSignal) DR(g_prefix+"d_", row++, "ABSORB","DETECTED",   clrYellow, x, y, gap, cw);
      if(g_icebergSignal)DR(g_prefix+"d_", row++, "ICEBERG","DETECTED",      C'0xCE,0x93,0xD8', x, y, gap, cw);
      if(g_exhaustionSignal) DR(g_prefix+"d_", row++, "EXH",  g_exhaustionType, clrOrange, x, y, gap, cw);
      if(g_bearishDiv)  DR(g_prefix+"d_", row++, "DIV",   "▼ BEAR",        clrRed,    x, y, gap, cw);
      if(g_bullishDiv)  DR(g_prefix+"d_", row++, "DIV",   "▲ BULL",        clrLime,   x, y, gap, cw);
      if(g_smdDist)     DR(g_prefix+"d_", row++, "SMD",   "DISTRIBUTION",  clrOrange, x, y, gap, cw);
      if(g_smdAccum)    DR(g_prefix+"d_", row++, "SMD",   "ACCUMULATION",  clrAqua,   x, y, gap, cw);
   }
   
   if(InpShowDeltaStrength)
      DR(g_prefix+"d_", row++, "Δ Strength", DoubleToString(g_deltaStrength,1), 
         g_deltaStrength > 20 ? clrLime : g_deltaStrength < -20 ? clrRed : clrGray, x, y, gap, cw);
   
   if(InpShowRotation)
      DR(g_prefix+"d_", row++, "Rotation", DoubleToString(g_rotationFactor,2),
         g_rotationFactor > 0 ? clrLime : g_rotationFactor < 0 ? clrRed : clrGray, x, y, gap, cw);
   
   // ── Market Structure ───────────────────────────────────────────────
   if(InpShowMktStruct)
   {
      string biasText = g_zzStructBias > 0 ? "▲ BULL" : g_zzStructBias < 0 ? "▼ BEAR" : "◆ NEUT";
      color biasClr = g_zzStructBias > 0 ? clrLime : g_zzStructBias < 0 ? clrRed : clrGray;
      DR(g_prefix+"d_", row++, "ZZ Bias", biasText, biasClr, x, y, gap, cw);
      
      if(InpShowStructScore)
      {
         string scoreText = "L:" + IntegerToString((int)g_zzScoreLong) + " S:" + IntegerToString((int)g_zzScoreShort);
         DR(g_prefix+"d_", row++, "Score", scoreText, C'0xAA,0xAA,0xAA', x, y, gap, cw);
      }
      
      if(g_zzSwingHigh > 0)
         DR(g_prefix+"d_", row++, "Swing Hi", DoubleToString(g_zzSwingHigh, _Digits), C'0xFF,0x52,0x52', x, y, gap, cw);
      if(g_zzSwingLow > 0)
         DR(g_prefix+"d_", row++, "Swing Lo", DoubleToString(g_zzSwingLow, _Digits), C'0x4C,0xAF,0x50', x, y, gap, cw);
   }
   
   if(InpShowPriorVA && g_hasPriorVA)
   {
      DR(g_prefix+"d_", row++, "Prior VAH", DoubleToString(g_priorVAH, _Digits), C'0xF2,0x36,0x45', x, y, gap, cw);
      DR(g_prefix+"d_", row++, "Prior VAL", DoubleToString(g_priorVAL, _Digits), C'0x08,0x99,0x81', x, y, gap, cw);
   }
   
   DR(g_prefix+"d_", row++, "Bins/Rows", IntegerToString(g_rows), C'0xFF,0x98,0x00', x, y, gap, cw);
   DR(g_prefix+"d_", row++, "Bin Size",  DoubleToString(g_binSize, _Digits), C'0xAA,0xAA,0xAA', x, y, gap, cw);
   
   // ── Object Counts / Performance ────────────────────────────────────
   if(InpShowPerf)
   {
      int fvgActive = 0, ifvgActive = 0;
      for(int i = 0; i < g_fvgListCount; i++) if(g_fvgList[i].active) fvgActive++;
      for(int i = 0; i < g_ifvgListCount; i++) if(g_ifvgList[i].active) ifvgActive++;
      
      int totalObjects = ObjectsTotal(0);
      string perfText = "FVG:" + IntegerToString(fvgActive) + "/" + IntegerToString(InpFVGMaxActive)
                     + " IFVG:" + IntegerToString(ifvgActive)
                     + " Obj:" + IntegerToString(totalObjects);
      DR(g_prefix+"d_", row++, "Perf", perfText, 
         totalObjects > (int)InpEmergencyCleanup * 5 ? clrRed : C'0x78,0x90,0x9C', x, y, gap, cw);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DrawGhostSegment — single POC migration stepline segment          |
//+------------------------------------------------------------------+
void DrawGhostSegment(int barFrom, double priceFrom, int barTo, double priceTo)
{
   datetime tFrom = iTime(_Symbol, _Period, barFrom);
   datetime tTo   = iTime(_Symbol, _Period, barTo);
   if(tFrom == 0 || tTo == 0) return;
   
   color segColor;
   if(InpColoredGhost)
   {
      if(priceTo > priceFrom)       segColor = C'0x4C,0xAF,0x50';
      else if(priceTo < priceFrom)  segColor = C'0xFF,0x52,0x52';
      else                          segColor = C'0x80,0x80,0x80';
   }
   else segColor = C'0x80,0x80,0x80';
   g_lastGhostColor = segColor;
   
   string hName = g_prefix + "GHOST_H_" + IntegerToString(barTo);
   if(ObjectFind(0, hName) >= 0) ObjectDelete(0, hName);
   ObjectCreate(0, hName, OBJ_TREND, 0, tFrom, priceFrom, tTo, priceFrom);
   ObjectSetInteger(0, hName, OBJPROP_COLOR, segColor);
   ObjectSetInteger(0, hName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, hName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, hName, OBJPROP_BACK, true);
   ObjectSetInteger(0, hName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hName, OBJPROP_HIDDEN, true);
   
   string vName = g_prefix + "GHOST_V_" + IntegerToString(barTo);
   if(ObjectFind(0, vName) >= 0) ObjectDelete(0, vName);
   ObjectCreate(0, vName, OBJ_TREND, 0, tTo, priceFrom, tTo, priceTo);
   ObjectSetInteger(0, vName, OBJPROP_COLOR, segColor);
   ObjectSetInteger(0, vName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, vName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, vName, OBJPROP_BACK, true);
   ObjectSetInteger(0, vName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, vName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| ClearGhostTrails — remove all ghost trail objects                  |
//+------------------------------------------------------------------+
void ClearGhostTrails()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "GHOST_") == 0) ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| SpawnCloudTile — add a VA cloud tile at current bar                |
//+------------------------------------------------------------------+
void SpawnCloudTile(const datetime &t[], int rates_total)
{
   int sessionAge = g_sessionBarCount;
   if(sessionAge <= 0) return;
   
   int effSessLen = MathMax(g_prevSessionBars, sessionAge + 1);
   int spawnInterval = MathMax(1, (int)MathRound((double)effSessLen / (double)InpMaxCloudTiles));
   
   bool shouldSpawn = (g_cloudTileCount == 0 && sessionAge > 0);
   if(!shouldSpawn) shouldSpawn = (sessionAge - g_cloudSpawnBar >= spawnInterval);
   if(!shouldSpawn) return;
   
   color baseCol;
   if(g_vaState == "Expanding")       baseCol = clrBlue;
   else if(g_vaState == "Contracting") baseCol = C'0xFF,0x98,0x00';
   else if(g_vaState == "Stable")      baseCol = C'0x8C,0xA0,0xC8';
   else                                baseCol = C'0xB4,0x8C,0x3C';
   
   if(InpVADeltaTint && g_sessionBuyVol + g_sessionSellVol > 0)
   {
      double pressure = g_flowPressure / 100.0;
      if(pressure > 0.15)       baseCol = C'0x4C,0xAF,0x50';
      else if(pressure < -0.15) baseCol = C'0xF4,0x43,0x36';
   }
   
   double lastPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool priceInside = (lastPrice >= g_VAL && lastPrice <= g_VAH);
   if(!priceInside) baseCol = (lastPrice > g_VAH) ? clrLime : clrRed;
   
   color borderCol = clrNONE;
   int borderWidth = 0;
   if(InpVAReclaimBorder)
   {
      if(!priceInside && g_prevPriceInsideVA)      { borderCol = clrRed; borderWidth = 1; }
      else if(priceInside && !g_prevPriceInsideVA)  { borderCol = clrLime; borderWidth = 1; }
   }
   
   datetime tileTime = t[rates_total-1];
   string tileName = g_prefix + "CLOUD_" + IntegerToString(g_cloudTileCount);
   
   if(g_cloudTileCount >= InpMaxCloudTiles)
   {
      if(g_cloudTileNames[0] != "" && ObjectFind(0, g_cloudTileNames[0]) >= 0)
         ObjectDelete(0, g_cloudTileNames[0]);
      for(int i = 0; i < g_cloudTileCount - 1; i++)
         g_cloudTileNames[i] = g_cloudTileNames[i+1];
      g_cloudTileCount--;
   }
   
   ObjectCreate(0, tileName, OBJ_RECTANGLE, 0, tileTime, g_VAH, tileTime + PeriodSeconds(), g_VAL);
   ObjectSetInteger(0, tileName, OBJPROP_COLOR, borderCol != clrNONE ? borderCol : baseCol);
   ObjectSetInteger(0, tileName, OBJPROP_FILL, true);
   ObjectSetInteger(0, tileName, OBJPROP_BACK, true);
   ObjectSetInteger(0, tileName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tileName, OBJPROP_HIDDEN, true);
   if(borderWidth > 0) ObjectSetInteger(0, tileName, OBJPROP_WIDTH, borderWidth);
   ObjectSetInteger(0, tileName, OBJPROP_ZORDER, 3);
   
   g_cloudTileNames[g_cloudTileCount] = tileName;
   g_cloudTileCount++;
   g_cloudSpawnBar = sessionAge;
}

//+------------------------------------------------------------------+
//| DrawVACloud — placeholder for chart event redraw                   |
//+------------------------------------------------------------------+
void DrawVACloud() { /* tiles are persistent objects, no-op */ }

//+------------------------------------------------------------------+
//| ClearCloudTiles — remove all VA cloud tile objects                 |
//+------------------------------------------------------------------+
void ClearCloudTiles()
{
   for(int i = 0; i < g_cloudTileCount; i++)
   {
      if(g_cloudTileNames[i] != "" && ObjectFind(0, g_cloudTileNames[i]) >= 0)
         ObjectDelete(0, g_cloudTileNames[i]);
      g_cloudTileNames[i] = "";
   }
   g_cloudTileCount = 0;
}

//+------------------------------------------------------------------+
//| DrawSessionBox — session boundary rectangle                       |
//+------------------------------------------------------------------+
void DrawSessionBox(const datetime &t[], int startBar, int endBar)
{
   string boxName = g_prefix + "SESS_BOX";
   double sHigh = 0, sLow = DBL_MAX_VAL;
   for(int i = startBar; i <= endBar; i++)
   {
      double hh = iHigh(_Symbol, _Period, i);
      double ll = iLow(_Symbol, _Period, i);
      if(hh > sHigh) sHigh = hh;
      if(ll < sLow)  sLow  = ll;
   }
   if(ObjectFind(0, boxName) < 0)
   {
      ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, t[startBar], sHigh, t[endBar], sLow);
      ObjectSetInteger(0, boxName, OBJPROP_COLOR, C'0xFF,0x99,0x00');
      ObjectSetInteger(0, boxName, OBJPROP_FILL, false);
      ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
      ObjectSetInteger(0, boxName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, boxName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, boxName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, boxName, OBJPROP_ZORDER, 0);
   }
   else
   {
      ObjectSetInteger(0, boxName, OBJPROP_TIME,  0, t[startBar]);
      ObjectSetDouble(0,  boxName, OBJPROP_PRICE, 0, sHigh);
      ObjectSetInteger(0, boxName, OBJPROP_TIME,  1, t[endBar]);
      ObjectSetDouble(0,  boxName, OBJPROP_PRICE, 1, sLow);
   }
   if(InpShowSessionLabels)
   {
      string labelName = g_prefix + "SESS_LABEL";
      if(ObjectFind(0, labelName) < 0)
      {
         ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 5);
      ObjectSetString(0,  labelName, OBJPROP_TEXT, SessionName() + " Session");
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, C'0xFF,0x99,0x00');
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   }
}

//+------------------------------------------------------------------+
//| DrawPriorVA — prior session VA reference lines                     |
//+------------------------------------------------------------------+
void DrawPriorVA(const datetime &t[], int leftBar, int rightBar)
{
   if(g_priorVAH <= 0 || g_priorVAL <= 0) return;
   datetime tLeft = t[leftBar], tRight = t[rightBar] + PeriodSeconds() * 50;
   
   string vahName = g_prefix + "PRIOR_VAH";
   if(ObjectFind(0, vahName) < 0)
      ObjectCreate(0, vahName, OBJ_TREND, 0, tLeft, g_priorVAH, tRight, g_priorVAH);
   else
   {
      ObjectSetInteger(0, vahName, OBJPROP_TIME, 0, tLeft);
      ObjectSetDouble(0,  vahName, OBJPROP_PRICE, 0, g_priorVAH);
      ObjectSetInteger(0, vahName, OBJPROP_TIME, 1, tRight);
      ObjectSetDouble(0,  vahName, OBJPROP_PRICE, 1, g_priorVAH);
   }
   ObjectSetInteger(0, vahName, OBJPROP_COLOR, C'0xF2,0x36,0x45');
   ObjectSetInteger(0, vahName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, vahName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, vahName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, vahName, OBJPROP_BACK, true);
   ObjectSetInteger(0, vahName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, vahName, OBJPROP_HIDDEN, true);
   
   string valName = g_prefix + "PRIOR_VAL";
   if(ObjectFind(0, valName) < 0)
      ObjectCreate(0, valName, OBJ_TREND, 0, tLeft, g_priorVAL, tRight, g_priorVAL);
   else
   {
      ObjectSetInteger(0, valName, OBJPROP_TIME, 0, tLeft);
      ObjectSetDouble(0,  valName, OBJPROP_PRICE, 0, g_priorVAL);
      ObjectSetInteger(0, valName, OBJPROP_TIME, 1, tRight);
      ObjectSetDouble(0,  valName, OBJPROP_PRICE, 1, g_priorVAL);
   }
   ObjectSetInteger(0, valName, OBJPROP_COLOR, C'0x08,0x99,0x81');
   ObjectSetInteger(0, valName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, valName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, valName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, valName, OBJPROP_BACK, true);
   ObjectSetInteger(0, valName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, valName, OBJPROP_HIDDEN, true);
   
   if(g_priorSessionPOC > 0)
   {
      string pocName = g_prefix + "PRIOR_POC";
      if(ObjectFind(0, pocName) < 0)
         ObjectCreate(0, pocName, OBJ_TREND, 0, tLeft, g_priorSessionPOC, tRight, g_priorSessionPOC);
      else
      {
         ObjectSetInteger(0, pocName, OBJPROP_TIME, 0, tLeft);
         ObjectSetDouble(0,  pocName, OBJPROP_PRICE, 0, g_priorSessionPOC);
         ObjectSetInteger(0, pocName, OBJPROP_TIME, 1, tRight);
         ObjectSetDouble(0,  pocName, OBJPROP_PRICE, 1, g_priorSessionPOC);
      }
      ObjectSetInteger(0, pocName, OBJPROP_COLOR, C'0xFF,0xEB,0x3B');
      ObjectSetInteger(0, pocName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, pocName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, pocName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, pocName, OBJPROP_BACK, true);
      ObjectSetInteger(0, pocName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, pocName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| ClearPriorVA — remove prior VA reference objects                   |
//+------------------------------------------------------------------+
void ClearPriorVA()
{
   string names[] = {"PRIOR_VAH", "PRIOR_VAL", "PRIOR_POC"};
   for(int i = 0; i < 3; i++)
   {
      string fullName = g_prefix + names[i];
      if(ObjectFind(0, fullName) >= 0) ObjectDelete(0, fullName);
   }
}

//+------------------------------------------------------------------+
//| DrawZZLine — connect prior swing to new confirmed swing            |
//+------------------------------------------------------------------+
void DrawZZLine(const datetime &t[], int idx)
{
   int fromBar = 0, toBar = idx;
   double fromPrice = 0, toPrice = 0;
   
   if(g_zzNewSwingHigh && g_zzPrevSwingHighBar > 0)
   {
      fromBar = g_zzPrevSwingHighBar; toBar = g_zzSwingHighBar;
      fromPrice = g_zzPrevSwingHigh; toPrice = g_zzSwingHigh;
   }
   else if(g_zzNewSwingHigh && g_zzPrevSwingLowBar > 0)
   {
      fromBar = g_zzPrevSwingLowBar; toBar = g_zzSwingHighBar;
      fromPrice = g_zzPrevSwingLow; toPrice = g_zzSwingHigh;
   }
   else if(g_zzNewSwingLow && g_zzPrevSwingLowBar > 0)
   {
      fromBar = g_zzPrevSwingLowBar; toBar = g_zzSwingLowBar;
      fromPrice = g_zzPrevSwingLow; toPrice = g_zzSwingLow;
   }
   else if(g_zzNewSwingLow && g_zzPrevSwingHighBar > 0)
   {
      fromBar = g_zzPrevSwingHighBar; toBar = g_zzSwingLowBar;
      fromPrice = g_zzPrevSwingHigh; toPrice = g_zzSwingLow;
   }
   else return;
   
   if(fromBar <= 0 || toBar <= 0 || fromBar >= toBar) return;
   
   datetime tFrom = iTime(_Symbol, _Period, fromBar);
   datetime tTo   = iTime(_Symbol, _Period, toBar);
   if(tFrom == 0 || tTo == 0) return;
   
   string zzName = g_prefix + "ZZ_" + IntegerToString(toBar);
   if(ObjectFind(0, zzName) >= 0) ObjectDelete(0, zzName);
   ObjectCreate(0, zzName, OBJ_TREND, 0, tFrom, fromPrice, tTo, toPrice);
   ObjectSetInteger(0, zzName, OBJPROP_COLOR, C'0xC8,0xC8,0xC8');
   ObjectSetInteger(0, zzName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, zzName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, zzName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, zzName, OBJPROP_BACK, true);
   ObjectSetInteger(0, zzName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, zzName, OBJPROP_HIDDEN, true);
   
   // Prune old ZZ lines (keep last 50)
   int zzCount = 0;
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "ZZ_") == 0) zzCount++;
   }
   if(zzCount > 50)
   {
      datetime oldestZZ = LONG_MAX;
      string oldestZZName = "";
      for(int i = ObjectsTotal(0)-1; i >= 0; i--)
      {
         string nm = ObjectName(0, i);
         if(StringFind(nm, g_prefix + "ZZ_") == 0)
         {
            datetime ot = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
            if(ot < oldestZZ) { oldestZZ = ot; oldestZZName = nm; }
         }
      }
      if(oldestZZName != "") ObjectDelete(0, oldestZZName);
   }
}

//+------------------------------------------------------------------+
//| DrawSwingLevels — resistance/support/equilibrium from ZZ swings     |
//+------------------------------------------------------------------+
void DrawSwingLevels(const datetime &t[], int idx)
{
   datetime tRight = t[idx] + PeriodSeconds() * 50;
   
   // Resistance line (swing high)
   string resName = g_prefix + "ZZ_RES";
   if(ObjectFind(0, resName) < 0)
      ObjectCreate(0, resName, OBJ_TREND, 0, t[g_zzSwingHighBar], g_zzSwingHigh, tRight, g_zzSwingHigh);
   else
   {
      ObjectSetInteger(0, resName, OBJPROP_TIME, 0, t[g_zzSwingHighBar]);
      ObjectSetDouble(0,  resName, OBJPROP_PRICE, 0, g_zzSwingHigh);
      ObjectSetInteger(0, resName, OBJPROP_TIME, 1, tRight);
      ObjectSetDouble(0,  resName, OBJPROP_PRICE, 1, g_zzSwingHigh);
   }
   ObjectSetInteger(0, resName, OBJPROP_COLOR, C'0xFF,0x52,0x52');
   ObjectSetInteger(0, resName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, resName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, resName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, resName, OBJPROP_BACK, true);
   ObjectSetInteger(0, resName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, resName, OBJPROP_HIDDEN, true);
   
   // Support line (swing low)
   string supName = g_prefix + "ZZ_SUP";
   if(ObjectFind(0, supName) < 0)
      ObjectCreate(0, supName, OBJ_TREND, 0, t[g_zzSwingLowBar], g_zzSwingLow, tRight, g_zzSwingLow);
   else
   {
      ObjectSetInteger(0, supName, OBJPROP_TIME, 0, t[g_zzSwingLowBar]);
      ObjectSetDouble(0,  supName, OBJPROP_PRICE, 0, g_zzSwingLow);
      ObjectSetInteger(0, supName, OBJPROP_TIME, 1, tRight);
      ObjectSetDouble(0,  supName, OBJPROP_PRICE, 1, g_zzSwingLow);
   }
   ObjectSetInteger(0, supName, OBJPROP_COLOR, C'0x4C,0xAF,0x50');
   ObjectSetInteger(0, supName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, supName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, supName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, supName, OBJPROP_BACK, true);
   ObjectSetInteger(0, supName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, supName, OBJPROP_HIDDEN, true);
   
   // Equilibrium (midpoint)
   if(InpShowEquilibrium)
   {
      double eq = (g_zzSwingHigh + g_zzSwingLow) / 2.0;
      string eqName = g_prefix + "ZZ_EQ";
      if(ObjectFind(0, eqName) < 0)
         ObjectCreate(0, eqName, OBJ_TREND, 0, t[g_zzSwingHighBar], eq, tRight, eq);
      else
      {
         ObjectSetInteger(0, eqName, OBJPROP_TIME, 0, t[MathMin(g_zzSwingHighBar, g_zzSwingLowBar)]);
         ObjectSetDouble(0,  eqName, OBJPROP_PRICE, 0, eq);
         ObjectSetInteger(0, eqName, OBJPROP_TIME, 1, tRight);
         ObjectSetDouble(0,  eqName, OBJPROP_PRICE, 1, eq);
      }
      ObjectSetInteger(0, eqName, OBJPROP_COLOR, C'0x96,0x96,0x96');
      ObjectSetInteger(0, eqName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, eqName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, eqName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, eqName, OBJPROP_BACK, true);
      ObjectSetInteger(0, eqName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, eqName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| ClearZZLines — remove all ZZ connecting line objects               |
//+------------------------------------------------------------------+
void ClearZZLines()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "ZZ_") == 0) ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| ClearSwingLevels — remove swing level line objects                 |
//+------------------------------------------------------------------+
void ClearSwingLevels()
{
   string names[] = {"ZZ_RES", "ZZ_SUP", "ZZ_EQ"};
   for(int i = 0; i < 3; i++)
   {
      string fullName = g_prefix + names[i];
      if(ObjectFind(0, fullName) >= 0) ObjectDelete(0, fullName);
   }
}

//+------------------------------------------------------------------+
//| Draw FVG rectangle (with g_prefix for cleanup)                     |
//+------------------------------------------------------------------+
void DrawFVG(string nm, datetime t1, double p1, datetime t2, double p2, color clr, int bias)
{
   string fullName = g_prefix + nm;
   if(ObjectFind(0, fullName) >= 0) return;
   
   // Prune oldest if at capacity
   if(g_fvgListCount >= InpFVGMaxActive)
   {
      datetime oldest = LONG_MAX; int oldestIdx = -1;
      for(int i = 0; i < g_fvgListCount; i++)
      {
         if(g_fvgList[i].active && g_fvgList[i].startTime < oldest)
            { oldest = g_fvgList[i].startTime; oldestIdx = i; }
      }
      if(oldestIdx >= 0)
      {
         if(ObjectFind(0, g_fvgList[oldestIdx].name) >= 0)
            ObjectDelete(0, g_fvgList[oldestIdx].name);
         for(int i = oldestIdx; i < g_fvgListCount - 1; i++)
            g_fvgList[i] = g_fvgList[i+1];
         g_fvgListCount--;
         g_fvgCount--;
      }
   }
   
   ObjectCreate(0, fullName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FILL, true);
   ObjectSetInteger(0, fullName, OBJPROP_BACK, true);
   ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, fullName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, fullName, OBJPROP_ZORDER, 6);
   
   // Store metadata
   if(g_fvgListCount < MAX_FVG_TRACK)
   {
      g_fvgList[g_fvgListCount].name = fullName;
      g_fvgList[g_fvgListCount].bias = bias;
      g_fvgList[g_fvgListCount].highPrice = MathMax(p1, p2);
      g_fvgList[g_fvgListCount].lowPrice = MathMin(p1, p2);
      g_fvgList[g_fvgListCount].startTime = t1;
      g_fvgList[g_fvgListCount].endTime = t2;
      g_fvgList[g_fvgListCount].active = true;
      g_fvgListCount++;
   }
   g_fvgCount++;
}

//+------------------------------------------------------------------+
//| ScanFVGMitigation — detect price closing through active FVGs       |
//+------------------------------------------------------------------+
void ScanFVGMitigation(double closePrice, datetime barTime)
{
   g_ifvgFlipBull = false; g_ifvgFlipBear = false;
   if(!InpShowIFVG) return;
   
   for(int i = g_fvgListCount - 1; i >= 0; i--)
   {
      if(!g_fvgList[i].active) continue;
      if(barTime < g_fvgList[i].startTime) continue;
      
      // Bull FVG mitigation: price closes below FVG low (gap filled downward)
      if(g_fvgList[i].bias == 1 && closePrice <= g_fvgList[i].lowPrice)
      {
         // Flip to bearish IFVG (resistance)
         string ifvgName = g_fvgList[i].name;
         StringReplace(ifvgName, "FVG_B_", "IFVG_S_");
         SpawnIFVG(ifvgName, g_fvgList[i].startTime, g_fvgList[i].highPrice,
                   g_fvgList[i].endTime, g_fvgList[i].lowPrice, -1);
         g_fvgList[i].active = false;
         // Hide original FVG rectangle
         if(ObjectFind(0, g_fvgList[i].name) >= 0)
            ObjectDelete(0, g_fvgList[i].name);
         g_ifvgFlipBear = true;
      }
      // Bear FVG mitigation: price closes above FVG high (gap filled upward)
      else if(g_fvgList[i].bias == -1 && closePrice >= g_fvgList[i].highPrice)
      {
         // Flip to bullish IFVG (support)
         string ifvgName = g_fvgList[i].name;
         StringReplace(ifvgName, "FVG_S_", "IFVG_B_");
         SpawnIFVG(ifvgName, g_fvgList[i].startTime, g_fvgList[i].highPrice,
                   g_fvgList[i].endTime, g_fvgList[i].lowPrice, 1);
         g_fvgList[i].active = false;
         if(ObjectFind(0, g_fvgList[i].name) >= 0)
            ObjectDelete(0, g_fvgList[i].name);
         g_ifvgFlipBull = true;
      }
   }
}

//+------------------------------------------------------------------+
//| SpawnIFVG — create inverse FVG rectangle                           |
//+------------------------------------------------------------------+
void SpawnIFVG(string nm, datetime t1, double pHigh, datetime t2, double pLow, int bias)
{
   if(ObjectFind(0, nm) >= 0) return;
   string fullName = (StringFind(nm, g_prefix) == 0) ? nm : g_prefix + nm;
   
   // Prune IFVGs if at capacity
   if(g_ifvgListCount >= InpIFVGMaxActive)
   {
      datetime oldest = LONG_MAX; int oldestIdx = -1;
      for(int i = 0; i < g_ifvgListCount; i++)
      {
         if(g_ifvgList[i].active && g_ifvgList[i].startTime < oldest)
            { oldest = g_ifvgList[i].startTime; oldestIdx = i; }
      }
      if(oldestIdx >= 0)
      {
         if(ObjectFind(0, g_ifvgList[oldestIdx].name) >= 0)
            ObjectDelete(0, g_ifvgList[oldestIdx].name);
         for(int i = oldestIdx; i < g_ifvgListCount - 1; i++)
            g_ifvgList[i] = g_ifvgList[i+1];
         g_ifvgListCount--;
      }
   }
   
   color clr = (bias == 1) ? C'0x9C,0x27,0xB0' : C'0xFF,0x98,0x00';  // purple bull IFVG, orange bear IFVG
   ObjectCreate(0, fullName, OBJ_RECTANGLE, 0, t1, pHigh, t2, pLow);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FILL, true);
   ObjectSetInteger(0, fullName, OBJPROP_BACK, true);
   ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, fullName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, fullName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, fullName, OBJPROP_ZORDER, 7);
   
   // Store IFVG metadata
   if(g_ifvgListCount < MAX_IFVG_TRACK)
   {
      g_ifvgList[g_ifvgListCount].name = fullName;
      g_ifvgList[g_ifvgListCount].bias = bias;
      g_ifvgList[g_ifvgListCount].highPrice = pHigh;
      g_ifvgList[g_ifvgListCount].lowPrice = pLow;
      g_ifvgList[g_ifvgListCount].startTime = t1;
      g_ifvgList[g_ifvgListCount].active = true;
      g_ifvgListCount++;
   }
}

//+------------------------------------------------------------------+
//| ScanIFVGInvalidation — price closes through IFVG = invalidated     |
//+------------------------------------------------------------------+
void ScanIFVGInvalidation(double closePrice, datetime barTime)
{
   if(!InpShowIFVG) return;
   
   for(int i = g_ifvgListCount - 1; i >= 0; i--)
   {
      if(!g_ifvgList[i].active) continue;
      if(barTime < g_ifvgList[i].startTime) continue;
      
      // Bull IFVG (support) invalidated: close below IFVG low
      if(g_ifvgList[i].bias == 1 && closePrice < g_ifvgList[i].lowPrice)
      {
         g_ifvgList[i].active = false;
         if(ObjectFind(0, g_ifvgList[i].name) >= 0)
            ObjectDelete(0, g_ifvgList[i].name);
      }
      // Bear IFVG (resistance) invalidated: close above IFVG high
      else if(g_ifvgList[i].bias == -1 && closePrice > g_ifvgList[i].highPrice)
      {
         g_ifvgList[i].active = false;
         if(ObjectFind(0, g_ifvgList[i].name) >= 0)
            ObjectDelete(0, g_ifvgList[i].name);
      }
   }
}

//+------------------------------------------------------------------+
//| AgeFVGs — expire FVGs past their end time                          |
//+------------------------------------------------------------------+
void AgeFVGs(datetime now)
{
   for(int i = g_fvgListCount - 1; i >= 0; i--)
   {
      if(g_fvgList[i].active && g_fvgList[i].endTime > 0 && g_fvgList[i].endTime < now)
      {
         g_fvgList[i].active = false;
         if(ObjectFind(0, g_fvgList[i].name) >= 0)
            ObjectDelete(0, g_fvgList[i].name);
         g_fvgCount--;
      }
      // Also age IFVGs past their end time
   }
   for(int i = g_ifvgListCount - 1; i >= 0; i--)
   {
      if(g_ifvgList[i].active && g_ifvgList[i].endTime > 0 && g_ifvgList[i].endTime < now)
      {
         g_ifvgList[i].active = false;
         if(ObjectFind(0, g_ifvgList[i].name) >= 0)
            ObjectDelete(0, g_ifvgList[i].name);
      }
   }
   if(g_fvgCount < 0) g_fvgCount = 0;
   // Compact lists to remove inactive entries
   CompactFVGLists();
}

//+------------------------------------------------------------------+
//| CompactFVGLists — physically remove inactive entries               |
//+------------------------------------------------------------------+
void CompactFVGLists()
{
   // Compact FVG list
   int writeIdx = 0;
   for(int i = 0; i < g_fvgListCount; i++)
   {
      if(g_fvgList[i].active)
      {
         if(writeIdx != i) g_fvgList[writeIdx] = g_fvgList[i];
         writeIdx++;
      }
   }
   g_fvgListCount = writeIdx;
   
   // Compact IFVG list
   writeIdx = 0;
   for(int i = 0; i < g_ifvgListCount; i++)
   {
      if(g_ifvgList[i].active)
      {
         if(writeIdx != i) g_ifvgList[writeIdx] = g_ifvgList[i];
         writeIdx++;
      }
   }
   g_ifvgListCount = writeIdx;
   g_fvgCount = g_fvgListCount;  // sync the legacy counter
}

//+------------------------------------------------------------------+
//| ClearAllFVGs — session reset                                       |
//+------------------------------------------------------------------+
void ClearAllFVGs()
{
   for(int i = 0; i < g_fvgListCount; i++)
   {
      if(ObjectFind(0, g_fvgList[i].name) >= 0)
         ObjectDelete(0, g_fvgList[i].name);
   }
   for(int i = 0; i < g_ifvgListCount; i++)
   {
      if(ObjectFind(0, g_ifvgList[i].name) >= 0)
         ObjectDelete(0, g_ifvgList[i].name);
   }
   g_fvgListCount = 0;
   g_ifvgListCount = 0;
   g_fvgCount = 0;
}

//+------------------------------------------------------------------+
//| DrawStackedImbalances — merged zones of buy/sell imbalance         |
//+------------------------------------------------------------------+
void DrawStackedImbalances(const datetime &t[], int endBar)
{
   // Clear old imbalance objects
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "IMB_") == 0) ObjectDelete(0, nm);
   }
   
   if(!InpShowImbalances || g_rows <= 0 || g_binSize <= 0) return;
   if(g_sessionBuyVol + g_sessionSellVol <= 0) return;
   
   datetime tRight = t[endBar] + PeriodSeconds() * 2;
   int imbCount = 0;
   
   for(int b = 0; b < g_rows; b++)
   {
      if(g_volBins[b] <= 0) continue;
      
      double buyVol  = g_buyBins[b];
      double sellVol = g_sellBins[b];
      if(buyVol <= 0 && sellVol <= 0) continue;
      
      double ratio = (sellVol > 0) ? buyVol / sellVol : (buyVol > 0 ? 100 : 1);
      double invRatio = (buyVol > 0) ? sellVol / buyVol : (sellVol > 0 ? 100 : 1);
      
      bool isImbalance = (ratio >= InpImbalanceRatio || invRatio >= InpImbalanceRatio);
      if(!isImbalance) continue;
      
      double binPriceLow  = g_vpLow + b * g_binSize;
      double binPriceHigh = binPriceLow + g_binSize;
      color imbColor = (ratio > invRatio) ? C'0x4C,0xAF,0x50' : C'0xF4,0x43,0x36';
      
      string imbName = g_prefix + "IMB_" + IntegerToString(imbCount);
      ObjectCreate(0, imbName, OBJ_RECTANGLE, 0, t[endBar], binPriceHigh, tRight, binPriceLow);
      ObjectSetInteger(0, imbName, OBJPROP_COLOR, imbColor);
      ObjectSetInteger(0, imbName, OBJPROP_FILL, true);
      ObjectSetInteger(0, imbName, OBJPROP_BACK, true);
      ObjectSetInteger(0, imbName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, imbName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, imbName, OBJPROP_ZORDER, 5);
      imbCount++;
      if(imbCount >= 40) break;  // cap at 40
   }
}

//+------------------------------------------------------------------+
//| DrawFastLanes — merged zones of thin volume (liquidity voids)      |
//+------------------------------------------------------------------+
void DrawFastLanes(const datetime &t[], int endBar)
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "FL_") == 0) ObjectDelete(0, nm);
   }
   
   if(!InpShowFastLanes || g_rows <= 0 || g_maxVol <= 0) return;
   
   double threshold = g_maxVol * InpFastLaneThresh;
   datetime tRight = t[endBar] + PeriodSeconds() * 2;
   int flCount = 0;
   int zoneStart = -1;
   
   for(int b = 0; b < g_rows; b++)
   {
      bool isThin = (g_volBins[b] <= threshold && g_volBins[b] > 0);
      
      if(isThin && zoneStart < 0)
         zoneStart = b;
      else if(!isThin && zoneStart >= 0)
      {
         int zoneWidth = b - zoneStart;
         if(zoneWidth >= InpFastLaneMinWidth)
         {
            double zLow  = g_vpLow + zoneStart * g_binSize;
            double zHigh = g_vpLow + b * g_binSize;
            string flName = g_prefix + "FL_" + IntegerToString(flCount);
            ObjectCreate(0, flName, OBJ_RECTANGLE, 0, t[endBar], zHigh, tRight, zLow);
            ObjectSetInteger(0, flName, OBJPROP_COLOR, C'0x8A,0x2B,0xE2');
            ObjectSetInteger(0, flName, OBJPROP_FILL, true);
            ObjectSetInteger(0, flName, OBJPROP_BACK, true);
            ObjectSetInteger(0, flName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, flName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, flName, OBJPROP_ZORDER, 4);
            flCount++;
         }
         zoneStart = -1;
      }
   }
   // Handle zone extending to end
   if(zoneStart >= 0 && (g_rows - zoneStart) >= InpFastLaneMinWidth)
   {
      double zLow  = g_vpLow + zoneStart * g_binSize;
      double zHigh = g_vpLow + g_rows * g_binSize;
      string flName = g_prefix + "FL_" + IntegerToString(flCount);
      ObjectCreate(0, flName, OBJ_RECTANGLE, 0, t[endBar], zHigh, tRight, zLow);
      ObjectSetInteger(0, flName, OBJPROP_COLOR, C'0x8A,0x2B,0xE2');
      ObjectSetInteger(0, flName, OBJPROP_FILL, true);
      ObjectSetInteger(0, flName, OBJPROP_BACK, true);
      ObjectSetInteger(0, flName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, flName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, flName, OBJPROP_ZORDER, 4);
   }
}

//+------------------------------------------------------------------+
//| DrawSignalLabel — place a signal label on chart                    |
//+------------------------------------------------------------------+
void DrawSignalLabel(string nm, datetime t, double price, string text, color clr)
{
   string fullName = g_prefix + "SIG_" + nm;
   if(ObjectFind(0, fullName) >= 0) return;
   ObjectCreate(0, fullName, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, fullName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, fullName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
}

//+------------------------------------------------------------------+
//| PruneSignalLabels — keep only the N newest signal labels           |
//+------------------------------------------------------------------+
void PruneSignalLabels(int maxLabels)
{
   int count = 0;
   // Count existing signal labels
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "SIG_") == 0) count++;
   }
   // Delete oldest if over limit
   while(count > maxLabels)
   {
      datetime oldestTime = LONG_MAX;
      string oldestName = "";
      for(int i = ObjectsTotal(0)-1; i >= 0; i--)
      {
         string nm = ObjectName(0, i);
         if(StringFind(nm, g_prefix + "SIG_") == 0)
         {
            datetime ot = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
            if(ot < oldestTime) { oldestTime = ot; oldestName = nm; }
         }
      }
      if(oldestName != "") { ObjectDelete(0, oldestName); count--; }
      else break;
   }
}

//+------------------------------------------------------------------+
//| Dashboard row helpers                                             |
//+------------------------------------------------------------------+
void DR(string p, int r, string l, string v, color c, int x, int y0, int g, int cw)
{
   int yy = y0 + r * g;
   CL(p+"l"+IntegerToString(r), l, x, yy, clrGray, 8);
   CL(p+"v"+IntegerToString(r), v, x+cw, yy, c, 8);
}

void CL(string n, string t, int x, int y, color c, int s)
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

//+------------------------------------------------------------------+
//| Cleanup                                                           |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n);
   }
   g_fvgCount = 0;
   g_fvgListCount = 0;
   g_ifvgListCount = 0;
   g_cloudTileCount = 0;
   for(int j = 0; j < MAX_CLOUD_TILES; j++) g_cloudTileNames[j] = "";
   ChartRedraw();
}
//+------------------------------------------------------------------+
