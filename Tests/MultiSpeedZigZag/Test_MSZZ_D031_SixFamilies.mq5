#property strict
#property script_show_inputs

// D031: six-family shadow research architecture tests. Same shape and
// helper-function conventions as Test_MSZZ_D027Strategies.mq5 and
// Test_MSZZ_CandidateHandoff.mq5 (BaseSnapshots/Pivot/Regime/Bar fixture
// builders, AssertTrue/g_tests/g_failures counters, OnStart() driver).
//
// COMPILE/RUN STATUS: this file was written and manually cross-checked
// against every Evaluate()/Emit() signature it calls (field-by-field,
// against Include/MultiSpeedZigZag/Research/Families/*.mqh as actually
// written), but could NOT be compiled or executed in this session --
// MetaEditor's compile bridge did not produce a compiler-log update
// across four attempts in a row, including against a previously-known-
// -good file (Test_MSZZ_CandidateHandoff.mq5), so this is an environment
// issue, not evidence of a code defect. See
// Docs/MultiSpeedZigZag/D031_SIX_FAMILY_ARCHITECTURE.md "Known
// limitations". Run this file before D032 begins.

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>
#include <MultiSpeedZigZag/Research/Families/SessionSweepReversal.mqh>
#include <MultiSpeedZigZag/Research/Families/MomentumContinuation.mqh>
#include <MultiSpeedZigZag/Research/Families/BreakRetestContinuation.mqh>
#include <MultiSpeedZigZag/Research/Families/CompressionBreakoutResearch.mqh>
#include <MultiSpeedZigZag/Research/Families/TrendPullback.mqh>
#include <MultiSpeedZigZag/Research/Families/RangeRotation.mqh>
#include <MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh>

int g_tests=0,g_failures=0;
void AssertTrue(const bool condition,const string name)
{
   g_tests++;
   if(!condition){ g_failures++; Print("FAIL: ",name); }
   else Print("PASS: ",name);
}

// ------------------------------------------------------------------ fixtures

MSZZPivot Pivot(const ENUM_MSZZ_PIVOT_KIND kind,const ENUM_MSZZ_STRUCTURE_LABEL label,
                const double price,const string id,const datetime t)
{
   MSZZPivot p; ZeroMemory(p); p.valid=true; p.kind=kind; p.structure_label=label;
   p.price=price; p.id=id; p.pivot_time=t-300; p.confirmed_time=t; return p;
}

void BaseSnapshots(MSZZSpeedSnapshot &f,MSZZSpeedSnapshot &m,MSZZSpeedSnapshot &s,const datetime t,const double atr=10.0)
{
   ZeroMemory(f); ZeroMemory(m); ZeroMemory(s);
   f.speed=MSZZ_SPEED_FAST; m.speed=MSZZ_SPEED_MEDIUM; s.speed=MSZZ_SPEED_SLOW;
   f.atr=atr; m.atr=atr*2.0; s.atr=atr*3.5;
}

MSZZRegimeState Regime(const double efficiency,const double fast_swing_amp_r,const double normalized_atr,const bool valid=true)
{
   MSZZRegimeState r; ZeroMemory(r); r.valid=valid;
   r.evaluation_time=D'2026.01.02 10:00';
   r.directional_efficiency=efficiency; r.fast_swing_amplitude_r=fast_swing_amp_r; r.normalized_atr=normalized_atr;
   r.trend_strength=MSZZ_TREND_NORMAL; r.volatility_state=MSZZ_VOL_NORMAL;
   r.alignment_state=MSZZ_ALIGN_FULLY_ALIGNED; r.market_phase=MSZZ_PHASE_UNCLASSIFIED;
   return r;
}

MqlRates Bar(const datetime t,const double low,const double high,const double close,const double open=0.0,const int spread=10)
{
   MqlRates b; ZeroMemory(b);
   b.time=t; b.low=low; b.high=high; b.close=close; b.open=(open>0.0 ? open : close);
   b.tick_volume=100; b.spread=spread; return b;
}

// ------------------------------------------------------------------ shared architecture tests

void TestIdAllocation()
{
   // Cross-checked directly against Include/MultiSpeedZigZag/Core/Types.mqh's
   // ENUM_MSZZ_STRATEGY_ID (1001-1080) and ENUM_MSZZ_STRATEGY_FAMILY (0-7) --
   // see Tools/D031/id_allocation.csv for the full inspection.
   int strat_ids[]={MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL,MSZZ_RSRCH_STRAT_MOMENTUM_CONTINUATION,
                    MSZZ_RSRCH_STRAT_BREAK_RETEST_CONTINUATION,MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT,
                    MSZZ_RSRCH_STRAT_TREND_PULLBACK,MSZZ_RSRCH_STRAT_RANGE_ROTATION};
   int family_ids[]={MSZZ_RSRCH_FAMILY_SESSION_SWEEP_REVERSAL,MSZZ_RSRCH_FAMILY_MOMENTUM_CONTINUATION,
                     MSZZ_RSRCH_FAMILY_BREAK_RETEST_CONTINUATION,MSZZ_RSRCH_FAMILY_COMPRESSION_BREAKOUT,
                     MSZZ_RSRCH_FAMILY_TREND_PULLBACK,MSZZ_RSRCH_FAMILY_RANGE_ROTATION};
   int existing_strat[]={1001,1002,1003,1010,1011,1012,1020,1030,1031,1040,1050,1060,1070,1080};
   int existing_family[]={0,1,2,3,4,5,6,7};

   bool strat_unique=true,family_unique=true,strat_no_collision=true,family_no_collision=true;
   for(int i=0;i<ArraySize(strat_ids);i++)
   {
      for(int j=i+1;j<ArraySize(strat_ids);j++) if(strat_ids[i]==strat_ids[j]) strat_unique=false;
      for(int j=0;j<ArraySize(existing_strat);j++) if(strat_ids[i]==existing_strat[j]) strat_no_collision=false;
   }
   for(int i=0;i<ArraySize(family_ids);i++)
   {
      for(int j=i+1;j<ArraySize(family_ids);j++) if(family_ids[i]==family_ids[j]) family_unique=false;
      for(int j=0;j<ArraySize(existing_family);j++) if(family_ids[i]==existing_family[j]) family_no_collision=false;
   }
   AssertTrue(strat_unique,"all six D031 strategy IDs unique");
   AssertTrue(family_unique,"all six D031 family IDs unique");
   AssertTrue(strat_no_collision,"D031 strategy IDs do not collide with existing 1001-1080");
   AssertTrue(family_no_collision,"D031 family IDs do not collide with existing 0-7");
}

void TestFactoryRejectsInvalidGeometry()
{
   // The ONE shared choke point every family routes through -- covers
   // "invalid stop"/"invalid target"/boundary-condition geometry checks
   // for all six families at once, rather than repeating per family.
   MSZZResearchCandidate out[]; int count;

   count=0; ArrayResize(out,0);
   bool r1=CMSZZResearchCandidateFactory::Emit(out,count,1200,8,MSZZ_DIR_LONG,D'2026.01.02 10:00',
              D'2026.01.02 10:15',100.0,100.0,2.0,7.0,"X","O","E","R","V","REG","SESS","REF","CTX",10,0.01);
   AssertTrue(!r1 && count==0,"factory rejects entry==stop");

   count=0; ArrayResize(out,0);
   bool r2=CMSZZResearchCandidateFactory::Emit(out,count,1200,8,MSZZ_DIR_LONG,D'2026.01.02 10:00',
              D'2026.01.02 10:15',100.0,105.0,2.0,7.0,"X","O","E","R","V","REG","SESS","REF","CTX",10,0.01);
   AssertTrue(!r2 && count==0,"factory rejects LONG stop on wrong side of entry");

   count=0; ArrayResize(out,0);
   bool r3=CMSZZResearchCandidateFactory::Emit(out,count,1200,8,MSZZ_DIR_SHORT,D'2026.01.02 10:00',
              D'2026.01.02 10:15',100.0,95.0,2.0,7.0,"X","O","E","R","V","REG","SESS","REF","CTX",10,0.01);
   AssertTrue(!r3 && count==0,"factory rejects SHORT stop on wrong side of entry");

   count=0; ArrayResize(out,0);
   bool r4=CMSZZResearchCandidateFactory::Emit(out,count,1200,8,MSZZ_DIR_LONG,D'2026.01.02 10:00',
              D'2026.01.02 10:15',100.0,95.0,2.0,7.0,"X","","E","R","V","REG","SESS","REF","CTX",10,0.01);
   AssertTrue(!r4 && count==0,"factory rejects missing origin_id");

   count=0; ArrayResize(out,0);
   bool r5=CMSZZResearchCandidateFactory::Emit(out,count,1200,8,MSZZ_DIR_LONG,D'2026.01.02 10:00',
              D'2026.01.02 10:15',100.0,95.0,2.0,7.0,"X","O","E","R","V","REG","SESS","REF","CTX",10,0.01);
   AssertTrue(r5 && count==1 && out[0].valid && out[0].target==110.0 && out[0].target_r==2.0 &&
              out[0].stop_distance_points==500.0 && out[0].hypothesis_version==MSZZ_RSRCH_HYPOTHESIS_VERSION,
              "factory computes target/target_r/stop_distance_points/hypothesis_version correctly on valid geometry");

   // "no mutation after emission": out[0] is a value-type copy: re-emitting
   // a second, DIFFERENT candidate into the same array must not alter the
   // first one already captured.
   MSZZResearchCandidate first_copy=out[0];
   CMSZZResearchCandidateFactory::Emit(out,count,1201,9,MSZZ_DIR_SHORT,D'2026.01.02 10:05',
              D'2026.01.02 10:20',200.0,210.0,2.0,7.0,"Y","O2","E2","R2","V2","REG2","SESS2","REF2","CTX2",10,0.01);
   AssertTrue(out[0].entry==first_copy.entry && out[0].stop==first_copy.stop && out[0].origin_id==first_copy.origin_id,
              "no mutation after emission: earlier candidate unchanged by a later Emit()");
}

// ------------------------------------------------------------------ Momentum Continuation

void TestMomentumContinuation()
{
   datetime t=D'2026.02.02 09:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZFamilyMomentumContinuation mc; mc.Configure(300);
   MSZZResearchCandidate out[];

   // canonical long: arm on bar1 (displacement + efficiency + alignment),
   // pause bar2 (shallow retracement, no trigger), trigger bar3 (close
   // beyond pause extreme).
   f.bullish_break=true; f.bullish_event_id="MC-L1"; f.leg_direction=MSZZ_DIR_LONG; m.leg_direction=MSZZ_DIR_LONG;
   f.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,100.0,"MCFL",t); f.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,110.0,"MCFH",t);
   int n1=mc.Evaluate(f,m,s,Regime(0.8,2.0,0.5),Bar(t,100,110,109),"R1","S1",0.01,out);
   AssertTrue(n1==0,"momentum continuation: no candidate on the arming bar itself");

   f.bullish_break=false;
   int n2=mc.Evaluate(f,m,s,Regime(0.8,2.0,0.5),Bar(t+300,108,109,109),"R2","S2",0.01,out);
   AssertTrue(n2==0,"momentum continuation: pause bar (no breach of pause extreme) emits nothing");

   int n3=mc.Evaluate(f,m,s,Regime(0.8,2.0,0.5),Bar(t+600,108,112,111),"R3","S3",0.01,out);
   AssertTrue(n3==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_MOMENTUM_CONTINUATION &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_MOMENTUM_CONTINUATION && out[0].direction==MSZZ_DIR_LONG &&
              out[0].entry==111.0 && out[0].stop<108.0 && out[0].target_r==MSZZ_MC_TARGET_R,
              "momentum continuation: canonical long triggers on close beyond pause extreme");

   // canonical short (mirrored, fresh instance)
   CMSZZFamilyMomentumContinuation mc_s; mc_s.Configure(300);
   MSZZSpeedSnapshot f2,m2,s2; BaseSnapshots(f2,m2,s2,t);
   f2.bearish_break=true; f2.bearish_event_id="MC-S1"; f2.leg_direction=MSZZ_DIR_SHORT; m2.leg_direction=MSZZ_DIR_SHORT;
   f2.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_LL,100.0,"MCFL2",t); f2.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_LH,110.0,"MCFH2",t);
   mc_s.Evaluate(f2,m2,s2,Regime(0.8,2.0,0.5),Bar(t,100,110,101),"R1","S1",0.01,out);
   f2.bearish_break=false;
   mc_s.Evaluate(f2,m2,s2,Regime(0.8,2.0,0.5),Bar(t+300,101,102,101),"R2","S2",0.01,out);
   int n4=mc_s.Evaluate(f2,m2,s2,Regime(0.8,2.0,0.5),Bar(t+600,98,102,99),"R3","S3",0.01,out);
   AssertTrue(n4==1 && out[0].direction==MSZZ_DIR_SHORT && out[0].entry==99.0 && out[0].stop>102.0,
              "momentum continuation: canonical short triggers on close beyond pause extreme");

   // missing prerequisite: identical setup but directional efficiency below
   // the frozen threshold -- must never arm.
   CMSZZFamilyMomentumContinuation mc_weak; mc_weak.Configure(300);
   MSZZSpeedSnapshot f3,m3,s3; BaseSnapshots(f3,m3,s3,t);
   f3.bullish_break=true; f3.bullish_event_id="MC-WEAK"; f3.leg_direction=MSZZ_DIR_LONG; m3.leg_direction=MSZZ_DIR_LONG;
   f3.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,100.0,"WL",t); f3.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,110.0,"WH",t);
   mc_weak.Evaluate(f3,m3,s3,Regime(0.30,2.0,0.5),Bar(t,100,110,109),"R1","S1",0.01,out); // efficiency 0.30 < 0.55
   f3.bullish_break=false;
   int n5=mc_weak.Evaluate(f3,m3,s3,Regime(0.30,2.0,0.5),Bar(t+300,105,115,114),"R2","S2",0.01,out);
   AssertTrue(n5==0,"momentum continuation: low directional efficiency never arms (missing prerequisite)");

   // stale setup: arm, then let the frozen pause window (6 bars) elapse
   // without a qualifying close -- must expire, not linger forever.
   CMSZZFamilyMomentumContinuation mc_exp; mc_exp.Configure(300);
   MSZZSpeedSnapshot f4,m4,s4; BaseSnapshots(f4,m4,s4,t);
   f4.bullish_break=true; f4.bullish_event_id="MC-EXP"; f4.leg_direction=MSZZ_DIR_LONG; m4.leg_direction=MSZZ_DIR_LONG;
   f4.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,100.0,"EL",t); f4.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,110.0,"EH",t);
   mc_exp.Evaluate(f4,m4,s4,Regime(0.8,2.0,0.5),Bar(t,100,110,109),"R1","S1",0.01,out);
   f4.bullish_break=false;
   for(int i=1;i<=7;i++) // 7 bars > MSZZ_MC_PAUSE_MAX_BARS(6) -- never closes beyond 110, so still armed the whole time
      mc_exp.Evaluate(f4,m4,s4,Regime(0.8,2.0,0.5),Bar(t+300*i,108,109,109),"R"+IntegerToString(i),"S",0.01,out);
   // decisive bar: a close well beyond the pause extreme (115) WOULD trigger
   // if the setup were still armed. If it stays silent here, the window
   // truly expired rather than merely "not yet triggered".
   int n_after_expiry=mc_exp.Evaluate(f4,m4,s4,Regime(0.8,2.0,0.5),Bar(t+300*8,108,116,115),"R8","S",0.01,out);
   AssertTrue(n_after_expiry==0,"momentum continuation: stale setup expires after the frozen pause window (decisive post-expiry bar stays silent)");
}

// ------------------------------------------------------------------ Trend Pullback

void TestTrendPullback()
{
   datetime t=D'2026.02.03 09:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZFamilyTrendPullback tp; tp.Configure(300);
   MSZZResearchCandidate out[];

   f.leg_direction=MSZZ_DIR_LONG; m.leg_direction=MSZZ_DIR_LONG;
   f.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,102.0,"TPL",t); f.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,108.0,"TPH",t);
   // bar1: close is the max of the bar's own OHL so VWAP (this bar's own
   // volume-weighted typical price) sits below close -- arms on correct
   // side of value.
   int n1=tp.Evaluate(f,m,s,Regime(0.70,1.0,1.0),Bar(t,100,105,105),"R1","S1",0.01,out);
   AssertTrue(n1==0,"trend pullback: no candidate on the arming bar itself");

   int n2=tp.Evaluate(f,m,s,Regime(0.70,1.0,1.0),Bar(t+300,106,108,107),"R2","S2",0.01,out);
   AssertTrue(n2==0,"trend pullback: pause bar within bounded depth emits nothing");

   int n3=tp.Evaluate(f,m,s,Regime(0.70,1.0,1.0),Bar(t+600,106,110,109),"R3","S3",0.01,out);
   AssertTrue(n3==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_TREND_PULLBACK &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_TREND_PULLBACK && out[0].direction==MSZZ_DIR_LONG &&
              out[0].reference_level_type=="SESSION_VWAP" && out[0].target_r==MSZZ_TP_TARGET_R,
              "trend pullback: canonical long triggers on close beyond pullback micro-structure");

   // missing prerequisite: no confirmed HL pivot on the fast leg -> never arms.
   CMSZZFamilyTrendPullback tp_miss; tp_miss.Configure(300);
   MSZZSpeedSnapshot f2,m2,s2; BaseSnapshots(f2,m2,s2,t);
   f2.leg_direction=MSZZ_DIR_LONG; m2.leg_direction=MSZZ_DIR_LONG;
   f2.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_LL,102.0,"NOHL",t); // LL, not HL
   f2.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,108.0,"TPH2",t);
   tp_miss.Evaluate(f2,m2,s2,Regime(0.70,1.0,1.0),Bar(t,100,105,105),"R1","S1",0.01,out);
   int n4=tp_miss.Evaluate(f2,m2,s2,Regime(0.70,1.0,1.0),Bar(t+300,106,112,111),"R2","S2",0.01,out);
   AssertTrue(n4==0,"trend pullback: missing confirmed HL pivot never arms (missing prerequisite)");
}

// ------------------------------------------------------------------ Session Sweep Reversal

void TestSessionSweepReversal()
{
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,D'2026.02.04 03:00');
   CMSZZFamilySessionSweepReversal ssr; ssr.Configure(300);
   MSZZResearchCandidate out[];

   datetime asian=D'2026.02.04 03:00'; // Asian hour, seeds/freezes the day's level at hour>=8
   datetime freeze=D'2026.02.04 08:00';
   datetime sweep_bar=D'2026.02.04 08:05';
   datetime reclaim_bar=D'2026.02.04 08:10';

   ssr.Evaluate(f,Bar(asian,100,105,102),"R0","Asian",0.01,out);       // seeds asian_low=100, asian_high=105
   int n1=ssr.Evaluate(f,Bar(freeze,101,103,102),"R1","London",0.01,out); // freezes the level (hour==8)
   AssertTrue(n1==0,"session sweep reversal: no candidate on the freeze bar (no sweep yet)");

   int n2=ssr.Evaluate(f,Bar(sweep_bar,95,101,99),"R2","London",0.01,out); // low=95 <= 100-1.5 -> arms long
   AssertTrue(n2==0,"session sweep reversal: no candidate on the sweep bar itself");

   int n3=ssr.Evaluate(f,Bar(reclaim_bar,96,102,101),"R3","London",0.01,out); // close 101 > 100+0.5 -> reclaim
   AssertTrue(n3==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_SESSION_SWEEP_REVERSAL && out[0].direction==MSZZ_DIR_LONG &&
              out[0].reference_level_type=="ASIA_SESSION_HIGH_LOW" && out[0].target_r==MSZZ_SSR_TARGET_R,
              "session sweep reversal: canonical long triggers on closed-bar reclaim of swept Asia low");

   // missing prerequisite: eligible hours but excursion never exceeds the
   // frozen minimum -> never arms.
   CMSZZFamilySessionSweepReversal ssr_miss; ssr_miss.Configure(300);
   MSZZSpeedSnapshot f2; BaseSnapshots(f2,m,s,asian);
   ssr_miss.Evaluate(f2,Bar(asian,100,105,102),"R0","Asian",0.01,out);
   ssr_miss.Evaluate(f2,Bar(freeze,101,103,102),"R1","London",0.01,out);
   int n4=ssr_miss.Evaluate(f2,Bar(sweep_bar,99.0,101,100),"R2","London",0.01,out); // low=99 -- inside min-excursion tolerance
   AssertTrue(n4==0,"session sweep reversal: excursion below frozen minimum never arms (missing prerequisite)");

   // stale setup: arm, then let the 6-bar reclaim window elapse without a
   // qualifying close.
   CMSZZFamilySessionSweepReversal ssr_exp; ssr_exp.Configure(300);
   MSZZSpeedSnapshot f3; BaseSnapshots(f3,m,s,asian);
   ssr_exp.Evaluate(f3,Bar(asian,100,105,102),"R0","Asian",0.01,out);
   ssr_exp.Evaluate(f3,Bar(freeze,101,103,102),"R1","London",0.01,out);
   ssr_exp.Evaluate(f3,Bar(sweep_bar,95,101,99),"R2","London",0.01,out);
   for(int i=1;i<=7;i++) // 7 bars > MSZZ_SSR_RECLAIM_WINDOW_BARS(6), never reclaims, still armed the whole time
      ssr_exp.Evaluate(f3,Bar(sweep_bar+300*i,96,99,98),"R"+IntegerToString(i),"London",0.01,out);
   // decisive bar: a close well above the session level (100) WOULD reclaim
   // if the setup were still armed. Silence here proves real expiry.
   int n_after_expiry=ssr_exp.Evaluate(f3,Bar(sweep_bar+300*8,96,103,102),"R8","London",0.01,out);
   AssertTrue(n_after_expiry==0,"session sweep reversal: stale setup expires after the frozen reclaim window (decisive post-expiry bar stays silent)");
}

// ------------------------------------------------------------------ Break-Retest Continuation

void TestBreakRetestContinuation()
{
   datetime t=D'2026.02.05 09:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZFamilyBreakRetestContinuation brc; brc.Configure(300);
   MSZZResearchCandidate out[];

   m.bullish_break=true; m.bullish_event_id="BRC-L1"; m.resistance_now=110.0;
   int n1=brc.Evaluate(m,Bar(t,104,114,113,105),"R1","S1",0.01,out); // body 8/range10=0.8, close113>=110+2
   AssertTrue(n1==0,"break-retest continuation: no candidate on the break bar itself");

   m.bullish_break=false;
   int n2=brc.Evaluate(m,Bar(t+300,111,113,112),"R2","S2",0.01,out); // bars_since_break=1 < MIN_BARS(2), no touch processed
   AssertTrue(n2==0,"break-retest continuation: retest ignored before the frozen minimum bar count");

   int n3=brc.Evaluate(m,Bar(t+600,109,112,110.5),"R3","S3",0.01,out); // touches the level -> RETEST_ZONE
   AssertTrue(n3==0,"break-retest continuation: touching the level enters the retest zone without triggering");

   int n4=brc.Evaluate(m,Bar(t+900,111,115,114),"R4","S4",0.01,out); // closes through the rejection bar's high (112)
   AssertTrue(n4==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_BREAK_RETEST_CONTINUATION &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_BREAK_RETEST_CONTINUATION && out[0].direction==MSZZ_DIR_LONG &&
              out[0].stop==109.0 && out[0].reference_level_type=="MEDIUM_SWING_HIGH_LOW",
              "break-retest continuation: canonical long triggers on close through rejection-bar high");

   // missing prerequisite: break bar fails the body/range filter (marginal,
   // near one-tick break) -> never arms.
   CMSZZFamilyBreakRetestContinuation brc_miss; brc_miss.Configure(300);
   MSZZSpeedSnapshot m2; BaseSnapshots(f,m2,s,t);
   m2.bullish_break=true; m2.bullish_event_id="BRC-MARGINAL"; m2.resistance_now=110.0;
   int n5=brc_miss.Evaluate(m2,Bar(t,112.4,114,112.5,112.3),"R1","S1",0.01,out); // body 0.2/range1.6 << 0.4
   m2.bullish_break=false;
   int n6=brc_miss.Evaluate(m2,Bar(t+300,111,113,112),"R2","S2",0.01,out);
   AssertTrue(n5==0 && n6==0,"break-retest continuation: marginal break bar (body/range filter) never arms");
}

// ------------------------------------------------------------------ Compression Breakout (Research)

void TestCompressionBreakoutResearch()
{
   datetime t=D'2026.02.06 09:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   m.leg_direction=MSZZ_DIR_LONG;
   CMSZZFamilyCompressionBreakoutResearch cbr; cbr.Configure(300);
   MSZZResearchCandidate out[];

   int n=0;
   // 14 identical tight-range bars: window fills at bar 12 (compressing
   // becomes evaluable), compression_bars reaches the frozen minimum
   // duration (3) at bar 14 -> arms.
   for(int i=1;i<=14;i++)
      n=cbr.Evaluate(f,m,s,Regime(0.5,1.0,0.5),Bar(t+300*i,100,105,102),"R"+IntegerToString(i),"S",0.01,out);
   AssertTrue(n==0,"compression breakout research: no candidate while still armed/compressing");

   int n_break=cbr.Evaluate(f,m,s,Regime(0.5,1.0,0.5),Bar(t+300*15,105,108,107),"R15","S",0.01,out); // close 107 >= 105+1
   AssertTrue(n_break==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_COMPRESSION_BREAKOUT && out[0].direction==MSZZ_DIR_LONG &&
              out[0].stop==100.0 && out[0].reference_level_type=="ROLLING_WINDOW_RANGE",
              "compression breakout research: canonical long triggers on medium-aligned close beyond compression high");

   // missing prerequisite: identical tight range, but the raw ATR ratio
   // never drops below the frozen threshold -> never compresses/arms.
   CMSZZFamilyCompressionBreakoutResearch cbr_miss; cbr_miss.Configure(300);
   MSZZSpeedSnapshot f2,m2,s2; BaseSnapshots(f2,m2,s2,t); m2.leg_direction=MSZZ_DIR_LONG;
   int n_miss=0;
   for(int i=1;i<=14;i++)
      n_miss=cbr_miss.Evaluate(f2,m2,s2,Regime(0.5,1.0,0.95),Bar(t+300*i,100,105,102),"R"+IntegerToString(i),"S",0.01,out); // atr ratio 0.95 > 0.80
   int n_miss2=cbr_miss.Evaluate(f2,m2,s2,Regime(0.5,1.0,0.95),Bar(t+300*15,105,108,107),"R15","S",0.01,out);
   AssertTrue(n_miss==0 && n_miss2==0,"compression breakout research: ATR ratio above threshold never arms (missing prerequisite)");
}

// ------------------------------------------------------------------ Range Rotation

void TestRangeRotation()
{
   datetime t=D'2026.02.07 00:00';
   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   CMSZZFamilyRangeRotation rr; rr.Configure(300);
   MSZZResearchCandidate out[];
   MSZZRegimeState low_eff=Regime(0.20,1.0,0.5); // low directional efficiency, required for a mature range

   int n=0;
   // Alternate touches of the range boundary for 60 bars: window fills at
   // 48, range "age" (stable-width bar count) reaches the frozen minimum
   // (12) at bar 60 -> mature.
   for(int i=1;i<=60;i++)
   {
      datetime bt=t+300*i;
      if(i%2==1) n=rr.Evaluate(f,m,s,low_eff,Bar(bt,105,112,108),"R"+IntegerToString(i),"S",0.01,out); // touches range high
      else       n=rr.Evaluate(f,m,s,low_eff,Bar(bt,100,107,104),"R"+IntegerToString(i),"S",0.01,out); // touches range low
   }
   AssertTrue(n==0,"range rotation: no candidate while the range is still forming/maturing");

   int n_arm=rr.Evaluate(f,m,s,low_eff,Bar(t+300*61,105,113,109),"R61","S",0.01,out); // high 113 in (112,115] -> arms short
   AssertTrue(n_arm==0,"range rotation: no candidate on the arming (slight-excess) bar itself");

   int n_trig=rr.Evaluate(f,m,s,low_eff,Bar(t+300*62,108,113,109),"R62","S",0.01,out); // close 109 < 112 -> reclaimed
   AssertTrue(n_trig==1 && out[0].strategy_id==MSZZ_RSRCH_STRAT_RANGE_ROTATION &&
              out[0].family_id==MSZZ_RSRCH_FAMILY_RANGE_ROTATION && out[0].direction==MSZZ_DIR_SHORT &&
              out[0].reference_level_type=="SELF_DETECTED_ROLLING_RANGE" &&
              MathAbs(out[0].target-106.0)<0.0001, // range midpoint (112+100)/2
              "range rotation: canonical short triggers on failed excess + reclaim, target is range midpoint");

   // missing prerequisite: same alternating range, but directional
   // efficiency stays high throughout -> never rated "mature", never arms.
   CMSZZFamilyRangeRotation rr_miss; rr_miss.Configure(300);
   MSZZSpeedSnapshot f2,m2,s2; BaseSnapshots(f2,m2,s2,t);
   MSZZRegimeState high_eff=Regime(0.90,1.0,0.5);
   int n_miss=0;
   for(int i=1;i<=61;i++)
   {
      datetime bt=t+300*i;
      if(i%2==1) n_miss=rr_miss.Evaluate(f2,m2,s2,high_eff,Bar(bt,105,113,109),"R"+IntegerToString(i),"S",0.01,out);
      else       n_miss=rr_miss.Evaluate(f2,m2,s2,high_eff,Bar(bt,100,107,104),"R"+IntegerToString(i),"S",0.01,out);
   }
   AssertTrue(n_miss==0,"range rotation: high directional efficiency never matures the range (missing prerequisite)");
}

// ------------------------------------------------------------------ determinism / suite-level

void TestDeterminismAndSuiteIsolation()
{
   datetime t=D'2026.02.08 09:00';

   // same input sequence through two fresh suite instances -> identical
   // candidate output (field-by-field), confirming no hidden global state.
   CMSZZSixFamilyResearchSuite suite_a; suite_a.Configure(300,false);
   CMSZZSixFamilyResearchSuite suite_b; suite_b.Configure(300,false);

   MSZZSpeedSnapshot f,m,s; BaseSnapshots(f,m,s,t);
   f.bullish_break=true; f.bullish_event_id="DET1"; f.leg_direction=MSZZ_DIR_LONG; m.leg_direction=MSZZ_DIR_LONG;
   f.last_low=Pivot(MSZZ_PIVOT_LOW,MSZZ_STRUCT_HL,100.0,"DL",t); f.last_high=Pivot(MSZZ_PIVOT_HIGH,MSZZ_STRUCT_HH,110.0,"DH",t);
   MSZZRegimeState regime=Regime(0.8,2.0,0.5);

   MSZZResearchCandidate out_a[],out_b[];
   suite_a.Evaluate(f,m,s,regime,Bar(t,100,110,109),out_a);
   suite_b.Evaluate(f,m,s,regime,Bar(t,100,110,109),out_b);
   f.bullish_break=false;
   suite_a.Evaluate(f,m,s,regime,Bar(t+300,108,109,109),out_a);
   suite_b.Evaluate(f,m,s,regime,Bar(t+300,108,109,109),out_b);
   int na=suite_a.Evaluate(f,m,s,regime,Bar(t+600,108,112,111),out_a);
   int nb=suite_b.Evaluate(f,m,s,regime,Bar(t+600,108,112,111),out_b);

   AssertTrue(na==nb && na>0,"determinism: two fresh suite instances given the same bar sequence emit the same count");
   bool identical=true;
   for(int i=0;i<na;i++)
      if(out_a[i].strategy_id!=out_b[i].strategy_id || out_a[i].entry!=out_b[i].entry ||
         out_a[i].stop!=out_b[i].stop || out_a[i].target!=out_b[i].target || out_a[i].origin_id!=out_b[i].origin_id)
         identical=false;
   AssertTrue(identical,"determinism: same input produces field-identical MSZZResearchCandidate output");
}

void OnStart()
{
   TestIdAllocation();
   TestFactoryRejectsInvalidGeometry();
   TestMomentumContinuation();
   TestTrendPullback();
   TestSessionSweepReversal();
   TestBreakRetestContinuation();
   TestCompressionBreakoutResearch();
   TestRangeRotation();
   TestDeterminismAndSuiteIsolation();
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
   if(g_failures>0) ExpertRemove();
}
