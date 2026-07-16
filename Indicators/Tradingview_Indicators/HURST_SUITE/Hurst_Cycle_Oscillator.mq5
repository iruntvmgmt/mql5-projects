//+------------------------------------------------------------------+
//|                                 Hurst Cycle Channel Oscillator.mq5 |
//|                    Ported from Pine Script v6 → MQL5              |
//|                    Original: HCC_Oscillator + HurstCycleLib       |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: Hurst Cycle Channel Oscillator [RunsTV] ::"
#property description "Hurst-style normalized cycle oscillator with divergence detection."
#property description "Channel: price position inside medium cycle channel."

#property indicator_separate_window
#property indicator_minimum -0.55
#property indicator_maximum 1.25
#property indicator_buffers 11
#property indicator_plots   7

// ── Plots ───────────────────────────────────────────────────────────────────
#property indicator_label1  "Oscillator"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_width1  1

#property indicator_label2  "Histogram"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2

#property indicator_label3  "Upper Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_width3  1

#property indicator_label4  "Lower Band"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_width4  1

#property indicator_label5  "Bull Div"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  2

#property indicator_label6  "Bear Div"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  2

#property indicator_label7  "Div Conf Bar"
#property indicator_type7   DRAW_NONE
#property indicator_color7  clrGray

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Cycle Settings ═══"
input int                          InpSCLBars      = 10;                 // Short Cycle Length (λ)
input int                          InpMCLBars      = 30;                 // Medium Cycle Length (λ)
input double                       InpSCM          = 1.0;                // Short Band ATR Mult
input double                       InpMCM          = 3.0;                // Medium Band ATR Mult
input ENUM_APPLIED_PRICE           InpSrc          = PRICE_CLOSE;        // Price Source

input group                        "═══ MA Engine ═══"
input ENUM_MA_METHOD               InpMAType       = MODE_SMMA;          // MA Type (RMA=SMMA)

input group                        "═══ Oscillator ═══"
input bool                         InpShowHist     = true;               // Show Histogram Fill
input double                       InpUpperBand    = 0.80;               // Upper Band Level
input double                       InpLowerBand    = 0.20;               // Lower Band Level
input bool                         InpClamp        = false;              // Clamp to 0-1

input group                        "═══ Validation ═══"
input bool                         InpStrictMA      = true;               // Reject unsupported MA types

input group                        "═══ Divergence ═══"
input bool                         InpShowDiv      = true;               // Show Divergence
input bool                         InpDivUseHL     = true;                // Use High/Low for price pivots (not source)
input int                          InpDivBars      = 8;                  // Divergence Pivot Bars

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_osc[];            // 0
double g_hist[];           // 1
double g_upperBand[];      // 2
double g_lowerBand[];      // 3
double g_bullDiv[];        // 4
double g_bearDiv[];        // 5
double g_divConfBar[];     // 6  — confirmation bar offset for EAs (0 = no signal)
// Calc buffers
double g_scBase[];         // 7
double g_scTop[];          // 8
double g_scBot[];          // 9
double g_mcBase[];         // 10

// Persistent incremental EMA/RMA buffers — O(1) per bar, replaces the
// old per-bar HurstMA(…, MODE_EMA/MODE_SMMA) calls that walked to
// ArraySize(a) every call (O(n) per bar = O(n^2) total).
double g_scEma[];          // runtime — short cycle incremental MA
double g_mcEma[];          // runtime — medium cycle incremental MA

// ── Divergence persistent state (global, reset on prev_calc==0) ────────────
double g_prevOL=0, g_prevPL=0, g_curOL=0, g_curPL=0;
double g_prevOH=0, g_prevPH=0, g_curOH=0, g_curPH=0;

string g_prefix = "HCC_";

//+------------------------------------------------------------------+
//| Hurst MA                                                          |
//+------------------------------------------------------------------+
double HurstMA(double &a[], int len, ENUM_MA_METHOD m, int s)
{
   if(s + len > ArraySize(a)) return 0;
   int safeLen = MathMax(2, len);
   
   if(m == MODE_SMMA) // RMA
   {
      double alpha = 1.0 / safeLen;
      double rma = 0;
      for(int j = 0; j < safeLen; j++) rma += a[s + j];
      rma /= safeLen;
      // Walk forward from s+safeLen to the end of the array
      int total = ArraySize(a);
      for(int j = s + safeLen; j < total; j++)
         rma = a[j] * alpha + rma * (1 - alpha);
      return rma;
   }
   else if(m == MODE_EMA)
   {
      double alpha = 2.0/(safeLen+1);
      double ema = 0;
      for(int j = 0; j < safeLen; j++) ema += a[s+j];
      ema /= safeLen;
      int total = ArraySize(a);
      for(int j = s+safeLen; j < total; j++)
         ema = a[j]*alpha + ema*(1-alpha);
      return ema;
   }
   else // SMA / TMA
   {
      double sum = 0;
      for(int i = 0; i < safeLen; i++) sum += a[s+i];
      return sum/safeLen;
   }
}

//+------------------------------------------------------------------+
//| ATR                                                               |
//+------------------------------------------------------------------+
double ATR(const double &h[], const double &l[], const double &c[], int p, int idx)
{
   if(idx < p) return 0;
   double sum = 0;
   for(int i = idx-p+1; i <= idx; i++)
   {
      double tr = MathMax(h[i]-l[i], MathMax(MathAbs(h[i]-c[i-1]), MathAbs(l[i]-c[i-1])));
      sum += tr;
   }
   return sum/p;
}

//+------------------------------------------------------------------+
//| IsPivotHigh                                                       |
//+------------------------------------------------------------------+
bool IsPivotHigh(double &a[], int lr, int idx)
{
   if(idx-lr < 0 || idx+lr >= ArraySize(a)) return false;
   double v = a[idx];
   for(int i = idx-lr; i < idx; i++) if(a[i] > v) return false;
   for(int i = idx+1; i <= idx+lr; i++) if(a[i] >= v) return false;
   return true;
}

bool IsPivotLow(double &a[], int lr, int idx)
{
   if(idx-lr < 0 || idx+lr >= ArraySize(a)) return false;
   double v = a[idx];
   for(int i = idx-lr; i < idx; i++) if(a[i] < v) return false;
   for(int i = idx+1; i <= idx+lr; i++) if(a[i] <= v) return false;
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
   // ── Input validation ─────────────────────────────────────────────────────
   if(InpSCLBars <= 0 || InpMCLBars <= 0 || InpDivBars <= 0)
   {
      Print("HCC OSC: Cycle lengths and divergence bars must be > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSCM < 0 || InpMCM < 0)
   {
      Print("HCC OSC: ATR multipliers must be >= 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLowerBand >= InpUpperBand)
   {
      Print("HCC OSC: Lower band must be < Upper band");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpStrictMA && InpMAType != MODE_SMA && InpMAType != MODE_EMA && InpMAType != MODE_SMMA)
   {
      Print("HCC OSC: Unsupported MA type. Use SMA, EMA, or SMMA (RMA)");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // ── Buffer binding ───────────────────────────────────────────────────────
   if(!SetIndexBuffer(0, g_osc,       INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(1, g_hist,      INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(2, g_upperBand, INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(3, g_lowerBand, INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(4, g_bullDiv,   INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(5, g_bearDiv,   INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(6, g_divConfBar,INDICATOR_DATA))  return INIT_FAILED;
   if(!SetIndexBuffer(7, g_scBase,    INDICATOR_CALCULATIONS)) return INIT_FAILED;
   if(!SetIndexBuffer(8, g_scTop,     INDICATOR_CALCULATIONS)) return INIT_FAILED;
   if(!SetIndexBuffer(9, g_scBot,     INDICATOR_CALCULATIONS)) return INIT_FAILED;
   if(!SetIndexBuffer(10,g_mcBase,    INDICATOR_CALCULATIONS)) return INIT_FAILED;
   
   PlotIndexSetInteger(4, PLOT_ARROW, 233);
   PlotIndexSetInteger(5, PLOT_ARROW, 234);
   
   // Compute minB for PLOT_DRAW_BEGIN (must match OnCalculate logic)
   int sc_L  = MathMax(3, (int)MathRound(InpSCLBars / 2.0));
   int mc_L  = MathMax(3, (int)MathRound(InpMCLBars / 2.0));
   int sc_disp = MathMax(1, (int)MathRound(sc_L / 2.0));
   int mc_disp = MathMax(1, (int)MathRound(mc_L / 2.0));
   int minB  = InpMCLBars + InpSCLBars + InpDivBars + 30;
   
   for(int p = 0; p < 7; p++)
   {
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      PlotIndexSetInteger(p, PLOT_DRAW_BEGIN, minB);
   }
   
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("HCC OSC(%d,%d)", InpSCLBars, InpMCLBars));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   // Clean up any chart objects (currently none created; kept for future use)
   for(int i = ObjectsTotal(0)-1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n);
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
   // ── Enforce chronological (ordinary) array indexing ──────────────────────
   // MQL5 does not guarantee input-array direction; we standardise here.
   ArraySetAsSeries(t,  false);
   ArraySetAsSeries(o,  false);
   ArraySetAsSeries(h,  false);
   ArraySetAsSeries(l,  false);
   ArraySetAsSeries(c,  false);
   ArraySetAsSeries(tv, false);
   ArraySetAsSeries(v,  false);
   ArraySetAsSeries(sp, false);
   
   int sc_L  = MathMax(3, (int)MathRound(InpSCLBars / 2.0));
   int mc_L  = MathMax(3, (int)MathRound(InpMCLBars / 2.0));
   int sc_disp = MathMax(1, (int)MathRound(sc_L / 2.0));
   int mc_disp = MathMax(1, (int)MathRound(mc_L / 2.0));
   int fld_shift = MathMax(1, (int)MathRound(InpMCLBars / 2.0));
   
   int minB = InpMCLBars + InpSCLBars + InpDivBars + 30;
   if(rates_total < minB) return 0;
   
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   if(start < minB) start = minB;
   
   // ── Reset on full recalculation ──────────────────────────────────────────
   bool useIncremental = (InpMAType == MODE_EMA || InpMAType == MODE_SMMA);
   
   if(prev_calc == 0)
   {
      // Clear signal buffers to EMPTY_VALUE so zero doesn't draw phantom arrows
      ArrayInitialize(g_bullDiv,    EMPTY_VALUE);
      ArrayInitialize(g_bearDiv,    EMPTY_VALUE);
      ArrayInitialize(g_divConfBar, EMPTY_VALUE);
      
      // Reset divergence pivot state
      g_prevOL=0; g_prevPL=0; g_curOL=0; g_curPL=0;
      g_prevOH=0; g_prevPH=0; g_curOH=0; g_curPH=0;
   }
   
   // ── Build source array ───────────────────────────────────────────────────
   double src[];
   ArrayResize(src, rates_total);
   for(int i = 0; i < rates_total; i++)
      src[i] = GetPrice(o[i], h[i], l[i], c[i], InpSrc);
   
   // ── Pre-fill incremental MAs so displaced reads are never uninitialised ──
   ArrayResize(g_scEma, rates_total);
   ArrayResize(g_mcEma, rates_total);
   
   if(prev_calc == 0 && useIncremental)
   {
      double sc_alpha = (InpMAType == MODE_SMMA) ? 1.0 / sc_L : 2.0 / (sc_L + 1.0);
      double mc_alpha = (InpMAType == MODE_SMMA) ? 1.0 / mc_L : 2.0 / (mc_L + 1.0);
      
      // Seed SC EMA at bar sc_L-1 with SMA of first sc_L bars
      int scSeed = sc_L - 1;
      if(scSeed < rates_total)
      {
         double sum = 0;
         for(int j = 0; j < sc_L; j++) sum += src[j];
         g_scEma[scSeed] = sum / sc_L;
         for(int j = sc_L; j < rates_total; j++)
            g_scEma[j] = src[j] * sc_alpha + g_scEma[j-1] * (1.0 - sc_alpha);
      }
      
      // Seed MC EMA at bar mc_L-1 with SMA of first mc_L bars
      int mcSeed = mc_L - 1;
      if(mcSeed < rates_total)
      {
         double sum = 0;
         for(int j = 0; j < mc_L; j++) sum += src[j];
         g_mcEma[mcSeed] = sum / mc_L;
         for(int j = mc_L; j < rates_total; j++)
            g_mcEma[j] = src[j] * mc_alpha + g_mcEma[j-1] * (1.0 - mc_alpha);
      }
   }
   else if(prev_calc > 0 && useIncremental)
   {
      // Continue incremental MAs from where we left off
      double sc_alpha = (InpMAType == MODE_SMMA) ? 1.0 / sc_L : 2.0 / (sc_L + 1.0);
      double mc_alpha = (InpMAType == MODE_SMMA) ? 1.0 / mc_L : 2.0 / (mc_L + 1.0);
      
      for(int j = start; j < rates_total; j++)
      {
         g_scEma[j] = src[j] * sc_alpha + g_scEma[j-1] * (1.0 - sc_alpha);
         g_mcEma[j] = src[j] * mc_alpha + g_mcEma[j-1] * (1.0 - mc_alpha);
      }
   }
   
   // ── Main calculation loop ────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // ── Short cycle channel (calculated for buffer storage; not yet wired to output) ──
      int sc_base_idx = MathMax(0, i - sc_disp);
      g_scBase[i] = useIncremental ? g_scEma[sc_base_idx]
                                   : HurstMA(src, sc_L, InpMAType, MathMax(0, sc_base_idx - sc_L + 1));
      
      double sc_atr = ATR(h, l, c, sc_L, i);
      g_scTop[i] = g_scBase[i] + InpSCM * sc_atr;
      g_scBot[i] = g_scBase[i] - InpSCM * sc_atr;
      
      // ── Medium cycle channel ──────────────────────────────────────────────
      int mc_idx = MathMax(0, i - mc_disp);
      g_mcBase[i] = useIncremental ? g_mcEma[mc_idx]
                                   : HurstMA(src, mc_L, InpMAType, MathMax(0, mc_idx - mc_L + 1));
      double mc_atr = ATR(h, l, c, mc_L, i);
      double mc_top = g_mcBase[i] + InpMCM * mc_atr;
      double mc_bot = g_mcBase[i] - InpMCM * mc_atr;
      
      // Medium cycle FLD (price from λ/2 bars ago)
      double fld_mc = (i >= fld_shift) ? src[i - fld_shift] : src[i];
      bool mc_bull = src[i] > fld_mc;
      
      // ── Oscillator ────────────────────────────────────────────────────────
      double mc_range = mc_top - mc_bot;
      double oscRaw = (mc_range > 1e-10) ? (src[i] - mc_bot) / mc_range : 0.5;
      g_osc[i] = InpClamp ? MathMax(0.0, MathMin(1.0, oscRaw)) : oscRaw;
      
      // ── Histogram (respects InpShowHist) ──────────────────────────────────
      if(InpShowHist)
      {
         double oscPhase = MathMax(0.0, MathMin(1.0, g_osc[i]));
         double oscDist  = MathMin(1.0, MathAbs(oscPhase - 0.5) * 2.0);
         g_hist[i] = mc_bull ? oscDist * 0.5 : -oscDist * 0.5;
      }
      else
      {
         g_hist[i] = EMPTY_VALUE;
      }
      
      // ── Bands ─────────────────────────────────────────────────────────────
      g_upperBand[i] = InpUpperBand;
      g_lowerBand[i] = InpLowerBand;
      
      // ── Divergence Detection ──────────────────────────────────────────────
      // Uses oscillator pivots confirmed at bar i (InpDivBars after the pivot).
      // Price is read from high/low at the oscillator-pivot bar for proper RSI-style divergence.
      // Arrow is placed at the pivot bar (pIdx); confirmation bar offset is stored in g_divConfBar.
      
      if(InpShowDiv && i >= InpDivBars * 2)
      {
         int pIdx = i - InpDivBars;
         
         // Clear previous signal at this position before re-evaluating
         g_bullDiv[pIdx]    = EMPTY_VALUE;
         g_bearDiv[pIdx]    = EMPTY_VALUE;
         g_divConfBar[pIdx] = 0;
         
         bool oPivLo = IsPivotLow(g_osc, InpDivBars, pIdx);
         bool oPivHi = IsPivotHigh(g_osc, InpDivBars, pIdx);
         
         // Price pivots: use high/low for divergence (or source if user prefers)
         double priceForBull, priceForBear;
         if(InpDivUseHL)
         {
            priceForBull = l[pIdx];  // bullish divergence → compare swing lows
            priceForBear = h[pIdx];  // bearish divergence → compare swing highs
         }
         else
         {
            priceForBull = src[pIdx];
            priceForBear = src[pIdx];
         }
         
         if(oPivLo)
         {
            g_prevOL = g_curOL;  g_curOL = g_osc[pIdx];
            g_prevPL = g_curPL;  g_curPL = priceForBull;
            
            // Bullish: price LL + osc HL (higher low)
            if(g_curPL < g_prevPL && g_curOL > g_prevOL && g_prevPL != 0)
            {
               g_bullDiv[pIdx]    = g_osc[pIdx] - 0.03;  // additive offset below oscillator
               g_divConfBar[pIdx] = InpDivBars;           // bars until confirmation
            }
         }
         
         if(oPivHi)
         {
            g_prevOH = g_curOH;  g_curOH = g_osc[pIdx];
            g_prevPH = g_curPH;  g_curPH = priceForBear;  // FIX: was prevPH = src[pIdx]
            
            // Bearish: price HH + osc LH (lower high)
            if(g_curPH > g_prevPH && g_curOH < g_prevOH && g_prevPH != 0)
            {
               g_bearDiv[pIdx]    = g_osc[pIdx] + 0.03;  // additive offset above oscillator
               g_divConfBar[pIdx] = InpDivBars;
            }
         }
      }
   }
   
   return rates_total;
}
//+------------------------------------------------------------------+
