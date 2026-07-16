//+------------------------------------------------------------------+
//|                                      Trendlines with Breaks.mq5   |
//|                              Ported from LuxAlgo Pine Script v5   |
//|           Original: "Trendlines with Breaks [LuxAlgo]"           |
//+------------------------------------------------------------------+
#property copyright   "Ported from LuxAlgo (CC BY-NC-SA 4.0)"
#property version     "1.00"
#property description ":: Trendlines with Breaks ::"
#property description "Auto-drawn trendlines from pivot highs/lows with"
#property description "configurable slope method and breakout signals."

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

// ── Plot 0: Upper Trendline ─────────────────────────────────────────────────
#property indicator_label1  "Upper Trendline"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrTeal
#property indicator_width1  2
#property indicator_style1  STYLE_DASH

// ── Plot 1: Lower Trendline ─────────────────────────────────────────────────
#property indicator_label2  "Lower Trendline"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_style2  STYLE_DASH

// ── Plot 2: Upper Break Marker ──────────────────────────────────────────────
#property indicator_label3  "Upper Break"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrTeal
#property indicator_width3  1

// ── Plot 3: Lower Break Marker ──────────────────────────────────────────────
#property indicator_label4  "Lower Break"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrangeRed
#property indicator_width4  1

// ── Enums ───────────────────────────────────────────────────────────────────
enum ENUM_SLOPE_METHOD
{
   SLOPE_ATR,     // ATR
   SLOPE_STDEV,   // Standard Deviation
   SLOPE_LINREG   // Linear Regression
};

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Swing Detection ═══"
input int                          InpLength        = 14;                 // Swing Detection Lookback
input double                       InpMult          = 1.0;                // Slope Multiplier
input ENUM_SLOPE_METHOD            InpSlopeMethod   = SLOPE_ATR;          // Slope Calculation Method
input bool                         InpBackpaint     = true;               // Backpainting (offset display)

input group                        "═══ Style ═══"
input color                        InpUpColor       = clrTeal;            // Up Trendline Color
input color                        InpDnColor       = clrOrangeRed;       // Down Trendline Color
input bool                         InpShowExt       = true;               // Show Extended Lines

input group                        "═══ Alerts ═══"
input bool                         InpShowAlerts    = true;               // Enable Alerts

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_bufUpper[];     // 0  Upper trendline plot values
double g_bufLower[];     // 1  Lower trendline plot values
double g_bufUpBreak[];   // 2  Upper break markers
double g_bufDnBreak[];   // 3  Lower break markers

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix = "LXTL_";
double g_upper     = 0.0;
double g_lower     = 0.0;
double g_slope_ph  = 0.0;
double g_slope_pl  = 0.0;
int    g_upos      = 0;
int    g_dnos      = 0;
int    g_upos_prev = 0;
int    g_dnos_prev = 0;

// Extended line object names
string g_uptl_name;
string g_dntl_name;

//+------------------------------------------------------------------+
//| Pivot High: highest of length bars on each side                   |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], int idx, int len)
{
   int sz = ArraySize(h);
   if(idx - len < 0 || idx + len >= sz) return false;

   double val = h[idx];
   for(int i = idx - len; i <= idx + len; i++)
      if(i != idx && h[i] >= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Pivot Low: lowest of length bars on each side                     |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &l[], int idx, int len)
{
   int sz = ArraySize(l);
   if(idx - len < 0 || idx + len >= sz) return false;

   double val = l[idx];
   for(int i = idx - len; i <= idx + len; i++)
      if(i != idx && l[i] <= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| ATR (SMA-based)                                                   |
//+------------------------------------------------------------------+
double CalcATR(const double &h[], const double &l[], const double &c[],
               int period, int idx)
{
   if(idx < period) return 0;
   double sum = 0;
   for(int i = idx - period + 1; i <= idx; i++)
      sum += MathMax(h[i] - l[i],
                     MathMax(MathAbs(h[i] - c[i - 1]),
                             MathAbs(l[i] - c[i - 1])));
   return sum / period;
}

//+------------------------------------------------------------------+
//| Standard Deviation                                                |
//+------------------------------------------------------------------+
double CalcStdDev(const double &src[], int period, int idx)
{
   if(idx < period) return 0;

   double sum = 0, sumSq = 0;
   for(int i = idx - period + 1; i <= idx; i++)
   { sum += src[i]; sumSq += src[i] * src[i]; }

   double mean = sum / period;
   return MathSqrt(sumSq / period - mean * mean);
}

//+------------------------------------------------------------------+
//| SMA helper                                                        |
//+------------------------------------------------------------------+
double SMA(const double &arr[], int period, int idx)
{
   if(idx < period - 1) return 0;
   double sum = 0;
   for(int i = idx - period + 1; i <= idx; i++) sum += arr[i];
   return sum / period;
}

//+------------------------------------------------------------------+
//| Slope: Linreg method                                              |
//+------------------------------------------------------------------+
double CalcLinregSlope(const double &src[], int period, int idx)
{
   if(idx < period) return 0;

   // sum(x*y) - sum(x)*sum(y)/n, where x = bar index, y = price
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

   for(int i = idx - period + 1; i <= idx; i++)
   {
      double x = (double)i;
      double y = src[i];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }

   double n = (double)period;
   double numerator   = sumXY - sumX * sumY / n;
   double denominator = sumX2 - sumX * sumX / n;

   if(denominator == 0) return 0;
   return MathAbs(numerator / denominator) / 2.0;
}

//+------------------------------------------------------------------+
//| Compute slope based on selected method                            |
//+------------------------------------------------------------------+
double CalcSlope(const double &h[], const double &l[], const double &c[],
                 int period, int idx, double mult)
{
   switch(InpSlopeMethod)
   {
      case SLOPE_ATR:
         return CalcATR(h, l, c, period, idx) / period * mult;

      case SLOPE_STDEV:
         return CalcStdDev(c, period, idx) / period * mult;

      case SLOPE_LINREG:
         return CalcLinregSlope(c, period, idx) * mult;

      default:
         return CalcATR(h, l, c, period, idx) / period * mult;
   }
}

//+------------------------------------------------------------------+
//| Create or update an extended trendline object                     |
//+------------------------------------------------------------------+
void UpdateExtLine(string name, int barIdx1, double price1,
                   int barIdx2, double price2,
                   const datetime &time[], color clr, bool create)
{
   int sz = ArraySize(time);
   if(barIdx1 < 0 || barIdx1 >= sz || barIdx2 < 0 || barIdx2 >= sz) return;

   if(create)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_TREND, 0, time[barIdx1], price1,
                      time[barIdx2], price2);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
   }
   else
   {
      if(ObjectFind(0, name) >= 0)
      {
         ObjectMove(0, name, 0, time[barIdx1], price1);
         ObjectMove(0, name, 1, time[barIdx2], price2);
      }
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_bufUpper,   INDICATOR_DATA);
   SetIndexBuffer(1, g_bufLower,   INDICATOR_DATA);
   SetIndexBuffer(2, g_bufUpBreak, INDICATOR_DATA);
   SetIndexBuffer(3, g_bufDnBreak, INDICATOR_DATA);

   // Upper line
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(0, PLOT_SHIFT, InpBackpaint ? -InpLength : 0);

   // Lower line
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_SHIFT, InpBackpaint ? -InpLength : 0);

   // Break markers
   PlotIndexSetInteger(2, PLOT_ARROW, 108);  // ● upper break
   PlotIndexSetInteger(3, PLOT_ARROW, 108);  // ● lower break

   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("LuxAlgo TL(%d)", InpLength));

   // Init state
   g_upper    = 0;
   g_lower    = 0;
   g_slope_ph = 0;
   g_slope_pl = 0;
   g_upos     = 0;
   g_dnos     = 0;
   g_upos_prev = 0;
   g_dnos_prev = 0;

   g_uptl_name = g_prefix + "UPTL";
   g_dntl_name = g_prefix + "DNTL";

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ObjectFind(0, g_uptl_name) >= 0) ObjectDelete(0, g_uptl_name);
   if(ObjectFind(0, g_dntl_name) >= 0) ObjectDelete(0, g_dntl_name);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
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
   int minBars = InpLength * 2 + 5;
   if(rates_total < minBars) return 0;

   int start = (prev_calculated > 0) ? prev_calculated - 1 : minBars;
   if(start < minBars) start = minBars;

   int offset = InpBackpaint ? InpLength : 0;
   int lastIdx = rates_total - 1;

   // Reset state on fresh load
   if(prev_calculated == 0)
   {
      ArrayInitialize(g_bufUpper,   EMPTY_VALUE);
      ArrayInitialize(g_bufLower,   EMPTY_VALUE);
      ArrayInitialize(g_bufUpBreak, EMPTY_VALUE);
      ArrayInitialize(g_bufDnBreak, EMPTY_VALUE);
      g_upper    = 0;
      g_lower    = 0;
      g_slope_ph = 0;
      g_slope_pl = 0;
      g_upos     = 0;
      g_dnos     = 0;
      g_upos_prev = 0;
      g_dnos_prev = 0;
   }

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // ── Pivot Detection ────────────────────────────────────────────────────
      bool ph = IsPivotHigh(high, i, InpLength);
      bool pl = IsPivotLow(low, i, InpLength);

      // ── Slope Calculation ──────────────────────────────────────────────────
      double slope = CalcSlope(high, low, close, InpLength, i, InpMult);

      g_slope_ph = ph ? slope : g_slope_ph;
      g_slope_pl = pl ? slope : g_slope_pl;

      // ── Trendline Tracking ─────────────────────────────────────────────────
      g_upper = ph ? high[i] : g_upper - g_slope_ph;
      g_lower = pl ? low[i]  : g_lower + g_slope_pl;

      // ── Breakout Detection ─────────────────────────────────────────────────
      g_upos_prev = g_upos;
      g_dnos_prev = g_dnos;

      g_upos = ph ? 0 : (close[i] > g_upper - g_slope_ph * InpLength) ? 1 : g_upos;
      g_dnos = pl ? 0 : (close[i] < g_lower + g_slope_pl * InpLength) ? 1 : g_dnos;

      // ── Plot Values (backpainted) ──────────────────────────────────────────
      double upperPlot = InpBackpaint ? g_upper : g_upper - g_slope_ph * InpLength;
      double lowerPlot = InpBackpaint ? g_lower : g_lower + g_slope_pl * InpLength;

      g_bufUpper[i] = ph ? EMPTY_VALUE : upperPlot;
      g_bufLower[i] = pl ? EMPTY_VALUE : lowerPlot;

      // ── Break Markers ──────────────────────────────────────────────────────
      if(g_upos > g_upos_prev && g_upos_prev == 0)
         g_bufUpBreak[i] = low[i];

      if(g_dnos > g_dnos_prev && g_dnos_prev == 0)
         g_bufDnBreak[i] = high[i];

      // ── Extended Line Objects (only reposition on new pivots) ──────────────
      if(InpShowExt)
      {
         if(ph)
         {
            int n1 = i - offset;
            int n2 = i - offset + 1;
            double p1 = InpBackpaint ? high[i] : g_upper - g_slope_ph * InpLength;
            double p2 = InpBackpaint ? high[i] - g_slope_ph
                                     : g_upper - g_slope_ph * (InpLength + 1);
            UpdateExtLine(g_uptl_name, n1, p1, n2, p2, time,
                          InpUpColor, ObjectFind(0, g_uptl_name) < 0);
         }

         if(pl)
         {
            int n1 = i - offset;
            int n2 = i - offset + 1;
            double p1 = InpBackpaint ? low[i] : g_lower + g_slope_pl * InpLength;
            double p2 = InpBackpaint ? low[i] + g_slope_pl
                                     : g_lower + g_slope_pl * (InpLength + 1);
            UpdateExtLine(g_dntl_name, n1, p1, n2, p2, time,
                          InpDnColor, ObjectFind(0, g_dntl_name) < 0);
         }
      }

      // ── Alerts ─────────────────────────────────────────────────────────────
      if(InpShowAlerts && i == lastIdx)
      {
         if(g_upos > g_upos_prev && g_upos_prev == 0)
            Alert("LuxAlgo TL: UPWARD BREAKOUT | ", _Symbol,
                  " | ", DoubleToString(close[i], _Digits));

         if(g_dnos > g_dnos_prev && g_dnos_prev == 0)
            Alert("LuxAlgo TL: DOWNWARD BREAKOUT | ", _Symbol,
                  " | ", DoubleToString(close[i], _Digits));
      }
   }

   // ── Hide extended lines if toggled off ────────────────────────────────────
   if(!InpShowExt)
   {
      if(ObjectFind(0, g_uptl_name) >= 0) ObjectDelete(0, g_uptl_name);
      if(ObjectFind(0, g_dntl_name) >= 0) ObjectDelete(0, g_dntl_name);
   }

   return rates_total;
}
//+------------------------------------------------------------------+
