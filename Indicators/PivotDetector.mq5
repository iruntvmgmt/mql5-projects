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
input bool                         InpShowLevelLines  = true;              // Show S/R Level Lines
input int                          InpMaxLevelLength  = 200;               // Max Level Length (0=unlimited)
input color                        InpResistanceColor = clrOrangeRed;      // Resistance Line Color
input color                        InpSupportColor    = clrDodgerBlue;     // Support Line Color

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
//| Draw a horizontal level line at a given price level               |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, double price, datetime startTime,
                   datetime endTime, color clr, int width, ENUM_LINE_STYLE style)
{
   // If the line already exists, update it; otherwise create it
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

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

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit – clean up chart objects                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
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

   // Clean objects on first load
   if(prev_calculated == 0)
   {
      int total = ObjectsTotal(0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringFind(name, g_prefix) == 0)
            ObjectDelete(0, name);
      }
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
            if(isMajorPhi) g_bufPivotHi[pivotMajorIdx] = high[pivotMajorIdx];
            if(isMajorPlo) g_bufPivotLo[pivotMajorIdx] = low[pivotMajorIdx];
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
                     g_bufHH[i] = high[i];  // HH
                  else if(pivotPhi2 != EMPTY_VALUE && pivotPhi3 != EMPTY_VALUE &&
                          pivotPhi0 < pivotPhi1 && pivotPhi1 < pivotPhi2 && pivotPhi2 < pivotPhi3)
                     g_bufLH[i] = high[i];  // LH
                  else if(pivotPhi2 != EMPTY_VALUE &&
                          pivotPhi0 < pivotPhi1 && pivotPhi1 > pivotPhi2)
                     g_bufLH[i] = high[i];  // LH (simple)
               }
               else
               {
                  if(pivotPhi0 > pivotPhi1)
                     g_bufHH[i] = high[i];
                  else if(pivotPhi0 < pivotPhi1)
                     g_bufLH[i] = high[i];
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
                     g_bufHL[i] = low[i];  // HL
                  else if(pivotPlo2 != EMPTY_VALUE && pivotPlo3 != EMPTY_VALUE &&
                          pivotPlo0 < pivotPlo1 && pivotPlo1 < pivotPlo2 && pivotPlo2 < pivotPlo3)
                     g_bufLL[i] = low[i];  // LL
                  else if(pivotPlo2 != EMPTY_VALUE &&
                          pivotPlo0 > pivotPlo1 && pivotPlo1 < pivotPlo2)
                     g_bufHL[i] = low[i];  // HL (simple)
               }
               else
               {
                  if(pivotPlo0 > pivotPlo1)
                     g_bufHL[i] = low[i];
                  else if(pivotPlo0 < pivotPlo1)
                     g_bufLL[i] = low[i];
               }
            }
         }
      }
   }

   // ── S/R Level Lines ──────────────────────────────────────────────────────
   if(InpShowLevelLines)
   {
      // Clean old level lines each pass (they get recreated)
      int objTotal = ObjectsTotal(0);
      for(int i = objTotal - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i);
         if(StringFind(name, g_prefix + "LVL_") == 0)
            ObjectDelete(0, name);
      }

      int lastIdx = rates_total - 1;
      if(lastIdx < 0) lastIdx = 0;

      // Draw resistance lines from pivot highs
      int levelCount = 0;
      for(int i = lastIdx; i >= start && !IsStopped(); i--)
      {
         if(InpMaxLevelLength > 0 && levelCount >= InpMaxLevelLength) break;

         if(g_bufPivotHi[i] != EMPTY_VALUE)
         {
            datetime startTime = time[i];
            datetime endTime   = time[lastIdx];

            // Extend the line forward by a few bars for visual clarity
            int barShift = (int)((time[lastIdx] - time[lastIdx - 1]) * 10);
            if(barShift < 3600) barShift = 3600;  // at least 1 hour forward
            endTime += barShift;

            string rName = g_prefix + "LVL_RES_" + IntegerToString(levelCount);
            DrawLevelLine(rName, high[i], startTime, endTime,
                         InpResistanceColor, 1, STYLE_DOT);
            levelCount++;
         }
      }

      // Draw support lines from pivot lows
      levelCount = 0;
      for(int i = lastIdx; i >= start && !IsStopped(); i--)
      {
         if(InpMaxLevelLength > 0 && levelCount >= InpMaxLevelLength) break;

         if(g_bufPivotLo[i] != EMPTY_VALUE)
         {
            datetime startTime = time[i];
            datetime endTime   = time[lastIdx] + 3600;

            string sName = g_prefix + "LVL_SUP_" + IntegerToString(levelCount);
            DrawLevelLine(sName, low[i], startTime, endTime,
                         InpSupportColor, 1, STYLE_DOT);
            levelCount++;
         }
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
