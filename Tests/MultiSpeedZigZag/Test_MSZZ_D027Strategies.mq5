#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Strategies/D027StrategyFamilies.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>

int g_tests=0,g_failures=0;
void AssertTrue(const bool condition,const string name)
{
   g_tests++;
   if(!condition){ g_failures++; Print("FAIL: ",name); }
   else Print("PASS: ",name);
}

MSZZPivot Pivot(const ENUM_MSZZ_PIVOT_KIND kind,const ENUM_MSZZ_STRUCTURE_LABEL label,
                const double price,const string id,const datetime t)
{
   MSZZPivot p; ZeroMemory(p); p.valid=true; p.kind=kind; p.structure_label=label;
   p.price=price; p.id=id; p.pivot_time=t-300; p.confirmed_time=t; return p;
}

void BaseSnapshots(MSZZSpeedSnapshot &f,MSZZSpeedSnapshot &m,MSZZSpeedSnapshot &s,const datetime t)
{
   ZeroMemory(f); ZeroMemory(m); ZeroMemory(s);
   f.speed=MSZZ_SPEED_FAST; m.speed=MSZZ_SPEED_MEDIUM; s.speed=MSZZ_SPEED_SLOW;
   f.atr=10.0; m.atr=20.0; s.atr=35.0;
   f.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,100.0,"FL",t);
   f.prior_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_LL,95.0,"FPL",t-600);
   f.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,110.0,"FH",t);
   f.prior_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_LH,105.0,"FPH",t-600);
   m.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,90.0,"ML",t);
   m.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,115.0,"MH",t);
   s.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,80.0,"SL",t);
   s.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,120.0,"SH",t);
   f.leg_direction=MSZZ_DIR_LONG; m.leg_direction=MSZZ_DIR_LONG; s.leg_direction=MSZZ_DIR_LONG;
   f.resistance_now=110.0; f.support_now=100.0;
}

MSZZRegimeState Regime(const ENUM_MSZZ_MARKET_PHASE phase)
{
   MSZZRegimeState r; ZeroMemory(r); r.valid=true; r.market_phase=phase;
   r.volatility_state=MSZZ_VOL_NORMAL; return r;
}

MqlRates Bar(const datetime t,const double low,const double high,const double close)
{
   MqlRates b; ZeroMemory(b); b.time=t; b.open=close; b.low=low; b.high=high; b.close=close; return b;
}

void ConfigureOnly(CMSZZD027StrategyFamilies &suite,const int which,const string state_file="")
{
   suite.Configure(which==1,which==2,which==3,which==4,which==5,2.0,3,300,false,state_file);
}

void TestPullbacks()
{
   datetime t=D'2026.01.02 10:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies suite; ConfigureOnly(suite,1);
   f.bullish_break=true; f.bullish_event_id="FB";
   MSZZCandidate out[]; int n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_PULLBACK),Bar(t,101,112,111),out);
   AssertTrue(n==1 && out[0].strategy_id==MSZZ_STRAT_ALIGNED_FAST_PULLBACK &&
              out[0].family_id==MSZZ_FAMILY_PULLBACK && out[0].direction==MSZZ_DIR_LONG &&
              out[0].stop==100.0,"pullback long and family identity");

   BaseSnapshots(f,m,s,t+300); f.leg_direction=MSZZ_DIR_SHORT; m.leg_direction=MSZZ_DIR_SHORT; s.leg_direction=MSZZ_DIR_SHORT;
   f.last_high.structure_label=MSZZ_STRUCT_LH; f.bearish_break=true; f.bearish_event_id="FS";
   n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_PULLBACK),Bar(t+300,98,109,99),out);
   AssertTrue(n==1 && out[0].direction==MSZZ_DIR_SHORT && out[0].stop==110.0,"pullback short");

   f.last_high.structure_label=MSZZ_STRUCT_HH;
   n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_PULLBACK),Bar(t+600,98,109,99),out);
   AssertTrue(n==0,"pullback invalidation/premature pivot rejected");
}

void TestRetestAndRestart()
{
   datetime t=D'2026.01.02 11:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies suite; ConfigureOnly(suite,2);
   f.bullish_break=true; f.bullish_event_id="BREAK-L";
   MSZZCandidate out[]; int n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_BREAKOUT),Bar(t,108,114,112),out);
   AssertTrue(n==0,"retest origin does not trigger on breakout bar");
   f.bullish_break=false;
   n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_TREND_CONTINUATION),Bar(t+300,110.5,113,112),out);
   AssertTrue(n==1 && out[0].strategy_id==MSZZ_STRAT_BREAKOUT_RETEST &&
              out[0].family_id==MSZZ_FAMILY_RETEST && out[0].origin_id=="BREAK-L","retest identity and reclaim");

   CMSZZD027StrategyFamilies expiry; ConfigureOnly(expiry,2);
   BaseSnapshots(f,m,s,t); f.bullish_break=true; f.bullish_event_id="EXP"; expiry.Evaluate(f,m,s,Regime(MSZZ_PHASE_BREAKOUT),Bar(t,108,114,112),out);
   f.bullish_break=false; expiry.Evaluate(f,m,s,Regime(MSZZ_PHASE_UNCLASSIFIED),Bar(t+13*300,112,114,113),out);
   n=expiry.Evaluate(f,m,s,Regime(MSZZ_PHASE_UNCLASSIFIED),Bar(t+14*300,110,113,112),out);
   AssertTrue(n==0,"retest expiry");

   string file="Test_D027_Restart.csv"; FileDelete(file);
   CMSZZD027StrategyFamilies before; ConfigureOnly(before,2,file);
   BaseSnapshots(f,m,s,t); f.bullish_break=true; f.bullish_event_id="RESTART";
   before.Evaluate(f,m,s,Regime(MSZZ_PHASE_BREAKOUT),Bar(t,108,114,112),out);
   AssertTrue(before.SaveState(),"retest state saved");
   CMSZZD027StrategyFamilies after; ConfigureOnly(after,2,file);
   AssertTrue(after.LoadState(),"retest state loaded");
   f.bullish_break=false;
   n=after.Evaluate(f,m,s,Regime(MSZZ_PHASE_TREND_CONTINUATION),Bar(t+300,110.5,113,112),out);
   AssertTrue(n==1 && out[0].origin_id=="RESTART","restart restores exact armed retest");
   FileDelete(file);
}

void TestSweeps()
{
   datetime t=D'2026.01.02 12:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies suite; ConfigureOnly(suite,3);
   MSZZCandidate out[];
   int n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_TRANSITION),Bar(t,98.5,103,101),out);
   AssertTrue(n==1 && out[0].strategy_id==MSZZ_STRAT_SWEEP_RECLAIM &&
              out[0].direction==MSZZ_DIR_LONG && out[0].family_id==MSZZ_FAMILY_REVERSAL,
              "sweep reclaim long");

   CMSZZD027StrategyFamilies short_suite; ConfigureOnly(short_suite,3);
   BaseSnapshots(f,m,s,t); f.leg_direction=MSZZ_DIR_SHORT; m.leg_direction=MSZZ_DIR_SHORT; s.leg_direction=MSZZ_DIR_SHORT;
   f.last_high.structure_label=MSZZ_STRUCT_LH;
   n=short_suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_TRANSITION),Bar(t,107,111.5,109),out);
   AssertTrue(n==1 && out[0].direction==MSZZ_DIR_SHORT,"sweep reclaim short");

   CMSZZD027StrategyFamilies wick; ConfigureOnly(wick,3);
   BaseSnapshots(f,m,s,t);
   n=wick.Evaluate(f,m,s,Regime(MSZZ_PHASE_TRANSITION),Bar(t,98.5,102,99.8),out);
   AssertTrue(n==0,"sweep without closed-bar reclaim rejected");
}

void TestCompression()
{
   datetime t=D'2026.01.02 13:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies suite; ConfigureOnly(suite,4);
   MSZZCandidate out[]; int n=0;
   for(int i=0;i<3;i++)
      n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_COMPRESSION),Bar(t+i*300,101,109,105),out);
   AssertTrue(n==0,"compression requires release after persistence");
   n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_BREAKOUT),Bar(t+900,104,112,111),out);
   AssertTrue(n==1 && out[0].strategy_id==MSZZ_STRAT_COMPRESSION_BREAKOUT &&
              out[0].direction==MSZZ_DIR_LONG && out[0].stop==100.0,"compression breakout long");

   CMSZZD027StrategyFamilies short_suite; ConfigureOnly(short_suite,4);
   BaseSnapshots(f,m,s,t); m.leg_direction=MSZZ_DIR_SHORT; s.leg_direction=MSZZ_DIR_SHORT;
   for(int i=0;i<3;i++) short_suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_COMPRESSION),Bar(t+i*300,101,109,105),out);
   n=short_suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_BREAKOUT),Bar(t+900,98,106,99),out);
   AssertTrue(n==1 && out[0].direction==MSZZ_DIR_SHORT && out[0].stop==110.0,"compression breakout short");
}

void TestTransitionAndClustering()
{
   datetime t=D'2026.01.02 14:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies suite; ConfigureOnly(suite,5);
   MSZZCandidate out[];
   int n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_TRANSITION),Bar(t,102,112,111),out);
   AssertTrue(n==1 && out[0].strategy_id==MSZZ_STRAT_STRUCTURE_TRANSITION &&
              out[0].family_id==MSZZ_FAMILY_REVERSAL,"confirmed transition");
   n=suite.Evaluate(f,m,s,Regime(MSZZ_PHASE_UNCLASSIFIED),Bar(t+300,102,112,111),out);
   AssertTrue(n==0,"premature transition rejected");

   MSZZCandidate candidates[]; ArrayResize(candidates,2);
   ZeroMemory(candidates[0]); ZeroMemory(candidates[1]);
   candidates[0].valid=true; candidates[0].strategy_id=MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE;
   candidates[0].family_id=MSZZ_FAMILY_BREAKOUT; candidates[0].direction=MSZZ_DIR_LONG;
   candidates[0].origin_type=MSZZ_ORIGIN_FAST_BREAK; candidates[0].origin_id="SHARED";
   candidates[0].event_id="A"; candidates[0].signal_time=t; candidates[0].expiry_time=t+900;
   candidates[0].entry=110; candidates[0].stop=100; candidates[0].score=8;
   candidates[1]=candidates[0]; candidates[1].strategy_id=MSZZ_STRAT_BREAKOUT_RETEST;
   candidates[1].family_id=MSZZ_FAMILY_RETEST; candidates[1].event_id="B"; candidates[1].score=7.5;
   CMSZZOpportunityClusterEngine clusters_engine; MSZZOpportunityCluster clusters[];
   int c=clusters_engine.Build("XAUUSD",PERIOD_M5,candidates,2,clusters);
   AssertTrue(c==1 && clusters[0].support_count==2 &&
              StringFind(clusters[0].supporting_family_ids,"1")>=0 &&
              StringFind(clusters[0].supporting_family_ids,"3")>=0,
              "cross-family clustering preserves family IDs");
}

void TestDefaultOffAndExistingFamilies()
{
   datetime t=D'2026.01.02 15:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZD027StrategyFamilies off;
   MSZZCandidate out[]; int n=off.Evaluate(f,m,s,Regime(MSZZ_PHASE_TRANSITION),Bar(t,98,112,111),out);
   AssertTrue(n==0 && !off.AnyEnabled(),"canonical D027 default off");

   CMSZZStrategySuite existing; existing.ConfigureStrategies(true,false,false,false,false,false,false,false);
   f.bullish_break=true; f.bullish_event_id="FAMILY";
   n=existing.Evaluate(f,m,s,t,111,out);
   AssertTrue(n==1 && out[0].family_id==MSZZ_FAMILY_BREAKOUT,"existing candidate family persisted");
}

void OnStart()
{
   TestPullbacks();
   TestRetestAndRestart();
   TestSweeps();
   TestCompression();
   TestTransitionAndClustering();
   TestDefaultOffAndExistingFamilies();
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
   if(g_failures>0) ExpertRemove();
}
