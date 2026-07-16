//+------------------------------------------------------------------+
//|                                         NAS100_Nexus_EA.mq5      |
//|   NAS100 opening-range, squeeze, and market-structure research   |
//+------------------------------------------------------------------+
#property copyright "NAS100 Nexus"
#property version   "1.05"
#property description "NAS100 Nexus EA - liquidity sweep displacement research"

input group "Safety"
input bool            InpEnableTrading       = false;      // Reserved; no order code exists in this build

input group "Signal Clock"
input ENUM_TIMEFRAMES InpSignalTimeframe     = PERIOD_M5;  // Closed-bar processing timeframe
input bool            InpAutoServerUtcOffset = true;       // Detect broker-server offset from UTC
input int             InpServerUtcOffset     = 0;          // Manual UTC offset when auto detection is off

input group "New York Session"
input string          InpOpeningRangeStart   = "09:30";   // New York time
input string          InpOpeningRangeEnd     = "09:45";   // New York time
input string          InpResearchWindowEnd   = "12:00";   // New York time

input group "Squeeze Research"
input int             InpBBLength            = 20;         // Bollinger Band length
input double          InpBBMultiplier        = 2.0;        // Bollinger Band deviation
input int             InpKCLength            = 20;         // Keltner Channel length
input double          InpKCMultiplier        = 1.5;        // Keltner true-range multiplier
input int             InpMomentumLength      = 20;         // TTM-style momentum length
input int             InpMaxSqueezeScan      = 50;         // Maximum consecutive bars to scan
input bool            InpDrawReleaseMarkers  = true;       // Mark confirmed squeeze releases
input bool            InpWriteBarLog         = false;      // Slow: append every closed bar to CSV

input group "Liquidity Sweep / Displacement"
input int             InpATRLength           = 14;         // ATR length for normalized thresholds
input string          InpPremarketStart      = "04:00";    // New York premarket range start
input bool            InpUsePremarketLevels  = true;       // Sweep premarket high / low
input bool            InpUseOpeningRange     = true;       // Sweep opening-range high / low
input double          InpSweepBufferATR      = 0.05;       // Required excursion beyond liquidity
input int             InpDisplacementBars    = 3;          // Bars allowed to confirm displacement
input double          InpDisplacementBodyATR = 0.40;       // Minimum displacement candle body
input int             InpPullbackWindowBars  = 5;          // Bars allowed to retrace displacement
input double          InpPullbackToleranceATR= 0.15;       // Allowed distance around 50% pullback
input double          InpInvalidationATR     = 0.35;       // Close beyond sweep extreme cancels setup
input bool            InpUseVWAPScore        = true;       // Score displacement alignment with VWAP
input bool            InpUseRelativeVolScore = true;       // Score displacement relative volume
input int             InpRelativeVolumeLength= 20;         // Tick-volume lookback
input double          InpRelativeVolumeMin   = 1.20;       // Relative-volume score threshold
input int             InpMinimumConfirmScore = 1;          // Optional confirmations required (0-2)
input int             InpMaximumSignalsDay   = 2;          // Research signals per New York day
input double          InpStopBufferATR       = 0.15;       // Stop beyond swept extreme
input double          InpResearchTargetR     = 1.5;        // Hypothetical target in R

input group "Outcome Tracking"
input int             InpOutcomeMaxBars      = 36;         // Force an exit after this many signal bars
input string          InpOutcomeSessionClose = "16:00";    // New York time for forced outcome exit
input double          InpSlippagePoints      = 2.0;        // Round-trip slippage estimate in MT5 points
input bool            InpStopFirstSameBar    = true;       // Both stop/target touched: score stop first
input bool            InpWriteOutcomeLog     = true;       // Write one row per resolved setup
input bool            InpWriteDailyLog       = true;       // Write one row per completed NY trading day
input double          InpResearchRiskPct     = 1.0;        // Hypothetical fixed-fraction risk per setup
input double          InpResearchStartEquity = 100.0;      // Hypothetical research balance

input group "Risk Preview (No Orders)"
input double          InpPreviewRiskPct      = 5.0;        // Equity risk used only for diagnostics
input double          InpPreviewStopDistance = 30.0;       // NAS100 index-price units

// Retained only so the archived v0.30 engine below remains compilable; it is never called.
const double          InpBreakoutBufferATR   = 0.10;
const double          InpRetestToleranceATR  = 0.20;
const int             InpRetestWindowBars    = 6;
const bool            InpRequireSqueeze      = true;
const int             InpReleaseLookbackBars = 4;
const int             InpMinimumSqueezeBars  = 3;

string   g_eaName = "NAS100 Nexus EA";
string   g_orHighName = "NAS100_NEXUS_OR_HIGH";
string   g_orLowName  = "NAS100_NEXUS_OR_LOW";
datetime g_lastSignalBarOpen = 0;
int      g_serverUtcOffset = 0;
int      g_orStartMinutes = 570;
int      g_orEndMinutes = 585;
int      g_researchEndMinutes = 690;
int      g_premarketStartMinutes = 240;
int      g_sessionDateKey = 0;
int      g_orBars = 0;
double   g_orHigh = 0.0;
double   g_orLow = 0.0;
bool     g_orReady = false;
int      g_premarketBars = 0;
double   g_premarketHigh = 0.0;
double   g_premarketLow = 0.0;
bool     g_premarketReady = false;
double   g_vwapPriceVolume = 0.0;
double   g_vwapVolume = 0.0;
double   g_sessionVwap = 0.0;

struct SqueezeSnapshot
{
   bool   valid;
   bool   squeezeOn;
   bool   released;
   int    squeezeBars;
   double momentum;
   double momentumDelta;
   int    releaseBias;       // +1 bullish, -1 bearish, 0 unconfirmed
};

SqueezeSnapshot g_squeeze;

enum ENUM_RESEARCH_STATE
{
   RESEARCH_IDLE,
   RESEARCH_WAIT_LONG_RETEST,
   RESEARCH_WAIT_SHORT_RETEST,
   RESEARCH_LONG_SIGNAL,
   RESEARCH_SHORT_SIGNAL
};

ENUM_RESEARCH_STATE g_researchState = RESEARCH_IDLE;
datetime g_breakoutTime = 0;
double   g_breakoutLevel = 0.0;
int      g_retestBarsRemaining = 0;
datetime g_lastReleaseTime = 0;
int      g_lastReleaseBias = 0;
int      g_lastReleaseDuration = 0;
datetime g_lastResearchSignalTime = 0;
int      g_signalsToday = 0;
int      g_currentResearchSignal = 0;
double   g_hypotheticalEntry = 0.0;
double   g_hypotheticalStop = 0.0;
double   g_hypotheticalTarget = 0.0;
int      g_outcomeCloseMinutes = 960;
bool     g_outcomeActive = false;
int      g_outcomeDirection = 0;
datetime g_outcomeEntryTime = 0;
int      g_outcomeBars = 0;
double   g_outcomeRisk = 0.0;
double   g_outcomeCostR = 0.0;
double   g_outcomeMfeR = 0.0;
double   g_outcomeMaeR = 0.0;
double   g_outcomeOrHigh = 0.0;
double   g_outcomeOrLow = 0.0;
int      g_outcomeSqueezeBars = 0;
int      g_currentOutcome = 0;              // +1 win, -1 loss, +2 timeout, +3 session exit
string   g_lastOutcomeReason = "none";
double   g_lastOutcomeR = 0.0;
int      g_totalOutcomes = 0;
int      g_totalWins = 0;
int      g_totalLosses = 0;
int      g_totalTimedExits = 0;
double   g_totalNetR = 0.0;
int      g_dailyDateKey = 0;
int      g_lastDailyWrittenKey = 0;
int      g_dailyOutcomes = 0;
int      g_dailyWins = 0;
int      g_dailyLosses = 0;
int      g_dailyTimedExits = 0;
double   g_dailyNetR = 0.0;
double   g_dailyStartEquity = 100.0;
double   g_researchEquity = 100.0;
double   g_researchPeakEquity = 100.0;
double   g_researchMaxDrawdownPct = 0.0;

enum ENUM_LIQUIDITY_STATE
{
   LIQUIDITY_IDLE,
   LIQUIDITY_WAIT_LONG_DISPLACEMENT,
   LIQUIDITY_WAIT_SHORT_DISPLACEMENT,
   LIQUIDITY_WAIT_LONG_PULLBACK,
   LIQUIDITY_WAIT_SHORT_PULLBACK
};

ENUM_LIQUIDITY_STATE g_liquidityState = LIQUIDITY_IDLE;
datetime g_liquiditySweepTime = 0;
double   g_liquidityLevel = 0.0;
double   g_sweepExtreme = 0.0;
int      g_liquidityBarsRemaining = 0;
double   g_pullbackPrice = 0.0;
int      g_displacementScore = 0;

//+------------------------------------------------------------------+
//| Parse HH:MM                                                      |
//+------------------------------------------------------------------+
bool ParseMinutes(const string value, int &minutes)
{
   string parts[];
   if(StringSplit(value, ':', parts) != 2)
      return false;

   int hour = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return false;

   minutes = hour * 60 + minute;
   return true;
}

//+------------------------------------------------------------------+
//| Calendar helpers                                                 |
//+------------------------------------------------------------------+
int NthSundayOfMonth(const int year, const int month, const int nth)
{
   MqlDateTime first = {};
   first.year = year;
   first.mon = month;
   first.day = 1;
   datetime firstTime = StructToTime(first);
   TimeToStruct(firstTime, first);
   int firstSunday = 1 + ((7 - first.day_of_week) % 7);
   return firstSunday + (nth - 1) * 7;
}

datetime CalendarTime(const int year, const int month, const int day,
                      const int hour, const int minute = 0)
{
   MqlDateTime value = {};
   value.year = year;
   value.mon = month;
   value.day = day;
   value.hour = hour;
   value.min = minute;
   return StructToTime(value);
}

bool IsNewYorkDstUtc(const datetime utcTime)
{
   MqlDateTime utc = {};
   TimeToStruct(utcTime, utc);

   int marchSunday = NthSundayOfMonth(utc.year, 3, 2);
   int novemberSunday = NthSundayOfMonth(utc.year, 11, 1);
   datetime dstStartUtc = CalendarTime(utc.year, 3, marchSunday, 7);
   datetime dstEndUtc = CalendarTime(utc.year, 11, novemberSunday, 6);
   return utcTime >= dstStartUtc && utcTime < dstEndUtc;
}

int ResolveServerUtcOffset()
{
   if(!InpAutoServerUtcOffset)
      return InpServerUtcOffset;

   datetime serverTime = TimeTradeServer();
   datetime utcTime = TimeGMT();
   if(serverTime <= 0 || utcTime <= 0)
      return InpServerUtcOffset;

   return (int)MathRound((double)(serverTime - utcTime) / 3600.0);
}

datetime ServerToNewYork(const datetime serverTime)
{
   datetime utcTime = serverTime - g_serverUtcOffset * 3600;
   int nyUtcOffset = IsNewYorkDstUtc(utcTime) ? -4 : -5;
   return utcTime + nyUtcOffset * 3600;
}

int NewYorkDateKey(const datetime serverTime, MqlDateTime &ny)
{
   TimeToStruct(ServerToNewYork(serverTime), ny);
   return ny.year * 10000 + ny.mon * 100 + ny.day;
}

//+------------------------------------------------------------------+
//| Opening-range state                                              |
//+------------------------------------------------------------------+
void DeleteOpeningRangeObjects()
{
   ObjectDelete(0, g_orHighName);
   ObjectDelete(0, g_orLowName);
}

void ResetResearchState()
{
   g_researchState = RESEARCH_IDLE;
   g_breakoutTime = 0;
   g_breakoutLevel = 0.0;
   g_retestBarsRemaining = 0;
   g_lastReleaseTime = 0;
   g_lastReleaseBias = 0;
   g_lastReleaseDuration = 0;
   g_lastResearchSignalTime = 0;
   g_signalsToday = 0;
   g_currentResearchSignal = 0;
   g_hypotheticalEntry = 0.0;
   g_hypotheticalStop = 0.0;
   g_hypotheticalTarget = 0.0;
   g_outcomeActive = false;
   g_outcomeDirection = 0;
   g_outcomeEntryTime = 0;
   g_outcomeBars = 0;
   g_outcomeRisk = 0.0;
   g_outcomeCostR = 0.0;
   g_outcomeMfeR = 0.0;
   g_outcomeMaeR = 0.0;
   g_outcomeOrHigh = 0.0;
   g_outcomeOrLow = 0.0;
   g_outcomeSqueezeBars = 0;
   g_currentOutcome = 0;
   g_liquidityState = LIQUIDITY_IDLE;
   g_liquiditySweepTime = 0;
   g_liquidityLevel = 0.0;
   g_sweepExtreme = 0.0;
   g_liquidityBarsRemaining = 0;
   g_pullbackPrice = 0.0;
   g_displacementScore = 0;
}

string DateKeyText(const int dateKey)
{
   int year = dateKey / 10000;
   int month = (dateKey / 100) % 100;
   int day = dateKey % 100;
   return StringFormat("%04d.%02d.%02d", year, month, day);
}

void StartDailyTracking(const int dateKey)
{
   g_dailyDateKey = dateKey;
   g_dailyOutcomes = 0;
   g_dailyWins = 0;
   g_dailyLosses = 0;
   g_dailyTimedExits = 0;
   g_dailyNetR = 0.0;
   g_dailyStartEquity = g_researchEquity;
}

void FinalizeDailySummary(const bool writeLog)
{
   if(g_dailyDateKey <= 0 || g_dailyDateKey == g_lastDailyWrittenKey)
      return;

   double dailyReturnPct = g_dailyStartEquity > 0.0
                           ? (g_researchEquity / g_dailyStartEquity - 1.0) * 100.0 : 0.0;
   double cumulativeReturnPct = InpResearchStartEquity > 0.0
                                ? (g_researchEquity / InpResearchStartEquity - 1.0) * 100.0 : 0.0;
   double drawdownPct = g_researchPeakEquity > 0.0
                        ? (g_researchPeakEquity - g_researchEquity) /
                          g_researchPeakEquity * 100.0 : 0.0;

   if(writeLog && InpWriteDailyLog)
   {
      FolderCreate("NAS100_Nexus");
      string safeSymbol = _Symbol;
      StringReplace(safeSymbol, "/", "_");
      string fileName = "NAS100_Nexus\\" + safeSymbol + "_M5_daily_v050.csv";
      int handle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
      if(handle != INVALID_HANDLE)
      {
         if(FileSize(handle) == 0)
            FileWrite(handle, "new_york_date", "outcomes", "wins", "losses", "timed_exits",
                      "net_r", "start_equity", "end_equity", "daily_return_pct",
                      "cumulative_return_pct", "drawdown_pct", "max_drawdown_pct");
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, DateKeyText(g_dailyDateKey), g_dailyOutcomes, g_dailyWins,
                   g_dailyLosses, g_dailyTimedExits, DoubleToString(g_dailyNetR, 4),
                   DoubleToString(g_dailyStartEquity, 2), DoubleToString(g_researchEquity, 2),
                   DoubleToString(dailyReturnPct, 4), DoubleToString(cumulativeReturnPct, 4),
                   DoubleToString(drawdownPct, 4), DoubleToString(g_researchMaxDrawdownPct, 4));
         FileClose(handle);
      }
      else
         PrintFormat("%s | daily log open failed: %d", g_eaName, GetLastError());
   }

   if(writeLog)
      PrintFormat("%s | daily %s | setups=%d net=%.3fR return=%.3f%% equity=%.2f",
                  g_eaName, DateKeyText(g_dailyDateKey), g_dailyOutcomes,
                  g_dailyNetR, dailyReturnPct, g_researchEquity);
   g_lastDailyWrittenKey = g_dailyDateKey;
}

void ResetOutcomeStatistics()
{
   g_lastOutcomeReason = "none";
   g_lastOutcomeR = 0.0;
   g_totalOutcomes = 0;
   g_totalWins = 0;
   g_totalLosses = 0;
   g_totalTimedExits = 0;
   g_totalNetR = 0.0;
   g_dailyDateKey = 0;
   g_lastDailyWrittenKey = 0;
   g_dailyOutcomes = 0;
   g_dailyWins = 0;
   g_dailyLosses = 0;
   g_dailyTimedExits = 0;
   g_dailyNetR = 0.0;
   g_researchEquity = InpResearchStartEquity;
   g_dailyStartEquity = g_researchEquity;
   g_researchPeakEquity = g_researchEquity;
   g_researchMaxDrawdownPct = 0.0;
}

void ResetSession(const int dateKey, const bool writeLog)
{
   if(g_dailyDateKey > 0 && dateKey != g_dailyDateKey)
      FinalizeDailySummary(writeLog);
   if(dateKey != g_dailyDateKey)
      StartDailyTracking(dateKey);
   g_sessionDateKey = dateKey;
   g_orBars = 0;
   g_orHigh = 0.0;
   g_orLow = 0.0;
   g_orReady = false;
   g_premarketBars = 0;
   g_premarketHigh = 0.0;
   g_premarketLow = 0.0;
   g_premarketReady = false;
   g_vwapPriceVolume = 0.0;
   g_vwapVolume = 0.0;
   g_sessionVwap = 0.0;
   ResetResearchState();
   DeleteOpeningRangeObjects();
}

void UpdateHorizontalLine(const string name, const double price, const color lineColor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawOpeningRange()
{
   if(g_orBars <= 0)
      return;

   UpdateHorizontalLine(g_orHighName, g_orHigh, clrDeepSkyBlue);
   UpdateHorizontalLine(g_orLowName, g_orLow, clrTomato);
}

void ProcessClosedBar(const MqlRates &bar, const bool writeLog)
{
   MqlDateTime ny = {};
   int dateKey = NewYorkDateKey(bar.time, ny);
   if(dateKey != g_sessionDateKey)
      ResetSession(dateKey, writeLog);

   if(ny.day_of_week == 0 || ny.day_of_week == 6)
      return;

   int nyMinutes = ny.hour * 60 + ny.min;
   if(nyMinutes >= g_premarketStartMinutes && nyMinutes < g_researchEndMinutes)
   {
      double typical = (bar.high + bar.low + bar.close) / 3.0;
      double volume = MathMax(1.0, (double)bar.tick_volume);
      g_vwapPriceVolume += typical * volume;
      g_vwapVolume += volume;
      g_sessionVwap = g_vwapPriceVolume / g_vwapVolume;
   }

   if(nyMinutes >= g_premarketStartMinutes && nyMinutes < g_orStartMinutes)
   {
      if(g_premarketBars == 0)
      {
         g_premarketHigh = bar.high;
         g_premarketLow = bar.low;
      }
      else
      {
         g_premarketHigh = MathMax(g_premarketHigh, bar.high);
         g_premarketLow = MathMin(g_premarketLow, bar.low);
      }
      g_premarketBars++;
   }
   else if(nyMinutes >= g_orStartMinutes && g_premarketBars > 0)
      g_premarketReady = true;

   if(nyMinutes >= g_orStartMinutes && nyMinutes < g_orEndMinutes)
   {
      if(g_orBars == 0)
      {
         g_orHigh = bar.high;
         g_orLow = bar.low;
      }
      else
      {
         g_orHigh = MathMax(g_orHigh, bar.high);
         g_orLow = MathMin(g_orLow, bar.low);
      }
      g_orBars++;
      g_orReady = false;
      DrawOpeningRange();
   }
   else if(nyMinutes >= g_orEndMinutes && g_orBars > 0 && !g_orReady)
   {
      g_orReady = true;
      DrawOpeningRange();
      if(writeLog)
         PrintFormat("%s | OR ready | high=%.*f low=%.*f bars=%d",
                     g_eaName, _Digits, g_orHigh, _Digits, g_orLow, g_orBars);
   }
}

void RebuildCurrentSession()
{
   g_sessionDateKey = 0;
   g_orBars = 0;
   g_orHigh = 0.0;
   g_orLow = 0.0;
   g_orReady = false;
   g_premarketBars = 0;
   g_premarketHigh = 0.0;
   g_premarketLow = 0.0;
   g_premarketReady = false;
   g_vwapPriceVolume = 0.0;
   g_vwapVolume = 0.0;
   g_sessionVwap = 0.0;

   datetime currentBarOpen = iTime(_Symbol, InpSignalTimeframe, 0);
   datetime fromTime = TimeTradeServer() - 3 * 86400;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe, fromTime,
                          TimeTradeServer(), rates);
   if(copied <= 0)
      return;

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time >= currentBarOpen)
         continue;
      ProcessClosedBar(rates[i], false);
   }
   DrawOpeningRange();
}

//+------------------------------------------------------------------+
//| Native causal squeeze engine                                     |
//+------------------------------------------------------------------+
int MaximumInt(const int a, const int b)
{
   return a > b ? a : b;
}

bool LoadSqueezeRates(const int shift, MqlRates &rates[])
{
   int bandHistory = MaximumInt(InpBBLength, InpKCLength) + 1;
   int momentumHistory = InpMomentumLength * 2 - 1;
   int required = MaximumInt(bandHistory, momentumHistory);
   ArrayResize(rates, required);
   return CopyRates(_Symbol, InpSignalTimeframe, shift, required, rates) == required;
}

double LinearRegressionEndpoint(const double &values[], const int count)
{
   if(count < 2 || ArraySize(values) < count)
      return 0.0;

   double sx = 0.0, sy = 0.0, sxy = 0.0, sx2 = 0.0;
   for(int i = 0; i < count; i++)
   {
      double x = (double)i;
      sx += x;
      sy += values[i];
      sxy += x * values[i];
      sx2 += x * x;
   }

   double denominator = count * sx2 - sx * sx;
   if(MathAbs(denominator) < 1e-12)
      return 0.0;

   double slope = (count * sxy - sx * sy) / denominator;
   double intercept = (sy - slope * sx) / count;
   return intercept + slope * (count - 1);
}

bool CalculateSqueezeAtShift(const int shift, SqueezeSnapshot &result)
{
   result.valid = false;
   result.squeezeOn = false;
   result.released = false;
   result.squeezeBars = 0;
   result.momentum = 0.0;
   result.momentumDelta = 0.0;
   result.releaseBias = 0;

   MqlRates rates[];
   if(!LoadSqueezeRates(shift, rates))
      return false;

   int total = ArraySize(rates);
   if(total < InpBBLength || total < InpKCLength + 1 ||
      total < InpMomentumLength * 2 - 1)
      return false;

   double bbMean = 0.0;
   int bbStart = total - InpBBLength;
   for(int i = bbStart; i < total; i++)
      bbMean += rates[i].close;
   bbMean /= InpBBLength;

   double variance = 0.0;
   for(int i = bbStart; i < total; i++)
   {
      double difference = rates[i].close - bbMean;
      variance += difference * difference;
   }
   double bbDeviation = MathSqrt(variance / InpBBLength) * InpBBMultiplier;
   double upperBB = bbMean + bbDeviation;
   double lowerBB = bbMean - bbDeviation;

   double kcMean = 0.0;
   double trMean = 0.0;
   int kcStart = total - InpKCLength;
   for(int i = kcStart; i < total; i++)
   {
      kcMean += rates[i].close;
      double trueRange = MathMax(rates[i].high - rates[i].low,
                         MathMax(MathAbs(rates[i].high - rates[i-1].close),
                                 MathAbs(rates[i].low - rates[i-1].close)));
      trMean += trueRange;
   }
   kcMean /= InpKCLength;
   trMean /= InpKCLength;
   double upperKC = kcMean + trMean * InpKCMultiplier;
   double lowerKC = kcMean - trMean * InpKCMultiplier;
   result.squeezeOn = lowerBB > lowerKC && upperBB < upperKC;

   double transformed[];
   ArrayResize(transformed, InpMomentumLength);
   int firstTarget = total - InpMomentumLength;
   for(int target = firstTarget; target < total; target++)
   {
      int windowStart = target - InpMomentumLength + 1;
      double highest = rates[windowStart].high;
      double lowest = rates[windowStart].low;
      double closeMean = 0.0;
      for(int i = windowStart; i <= target; i++)
      {
         highest = MathMax(highest, rates[i].high);
         lowest = MathMin(lowest, rates[i].low);
         closeMean += rates[i].close;
      }
      closeMean /= InpMomentumLength;
      double center = ((highest + lowest) * 0.5 + closeMean) * 0.5;
      transformed[target - firstTarget] = rates[target].close - center;
   }

   result.momentum = LinearRegressionEndpoint(transformed, InpMomentumLength);
   result.valid = true;
   return true;
}

int CountSqueezeBarsFromShift(const int firstShift)
{
   int count = 0;
   int limit = MathMax(1, InpMaxSqueezeScan);
   for(int shift = firstShift; shift < firstShift + limit; shift++)
   {
      SqueezeSnapshot barState;
      if(!CalculateSqueezeAtShift(shift, barState) || !barState.squeezeOn)
         break;
      count++;
   }
   return count;
}

void DrawSqueezeRelease(const MqlRates &bar, const int bias)
{
   if(!InpDrawReleaseMarkers)
      return;

   string name = "NAS100_NEXUS_SQZ_" + IntegerToString((long)bar.time);
   double offset = MathMax(bar.high - bar.low,
                           SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0) * 0.25;
   double price = bias > 0 ? bar.low - offset : bar.high + offset;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, bar.time, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bias > 0 ? 233 : bias < 0 ? 234 : 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bias > 0 ? clrLime : bias < 0 ? clrTomato : clrGold);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void WriteResearchRow(const MqlRates &bar, const SqueezeSnapshot &state)
{
   if(!InpWriteBarLog)
      return;

   FolderCreate("NAS100_Nexus");
   string safeSymbol = _Symbol;
   StringReplace(safeSymbol, "/", "_");
   string fileName = "NAS100_Nexus\\" + safeSymbol + "_M5_research_v050.csv";
   int handle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("%s | research log open failed: %d", g_eaName, GetLastError());
      return;
   }

   if(FileSize(handle) == 0)
      FileWrite(handle, "server_time", "new_york_time", "open", "high", "low", "close",
                "tick_volume", "or_ready", "or_high", "or_low", "squeeze_on",
                "squeeze_release", "squeeze_bars", "momentum", "momentum_delta", "release_bias",
                "setup_state", "strategy_signal", "hyp_entry", "hyp_stop", "hyp_target",
                "outcome_active", "outcome_event", "last_outcome", "last_net_r",
                "total_outcomes", "wins", "losses", "timed_exits", "cumulative_net_r");

   FileSeek(handle, 0, SEEK_END);
   datetime nyTime = ServerToNewYork(bar.time);
   FileWrite(handle,
             TimeToString(bar.time, TIME_DATE|TIME_MINUTES),
             TimeToString(nyTime, TIME_DATE|TIME_MINUTES),
             DoubleToString(bar.open, _Digits),
             DoubleToString(bar.high, _Digits),
             DoubleToString(bar.low, _Digits),
             DoubleToString(bar.close, _Digits),
             IntegerToString(bar.tick_volume),
             g_orReady ? 1 : 0,
             DoubleToString(g_orHigh, _Digits),
             DoubleToString(g_orLow, _Digits),
             state.squeezeOn ? 1 : 0,
             state.released ? 1 : 0,
             state.squeezeBars,
             DoubleToString(state.momentum, 8),
             DoubleToString(state.momentumDelta, 8),
             state.releaseBias,
             (int)g_researchState,
             g_currentResearchSignal,
             DoubleToString(g_hypotheticalEntry, _Digits),
             DoubleToString(g_hypotheticalStop, _Digits),
             DoubleToString(g_hypotheticalTarget, _Digits),
             g_outcomeActive ? 1 : 0,
             g_currentOutcome,
             g_lastOutcomeReason,
             DoubleToString(g_lastOutcomeR, 4),
             g_totalOutcomes,
             g_totalWins,
             g_totalLosses,
             g_totalTimedExits,
             DoubleToString(g_totalNetR, 4));
   FileClose(handle);
}

bool BuildSqueezeSnapshotAtShift(const int shift, SqueezeSnapshot &snapshot)
{
   SqueezeSnapshot current;
   SqueezeSnapshot previous;
   if(!CalculateSqueezeAtShift(shift, current) ||
      !CalculateSqueezeAtShift(shift + 1, previous))
      return false;

   current.momentumDelta = current.momentum - previous.momentum;
   current.released = previous.squeezeOn && !current.squeezeOn;
   current.squeezeBars = current.squeezeOn ? CountSqueezeBarsFromShift(shift) :
                         current.released ? CountSqueezeBarsFromShift(shift + 1) : 0;
   if(current.released && current.momentum > 0.0 && current.momentumDelta > 0.0)
      current.releaseBias = 1;
   else if(current.released && current.momentum < 0.0 && current.momentumDelta < 0.0)
      current.releaseBias = -1;
   else
      current.releaseBias = 0;

   snapshot = current;
   return true;
}

void UpdateSqueezeState(const MqlRates &closedBar, const bool writeLog)
{
   SqueezeSnapshot current;
   if(!BuildSqueezeSnapshotAtShift(1, current))
   {
      g_squeeze.valid = false;
      return;
   }

   g_squeeze = current;
   if(current.released)
   {
      DrawSqueezeRelease(closedBar, current.releaseBias);
      if(writeLog)
         PrintFormat("%s | squeeze release | bars=%d momentum=%.5f delta=%.5f bias=%d",
                     g_eaName, current.squeezeBars, current.momentum,
                     current.momentumDelta, current.releaseBias);
   }
}

//+------------------------------------------------------------------+
//| OR breakout / retest research engine                             |
//+------------------------------------------------------------------+
string ResearchStateText()
{
   switch(g_researchState)
   {
      case RESEARCH_WAIT_LONG_RETEST:  return "WAIT LONG RETEST";
      case RESEARCH_WAIT_SHORT_RETEST: return "WAIT SHORT RETEST";
      case RESEARCH_LONG_SIGNAL:       return "LONG SIGNAL";
      case RESEARCH_SHORT_SIGNAL:      return "SHORT SIGNAL";
      default:                         return "IDLE";
   }
}

bool CalculateATRAtShift(const int shift, double &atr)
{
   atr = 0.0;
   MqlRates rates[];
   int required = InpATRLength + 1;
   ArrayResize(rates, required);
   if(CopyRates(_Symbol, InpSignalTimeframe, shift, required, rates) != required)
      return false;

   double sum = 0.0;
   for(int i = 1; i < required; i++)
   {
      double trueRange = MathMax(rates[i].high - rates[i].low,
                         MathMax(MathAbs(rates[i].high - rates[i-1].close),
                                 MathAbs(rates[i].low - rates[i-1].close)));
      sum += trueRange;
   }
   atr = sum / InpATRLength;
   return atr > 0.0;
}

bool HasAlignedSqueezeContext(const MqlRates &bar, const int direction)
{
   if(!InpRequireSqueeze)
      return true;
   if(g_lastReleaseTime <= 0 || g_lastReleaseBias != direction ||
      g_lastReleaseDuration < InpMinimumSqueezeBars)
      return false;

   int periodSeconds = PeriodSeconds(InpSignalTimeframe);
   if(periodSeconds <= 0 || bar.time < g_lastReleaseTime)
      return false;
   int ageBars = (int)((bar.time - g_lastReleaseTime) / periodSeconds);
   return ageBars <= InpReleaseLookbackBars;
}

void DrawBreakoutMarker(const MqlRates &bar, const int direction)
{
   string name = "NAS100_NEXUS_BREAK_" + IntegerToString((long)bar.time);
   double offset = MathMax(bar.high - bar.low,
                           SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0) * 0.15;
   double price = direction > 0 ? bar.low - offset : bar.high + offset;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, bar.time, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 158);
   ObjectSetInteger(0, name, OBJPROP_COLOR, direction > 0 ? clrDodgerBlue : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawHypotheticalLevel(const string suffix, const datetime startTime,
                           const double price, const color lineColor)
{
   string name = "NAS100_NEXUS_SIGNAL_" + IntegerToString((long)startTime) + "_" + suffix;
   datetime endTime = startTime + PeriodSeconds(InpSignalTimeframe) * 10;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void WriteOutcomeTrade(const datetime exitTime, const double exitPrice,
                       const string reason, const double grossR, const double netR)
{
   if(!InpWriteOutcomeLog)
      return;

   FolderCreate("NAS100_Nexus");
   string safeSymbol = _Symbol;
   StringReplace(safeSymbol, "/", "_");
   string fileName = "NAS100_Nexus\\" + safeSymbol + "_M5_outcomes_v050.csv";
   int handle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("%s | outcome log open failed: %d", g_eaName, GetLastError());
      return;
   }

   if(FileSize(handle) == 0)
      FileWrite(handle, "entry_server_time", "entry_new_york_time", "exit_server_time",
                "exit_new_york_time", "direction", "entry", "stop", "target", "exit_price",
                "risk_distance", "bars_held", "exit_reason", "gross_r", "cost_r", "net_r",
                "mfe_r", "mae_r", "or_high", "or_low", "confirmation_score");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(g_outcomeEntryTime, TIME_DATE|TIME_MINUTES),
             TimeToString(ServerToNewYork(g_outcomeEntryTime), TIME_DATE|TIME_MINUTES),
             TimeToString(exitTime, TIME_DATE|TIME_MINUTES),
             TimeToString(ServerToNewYork(exitTime), TIME_DATE|TIME_MINUTES),
             g_outcomeDirection > 0 ? "LONG" : "SHORT",
             DoubleToString(g_hypotheticalEntry, _Digits),
             DoubleToString(g_hypotheticalStop, _Digits),
             DoubleToString(g_hypotheticalTarget, _Digits),
             DoubleToString(exitPrice, _Digits),
             DoubleToString(g_outcomeRisk, _Digits),
             g_outcomeBars,
             reason,
             DoubleToString(grossR, 4),
             DoubleToString(g_outcomeCostR, 4),
             DoubleToString(netR, 4),
             DoubleToString(g_outcomeMfeR, 4),
             DoubleToString(g_outcomeMaeR, 4),
             DoubleToString(g_outcomeOrHigh, _Digits),
             DoubleToString(g_outcomeOrLow, _Digits),
             g_outcomeSqueezeBars);
   FileClose(handle);
}

void DrawOutcomeMarker(const MqlRates &bar, const double price, const double netR)
{
   string name = "NAS100_NEXUS_EXIT_" + IntegerToString((long)g_outcomeEntryTime);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, bar.time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, netR >= 0.0 ? clrLime : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void ResolveOutcome(const MqlRates &bar, const double exitPrice, const string reason,
                    const int eventCode, const double grossR, const bool writeLog)
{
   double netR = grossR - g_outcomeCostR;
   g_lastOutcomeReason = reason;
   g_lastOutcomeR = netR;
   g_currentOutcome = eventCode;
   g_totalOutcomes++;
   g_totalNetR += netR;
   if(netR > 0.0)
      g_totalWins++;
   else
      g_totalLosses++;
   if(eventCode == 2 || eventCode == 3)
      g_totalTimedExits++;

   g_dailyOutcomes++;
   g_dailyNetR += netR;
   if(netR > 0.0)
      g_dailyWins++;
   else
      g_dailyLosses++;
   if(eventCode == 2 || eventCode == 3)
      g_dailyTimedExits++;

   double equityMultiplier = 1.0 + netR * InpResearchRiskPct / 100.0;
   g_researchEquity *= MathMax(0.0, equityMultiplier);
   g_researchPeakEquity = MathMax(g_researchPeakEquity, g_researchEquity);
   double drawdownPct = g_researchPeakEquity > 0.0
                        ? (g_researchPeakEquity - g_researchEquity) /
                          g_researchPeakEquity * 100.0 : 0.0;
   g_researchMaxDrawdownPct = MathMax(g_researchMaxDrawdownPct, drawdownPct);

   if(writeLog)
      WriteOutcomeTrade(bar.time, exitPrice, reason, grossR, netR);
   DrawOutcomeMarker(bar, exitPrice, netR);
   g_outcomeActive = false;

   if(writeLog)
      PrintFormat("%s | outcome %s | gross=%.3fR cost=%.3fR net=%.3fR bars=%d MFE=%.3fR MAE=%.3fR",
                  g_eaName, reason, grossR, g_outcomeCostR, netR,
                  g_outcomeBars, g_outcomeMfeR, g_outcomeMaeR);
}

void ProcessOutcomeBar(const MqlRates &bar, const bool writeLog)
{
   g_currentOutcome = 0;
   if(!g_outcomeActive || bar.time <= g_outcomeEntryTime || g_outcomeRisk <= 0.0)
      return;

   g_outcomeBars++;
   double favorableR = g_outcomeDirection > 0
                       ? (bar.high - g_hypotheticalEntry) / g_outcomeRisk
                       : (g_hypotheticalEntry - bar.low) / g_outcomeRisk;
   double adverseR = g_outcomeDirection > 0
                     ? (g_hypotheticalEntry - bar.low) / g_outcomeRisk
                     : (bar.high - g_hypotheticalEntry) / g_outcomeRisk;
   g_outcomeMfeR = MathMax(g_outcomeMfeR, favorableR);
   g_outcomeMaeR = MathMax(g_outcomeMaeR, adverseR);

   bool stopHit = g_outcomeDirection > 0
                  ? bar.low <= g_hypotheticalStop
                  : bar.high >= g_hypotheticalStop;
   bool targetHit = g_outcomeDirection > 0
                    ? bar.high >= g_hypotheticalTarget
                    : bar.low <= g_hypotheticalTarget;

   if(stopHit && (!targetHit || InpStopFirstSameBar))
   {
      ResolveOutcome(bar, g_hypotheticalStop, targetHit ? "BOTH_STOP_FIRST" : "STOP",
                     -1, -1.0, writeLog);
      return;
   }
   if(targetHit)
   {
      ResolveOutcome(bar, g_hypotheticalTarget, stopHit ? "BOTH_TARGET_FIRST" : "TARGET",
                     1, InpResearchTargetR, writeLog);
      return;
   }

   MqlDateTime ny = {};
   NewYorkDateKey(bar.time, ny);
   int nyMinutes = ny.hour * 60 + ny.min;
   bool maxBarsReached = g_outcomeBars >= InpOutcomeMaxBars;
   bool sessionEnded = nyMinutes >= g_outcomeCloseMinutes;
   if(maxBarsReached || sessionEnded)
   {
      double grossR = g_outcomeDirection > 0
                      ? (bar.close - g_hypotheticalEntry) / g_outcomeRisk
                      : (g_hypotheticalEntry - bar.close) / g_outcomeRisk;
      ResolveOutcome(bar, bar.close, sessionEnded ? "SESSION_CLOSE" : "TIMEOUT",
                     sessionEnded ? 3 : 2, grossR, writeLog);
   }
}

bool RegisterResearchSignal(const MqlRates &bar, const int direction, const double atr,
                            const bool writeLog)
{
   double entry = bar.close;
   double stop = direction > 0
                 ? MathMin(bar.low, g_orHigh) - atr * InpStopBufferATR
                 : MathMax(bar.high, g_orLow) + atr * InpStopBufferATR;
   double riskDistance = MathAbs(entry - stop);
   if(riskDistance < SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))
      return false;

   g_hypotheticalEntry = entry;
   g_hypotheticalStop = stop;
   g_hypotheticalTarget = direction > 0
                          ? entry + riskDistance * InpResearchTargetR
                          : entry - riskDistance * InpResearchTargetR;
   g_currentResearchSignal = direction;
   g_lastResearchSignalTime = bar.time;
   g_signalsToday++;
   g_researchState = direction > 0 ? RESEARCH_LONG_SIGNAL : RESEARCH_SHORT_SIGNAL;
   g_outcomeActive = true;
   g_outcomeDirection = direction;
   g_outcomeEntryTime = bar.time;
   g_outcomeBars = 0;
   g_outcomeRisk = riskDistance;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_outcomeCostR = riskDistance > 0.0
                    ? (MathMax(0.0, (double)bar.spread) + InpSlippagePoints) * point / riskDistance
                    : 0.0;
   g_outcomeMfeR = 0.0;
   g_outcomeMaeR = 0.0;
   g_outcomeOrHigh = g_orHigh;
   g_outcomeOrLow = g_orLow;
   g_outcomeSqueezeBars = g_lastReleaseDuration;

   string arrowName = "NAS100_NEXUS_ENTRY_" + IntegerToString((long)bar.time);
   double arrowPrice = direction > 0 ? bar.low : bar.high;
   if(ObjectFind(0, arrowName) < 0)
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, bar.time, arrowPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, direction > 0 ? 233 : 234);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, direction > 0 ? clrLime : clrTomato);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

   DrawHypotheticalLevel("ENTRY", bar.time, g_hypotheticalEntry, clrWhite);
   DrawHypotheticalLevel("STOP", bar.time, g_hypotheticalStop, clrTomato);
   DrawHypotheticalLevel("TARGET", bar.time, g_hypotheticalTarget, clrLime);

   if(writeLog)
      PrintFormat("%s | research %s | entry=%.*f stop=%.*f target=%.*f",
                  g_eaName, direction > 0 ? "LONG" : "SHORT",
                  _Digits, entry, _Digits, stop, _Digits, g_hypotheticalTarget);
   return true;
}

void ProcessResearchBar(const MqlRates &bar, const SqueezeSnapshot &squeeze,
                        const int shift, const bool writeLog)
{
   g_currentResearchSignal = 0;
   if(squeeze.released && squeeze.releaseBias != 0)
   {
      g_lastReleaseTime = bar.time;
      g_lastReleaseBias = squeeze.releaseBias;
      g_lastReleaseDuration = squeeze.squeezeBars;
   }

   MqlDateTime ny = {};
   int dateKey = NewYorkDateKey(bar.time, ny);
   if(dateKey != g_sessionDateKey || ny.day_of_week == 0 || ny.day_of_week == 6)
      return;
   int nyMinutes = ny.hour * 60 + ny.min;
   if(!g_orReady || nyMinutes < g_orEndMinutes || nyMinutes >= g_researchEndMinutes)
   {
      if(nyMinutes >= g_researchEndMinutes &&
         (g_researchState == RESEARCH_WAIT_LONG_RETEST ||
          g_researchState == RESEARCH_WAIT_SHORT_RETEST))
         g_researchState = RESEARCH_IDLE;
      return;
   }

   double atr = 0.0;
   if(!CalculateATRAtShift(shift, atr))
      return;

   if(g_researchState == RESEARCH_WAIT_LONG_RETEST)
   {
      double tolerance = atr * InpRetestToleranceATR;
      bool invalidated = bar.close < g_orHigh - atr * InpInvalidationATR;
      bool confirmed = bar.low <= g_orHigh + tolerance &&
                       bar.close > g_orHigh && bar.close > bar.open;
      if(confirmed)
         RegisterResearchSignal(bar, 1, atr, writeLog);
      else if(invalidated || --g_retestBarsRemaining <= 0)
         g_researchState = RESEARCH_IDLE;
      return;
   }

   if(g_researchState == RESEARCH_WAIT_SHORT_RETEST)
   {
      double tolerance = atr * InpRetestToleranceATR;
      bool invalidated = bar.close > g_orLow + atr * InpInvalidationATR;
      bool confirmed = bar.high >= g_orLow - tolerance &&
                       bar.close < g_orLow && bar.close < bar.open;
      if(confirmed)
         RegisterResearchSignal(bar, -1, atr, writeLog);
      else if(invalidated || --g_retestBarsRemaining <= 0)
         g_researchState = RESEARCH_IDLE;
      return;
   }

   if(g_researchState == RESEARCH_LONG_SIGNAL ||
      g_researchState == RESEARCH_SHORT_SIGNAL ||
      g_signalsToday >= InpMaximumSignalsDay)
      return;

   double previousClose = iClose(_Symbol, InpSignalTimeframe, shift + 1);
   double longBreakLevel = g_orHigh + atr * InpBreakoutBufferATR;
   double shortBreakLevel = g_orLow - atr * InpBreakoutBufferATR;
   bool longBreak = previousClose <= longBreakLevel && bar.close > longBreakLevel &&
                    bar.close > bar.open && HasAlignedSqueezeContext(bar, 1);
   bool shortBreak = previousClose >= shortBreakLevel && bar.close < shortBreakLevel &&
                     bar.close < bar.open && HasAlignedSqueezeContext(bar, -1);

   if(longBreak)
   {
      g_researchState = RESEARCH_WAIT_LONG_RETEST;
      g_breakoutTime = bar.time;
      g_breakoutLevel = g_orHigh;
      g_retestBarsRemaining = InpRetestWindowBars;
      DrawBreakoutMarker(bar, 1);
   }
   else if(shortBreak)
   {
      g_researchState = RESEARCH_WAIT_SHORT_RETEST;
      g_breakoutTime = bar.time;
      g_breakoutLevel = g_orLow;
      g_retestBarsRemaining = InpRetestWindowBars;
      DrawBreakoutMarker(bar, -1);
   }
}

void RebuildResearchState()
{
   ResetResearchState();
   datetime currentBarOpen = iTime(_Symbol, InpSignalTimeframe, 0);
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe,
                          TimeTradeServer() - 2 * 86400,
                          TimeTradeServer(), rates);
   if(copied <= 0)
      return;

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time >= currentBarOpen)
         continue;
      MqlDateTime ny = {};
      if(NewYorkDateKey(rates[i].time, ny) != g_sessionDateKey)
         continue;
      int shift = iBarShift(_Symbol, InpSignalTimeframe, rates[i].time, true);
      if(shift < 1)
         continue;
      SqueezeSnapshot snapshot;
      if(!BuildSqueezeSnapshotAtShift(shift, snapshot))
         continue;
      g_squeeze = snapshot;
      ProcessOutcomeBar(rates[i], false);
      ProcessResearchBar(rates[i], snapshot, shift, false);
   }
}

//+------------------------------------------------------------------+
//| Liquidity sweep / displacement / pullback engine                 |
//+------------------------------------------------------------------+
string LiquidityStateText()
{
   switch(g_liquidityState)
   {
      case LIQUIDITY_WAIT_LONG_DISPLACEMENT:  return "LONG SWEEP -> DISPLACE";
      case LIQUIDITY_WAIT_SHORT_DISPLACEMENT: return "SHORT SWEEP -> DISPLACE";
      case LIQUIDITY_WAIT_LONG_PULLBACK:      return "LONG WAIT PULLBACK";
      case LIQUIDITY_WAIT_SHORT_PULLBACK:     return "SHORT WAIT PULLBACK";
      default:                                return "SCAN LIQUIDITY";
   }
}

double RelativeVolumeAtShift(const int shift)
{
   MqlRates rates[];
   int required = InpRelativeVolumeLength + 1;
   ArrayResize(rates, required);
   if(CopyRates(_Symbol, InpSignalTimeframe, shift, required, rates) != required)
      return 0.0;

   double average = 0.0;
   for(int i = 0; i < required - 1; i++)
      average += (double)rates[i].tick_volume;
   average /= InpRelativeVolumeLength;
   return average > 0.0 ? (double)rates[required - 1].tick_volume / average : 0.0;
}

int DisplacementConfirmationScore(const MqlRates &bar, const int direction,
                                  const int shift)
{
   int score = 0;
   if(InpUseVWAPScore && g_sessionVwap > 0.0 &&
      (direction > 0 ? bar.close > g_sessionVwap : bar.close < g_sessionVwap))
      score++;
   if(InpUseRelativeVolScore && RelativeVolumeAtShift(shift) >= InpRelativeVolumeMin)
      score++;
   return score;
}

void DrawLiquiditySweep(const MqlRates &bar, const int direction)
{
   string name = "NAS100_NEXUS_SWEEP_" + IntegerToString((long)bar.time);
   double price = direction > 0 ? bar.low : bar.high;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, bar.time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, direction > 0 ? clrAqua : clrOrange);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

bool RegisterLiquiditySignal(const MqlRates &bar, const int direction,
                             const double atr, const bool writeLog)
{
   double entry = bar.close;
   double stop = direction > 0
                 ? MathMin(g_sweepExtreme, bar.low) - atr * InpStopBufferATR
                 : MathMax(g_sweepExtreme, bar.high) + atr * InpStopBufferATR;
   double riskDistance = MathAbs(entry - stop);
   if(riskDistance < SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))
      return false;

   g_hypotheticalEntry = entry;
   g_hypotheticalStop = stop;
   g_hypotheticalTarget = direction > 0
                          ? entry + riskDistance * InpResearchTargetR
                          : entry - riskDistance * InpResearchTargetR;
   g_currentResearchSignal = direction;
   g_lastResearchSignalTime = bar.time;
   g_signalsToday++;
   g_outcomeActive = true;
   g_outcomeDirection = direction;
   g_outcomeEntryTime = bar.time;
   g_outcomeBars = 0;
   g_outcomeRisk = riskDistance;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_outcomeCostR = riskDistance > 0.0
                    ? (MathMax(0.0, (double)bar.spread) + InpSlippagePoints) * point / riskDistance
                    : 0.0;
   g_outcomeMfeR = 0.0;
   g_outcomeMaeR = 0.0;
   g_outcomeOrHigh = g_orHigh;
   g_outcomeOrLow = g_orLow;
   g_outcomeSqueezeBars = g_displacementScore;
   g_liquidityState = LIQUIDITY_IDLE;

   string arrowName = "NAS100_NEXUS_LIQ_ENTRY_" + IntegerToString((long)bar.time);
   if(ObjectFind(0, arrowName) < 0)
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, bar.time,
                   direction > 0 ? bar.low : bar.high);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, direction > 0 ? 233 : 234);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, direction > 0 ? clrLime : clrTomato);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
   DrawHypotheticalLevel("ENTRY", bar.time, entry, clrWhite);
   DrawHypotheticalLevel("STOP", bar.time, stop, clrTomato);
   DrawHypotheticalLevel("TARGET", bar.time, g_hypotheticalTarget, clrLime);

   if(writeLog)
      PrintFormat("%s | liquidity %s | score=%d entry=%.*f stop=%.*f target=%.*f",
                  g_eaName, direction > 0 ? "LONG" : "SHORT", g_displacementScore,
                  _Digits, entry, _Digits, stop, _Digits, g_hypotheticalTarget);
   return true;
}

void ProcessLiquidityBar(const MqlRates &bar, const int shift, const bool writeLog)
{
   g_currentResearchSignal = 0;
   MqlDateTime ny = {};
   int dateKey = NewYorkDateKey(bar.time, ny);
   int nyMinutes = ny.hour * 60 + ny.min;
   if(dateKey != g_sessionDateKey || ny.day_of_week == 0 || ny.day_of_week == 6 ||
      !g_orReady || nyMinutes < g_orEndMinutes || nyMinutes >= g_researchEndMinutes)
   {
      if(nyMinutes >= g_researchEndMinutes)
         g_liquidityState = LIQUIDITY_IDLE;
      return;
   }

   double atr = 0.0;
   if(!CalculateATRAtShift(shift, atr))
      return;

   if(g_liquidityState == LIQUIDITY_WAIT_LONG_DISPLACEMENT ||
      g_liquidityState == LIQUIDITY_WAIT_SHORT_DISPLACEMENT)
   {
      int direction = g_liquidityState == LIQUIDITY_WAIT_LONG_DISPLACEMENT ? 1 : -1;
      bool invalidated = direction > 0
                         ? bar.close < g_sweepExtreme - atr * InpInvalidationATR
                         : bar.close > g_sweepExtreme + atr * InpInvalidationATR;
      double previousHigh = iHigh(_Symbol, InpSignalTimeframe, shift + 1);
      double previousLow = iLow(_Symbol, InpSignalTimeframe, shift + 1);
      double body = MathAbs(bar.close - bar.open);
      bool displaced = direction > 0
                       ? bar.close > previousHigh && bar.close > bar.open &&
                         body >= atr * InpDisplacementBodyATR
                       : bar.close < previousLow && bar.close < bar.open &&
                         body >= atr * InpDisplacementBodyATR;
      if(displaced)
      {
         g_displacementScore = DisplacementConfirmationScore(bar, direction, shift);
         if(g_displacementScore >= InpMinimumConfirmScore)
         {
            g_pullbackPrice = (bar.open + bar.close) * 0.5;
            g_liquidityBarsRemaining = InpPullbackWindowBars;
            g_liquidityState = direction > 0 ? LIQUIDITY_WAIT_LONG_PULLBACK
                                             : LIQUIDITY_WAIT_SHORT_PULLBACK;
            return;
         }
      }
      if(invalidated || --g_liquidityBarsRemaining <= 0)
         g_liquidityState = LIQUIDITY_IDLE;
      return;
   }

   if(g_liquidityState == LIQUIDITY_WAIT_LONG_PULLBACK ||
      g_liquidityState == LIQUIDITY_WAIT_SHORT_PULLBACK)
   {
      int direction = g_liquidityState == LIQUIDITY_WAIT_LONG_PULLBACK ? 1 : -1;
      double tolerance = atr * InpPullbackToleranceATR;
      bool invalidated = direction > 0
                         ? bar.close < g_sweepExtreme - atr * InpInvalidationATR
                         : bar.close > g_sweepExtreme + atr * InpInvalidationATR;
      bool confirmed = direction > 0
                       ? bar.low <= g_pullbackPrice + tolerance &&
                         bar.close > g_pullbackPrice && bar.close > bar.open
                       : bar.high >= g_pullbackPrice - tolerance &&
                         bar.close < g_pullbackPrice && bar.close < bar.open;
      if(confirmed)
         RegisterLiquiditySignal(bar, direction, atr, writeLog);
      else if(invalidated || --g_liquidityBarsRemaining <= 0)
         g_liquidityState = LIQUIDITY_IDLE;
      return;
   }

   if(g_outcomeActive || g_signalsToday >= InpMaximumSignalsDay)
      return;

   double buffer = atr * InpSweepBufferATR;
   bool longSweep = false;
   bool shortSweep = false;
   double longLevel = 0.0;
   double shortLevel = 0.0;
   if(InpUseOpeningRange)
   {
      longSweep = bar.low < g_orLow - buffer && bar.close > g_orLow;
      shortSweep = bar.high > g_orHigh + buffer && bar.close < g_orHigh;
      longLevel = g_orLow;
      shortLevel = g_orHigh;
   }
   if(InpUsePremarketLevels && g_premarketReady)
   {
      bool sweptLow = bar.low < g_premarketLow - buffer && bar.close > g_premarketLow;
      bool sweptHigh = bar.high > g_premarketHigh + buffer && bar.close < g_premarketHigh;
      if(sweptLow)
      {
         longSweep = true;
         longLevel = g_premarketLow;
      }
      if(sweptHigh)
      {
         shortSweep = true;
         shortLevel = g_premarketHigh;
      }
   }

   if(longSweep && !shortSweep)
   {
      g_liquidityState = LIQUIDITY_WAIT_LONG_DISPLACEMENT;
      g_liquiditySweepTime = bar.time;
      g_liquidityLevel = longLevel;
      g_sweepExtreme = bar.low;
      g_liquidityBarsRemaining = InpDisplacementBars;
      DrawLiquiditySweep(bar, 1);
   }
   else if(shortSweep && !longSweep)
   {
      g_liquidityState = LIQUIDITY_WAIT_SHORT_DISPLACEMENT;
      g_liquiditySweepTime = bar.time;
      g_liquidityLevel = shortLevel;
      g_sweepExtreme = bar.high;
      g_liquidityBarsRemaining = InpDisplacementBars;
      DrawLiquiditySweep(bar, -1);
   }
}

void RebuildLiquidityState()
{
   g_sessionDateKey = 0;
   g_orBars = 0;
   g_orHigh = 0.0;
   g_orLow = 0.0;
   g_orReady = false;
   g_premarketBars = 0;
   g_premarketHigh = 0.0;
   g_premarketLow = 0.0;
   g_premarketReady = false;
   g_vwapPriceVolume = 0.0;
   g_vwapVolume = 0.0;
   g_sessionVwap = 0.0;
   ResetResearchState();

   datetime currentBarOpen = iTime(_Symbol, InpSignalTimeframe, 0);
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe,
                          TimeTradeServer() - 3 * 86400, TimeTradeServer(), rates);
   if(copied <= 0)
      return;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time >= currentBarOpen)
         continue;
      int shift = iBarShift(_Symbol, InpSignalTimeframe, rates[i].time, true);
      if(shift < 1)
         continue;
      ProcessOutcomeBar(rates[i], false);
      ProcessClosedBar(rates[i], false);
      ProcessLiquidityBar(rates[i], shift, false);
   }
   DrawOpeningRange();
}

//+------------------------------------------------------------------+
//| Broker-aware risk preview                                        |
//+------------------------------------------------------------------+
double NormalizeVolumeDown(const double requested)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0 || requested < minVolume)
      return 0.0;

   double volume = MathFloor((requested + 1e-12) / step) * step;
   volume = MathMin(volume, maxVolume);
   if(volume < minVolume)
      return 0.0;
   return NormalizeDouble(volume, 8);
}

bool CalculateLoss(const double volume, const double stopDistance,
                   double &lossAmount)
{
   lossAmount = 0.0;
   if(volume <= 0.0 || stopDistance <= 0.0)
      return false;

   MqlTick tick = {};
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0)
      return false;

   double result = 0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, volume,
                       tick.ask, tick.ask - stopDistance, result))
      return false;

   lossAmount = MathAbs(result);
   return true;
}

double PreviewRiskVolume(double &minVolumeLoss, double &actualLoss)
{
   minVolumeLoss = 0.0;
   actualLoss = 0.0;
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(!CalculateLoss(minVolume, InpPreviewStopDistance, minVolumeLoss))
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskBudget = equity * MathMax(0.0, InpPreviewRiskPct) / 100.0;
   if(minVolumeLoss > riskBudget || minVolumeLoss <= 0.0)
      return 0.0;

   double rawVolume = minVolume * riskBudget / minVolumeLoss;
   double volume = NormalizeVolumeDown(rawVolume);
   if(volume > 0.0)
      CalculateLoss(volume, InpPreviewStopDistance, actualLoss);
   return volume;
}

//+------------------------------------------------------------------+
//| Status panel                                                     |
//+------------------------------------------------------------------+
string SessionStateText(const int nyMinutes)
{
   if(nyMinutes < g_orStartMinutes)
      return "PRE-OPEN";
   if(nyMinutes < g_orEndMinutes)
      return "BUILDING OR";
   if(nyMinutes < g_researchEndMinutes)
      return g_orReady ? "RESEARCH WINDOW" : "OR DATA MISSING";
   return "WINDOW CLOSED";
}

void RenderStatus()
{
   g_serverUtcOffset = ResolveServerUtcOffset();

   datetime serverNow = TimeTradeServer();
   datetime nyNow = ServerToNewYork(serverNow);
   MqlDateTime ny = {};
   TimeToStruct(nyNow, ny);
   int nyMinutes = ny.hour * 60 + ny.min;

   MqlTick tick = {};
   SymbolInfoTick(_Symbol, tick);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spreadPrice = tick.ask - tick.bid;
   double spreadPoints = point > 0.0 ? spreadPrice / point : 0.0;

   double minLoss = 0.0;
   double previewLoss = 0.0;
   double previewVolume = PreviewRiskVolume(minLoss, previewLoss);
   double riskBudget = AccountInfoDouble(ACCOUNT_EQUITY) *
                       MathMax(0.0, InpPreviewRiskPct) / 100.0;
   string previewText = previewVolume > 0.0
                        ? StringFormat("%.4f lots / %.2f loss", previewVolume, previewLoss)
                        : StringFormat("REJECT (min loss %.2f > budget %.2f)", minLoss, riskBudget);

   string orText = g_orBars > 0
                   ? StringFormat("%.*f / %.*f (%d bars)",
                                  _Digits, g_orHigh, _Digits, g_orLow, g_orBars)
                   : "not captured";

   string squeezeText = !g_squeeze.valid ? "insufficient history" :
                        g_squeeze.squeezeOn
                        ? StringFormat("ON (%d bars)", g_squeeze.squeezeBars) :
                        g_squeeze.released
                        ? StringFormat("RELEASE (%d bars, bias %d)",
                                       g_squeeze.squeezeBars, g_squeeze.releaseBias) : "OFF";
   string premarketText = g_premarketBars > 0
                          ? StringFormat("%.*f / %.*f (%d bars)",
                                         _Digits, g_premarketHigh,
                                         _Digits, g_premarketLow, g_premarketBars)
                          : "not captured";
   string levelText = g_lastResearchSignalTime > 0
                      ? StringFormat("%.*f / %.*f / %.*f",
                                     _Digits, g_hypotheticalEntry,
                                     _Digits, g_hypotheticalStop,
                                     _Digits, g_hypotheticalTarget)
                      : "none";
   string outcomeText = g_outcomeActive
                        ? StringFormat("ACTIVE %s | %d bars | MFE %.2fR / MAE %.2fR",
                                       g_outcomeDirection > 0 ? "LONG" : "SHORT",
                                       g_outcomeBars, g_outcomeMfeR, g_outcomeMaeR)
                        : StringFormat("%s %.2fR", g_lastOutcomeReason, g_lastOutcomeR);
   double expectancy = g_totalOutcomes > 0 ? g_totalNetR / g_totalOutcomes : 0.0;
   double dailyReturnPct = g_dailyStartEquity > 0.0
                           ? (g_researchEquity / g_dailyStartEquity - 1.0) * 100.0 : 0.0;
   double cumulativeReturnPct = InpResearchStartEquity > 0.0
                                ? (g_researchEquity / InpResearchStartEquity - 1.0) * 100.0 : 0.0;

   string panel = g_eaName;
   panel += "\nVersion: 0.50 | RESEARCH ONLY - ORDER CODE ABSENT";
   panel += "\nSymbol: " + _Symbol + " | TF: " + EnumToString(InpSignalTimeframe);
   panel += "\nNew York: " + TimeToString(nyNow, TIME_DATE|TIME_MINUTES) +
            " | Server UTC: " + StringFormat("%+d", g_serverUtcOffset);
   panel += "\nSession: " + SessionStateText(nyMinutes);
   panel += "\nOR high / low: " + orText;
   panel += "\nPremarket high / low: " + premarketText;
   panel += "\nSession VWAP: " + DoubleToString(g_sessionVwap, _Digits);
   panel += "\nSetup: " + LiquidityStateText() + " | Bars left: " +
            (string)g_liquidityBarsRemaining + " | Score: " +
            (string)g_displacementScore + " | Signals: " + (string)g_signalsToday;
   panel += "\nHyp entry / stop / target: " + levelText;
   panel += "\nOutcome: " + outcomeText;
   panel += "\nResults: " + (string)g_totalWins + "W / " + (string)g_totalLosses +
            "L | Net " + DoubleToString(g_totalNetR, 2) +
            "R | Avg " + DoubleToString(expectancy, 3) + "R";
   panel += "\nToday: " + (string)g_dailyOutcomes + " setups | " +
            DoubleToString(g_dailyNetR, 2) + "R | " +
            DoubleToString(dailyReturnPct, 3) + "%";
   panel += "\nResearch equity: " + DoubleToString(g_researchEquity, 2) +
            " | Return " + DoubleToString(cumulativeReturnPct, 2) +
            "% | Max DD " + DoubleToString(g_researchMaxDrawdownPct, 2) + "%";
   panel += "\nSpread: " + DoubleToString(spreadPrice, _Digits) + " (" +
            DoubleToString(spreadPoints, 1) + " MT5 points)";
   panel += "\nEquity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
            " | Leverage: 1:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE);
   panel += "\nVolume min / step: " +
            DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 4) + " / " +
            DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 4);
   panel += "\nTick size / value: " +
            DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), _Digits) + " / " +
            DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 4);
   panel += "\nPreview " + DoubleToString(InpPreviewRiskPct, 1) + "% risk, " +
            DoubleToString(InpPreviewStopDistance, 1) + " index-unit stop: " + previewText;
   panel += "\nInput trading switch: " +
            (InpEnableTrading ? "ON (still locked)" : "OFF");
   Comment(panel);
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ParseMinutes(InpOpeningRangeStart, g_orStartMinutes) ||
      !ParseMinutes(InpOpeningRangeEnd, g_orEndMinutes) ||
      !ParseMinutes(InpResearchWindowEnd, g_researchEndMinutes) ||
      !ParseMinutes(InpPremarketStart, g_premarketStartMinutes) ||
      !ParseMinutes(InpOutcomeSessionClose, g_outcomeCloseMinutes) ||
      g_premarketStartMinutes >= g_orStartMinutes ||
      g_orStartMinutes >= g_orEndMinutes ||
      g_orEndMinutes >= g_researchEndMinutes ||
      InpATRLength < 2 || InpDisplacementBars < 1 || InpPullbackWindowBars < 1 ||
      InpSweepBufferATR < 0.0 || InpDisplacementBodyATR <= 0.0 ||
      InpPullbackToleranceATR < 0.0 || InpInvalidationATR <= 0.0 ||
      InpRelativeVolumeLength < 2 || InpRelativeVolumeMin <= 0.0 ||
      InpMinimumConfirmScore < 0 ||
      InpMinimumConfirmScore > (InpUseVWAPScore ? 1 : 0) + (InpUseRelativeVolScore ? 1 : 0) ||
      (!InpUsePremarketLevels && !InpUseOpeningRange) || InpMaximumSignalsDay < 1 ||
      InpStopBufferATR < 0.0 || InpResearchTargetR <= 0.0 ||
      InpOutcomeMaxBars < 1 || InpSlippagePoints < 0.0 ||
      InpResearchRiskPct < 0.0 || InpResearchRiskPct > 100.0 ||
      InpResearchStartEquity <= 0.0 ||
      g_outcomeCloseMinutes <= g_researchEndMinutes)
   {
      Print(g_eaName, " initialization failed: invalid session times");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_serverUtcOffset = ResolveServerUtcOffset();
   ResetOutcomeStatistics();
   if(MQLInfoInteger(MQL_TESTER))
   {
      g_sessionDateKey = 0;
      ResetResearchState();
   }
   else
      RebuildLiquidityState();
   g_lastSignalBarOpen = iTime(_Symbol, InpSignalTimeframe, 0);
   EventSetTimer(1);

   PrintFormat("%s v0.50 initialized on %s. Trading locked. Server UTC offset=%+d",
               g_eaName, _Symbol, g_serverUtcOffset);
   RenderStatus();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   double expectancy = g_totalOutcomes > 0 ? g_totalNetR / g_totalOutcomes : 0.0;
   PrintFormat("%s v0.50 summary | outcomes=%d wins=%d losses=%d timed=%d net=%.3fR avg=%.3fR equity=%.2f maxDD=%.3f%%",
               g_eaName, g_totalOutcomes, g_totalWins, g_totalLosses,
               g_totalTimedExits, g_totalNetR, expectancy,
               g_researchEquity, g_researchMaxDrawdownPct);
   Comment("");
   DeleteOpeningRangeObjects();
}

double OnTester()
{
   FinalizeDailySummary(true);
   double expectancy = g_totalOutcomes > 0 ? g_totalNetR / g_totalOutcomes : 0.0;
   PrintFormat("%s v0.50 tester result | outcomes=%d wins=%d losses=%d timed=%d net=%.3fR avg=%.3fR equity=%.2f maxDD=%.3f%%",
               g_eaName, g_totalOutcomes, g_totalWins, g_totalLosses,
               g_totalTimedExits, g_totalNetR, expectancy,
               g_researchEquity, g_researchMaxDrawdownPct);
   return g_totalNetR;
}

void OnTick()
{
   datetime currentBarOpen = iTime(_Symbol, InpSignalTimeframe, 0);
   if(currentBarOpen > 0 && currentBarOpen != g_lastSignalBarOpen)
   {
      MqlRates closedBar[1];
      if(CopyRates(_Symbol, InpSignalTimeframe, 1, 1, closedBar) == 1)
      {
         ProcessOutcomeBar(closedBar[0], true);
         ProcessClosedBar(closedBar[0], true);
         ProcessLiquidityBar(closedBar[0], 1, true);
         WriteResearchRow(closedBar[0], g_squeeze);
      }
      g_lastSignalBarOpen = currentBarOpen;
   }

   RenderStatus();
}

void OnTimer()
{
   RenderStatus();
}
//+------------------------------------------------------------------+
