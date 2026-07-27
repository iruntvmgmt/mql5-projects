//+------------------------------------------------------------------+
//| Test_MSZZ_ExitSimulator.mq5                                       |
//| Covers DECISION_LOG.md D021 requirements (deterministic core).   |
//| E2E cases (14, 15, and the signal/portfolio-level distinctions)   |
//| are verified against the actual three-strategy run instead --    |
//| see BACKTEST_LOG.md D021 entry.                                   |
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

// Builds a simple synthetic bar path. entry=100, risk=2 (stop=98 for long).
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

//--- Case 1: target hit first (clean uptrend, long) -------------------
void TestTargetHitFirstLong()
{
   MSZZExitBar bars[];
   BuildLongBars(bars,10,101.0,100.0,1.0,D'2026.01.01 00:05:00',300);
   // entry=100, risk=2, stop=98, target=104 (FIXED_2R). Bars climb by 1
   // each step: bar0 high=101, bar3 high=104 -> target hit at bar3.
   MSZZExitParams p; p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=2.0;
   p.be_trigger_r=0; p.be_offset_price=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars,10,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TP","target hit first resolves as TP");
   AssertNear(r.exit_price,104.0,0.0001,"exit price equals target");
}

//--- Case 2: stop hit first (clean downtrend, long) -------------------
void TestStopHitFirstLong()
{
   MSZZExitBar bars[];
   BuildLongBars(bars,10,99.0,98.0,-1.0,D'2026.01.01 00:05:00',300);
   // entry=100, risk=2, stop=98: bar0 low=98 -> stop hit immediately.
   MSZZExitParams p; p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=2.0;
   p.be_trigger_r=0; p.be_offset_price=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars,10,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="SL","stop hit first resolves as SL");
   AssertNear(r.exit_price,98.0,0.0001,"exit price equals stop");
}

//--- Case 3: same-bar ambiguity, pessimistic vs optimistic diverge ----
void TestSameBarAmbiguity()
{
   MSZZExitBar bars[1];
   bars[0].time=D'2026.01.01 00:05:00'; bars[0].high=105.0; bars[0].low=97.0; bars[0].close=101.0;
   // entry=100, risk=2, stop=98, target=104 -- both in [97,105] range.
   MSZZExitParams p; p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=2.0;
   p.be_trigger_r=0; p.be_offset_price=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;
   MSZZExitResult r_pess, r_opt;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars,1,p,MSZZ_AMBIG_PESSIMISTIC,r_pess);
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars,1,p,MSZZ_AMBIG_OPTIMISTIC,r_opt);
   AssertTrue(r_pess.ambiguous_bar_used && r_opt.ambiguous_bar_used,"both modes flag the ambiguous bar");
   AssertTrue(r_pess.exit_reason=="SL","pessimistic resolves adverse (SL) first");
   AssertTrue(r_opt.exit_reason=="TP","optimistic resolves favorable (TP) first");
}

//--- Case 4: breakeven activation then reversal -----------------------
void TestBreakevenActivationThenReversal()
{
   MSZZExitBar bars[6];
   datetime t=D'2026.01.01 00:05:00';
   // Rally to +1R (entry=100,risk=2 -> price 102) then reverse back
   // through entry. BE_1R should move stop to 100 once +1R is reached,
   // so the reversal exits at breakeven (100), not a loss.
   bars[0].time=t;      bars[0].high=101.0; bars[0].low=100.5; bars[0].close=101.0;
   bars[1].time=t+300;  bars[1].high=102.5; bars[1].low=101.5; bars[1].close=102.0; // +1R reached (high>=102)
   bars[2].time=t+600;  bars[2].high=102.0; bars[2].low=101.0; bars[2].close=101.5;
   bars[3].time=t+900;  bars[3].high=101.0; bars[3].low=100.0; bars[3].close=100.5; // touches BE stop at 100
   bars[4].time=t+1200; bars[4].high=99.0;  bars[4].low=98.0;  bars[4].close=98.5;
   bars[5].time=t+1500; bars[5].high=97.0;  bars[5].low=96.0;  bars[5].close=96.5;
   MSZZExitParams p; p.model=MSZZ_EXIT_BE_1R; p.be_trigger_r=1.0; p.be_offset_price=0.0;
   p.fixed_r_multiple=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,106.0,bars,6,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved,"breakeven-then-reversal resolves");
   AssertNear(r.exit_price,100.0,0.0001,"exits at breakeven (entry price), not the original stop");
   AssertTrue(r.exit_reason=="BE_TRAIL","exit reason reflects the moved stop, not a plain SL");
}

//--- Case 5 & 6: trail ratcheting and never-widens --------------------
void TestTrailRatchetingNeverWidens()
{
   MSZZExitBar bars[6];
   datetime t=D'2026.01.01 00:05:00';
   // entry=100, risk=2. Trail arms at +1R (price 102), trails 0.5R (=1.0)
   // behind the running high. Then price dips (should NOT widen the stop
   // back out) then continues higher (stop should ratchet further). Each
   // arming/ratcheting bar's own low is kept safely above that same bar's
   // newly-implied trail level, so the ratchet and the eventual stop-hit
   // are on clearly separate bars (no same-bar ambiguity in this case --
   // that is covered separately by TestSameBarAmbiguity).
   bars[0].time=t;      bars[0].high=102.0; bars[0].low=101.5; bars[0].close=101.8; // arm at 102, stop->101
   bars[1].time=t+300;  bars[1].high=104.0; bars[1].low=103.5; bars[1].close=103.8; // new high 104, stop->103
   bars[2].time=t+600;  bars[2].high=103.5; bars[2].low=103.2; bars[2].close=103.3; // dip, stop must stay 103
   bars[3].time=t+900;  bars[3].high=106.0; bars[3].low=105.2; bars[3].close=105.5; // new high 106, stop->105
   bars[4].time=t+1200; bars[4].high=105.0; bars[4].low=104.0; bars[4].close=104.5; // dip below 105 -> stop hit
   bars[5].time=t+1500; bars[5].high=103.0; bars[5].low=102.0; bars[5].close=102.5;
   MSZZExitParams p; p.model=MSZZ_EXIT_TRAIL_0_5R_AFTER_1R; p.trail_trigger_r=1.0; p.trail_distance_r=0.5;
   p.fixed_r_multiple=0; p.be_trigger_r=0; p.be_offset_price=0;
   p.time_limit_seconds=0; p.session_boundary=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars,6,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved,"trail resolves");
   AssertNear(r.exit_price,105.0,0.0001,"trail stop ratcheted to 105 (106 high - 1.0) before being hit");
   AssertTrue(r.exit_reason=="BE_TRAIL","trail exit reason reflects the moved stop");
   AssertTrue(r.number_of_trail_updates>=3,"trail updated on every new high, not just once");
}

//--- Case 7: time exit exactly on the boundary bar --------------------
void TestTimeExitBoundary()
{
   MSZZExitBar bars[4];
   datetime t=D'2026.01.01 00:05:00';
   int period=300;
   for(int i=0;i<4;i++)
   {
      bars[i].time=t+i*period; bars[i].high=100.5; bars[i].low=99.5; bars[i].close=100.0;
   }
   // 4h = 14400s. bars[0].time + 14400 lands exactly on a later bar; use a
   // small limit (900s = 3 bars) so the boundary bar is bars[3] in this
   // synthetic array (t, t+300, t+600, t+900).
   MSZZExitParams p; p.model=MSZZ_EXIT_TIME_4H; p.time_limit_seconds=900;
   p.fixed_r_multiple=0; p.be_trigger_r=0; p.be_offset_price=0;
   p.trail_trigger_r=0; p.trail_distance_r=0; p.session_boundary=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars,4,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="TIME","resolves via time exit, not stop/target");
   AssertTrue(r.exit_time==bars[3].time,"exits exactly on the boundary bar, not one early or late");
}

//--- Case 8: session-close boundary ------------------------------------
void TestSessionCloseBoundary()
{
   MSZZExitBar bars[3];
   datetime t=D'2026.01.01 07:50:00';
   bars[0].time=t;      bars[0].high=100.5; bars[0].low=99.5; bars[0].close=100.0;
   bars[1].time=t+300;  bars[1].high=100.5; bars[1].low=99.5; bars[1].close=100.2; // 07:55 -- before boundary
   bars[2].time=t+600;  bars[2].high=100.5; bars[2].low=99.5; bars[2].close=100.4; // 08:00 -- at boundary
   MSZZExitParams p; p.model=MSZZ_EXIT_SESSION_CLOSE; p.session_boundary=D'2026.01.01 08:00:00';
   p.fixed_r_multiple=0; p.be_trigger_r=0; p.be_offset_price=0;
   p.trail_trigger_r=0; p.trail_distance_r=0; p.time_limit_seconds=0;
   MSZZExitResult r;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,110.0,bars,3,p,MSZZ_AMBIG_PESSIMISTIC,r);
   AssertTrue(r.resolved && r.exit_reason=="SESSION_CLOSE","resolves via session close");
   AssertTrue(r.exit_time==bars[2].time,"exits at the first bar at/after the session boundary, not before");
}

//--- Case 9: long/short symmetry (mirrored synthetic paths) -----------
void TestLongShortSymmetry()
{
   MSZZExitBar long_bars[5];
   datetime t=D'2026.01.01 00:05:00';
   long_bars[0].time=t;     long_bars[0].high=101.0; long_bars[0].low=100.0; long_bars[0].close=100.5;
   long_bars[1].time=t+300; long_bars[1].high=104.5; long_bars[1].low=103.0; long_bars[1].close=104.0;

   MSZZExitBar short_bars[5];
   short_bars[0].time=t;     short_bars[0].high=100.0; short_bars[0].low=99.0;  short_bars[0].close=99.5;
   short_bars[1].time=t+300; short_bars[1].high=97.0;  short_bars[1].low=95.5;  short_bars[1].close=96.0;

   MSZZExitParams p; p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=2.0;
   p.be_trigger_r=0; p.be_offset_price=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;

   MSZZExitResult r_long, r_short;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,long_bars,2,p,MSZZ_AMBIG_PESSIMISTIC,r_long);
   CMSZZExitSimulatorPolicy::SimulateExit(-1,100.0,102.0,2.0,96.0,short_bars,2,p,MSZZ_AMBIG_PESSIMISTIC,r_short);

   double r_long_result=CMSZZExitSimulatorPolicy::RMultiple(r_long.exit_price,100.0,2.0,1);
   double r_short_result=CMSZZExitSimulatorPolicy::RMultiple(r_short.exit_price,100.0,2.0,-1);
   AssertTrue(r_long.exit_reason=="TP" && r_short.exit_reason=="TP","mirrored long/short paths both resolve as TP");
   AssertNear(r_long_result,r_short_result,0.0001,"mirrored long/short paths produce identical R-magnitude results");
}

//--- Case 10: commission/swap arithmetic on net_r_after_costs ----------
void TestCommissionSwapArithmetic()
{
   // Pure arithmetic check: net_r_after_costs should reduce gross_r by
   // (commission+swap converted to R) -- exercised at the script level
   // (ExitSimulator.mq5) since it requires point-value/contract-size
   // context this policy file deliberately does not depend on. Here we
   // confirm the building block RMultiple() is exact so the script-level
   // cost subtraction has a correct base to work from.
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
   bars_full[3].time=t+900;  bars_full[3].high=105.0; bars_full[3].low=104.0; bars_full[3].close=104.5; // TP here
   bars_full[4].time=t+1200; bars_full[4].high=90.0;  bars_full[4].low=80.0;  bars_full[4].close=85.0;  // future crash
   bars_full[5].time=t+1500; bars_full[5].high=80.0;  bars_full[5].low=70.0;  bars_full[5].close=75.0;

   MSZZExitBar bars_truncated[4];
   for(int i=0;i<4;i++) bars_truncated[i]=bars_full[i];

   MSZZExitParams p; p.model=MSZZ_EXIT_FIXED_2R; p.fixed_r_multiple=2.0;
   p.be_trigger_r=0; p.be_offset_price=0; p.trail_trigger_r=0; p.trail_distance_r=0;
   p.time_limit_seconds=0; p.session_boundary=0;

   MSZZExitResult r_full, r_trunc;
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars_full,6,p,MSZZ_AMBIG_PESSIMISTIC,r_full);
   CMSZZExitSimulatorPolicy::SimulateExit(1,100.0,98.0,2.0,104.0,bars_truncated,4,p,MSZZ_AMBIG_PESSIMISTIC,r_trunc);

   AssertTrue(r_full.resolved && r_trunc.resolved,"both full and truncated arrays resolve");
   AssertTrue(r_full.exit_time==r_trunc.exit_time && MathAbs(r_full.exit_price-r_trunc.exit_price)<0.0001,
              "truncating bars AFTER the decision point does not change the already-resolved exit (no lookahead)");
}

void OnStart()
{
   TestTargetHitFirstLong();
   TestStopHitFirstLong();
   TestSameBarAmbiguity();
   TestBreakevenActivationThenReversal();
   TestTrailRatchetingNeverWidens();
   TestTimeExitBoundary();
   TestSessionCloseBoundary();
   TestLongShortSymmetry();
   TestCommissionSwapArithmetic();
   TestNoFutureLookahead();

   PrintFormat("MSZZ exit simulator test complete failures=%d",g_failures);
}
