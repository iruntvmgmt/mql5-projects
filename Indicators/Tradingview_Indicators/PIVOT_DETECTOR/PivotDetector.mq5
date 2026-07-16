//+------------------------------------------------------------------+
//|                                               PivotDetector.mq5  |
//|                                    Pivot Detection System v1.0    |
//|                    Detects swing pivots, S/R levels, HH/HL/LH/LL  |
//+------------------------------------------------------------------+
#property copyright   "Pivot Detector"
#property version     "1.00"
#property description ":: PIVOT DETECTOR ::"
#property description "Multi-strength pivot detection with S/R level projections,"
#property description "HH/HL/LH/LL swing classification, and alert system."

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

// ── Plot 0: Pivot High (Major) ──────────────────────────────────────────────
#property indicator_label1  "Pivot High"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  3

// ── Plot 1: Pivot Low (Major) ───────────────────────────────────────────────
#property indicator_label2  "Pivot Low"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  3

// ── Plot 2: Pivot High (Minor) ──────────────────────────────────────────────
#property indicator_label3  "Minor Pivot High"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLightSteelBlue
#property indicator_width3  2

// ── Plot 3: Pivot Low (Minor) ───────────────────────────────────────────────
#property indicator_label4  "Minor Pivot Low"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLightCoral
#property indicator_width4  2

// ── Plot 4: Higher High ─────────────────────────────────────────────────────
#property indicator_label5  "Higher High"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLimeGreen
#property indicator_width5  2

// ── Plot 5: Lower High ──────────────────────────────────────────────────────
#property indicator_label6  "Lower High"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrOrange
#property indicator_width6  2

// ── Plot 6: Higher Low ──────────────────────────────────────────────────────
#property indicator_label7  "Higher Low"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrMediumSpringGreen
#property indicator_width7  2

// ── Plot 7: Lower Low ───────────────────────────────────────────────────────
#property indicator_label8  "Lower Low"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrTomato
#property indicator_width8  2

// ── Enums ───────────────────────────────────────────────────────────────────

// Pivot detection mode
enum ENUM_PIVOT_MODE
{
   PIVOT_MODE_STANDARD,     // Standard (allow equals on left side)
   PIVOT_MODE_IDEAL         // Ideal (strict absolute high/low - no ties)
};

// Pivot strength mode
enum ENUM_PIVOT_STRENGTH
{
   PIVOT_STRENGTH_MAJOR,    // Major pivots only
   PIVOT_STRENGTH_MINOR,    // Minor pivots only
   PIVOT_STRENGTH_BOTH      // Both major and minor
};

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ Pivot Detection ═══"
input int                          InpLeftBars        = 5;                 // Left Bars (≥1)
input int                          InpRightBars       = 5;                 // Right Bars (≥1)
input ENUM_PIVOT_MODE              InpPivotMode       = PIVOT_MODE_STANDARD; // Detection Mode
input ENUM_PIVOT_STRENGTH          InpPivotStrength   = PIVOT_STRENGTH_BOTH; // Pivot Strength
input int                          InpMinorLeft       = 3;                 // Minor Pivot: Left Bars
input int                          InpMinorRight      = 3;                 // Minor Pivot: Right Bars

input group                        "═══ Swing Classification ═══"
input bool                         InpShowSwingLabels = true;              // Show HH/HL/LH/LL
input bool                         InpUse3LevelFilter = false;             // Filter to 3-Level Swings Only

input group                        "═══ S/R Level Lines ═══"
input bool                         InpShowLevelLines     = true;              // Show S/R Level Lines
input int                          InpMaxLevelLength     = 200;               // Max Level Length in bars (0=unlimited)
input bool                         InpBreakOnClose       = true;              // Stop Line When Price Closes Through Level
input int                          InpMaxActiveLevels    = 100;               // Max Simultaneous Lines (perf safeguard)
input color                        InpResistanceColor    = clrOrangeRed;      // Resistance Line Color
input color                        InpSupportColor       = clrDodgerBlue;     // Support Line Color
input color                        InpBrokenLevelColor   = clrGray;           // Broken Level Line Color
input bool                         InpDimBrokenLevels    = true;              // Dim Broken Levels for Clarity

input group                        "═══ Pivot Structure Labels ═══"
input bool                         InpShowPivotLabels     = true;              // Show Floating Structure Labels
input double                       InpLabelOffsetATRMult  = 0.5;               // Label Offset (x ATR)
input int                          InpLabelATRPeriod      = 14;                // ATR Period for Label Offset
input int                          InpLabelFontSize       = 8;                 // Label Font Size
input color                        InpHHLabelColor        = clrLimeGreen;      // HH Label Color
input color                        InpLHLabelColor        = clrOrange;         // LH Label Color
input color                        InpHLLabelColor        = clrMediumSpringGreen; // HL Label Color
input color                        InpLLLabelColor        = clrTomato;         // LL Label Color
input color                        InpPHLabelColor        = clrDodgerBlue;     // Unclassified PH Label Color
input color                        InpPLLabelColor        = clrOrangeRed;      // Unclassified PL Label Color

input group                        "═══ Alerts ═══"
input bool                         InpEnableAlerts    = true;              // Enable Popup Alerts
input bool                         InpAlertOnNewPivot = true;              // Alert on New Pivot Formation
input bool                         InpAlertOnSwing    = true;              // Alert on HH/HL/LH/LL

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_bufPivotHi[];       // 0  Major pivot high arrows
double g_bufPivotLo[];       // 1  Major pivot low arrows
double g_bufMinorHi[];       // 2  Minor pivot high arrows
double g_bufMinorLo[];       // 3  Minor pivot low arrows
double g_bufHH[];            // 4  Higher High markers
double g_bufLH[];            // 5  Lower High markers
double g_bufHL[];            // 6  Higher Low markers
double g_bufLL[];            // 7  Lower Low markers

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix    = "PVDT_";        // Object name prefix
int    g_totalBars = 0;              // Track bar count for new-bar detection
datetime g_lastAlertTime = 0;        // Throttle alerts to once per bar

// ── S/R Level state tracking ────────────────────────────────────────────────
struct SLevelState
{
   int      pivotIdx;        // bar index where the pivot occurred
   double   price;           // pivot high/low price
   int      lastScannedIdx;  // last bar index we've already checked for a break
   int      brokenIdx;       // -1 if not yet broken, else the bar index of the break
   bool     finalized;       // true once brokenIdx is set OR max length reached
   string   objName;         // chart object name for this level
};

SLevelState g_resLevels[];   // resistance levels (from pivot highs)
SLevelState g_supLevels[];   // support levels (from pivot lows)
int        g_resCount = 0;   // number of active resistance level entries
int        g_supCount = 0;   // number of active support level entries

// ── Pivot label tracking ────────────────────────────────────────────────────
struct SPivotLabel
{
   int    barIdx;       // bar index where the pivot occurred
   string objName;      // chart object name for this label
   bool   classified;   // false until HH/LH/HL/LL resolved, true after
};

SPivotLabel g_pivotHiLabels[];  // labels for major pivot highs
SPivotLabel g_pivotLoLabels[];  // labels for major pivot lows
int         g_hiLabelCount = 0;
int         g_loLabelCount = 0;

// ── ATR cache ───────────────────────────────────────────────────────────────
double g_atrCache[];      // cached ATR values, one per bar

// ── Swing state tracking ────────────────────────────────────────────────────
double g_lastPhiVal = EMPTY_VALUE;   // Most recent pivot high value
double g_lastPloVal = EMPTY_VALUE;   // Most recent pivot low value
int    g_lastPhiIdx = -1;            // Most recent pivot high bar index
int    g_lastPloIdx = -1;            // Most recent pivot low bar index
double g_prevPhiVal = EMPTY_VALUE;   // Previous pivot high value
double g_prevPloVal = EMPTY_VALUE;   // Previous pivot low value

//+------------------------------------------------------------------+
//| Pivot High – Standard (allow equals on left, strict on right)     |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &arr[], int left, int right, int idx)
{
   int size = ArraySize(arr);
   if(idx - left < 0 || idx + right >= size) return false;

   double val = arr[idx];

   // Left side: allow equal values (prevents false negatives on flat tops)
   for(int i = idx - left; i < idx; i++)
      if(arr[i] > val) return false;

   // Right side: strict greater-than (must break the high)
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] >= val) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Pivot Low – Standard (allow equals on left, strict on right)      |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &arr[], int left, int right, int idx)
{
   int size = ArraySize(arr);
   if(idx - left < 0 || idx + right >= size) return false;

   double val = arr[idx];

   // Left side: allow equal values
   for(int i = idx - left; i < idx; i++)
      if(arr[i] < val) return false;

   // Right side: strict less-than
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] <= val) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Pivot High – Ideal (strict absolute highest)                      |
//+------------------------------------------------------------------+
bool IsIdealPivotHigh(const double &arr[], int left, int right, int idx)
{
   int size = ArraySize(arr);
   if(idx - left < 0 || idx + right >= size) return false;

   double val = arr[idx];
   for(int i = idx - left; i <= idx + right; i++)
      if(i != idx && arr[i] >= val) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Pivot Low – Ideal (strict absolute lowest)                        |
//+------------------------------------------------------------------+
bool IsIdealPivotLow(const double &arr[], int left, int right, int idx)
{
   int size = ArraySize(arr);
   if(idx - left < 0 || idx + right >= size) return false;

   double val = arr[idx];
   for(int i = idx - left; i <= idx + right; i++)
      if(i != idx && arr[i] <= val) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Create a new horizontal level line object (call once per level)    |
//+------------------------------------------------------------------+
void CreateLevelLine(string name, double price, datetime startTime,
                     datetime endTime, color clr, int width, ENUM_LINE_STYLE style)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update the endpoint of an existing level line via ObjectMove      |
//+------------------------------------------------------------------+
void UpdateLevelEndPoint(string name, datetime endTime, double price)
{
   ObjectMove(0, name, 1, endTime, price);
}

//+------------------------------------------------------------------+
//| Remove a level object and compact the tracking array              |
//+------------------------------------------------------------------+
void RemoveLevel(SLevelState &levels[], int &count, int idx)
{
   if(idx < 0 || idx >= count) return;

   // Delete the chart object
   if(ObjectFind(0, levels[idx].objName) >= 0)
      ObjectDelete(0, levels[idx].objName);

   // Compact the array by shifting remaining entries down
   for(int i = idx; i < count - 1; i++)
      levels[i] = levels[i + 1];

   count--;
}

//+------------------------------------------------------------------+
//| Register a new pivot as a level, creating its chart object        |
//+------------------------------------------------------------------+
void RegisterLevel(SLevelState &levels[], int &count, int maxLevels,
                   int pivotIdx, double price, datetime startTime,
                   datetime endTime, string prefix, string suffix,
                   color clr)
{
   // Prune if at capacity: remove the oldest finalized level first
   if(count >= maxLevels)
   {
      // First pass: remove any finalized level
      int oldestFinalized = -1;
      int oldestFinalizedIdx = -1;
      for(int i = 0; i < count; i++)
      {
         if(levels[i].finalized && (levels[i].pivotIdx < oldestFinalizedIdx || oldestFinalizedIdx == -1))
         {
            oldestFinalized = i;
            oldestFinalizedIdx = levels[i].pivotIdx;
         }
      }
      if(oldestFinalized >= 0)
      {
         RemoveLevel(levels, count, oldestFinalized);
      }
      else
      {
         // No finalized levels — remove the oldest overall
         int oldest = 0;
         int oldestPivot = levels[0].pivotIdx;
         for(int i = 1; i < count; i++)
         {
            if(levels[i].pivotIdx < oldestPivot)
            {
               oldest = i;
               oldestPivot = levels[i].pivotIdx;
            }
         }
         RemoveLevel(levels, count, oldest);
      }
   }

   // Append new level
   SLevelState newLevel;
   newLevel.pivotIdx       = pivotIdx;
   newLevel.price          = price;
   newLevel.lastScannedIdx = pivotIdx;
   newLevel.brokenIdx      = -1;
   newLevel.finalized      = false;
   newLevel.objName        = prefix + "LVL_" + suffix + "_" + IntegerToString(pivotIdx);

   CreateLevelLine(newLevel.objName, price, startTime, endTime, clr, 1, STYLE_DOT);

   // Grow array if needed
   if(count >= ArraySize(levels))
      ArrayResize(levels, count + 64);

   levels[count] = newLevel;
   count++;
}

//+------------------------------------------------------------------+
//| Prune levels that are off-screen (finished and far behind)        |
//+------------------------------------------------------------------+
void PruneOffScreenLevels(SLevelState &levels[], int &count, int currentBar, int retentionBars)
{
   for(int i = count - 1; i >= 0; i--)
   {
      if(!levels[i].finalized) continue;

      int endBar = (levels[i].brokenIdx >= 0) ? levels[i].brokenIdx :
                    levels[i].pivotIdx + InpMaxLevelLength;

      if(currentBar - endBar > retentionBars)
         RemoveLevel(levels, count, i);
   }
}

//+------------------------------------------------------------------+
//| Advance and check all unfinalized levels for breaks/caps          |
//+------------------------------------------------------------------+
void AdvanceLevels(SLevelState &levels[], int &count,
                   const double &close[], const datetime &time[],
                   int lastIdx, bool isResistance, color liveColor, color brokenColor)
{
   for(int i = 0; i < count; i++)
   {
      if(levels[i].finalized) continue;  // skip finalized — already done

      int   pivotIdx = levels[i].pivotIdx;
      double price   = levels[i].price;
      int   scanFrom = levels[i].lastScannedIdx + 1;
      bool  broken   = false;
      int   breakBar = -1;

      // Scan forward from where we left off
      if(InpBreakOnClose && scanFrom <= lastIdx)
      {
         for(int j = scanFrom; j <= lastIdx; j++)
         {
            bool crossed = isResistance ? (close[j] >= price) : (close[j] <= price);
            if(crossed)
            {
               broken  = true;
               breakBar = j;
               break;
            }
         }
      }

      int barSpan   = lastIdx - pivotIdx;
      bool capped   = (InpMaxLevelLength > 0 && barSpan >= InpMaxLevelLength);
      bool finalize = broken || capped;

      if(finalize)
      {
         levels[i].finalized = true;

         datetime endTime;
         if(broken)
         {
            levels[i].brokenIdx = breakBar;
            endTime = time[breakBar];
         }
         else
         {
            // Capped by max length
            int capIdx = pivotIdx + InpMaxLevelLength;
            if(capIdx > lastIdx) capIdx = lastIdx;
            endTime = time[capIdx];
         }

         // Set final endpoint
         UpdateLevelEndPoint(levels[i].objName, endTime, price);

         // Recolor if dimming is enabled
         if(InpDimBrokenLevels)
            ObjectSetInteger(0, levels[i].objName, OBJPROP_COLOR, brokenColor);
      }
      else
      {
         // Still live — extend endpoint to current bar
         datetime newEnd = time[lastIdx];
         UpdateLevelEndPoint(levels[i].objName, newEnd, price);
      }

      levels[i].lastScannedIdx = lastIdx;
   }
}

//+------------------------------------------------------------------+
//| Scan buffer for new pivots and register them as levels            |
//+------------------------------------------------------------------+
void RegisterNewPivots(const double &pivotBuf[], const double &priceBuf[],
                       const datetime &time[], int rates_total, int start,
                       SLevelState &levels[], int &count, int maxLevels,
                       string prefix, string suffix, color liveColor, bool isResistance)
{
   // Build a quick set of already-registered pivot indices
   // For small counts this linear scan is fine
   for(int i = start; i < rates_total; i++)
   {
      if(pivotBuf[i] == EMPTY_VALUE || pivotBuf[i] == 0)
         continue;

      // Check if already registered
      bool alreadyRegistered = false;
      for(int j = 0; j < count; j++)
      {
         if(levels[j].pivotIdx == i)
         {
            alreadyRegistered = true;
            break;
         }
      }

      if(alreadyRegistered) continue;

      RegisterLevel(levels, count, maxLevels, i, priceBuf[i],
                    time[i], time[i], prefix, suffix, liveColor);
   }
}

//+------------------------------------------------------------------+
//| Compute ATR for all bars (called once per OnCalculate)             |
//+------------------------------------------------------------------+
void ComputeATR(const double &high[], const double &low[], const double &close[],
                int rates_total, int period)
{
   if(ArraySize(g_atrCache) < rates_total)
      ArrayResize(g_atrCache, rates_total);

   // True Range for bar 0
   if(rates_total > 0)
      g_atrCache[0] = high[0] - low[0];

   // Compute true range and smoothed ATR
   for(int i = 1; i < rates_total; i++)
   {
      double tr = MathMax(high[i] - low[i],
                  MathMax(MathAbs(high[i] - close[i - 1]),
                          MathAbs(low[i] - close[i - 1])));

      if(i < period)
         g_atrCache[i] = ((i > 0 ? g_atrCache[i - 1] : tr) * i + tr) / (i + 1);
      else
         g_atrCache[i] = (g_atrCache[i - 1] * (period - 1) + tr) / period;
   }
}

//+------------------------------------------------------------------+
//| Create a pivot text label object (call once per pivot)            |
//+------------------------------------------------------------------+
void CreatePivotLabel(int barIdx, double price, datetime barTime,
                      double atrOffset, string text, color clr,
                      SPivotLabel &labels[], int &count, bool isHigh)
{
   string name = g_prefix + "LBL_" + IntegerToString(barIdx);

   // Don't create if already exists
   if(ObjectFind(0, name) >= 0) return;

   double yPos;
   ENUM_ANCHOR_POINT anchor;
   if(isHigh)
   {
      yPos   = price + atrOffset;
      anchor = ANCHOR_LOWER;  // text sits above the point
   }
   else
   {
      yPos   = price - atrOffset;
      anchor = ANCHOR_UPPER;  // text sits below the point
   }

   if(!ObjectCreate(0, name, OBJ_TEXT, 0, barTime, yPos))
      return;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // Track it
   SPivotLabel lbl;
   lbl.barIdx     = barIdx;
   lbl.objName    = name;
   lbl.classified = false;

   if(count >= ArraySize(labels))
      ArrayResize(labels, count + 64);

   labels[count] = lbl;
   count++;
}

//+------------------------------------------------------------------+
//| Update a pivot label's text in-place (classification resolved)    |
//+------------------------------------------------------------------+
void UpdatePivotLabelText(SPivotLabel &labels[], int count, int barIdx,
                          string newText, color newColor)
{
   for(int i = 0; i < count; i++)
   {
      if(labels[i].barIdx == barIdx && !labels[i].classified)
      {
         ObjectSetString(0, labels[i].objName, OBJPROP_TEXT, newText);
         ObjectSetInteger(0, labels[i].objName, OBJPROP_COLOR, newColor);
         labels[i].classified = true;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all pivot label objects and reset tracking                 |
//+------------------------------------------------------------------+
void ClearAllPivotLabels(SPivotLabel &hiLabels[], int &hiCount,
                         SPivotLabel &loLabels[], int &loCount)
{
   for(int i = 0; i < hiCount; i++)
      if(ObjectFind(0, hiLabels[i].objName) >= 0)
         ObjectDelete(0, hiLabels[i].objName);
   for(int i = 0; i < loCount; i++)
      if(ObjectFind(0, loLabels[i].objName) >= 0)
         ObjectDelete(0, loLabels[i].objName);

   hiCount = 0;
   loCount = 0;
   ArrayFree(hiLabels);
   ArrayFree(loLabels);
}

//+------------------------------------------------------------------+
//| Get the bar index of the most recent non-EMPTY pivot in a buffer  |
//+------------------------------------------------------------------+
int GetLastPivotIndex(const double &buf[], int fromIdx)
{
   for(int i = fromIdx; i >= 0; i--)
      if(buf[i] != EMPTY_VALUE && buf[i] != 0)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Get value at Nth occurrence (ValueWhen equivalent)                |
//+------------------------------------------------------------------+
double ValueWhen(const double &cond[], const double &vals[], int occurrence, int fromIdx)
{
   int count = 0;
   for(int i = fromIdx; i >= 0; i--)
   {
      if(cond[i] != EMPTY_VALUE && cond[i] != 0)
      {
         if(count == occurrence)
            return vals[i];
         count++;
      }
   }
   return EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Check if bar is a new bar (for alert throttling)                  |
//+------------------------------------------------------------------+
bool IsNewBar(int rates_total)
{
   if(rates_total != g_totalBars)
   {
      g_totalBars = rates_total;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Send a popup alert                                                |
//+------------------------------------------------------------------+
void SendAlert(string msg)
{
   if(!InpEnableAlerts) return;
   Alert("PivotDetector: ", msg);
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Bind buffers
   SetIndexBuffer(0, g_bufPivotHi,  INDICATOR_DATA);
   SetIndexBuffer(1, g_bufPivotLo,  INDICATOR_DATA);
   SetIndexBuffer(2, g_bufMinorHi,  INDICATOR_DATA);
   SetIndexBuffer(3, g_bufMinorLo,  INDICATOR_DATA);
   SetIndexBuffer(4, g_bufHH,       INDICATOR_DATA);
   SetIndexBuffer(5, g_bufLH,       INDICATOR_DATA);
   SetIndexBuffer(6, g_bufHL,       INDICATOR_DATA);
   SetIndexBuffer(7, g_bufLL,       INDICATOR_DATA);

   // Set arrow codes (Wingdings)
   // 108 = filled circle ●  |  234 = down triangle ▼  |  233 = up triangle ▲
   PlotIndexSetInteger(0, PLOT_ARROW, 108);   // Major pivot high ●
   PlotIndexSetInteger(1, PLOT_ARROW, 108);   // Major pivot low  ●
   PlotIndexSetInteger(2, PLOT_ARROW, 161);   // Minor pivot high ¤ (small dot-like)
   PlotIndexSetInteger(3, PLOT_ARROW, 161);   // Minor pivot low  ¤
   PlotIndexSetInteger(4, PLOT_ARROW, 233);   // HH ▲
   PlotIndexSetInteger(5, PLOT_ARROW, 234);   // LH ▼
   PlotIndexSetInteger(6, PLOT_ARROW, 233);   // HL ▲
   PlotIndexSetInteger(7, PLOT_ARROW, 234);   // LL ▼

   // Set arrow vertical offsets
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);  // Above bar for highs
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -5);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 10);   // Below bar for lows
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 5);
   PlotIndexSetInteger(6, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(7, PLOT_ARROW_SHIFT, 15);

   // EMPTY_VALUE for all buffers
   for(int p = 0; p < 8; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("PivotDetector(%d,%d)", InpLeftBars, InpRightBars));

   // Labels for Data Window
   PlotIndexSetString(0, PLOT_LABEL, "Major Pivot High");
   PlotIndexSetString(1, PLOT_LABEL, "Major Pivot Low");
   PlotIndexSetString(2, PLOT_LABEL, "Minor Pivot High");
   PlotIndexSetString(3, PLOT_LABEL, "Minor Pivot Low");
   PlotIndexSetString(4, PLOT_LABEL, "Higher High");
   PlotIndexSetString(5, PLOT_LABEL, "Lower High");
   PlotIndexSetString(6, PLOT_LABEL, "Higher Low");
   PlotIndexSetString(7, PLOT_LABEL, "Lower Low");

   g_totalBars = 0;

   // Initialize level tracking arrays
   ArrayResize(g_resLevels, 64);
   ArrayResize(g_supLevels, 64);
   g_resCount = 0;
   g_supCount = 0;

   // Initialize label tracking arrays
   ArrayResize(g_pivotHiLabels, 64);
   ArrayResize(g_pivotLoLabels, 64);
   g_hiLabelCount = 0;
   g_loLabelCount = 0;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit – clean up chart objects                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove all chart objects with our prefix
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }

   // Clear level tracking arrays
   g_resCount = 0;
   g_supCount = 0;
   ArrayFree(g_resLevels);
   ArrayFree(g_supLevels);

   // Clear label tracking arrays
   g_hiLabelCount = 0;
   g_loLabelCount = 0;
   ArrayFree(g_pivotHiLabels);
   ArrayFree(g_pivotLoLabels);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate – main indicator loop                                 |
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
   // ── Safety: need enough bars ──────────────────────────────────────────────
   int minBars = InpLeftBars + InpRightBars + 50;
   if(minBars > InpMinorLeft + InpMinorRight + 50)
      minBars = InpMinorLeft + InpMinorRight + 50;
   if(rates_total < minBars) return 0;

   // ── Full recalculation ────────────────────────────────────────────────────
   bool isNewBarFlag = IsNewBar(rates_total);

   // Clean objects and reset level tracking on first load
   if(prev_calculated == 0)
   {
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringFind(name, g_prefix) == 0)
            ObjectDelete(0, name);
      }

      // Reset level tracking arrays
      g_resCount = 0;
      g_supCount = 0;
      ArrayFree(g_resLevels);
      ArrayFree(g_supLevels);
      ArrayResize(g_resLevels, 64);
      ArrayResize(g_supLevels, 64);

      // Reset label tracking
      g_hiLabelCount = 0;
      g_loLabelCount = 0;
      ArrayFree(g_pivotHiLabels);
      ArrayFree(g_pivotLoLabels);
      ArrayResize(g_pivotHiLabels, 64);
      ArrayResize(g_pivotLoLabels, 64);
   }

   // Initialize buffers with EMPTY_VALUE
   ArrayInitialize(g_bufPivotHi, EMPTY_VALUE);
   ArrayInitialize(g_bufPivotLo, EMPTY_VALUE);
   ArrayInitialize(g_bufMinorHi, EMPTY_VALUE);
   ArrayInitialize(g_bufMinorLo, EMPTY_VALUE);
   ArrayInitialize(g_bufHH,      EMPTY_VALUE);
   ArrayInitialize(g_bufLH,      EMPTY_VALUE);
   ArrayInitialize(g_bufHL,      EMPTY_VALUE);
   ArrayInitialize(g_bufLL,      EMPTY_VALUE);

   // ── Determine where to start calculating ──────────────────────────────────
   int start = InpLeftBars + InpRightBars + 5;
   if(InpMinorLeft + InpMinorRight + 5 > start)
      start = InpMinorLeft + InpMinorRight + 5;
   if(prev_calculated > start)
      start = prev_calculated - InpLeftBars - InpRightBars - 1;
   if(start < InpLeftBars + InpRightBars + 5)
      start = InpLeftBars + InpRightBars + 5;

   // ── Select detection function based on mode ───────────────────────────────
   bool useIdeal = (InpPivotMode == PIVOT_MODE_IDEAL);

   // ── Pre-compute ATR for label offsets ────────────────────────────────────
   if(InpShowPivotLabels)
      ComputeATR(high, low, close, rates_total, InpLabelATRPeriod);

   // ── MAIN LOOP ────────────────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // --- Major Pivot Detection ---
      int pivotMajorIdx = i - InpRightBars;  // The bar where the pivot actually is
      if(pivotMajorIdx >= InpLeftBars && pivotMajorIdx < rates_total)
      {
         bool isMajorPhi = false;
         bool isMajorPlo = false;

         if(useIdeal)
         {
            isMajorPhi = IsIdealPivotHigh(high, InpLeftBars, InpRightBars, pivotMajorIdx);
            isMajorPlo = IsIdealPivotLow(low,   InpLeftBars, InpRightBars, pivotMajorIdx);
         }
         else
         {
            isMajorPhi = IsPivotHigh(high, InpLeftBars, InpRightBars, pivotMajorIdx);
            isMajorPlo = IsPivotLow(low,   InpLeftBars, InpRightBars, pivotMajorIdx);
         }

         bool showMajor = (InpPivotStrength == PIVOT_STRENGTH_MAJOR ||
                           InpPivotStrength == PIVOT_STRENGTH_BOTH);

         if(showMajor)
         {
            if(isMajorPhi)
            {
               g_bufPivotHi[pivotMajorIdx] = high[pivotMajorIdx];

               // Create placeholder label if labels enabled
               if(InpShowPivotLabels)
               {
                  double atrOffset = (pivotMajorIdx < rates_total && pivotMajorIdx >= 0)
                                     ? g_atrCache[pivotMajorIdx] * InpLabelOffsetATRMult : 0.0;
                  CreatePivotLabel(pivotMajorIdx, high[pivotMajorIdx], time[pivotMajorIdx],
                                   atrOffset, "PH", InpPHLabelColor,
                                   g_pivotHiLabels, g_hiLabelCount, true);
               }
            }
            if(isMajorPlo)
            {
               g_bufPivotLo[pivotMajorIdx] = low[pivotMajorIdx];

               // Create placeholder label if labels enabled
               if(InpShowPivotLabels)
               {
                  double atrOffset = (pivotMajorIdx < rates_total && pivotMajorIdx >= 0)
                                     ? g_atrCache[pivotMajorIdx] * InpLabelOffsetATRMult : 0.0;
                  CreatePivotLabel(pivotMajorIdx, low[pivotMajorIdx], time[pivotMajorIdx],
                                   atrOffset, "PL", InpPLLabelColor,
                                   g_pivotLoLabels, g_loLabelCount, false);
               }
            }
         }
      }

      // --- Minor Pivot Detection ---
      int pivotMinorIdx = i - InpMinorRight;
      if(pivotMinorIdx >= InpMinorLeft && pivotMinorIdx < rates_total)
      {
         bool isMinorPhi = false;
         bool isMinorPlo = false;

         if(useIdeal)
         {
            isMinorPhi = IsIdealPivotHigh(high, InpMinorLeft, InpMinorRight, pivotMinorIdx);
            isMinorPlo = IsIdealPivotLow(low,   InpMinorLeft, InpMinorRight, pivotMinorIdx);
         }
         else
         {
            isMinorPhi = IsPivotHigh(high, InpMinorLeft, InpMinorRight, pivotMinorIdx);
            isMinorPlo = IsPivotLow(low,   InpMinorLeft, InpMinorRight, pivotMinorIdx);
         }

         // Don't mark as minor if it's already a major pivot
         if(g_bufPivotHi[pivotMinorIdx] != EMPTY_VALUE)
            isMinorPhi = false;
         if(g_bufPivotLo[pivotMinorIdx] != EMPTY_VALUE)
            isMinorPlo = false;

         bool showMinor = (InpPivotStrength == PIVOT_STRENGTH_MINOR ||
                           InpPivotStrength == PIVOT_STRENGTH_BOTH);

         if(showMinor)
         {
            if(isMinorPhi) g_bufMinorHi[pivotMinorIdx] = high[pivotMinorIdx];
            if(isMinorPlo) g_bufMinorLo[pivotMinorIdx] = low[pivotMinorIdx];
         }
      }
   }

   // ── SECOND PASS: Swing Classification (HH/HL/LH/LL) ──────────────────────
   if(InpShowSwingLabels && rates_total > start)
   {
      for(int i = start; i < rates_total && !IsStopped(); i++)
      {
         // Use the combined pivot buffer (major only for swing labels)
         double pivotPhi0 = ValueWhen(g_bufPivotHi, high, 0, i);
         double pivotPhi1 = ValueWhen(g_bufPivotHi, high, 1, i);
         double pivotPhi2 = ValueWhen(g_bufPivotHi, high, 2, i);
         double pivotPhi3 = ValueWhen(g_bufPivotHi, high, 3, i);

         double pivotPlo0 = ValueWhen(g_bufPivotLo, low, 0, i);
         double pivotPlo1 = ValueWhen(g_bufPivotLo, low, 1, i);
         double pivotPlo2 = ValueWhen(g_bufPivotLo, low, 2, i);
         double pivotPlo3 = ValueWhen(g_bufPivotLo, low, 3, i);

         // Current bar is a pivot high
         if(g_bufPivotHi[i] != EMPTY_VALUE)
         {
            if(pivotPhi0 != EMPTY_VALUE && pivotPhi1 != EMPTY_VALUE)
            {
               if(InpUse3LevelFilter)
               {
                  // 3-level filter: H0 > H1 > H2 > H3
                  if(pivotPhi2 != EMPTY_VALUE && pivotPhi3 != EMPTY_VALUE &&
                     pivotPhi0 > pivotPhi1 && pivotPhi1 > pivotPhi2 && pivotPhi2 > pivotPhi3)
                  {
                     g_bufHH[i] = high[i];  // HH
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotHiLabels, g_hiLabelCount, i, "HH", InpHHLabelColor);
                  }
                  else if(pivotPhi2 != EMPTY_VALUE && pivotPhi3 != EMPTY_VALUE &&
                          pivotPhi0 < pivotPhi1 && pivotPhi1 < pivotPhi2 && pivotPhi2 < pivotPhi3)
                  {
                     g_bufLH[i] = high[i];  // LH
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotHiLabels, g_hiLabelCount, i, "LH", InpLHLabelColor);
                  }
                  else if(pivotPhi2 != EMPTY_VALUE &&
                          pivotPhi0 < pivotPhi1 && pivotPhi1 > pivotPhi2)
                  {
                     g_bufLH[i] = high[i];  // LH (simple)
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotHiLabels, g_hiLabelCount, i, "LH", InpLHLabelColor);
                  }
               }
               else
               {
                  if(pivotPhi0 > pivotPhi1)
                  {
                     g_bufHH[i] = high[i];
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotHiLabels, g_hiLabelCount, i, "HH", InpHHLabelColor);
                  }
                  else if(pivotPhi0 < pivotPhi1)
                  {
                     g_bufLH[i] = high[i];
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotHiLabels, g_hiLabelCount, i, "LH", InpLHLabelColor);
                  }
               }
            }
         }

         // Current bar is a pivot low
         if(g_bufPivotLo[i] != EMPTY_VALUE)
         {
            if(pivotPlo0 != EMPTY_VALUE && pivotPlo1 != EMPTY_VALUE)
            {
               if(InpUse3LevelFilter)
               {
                  if(pivotPlo2 != EMPTY_VALUE && pivotPlo3 != EMPTY_VALUE &&
                     pivotPlo0 > pivotPlo1 && pivotPlo1 > pivotPlo2 && pivotPlo2 > pivotPlo3)
                  {
                     g_bufHL[i] = low[i];  // HL
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotLoLabels, g_loLabelCount, i, "HL", InpHLLabelColor);
                  }
                  else if(pivotPlo2 != EMPTY_VALUE && pivotPlo3 != EMPTY_VALUE &&
                          pivotPlo0 < pivotPlo1 && pivotPlo1 < pivotPlo2 && pivotPlo2 < pivotPlo3)
                  {
                     g_bufLL[i] = low[i];  // LL
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotLoLabels, g_loLabelCount, i, "LL", InpLLLabelColor);
                  }
                  else if(pivotPlo2 != EMPTY_VALUE &&
                          pivotPlo0 > pivotPlo1 && pivotPlo1 < pivotPlo2)
                  {
                     g_bufHL[i] = low[i];  // HL (simple)
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotLoLabels, g_loLabelCount, i, "HL", InpHLLabelColor);
                  }
               }
               else
               {
                  if(pivotPlo0 > pivotPlo1)
                  {
                     g_bufHL[i] = low[i];
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotLoLabels, g_loLabelCount, i, "HL", InpHLLabelColor);
                  }
                  else if(pivotPlo0 < pivotPlo1)
                  {
                     g_bufLL[i] = low[i];
                     if(InpShowPivotLabels)
                        UpdatePivotLabelText(g_pivotLoLabels, g_loLabelCount, i, "LL", InpLLLabelColor);
                  }
               }
            }
         }
      }
   }

   // ── S/R Level Lines ──────────────────────────────────────────────────────
   if(InpShowLevelLines)
   {
      int lastIdx = rates_total - 1;
      if(lastIdx < 0) lastIdx = 0;

      int maxLevels = InpMaxActiveLevels;
      if(maxLevels <= 0) maxLevels = 100;

      // Register new pivot highs as resistance levels
      RegisterNewPivots(g_bufPivotHi, high, time, rates_total, start,
                        g_resLevels, g_resCount, maxLevels,
                        g_prefix, "RES", InpResistanceColor, true);

      // Register new pivot lows as support levels
      RegisterNewPivots(g_bufPivotLo, low, time, rates_total, start,
                        g_supLevels, g_supCount, maxLevels,
                        g_prefix, "SUP", InpSupportColor, false);

      // Advance unfinalized resistance levels (check for break/cap)
      AdvanceLevels(g_resLevels, g_resCount, close, time, lastIdx,
                    true, InpResistanceColor, InpBrokenLevelColor);

      // Advance unfinalized support levels
      AdvanceLevels(g_supLevels, g_supCount, close, time, lastIdx,
                    false, InpSupportColor, InpBrokenLevelColor);

      // Prune off-screen finalized levels to keep arrays small
      int retentionBars = InpMaxLevelLength > 0 ? (InpMaxLevelLength * 3) : 1000;
      PruneOffScreenLevels(g_resLevels, g_resCount, lastIdx, retentionBars);
      PruneOffScreenLevels(g_supLevels, g_supCount, lastIdx, retentionBars);
   }
   else
   {
      // Toggled off — remove all level objects and clear tracking
      if(g_resCount > 0 || g_supCount > 0)
      {
         for(int i = 0; i < g_resCount; i++)
         {
            if(ObjectFind(0, g_resLevels[i].objName) >= 0)
               ObjectDelete(0, g_resLevels[i].objName);
         }
         for(int i = 0; i < g_supCount; i++)
         {
            if(ObjectFind(0, g_supLevels[i].objName) >= 0)
               ObjectDelete(0, g_supLevels[i].objName);
         }
         g_resCount = 0;
         g_supCount = 0;
      }
   }

   // ── Pivot Structure Labels Toggle ────────────────────────────────────────
   if(!InpShowPivotLabels)
   {
      // Toggled off — remove all label objects and clear tracking
      if(g_hiLabelCount > 0 || g_loLabelCount > 0)
      {
         ClearAllPivotLabels(g_pivotHiLabels, g_hiLabelCount,
                             g_pivotLoLabels, g_loLabelCount);
      }
   }

   // ── Alerts ───────────────────────────────────────────────────────────────
   if(InpEnableAlerts && InpAlertOnNewPivot && isNewBarFlag)
   {
      int checkIdx = rates_total - 1 - InpRightBars;
      if(checkIdx >= 0 && checkIdx < rates_total)
      {
         if(g_bufPivotHi[checkIdx] != EMPTY_VALUE)
         {
            SendAlert(StringFormat("NEW MAJOR PIVOT HIGH at %.5f on %s",
                     high[checkIdx], Symbol()));
            g_lastAlertTime = TimeCurrent();
         }
         if(g_bufPivotLo[checkIdx] != EMPTY_VALUE)
         {
            SendAlert(StringFormat("NEW MAJOR PIVOT LOW at %.5f on %s",
                     low[checkIdx], Symbol()));
            g_lastAlertTime = TimeCurrent();
         }
      }
   }

   if(InpEnableAlerts && InpAlertOnSwing && isNewBarFlag)
   {
      int checkIdx = rates_total - 1;
      if(checkIdx >= 0 && checkIdx < rates_total)
      {
         if(g_bufHH[checkIdx] != EMPTY_VALUE)
            SendAlert(StringFormat("HIGHER HIGH on %s", Symbol()));
         if(g_bufLH[checkIdx] != EMPTY_VALUE)
            SendAlert(StringFormat("LOWER HIGH on %s — potential reversal", Symbol()));
         if(g_bufHL[checkIdx] != EMPTY_VALUE)
            SendAlert(StringFormat("HIGHER LOW on %s", Symbol()));
         if(g_bufLL[checkIdx] != EMPTY_VALUE)
            SendAlert(StringFormat("LOWER LOW on %s — potential breakdown", Symbol()));
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
