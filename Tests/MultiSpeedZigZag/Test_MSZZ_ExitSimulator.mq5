//+------------------------------------------------------------------+
//| Test_MSZZ_ExitSimulator.mq5                                       |
//| Covers DECISION_LOG.md D021/D022 requirements (deterministic     |
//| core). E2E cases (identical/differing counts across replay modes, |
//| deterministic rerun hash, portfolio occupancy) are verified       |
//| against the actual three-strategy run instead -- see              |
//| BACKTEST_LOG.md D021/D022 entries.                                 |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ExitSimulatorPolicy.mqh>

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

void BuildLongBars(MSZZExitBar &bars[],const int count,const double base_high,const double base_low,
                    const double step,const datetime start_time,const int period_seconds)
{
   ArrayResize(bars,count);
   for(int i=0;i<count;i++)
   {
      bars[i].time=start_time+i*period_seconds;
      bars[i].high=base_high+i*step;
      bars[i].low=base_low+i*step;
      bars[i].close=(bars[i].high+bars[i].low)/2.0;
   }
}

MSZZExitParams MakeFixedParams(const double r_multiple)
{
   MSZZExitParams p; ZeroMemory(p);
   p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=r_multiple;
   return p;
}

MSZZExitParams MakeBeParams(const double trigger_r)
{
   MSZZExitParams p; ZeroMemory(p);
   p.model=MSZZ_EXIT_BE_1R; p.be_trigger_r=trigger_r; p.be_offset_price=0.0;
   return p;
}

MSZZExitParams MakeTrailParams(const double trigger_r,const double distance_r)
{
   MSZZExitParams p; ZeroMemory(p);
   p.model=MSZZ_EXIT_TRAIL_0_5R_AFTER_1R; p.trail_trigger_r=trigger_r; p.trail_distance_r=distance_r;
   return p;
}

//--- Case 1: target hit first (clean uptrend, long) -------------------
void TestTargetHitFirstLong()
{
   MSZZExitBar bars[];
   BuildLongBars(bars,10,101.0,100.0,1.0,D'2026.01.01 00:05:00',300);
   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars[0].time,bars,10,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TP","target hit first resolves as TP");
   AssertNear(r.exit_price,104.0,0.0001,"exit price equals target");
}

//--- Case 2: stop hit first (clean downtrend, long) -------------------
void TestStopHitFirstLong()
{
   MSZZExitBar bars[];
   BuildLongBars(bars,10,99.0,98.0,-1.0,D'2026.01.01 00:05:00',300);
   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars[0].time,bars,10,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="SL","stop hit first resolves as SL");
   AssertNear(r.exit_price,98.0,0.0001,"exit price equals stop");
}

//--- Case 3: same-bar stop/target ambiguity, pessimistic vs optimistic -
void TestSameBarAmbiguity()
{
   MSZZExitBar bars[1];
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=105.0; bars[0].low=97.0; bars[0].close=101.0;
   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r_pess, r_opt;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r_pess);
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars[0].time,bars,1,p,MSZZ_AMBIG_OPTIMISTIC,r_opt);
   AssertTrue(r_pess.ambiguous_bar_used,"pessimistic flags the ambiguous bar");
   AssertTrue(r_pess.exit_reason=="SL","pessimistic resolves adverse (SL) first");
   AssertTrue(r_opt.exit_reason=="TP","optimistic resolves favorable (TP) first");
}

//--- Case 4 (D022): old stop touched BEFORE any same-bar favorable move
//    can activate breakeven -- long side. A bar whose low hits the
//    ORIGINAL stop must exit there even if that same bar's high would
//    have reached the BE trigger -- the position doesn't survive to see
//    the favorable move "count".
void TestOldStopTouchedBeforeBeActivationLong()
{
   MSZZExitBar bars[1];
   // entry=100, risk=2, stop=98, BE trigger=+1R (price 102). This bar's
   // high (103) clears the BE trigger, but its low (97.5) also breaches
   // the ORIGINAL stop (98) -- pessimistic must exit at the original
   // stop, not at breakeven.
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=103.0; bars[0].low=97.5; bars[0].close=99.0;
   MSZZExitParams p=MakeBeParams(1.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved,"resolves");
   AssertNear(r.exit_price,98.0,0.0001,"exits at the ORIGINAL stop, not breakeven, despite same-bar BE trigger");
   AssertTrue(r.exit_reason=="SL","exit reason is a plain SL, not BE_TRAIL -- breakeven never activated");
}

//--- Case 5 (D022): short mirror of case 4 --------------------------
void TestOldStopTouchedBeforeBeActivationShort()
{
   MSZZExitBar bars[1];
   // entry=100, risk=2, stop=102 (short). BE trigger +1R = price 98.
   // This bar's low (97) clears the trigger, but its high (102.5) also
   // breaches the original stop -- pessimistic must exit at 102.
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=102.5; bars[0].low=97.0; bars[0].close=100.0;
   MSZZExitParams p=MakeBeParams(1.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(-1,100.0,102.0,2.0,90.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved,"resolves");
   AssertNear(r.exit_price,102.0,0.0001,"short mirror: exits at the ORIGINAL stop, not breakeven");
   AssertTrue(r.exit_reason=="SL","short mirror: plain SL, breakeven never activated");
}

//--- Case 6 (D022): a bar survives against the old stop and correctly
//    arms/ratchets; the new stop is only live starting the NEXT bar.
void TestActivationBarSurvivesNewStopNextBarOnly()
{
   MSZZExitBar bars[2];
   datetime t=D'2026.01.01 00:05:00';
   // Bar 0: reaches +1R (high=102), low stays safely above the ORIGINAL
   // stop (98) -- survives, arms breakeven (new stop=100).
   bars[0].time=t;     bars[0].high=102.0; bars[0].low=99.0; bars[0].close=101.0;
   // Bar 1: dips to 99.5 -- ABOVE the new breakeven stop (100)? No,
   // 99.5<100 would hit it. Use 100.5 so bar 1 does NOT hit the new
   // stop yet, proving it only becomes relevant (and here, not even
   // touched) starting bar 1, not retroactively on bar 0.
   bars[1].time=t+300; bars[1].high=101.5; bars[1].low=100.5; bars[1].close=101.0;
   MSZZExitParams p=MakeBeParams(1.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,2,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(!r.resolved,"neither bar triggers an exit -- new stop correctly deferred to bar 1, not tested on bar 0");
}

//--- Case 7 (D022): same-bar high reaches the trail trigger AND the low
//    crosses the proposed new (not-yet-active) stop -- must flag
//    sequencing_ambiguous and report the alternate bound, while the
//    primary pessimistic result still defers to the next bar.
void TestSequencingAmbiguousTrailSameBar()
{
   MSZZExitBar bars[1];
   // entry=100, risk=2. Trail arms at +1R (102), trails 0.5R (=1.0)
   // behind the high -- proposed new stop from this bar's high (103) is
   // 102. This bar's low (101.5) is ABOVE the ORIGINAL stop (98, so no
   // exit there) but BELOW the proposed new stop (102) -- classic
   // same-bar sequencing ambiguity.
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=103.0; bars[0].low=101.5; bars[0].close=102.0;
   MSZZExitParams p=MakeTrailParams(1.0,0.5);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(!r.resolved,"primary pessimistic result defers the new stop to the next bar (no exit yet)");
   AssertTrue(r.sequencing_ambiguous,"sequencing_ambiguous is flagged");
   AssertNear(r.alt_bound_exit_price,102.0,0.0001,"alternate bound records the proposed new stop level");
}

//--- Case 8 (D022): old stop NOT hit, but the proposed new stop alone
//    would have been -- must NOT exit this bar in pessimistic mode
//    (same scenario as case 7, phrased as its own explicit requirement).
void TestOldStopSurvivesNewStopWouldHaveHit()
{
   MSZZExitBar bars[1];
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=103.0; bars[0].low=101.5; bars[0].close=102.0;
   MSZZExitParams p=MakeTrailParams(1.0,0.5);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(!r.resolved,"old stop (98) not touched by this bar's low (101.5) -- position survives, no exit");
}

//--- Case 9 (D022): pessimistic and optimistic produce genuinely
//    different outcomes on an identical ambiguous BE/trail bar.
void TestPessimisticOptimisticDivergeOnBeBar()
{
   MSZZExitBar bars[1];
   // Same bar as cases 7/8. Optimistic: favorable-first means the trail
   // arms/ratchets to 102 THEN the same bar's low (101.5) is checked
   // against that new stop -- 101.5<=102, so optimistic DOES exit this
   // bar (at 102), while pessimistic defers to the next bar entirely.
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=103.0; bars[0].low=101.5; bars[0].close=102.0;
   MSZZExitParams p=MakeTrailParams(1.0,0.5);
   MSZZExitResult r_pess, r_opt;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r_pess);
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,1,p,MSZZ_AMBIG_OPTIMISTIC,r_opt);
   AssertTrue(!r_pess.resolved,"pessimistic: no exit this bar (deferred)");
   AssertTrue(r_opt.resolved && r_opt.exit_reason=="BE_TRAIL","optimistic: resolves this bar via the newly-armed trail stop");
   AssertNear(r_opt.exit_price,102.0,0.0001,"optimistic exits at the freshly-ratcheted stop level");
}

//--- Case 10 (D022): time exit anchored to entry_time, not bars[0].time,
//    when entry_time does not fall exactly on a bar boundary.
void TestTimeExitAnchoredToEntryTime()
{
   MSZZExitBar bars[4];
   datetime bar_start=D'2026.01.01 00:10:00'; // first POST-entry bar
   int period=300;
   for(int i=0;i<4;i++)
   {
      bars[i].time=bar_start+i*period; bars[i].high=100.5; bars[i].low=99.5; bars[i].close=100.0;
   }
   // entry_time is 6 minutes BEFORE bars[0].time (a mid-bar entry, as
   // could happen with non-M5-aligned data). A 900s (15 min) time limit
   // anchored to entry_time fires at entry_time+900 = bar_start+540,
   // whose first covering bar is bars[2] (bar_start+600). Anchored to
   // bars[0].time instead (the old, wrong behavior) it would fire at
   // bar_start+900, whose first covering bar is bars[3] -- the two
   // anchors must disagree by a full bar for this test to actually
   // distinguish them.
   datetime entry_time=bar_start-(datetime)360;
   MSZZExitParams p; ZeroMemory(p);
   p.model=MSZZ_EXIT_TIME_4H; p.time_limit_seconds=900;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,entry_time,bars,4,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TIME","resolves via time exit");
   AssertTrue(r.exit_time==bars[2].time,
              "boundary computed from entry_time (not bars[0].time) lands on the correct earlier bar");
}

//--- Case 11 (D022): MFE-until-exit excludes price movement AFTER the
//    resolved exit; the shared reference-horizon MFE (computed
//    separately by ComputeMfeMae over the full path) includes it.
void TestMfeUntilExitExcludesPostExitMovement()
{
   MSZZExitBar bars[4];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;      bars[0].high=101.0; bars[0].low=100.0; bars[0].close=100.5;
   bars[1].time=t+300;  bars[1].high=104.5; bars[1].low=103.0; bars[1].close=104.0; // TP hit here (target=104)
   bars[2].time=t+600;  bars[2].high=150.0; bars[2].low=140.0; bars[2].close=145.0; // huge post-exit move
   bars[3].time=t+900;  bars[3].high=160.0; bars[3].low=150.0; bars[3].close=155.0;

   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars[0].time,bars,4,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TP","resolves at target on bar 1");
   AssertTrue(r.mfe_until_exit_r<10.0,"MFE-until-exit does not include the huge post-exit move on bars 2-3");

   double ref_mfe_r,ref_mae_r; int bars_to_mfe; datetime time_to_mfe;
   CMSZZExitSimulatorPolicy::ComputeMfeMae(100.0,2.0,1,bars,4,ref_mfe_r,ref_mae_r,bars_to_mfe,time_to_mfe);
   AssertTrue(ref_mfe_r>10.0,"reference-horizon MFE (full path) DOES include the post-exit move -- the two metrics genuinely differ");
}

//--- Case 12: commission/swap arithmetic base (RMultiple exactness) ---
void TestCommissionSwapArithmeticBase()
{
   double gross_r=CMSZZExitSimulatorPolicy::RMultiple(104.0,100.0,2.0,1);
   AssertNear(gross_r,2.0,0.0001,"RMultiple exact for a clean 2R move (base for cost-adjusted net_r)");
}

//--- Case 13: no forming-bar / no future lookahead ---------------------
void TestNoFutureLookahead()
{
   MSZZExitBar bars_full[6];
   datetime t=D'2026.01.01 00:05:00';
   bars_full[0].time=t;      bars_full[0].high=100.5; bars_full[0].low=99.5;  bars_full[0].close=100.0;
   bars_full[1].time=t+300;  bars_full[1].high=100.5; bars_full[1].low=99.5;  bars_full[1].close=100.0;
   bars_full[2].time=t+600;  bars_full[2].high=100.5; bars_full[2].low=99.5;  bars_full[2].close=100.0;
   bars_full[3].time=t+900;  bars_full[3].high=105.0; bars_full[3].low=104.0; bars_full[3].close=104.5;
   bars_full[4].time=t+1200; bars_full[4].high=90.0;  bars_full[4].low=80.0;  bars_full[4].close=85.0;
   bars_full[5].time=t+1500; bars_full[5].high=80.0;  bars_full[5].low=70.0;  bars_full[5].close=75.0;

   MSZZExitBar bars_truncated[4];
   for(int i=0;i<4;i++) bars_truncated[i]=bars_full[i];

   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r_full, r_trunc;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars_full[0].time,bars_full,6,p,MSZZ_AMBIG_PESSIMISTIC,r_full);
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars_truncated[0].time,bars_truncated,4,p,MSZZ_AMBIG_PESSIMISTIC,r_trunc);

   AssertTrue(r_full.resolved && r_trunc.resolved,"both full and truncated arrays resolve");
   AssertTrue(r_full.exit_time==r_trunc.exit_time && MathAbs(r_full.exit_price-r_trunc.exit_price)<0.0001,
              "truncating bars AFTER the decision point does not change the already-resolved exit (no lookahead)");
}

//--- Case 14: trail never widens across a longer, unambiguous path ----
void TestTrailNeverWidens()
{
   MSZZExitBar bars[6];
   datetime t=D'2026.01.01 00:05:00';
   bars[0].time=t;      bars[0].high=102.0; bars[0].low=101.5; bars[0].close=101.8;
   bars[1].time=t+300;  bars[1].high=104.0; bars[1].low=103.5; bars[1].close=103.8;
   bars[2].time=t+600;  bars[2].high=103.5; bars[2].low=103.2; bars[2].close=103.3;
   bars[3].time=t+900;  bars[3].high=106.0; bars[3].low=105.2; bars[3].close=105.5;
   bars[4].time=t+1200; bars[4].high=105.0; bars[4].low=104.0; bars[4].close=104.5;
   bars[5].time=t+1500; bars[5].high=103.0; bars[5].low=102.0; bars[5].close=102.5;
   MSZZExitParams p=MakeTrailParams(1.0,0.5);
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,6,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved,"trail resolves");
   AssertNear(r.exit_price,105.0,0.0001,"trail stop ratcheted to 105 (106 high - 1.0) before being hit on bar 4");
   AssertTrue(r.number_of_trail_updates>=3,"trail updated on multiple new highs, not just once");
}

//--- Case 15: long/short symmetry (mirrored synthetic paths) -----------
void TestLongShortSymmetry()
{
   MSZZExitBar long_bars[2];
   datetime t=D'2026.01.01 00:05:00';
   long_bars[0].time=t;     long_bars[0].high=101.0; long_bars[0].low=100.0; long_bars[0].close=100.5;
   long_bars[1].time=t+300; long_bars[1].high=104.5; long_bars[1].low=103.0; long_bars[1].close=104.0;

   MSZZExitBar short_bars[2];
   short_bars[0].time=t;     short_bars[0].high=100.0; short_bars[0].low=99.0;  short_bars[0].close=99.5;
   short_bars[1].time=t+300; short_bars[1].high=97.0;  short_bars[1].low=95.5;  short_bars[1].close=96.0;

   MSZZExitParams p=MakeFixedParams(2.0);
   MSZZExitResult r_long, r_short;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,long_bars[0].time,long_bars,2,p,MSZZ_AMBIG_PESSIMISTIC,r_long);
   CMSZZExitSimulatorPolicy::SimulateExit(-1,100.0,102.0,2.0,96.0,short_bars[0].time,short_bars,2,p,MSZZ_AMBIG_PESSIMISTIC,r_short);

   double r_long_result=CMSZZExitSimulatorPolicy::RMultiple(r_long.exit_price,100.0,2.0,1);
   double r_short_result=CMSZZExitSimulatorPolicy::RMultiple(r_short.exit_price,100.0,2.0,-1);
   AssertTrue(r_long.exit_reason=="TP" && r_short.exit_reason=="TP","mirrored long/short paths both resolve as TP");
   AssertNear(r_long_result,r_short_result,0.0001,"mirrored long/short paths produce identical R-magnitude results");
}

//--- Case 16: session-close boundary ------------------------------------
void TestSessionCloseBoundary()
{
   MSZZExitBar bars[3];
   datetime t=D'2026.01.01 07:50:00';
   bars[0].time=t;      bars[0].high=100.5; bars[0].low=99.5; bars[0].close=100.0;
   bars[1].time=t+300;  bars[1].high=100.5; bars[1].low=99.5; bars[1].close=100.2;
   bars[2].time=t+600;  bars[2].high=100.5; bars[2].low=99.5; bars[2].close=100.4;
   MSZZExitParams p; ZeroMemory(p);
   p.model=MSZZ_EXIT_SESSION_CLOSE; p.session_boundary=D'2026.01.01 08:00:00';
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars[0].time,bars,3,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="SESSION_CLOSE","resolves via session close");
   AssertTrue(r.exit_time==bars[2].time,"exits at the first bar at/after the session boundary, not before");
}

void OnStart()
{
   TestTargetHitFirstLong();
   TestStopHitFirstLong();
   TestSameBarAmbiguity();
   TestOldStopTouchedBeforeBeActivationLong();
   TestOldStopTouchedBeforeBeActivationShort();
   TestActivationBarSurvivesNewStopNextBarOnly();
   TestSequencingAmbiguousTrailSameBar();
   TestOldStopSurvivesNewStopWouldHaveHit();
   TestPessimisticOptimisticDivergeOnBeBar();
   TestTimeExitAnchoredToEntryTime();
   TestMfeUntilExitExcludesPostExitMovement();
   TestCommissionSwapArithmeticBase();
   TestNoFutureLookahead();
   TestTrailNeverWidens();
   TestLongShortSymmetry();
   TestSessionCloseBoundary();

   PrintFormat("MSZZ exit simulator test complete failures=%d",g_failures);
}
