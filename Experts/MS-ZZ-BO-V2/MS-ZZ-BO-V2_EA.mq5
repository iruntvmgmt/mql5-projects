//+------------------------------------------------------------------+
//|                         MS-ZZ-BO-V2_EA.mq5                       |
//|   v1.000 — Production: bar-index signal tracking                 |
//|                                                                  |
//|   Signal source: MS-ZZ-BO-V2 indicator (buffers 6/7/8)          |
//|   - Fast Break Buy (6) / Fast Break Sell (7) / Med Break Buy (8)|
//|   - Tracks bar index of last signal to detect new ones           |
//+------------------------------------------------------------------+
#property copyright   "MS-ZZ-BO-V2 EA"
#property version     "1.000"
#property description  "MS-ZZ-BO-V2 EA — Multi-Speed ZigZag Breakout trading"

#include <Trade\Trade.mqh>

enum ENUM_SIGNAL_MODE
{
   SIGNAL_MED_ONLY  = 0,  // Only medium breakouts (long only)
   SIGNAL_FAST_ONLY = 1,  // Only fast breakouts (long+short)
   SIGNAL_ANY       = 2   // Any breakout, med preferred
};

input group "1. Safety"
input bool            InpEnableTrading        = false;
input int             InpMagicNumber          = 260715;
input string          InpTradeSymbol          = "XAUUSD";
input ENUM_TIMEFRAMES InpSignalTF             = PERIOD_CURRENT;

input group "2. Indicator"
input string          InpIndicatorPath        = "Tradingview_Indicators\\MULTI_SPEED_ZIGZAG\\MS-ZZ-BO-V2";
input ENUM_SIGNAL_MODE InpSignalMode          = SIGNAL_MED_ONLY;
input int             InpMinBarsBetweenTrades = 3;

input group "3. Session & Spread"
input bool            InpUseSessionFilter     = true;
input string          InpSessionStart         = "07:00";
input string          InpSessionEnd           = "17:00";
input bool            InpUseSpreadFilter      = true;
input double          InpMaxSpreadPoints      = 80.0;

input group "4. Risk"
input int             InpATRPeriod            = 14;
input double          InpATRMultSL            = 2.0;
input double          InpTargetR              = 2.0;
input bool            InpUseBreakeven         = true;
input double          InpBEActivationR        = 1.0;
input bool            InpUseTrailingStop      = true;
input double          InpTrailActivationR     = 1.25;
input double          InpTrailDistanceATR     = 1.0;
input double          InpRiskPct              = 1.0;
input double          InpMaxLots              = 1.0;
input double          InpMinLots              = 0.01;

input group "5. Misc"
input bool            InpVerboseLogging       = true;

string   g_eaName = "MS_ZZ_BO_V2_EA";
datetime g_lastBarTime = 0;
datetime g_lastEntryBarTime = 0;
int      g_sessionStartMin = 420;
int      g_sessionEndMin = 1020;

// Bar-index tracking for NEW signal detection
int g_lastFBidx = -1;  // last bar index where FastBuy was seen
int g_lastFSidx = -1;  // last bar index where FastSell was seen
int g_lastMBidx = -1;  // last bar index where MedBuy was seen

CTrade   g_trade;
int      g_indicatorHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;

// ── Helpers ────────────────────────────────────────────────────────
bool ParseMinutes(const string value, int &minutes)
{
   string parts[];
   if(StringSplit(value, ':', parts) != 2) return false;
   int hour = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59) return false;
   minutes = hour * 60 + minute;
   return true;
}

bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   if(barTime <= 0) return false;
   if(barTime == g_lastBarTime) return false;
   g_lastBarTime = barTime;
   return true;
}

bool IsWithinSession(const datetime t)
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt = {};
   TimeToStruct(t, dt);
   int minutes = dt.hour * 60 + dt.min;
   if(g_sessionStartMin == g_sessionEndMin) return true;
   if(g_sessionStartMin < g_sessionEndMin)
      return minutes >= g_sessionStartMin && minutes <= g_sessionEndMin;
   return minutes >= g_sessionStartMin || minutes <= g_sessionEndMin;
}

double SpreadPts()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

double GetATR(int shift = 0)
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1) return 0.0;
   return buf[0];
}

// Scan backward from shift=1 to find the most recent signal bar index
int FindSignalBar(const int bufIdx)
{
   for(int shift = 1; shift <= 300; shift++)
   {
      double buf[1];
      if(CopyBuffer(g_indicatorHandle, bufIdx, shift, 1, buf) != 1)
         return -1;
      if(buf[0] != EMPTY_VALUE && buf[0] < 1e300 && MathAbs(buf[0]) > 0.001)
      {
         // Found a signal — return its absolute bar index
         datetime t = iTime(_Symbol, InpSignalTF, shift);
         if(t <= 0) return -1;
         // Use Bars() and shift to compute absolute index
         return Bars(_Symbol, InpSignalTF) - 1 - shift;
      }
   }
   return -1;
}

int CalculateSignal(string &reason)
{
   // Find current signal bar indices for each buffer
   int fbIdx = FindSignalBar(6);
   int fsIdx = FindSignalBar(7);
   int mbIdx = FindSignalBar(8);

   // Update tracking and detect NEW signals
   bool newFB = (fbIdx >= 0 && fbIdx != g_lastFBidx);
   bool newFS = (fsIdx >= 0 && fsIdx != g_lastFSidx);
   bool newMB = (mbIdx >= 0 && mbIdx != g_lastMBidx);

   if(fbIdx >= 0) g_lastFBidx = fbIdx;
   if(fsIdx >= 0) g_lastFSidx = fsIdx;
   if(mbIdx >= 0) g_lastMBidx = mbIdx;

   if(fbIdx < 0 && fsIdx < 0 && mbIdx < 0)
   {
      reason = "no buffers";
      return 0;
   }

   bool buy = false, sell = false;
   string src = "";

   switch(InpSignalMode)
   {
      case SIGNAL_FAST_ONLY:
         if(newFB)       { buy = true;  src = "Fast"; }
         else if(newFS)  { sell = true; src = "Fast"; }
         break;

      case SIGNAL_ANY:
         if(newMB)       { buy = true;  src = "Med";  }
         else if(newFB)  { buy = true;  src = "Fast"; }
         else if(newFS)  { sell = true; src = "Fast"; }
         break;

      case SIGNAL_MED_ONLY:
      default:
         if(newMB)       { buy = true;  src = "Med";  }
         break;
   }

   if(buy)
   {
      reason = StringFormat("%s BUY idx=%d", src, buy ? mbIdx : fbIdx);
      return 1;
   }
   if(sell)
   {
      reason = StringFormat("%s SELL idx=%d", src, fsIdx);
      return -1;
   }

   if(InpVerboseLogging)
   {
      reason = StringFormat("no new sig | fb=%d(%s) fs=%d(%s) mb=%d(%s)",
                            fbIdx, newFB?"NEW":"old",
                            fsIdx, newFS?"NEW":"old",
                            mbIdx, newMB?"NEW":"old");
   }
   return 0;
}

// ── Position Management ───────────────────────────────────────────
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

bool GetOpenPosition(ulong &ticket, double &entryPrice, double &currentSl,
                     double &currentTp, int &direction, double &volume)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ticket     = PositionGetInteger(POSITION_TICKET);
            entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            currentSl  = PositionGetDouble(POSITION_SL);
            currentTp  = PositionGetDouble(POSITION_TP);
            direction  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
            volume     = PositionGetDouble(POSITION_VOLUME);
            return true;
         }
      }
   }
   return false;
}

double CalculatePositionSize(double slDistancePoints)
{
   if(slDistancePoints <= 0) return 0.0;
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * InpRiskPct / 100.0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointVal = (tickSize > 0) ? tickVal / tickSize : 0.0;
   if(pointVal <= 0) return 0.0;
   double lots = riskAmt / (slDistancePoints * pointVal);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   double maxLots = MathMin(InpMaxLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   double minLots = MathMax(InpMinLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   if(lots < minLots) lots = minLots;
   if(lots > maxLots) lots = maxLots;
   return lots;
}

bool OpenPosition(const int direction, const double lots, const double slPrice,
                  const double tpPrice, const string sigName)
{
   if(!InpEnableTrading)
   {
      PrintFormat("[%s] BLOCKED %s | %s | lots=%.2f SL=%.2f TP=%.2f",
                  g_eaName, sigName, direction == 1 ? "BUY" : "SELL", lots, slPrice, tpPrice);
      return false;
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);
   bool ok = false;
   if(direction == 1)
      ok = g_trade.Buy(lots, _Symbol, 0.0, slPrice, tpPrice, StringFormat("%s %s", g_eaName, sigName));
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, slPrice, tpPrice, StringFormat("%s %s", g_eaName, sigName));
   if(ok)
   {
      g_lastEntryBarTime = iTime(_Symbol, InpSignalTF, 1);
      PrintFormat("[%s] OPENED %s | %s | lots=%.2f entry=%.2f SL=%.2f TP=%.2f order=%I64u",
                  g_eaName, sigName, direction == 1 ? "BUY" : "SELL",
                  lots, g_trade.ResultPrice(), slPrice, tpPrice, g_trade.ResultOrder());
   }
   else
   {
      PrintFormat("[%s] FAILED %s | %s | err=%d ret=%d",
                  g_eaName, sigName, direction == 1 ? "BUY" : "SELL",
                  GetLastError(), g_trade.ResultRetcode());
   }
   return ok;
}

void ManageBreakeven()
{
   if(!InpUseBreakeven) return;
   ulong ticket; double entryPrice, currentSl, currentTp, volume; int direction;
   if(!GetOpenPosition(ticket, entryPrice, currentSl, currentTp, direction, volume)) return;
   double risk = MathAbs(entryPrice - currentSl);
   if(risk <= 0) return;
   double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitR = direction * (currentPrice - entryPrice) / risk;
   if(profitR < InpBEActivationR) return;
   bool atBE = (direction == 1 && currentSl >= entryPrice) || (direction == -1 && currentSl <= entryPrice);
   if(atBE) return;
   double beSl = (direction == 1) ? entryPrice + _Point : entryPrice - _Point;
   if(!g_trade.PositionModify(_Symbol, beSl, currentTp))
      PrintFormat("[%s] BE FAILED ticket=%I64u", g_eaName, ticket);
   else
      PrintFormat("[%s] BE->%.2f ticket=%I64u", g_eaName, beSl, ticket);
}

void ManageTrailingStop()
{
   if(!InpUseTrailingStop) return;
   ulong ticket; double entryPrice, currentSl, currentTp, volume; int direction;
   if(!GetOpenPosition(ticket, entryPrice, currentSl, currentTp, direction, volume)) return;
   double atr = GetATR(1);
   if(atr <= 0) return;
   double risk = MathAbs(entryPrice - currentSl);
   if(risk <= 0) return;
   double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitR = direction * (currentPrice - entryPrice) / risk;
   if(profitR < InpTrailActivationR) return;
   double trailDist = InpTrailDistanceATR * atr;
   double newSl = (direction == 1) ? currentPrice - trailDist : currentPrice + trailDist;
   if((direction == 1 && newSl > currentSl) || (direction == -1 && newSl < currentSl))
   {
      if(!g_trade.PositionModify(_Symbol, newSl, currentTp))
         PrintFormat("[%s] TRAIL FAILED ticket=%I64u", g_eaName, ticket);
   }
}

// ── Main ───────────────────────────────────────────────────────────
void ProcessNewBar()
{
   if(HasOpenPosition()) { ManageBreakeven(); ManageTrailingStop(); }

   if(!IsWithinSession(TimeCurrent()))
   {
      if(InpVerboseLogging) PrintFormat("[%s] skip: session", g_eaName);
      return;
   }

   double spread = SpreadPts();
   if(InpUseSpreadFilter && spread > InpMaxSpreadPoints)
   {
      if(InpVerboseLogging) PrintFormat("[%s] skip: spread %.0f > %.0f", g_eaName, spread, InpMaxSpreadPoints);
      return;
   }

   if(HasOpenPosition())
   {
      if(InpVerboseLogging) PrintFormat("[%s] skip: pos open", g_eaName);
      return;
   }

   if(g_lastEntryBarTime > 0)
   {
      datetime bar1Time = iTime(_Symbol, InpSignalTF, 1);
      int barsSince = (int)((bar1Time - g_lastEntryBarTime) / PeriodSeconds(InpSignalTF));
      if(barsSince < InpMinBarsBetweenTrades)
      {
         if(InpVerboseLogging) PrintFormat("[%s] skip: cooldown %d/%d", g_eaName, barsSince, InpMinBarsBetweenTrades);
         return;
      }
   }

   string reason = "";
   int signal = CalculateSignal(reason);
   if(signal == 0)
   {
      if(InpVerboseLogging) PrintFormat("[%s] no trade: %s", g_eaName, reason);
      return;
   }

   double atr = GetATR(1);
   if(atr <= 0) { PrintFormat("[%s] skip: ATR", g_eaName); return; }

   double slDist = InpATRMultSL * atr;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (signal == 1) ? ask : bid;
   double sl = (signal == 1) ? entry - slDist : entry + slDist;
   double tp = (signal == 1) ? entry + InpTargetR * slDist : entry - InpTargetR * slDist;
   double lots = CalculatePositionSize(slDist / _Point);
   if(lots <= 0) { PrintFormat("[%s] skip: lots", g_eaName); return; }

   PrintFormat("[%s] SIGNAL %s | %s | spread=%.0f ATR=%.2f lots=%.2f",
               g_eaName, signal == 1 ? "BUY" : "SELL", reason, spread, atr, lots);
   OpenPosition(signal, lots, sl, tp, "ZZBreak");
}

int OnInit()
{
   if(!ParseMinutes(InpSessionStart, g_sessionStartMin) ||
      !ParseMinutes(InpSessionEnd, g_sessionEndMin))
      return INIT_PARAMETERS_INCORRECT;

   if(InpTradeSymbol != "" && _Symbol != InpTradeSymbol)
      PrintFormat("[%s] WARNING: chart=%s configured=%s", g_eaName, _Symbol, InpTradeSymbol);

   g_indicatorHandle = iCustom(_Symbol, InpSignalTF, InpIndicatorPath);
   g_atrHandle = iATR(_Symbol, InpSignalTF, InpATRPeriod);

   if(g_indicatorHandle == INVALID_HANDLE)
   {
      PrintFormat("[%s] ERROR: iCustom failed", g_eaName);
      return INIT_FAILED;
   }
   if(g_atrHandle == INVALID_HANDLE)
   {
      PrintFormat("[%s] ERROR: ATR failed", g_eaName);
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);

   // Seed tracking with current bar indices so first run doesn't trigger on old data
   g_lastFBidx = FindSignalBar(6);
   g_lastFSidx = FindSignalBar(7);
   g_lastMBidx = FindSignalBar(8);

   PrintFormat("[%s] INIT v1.000 | TF=%s | Mode=%d | Trading=%s | fb=%d fs=%d mb=%d",
               g_eaName, EnumToString(InpSignalTF), InpSignalMode,
               InpEnableTrading ? "ENABLED" : "DISABLED",
               g_lastFBidx, g_lastFSidx, g_lastMBidx);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_indicatorHandle != INVALID_HANDLE) IndicatorRelease(g_indicatorHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   g_indicatorHandle = INVALID_HANDLE;
   g_atrHandle = INVALID_HANDLE;
   PrintFormat("[%s] DEINIT reason=%d", g_eaName, reason);
}

void OnTick()
{
   if(InpTradeSymbol != "" && _Symbol != InpTradeSymbol) return;
   if(!IsNewBar()) return;
   ProcessNewBar();
}
//+------------------------------------------------------------------+
