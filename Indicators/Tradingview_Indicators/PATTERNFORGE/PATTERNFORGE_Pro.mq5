//+------------------------------------------------------------------+
//|                                        PatternForge Pro Ind.mq5   |
//|                    Ported from Pine Script v5 → MQL5              |
//|                    Original: PATTERNFORGE_5_24.pine              |
//|                    v1.3: Full audit fix — pivot engine, flags,    |
//|                          triangles, alerts, objects, validation   |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script — IRUNTV"
#property version     "1.30"
#property description ":: PatternForge Pro — v1.3 ::"
#property description "H&S, Inv H&S, Double Top/Bot, Triangles, Flags/Pennants"
#property description "v1.3: Full audit remediation — see v1.3 changelog"

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "H&S Top"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_width1  3

#property indicator_label2  "Inv H&S Bot"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  3

#property indicator_label3  "Double Top"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrange
#property indicator_width3  2

#property indicator_label4  "Double Bottom"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrAqua
#property indicator_width4  2

#property indicator_label5  "Triangle/Wedge"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrYellow
#property indicator_width5  2

#property indicator_label6  "Flag/Pennant"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrMagenta
#property indicator_width6  2

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Pattern Selection ═══"
input bool                         InpDetectHS     = true;               // Detect H&S
input bool                         InpDetectIHS    = true;               // Detect Inverse H&S
input bool                         InpDetectDT     = true;               // Detect Double Top
input bool                         InpDetectDB     = true;               // Detect Double Bottom
input bool                         InpDetectTri    = true;               // Detect Triangles/Wedges
input bool                         InpDetectFlag   = true;               // Detect Flags/Pennants

input group                        "═══ Detection ═══"
input int                          InpPivotLook    = 5;                  // Pivot Lookback (bars)  (min:1)
input double                       InpTolerancePct = 0.5;                // Price Tolerance (%)    (min:0)
input int                          InpMaxPattern   = 100;                // Max Pattern Bars       (min:10)
input int                          InpMinPoleBars  = 5;                  // Min Flag Pole Bars     (min:2)
input double                       InpMinPolePct   = 1.5;                // Min Pole Move %        (min:0.1)
input double                       InpMinRetracePct = 10.0;              // Min Retracement % (DT/DB)
input bool                         InpReqNeckBreak = true;               // Require Neckline Break (H&S)

input group                        "═══ Visuals ═══"
input bool                         InpShowLines    = true;               // Show Pattern Lines
input bool                         InpShowLabels   = true;               // Show Labels
input bool                         InpShowAlerts   = true;               // Enable Alerts
input bool                         InpVolConfirm   = true;               // Require Volume Confirmation
input int                          InpInstanceID   = 0;                  // Instance ID (for multi-copy)
input int                          InpMaxObjects   = 500;                // Max Drawing Objects

input group                        "═══ Flag/Pennant ═══"
input int                          InpMaxConsolBars = 30;               // Max Consolidation Bars
input double                       InpMaxConsolPct  = 3.0;               // Max Consolidation Range %

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_hs[];          // 0
double g_ihs[];         // 1
double g_dt[];          // 2
double g_db[];          // 3
double g_tri[];         // 4
double g_flag[];        // 5

string g_prefix;

// ── GLOBAL persistent pivot storage (circular ring buffers) ─────────────────
#define MAX_PIVOTS 100
struct Piv { int idx; double val; datetime time; };
Piv g_phBuf[MAX_PIVOTS];    // pivot highs
Piv g_plBuf[MAX_PIVOTS];    // pivot lows
int  g_phCount = 0;         // number of stored highs
int  g_plCount = 0;         // number of stored lows
int  g_phWrite = 0;         // ring-buffer write cursor
int  g_plWrite = 0;

// ── Alert tracking per pattern category (prevents repeat alerts) ────────────
string g_lastAlertKeys[6];  // indexed by pattern type: 0=HS,1=IHS,2=DT,3=DB,4=TRI,5=FLAG

// ── Object tracking for pruning ─────────────────────────────────────────────
int g_objectCount = 0;

//+------------------------------------------------------------------+
//| Helpers — pivot detection (array is NOT series: 0=oldest)         |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], int lr, int idx, int total)
{
   if(idx-lr < 0 || idx+lr >= total) return false;
   double v = h[idx];
   for(int i = idx-lr; i < idx; i++) if(h[i] > v) return false;
   for(int i = idx+1; i <= idx+lr; i++) if(h[i] >= v) return false;
   return true;
}

bool IsPivotLow(const double &l[], int lr, int idx, int total)
{
   if(idx-lr < 0 || idx+lr >= total) return false;
   double v = l[idx];
   for(int i = idx-lr; i < idx; i++) if(l[i] < v) return false;
   for(int i = idx+1; i <= idx+lr; i++) if(l[i] <= v) return false;
   return true;
}

// Check if a pivot datetime already exists in the given ring buffer
bool PivotTimeExists(const Piv &buf[], int count, int write, datetime t)
{
   for(int i = 0; i < count; i++)
   {
      int actual = (write - count + i + MAX_PIVOTS) % MAX_PIVOTS;
      if(actual < 0) actual += MAX_PIVOTS;
      if(buf[actual].time == t) return true;
   }
   return false;
}

// Add a pivot to the ring buffer (with datetime deduplication)
void AddPivotHigh(int idx, double val, datetime time)
{
   if(PivotTimeExists(g_phBuf, g_phCount, g_phWrite, time)) return;
   g_phBuf[g_phWrite].idx = idx;
   g_phBuf[g_phWrite].val = val;
   g_phBuf[g_phWrite].time = time;
   g_phWrite = (g_phWrite + 1) % MAX_PIVOTS;
   if(g_phCount < MAX_PIVOTS) g_phCount++;
}

void AddPivotLow(int idx, double val, datetime time)
{
   if(PivotTimeExists(g_plBuf, g_plCount, g_plWrite, time)) return;
   g_plBuf[g_plWrite].idx = idx;
   g_plBuf[g_plWrite].val = val;
   g_plBuf[g_plWrite].time = time;
   g_plWrite = (g_plWrite + 1) % MAX_PIVOTS;
   if(g_plCount < MAX_PIVOTS) g_plCount++;
}

// Get pivot by chronological index (0 = oldest among stored, count-1 = newest)
Piv GetPivotHigh(int relIdx)
{
   int actual = (g_phWrite - g_phCount + relIdx + MAX_PIVOTS) % MAX_PIVOTS;
   if(actual < 0) actual += MAX_PIVOTS;
   return g_phBuf[actual];
}

Piv GetPivotLow(int relIdx)
{
   int actual = (g_plWrite - g_plCount + relIdx + MAX_PIVOTS) % MAX_PIVOTS;
   if(actual < 0) actual += MAX_PIVOTS;
   return g_plBuf[actual];
}

//+------------------------------------------------------------------+
//| Local volume average around a given bar index                     |
//+------------------------------------------------------------------+
double LocalAvgVolume(const long &tv[], int barIdx, int lookback, int total)
{
   int vStart = MathMax(0, barIdx - lookback);
   int vEnd   = MathMin(total - 1, barIdx);
   if(vStart >= vEnd) return (double)tv[barIdx];
   
   double sum = 0;
   for(int i = vStart; i <= vEnd; i++) sum += (double)tv[i];
   return sum / (double)(vEnd - vStart + 1);
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // ── Input validation ─────────────────────────────────────────────
   if(InpPivotLook < 1 || InpTolerancePct < 0 || InpMaxPattern < 10 ||
      InpMinPoleBars < 2 || InpMinPolePct < 0.1)
   {
      Print("PatternForge: Invalid input parameters. Check PivotLook(>=1), Tolerance(>=0), MaxPattern(>=10), MinPoleBars(>=2), MinPolePct(>=0.1)");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // ── Unique per-instance prefix ───────────────────────────────────
   g_prefix = "PF_" + IntegerToString((int)ChartID()) + "_" +
              _Symbol + "_" + IntegerToString(_Period) + "_" +
              IntegerToString(InpInstanceID) + "_";
   
   // ── Explicit array direction: 0=oldest, rates_total-1=newest ────
   ArraySetAsSeries(g_hs, false);
   ArraySetAsSeries(g_ihs, false);
   ArraySetAsSeries(g_dt, false);
   ArraySetAsSeries(g_db, false);
   ArraySetAsSeries(g_tri, false);
   ArraySetAsSeries(g_flag, false);
   
   SetIndexBuffer(0, g_hs,   INDICATOR_DATA);
   SetIndexBuffer(1, g_ihs,  INDICATOR_DATA);
   SetIndexBuffer(2, g_dt,   INDICATOR_DATA);
   SetIndexBuffer(3, g_db,   INDICATOR_DATA);
   SetIndexBuffer(4, g_tri,  INDICATOR_DATA);
   SetIndexBuffer(5, g_flag, INDICATOR_DATA);
   
   PlotIndexSetInteger(0, PLOT_ARROW, 242); PlotIndexSetInteger(1, PLOT_ARROW, 241);
   PlotIndexSetInteger(2, PLOT_ARROW, 242); PlotIndexSetInteger(3, PLOT_ARROW, 241);
   PlotIndexSetInteger(4, PLOT_ARROW, 251); PlotIndexSetInteger(5, PLOT_ARROW, 252);
   for(int p = 0; p < 6; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "PF Pro v1.3");
   
   g_phCount = 0; g_plCount = 0;
   g_phWrite = 0; g_plWrite = 0;
   g_objectCount = 0;
   
   for(int k = 0; k < 6; k++) g_lastAlertKeys[k] = "";
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r) { CleanupObjects(); }

//+------------------------------------------------------------------+
//| OnCalculate  (array direction: 0=oldest, rates_total-1=newest)    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calc,
                const datetime &t[], const double &o[], const double &h[],
                const double &l[], const double &c[], const long &tv[],
                const long &v[], const int &sp[])
{
   // ── Ensure arrays use non-series indexing (0=oldest) ──────────────
   ArraySetAsSeries(t, false);
   ArraySetAsSeries(h, false);
   ArraySetAsSeries(l, false);
   ArraySetAsSeries(c, false);
   ArraySetAsSeries(tv, false);
   
   int minB = InpMaxPattern + InpPivotLook * 3 + 20;
   if(rates_total < minB) return 0;
   
   int start = (prev_calc > 0) ? prev_calc - 1 : 0;
   if(start < minB) start = minB;
   
   // ── New-bar detection ────────────────────────────────────────────
   static datetime lastBarTime = 0;
   bool isNewBar = (t[rates_total-1] != lastBarTime);
   if(isNewBar) lastBarTime = t[rates_total-1];
   
   // ── Pivot scanning ───────────────────────────────────────────────
   if(prev_calc == 0)
   {
      // Full rebuild on first load
      g_phCount = 0; g_plCount = 0;
      g_phWrite = 0; g_plWrite = 0;
      
      for(int i = minB; i < rates_total; i++)
      {
         if(IsPivotHigh(h, InpPivotLook, i, rates_total))
            AddPivotHigh(i, h[i], t[i]);
         if(IsPivotLow(l, InpPivotLook, i, rates_total))
            AddPivotLow(i, l[i], t[i]);
      }
   }
   else
   {
      // Incremental: scan backward far enough for newly confirmable pivots
      // A pivot at index i is confirmable only when i + InpPivotLook < rates_total
      // So newly confirmable range: [rates_total - 1 - InpPivotLook - (newBars), rates_total - 1 - InpPivotLook]
      int newBars = rates_total - prev_calc;
      int pivotStart = MathMax(minB, prev_calc - InpPivotLook - 2);
      int pivotEnd   = rates_total - 1 - InpPivotLook;
      
      for(int i = pivotStart; i <= pivotEnd && !IsStopped(); i++)
      {
         if(IsPivotHigh(h, InpPivotLook, i, rates_total))
            AddPivotHigh(i, h[i], t[i]);
         if(IsPivotLow(l, InpPivotLook, i, rates_total))
            AddPivotLow(i, l[i], t[i]);
      }
   }
   
   // ── Reset arrow buffers ──────────────────────────────────────────
   for(int i = start; i < rates_total; i++)
   {
      g_hs[i] = EMPTY_VALUE; g_ihs[i] = EMPTY_VALUE;
      g_dt[i] = EMPTY_VALUE; g_db[i] = EMPTY_VALUE;
      g_tri[i] = EMPTY_VALUE; g_flag[i] = EMPTY_VALUE;
   }
   
   double tol = InpTolerancePct / 100.0;
   int phN = g_phCount, plN = g_plCount;
   
   // ── Search recent pivot combinations (last N pivots, not just last 2-3) ──
   #define HS_COMBO_DEPTH  10
   #define DT_COMBO_DEPTH  8
   #define TRI_COMBO_DEPTH 8
   
   // ══════════════════════════════════════════════════════════════════════
   // H&S Detection — search last HS_COMBO_DEPTH highs for valid combos
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectHS && phN >= 3)
   {
      int searchStart = MathMax(0, phN - HS_COMBO_DEPTH);
      bool hsFound = false;
      
      for(int a = searchStart; a < phN - 2 && !hsFound; a++)
      {
         for(int b = a + 1; b < phN - 1 && !hsFound; b++)
         {
            for(int c = b + 1; c < phN && !hsFound; c++)
            {
               Piv ls = GetPivotHigh(a), hd = GetPivotHigh(b), rs = GetPivotHigh(c);
               
               // Pattern span check
               int patternSpan = rs.idx - ls.idx;
               if(patternSpan > InpMaxPattern) continue;
               
               // Age check: right shoulder must be recent enough
               if(rs.idx < rates_total - 1 - InpMaxPattern) continue;
               
               if(!(hd.val > ls.val && hd.val > rs.val)) continue;
               if(MathAbs(ls.val - rs.val) / MathMax(ls.val, 0.0001) >= tol) continue;
               
               // Volume confirmation (local to rs)
               bool volOk = true;
               if(InpVolConfirm)
               {
                  double localAvg = LocalAvgVolume(tv, rs.idx, 20, rates_total);
                  volOk = (tv[rs.idx] >= localAvg * 0.8);
               }
               if(!volOk) continue;
               
               // Neckline break check
               if(InpReqNeckBreak)
               {
                  // Calculate neckline: lowest lows between LS-HD and HD-RS
                  double neckL = l[ls.idx], neckR = l[rs.idx];
                  for(int i = ls.idx; i <= hd.idx; i++) if(l[i] < neckL) neckL = l[i];
                  for(int i = hd.idx; i <= rs.idx; i++) if(l[i] < neckR) neckR = l[i];
                  
                  // Neckline slope from left to right neck pivot
                  int neckLIdx = ls.idx, neckRIdx = rs.idx;
                  for(int i = ls.idx; i <= hd.idx; i++) if(l[i] <= neckL) neckLIdx = i;
                  for(int i = hd.idx; i <= rs.idx; i++) if(l[i] <= neckR) neckRIdx = i;
                  
                  double neckSlope = (neckRIdx != neckLIdx)
                     ? (neckR - neckL) / (double)(neckRIdx - neckLIdx) : 0;
                  
                  // Check if price broke neckline after RS
                  bool broken = false;
                  for(int i = rs.idx + 1; i < rates_total && !broken; i++)
                  {
                     double neckAtI = neckR + neckSlope * (i - neckRIdx);
                     if(c[i] < neckAtI) broken = true;
                  }
                  if(!broken) continue;
               }
               
               g_hs[rs.idx] = h[rs.idx];
               DrawHS(ls, hd, rs, l, t, rates_total);
               hsFound = true;
               
               string key = "HS_" + IntegerToString((long)ls.time) + "_" + IntegerToString((long)rs.time);
               if(isNewBar && TryAlert(0, key))
                  Alert("PatternForge: H&S Top at " + _Symbol + " " + DoubleToString(h[rs.idx], _Digits));
            }
         }
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // Inverse H&S — search last HS_COMBO_DEPTH lows
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectIHS && plN >= 3)
   {
      int searchStart = MathMax(0, plN - HS_COMBO_DEPTH);
      bool ihsFound = false;
      
      for(int a = searchStart; a < plN - 2 && !ihsFound; a++)
      {
         for(int b = a + 1; b < plN - 1 && !ihsFound; b++)
         {
            for(int c = b + 1; c < plN && !ihsFound; c++)
            {
               Piv ls = GetPivotLow(a), hd = GetPivotLow(b), rs = GetPivotLow(c);
               
               int patternSpan = rs.idx - ls.idx;
               if(patternSpan > InpMaxPattern) continue;
               if(rs.idx < rates_total - 1 - InpMaxPattern) continue;
               
               if(!(hd.val < ls.val && hd.val < rs.val)) continue;
               if(MathAbs(ls.val - rs.val) / MathMax(ls.val, 0.0001) >= tol) continue;
               
               bool volOk = true;
               if(InpVolConfirm)
               {
                  double localAvg = LocalAvgVolume(tv, rs.idx, 20, rates_total);
                  volOk = (tv[rs.idx] >= localAvg * 0.8);
               }
               if(!volOk) continue;
               
               // Neckline break (upside)
               if(InpReqNeckBreak)
               {
                  double neckL = h[ls.idx], neckR = h[rs.idx];
                  int neckLIdx = ls.idx, neckRIdx = rs.idx;
                  for(int i = ls.idx; i <= hd.idx; i++) if(h[i] > neckL) { neckL = h[i]; neckLIdx = i; }
                  for(int i = hd.idx; i <= rs.idx; i++) if(h[i] > neckR) { neckR = h[i]; neckRIdx = i; }
                  
                  double neckSlope = (neckRIdx != neckLIdx)
                     ? (neckR - neckL) / (double)(neckRIdx - neckLIdx) : 0;
                  
                  bool broken = false;
                  for(int i = rs.idx + 1; i < rates_total && !broken; i++)
                  {
                     double neckAtI = neckR + neckSlope * (i - neckRIdx);
                     if(c[i] > neckAtI) broken = true;
                  }
                  if(!broken) continue;
               }
               
               g_ihs[rs.idx] = l[rs.idx];
               DrawIHS(ls, hd, rs, h, t, rates_total);
               ihsFound = true;
               
               string key = "IHS_" + IntegerToString((long)ls.time) + "_" + IntegerToString((long)rs.time);
               if(isNewBar && TryAlert(1, key))
                  Alert("PatternForge: Inv H&S at " + _Symbol + " " + DoubleToString(l[rs.idx], _Digits));
            }
         }
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // Double Top — search last DT_COMBO_DEPTH highs
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectDT && phN >= 2)
   {
      int searchStart = MathMax(0, phN - DT_COMBO_DEPTH);
      bool dtFound = false;
      
      for(int a = searchStart; a < phN - 1 && !dtFound; a++)
      {
         for(int b = a + 1; b < phN && !dtFound; b++)
         {
            Piv p1 = GetPivotHigh(a), p2 = GetPivotHigh(b);
            
            int span = p2.idx - p1.idx;
            if(span > InpMaxPattern) continue;
            if(p2.idx < rates_total - 1 - InpMaxPattern) continue;
            if(span <= InpPivotLook * 2) continue;
            if(MathAbs(p1.val - p2.val) / MathMax(p1.val, 0.0001) >= tol) continue;
            
            // Retracement: find lowest low between peaks
            double retraceLo = l[p1.idx];
            for(int i = p1.idx; i <= p2.idx; i++)
               if(l[i] < retraceLo) retraceLo = l[i];
            
            double retracePct = (MathMax(p1.val, p2.val) - retraceLo) / MathMax(p1.val, 0.0001) * 100;
            if(retracePct < InpMinRetracePct) continue;
            
            bool volOk = true;
            if(InpVolConfirm)
            {
               double localAvg = LocalAvgVolume(tv, p2.idx, 20, rates_total);
               volOk = (tv[p2.idx] >= localAvg * 0.8);
            }
            if(!volOk) continue;
            
            g_dt[p2.idx] = h[p2.idx];
            DrawDouble("DT", p1, p2, clrOrange, "Double Top");
            dtFound = true;
            
            string key = "DT_" + IntegerToString((long)p1.time) + "_" + IntegerToString((long)p2.time);
            if(isNewBar && TryAlert(2, key))
               Alert("PatternForge: Double Top at " + _Symbol + " " + DoubleToString(h[p2.idx], _Digits));
         }
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // Double Bottom — search last DT_COMBO_DEPTH lows
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectDB && plN >= 2)
   {
      int searchStart = MathMax(0, plN - DT_COMBO_DEPTH);
      bool dbFound = false;
      
      for(int a = searchStart; a < plN - 1 && !dbFound; a++)
      {
         for(int b = a + 1; b < plN && !dbFound; b++)
         {
            Piv p1 = GetPivotLow(a), p2 = GetPivotLow(b);
            
            int span = p2.idx - p1.idx;
            if(span > InpMaxPattern) continue;
            if(p2.idx < rates_total - 1 - InpMaxPattern) continue;
            if(span <= InpPivotLook * 2) continue;
            if(MathAbs(p1.val - p2.val) / MathMax(p1.val, 0.0001) >= tol) continue;
            
            // Rally between troughs
            double rallyHi = h[p1.idx];
            for(int i = p1.idx; i <= p2.idx; i++)
               if(h[i] > rallyHi) rallyHi = h[i];
            
            double rallyPct = (rallyHi - MathMin(p1.val, p2.val)) / MathMax(p1.val, 0.0001) * 100;
            if(rallyPct < InpMinRetracePct) continue;
            
            bool volOk = true;
            if(InpVolConfirm)
            {
               double localAvg = LocalAvgVolume(tv, p2.idx, 20, rates_total);
               volOk = (tv[p2.idx] >= localAvg * 0.8);
            }
            if(!volOk) continue;
            
            g_db[p2.idx] = l[p2.idx];
            DrawDouble("DB", p1, p2, clrAqua, "Double Bot");
            dbFound = true;
            
            string key = "DB_" + IntegerToString((long)p1.time) + "_" + IntegerToString((long)p2.time);
            if(isNewBar && TryAlert(3, key))
               Alert("PatternForge: Double Bottom at " + _Symbol + " " + DoubleToString(l[p2.idx], _Digits));
         }
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // Triangle/Wedge — proper slope/convergence analysis
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectTri && phN >= 2 && plN >= 2)
   {
      int hSearch = MathMax(0, phN - TRI_COMBO_DEPTH);
      int lSearch = MathMax(0, plN - TRI_COMBO_DEPTH);
      bool triFound = false;
      
      for(int a = hSearch; a < phN - 1 && !triFound; a++)
      {
         for(int b = a + 1; b < phN && !triFound; b++)
         {
            for(int c = lSearch; c < plN - 1 && !triFound; c++)
            {
               for(int d = c + 1; d < plN && !triFound; d++)
               {
                  Piv h1 = GetPivotHigh(a), h2 = GetPivotHigh(b);
                  Piv l1 = GetPivotLow(c),  l2 = GetPivotLow(d);
                  
                  // All four pivots must be in chronological order
                  if(!(h1.idx < l1.idx && l1.idx < h2.idx && h2.idx < l2.idx) &&
                     !(l1.idx < h1.idx && h1.idx < l2.idx && l2.idx < h2.idx) &&
                     !(h1.idx < h2.idx && h2.idx < l1.idx && l1.idx < l2.idx) &&
                     !(l1.idx < l2.idx && l2.idx < h1.idx && h1.idx < h2.idx))
                     continue;
                  
                  // Pattern span: earliest to latest of all four
                  int earliest = MathMin(MathMin(h1.idx, h2.idx), MathMin(l1.idx, l2.idx));
                  int latest   = MathMax(MathMax(h1.idx, h2.idx), MathMax(l1.idx, l2.idx));
                  int span = latest - earliest;
                  if(span > InpMaxPattern) continue;
                  
                  // Latest pivot must be recent enough
                  if(latest < rates_total - 1 - InpMaxPattern) continue;
                  
                  // Slope calculations
                  double hSlope = (h2.idx > h1.idx)
                     ? (h2.val - h1.val) / (double)(h2.idx - h1.idx) : 0;
                  double lSlope = (l2.idx > l1.idx)
                     ? (l2.val - l1.val) / (double)(l2.idx - l1.idx) : 0;
                  
                  // Classify: either converging (triangle) or parallel-sloped (wedge)
                  bool converging = false;
                  string triType = "";
                  
                  // Descending triangle: flat-ish highs, rising lows (converging)
                  if(MathAbs(hSlope) < 0.0001 * MathMax(h1.val, 0.0001) && lSlope > 0)
                     { converging = true; triType = "DescTri"; }
                  // Ascending triangle: falling highs, flat-ish lows (converging)
                  else if(hSlope < 0 && MathAbs(lSlope) < 0.0001 * MathMax(l1.val, 0.0001))
                     { converging = true; triType = "AscTri"; }
                  // Symmetrical triangle: falling highs + rising lows (converging)
                  else if(hSlope < 0 && lSlope > 0)
                     { converging = true; triType = "SymTri"; }
                  // Rising wedge: both rising, lower rising faster
                  else if(hSlope > 0 && lSlope > 0 && lSlope > hSlope * 1.2)
                     { converging = true; triType = "RiseWedge"; }
                  // Falling wedge: both falling, upper falling faster
                  else if(hSlope < 0 && lSlope < 0 && hSlope < lSlope * 1.2)
                     { converging = true; triType = "FallWedge"; }
                  
                  if(!converging) continue;
                  
                  // Volume confirmation
                  bool volOk = true;
                  if(InpVolConfirm)
                  {
                     double localAvg = LocalAvgVolume(tv, latest, 20, rates_total);
                     volOk = (tv[latest] >= localAvg * 0.8);
                  }
                  if(!volOk) continue;
                  
                  g_tri[latest] = h[latest];
                  DrawTriangle(h1, h2, l1, l2, triType);
                  triFound = true;
                  
                  // Use earliest pivot's timestamp for stable key
                  datetime earliestTime = t[earliest];
                  string key = "TRI_" + IntegerToString((long)earliestTime) + "_" + triType;
                  if(isNewBar && TryAlert(4, key))
                     Alert("PatternForge: " + triType + " at " + _Symbol + " " + DoubleToString(h[latest], _Digits));
               }
            }
         }
      }
   }
   
   // ══════════════════════════════════════════════════════════════════════
   // Flag/Pennant — correct post-pole consolidation detection
   // ══════════════════════════════════════════════════════════════════════
   if(InpDetectFlag)
   {
      // Cap historical processing: only scan recent bars beyond the initial load
      int flagScanStart = MathMax(start, InpMinPoleBars + InpPivotLook);
      // On first load, only scan recent bars to avoid massive object creation
      if(prev_calc == 0)
         flagScanStart = MathMax(flagScanStart, rates_total - InpMaxPattern * 3);
      
      bool flagFoundThisBar = false;
      
      for(int i = flagScanStart; i < rates_total && !IsStopped() && !flagFoundThisBar; i++)
      {
         int poleEndIdx = i - InpPivotLook;
         int poleStartIdx = poleEndIdx - InpMinPoleBars;
         if(poleStartIdx < 0) continue;
         
         double poleMove = MathAbs(c[poleEndIdx] - c[poleStartIdx]);
         double polePct = poleMove / MathMax(c[poleStartIdx], 0.0001) * 100;
         
         if(polePct < InpMinPolePct) continue;
         
         bool isBull = c[poleEndIdx] > c[poleStartIdx];
         
         // Consolidation zone: AFTER pole end, up to current bar i
         int consolStart = poleEndIdx;
         int consolEnd   = MathMin(i, consolStart + InpMaxConsolBars);
         if(consolEnd - consolStart < 3) continue;  // need some consolidation bars
         
         // Measure consolidation range (correct: between pole end and current)
         double consolHi = h[consolStart], consolLo = l[consolStart];
         for(int j = consolStart; j <= consolEnd; j++)
         {
            if(h[j] > consolHi) consolHi = h[j];
            if(l[j] < consolLo) consolLo = l[j];
         }
         
         double consolRange = (consolHi - consolLo) / MathMax(c[consolStart], 0.0001) * 100;
         if(consolRange > InpMaxConsolPct) continue;
         if(consolRange >= polePct * 0.5) continue;
         
         // Countertrend slope: flag should slope against the pole direction
         double consolSlope = 0;
         if(consolEnd > consolStart)
         {
            double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
            int n = consolEnd - consolStart + 1;
            for(int j = consolStart; j <= consolEnd; j++)
            {
               double x = j - consolStart;
               double y = c[j];
               sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x;
            }
            double denom = n * sumX2 - sumX * sumX;
            if(MathAbs(denom) > 0.0001)
               consolSlope = (n * sumXY - sumX * sumY) / denom;
         }
         
         // Bull flag: pole up, consolidation flat-to-down (countertrend)
         // Bear flag: pole down, consolidation flat-to-up (countertrend)
         if(isBull && consolSlope > 0.001) continue;
         if(!isBull && consolSlope < -0.001) continue;
         
         // Volume confirmation
         bool volOk = true;
         if(InpVolConfirm)
         {
            double localAvg = LocalAvgVolume(tv, i, 20, rates_total);
            volOk = (tv[i] >= localAvg * 0.6);  // flags often have lower vol in consolidation
         }
         if(!volOk) continue;
         
         // Check span against InpMaxPattern
         int flagSpan = i - poleStartIdx;
         if(flagSpan > InpMaxPattern) continue;
         
         g_flag[i] = isBull ? l[i] * 0.998 : h[i] * 1.002;
         DrawFlag(i, isBull, t, c, poleStartIdx, poleEndIdx, consolStart, consolEnd, rates_total);
         flagFoundThisBar = true;
         
         string key = "FLAG_" + IntegerToString((long)t[poleStartIdx]) + "_" + (isBull ? "B" : "S");
         if(isNewBar && TryAlert(5, key))
            Alert("PatternForge: " + (isBull ? "Bull" : "Bear") + " Flag/Pennant at " +
                  _Symbol + " " + EnumToString(_Period) + " " + DoubleToString(c[i], _Digits));
      }
   }
   
   // ── Periodic stale-object pruning ──────────────────────────────────
   static int pruneCounter = 0;
   pruneCounter++;
   if(pruneCounter >= 50)  // every ~50 OnCalculate calls
   {
      PruneStaleObjects(t, rates_total);
      pruneCounter = 0;
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Draw H&S — proper neckline connecting reaction lows               |
//+------------------------------------------------------------------+
void DrawHS(const Piv &ls, const Piv &hd, const Piv &rs, const double &l[], const datetime &t[], int total)
{
   // Use timestamp-based names for stability
   string prefix = g_prefix + "HS_" + IntegerToString((long)ls.time) + "_" + IntegerToString((long)rs.time) + "_";
   
   // Find neckline: lowest lows between LS-HD and HD-RS
   double neckL = l[ls.idx], neckR = l[rs.idx];
   int neckLIdx = ls.idx, neckRIdx = rs.idx;
   
   for(int i = ls.idx; i <= hd.idx; i++)
   {
      if(l[i] < neckL) { neckL = l[i]; neckLIdx = i; }
   }
   for(int i = hd.idx; i <= rs.idx; i++)
   {
      if(l[i] < neckR) { neckR = l[i]; neckRIdx = i; }
   }
   
   if(InpShowLines)
   {
      // Proper neckline: connect the two reaction lows
      DrawLine(prefix + "NECK_", t[neckLIdx], neckL, t[neckRIdx], neckR, C'0xFF,0x57,0x22', STYLE_DASH, 2);
      
      // Shoulder → head connecting lines
      DrawLine(prefix + "LS_HD_", ls.time, ls.val, hd.time, hd.val, C'0xFF,0x57,0x22', STYLE_DOT, 1);
      DrawLine(prefix + "HD_RS_", hd.time, hd.val, rs.time, rs.val, C'0xFF,0x57,0x22', STYLE_DOT, 1);
   }
   
   if(InpShowLabels)
      DrawLabel(prefix + "LBL", rs.time, rs.val, "H&S", C'0xFF,0x57,0x22');
}

//+------------------------------------------------------------------+
//| Draw Inverse H&S — proper neckline connecting reaction highs      |
//+------------------------------------------------------------------+
void DrawIHS(const Piv &ls, const Piv &hd, const Piv &rs, const double &h[], const datetime &t[], int total)
{
   string prefix = g_prefix + "IHS_" + IntegerToString((long)ls.time) + "_" + IntegerToString((long)rs.time) + "_";
   
   // Find neckline: highest highs between LS-HD and HD-RS
   double neckL = h[ls.idx], neckR = h[rs.idx];
   int neckLIdx = ls.idx, neckRIdx = rs.idx;
   
   for(int i = ls.idx; i <= hd.idx; i++)
   {
      if(h[i] > neckL) { neckL = h[i]; neckLIdx = i; }
   }
   for(int i = hd.idx; i <= rs.idx; i++)
   {
      if(h[i] > neckR) { neckR = h[i]; neckRIdx = i; }
   }
   
   if(InpShowLines)
   {
      // Proper neckline: connect the two reaction highs
      DrawLine(prefix + "NECK_", t[neckLIdx], neckL, t[neckRIdx], neckR, C'0x00,0xE6,0x76', STYLE_DASH, 2);
      DrawLine(prefix + "LS_HD_", ls.time, ls.val, hd.time, hd.val, C'0x00,0xE6,0x76', STYLE_DOT, 1);
      DrawLine(prefix + "HD_RS_", hd.time, hd.val, rs.time, rs.val, C'0x00,0xE6,0x76', STYLE_DOT, 1);
   }
   
   if(InpShowLabels)
      DrawLabel(prefix + "LBL", rs.time, rs.val, "Inv H&S", C'0x00,0xE6,0x76');
}

//+------------------------------------------------------------------+
//| Draw Double Top/Bottom — horizontal line + connector              |
//+------------------------------------------------------------------+
void DrawDouble(string typ, const Piv &p1, const Piv &p2, color clr, string label)
{
   string prefix = g_prefix + typ + "_" + IntegerToString((long)p1.time) + "_" + IntegerToString((long)p2.time) + "_";
   
   if(InpShowLines)
   {
      double avg = (p1.val + p2.val) / 2.0;
      DrawLine(prefix + "LINE_", p2.time, avg, p2.time + 30*PeriodSeconds(), avg, clr, STYLE_DASH, 2);
      DrawLine(prefix + "CONN_", p1.time, p1.val, p2.time, p2.val, clr, STYLE_DOT, 1);
   }
   
   if(InpShowLabels)
      DrawLabel(prefix + "LBL", p2.time, p2.val, label, clr);
}

//+------------------------------------------------------------------+
//| Draw Triangle — upper + lower converging trendlines with type     |
//+------------------------------------------------------------------+
void DrawTriangle(const Piv &h1, const Piv &h2, const Piv &l1, const Piv &l2, string triType)
{
   string prefix = g_prefix + "TRI_" + IntegerToString((long)h1.time) + "_" + IntegerToString((long)l2.time) + "_";
   
   if(InpShowLines)
   {
      DrawLine(prefix + "UPPER_", h1.time, h1.val, h2.time, h2.val, C'0xFF,0xEB,0x3B', STYLE_SOLID, 2);
      DrawLine(prefix + "LOWER_", l1.time, l1.val, l2.time, l2.val, C'0xFF,0xEB,0x3B', STYLE_SOLID, 2);
      
      // Extend both lines right (projection)
      int extBars = 10;
      datetime extT = MathMax(h2.time, l2.time) + extBars * PeriodSeconds();
      double upperSlope = (h2.idx > h1.idx) ? (h2.val - h1.val) / (double)(h2.idx - h1.idx) : 0;
      double lowerSlope = (l2.idx > l1.idx) ? (l2.val - l1.val) / (double)(l2.idx - l1.idx) : 0;
      double upperExt = h2.val + upperSlope * extBars;
      double lowerExt = l2.val + lowerSlope * extBars;
      DrawLine(prefix + "UPEXT_", h2.time, h2.val, extT, upperExt, C'0xFF,0xEB,0x3B', STYLE_DOT, 1);
      DrawLine(prefix + "LOEXT_", l2.time, l2.val, extT, lowerExt, C'0xFF,0xEB,0x3B', STYLE_DOT, 1);
   }
   
   if(InpShowLabels)
   {
      datetime latestT = MathMax(h2.time, l2.time);
      double latestP = MathMax(h2.val, l2.val);
      DrawLabel(prefix + "LBL", latestT, latestP, triType, C'0xFF,0xEB,0x3B');
   }
}

//+------------------------------------------------------------------+
//| Draw Flag — pole line + consolidation channel (post-pole zone)    |
//+------------------------------------------------------------------+
void DrawFlag(int bar, bool isBull, const datetime &t[], const double &c[],
              int poleStartIdx, int poleEndIdx, int consolStartIdx, int consolEndIdx, int total)
{
   string prefix = g_prefix + "FLAG_" + IntegerToString((long)t[poleStartIdx]) + "_" +
                   IntegerToString((long)t[bar]) + "_";
   datetime barT = t[bar];
   double barC = c[bar];
   color clr = clrMagenta;
   
   if(InpShowLines)
   {
      // Pole line: from pole start to pole end
      DrawLine(prefix + "POLE_", t[poleStartIdx], c[poleStartIdx], t[poleEndIdx], c[poleEndIdx],
               C'0xCE,0x93,0xD8', STYLE_SOLID, 2);
      
      // Consolidation channel: from pole end to current bar
      double consolHi = c[consolStartIdx], consolLo = c[consolStartIdx];
      for(int j = consolStartIdx; j <= consolEndIdx; j++)
      {
         if(c[j] > consolHi) consolHi = c[j];
         if(c[j] < consolLo) consolLo = c[j];
      }
      
      // Draw upper and lower channel boundaries
      DrawLine(prefix + "CHANHI_", t[consolStartIdx], consolHi, t[consolEndIdx], consolHi,
               isBull ? C'0x00,0xE6,0x76' : C'0xF4,0x43,0x36', STYLE_DASH, 1);
      DrawLine(prefix + "CHANLO_", t[consolStartIdx], consolLo, t[consolEndIdx], consolLo,
               isBull ? C'0x00,0xE6,0x76' : C'0xF4,0x43,0x36', STYLE_DASH, 1);
   }
   
   if(InpShowLabels)
      DrawLabel(prefix + "LBL", barT, isBull ? barC * 0.998 : barC * 1.002,
                isBull ? "Bull Flag" : "Bear Flag", clr);
}

//+------------------------------------------------------------------+
//| Low-level draw helpers (with error checking + object cap)         |
//+------------------------------------------------------------------+
void DrawLine(string prefix, datetime t1, double p1, datetime t2, double p2, color clr, int style, int width)
{
   if(g_objectCount >= InpMaxObjects) return;
   
   string nm = prefix + "L";
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   
   if(!ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      PrintFormat("PatternForge: Failed to create line %s, error %d", nm, GetLastError());
      return;
   }
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   g_objectCount++;
}

void DrawLabel(string prefix, datetime t, double price, string text, color clr)
{
   if(g_objectCount >= InpMaxObjects) return;
   
   string nm = prefix + "T";
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   
   if(!ObjectCreate(0, nm, OBJ_TEXT, 0, t, price))
   {
      PrintFormat("PatternForge: Failed to create label %s, error %d", nm, GetLastError());
      return;
   }
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   g_objectCount++;
}

//+------------------------------------------------------------------+
//| Alert sender — per-pattern-category deduplication by stable key   |
//+------------------------------------------------------------------+
bool TryAlert(int category, string patternKey)
{
   // categories: 0=HS, 1=IHS, 2=DT, 3=DB, 4=TRI, 5=FLAG
   if(!InpShowAlerts) return false;
   if(category < 0 || category >= 6) return false;
   
   if(g_lastAlertKeys[category] == patternKey) return false;  // already alerted for this pattern
   g_lastAlertKeys[category] = patternKey;
   return true;
}

//+------------------------------------------------------------------+
//| Prune stale objects (patterns older than InpMaxPattern)           |
//+------------------------------------------------------------------+
void PruneStaleObjects(const datetime &t[], int total)
{
   if(total < 1) return;
   datetime cutoff = t[total - 1] - InpMaxPattern * PeriodSeconds();
   int removed = 0;
   
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) != 0) continue;
      
      // Check if object's anchor time is stale
      datetime objTime = 0;
      if(!ObjectGetInteger(0, n, OBJPROP_TIME, 0, objTime)) continue;
      
      if(objTime < cutoff)
      {
         ObjectDelete(0, n);
         removed++;
         g_objectCount--;
      }
   }
   
   if(removed > 0) ChartRedraw();
}

//+------------------------------------------------------------------+
//| Cleanup on deinit                                                 |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, g_prefix) == 0) ObjectDelete(0, n);
   }
   g_objectCount = 0;
   ChartRedraw();
}
//+------------------------------------------------------------------+
