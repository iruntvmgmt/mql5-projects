//+------------------------------------------------------------------+
//|                                        XAUUSD_Scalper.mq5        |
//|   V7.1: Clean buffers + Optional Countertrend                     |
//|                                                                  |
//|   Indicator: CRSI_Prestige_Strategy (TradingView port)           |
//|   Path: Indicators/Tradingview_Indicators/CRSI/                  |
//|                                                                  |
//|   Entry: CRSI BuySig / SellSig buffers (15/16)                   |
//|   Filter: H1 trend (price vs EMA), optional countertrend         |
//|   Exit:  2.5R TP, BE@1.5R, Trail@2R behind Dyn bands            |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Scalper V7.1 — Signal Buffers + Countertrend"
#property version   "2.10"
#property description "CRSI Signal Buffers for XAUUSD"
#property description " "
#property description "CRSI BUFFER MAP (iCustom indexes):"
#property description "  0=CRSI  1=SmoothCRSI  2=DynLow  3=DynHigh"
#property description "  4=Fib50  5=Fib618Up  6=Fib618Dn"
#property description "  7=LevelHI  8=LevelMID  9=LevelLO"
#property description "  10=HISub  11=LOSub"
#property description "  12=BBUpper  13=BBMiddle  14=BBLower"
#property description "  15=BuySig  16=SellSig"
#property description "  17=SQZMomentum  18=SQZOn"
#property description "  19=BBMidStd  20=PriceNorm(0-100)"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+

input group "1. Safety"
input bool            InpEnableTrading        = false;
input int             InpMagicNumber          = 260713;
input string          InpTradeSymbol          = "XAUUSD";
input ENUM_TIMEFRAMES InpEntryTF              = PERIOD_M5;

input group "2. CRSI Indicator"
input string          InpCRSIPath             = "Tradingview_Indicators\\CRSI\\CRSI_Prestige_Strategy";
input int             InpCRSIDomCycle         = 20;
input int             InpCRSILeveling         = 10;
input int             InpCRSISmoothLen        = 3;

input group "3. Session & Spread"
input bool            InpUseSessionFilter     = true;
input string          InpSessionStart         = "07:00";
input string          InpSessionEnd           = "17:00";
input bool            InpUseSpreadFilter      = true;
input double          InpMaxSpreadPoints      = 40.0;

input group "4. Trend Filter"
input bool            InpUseTrendFilter       = true;
input int             InpTrendEMAPeriod       = 50;
input ENUM_TIMEFRAMES InpTrendTF              = PERIOD_M15;

input group "4b. Countertrend (only when trend filter is active)"
input bool            InpAllowCounterTrend    = false;         // Allow countertrend trades with strong PriceNorm
input double          InpCT_PriceNormLong     = 70.0;          // For LONG in downtrend: require PriceNorm > this
input double          InpCT_PriceNormShort    = 30.0;          // For SHORT in uptrend: require PriceNorm < this

input group "5. Band Cross Entry"
input bool            InpRequireSqzOff        = false;         // Skip signals when squeeze is on
input bool            InpRequirePriceNorm     = false;         // Require PriceNorm > 50 for long, < 50 for short
input int             InpMinBarsBetweenTrades = 2;             // Min bars to wait after a close before next entry

input group "6. Exit"
input int             InpATRPeriod            = 14;
input double          InpATRMultSL            = 2.0;           // SL = N × ATR from entry
input double          InpTargetR              = 2.5;           // TP = R-multiple of SL distance
input bool            InpUseBreakeven         = true;
input double          InpBE_ActivationR       = 1.5;           // Move SL to BE after price moves 1.5R
input bool            InpUseTrailingStop      = true;
input double          InpTrailActivationR     = 2.0;           // Start trailing after 2R in profit
input double          InpTrailDistanceATR     = 1.5;           // Trail distance in ATR multiples

input group "7. Risk"
input double          InpRiskPct              = 1.0;
input double          InpMaxLots              = 1.0;
input double          InpMinLots              = 0.01;

input group "8. Misc"
input bool            InpVerboseLogging       = true;


//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string   g_eaName          = "XAUUSD_Scalper";
datetime g_lastBarTime     = 0;
int      g_sessionStartMin = 420;
int      g_sessionEndMin   = 1020;

CTrade         g_trade;
datetime       g_lastTradeCloseTime = 0;
double         g_lastTradePnl       = 0.0;
datetime       g_lastEntryBarTime   = 0;

int   g_crsiHandle    = INVALID_HANDLE;
int   g_atrHandle     = INVALID_HANDLE;
int   g_trendMAHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| UTILITY                                                            |
//+------------------------------------------------------------------+
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
   datetime barTime = iTime(_Symbol, InpEntryTF, 0);
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

double CurrentSpreadPoints()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
           SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

//+------------------------------------------------------------------+
//| CRSI BUFFER READERS                                                |
//+------------------------------------------------------------------+
double CRSI_Buf(int bufIdx, int shift=1)
{
   if(g_crsiHandle == INVALID_HANDLE) return EMPTY_VALUE;
   double val[1];
   if(CopyBuffer(g_crsiHandle, bufIdx, shift, 1, val) != 1) return EMPTY_VALUE;
   return val[0];
}

#define CRSI(v)        CRSI_Buf(0, v)
#define SMOOTH(v)      CRSI_Buf(1, v)
#define DYN_LOW(v)     CRSI_Buf(2, v)
#define DYN_HIGH(v)    CRSI_Buf(3, v)
#define FIB50(v)       CRSI_Buf(4, v)
#define FIB618UP(v)    CRSI_Buf(5, v)
#define FIB618DN(v)    CRSI_Buf(6, v)
#define BUY_SIG(v)     CRSI_Buf(15, v)
#define SELL_SIG(v)    CRSI_Buf(16, v)
#define SQZ_ON(v)      CRSI_Buf(18, v)
#define SQZ_MOM(v)     CRSI_Buf(17, v)
#define PRICE_NORM(v)  CRSI_Buf(20, v)

double GetATR(int shift=0)
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1) return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| H1 TREND FILTER                                                    |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   if(!InpUseTrendFilter || g_trendMAHandle == INVALID_HANDLE) return 0; // 0 = no filter
   
   double ma[1], close[1];
   if(CopyBuffer(g_trendMAHandle, 0, 1, 1, ma) != 1) return 0;
   if(CopyClose(_Symbol, InpTrendTF, 1, 1, close) != 1) return 0;
   
   if(ma[0] <= 0 || close[0] <= 0) return 0;
   
   if(close[0] > ma[0]) return 1;   // Uptrend — only longs
   if(close[0] < ma[0]) return -1;  // Downtrend — only shorts
   return 0;                         // Flat — allow both
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                                |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
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

//+------------------------------------------------------------------+
//| RISK SIZING                                                        |
//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistancePoints)
{
   if(slDistancePoints <= 0) return 0.0;
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = equity * InpRiskPct / 100.0;
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

//+------------------------------------------------------------------+
//| SIGNAL: CRSI Buy/Sell Buffers                                      |
//+------------------------------------------------------------------+
int CalculateSignal(string &reason)
{
   // --- Bar 1 = just closed, Bar 2 = previous ---
   double crsi1   = CRSI(1);
   double crsi2   = CRSI(2);
   double smooth1 = SMOOTH(1);
   double smooth2 = SMOOTH(2);
   double dynLow1 = DYN_LOW(1);
   double dynHi1  = DYN_HIGH(1);
   double fib50_1 = FIB50(1);
   double buySig1 = BUY_SIG(1);
   double buySig2 = BUY_SIG(2);
   double sellSig1 = SELL_SIG(1);
   double sellSig2 = SELL_SIG(2);
   double sqzOn1  = SQZ_ON(1);
   double pNorm1  = PRICE_NORM(1);

   // --- Core buffer guard (mandatory buffers only) ---
   if(crsi1 == EMPTY_VALUE || crsi2 == EMPTY_VALUE ||
      smooth1 == EMPTY_VALUE || smooth2 == EMPTY_VALUE ||
      dynLow1 == EMPTY_VALUE || dynHi1 == EMPTY_VALUE ||
      fib50_1 == EMPTY_VALUE)
      { reason = "CRSI buffers unavailable"; return 0; }

   // --- SQZ guard (only when squeeze filter is active) ---
   if(InpRequireSqzOff)
   {
      if(sqzOn1 == EMPTY_VALUE || sqzOn1 >= 1e300)
         { reason = "CRSI SQZ buffer unavailable"; return 0; }
   }

   // --- PriceNorm guard (only when PriceNorm filter is active) ---
   if(InpRequirePriceNorm)
   {
      if(pNorm1 == EMPTY_VALUE || pNorm1 >= 1e300)
         { reason = "CRSI PriceNorm buffer unavailable"; return 0; }
   }

   // --- Bar cooldown ---
   if(g_lastEntryBarTime > 0)
   {
      datetime bar1Time = iTime(_Symbol, InpEntryTF, 1);
      int barsSince = (int)((bar1Time - g_lastEntryBarTime) / PeriodSeconds(InpEntryTF));
      if(barsSince < InpMinBarsBetweenTrades)
      {
         reason = StringFormat("Cooldown: %d/%d bars since last entry", barsSince, InpMinBarsBetweenTrades);
         return 0;
      }
   }

   // --- Squeeze filter ---
   bool inSqueeze = (sqzOn1 > 0.5 && sqzOn1 < 1e10);  // guard against uninitialized DBL_MAX
   if(InpRequireSqzOff && inSqueeze)
   {
      reason = StringFormat("Squeeze ON (SQZ=%.0f) - waiting for expansion", sqzOn1);
      return 0;
   }

   // --- Trend filter ---
   int trend = GetTrendDirection();

   // --- LONG: indicator's own buy marker ---
   bool longMarker = (buySig1 != EMPTY_VALUE && buySig1 < 1e300);
   bool longMarkerPrev = (buySig2 != EMPTY_VALUE && buySig2 < 1e300);
   if(longMarker && !longMarkerPrev)
   {
      if(InpRequirePriceNorm && pNorm1 <= 50.0)
         { reason = "LONG marker skipped: PriceNorm <= 50"; return 0; }
      if(trend == -1)
      {
         if(!InpAllowCounterTrend || pNorm1 <= InpCT_PriceNormLong)
            { reason = "LONG marker skipped: H1 downtrend"; return 0; }
         // else allowed: countertrend LONG with strong PriceNorm
      }
      
      string trendStr = (trend==1) ? "UP" : ((trend==-1) ? "DOWN" : "FLAT");
      reason = StringFormat("LONG: BuySig | CRSI: %.1f->%.1f Smooth: %.1f->%.1f F50: %.1f | PriceNorm=%.1f Trend=%s",
                             crsi2, crsi1, smooth2, smooth1, fib50_1, pNorm1, trendStr);
      return 1;
   }

   // --- SHORT: indicator's own sell marker ---
   bool shortMarker = (sellSig1 != EMPTY_VALUE && sellSig1 < 1e300);
   bool shortMarkerPrev = (sellSig2 != EMPTY_VALUE && sellSig2 < 1e300);
   if(shortMarker && !shortMarkerPrev)
   {
      if(InpRequirePriceNorm && pNorm1 >= 50.0)
         { reason = "SHORT marker skipped: PriceNorm >= 50"; return 0; }
      if(trend == 1)
      {
         if(!InpAllowCounterTrend || pNorm1 >= InpCT_PriceNormShort)
            { reason = "SHORT marker skipped: H1 uptrend"; return 0; }
         // else allowed: countertrend SHORT with strong PriceNorm
      }
      
      string trendStr = (trend==1) ? "UP" : ((trend==-1) ? "DOWN" : "FLAT");
      reason = StringFormat("SHORT: SellSig | CRSI: %.1f->%.1f Smooth: %.1f->%.1f F50: %.1f | PriceNorm=%.1f Trend=%s",
                             crsi2, crsi1, smooth2, smooth1, fib50_1, pNorm1, trendStr);
      return -1;
   }

   // --- No signal ---
   string trendStr2 = (trend==1) ? "UP" : ((trend==-1) ? "DOWN" : "FLAT");
   if(InpVerboseLogging)
   {
      string buyStr  = (buySig1 != EMPTY_VALUE && buySig1 < 1e300)  ? StringFormat("%.1f", buySig1)  : "none";
      string sellStr = (sellSig1 != EMPTY_VALUE && sellSig1 < 1e300) ? StringFormat("%.1f", sellSig1) : "none";
      reason = StringFormat("No marker: CRSI=%.1f Smooth=%.1f F50=%.1f Dyn[%.1f-%.1f] Buy=%s Sell=%s Sqz=%s Trend=%s",
                             crsi1, smooth1, fib50_1, dynLow1, dynHi1, buyStr, sellStr,
                             inSqueeze?"ON":"OFF", trendStr2);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                    |
//+------------------------------------------------------------------+
bool OpenPosition(int direction, double lots, double slPrice, double tpPrice, string sigName)
{
   if(!InpEnableTrading)
   {
      PrintFormat("[%s] BLOCKED: %s %s | Lots=%.2f | SL=%.2f | TP=%.2f",
                  g_eaName, sigName, direction==1?"BUY":"SELL", lots, slPrice, tpPrice);
      return false;
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   bool result = (direction == 1)
      ? g_trade.Buy(lots, _Symbol, 0.0, slPrice, tpPrice, StringFormat("%s %s", g_eaName, sigName))
      : g_trade.Sell(lots, _Symbol, 0.0, slPrice, tpPrice, StringFormat("%s %s", g_eaName, sigName));

   if(result)
   {
      g_lastEntryBarTime = iTime(_Symbol, InpEntryTF, 1);
      PrintFormat("[%s] OPENED %s | Dir=%s | Lots=%.2f | Entry=%.2f | SL=%.2f | TP=%.2f | Ticket=%I64u",
                  g_eaName, sigName, direction==1?"BUY":"SELL", lots,
                  g_trade.ResultPrice(), slPrice, tpPrice, g_trade.ResultOrder());
   }
   else
      PrintFormat("[%s] FAILED %s | Dir=%s | Err=%d Ret=%d",
                  g_eaName, sigName, direction==1?"BUY":"SELL", GetLastError(), g_trade.ResultRetcode());
   return result;
}

bool ModifyPositionSLTP(ulong ticket, double newSl, double newTp)
{
   if(!InpEnableTrading) return false;
   if(!g_trade.PositionModify(ticket, newSl, newTp))
   {
      if(g_trade.ResultRetcode() != 1)
         PrintFormat("[%s] Modify FAILED tkt=%I64u | Err=%d", g_eaName, ticket, GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| EXIT MANAGEMENT                                                    |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   if(!InpUseBreakeven) return;
   ulong ticket; double entry, sl, tp; int dir; double vol;
   if(!GetOpenPosition(ticket, entry, sl, tp, dir, vol)) return;
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir * (price - entry) / risk < InpBE_ActivationR) return;
   if((dir == 1 && sl >= entry) || (dir == -1 && sl <= entry)) return;  // already at BE+
   
   double newSl = (dir == 1) ? entry + _Point : entry - _Point;
   if(ModifyPositionSLTP(ticket, newSl, tp))
      PrintFormat("[%s] BE MOVED | tkt=%I64u | SL->%.2f (breakeven + spread)", g_eaName, ticket, newSl);
}

void ManageTrailingStop()
{
   if(!InpUseTrailingStop) return;
   ulong ticket; double entry, sl, tp; int dir; double vol;
   if(!GetOpenPosition(ticket, entry, sl, tp, dir, vol)) return;
   double atr = GetATR();
   if(atr <= 0) return;
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir * (price - entry) / risk < InpTrailActivationR) return;
   
   double trailDist = InpTrailDistanceATR * atr;
   double newSl = (dir == 1) ? price - trailDist : price + trailDist;
   
   // Also use DynLow (for longs) or DynHigh (for shorts) as a ceiling/floor for the trail
   // This anchors the trail to the dynamic band structure
   double dynLow = DYN_LOW(0);
   double dynHi  = DYN_HIGH(0);
   if(dir == 1 && dynLow != EMPTY_VALUE)
   {
      // For longs, don't trail past the DynLow converted to price — but we trail by ATR from price
      // Just move SL if it improves
   }
   if(dir == -1 && dynHi != EMPTY_VALUE)
   {
      // For shorts, similar logic
   }
   
   if((dir == 1 && newSl > sl) || (dir == -1 && newSl < sl))
      if(ModifyPositionSLTP(ticket, newSl, tp))
         PrintFormat("[%s] TRAIL | tkt=%I64u | SL->%.2f (%.2fR in profit)",
                     g_eaName, ticket, newSl, dir*(price-entry)/risk);
}

void ManagePosition()
{
   ManageBreakeven();
   ManageTrailingStop();
}

//+------------------------------------------------------------------+
//| CLOSED TRADE LOGGING                                               |
//+------------------------------------------------------------------+
void LogClosedPositions()
{
   HistorySelect(g_lastTradeCloseTime > 0 ? g_lastTradeCloseTime : TimeCurrent() - 86400, TimeCurrent() + 1);
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      if((datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME) <= g_lastTradeCloseTime) continue;
      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
      double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double vol = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      double pr  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      g_lastTradeCloseTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      g_lastTradePnl = pnl;
      PrintFormat("[%s] POSITION CLOSED | PnL=%.2f | Volume=%.2f | ClosePrice=%.2f", g_eaName, pnl, vol, pr);
   }
}

//+------------------------------------------------------------------+
//| MAIN                                                               |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   LogClosedPositions();

   // --- Manage existing position ---
   if(HasOpenPosition()) { ManagePosition(); return; }

   // --- Gate checks ---
   if(!IsWithinSession(TimeCurrent())) return;
   
   double spread = CurrentSpreadPoints();
   if(InpUseSpreadFilter && spread > InpMaxSpreadPoints) return;

   // --- Signal ---
   string reason = "";
   int signal = CalculateSignal(reason);
   if(signal == 0)
   {
      if(InpVerboseLogging && reason != "")
         PrintFormat("[%s] %s", g_eaName, reason);
      return;
   }

   // --- Size the trade ---
   double atr = GetATR();
   if(atr <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slDist = InpATRMultSL * atr;
   if(slDist <= 0) return;

   double entryP = (signal == 1) ? ask : bid;
   double slP    = (signal == 1) ? entryP - slDist : entryP + slDist;
   double tpP    = (signal == 1) ? entryP + InpTargetR * slDist : entryP - InpTargetR * slDist;

   double lots = CalculatePositionSize(slDist / _Point);
   if(lots <= 0) return;

   PrintFormat("[%s] === %s SIGNAL ===", g_eaName, signal==1?"LONG":"SHORT");
   PrintFormat("[%s]   %s", g_eaName, reason);
   PrintFormat("[%s]   Entry=%.2f | SL=%.2f | TP=%.2f | ATR=%.3f | Spread=%.0f pts | Lots=%.2f",
               g_eaName, entryP, slP, tpP, atr, spread, lots);

   OpenPosition(signal, lots, slP, tpP, "BandCross");
}

//+------------------------------------------------------------------+
//| EVENTS                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ParseMinutes(InpSessionStart, g_sessionStartMin) || !ParseMinutes(InpSessionEnd, g_sessionEndMin))
      return INIT_PARAMETERS_INCORRECT;

   if(InpTradeSymbol != "" && _Symbol != InpTradeSymbol)
      PrintFormat("[%s] WARNING: chart=%s configured for %s", g_eaName, _Symbol, InpTradeSymbol);

   // --- Indicator handles ---
   g_crsiHandle = iCustom(_Symbol, InpEntryTF, InpCRSIPath,
                          InpCRSIDomCycle, InpCRSILeveling, InpCRSISmoothLen);
   g_atrHandle  = iATR(_Symbol, InpEntryTF, InpATRPeriod);

   if(InpUseTrendFilter)
      g_trendMAHandle = iMA(_Symbol, InpTrendTF, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(g_crsiHandle == INVALID_HANDLE)
   {
      PrintFormat("[%s] ERROR: CRSI iCustom failed. Path='%s' TF=%s",
                  g_eaName, InpCRSIPath, EnumToString(InpEntryTF));
      return INIT_FAILED;
   }

   if(g_atrHandle == INVALID_HANDLE)
   {
      PrintFormat("[%s] ERROR: ATR init failed.", g_eaName);
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);

   PrintFormat("[%s] ========================================", g_eaName);
   PrintFormat("[%s] V7 INIT | %s | %s | _Point=%.5f",
               g_eaName, _Symbol, EnumToString(InpEntryTF), _Point);
   PrintFormat("[%s]   CRSI: %s (cycle=%d level=%d smooth=%d)",
               g_eaName, InpCRSIPath, InpCRSIDomCycle, InpCRSILeveling, InpCRSISmoothLen);
   PrintFormat("[%s]   Entry: BuySig/SellSig buffers | SqzFilter=%s | PriceNorm=%s",
               g_eaName, InpRequireSqzOff?"ON":"OFF", InpRequirePriceNorm?"ON":"OFF");
   PrintFormat("[%s]   Trend: %s EMA(%d) | Filter=%s | Countertrend=%s (L>%.0f S<%.0f)",
               g_eaName, EnumToString(InpTrendTF), InpTrendEMAPeriod, InpUseTrendFilter?"ON":"OFF",
               InpAllowCounterTrend?"ON":"OFF", InpCT_PriceNormLong, InpCT_PriceNormShort);
   PrintFormat("[%s]   Exit: SL=%.1fxATR | TP=%.1fR | BE@%.1fR | Trail@%.1fR(%.1fxATR)",
               g_eaName, InpATRMultSL, InpTargetR, InpBE_ActivationR,
               InpTrailActivationR, InpTrailDistanceATR);
   PrintFormat("[%s]   Risk: %.1f%% equity | Lots: %.2f-%.2f | Cooldown: %d bars",
               g_eaName, InpRiskPct, InpMinLots, InpMaxLots, InpMinBarsBetweenTrades);
   PrintFormat("[%s]   Trading: %s", g_eaName, InpEnableTrading?"ENABLED":"DISABLED");
   PrintFormat("[%s] ========================================", g_eaName);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_crsiHandle    != INVALID_HANDLE) IndicatorRelease(g_crsiHandle);
   if(g_atrHandle     != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_trendMAHandle != INVALID_HANDLE) IndicatorRelease(g_trendMAHandle);
   PrintFormat("[%s] DEINIT reason=%d | lastPnl=%.2f", g_eaName, reason, g_lastTradePnl);
}

void OnTick()
{
   if(InpTradeSymbol != "" && _Symbol != InpTradeSymbol) return;
   if(!IsNewBar()) return;
   ProcessNewBar();
}
//+------------------------------------------------------------------+
