//+------------------------------------------------------------------+
//| Test_MSZZ_ExitModelsPhase2.mq5                                    |
//| D024: deterministic causal-correctness tests for the 11 new       |
//| structural/composite Phase 2 exit models (see ExitModelsPhase2.mqh|
//| and DECISION_LOG.md D024). TRAIL_AFTER_1R (model 10) is D021/D022's|
//| already-tested TRAIL_0_5R_AFTER_1R, not retested here.             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ExitModelsPhase2.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void AssertNear(const double actual,const double expected,const double tol,const string message)
{
   AssertTrue(MathAbs(actual-expected)<=tol,
              StringFormat("%s (actual=%.6f expected=%.6f)",message,actual,expected));
}

void BlankState(MSZZSpeedBarState &s)
{
   s.leg_direction=MSZZ_DIR_NONE; s.bullish_break=false; s.bearish_break=false;
   s.new_high_pivot=false; s.new_low_pivot=false; s.warmed_up=true;
   s.last_high.valid=false; s.last_high.structure_label=MSZZ_STRUCT_UNKNOWN;
   s.last_low.valid=false; s.last_low.structure_label=MSZZ_STRUCT_UNKNOWN;
   s.prior_high.valid=false; s.prior_low.valid=false;
}

void SetLow(MSZZSpeedBarState &s,const double price,const ENUM_MSZZ_STRUCTURE_LABEL label)
{
   s.last_low.valid=true; s.last_low.price=price; s.last_low.structure_label=label;
}

void SetHigh(MSZZSpeedBarState &s,const double price,const ENUM_MSZZ_STRUCTURE_LABEL label)
{
   s.last_high.valid=true; s.last_high.price=price; s.last_high.structure_label=label;
}

//--- Case 1: Chandelier trail ratchets on new highs, never widens on pullback
void TestChandelierNeverWidens()
{
   MSZZExitBar bars[5];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;      bars[0].high=105.0; bars[0].low=104.0; bars[0].close=104.5;
   bars[1].time=t+300;  bars[1].high=110.0; bars[1].low=109.0; bars[1].close=109.5;
   bars[2].time=t+600;  bars[2].high=109.0; bars[2].low=108.5; bars[2].close=108.7; // pullback, stays above the already-ratcheted stop(108) -- should not widen it
   bars[3].time=t+900;  bars[3].high=115.0; bars[3].low=114.0; bars[3].close=114.5;
   bars[4].time=t+1200; bars[4].high=111.0; bars[4].low=104.9; bars[4].close=105.0; // hits ratcheted stop

   MSZZSpeedBarState fast_hist[5], med_hist[5];
   for(int i=0;i<5;i++) { BlankState(fast_hist[i]); BlankState(med_hist[i]); }
   double atr_med[5]={1.0,1.0,1.0,1.0,1.0}; // ATR=1.0 flat for arithmetic simplicity

   MSZZPhase2Params p; p.model=MSZZ_P2_CHANDELIER_TRAIL; p.chandelier_atr_mult=2.0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,5,p,MSZZ_AMBIG_PESSIMISTIC,r);
   // Highest high since entry after bar3 = 115.0 -> chandelier = 115-2*1=113 (executable bar4).
   // Bar4 low=104.9 <113 -> stop hit at 113, not at some wider level from bar1's high(110->108).
   AssertTrue(r.resolved,"chandelier resolves");
   AssertNear(r.exit_price,113.0,0.0001,"chandelier stop reflects the highest ratchet (113), not a wider earlier level");
   AssertTrue(r.number_of_trail_updates>=3,"chandelier ratcheted on multiple new highs (bars 0,1,3), not just once");
}

//--- Case 2: Fast swing trail -- activation bar survives, new stop live next bar only
void TestFastSwingTrailDeferredToNextBar()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;     bars[0].high=105.0; bars[0].low=99.0; bars[0].close=104.0; // survives old stop(90), confirms a fast low at 99
   bars[1].time=t+300; bars[1].high=106.0; bars[1].low=98.5; bars[1].close=105.0; // dips below new stop(99) -- must NOT exit if new stop only active next bar... wait it IS next bar

   MSZZSpeedBarState fast_hist[2], med_hist[2];
   BlankState(fast_hist[0]); BlankState(fast_hist[1]); BlankState(med_hist[0]); BlankState(med_hist[1]);
   SetLow(fast_hist[0],99.0,MSZZ_STRUCT_UNKNOWN); // confirmed low visible as of bar0's close
   SetLow(fast_hist[1],99.0,MSZZ_STRUCT_UNKNOWN);
   double atr_med[2]={0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_FAST_SWING_TRAIL; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   // Bar0: old stop=90 not touched (low=99>90) -> survives -> candidate stop=99 computed, executable bar1 only.
   // Bar1: stop_at_open=99 (now active) -> low=98.5<=99 -> exits at 99.
   AssertTrue(r.resolved,"fast swing trail resolves");
   AssertNear(r.exit_price,99.0,0.0001,"exits at the swing-trail stop once it becomes active on bar1");
   AssertTrue(r.exit_time==bars[1].time,"exit happens on bar1, not bar0 (new stop deferred, not tested against the bar that produced it)");
}

//--- Case 3: HL/LH trail only ratchets on constructively-labeled swings
void TestHlLhFiltersNonConstructiveSwing()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;     bars[0].high=105.0; bars[0].low=95.0; bars[0].close=104.0; // confirms a LOW LOWER LOW (LL) -- not constructive for a long
   bars[1].time=t+300; bars[1].high=106.0; bars[1].low=94.5; bars[1].close=105.0;

   MSZZSpeedBarState med_hist[2], fast_hist[2];
   BlankState(med_hist[0]); BlankState(med_hist[1]); BlankState(fast_hist[0]); BlankState(fast_hist[1]);
   SetLow(med_hist[0],95.0,MSZZ_STRUCT_LL); // LL, not HL
   SetLow(med_hist[1],95.0,MSZZ_STRUCT_LL);
   double atr_med[2]={0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_HL_LH_TRAIL; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   // Original stop stays at 90 (LL is not HL, so no ratchet) -- bar1 low=94.5 does not hit 90 -> no exit.
   AssertTrue(!r.resolved,"HL/LH trail ignores a non-constructive (LL) swing -- stop never ratchets off it, no exit");

   // Now confirm MEDIUM_SWING_TRAIL (model 3, no label filter) WOULD have ratcheted on the same data.
   MSZZPhase2Params p2; p2.model=MSZZ_P2_MEDIUM_SWING_TRAIL; p2.chandelier_atr_mult=0; p2.timeout_seconds=0;
   MSZZExitResult r2;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p2,MSZZ_AMBIG_PESSIMISTIC,r2);
   AssertTrue(r2.resolved && r2.exit_price==95.0,"model 3 (no label filter) DOES ratchet to the same LL swing and exits at 95 -- confirms models 3 and 4 are genuinely distinct");
}

//--- Case 4: opposite-Fast-structure exit fires exactly on bearish_break for a long
void TestOppositeFastStructureExit()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;     bars[0].high=101.0; bars[0].low=99.5; bars[0].close=100.5; // no break yet
   bars[1].time=t+300; bars[1].high=100.8; bars[1].low=99.0; bars[1].close=99.2;  // bearish_break fires here

   MSZZSpeedBarState fast_hist[2], med_hist[2];
   BlankState(fast_hist[0]); BlankState(fast_hist[1]); BlankState(med_hist[0]); BlankState(med_hist[1]);
   fast_hist[1].bearish_break=true;
   double atr_med[2]={0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_OPPOSITE_FAST_EXIT; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="OPPOSITE_STRUCTURE","exits on the bar where bearish_break fires, reason OPPOSITE_STRUCTURE");
   AssertTrue(r.exit_time==bars[1].time,"fires exactly on bar1 (where the break is flagged), not bar0");
   AssertNear(r.exit_price,99.2,0.0001,"exits at that bar's close");
}

//--- Case 5: opposite-Fast-structure exit does NOT fire without the break flag
void TestOppositeFastStructureExitDoesNotFireSpuriously()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;     bars[0].high=101.0; bars[0].low=99.5; bars[0].close=100.5;
   bars[1].time=t+300; bars[1].high=100.8; bars[1].low=99.0; bars[1].close=99.2;

   MSZZSpeedBarState fast_hist[2], med_hist[2];
   BlankState(fast_hist[0]); BlankState(fast_hist[1]); BlankState(med_hist[0]); BlankState(med_hist[1]);
   double atr_med[2]={0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_OPPOSITE_FAST_EXIT; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(!r.resolved,"no exit fires when bearish_break is never flagged");
}

//--- Case 6: fixed 2R plus stale-trade timeout -- timeout wins when neither stop nor target hit
void TestFixed2RPlusTimeout()
{
   MSZZExitBar bars[3];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;         bars[0].high=101.0; bars[0].low=99.5;  bars[0].close=100.5;
   bars[1].time=t+3600*10; bars[1].high=102.0; bars[1].low=101.0; bars[1].close=101.5;
   bars[2].time=t+3600*25; bars[2].high=103.0; bars[2].low=102.0; bars[2].close=102.5; // past 24h timeout

   MSZZSpeedBarState fast_hist[3], med_hist[3];
   for(int i=0;i<3;i++){ BlankState(fast_hist[i]); BlankState(med_hist[i]); }
   double atr_med[3]={0,0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_FIXED_2R_PLUS_TIMEOUT; p.chandelier_atr_mult=0; p.timeout_seconds=86400;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,3,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TIMEOUT","exits via TIMEOUT when 2R target (120) and stop(90) are never reached");
   AssertTrue(r.exit_time==bars[2].time,"timeout fires on the first bar at/after entry_time+24h");
}

//--- Case 7: breakeven-at-1R-plus-structural-trail -- arms at 1R, then ratchets further via medium swings
void TestBe1RPlusTrailArmsThenRatchets()
{
   MSZZExitBar bars[3];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;     bars[0].high=111.0; bars[0].low=105.0; bars[0].close=110.0; // reaches +1R (110), survives old stop(90)
   bars[1].time=t+300; bars[1].high=112.0; bars[1].low=104.0; bars[1].close=111.0; // dips to 104: below entry(100)? No, 104>100, survives breakeven(100)
   bars[2].time=t+600; bars[2].high=113.0; bars[2].low=101.5; bars[2].close=112.0; // above ratcheted medium-swing stop(102) if armed

   MSZZSpeedBarState fast_hist[3], med_hist[3];
   for(int i=0;i<3;i++){ BlankState(fast_hist[i]); BlankState(med_hist[i]); }
   SetLow(med_hist[1],102.0,MSZZ_STRUCT_UNKNOWN); // a medium swing confirms above breakeven on bar1
   SetLow(med_hist[2],102.0,MSZZ_STRUCT_UNKNOWN);
   double atr_med[3]={0,0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_BE_1R_PLUS_TRAIL; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,3,p,MSZZ_AMBIG_PESSIMISTIC,r);
   // Bar0: fav_r=+1.1R (>=1R) -> arms breakeven, candidate=100, executable bar1.
   // Bar1: stop_at_open=100 (armed) -- low=104>100, survives. Medium swing(102) improves on 100 -> candidate=102, executable bar2.
   // Bar2: stop_at_open=102 -- low=101.5<=102 -> exits at 102.
   AssertTrue(r.resolved,"resolves");
   AssertNear(r.exit_price,102.0,0.0001,"exits at the medium-swing-ratcheted stop (102), beyond plain breakeven (100)");
   AssertTrue(r.exit_time==bars[2].time,"exit happens on bar2 once the ratcheted stop is active, not earlier");
}

//--- Case 8: session-overnight exit fires exactly once at the Asian-session transition
void TestSessionOvernightFiresAtAsianTransition()
{
   MSZZExitBar bars[3];
   bars[0].time=D'2026.01.01 22:00:00'; bars[0].high=101.0; bars[0].low=99.5; bars[0].close=100.5; // NewYork
   bars[1].time=D'2026.01.01 23:55:00'; bars[1].high=101.2; bars[1].low=99.6; bars[1].close=100.6; // still NewYork (hour 23)
   bars[2].time=D'2026.01.02 00:00:00'; bars[2].high=101.5; bars[2].low=99.8; bars[2].close=100.8; // transition into Asian (hour 0)

   MSZZSpeedBarState fast_hist[3], med_hist[3];
   for(int i=0;i<3;i++){ BlankState(fast_hist[i]); BlankState(med_hist[i]); }
   double atr_med[3]={0,0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_SESSION_OVERNIGHT; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,bars[0].time,bars,fast_hist,med_hist,atr_med,3,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="SESSION_OVERNIGHT","exits with SESSION_OVERNIGHT reason");
   AssertTrue(r.exit_time==bars[2].time,"fires exactly at the bar transitioning into the Asian bucket (hour 0), not at bar0 or bar1 (both NewYork)");
}

//--- Case 9: sequencing ambiguity flagged correctly for a structural trail (mirrors D022's rule)
void TestStructuralTrailSequencingAmbiguity()
{
   MSZZExitBar bars[1];
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=105.0; bars[0].low=101.5; bars[0].close=104.0;
   // Old stop=90 not touched (low=101.5>90) -- survives. Medium swing confirms at 102 (a valid
   // improvement over 90), and this SAME bar's low (101.5) would also have hit that proposed stop.
   MSZZSpeedBarState fast_hist[1], med_hist[1];
   BlankState(fast_hist[0]); BlankState(med_hist[0]);
   SetLow(med_hist[0],102.0,MSZZ_STRUCT_UNKNOWN);
   double atr_med[1]={0};

   MSZZPhase2Params p; p.model=MSZZ_P2_MEDIUM_SWING_TRAIL; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,bars[0].time,bars,fast_hist,med_hist,atr_med,1,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(!r.resolved,"pessimistic defers the new stop to the next bar -- no exit yet despite same-bar touch");
   AssertTrue(r.sequencing_ambiguous,"sequencing_ambiguous flagged");
   AssertNear(r.alt_bound_exit_price,102.0,0.0001,"alternate bound records the proposed new stop level");
}

//--- Case 10: no-lookahead -- truncating bars after the decision point doesn't change the resolved exit
void TestNoLookahead()
{
   MSZZExitBar bars_full[4];
   datetime t=D'2026.01.01 00:05:00';
   bars_full[0].time=t;      bars_full[0].high=101.0; bars_full[0].low=99.5;  bars_full[0].close=100.5;
   bars_full[1].time=t+300;  bars_full[1].high=125.0; bars_full[1].low=124.0; bars_full[1].close=124.5; // hits 2R target(120)
   bars_full[2].time=t+600;  bars_full[2].high=150.0; bars_full[2].low=140.0; bars_full[2].close=145.0;
   bars_full[3].time=t+900;  bars_full[3].high=160.0; bars_full[3].low=150.0; bars_full[3].close=155.0;

   MSZZExitBar bars_trunc[2]; bars_trunc[0]=bars_full[0]; bars_trunc[1]=bars_full[1];

   MSZZSpeedBarState fast_hist[4], med_hist[4];
   for(int i=0;i<4;i++){ BlankState(fast_hist[i]); BlankState(med_hist[i]); }
   double atr_med[4]={0,0,0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_FIXED_2R_PLUS_TIMEOUT; p.chandelier_atr_mult=0; p.timeout_seconds=86400;
   MSZZExitResult r_full, r_trunc;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars_full,fast_hist,med_hist,atr_med,4,p,MSZZ_AMBIG_PESSIMISTIC,r_full);
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars_trunc,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r_trunc);
   AssertTrue(r_full.resolved && r_trunc.resolved,"both resolve");
   AssertTrue(r_full.exit_time==r_trunc.exit_time && MathAbs(r_full.exit_price-r_trunc.exit_price)<0.0001,
              "truncating bars AFTER the decision point does not change the already-resolved exit");
}

//--- Case 11 (regression): a stale swing on the WRONG side of current
//    price (e.g. an old "last_low" left over from before a sustained
//    decline, now sitting ABOVE current price) must never be accepted
//    as a trail candidate -- found empirically when a real replay run
//    produced impossible >100R "profits" from exactly this pattern.
void TestSwingTrailRejectsStaleWrongSideSwing()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   // Long entry at 100. Price has actually been falling: bar0 closes at 95.
   bars[0].time=t;     bars[0].high=101.0; bars[0].low=94.0; bars[0].close=95.0;
   bars[1].time=t+300; bars[1].high=96.0;  bars[1].low=93.0; bars[1].close=94.0;

   MSZZSpeedBarState fast_hist[2], med_hist[2];
   BlankState(fast_hist[0]); BlankState(fast_hist[1]); BlankState(med_hist[0]); BlankState(med_hist[1]);
   // Stale "last_low" from before the decline -- ABOVE current price (95).
   SetLow(med_hist[0],103.0,MSZZ_STRUCT_UNKNOWN);
   SetLow(med_hist[1],103.0,MSZZ_STRUCT_UNKNOWN);
   double atr_med[2]={0,0};

   MSZZPhase2Params p; p.model=MSZZ_P2_MEDIUM_SWING_TRAIL; p.chandelier_atr_mult=0; p.timeout_seconds=0;
   MSZZExitResult r;
   CMSZZPhase2ExitPolicy::SimulatePhase2Exit(1,100.0,90.0,10.0,120.0,t,bars,fast_hist,med_hist,atr_med,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   // Old stop (90) is never touched (lows stay 94/93, both above 90) --
   // the stale 103 swing must be rejected, so the position must NOT
   // exit at any point in this 2-bar window.
   AssertTrue(!r.resolved,"a stale swing above current price is rejected -- no nonsensical stop-out or fake profit");
}

void OnStart()
{
   TestChandelierNeverWidens();
   TestFastSwingTrailDeferredToNextBar();
   TestHlLhFiltersNonConstructiveSwing();
   TestOppositeFastStructureExit();
   TestOppositeFastStructureExitDoesNotFireSpuriously();
   TestFixed2RPlusTimeout();
   TestBe1RPlusTrailArmsThenRatchets();
   TestSessionOvernightFiresAtAsianTransition();
   TestStructuralTrailSequencingAmbiguity();
   TestNoLookahead();
   TestSwingTrailRejectsStaleWrongSideSwing();
   PrintFormat("MSZZ Phase2 exit models test complete failures=%d",g_failures);
}
