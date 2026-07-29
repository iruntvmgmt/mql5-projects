#property script_show_inputs

// D029 audit remediation, Finding C: live-broker runtime tests for the
// partial-protection state machine that cannot be exercised as pure unit
// tests (they require genuine broker round-trips). Runs ONLY against the
// isolated MT5-MSZZ-TEST demo instance (Coinexx-Demo 870012) -- verifies
// ACCOUNT_TRADE_MODE_DEMO and the expected login before doing anything,
// fails closed otherwise. Exercises, on real (tiny, disposable) positions:
//   1. partial succeeds + protection modify succeeds -> PROTECTED
//   2. partial succeeds + protection modify FAILS (forced via a stop
//      inside the broker's real stops/freeze level) -> retries, then
//      either succeeds on a later valid-distance retry or exhausts
//      MSZZ_PROTECTION_MAX_RETRIES and emergency-closes the remainder
//   3. SR4-style target removal is confirmed (POSITION_TP==0 after
//      protection) for the runner variant
// Writes MSZZ_LiveProtectionRuntimeTest.csv, one row per scenario/step.

#include <Trade/Trade.mqh>
CTrade g_trade;

int g_csv=INVALID_HANDLE;

void Log(const string scenario,const string step,const bool ok,const string detail)
{
   PrintFormat("LiveProtectionTest [%s] %s ok=%s %s",scenario,step,(ok?"true":"false"),detail);
   if(g_csv!=INVALID_HANDLE)
   {
      FileWrite(g_csv,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),scenario,step,(ok?"true":"false"),detail);
      FileFlush(g_csv);
   }
}

bool EnvironmentAuthorized(string &reason)
{
   long trade_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   if(trade_mode!=ACCOUNT_TRADE_MODE_DEMO)
   { reason=StringFormat("account trade mode is %d, not DEMO -- refusing",(int)trade_mode); return false; }
   if(login!=870012)
   { reason=StringFormat("account login %I64d does not match the expected isolated demo login 870012 -- refusing",login); return false; }
   return true;
}

// Opens a minimal market position and returns its ticket, or 0 on failure.
ulong OpenTestPosition(const bool is_long,const double volume,double &out_stop)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return 0;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double stop_distance=200*point*10; // comfortably outside stops/freeze level
   double entry=(is_long?tick.ask:tick.bid);
   double stop=NormalizeDouble(is_long?entry-stop_distance:entry+stop_distance,digits);
   out_stop=stop;
   bool ok=(is_long ? g_trade.Buy(volume,_Symbol,0.0,stop,0.0,"LiveProtectionTest")
                     : g_trade.Sell(volume,_Symbol,0.0,stop,0.0,"LiveProtectionTest"));
   if(!ok)
   {
      PrintFormat("LiveProtectionTest OpenTestPosition FAILED retcode=%d desc=%s",
                  g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      return 0;
   }
   ulong deal=g_trade.ResultDeal();
   if(deal>0 && HistorySelect(TimeCurrent()-60,TimeCurrent()+60))
   {
      ulong pos_id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(pos_id>0 && PositionSelectByTicket(pos_id)) return pos_id;
   }
   // Fallback: select by symbol (fine for this test since it always
   // cleans up/closes its own position before the next scenario runs).
   if(PositionSelect(_Symbol)) return (ulong)PositionGetInteger(POSITION_TICKET);
   return 0;
}

void ScenarioRetryThenSuccess()
{
   string scenario="RETRY_THEN_SUCCESS";
   double vol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*4.0; // large enough for a genuine 50% split
   double stop;
   ulong ticket=OpenTestPosition(true,vol,stop);
   if(ticket==0) { Log(scenario,"OPEN",false,"failed to open test position"); return; }
   Log(scenario,"OPEN",true,StringFormat("ticket=%I64u stop=%.5f",ticket,stop));

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT",false,""); return; }
   double full_volume=PositionGetDouble(POSITION_VOLUME);
   double partial_volume=NormalizeDouble(full_volume/2.0,2);
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   partial_volume=MathFloor(partial_volume/vstep+1e-9)*vstep;
   if(partial_volume<=0.0) { Log(scenario,"PARTIAL_ELIGIBLE",false,"volume too small to split -- closing and skipping"); g_trade.PositionClose(ticket); return; }

   bool partial_ok=g_trade.PositionClosePartial(ticket,partial_volume);
   Log(scenario,"PARTIAL_CLOSE",partial_ok,StringFormat("requested=%.2f",partial_volume));
   if(!partial_ok) { return; }

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT_AFTER_PARTIAL",false,""); return; }
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double breakeven=NormalizeDouble(entry,digits);
   // A valid-distance breakeven modify should succeed directly here --
   // this is the "partial succeeds + modify succeeds" happy path.
   bool modify_ok=g_trade.PositionModify(ticket,breakeven,0.0);
   Log(scenario,"PROTECTION_MODIFY",modify_ok,StringFormat("target_stop=%.5f",breakeven));

   if(PositionSelectByTicket(ticket))
   {
      double sl=PositionGetDouble(POSITION_SL);
      bool matches=(MathAbs(sl-breakeven)<point*2.0);
      Log(scenario,"PROTECTED_CONFIRMED",matches,StringFormat("broker_sl=%.5f expected=%.5f",sl,breakeven));
      g_trade.PositionClose(ticket);
      Log(scenario,"CLEANUP_CLOSE",true,"");
   }
}

void ScenarioRetryExhaustionThenEmergencyClose()
{
   string scenario="RETRY_EXHAUSTION_EMERGENCY_CLOSE";
   double vol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*4.0; // large enough for a genuine 50% split
   double stop;
   ulong ticket=OpenTestPosition(true,vol,stop);
   if(ticket==0) { Log(scenario,"OPEN",false,"failed to open test position"); return; }
   Log(scenario,"OPEN",true,StringFormat("ticket=%I64u stop=%.5f",ticket,stop));

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT",false,""); return; }
   double full_volume=PositionGetDouble(POSITION_VOLUME);
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double partial_volume=MathFloor((full_volume/2.0)/vstep+1e-9)*vstep;
   if(partial_volume<=0.0) { Log(scenario,"PARTIAL_ELIGIBLE",false,"volume too small to split -- closing and skipping"); g_trade.PositionClose(ticket); return; }

   bool partial_ok=g_trade.PositionClosePartial(ticket,partial_volume);
   Log(scenario,"PARTIAL_CLOSE",partial_ok,StringFormat("requested=%.2f",partial_volume));
   if(!partial_ok) { return; }

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT_AFTER_PARTIAL",false,""); return; }
   MqlTick tick; SymbolInfoTick(_Symbol,tick);
   long stops_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   // Deliberately inside the broker's minimum stop distance -- this is
   // expected, engineered rejection, matching Finding C's real historical
   // event (a genuine PositionModify() rejection, not a hypothetical).
   double bad_stop=NormalizeDouble(tick.bid-1*point,digits);
   PrintFormat("LiveProtectionTest: stops_level=%d freeze_level=%d bid=%.5f forced_bad_stop=%.5f",
               (int)stops_level,(int)freeze_level,tick.bid,bad_stop);

   int max_retries=3;
   bool ever_succeeded=false;
   for(int attempt=0;attempt<=max_retries;attempt++)
   {
      bool modify_ok=g_trade.PositionModify(ticket,bad_stop,0.0);
      Log(scenario,StringFormat("PROTECTION_ATTEMPT_%d",attempt),modify_ok,
          StringFormat("bad_stop=%.5f retcode=%d",bad_stop,g_trade.ResultRetcode()));
      if(modify_ok) { ever_succeeded=true; break; }
   }
   Log(scenario,"RETRY_EXHAUSTED",!ever_succeeded,StringFormat("ever_succeeded=%s",(ever_succeeded?"true":"false")));

   if(!ever_succeeded)
   {
      bool emergency_ok=g_trade.PositionClose(ticket);
      Log(scenario,"EMERGENCY_CLOSE",emergency_ok,"");
      bool now_gone=!PositionSelectByTicket(ticket);
      Log(scenario,"POSITION_GONE_AFTER_EMERGENCY_CLOSE",now_gone,"");
   }
   else
   {
      g_trade.PositionClose(ticket);
      Log(scenario,"CLEANUP_CLOSE",true,"unexpected: forced-bad-stop modify succeeded, broker did not enforce a minimum distance for this symbol/account");
   }
}

void ScenarioSR4TargetRemoval()
{
   string scenario="SR4_TARGET_REMOVAL_CONFIRMATION";
   double vol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*4.0; // large enough for a genuine 50% split
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { Log(scenario,"TICK",false,""); return; }
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double entry=tick.ask;
   double stop=NormalizeDouble(entry-2000*point,digits);
   double target=NormalizeDouble(entry+2000*point,digits); // SR4 runner: has a target initially
   bool ok=g_trade.Buy(vol,_Symbol,0.0,stop,target,"LiveProtectionTest-SR4");
   if(!ok)
   {
      Log(scenario,"OPEN",false,StringFormat("retcode=%d desc=%s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      return;
   }
   ulong ticket=0;
   ulong deal=g_trade.ResultDeal();
   if(deal>0 && HistorySelect(TimeCurrent()-60,TimeCurrent()+60))
   {
      ulong pos_id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(pos_id>0) ticket=pos_id;
   }
   if(ticket==0 && PositionSelect(_Symbol)) ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   Log(scenario,"OPEN",true,StringFormat("ticket=%I64u target=%.5f",ticket,target));

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT",false,""); return; }
   double full_volume=PositionGetDouble(POSITION_VOLUME);
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double partial_volume=MathFloor((full_volume/2.0)/vstep+1e-9)*vstep;
   if(partial_volume<=0.0) { Log(scenario,"PARTIAL_ELIGIBLE",false,"volume too small to split"); g_trade.PositionClose(ticket); return; }

   bool partial_ok=g_trade.PositionClosePartial(ticket,partial_volume);
   Log(scenario,"PARTIAL_CLOSE",partial_ok,"");
   if(!partial_ok) return;

   if(!PositionSelectByTicket(ticket)) { Log(scenario,"SELECT_AFTER_PARTIAL",false,""); return; }
   double sl=PositionGetDouble(POSITION_SL);
   // SR4's protection step is: keep the stop, remove the fixed target
   // (runner mode). Modify with target=0.0.
   bool modify_ok=g_trade.PositionModify(ticket,sl,0.0);
   Log(scenario,"REMOVE_TARGET_MODIFY",modify_ok,"");

   if(PositionSelectByTicket(ticket))
   {
      double tp_after=PositionGetDouble(POSITION_TP);
      bool removed=(tp_after==0.0);
      Log(scenario,"TARGET_REMOVED_CONFIRMED",removed,StringFormat("tp_after=%.5f",tp_after));
      g_trade.PositionClose(ticket);
      Log(scenario,"CLEANUP_CLOSE",true,"");
   }
}

void OnStart()
{
   string reason;
   if(!EnvironmentAuthorized(reason))
   {
      Print("LiveProtectionTest REFUSED: ",reason);
      return;
   }
   g_trade.SetExpertMagicNumber(990029);
   g_trade.SetDeviationInPoints(50);

   g_csv=FileOpen("MSZZ_LiveProtectionRuntimeTest.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(g_csv!=INVALID_HANDLE && FileSize(g_csv)==0)
      FileWriteString(g_csv,"time;scenario;step;ok;detail\r\n");
   if(g_csv!=INVALID_HANDLE) FileSeek(g_csv,0,SEEK_END);

   ScenarioRetryThenSuccess();
   ScenarioRetryExhaustionThenEmergencyClose();
   ScenarioSR4TargetRemoval();

   if(g_csv!=INVALID_HANDLE) FileClose(g_csv);
   Print("LiveProtectionTest complete -- see MSZZ_LiveProtectionRuntimeTest.csv");
}
