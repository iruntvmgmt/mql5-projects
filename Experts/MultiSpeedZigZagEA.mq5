//+------------------------------------------------------------------+
//| MultiSpeedZigZagEA.mq5                                           |
//| Standalone multi-strategy ATR ZigZag research/execution EA       |
//+------------------------------------------------------------------+
#property strict
#property version   "0.20"
#property description "Standalone Multi-Speed ZigZag strategy suite"

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Execution/EventStore.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionGuard.mqh>

input group "═══ Operating Mode ═══"
input bool   InpShadowOnly           = true;
input bool   InpAllowLiveExecution   = false;
input bool   InpAcknowledgeRisk      = false;
input long   InpMagic                = 26072501;
input int    InpHistoryBars          = 1500;

input group "═══ Fast Speed ═══"
input int    InpFastATRLen           = 14;
input double InpFastATRMult          = 1.0;

input group "═══ Medium Speed ═══"
input int    InpMedATRLen            = 14;
input double InpMedATRMult           = 2.0;

input group "═══ Slow Speed ═══"
input int    InpSlowATRLen           = 14;
input double InpSlowATRMult          = 3.5;

input group "═══ Strategy Enablement ═══"
input bool   InpEnableFastBreakout       = true;
input bool   InpEnableMediumBreakout     = true;
input bool   InpEnableSlowBreakout       = true;
input bool   InpEnableFastMedConfluence  = true;
input bool   InpEnableFastMedContext     = true;
input bool   InpEnableMedSlowContext     = true;
input bool   InpEnableNestedPullback     = true;
input bool   InpEnableWeightedEnsemble   = true;

input group "═══ Structure & Signal ═══"
input int    InpMinBarsBetween       = 3;
input double InpMinScore             = 5.0;
input double InpRiskReward           = 1.5;
input bool   InpOnePositionPerSymbol = true;

input group "═══ Standalone Execution ═══"
input double InpFixedLots            = 0.01;
input double InpMaxSpreadPoints      = 80.0;
input int    InpDeviationPoints      = 30;
input bool   InpExitOnOpposite       = true;
input int    InpMaxPersistentEvents  = 2000;

input group "═══ Diagnostics ═══"
input bool   InpWriteCSV             = true;
input bool   InpVerboseLog           = true;

CMSZZTripleZigZagEngine g_engine;
CMSZZStrategySuite      g_suite;
CMSZZEventStore         g_event_store;
CMSZZExecutionGuard     g_execution_guard;
CTrade                  g_trade;
datetime                g_last_bar=0;

bool EventConsumed(const string event_id)
{
   return g_event_store.Contains(event_id);
}

bool ConsumeEvent(const string event_id)
{
   return g_event_store.Add(event_id);
}

void Journal(const MSZZCandidate &c,const string status)
{
   string line=StringFormat("MSZZ %s %s score=%.2f entry=%.*f stop=%.*f target=%.*f event=%s reason=%s",
                            status,c.setup_name,c.score,_Digits,c.entry,_Digits,c.stop,_Digits,c.target,c.event_id,c.reason);
   if(InpVerboseLog) Print(line);
   if(!InpWriteCSV) return;

   int h=FileOpen("MSZZ_SignalJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("MSZZ journal open failed error=%d",GetLastError());
      return;
   }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","status","strategy_id","setup","direction","score","entry","stop","target","event_id","reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(c.signal_time,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),status,
             (int)c.strategy_id,c.setup_name,MSZZDirectionText(c.direction),DoubleToString(c.score,2),
             DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),DoubleToString(c.target,_Digits),
             c.event_id,c.reason);
   FileFlush(h);
   FileClose(h);
}

bool HasSymbolPosition()
{
   return PositionSelect(_Symbol);
}

bool LiveExecutionAuthorized()
{
   return (!InpShadowOnly && InpAllowLiveExecution && InpAcknowledgeRisk);
}

bool CloseOppositeIfNeeded(const MSZZCandidate &c)
{
   if(!InpExitOnOpposite || !PositionSelect(_Symbol)) return true;
   long type=PositionGetInteger(POSITION_TYPE);
   bool opposite=(c.direction==MSZZ_DIR_LONG && type==POSITION_TYPE_SELL) ||
                 (c.direction==MSZZ_DIR_SHORT && type==POSITION_TYPE_BUY);
   if(!opposite) return true;
   if(!g_trade.PositionClose(_Symbol))
   {
      PrintFormat("MSZZ opposite close failed retcode=%u %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool PrepareMarketCandidate(const MSZZCandidate &source,MSZZCandidate &prepared,string &reason)
{
   prepared=source;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      reason="no current tick";
      return false;
   }
   prepared.entry=(source.direction==MSZZ_DIR_LONG ? tick.ask : tick.bid);
   double risk=MathAbs(prepared.entry-source.stop);
   if(risk<=0.0)
   {
      reason="market entry equals structural stop";
      return false;
   }
   prepared.target=(source.direction==MSZZ_DIR_LONG ? prepared.entry+risk*InpRiskReward
                                                    : prepared.entry-risk*InpRiskReward);
   return g_execution_guard.ValidateStops(prepared,prepared.stop,prepared.target,reason);
}

bool ExecuteCandidate(const MSZZCandidate &source)
{
   if(!LiveExecutionAuthorized())
   {
      Journal(source,"SHADOW");
      return true;
   }
   if(source.score<InpMinScore) { Journal(source,"REJECT_SCORE"); return false; }
   if(EventConsumed(source.event_id)) { Journal(source,"REJECT_DUPLICATE"); return false; }

   string reason;
   if(!g_execution_guard.TradingAllowed(reason))
   {
      MSZZCandidate rejected=source; rejected.reason=reason;
      Journal(rejected,"REJECT_TRADING_DISABLED");
      return false;
   }

   double spread_points=0.0;
   if(!g_execution_guard.SpreadAllowed(InpMaxSpreadPoints,spread_points))
   {
      MSZZCandidate rejected=source;
      rejected.reason=StringFormat("spread %.1f exceeds maximum %.1f points",spread_points,InpMaxSpreadPoints);
      Journal(rejected,"REJECT_SPREAD");
      return false;
   }

   MSZZCandidate prepared;
   if(!PrepareMarketCandidate(source,prepared,reason))
   {
      MSZZCandidate rejected=source; rejected.reason=reason;
      Journal(rejected,"REJECT_STOPS");
      return false;
   }

   double volume=g_execution_guard.NormalizeVolume(InpFixedLots);
   if(volume<=0.0)
   {
      prepared.reason="volume normalization failed";
      Journal(prepared,"REJECT_VOLUME");
      return false;
   }

   if(!CloseOppositeIfNeeded(prepared))
   {
      Journal(prepared,"REJECT_OPPOSITE_CLOSE_FAILED");
      return false;
   }
   if(InpOnePositionPerSymbol && HasSymbolPosition())
   {
      Journal(prepared,"REJECT_POSITION_EXISTS");
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok=false;
   string comment="MSZZ|"+IntegerToString((int)prepared.strategy_id);
   if(prepared.direction==MSZZ_DIR_LONG)
      ok=g_trade.Buy(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);
   else if(prepared.direction==MSZZ_DIR_SHORT)
      ok=g_trade.Sell(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);

   if(ok)
   {
      if(!ConsumeEvent(prepared.event_id))
         Print("MSZZ WARNING: order executed but event persistence failed; duplicate risk exists after restart.");
      Journal(prepared,"EXECUTED");
   }
   else
   {
      prepared.reason=StringFormat("retcode=%u %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      Journal(prepared,"ORDER_FAILED");
   }
   return ok;
}

void ProcessClosedBar()
{
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int requested=MathMax(300,InpHistoryBars);
   int copied=CopyRates(_Symbol,_Period,0,requested,rates);
   if(copied<100)
   {
      PrintFormat("MSZZ insufficient bars copied=%d error=%d",copied,GetLastError());
      return;
   }

   int closed_count=copied-1;
   if(closed_count<100) return;

   g_engine.Configure(InpFastATRLen,InpFastATRMult,InpMedATRLen,InpMedATRMult,
                      InpSlowATRLen,InpSlowATRMult,InpMinBarsBetween);
   if(!g_engine.Rebuild(_Symbol,_Period,rates,closed_count)) return;

   MSZZSpeedSnapshot fast=g_engine.Snapshot(MSZZ_SPEED_FAST);
   MSZZSpeedSnapshot med =g_engine.Snapshot(MSZZ_SPEED_MEDIUM);
   MSZZSpeedSnapshot slow=g_engine.Snapshot(MSZZ_SPEED_SLOW);

   MSZZCandidate candidates[];
   g_suite.SetRiskReward(InpRiskReward);
   g_suite.ConfigureStrategies(InpEnableFastBreakout,InpEnableMediumBreakout,InpEnableSlowBreakout,
                               InpEnableFastMedConfluence,InpEnableFastMedContext,InpEnableMedSlowContext,
                               InpEnableNestedPullback,InpEnableWeightedEnsemble);
   int count=g_suite.Evaluate(fast,med,slow,rates[closed_count-1].time,rates[closed_count-1].close,candidates);
   if(count<=0) return;

   for(int i=0;i<count;i++)
      if(candidates[i].valid) Journal(candidates[i],"RAW_CANDIDATE");

   MSZZCandidate selected;
   int best=g_suite.SelectBestClustered(candidates,count,selected);
   if(best<0 || !selected.valid) return;
   if(selected.score<InpMinScore) { Journal(selected,"REJECT_SCORE"); return; }
   if(EventConsumed(selected.event_id)) { Journal(selected,"REJECT_DUPLICATE"); return; }

   ExecuteCandidate(selected);
   if(!LiveExecutionAuthorized())
   {
      if(!ConsumeEvent(selected.event_id))
         Print("MSZZ WARNING: shadow event persistence failed.");
   }
}

int OnInit()
{
   if(InpFastATRLen<1 || InpMedATRLen<1 || InpSlowATRLen<1 ||
      InpFastATRMult<=0.0 || InpMedATRMult<=0.0 || InpSlowATRMult<=0.0 ||
      InpRiskReward<=0.0 || InpHistoryBars<300)
   {
      Print("MSZZ invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   if(!g_execution_guard.Load(_Symbol))
   {
      Print("MSZZ failed to load symbol execution properties.");
      return INIT_FAILED;
   }

   g_event_store.Configure(_Symbol,_Period,InpMagic,InpMaxPersistentEvents);
   if(!g_event_store.Load())
   {
      Print("MSZZ failed to load persistent event store.");
      return INIT_FAILED;
   }

   if(!LiveExecutionAuthorized())
      Print("MSZZ initialized in SHADOW posture. Orders require ShadowOnly=false, AllowLiveExecution=true, and AcknowledgeRisk=true.");
   else
      Print("MSZZ WARNING: LIVE EXECUTION AUTHORIZED by all three gates.");

   PrintFormat("MSZZ event store loaded count=%d file=%s",g_event_store.Count(),g_event_store.Filename());
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==0 || bar==g_last_bar) return;
   g_last_bar=bar;
   ProcessClosedBar();
}

void OnDeinit(const int reason)
{
   PrintFormat("MSZZ deinitialized reason=%d",reason);
}
