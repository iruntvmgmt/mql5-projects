//+------------------------------------------------------------------+
//|                                    NQ Opening Range Retest EA.mq5 |
//|                    Ported from Pine Script v6 → MQL5 (EA)         |
//|                    Original: NQ_Opening_Range_Retest_Strategy.pine|
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: NQ Opening Range Retest Strategy ::"
#property description "Opening Range Breakout with retest entry model,"
#property description "multi-filter, ATR risk management, dashboard."

// ── ENUMS ───────────────────────────────────────────────────────────────────
enum ENUM_ORB_ENTRY_MODE  { ORB_BREAKOUT_ONLY, ORB_RETEST_ONLY, ORB_BREAKOUT_AND_RETEST };
enum ENUM_ORB_DIRECTION   { ORB_BOTH, ORB_LONG_ONLY, ORB_SHORT_ONLY };
enum ENUM_ORB_BREAK_TRIG  { ORB_CROSS, ORB_STATE };
enum ENUM_ORB_TRADE_WIN   { ORB_WIN_AM, ORB_WIN_AM_PM, ORB_WIN_FULL_RTH, ORB_WIN_CUSTOM };
enum ENUM_ORB_STOP_MODEL  { ORB_STOP_ATR, ORB_STOP_FIXED, ORB_STOP_OR };

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                           "═══ Session ═══"
input string                          InpORStart       = "09:30";           // OR Start (HH:MM)
input string                          InpOREnd         = "09:45";           // OR End (HH:MM)
input ENUM_ORB_TRADE_WIN              InpTradeWin      = ORB_WIN_FULL_RTH;  // Trade Window
input string                          InpAMStart       = "10:00";           // AM Start
input string                          InpAMEnd         = "11:30";           // AM End
input string                          InpPMStart       = "13:30";           // PM Start
input string                          InpPMEnd         = "15:45";           // PM End
input string                          InpCustomStart   = "10:00";           // Custom Start
input string                          InpCustomEnd     = "15:45";           // Custom End
input bool                            InpFlattenEOD    = true;              // Flatten Near Close
input string                          InpFlattenStart  = "15:55";           // Flatten Window Start
input string                          InpFlattenEnd    = "16:00";           // Flatten Window End

input group                           "═══ Entry Model ═══"
input ENUM_ORB_ENTRY_MODE             InpEntryMode     = ORB_BREAKOUT_AND_RETEST; // Entry Mode
input ENUM_ORB_DIRECTION              InpDirection     = ORB_BOTH;          // Trade Direction
input ENUM_ORB_BREAK_TRIG             InpBreakTrig     = ORB_STATE;         // Breakout Trigger
input double                          InpBreakBufPts   = 0.5;               // Breakout Buffer (points)
input double                          InpRetestBufATR  = 0.35;              // Retest Buffer (ATR mult)
input int                             InpRetestBars    = 20;                // Retest Window (bars)
input int                             InpMaxTradesDay  = 8;                 // Max Trades Per Day
input int                             InpCooldownBars  = 1;                 // Cooldown Bars

input group                           "═══ Filters ═══"
input bool                            InpUseVWAP       = false;             // VWAP Alignment
input bool                            InpUseEMA        = false;             // EMA Trend Filter
input int                             InpFastEMA       = 21;                // Fast EMA
input int                             InpSlowEMA       = 55;                // Slow EMA
input bool                            InpUseHTF        = false;             // HTF EMA Slope
input ENUM_TIMEFRAMES                 InpHTF           = PERIOD_M15;        // HTF Timeframe
input int                             InpHTFEMA        = 50;                // HTF EMA
input bool                            InpUseATRFloor   = false;             // ATR Floor
input double                          InpATRFloorPts   = 8.0;               // Min ATR (points)
input bool                            InpUseVol        = false;             // Volume Surge
input int                             InpVolLen        = 20;                // Volume SMA Length
input double                          InpVolMult       = 1.1;               // Volume Multiplier

input group                           "═══ Risk ═══"
input ENUM_ORB_STOP_MODEL             InpStopModel     = ORB_STOP_ATR;      // Stop Model
input int                             InpATRLen        = 14;                // ATR Length
input double                          InpATRStopMult   = 0.8;               // ATR Stop Multiplier
input double                          InpFixedStopPts  = 8.0;               // Fixed Stop (points)
input double                          InpORStopBufPts  = 3.0;               // OR Stop Buffer (points)
input double                          InpTargetR       = 2.5;               // Target R (risk multiple)
input bool                            InpUseRunner     = false;             // Use Runner Trail
input int                             InpRunnerQtyPct  = 35;                // Runner Qty %
input double                          InpTrailATRMult  = 2.0;               // Runner Trail ATR
input bool                            InpMoveToBE      = true;              // Move Stop to Breakeven
input double                          InpBER           = 1.0;               // BE Trigger R
input double                          InpRiskPct       = 1.0;               // Risk % Per Trade
input double                          InpFixedLot      = 0.01;              // Fixed Lot Size (0=auto)

input group                           "═══ Challenge Profile ═══"
input bool                            InpAggressive    = true;              // Aggressive $100 Challenge
input bool                            InpMomentumFB    = true;              // Momentum Fallback

input group                           "═══ Visuals ═══"
input bool                            InpShowOR        = true;              // Show Opening Range
input bool                            InpShowSignals   = true;              // Show Entry Signals
input bool                            InpShowDash      = true;              // Show Dashboard

// ── GLOBALS ─────────────────────────────────────────────────────────────────
string   g_prefix      = "NQ_ORB_";
datetime g_dayStart;
double   g_orHigh, g_orLow;
bool     g_rangeReady;
int      g_tradesToday;
datetime g_lastExitTime;
int      g_longBreakBar, g_shortBreakBar;
double   g_activeStopDist, g_activeEntryPrice;
int      g_emaFastH, g_emaSlowH, g_atrH;
string   g_orHighLine, g_orLowLine;
bool     g_lastBuy, g_lastSell;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_dayStart      = 0;
   g_orHigh        = 0;
   g_orLow         = 0;
   g_rangeReady    = false;
   g_tradesToday   = 0;
   g_lastExitTime  = 0;
   g_longBreakBar  = 0;
   g_shortBreakBar = 0;
   g_activeStopDist = 0;
   g_lastBuy       = false;
   g_lastSell      = false;
   
   g_emaFastH = iMA(_Symbol, PERIOD_CURRENT, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowH = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atrH     = iATR(_Symbol, PERIOD_CURRENT, InpATRLen);
   
   g_orHighLine = g_prefix + "OR_High";
   g_orLowLine  = g_prefix + "OR_Low";
   
   if(g_emaFastH == INVALID_HANDLE || g_emaSlowH == INVALID_HANDLE || g_atrH == INVALID_HANDLE)
      return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
   if(g_emaFastH != INVALID_HANDLE)  IndicatorRelease(g_emaFastH);
   if(g_emaSlowH != INVALID_HANDLE)  IndicatorRelease(g_emaSlowH);
   if(g_atrH != INVALID_HANDLE)      IndicatorRelease(g_atrH);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // ── Get current bar data ──
   MqlRates rt[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 5, rt) < 5) return;
   int idx = 4; // current bar (0=oldest, 4=newest in CopyRates)
   
   double o = rt[idx].open;
   double h = rt[idx].high;
   double l = rt[idx].low;
   double c = rt[idx].close;
   datetime barTime = rt[idx].time;
   
   // ── Time parsing ──
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   int nyMinutes = dt.hour * 60 + dt.min;
   bool nyWeekday = (dt.day_of_week >= 1 && dt.day_of_week <= 5);
   
   // Session times
   int orStartMin  = TimeStrToMin(InpORStart);    // e.g., 9*60+30 = 570
   int orEndMin    = TimeStrToMin(InpOREnd);      // 585
   int flatStartMin= TimeStrToMin(InpFlattenStart);
   int flatEndMin  = TimeStrToMin(InpFlattenEnd);
   
   bool inOR         = nyWeekday && nyMinutes >= orStartMin && nyMinutes < orEndMin;
   bool inFlatten    = nyWeekday && nyMinutes >= flatStartMin && nyMinutes < flatEndMin;
   
   // Trade window check
   bool inTradeWin = IsInTradeWindow(nyMinutes, nyWeekday, orStartMin, orEndMin);
   
   // ── Day change detection ──
   if(g_dayStart == 0 || barTime - g_dayStart > 86400)
   {
      g_dayStart     = barTime;
      g_orHigh       = 0;
      g_orLow        = 0;
      g_rangeReady   = false;
      g_tradesToday  = 0;
      g_longBreakBar = 0;
      g_shortBreakBar= 0;
      
      // Delete old OR lines
      ObjectDelete(0, g_orHighLine);
      ObjectDelete(0, g_orLowLine);
   }
   
   // ── Opening Range capture ──
   if(inOR)
   {
      if(g_orHigh == 0 || h > g_orHigh) g_orHigh = h;
      if(g_orLow == 0  || l < g_orLow)  g_orLow  = l;
      g_rangeReady = false;
   }
   else if(!g_rangeReady && g_orHigh > 0 && g_orLow > 0)
   {
      g_rangeReady = true;
      
      // Draw OR lines
      DrawORLines(barTime, g_orHigh, g_orLow);
   }
   
   // ── Background for OR / Trade window ──
   if(InpShowOR)
   {
      color bgColor = inOR ? C'0x00,0x00,0xFF' : (inTradeWin ? C'0x00,0xFF,0x00' : clrNONE);
      if(bgColor != clrNONE)
      {
         string bgName = g_prefix + "bg_" + IntegerToString(idx);
         ObjectDelete(0, bgName);
         CreateRect(bgName, barTime, h, barTime + PeriodSeconds(), l, bgColor, 15);
      }
   }
   
   // ── Indicators ──
   double emaFast[1], emaSlow[1], atrBuf[1];
   CopyBuffer(g_emaFastH, 0, 0, 1, emaFast);
   CopyBuffer(g_emaSlowH, 0, 0, 1, emaSlow);
   CopyBuffer(g_atrH, 0, 0, 1, atrBuf);
   double atrVal = atrBuf[0];
   
   // ── VWAP (approximation) ──
   double vwapVal = CalcVWAP();
   
   // ── HTF EMA ──
   double htfEma[1], htfEmaPrev[1];
   int htfH = iMA(_Symbol, InpHTF, InpHTFEMA, 0, MODE_EMA, PRICE_CLOSE);
   bool htfSlopeUp = false, htfSlopeDown = false;
   if(htfH != INVALID_HANDLE)
   {
      CopyBuffer(htfH, 0, 0, 1, htfEma);
      CopyBuffer(htfH, 0, 1, 1, htfEmaPrev);
      htfSlopeUp   = htfEma[0] > htfEmaPrev[0];
      htfSlopeDown = htfEma[0] < htfEmaPrev[0];
      IndicatorRelease(htfH);
   }
   
   // ── Volume filter ──
   bool volOk = true;
   if(InpUseVol)
   {
      long volArr[21];
      CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, 21, volArr);
      double volSMA = 0;
      for(int i = 1; i <= InpVolLen; i++) volSMA += volArr[i];
      volSMA /= InpVolLen;
      volOk = volArr[0] > volSMA * InpVolMult;
   }
   
   // ── ATR Floor ──
   bool atrOk = !InpUseATRFloor || atrVal >= InpATRFloorPts;
   
   // ── Filters ──
   bool longFilter  = (!InpUseVWAP || c > vwapVal) &&
                      (!InpUseEMA  || emaFast[0] > emaSlow[0]) &&
                      (!InpUseHTF  || htfSlopeUp) && volOk && atrOk;
   bool shortFilter = (!InpUseVWAP || c < vwapVal) &&
                      (!InpUseEMA  || emaFast[0] < emaSlow[0]) &&
                      (!InpUseHTF  || htfSlopeDown) && volOk && atrOk;
   
   bool canLong  = InpDirection != ORB_SHORT_ONLY;
   bool canShort = InpDirection != ORB_LONG_ONLY;
   
   // ── Cooldown ──
   bool cooldownOk = (InpCooldownBars == 0 || g_lastExitTime == 0 ||
                      barTime - g_lastExitTime > InpCooldownBars * PeriodSeconds());
   bool tradeCountOk = g_tradesToday < InpMaxTradesDay;
   bool posFlat = (PositionSelect(_Symbol) ? PositionGetDouble(POSITION_VOLUME) == 0 : true);
   bool canEnter = g_rangeReady && inTradeWin && cooldownOk && tradeCountOk && posFlat;
   
   // ── Breakout / Retest levels ──
   double longBreakLvl  = g_orHigh + InpBreakBufPts;
   double shortBreakLvl = g_orLow  - InpBreakBufPts;
   
   bool longBreakout  = false, shortBreakout = false;
   if(InpBreakTrig == ORB_CROSS)
   {
      longBreakout  = (c > longBreakLvl && o <= longBreakLvl);
      shortBreakout = (c < shortBreakLvl && o >= shortBreakLvl);
   }
   else
   {
      longBreakout  = (c > longBreakLvl && c > o);
      shortBreakout = (c < shortBreakLvl && c < o);
   }
   
   longBreakout  = canEnter && canLong  && longFilter  && longBreakout;
   shortBreakout = canEnter && canShort && shortFilter && shortBreakout;
   
   if(longBreakout)  g_longBreakBar  = barTime;
   if(shortBreakout) g_shortBreakBar = barTime;
   
   // ── Retest signals ──
   bool longRetestActive  = (g_longBreakBar > 0 && (int)(barTime - g_longBreakBar)/PeriodSeconds() <= InpRetestBars);
   bool shortRetestActive = (g_shortBreakBar > 0 && (int)(barTime - g_shortBreakBar)/PeriodSeconds() <= InpRetestBars);
   
   bool longRetest  = canEnter && canLong  && longFilter  && longRetestActive &&
                      l <= g_orHigh + atrVal * InpRetestBufATR && c > g_orHigh;
   bool shortRetest = canEnter && canShort && shortFilter && shortRetestActive &&
                      h >= g_orLow - atrVal * InpRetestBufATR && c < g_orLow;
   
   // ── Combine entry signals ──
   bool enterLong  = false, enterShort = false;
   if(InpEntryMode != ORB_RETEST_ONLY)        { enterLong |= longBreakout;  enterShort |= shortBreakout; }
   if(InpEntryMode != ORB_BREAKOUT_ONLY)      { enterLong |= longRetest;    enterShort |= shortRetest;  }
   
   // Momentum fallback (aggressive)
   if(InpAggressive && InpMomentumFB && cooldownOk && tradeCountOk && posFlat)
   {
      enterLong  |= (c > rt[idx-1].high && c > emaFast[0] && c > o);
      enterShort |= (c < rt[idx-1].low  && c < emaFast[0] && c < o);
   }
   
   // ── Execute trades ──
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipSize = point; // For indices, point ≈ tick
   
   // Calculate stop distance
   double stopDist = 0;
   if(InpStopModel == ORB_STOP_FIXED)       stopDist = InpFixedStopPts * pipSize;
   else if(InpStopModel == ORB_STOP_OR)     stopDist = MathMax(c - (g_orLow - InpORStopBufPts * pipSize), tickSz);
   else                                     stopDist = atrVal * InpATRStopMult * pipSize;
   
   double lotSize = InpFixedLot > 0 ? InpFixedLot : CalcLotSize(stopDist);
   
   if(enterLong)
   {
      double sl = c - stopDist;
      double tp = c + stopDist * InpTargetR;
      ExecuteTrade(ORDER_TYPE_BUY, lotSize, sl, tp, "NQ ORB Long");
      g_tradesToday++;
      g_longBreakBar = 0; g_shortBreakBar = 0;
      
      if(InpShowSignals)
         DrawSignal("L", barTime, l, clrLime, true);
   }
   
   if(enterShort)
   {
      double sl = c + stopDist;
      double tp = c - stopDist * InpTargetR;
      ExecuteTrade(ORDER_TYPE_SELL, lotSize, sl, tp, "NQ ORB Short");
      g_tradesToday++;
      g_longBreakBar = 0; g_shortBreakBar = 0;
      
      if(InpShowSignals)
         DrawSignal("S", barTime, h, clrRed, false);
   }
   
   // ── Manage open positions (breakeven, trail, flatten) ──
   ManagePositions(atrVal, point);
   
   // ── Flatten at EOD ──
   if(InpFlattenEOD && inFlatten && posFlat == false)
      CloseAllPositions("EOD Flatten");
   
   // ── Alerts ──
   if(enterLong && !g_lastBuy)
      Alert("NQ ORB LONG | ", _Symbol, " | Price: ", DoubleToString(c, _Digits));
   if(enterShort && !g_lastSell)
      Alert("NQ ORB SHORT | ", _Symbol, " | Price: ", DoubleToString(c, _Digits));
   g_lastBuy = enterLong; g_lastSell = enterShort;
   
   // ── Dashboard ──
   if(InpShowDash)
      RenderDashboard(c, emaFast[0], emaSlow[0], atrVal, vwapVal, longFilter, shortFilter,
                      inTradeWin, tradeCountOk, stopDist);
   
   // Track exit time
   if(!posFlat && g_lastExitTime == 0)
      g_lastExitTime = 0;
}

//+------------------------------------------------------------------+
//| Check if we're in the trade window                                |
//+------------------------------------------------------------------+
bool IsInTradeWindow(int nyMinutes, bool nyWeekday, int orEndMin, int orStartMin)
{
   if(!nyWeekday) return false;
   
   int amS  = TimeStrToMin(InpAMStart),  amE  = TimeStrToMin(InpAMEnd);
   int pmS  = TimeStrToMin(InpPMStart),  pmE  = TimeStrToMin(InpPMEnd);
   int cstS = TimeStrToMin(InpCustomStart), cstE = TimeStrToMin(InpCustomEnd);
   
   bool inRTH = nyMinutes >= orEndMin && nyMinutes < 16*60; // Full RTH: OR end to 16:00
   
   switch(InpTradeWin)
   {
      case ORB_WIN_AM:       return nyMinutes >= amS  && nyMinutes < amE;
      case ORB_WIN_AM_PM:    return (nyMinutes >= amS && nyMinutes < amE) || (nyMinutes >= pmS && nyMinutes < pmE);
      case ORB_WIN_FULL_RTH: return inRTH && nyMinutes >= orEndMin;
      case ORB_WIN_CUSTOM:   return nyMinutes >= cstS && nyMinutes < cstE;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Time string "HH:MM" → minutes                                     |
//+------------------------------------------------------------------+
int TimeStrToMin(string t)
{
   string parts[];
   StringSplit(t, ':', parts);
   if(ArraySize(parts) >= 2)
      return (int)parts[0] * 60 + (int)parts[1];
   return 0;
}

//+------------------------------------------------------------------+
//| Draw Opening Range lines                                          |
//+------------------------------------------------------------------+
void DrawORLines(datetime time, double orH, double orL)
{
   // High line
   if(ObjectFind(0, g_orHighLine) < 0)
   {
      ObjectCreate(0, g_orHighLine, OBJ_HLINE, 0, 0, orH);
      ObjectSetInteger(0, g_orHighLine, OBJPROP_COLOR, clrTeal);
      ObjectSetInteger(0, g_orHighLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, g_orHighLine, OBJPROP_STYLE, STYLE_DASH);
   }
   else ObjectSetDouble(0, g_orHighLine, OBJPROP_PRICE, orH);
   
   // Low line
   if(ObjectFind(0, g_orLowLine) < 0)
   {
      ObjectCreate(0, g_orLowLine, OBJ_HLINE, 0, 0, orL);
      ObjectSetInteger(0, g_orLowLine, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, g_orLowLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, g_orLowLine, OBJPROP_STYLE, STYLE_DASH);
   }
   else ObjectSetDouble(0, g_orLowLine, OBJPROP_PRICE, orL);
}

//+------------------------------------------------------------------+
//| Draw entry signal marker                                          |
//+------------------------------------------------------------------+
void DrawSignal(string text, datetime time, double price, color clr, bool below)
{
   string name = g_prefix + "sig_" + IntegerToString((int)time);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, below ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, below ? ANCHOR_TOP : ANCHOR_BOTTOM);
   }
}

//+------------------------------------------------------------------+
//| Create filled rectangle                                           |
//+------------------------------------------------------------------+
void CreateRect(string name, datetime t1, double p1, datetime t2, double p2, color clr, uchar alpha)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, ColorWithAlpha(clr, alpha));
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Color with alpha                                                  |
//+------------------------------------------------------------------+
color ColorWithAlpha(color clr, uchar alpha)
{
   return (color)(((uint)clr & 0x00FFFFFF) | ((uint)alpha << 24));
}

//+------------------------------------------------------------------+
//| Approximate VWAP (cumulative)                                    |
//+------------------------------------------------------------------+
double CalcVWAP()
{
   MqlRates rt[];
   int bars = iBars(_Symbol, PERIOD_D1);
   int count = MathMin(bars, 1000);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, count, rt) < count) return 0;
   
   double sumPV = 0, sumV = 0;
   for(int i = 0; i < count; i++)
   {
      double tp = (rt[i].high + rt[i].low + rt[i].close) / 3.0;
      double vol = (double)rt[i].tick_volume;
      if(vol <= 0) vol = 1;
      sumPV += tp * vol;
      sumV  += vol;
   }
   return (sumV > 0) ? sumPV / sumV : rt[count-1].close;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.type      = type;
   req.price     = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = 50;
   req.comment   = comment;
   req.type_filling = ORDER_FILLING_IOC;
   
   OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string comment)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action   = TRADE_ACTION_DEAL;
            req.symbol   = _Symbol;
            req.volume   = PositionGetDouble(POSITION_VOLUME);
            req.type     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                           ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price    = (req.type == ORDER_TYPE_BUY)
                           ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            req.deviation = 50;
            req.comment  = comment;
            OrderSend(req, res);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (BE, trail)                                 |
//+------------------------------------------------------------------+
void ManagePositions(double atr, double point)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      double entryPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl   = PositionGetDouble(POSITION_SL);
      double currentTp   = PositionGetDouble(POSITION_TP);
      double currentBid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool   isLong      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      
      double stopDist = currentSl > 0 ? MathAbs(entryPrice - currentSl) : atr * InpATRStopMult * point;
      
      // Breakeven
      if(InpMoveToBE)
      {
         double beTrigger = stopDist * InpBER;
         double profitPts = isLong ? (currentBid - entryPrice) : (entryPrice - currentAsk);
         
         if(profitPts >= beTrigger)
         {
            double newSl = isLong ? (entryPrice + point) : (entryPrice - point);
            if((isLong && (currentSl == 0 || newSl > currentSl)) ||
               (!isLong && (currentSl == 0 || newSl < currentSl)))
            {
               ModifySLTP(ticket, newSl, currentTp);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify SL/TP                                                      |
//+------------------------------------------------------------------+
void ModifySLTP(ulong ticket, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl       = sl;
   req.tp       = tp;
   req.symbol   = _Symbol;
   OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Auto lot sizing based on risk %                                   |
//+------------------------------------------------------------------+
double CalcLotSize(double stopDistPts)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPct / 100.0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(stopDistPts <= 0 || tickSize <= 0) return 0.01;
   
   double lotSize = riskAmt / (stopDistPts / tickSize * tickVal);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / step) * step;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Render Dashboard                                                  |
//+------------------------------------------------------------------+
void RenderDashboard(double c, double fastEMA, double slowEMA, double atr, double vwap,
                     bool longF, bool shortF, bool inWin, bool tradeOk, double stopDist)
{
   string dashPrefix = g_prefix + "dash_";
   int x = 10, y = 20, gap = 16, colW = 130;
   
   string biasText = longF && !shortF ? "LONG" : shortF && !longF ? "SHORT" :
                     longF && shortF ? "MIXED" : "BLOCKED";
   color biasClr = biasText == "LONG" ? clrLime : biasText == "SHORT" ? clrRed : clrSilver;
   
   string rangeText = g_rangeReady ? DoubleToString(g_orHigh - g_orLow, _Digits) + " pts" : "Building...";
   string winText   = inWin ? "OPEN" : "CLOSED";
   color  winClr    = inWin ? clrLime : clrSilver;
   
   int row = 0;
   DashRow(dashPrefix, row++, "NQ ORB", biasText, clrWhite, biasClr, x, y, gap, colW);
   DashRow(dashPrefix, row++, "OR Range", rangeText, clrSilver, clrWhite, x, y, gap, colW);
   DashRow(dashPrefix, row++, "ATR", DoubleToString(atr, _Digits), clrSilver, clrWhite, x, y, gap, colW);
   DashRow(dashPrefix, row++, "Window", winText, clrSilver, winClr, x, y, gap, colW);
   DashRow(dashPrefix, row++, "Trades", StringFormat("%d/%d", g_tradesToday, InpMaxTradesDay),
           clrSilver, tradeOk ? clrWhite : clrOrange, x, y, gap, colW);
   DashRow(dashPrefix, row++, "Risk", DoubleToString(stopDist / SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1) + " pts",
           clrSilver, clrWhite, x, y, gap, colW);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Dashboard row helper                                              |
//+------------------------------------------------------------------+
void DashRow(string prefix, int row, string label, string value, color lblClr, color valClr,
             int x, int y0, int gap, int colW)
{
   int yy = y0 + row * gap;
   CreateLabel(prefix + "l" + IntegerToString(row), label, x, yy, lblClr, 8);
   CreateLabel(prefix + "v" + IntegerToString(row), value, x + colW, yy, valClr, 8);
}

//+------------------------------------------------------------------+
//| Create OBJ_LABEL                                                  |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size = 8)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
}

//+------------------------------------------------------------------+
//| Cleanup chart objects                                             |
//+------------------------------------------------------------------+
void CleanupObjects()
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
