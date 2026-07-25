//+------------------------------------------------------------------+
//| MultiSpeedZigZagEA.mq5                                           |
//| Standalone multi-strategy ATR ZigZag research/execution EA       |
//+------------------------------------------------------------------+
#property strict
#property version   "0.10"
#property description "Standalone Multi-Speed ZigZag strategy suite"

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>

input group "═══ Operating Mode ═══"
input bool   InpShadowOnly          = true;
input bool   InpAllowLiveExecution  = false;
input long   InpMagic               = 26072501;
input int    InpHistoryBars         = 1500;

input group "═══ Fast Speed ═══"
input int    InpFastATRLen          = 14;
input double InpFastATRMult         = 1.0;

input group "═══ Medium Speed ═══"
input int    InpMedATRLen           = 14;
input double InpMedATRMult          = 2.0;

input group "═══ Slow Speed ═══"
input int    InpSlowATRLen          = 14;
input double InpSlowATRMult         = 3.5;

input group "═══ Structure & Signal ═══"
input int    InpMinBarsBetween      = 3;
input double InpMinScore            = 5.0;
input double InpRiskReward          = 1.5;
input bool   InpOnePositionPerSymbol = true;

input group "═══ Standalone Execution ═══"
input double InpFixedLots           = 0.01;
input int    InpDeviationPoints     = 30;
input bool   InpExitOnOpposite      = true;

input group "═══ Diagnostics ═══"
input bool   InpWriteCSV            = true;
input bool   InpVerboseLog          = true;

CMSZZTripleZigZagEngine g_engine;
CMSZZStrategySuite      g_suite;
CTrade                  g_trade;
datetime                g_last_bar=0;
string                  g_consumed_events[];

bool EventConsumed(const string event_id)
{
   for(int i=0;i<ArraySize(g_consumed_events);i++)
      if(g_consumed_events[i]==event_id) return true;
   return false;
}

void ConsumeEvent(const string event_id)
{
   if(event_id=="" || EventConsumed(event_id)) return;
   int n=ArraySize(g_consumed_events);
   ArrayResize(g_consumed_events,n+1);
   g_consumed_events[n]=event_id;
   if(ArraySize(g_consumed_events)>1000)
   {
      for(int i=1;i<ArraySize(g_consumed_events);i++) g_consumed_events[i-1]=g_consumed_events[i];
      ArrayResize(g_consumed_events,1000);
   }
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
   FileClose(h);
}

bool HasSymbolPosition()
{
   return PositionSelect(_Symbol);
}

void CloseOppositeIfNeeded(const MSZZCandidate &c)
{
   if(!InpExitOnOpposite || !PositionSelect(_Symbol)) return;
   long type=PositionGetInteger(POSITION_TYPE);
   bool opposite=(c.direction==MSZZ_DIR_LONG && type==POSITION_TYPE_SELL) ||
                 (c.direction==MSZZ_DIR_SHORT && type==POSITION_TYPE_BUY);
   if(opposite) g_trade.PositionClose(_Symbol);
}

bool ExecuteCandidate(const MSZZCandidate &c)
{
   if(InpShadowOnly || !InpAllowLiveExecution)
   {
      Journal(c,"SHADOW");
      return true;
   }
   if(c.score<InpMinScore) { Journal(c,"REJECT_SCORE"); return false; }
   if(EventConsumed(c.event_id)) { Journal(c,"REJECT_DUPLICATE"); return false; }

   CloseOppositeIfNeeded(c);
   if(InpOnePositionPerSymbol && HasSymbolPosition())
   {
      Journal(c,"REJECT_POSITION_EXISTS");
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok=false;
   if(c.direction==MSZZ_DIR_LONG)
      ok=g_trade.Buy(InpFixedLots,_Symbol,0.0,c.stop,c.target,"MSZZ|"+IntegerToString((int)c.strategy_id));
   else if(c.direction==MSZZ_DIR_SHORT)
      ok=g_trade.Sell(InpFixedLots,_Symbol,0.0,c.stop,c.target,"MSZZ|"+IntegerToString((int)c.strategy_id));

   if(ok)
   {
      ConsumeEvent(c.event_id);
      Journal(c,"EXECUTED");
   }
   else
   {
      Journal(c,"ORDER_FAILED_"+IntegerToString((int)g_trade.ResultRetcode()));
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

   // Exclude the currently forming bar. Structural decisions use closed bars only.
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
   int count=g_suite.Evaluate(fast,med,slow,rates[closed_count-1].time,rates[closed_count-1].close,candidates);
   if(count<=0) return;

   for(int i=0;i<count;i++)
      if(candidates[i].valid && candidates[i].score>=InpMinScore) Journal(candidates[i],"RAW_CANDIDATE");

   MSZZCandidate selected;
   int best=g_suite.SelectBestClustered(candidates,count,selected);
   if(best<0 || !selected.valid) return;
   if(selected.score<InpMinScore) { Journal(selected,"REJECT_SCORE"); return; }
   if(EventConsumed(selected.event_id)) { Journal(selected,"REJECT_DUPLICATE"); return; }

   ExecuteCandidate(selected);
   // Shadow events are also consumed in-memory to guarantee one decision per structural event per attach.
   if(InpShadowOnly) ConsumeEvent(selected.event_id);
}

int OnInit()
{
   if(InpAllowLiveExecution && InpShadowOnly)
      Print("MSZZ: live execution requested but ShadowOnly remains enabled; no orders will be sent.");
   if(!InpShadowOnly && !InpAllowLiveExecution)
      Print("MSZZ: ShadowOnly disabled without live authorization; no orders will be sent.");

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   Print("MSZZ standalone suite initialized. Default posture is SHADOW ONLY.");
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
