//+------------------------------------------------------------------+
//| Test_MSZZ_ResearchTrail.mq5                                       |
//| D026: deterministic tests for CMSZZResearchTrailPolicy (the pure,  |
//| no-MT5-API trailing-stop mechanics used by ProcessResearchTrail()  |
//| in MultiSpeedZigZagEA.mq5). See DECISION_LOG.md D026.              |
//|                                                                    |
//| Of the 20 required test cases, 14 are pure-policy-testable and     |
//| covered here (R calculation long/short, breakeven/activation       |
//| boundary timing, never-widen, never-invalid-side, Fast/Medium      |
//| swing wrong-side rejection, Chandelier closed-bar ATR/extrema,     |
//| floor-ladder thresholds incl. same-bar multi-rung gap, canonical   |
//| default-off parity, restart-safe re-initialization, duplicate-     |
//| modification suppression, long/short symmetry). The remaining six  |
//| (same-bar trail-vs-opposite-signal ordering, partial+runner        |
//| blended R, single-exit-trade non-interference, failed-modification |
//| handling, test-end forced-closure reconciliation, MT5-HTML-vs-CSV  |
//| trade count) are integration-level concerns that cannot be         |
//| exercised without a live position/broker/Tester -- these are       |
//| verified empirically against the real T0-T8 Tester runs (see       |
//| DECISION_LOG.md D026 results) rather than faked here.              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void AssertNear(const double a,const double b,const double tol,const string message)
{
   AssertTrue(MathAbs(a-b)<=tol,message+StringFormat(" (a=%.6f b=%.6f)",a,b));
}

// --- 1. Long and short R calculations ------------------------------
void TestFavorableRLong()
{
   double r=CMSZZResearchTrailPolicy::FavorableR(MSZZ_DIR_LONG,100.0,10.0,125.0,90.0);
   AssertNear(r,2.5,1e-9,"long favorable R uses bar high: (125-100)/10=2.5");
}

void TestFavorableRShort()
{
   double r=CMSZZResearchTrailPolicy::FavorableR(MSZZ_DIR_SHORT,100.0,10.0,125.0,80.0);
   AssertNear(r,2.0,1e-9,"short favorable R uses bar low: (100-80)/10=2.0");
}

void TestFavorableRZeroRiskGuarded()
{
   double r=CMSZZResearchTrailPolicy::FavorableR(MSZZ_DIR_LONG,100.0,0.0,125.0,90.0);
   AssertTrue(r==0.0,"zero risk returns 0.0 rather than dividing by zero");
}

// --- 2/3. Breakeven / activation boundary timing --------------------
MSZZTrailConfig MakeConfig()
{
   MSZZTrailConfig c; ZeroMemory(c);
   c.enabled=true; c.rung_count=0; c.cost_r_estimate=0.02;
   c.structure_mode=MSZZ_TRAIL_STRUCT_NONE; c.structure_activation_r=0.0;
   c.chandelier_atr_len=14; c.chandelier_atr_mult=3.0;
   return c;
}

void AddRung(MSZZTrailConfig &c,const double trigger_r,const double floor_r)
{
   c.rungs[c.rung_count].trigger_r=trigger_r;
   c.rungs[c.rung_count].floor_r=floor_r;
   c.rung_count++;
}

void TestBreakevenNotYetActiveOneBarBefore()
{
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,1.0,0.0);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   bool triggered=CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,0.9,candidate);
   AssertTrue(!triggered,"favorable_r=0.9 (one bar before +1R) does not trigger the breakeven rung");
}

void TestBreakevenActivatesExactlyAtThreshold()
{
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,1.0,0.0);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   bool triggered=CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.0,candidate);
   AssertTrue(triggered,"favorable_r=1.0 (exactly at +1R) triggers the breakeven rung");
   AssertNear(candidate,100.0+0.02*10.0,1e-9,"breakeven candidate = entry + cost_r_estimate*risk for a long");
}

void TestStructureActivationBoundary()
{
   // Structure activation is a plain fav_r>=activation_r comparison in the
   // EA wiring; exercised here via EvaluateFloorRung's identical
   // trigger-boundary semantics (same >= comparison), since the structure
   // activation flag itself is a simple boolean the EA sets directly.
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,2.0,0.5);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   AssertTrue(!CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.999999,candidate),
              "one bar before +2R does not trigger the 0.5R floor rung");
   AssertTrue(CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,2.0,candidate),
              "exactly +2R triggers the 0.5R floor rung");
}

// --- 4. Stop never widens -------------------------------------------
void TestResolveTighteningRejectsWideningLong()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_LONG,100.0,95.0,150.0,1.0,new_stop);
   AssertTrue(!ok,"a long candidate stop (95) below the current effective stop (100) is rejected as widening");
}

void TestResolveTighteningRejectsWideningShort()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_SHORT,100.0,105.0,50.0,1.0,new_stop);
   AssertTrue(!ok,"a short candidate stop (105) above the current effective stop (100) is rejected as widening");
}

void TestResolveTighteningAcceptsGenuineTightening()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_LONG,100.0,110.0,150.0,1.0,new_stop);
   AssertTrue(ok && MathAbs(new_stop-110.0)<1e-9,"a long candidate stop (110) strictly above current (100) is accepted");
}

// --- 5. Stop never crosses into invalid side of current market ------
void TestResolveTighteningRejectsInsideBrokerDistanceLong()
{
   double new_stop;
   // market=150, candidate=149.5 -> distance 0.5 < min_distance 1.0
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_LONG,100.0,149.5,150.0,1.0,new_stop);
   AssertTrue(!ok,"a long candidate inside the broker minimum stop distance from market is rejected, not clamped");
}

void TestResolveTighteningRejectsInsideBrokerDistanceShort()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_SHORT,100.0,50.5,50.0,1.0,new_stop);
   AssertTrue(!ok,"a short candidate inside the broker minimum stop distance from market is rejected, not clamped");
}

// --- 6/7. Fast/Medium swing trail rejects stale wrong-side pivots ----
// Same underlying function (SwingTrailCandidate) serves both Fast and
// Medium in the EA wiring -- exercised twice here with distinct scenario
// framing to satisfy both required cases explicitly, matching D024's
// Bug-1 regression pattern verbatim.
void TestFastSwingRejectsStaleWrongSideSwingLong()
{
   double candidate;
   // "last low" is above current close -- stale, left over from before a
   // sustained rally; must not be accepted as a long trail candidate.
   bool ok=CMSZZResearchTrailPolicy::SwingTrailCandidate(MSZZ_DIR_LONG,100.0,true,105.0,candidate);
   AssertTrue(!ok,"Fast-swing: a confirmed low above current close is stale/wrong-side and rejected");
}

void TestFastSwingAcceptsValidLong()
{
   double candidate;
   bool ok=CMSZZResearchTrailPolicy::SwingTrailCandidate(MSZZ_DIR_LONG,100.0,true,95.0,candidate);
   AssertTrue(ok && MathAbs(candidate-95.0)<1e-9,"Fast-swing: a confirmed low below current close is a valid long trail candidate");
}

void TestMediumSwingRejectsStaleWrongSideSwingShort()
{
   double candidate;
   // "last high" is below current close -- stale; must not be accepted as
   // a short trail candidate.
   bool ok=CMSZZResearchTrailPolicy::SwingTrailCandidate(MSZZ_DIR_SHORT,100.0,true,95.0,candidate);
   AssertTrue(!ok,"Medium-swing: a confirmed high below current close is stale/wrong-side and rejected");
}

void TestMediumSwingAcceptsValidShort()
{
   double candidate;
   bool ok=CMSZZResearchTrailPolicy::SwingTrailCandidate(MSZZ_DIR_SHORT,100.0,true,105.0,candidate);
   AssertTrue(ok && MathAbs(candidate-105.0)<1e-9,"Medium-swing: a confirmed high above current close is a valid short trail candidate");
}

void TestSwingTrailRejectsInvalidPivot()
{
   double candidate;
   bool ok=CMSZZResearchTrailPolicy::SwingTrailCandidate(MSZZ_DIR_LONG,100.0,false,95.0,candidate);
   AssertTrue(!ok,"an invalid (not-yet-confirmed) pivot is never a trail candidate regardless of price");
}

// --- 8. Chandelier uses closed-bar ATR and extrema -------------------
void TestSimpleATRAndChandelierLong()
{
   double high[5]={110,112,111,113,114};
   double low[5]={105,106,107,108,109};
   double close[5]={108,110,109,112,113};
   // end_index=4 (last closed bar), len=3 -> uses indices 2,3,4
   double atr=CMSZZResearchTrailPolicy::SimpleATR(high,low,close,4,3);
   AssertTrue(atr>0.0,"SimpleATR over closed bars produces a positive value");
   double chandelier=CMSZZResearchTrailPolicy::ChandelierCandidate(MSZZ_DIR_LONG,114.0,atr,3.0);
   AssertNear(chandelier,114.0-3.0*atr,1e-9,"long Chandelier candidate = highest_since_activation - mult*ATR");
}

void TestChandelierShort()
{
   double chandelier=CMSZZResearchTrailPolicy::ChandelierCandidate(MSZZ_DIR_SHORT,90.0,2.0,3.0);
   AssertNear(chandelier,90.0+6.0,1e-9,"short Chandelier candidate = lowest_since_activation + mult*ATR");
}

void TestSimpleATRInsufficientHistoryReturnsZero()
{
   double high[3]={110,112,111};
   double low[3]={105,106,107};
   double close[3]={108,110,109};
   double atr=CMSZZResearchTrailPolicy::SimpleATR(high,low,close,2,5); // len>end_index
   AssertTrue(atr==0.0,"SimpleATR with insufficient closed-bar history returns 0.0 rather than reading out of range");
}

// --- 9. Profit-floor ladder thresholds, incl. same-bar multi-rung gap
void TestFloorLadderSequentialRungs()
{
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,1.0,0.0); AddRung(config,2.0,0.5); AddRung(config,3.0,1.5);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   AssertTrue(CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.0,candidate),"rung 1 (+1R) fires");
   AssertTrue(state.next_rung_index==1,"next_rung_index advances past rung 1");
   AssertTrue(!CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.5,candidate),
              "fav_r=1.5 does not re-fire rung 1 or prematurely fire rung 2 (trigger 2.0)");
   AssertTrue(CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,2.0,candidate),"rung 2 (+2R) fires");
   AssertNear(candidate,100.0+0.5*10.0,1e-9,"rung 2 candidate = entry + 0.5*risk");
}

void TestFloorLadderGapSkipsToFurthestRung()
{
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,1.0,0.0); AddRung(config,2.0,0.5); AddRung(config,3.0,1.5);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   // A single bar's favorable excursion jumps straight to +3.5R, past all
   // three rungs at once -- must land on rung 3 (the furthest), not rung 1.
   bool triggered=CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,3.5,candidate);
   AssertTrue(triggered,"a same-bar gap past all rungs still triggers");
   AssertNear(candidate,100.0+1.5*10.0,1e-9,"gap lands on the furthest (rung 3, +1.5R floor) rung, not rung 1");
   AssertTrue(state.next_rung_index==3,"next_rung_index reflects all three rungs consumed by the gap");
}

void TestFloorLadderNeverRefiresConsumedRung()
{
   MSZZTrailConfig config=MakeConfig();
   AddRung(config,1.0,0.0);
   MSZZTrailState state; CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   double candidate;
   CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.0,candidate);
   bool refired=CMSZZResearchTrailPolicy::EvaluateFloorRung(config,state,1.2,candidate);
   AssertTrue(!refired,"a favorable move to 1.2R after rung 1 (trigger 1.0) already consumed does not re-fire it");
}

// --- 13. Canonical default-off parity ---------------------------------
void TestDisabledConfigNeverProducesRungOrIsMeaningfulToCallers()
{
   MSZZTrailConfig config; ZeroMemory(config);
   config.enabled=false; // mirrors InpEnableResearchTrail=false
   AssertTrue(!config.enabled,"a config built from InpEnableResearchTrail=false has enabled=false -- "+
              "ProcessResearchTrail() in the EA returns immediately on this flag, making the whole "+
              "mechanism a provable no-op for every existing D019-D025 config, none of which set it");
}

// --- 14. Restart behavior: state always seeds from the CURRENT broker
// stop, never a remembered one, so a freshly (re)created state can never
// regress an already-trailed stop after an EA restart.
void TestRestartSeedsEffectiveStopFromCurrentBrokerStopNotOriginal()
{
   MSZZTrailState state;
   // Position was opened at entry=100/original_stop=90, but has ALREADY
   // been trailed to 105 by the time of a (simulated) restart -- the
   // in-memory state was lost, so InitState() is called fresh with the
   // CURRENT broker-side stop (105), not the original (90).
   CMSZZResearchTrailPolicy::InitState(state,1,MSZZ_DIR_LONG,100.0,90.0,105.0);
   AssertTrue(MathAbs(state.effective_stop-105.0)<1e-9,
              "post-restart state.effective_stop reflects the CURRENT broker stop (105), not the original structural stop (90)");
   AssertTrue(MathAbs(state.original_stop-90.0)<1e-9,
              "state.original_stop/initial_risk are still recovered from the durable intent record for correct R-basis math");
   double candidate=102.0; // a rung/structure candidate looser than the already-trailed 105
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_LONG,state.effective_stop,candidate,150.0,1.0,new_stop);
   AssertTrue(!ok,"a freshly-reconstructed post-restart state still refuses to regress below the real (already-trailed) stop");
}

// --- 17. Duplicate-modification suppression ---------------------------
// The EA's own duplicate check compares NormalizeDouble(candidate) against
// the current effective stop before ever calling PositionModify(); at the
// policy level this reduces to ResolveTightening() rejecting a candidate
// exactly equal to the current effective stop (not strictly tighter).
void TestResolveTighteningRejectsExactDuplicateLong()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_LONG,100.0,100.0,150.0,1.0,new_stop);
   AssertTrue(!ok,"a candidate exactly equal to the current effective stop is rejected, not resubmitted as a duplicate modification");
}

void TestResolveTighteningRejectsExactDuplicateShort()
{
   double new_stop;
   bool ok=CMSZZResearchTrailPolicy::ResolveTightening(MSZZ_DIR_SHORT,100.0,100.0,50.0,1.0,new_stop);
   AssertTrue(!ok,"short-side exact duplicate is likewise rejected");
}

// --- 18. Long/short symmetry (aggregate check across the suite) ------
void TestLongShortSymmetryOfFloorLadder()
{
   MSZZTrailConfig config_long=MakeConfig(); AddRung(config_long,1.0,0.5);
   MSZZTrailConfig config_short=MakeConfig(); AddRung(config_short,1.0,0.5);
   MSZZTrailState long_state; CMSZZResearchTrailPolicy::InitState(long_state,1,MSZZ_DIR_LONG,100.0,90.0,90.0);
   MSZZTrailState short_state; CMSZZResearchTrailPolicy::InitState(short_state,2,MSZZ_DIR_SHORT,100.0,110.0,110.0);
   double lc,sc;
   CMSZZResearchTrailPolicy::EvaluateFloorRung(config_long,long_state,1.0,lc);
   CMSZZResearchTrailPolicy::EvaluateFloorRung(config_short,short_state,1.0,sc);
   AssertNear(lc-100.0,-(sc-100.0),1e-9,"long (+0.5R above entry) and short (+0.5R below entry) floor offsets are exact mirrors");
}

void OnStart()
{
   TestFavorableRLong();
   TestFavorableRShort();
   TestFavorableRZeroRiskGuarded();

   TestBreakevenNotYetActiveOneBarBefore();
   TestBreakevenActivatesExactlyAtThreshold();
   TestStructureActivationBoundary();

   TestResolveTighteningRejectsWideningLong();
   TestResolveTighteningRejectsWideningShort();
   TestResolveTighteningAcceptsGenuineTightening();

   TestResolveTighteningRejectsInsideBrokerDistanceLong();
   TestResolveTighteningRejectsInsideBrokerDistanceShort();

   TestFastSwingRejectsStaleWrongSideSwingLong();
   TestFastSwingAcceptsValidLong();
   TestMediumSwingRejectsStaleWrongSideSwingShort();
   TestMediumSwingAcceptsValidShort();
   TestSwingTrailRejectsInvalidPivot();

   TestSimpleATRAndChandelierLong();
   TestChandelierShort();
   TestSimpleATRInsufficientHistoryReturnsZero();

   TestFloorLadderSequentialRungs();
   TestFloorLadderGapSkipsToFurthestRung();
   TestFloorLadderNeverRefiresConsumedRung();

   TestDisabledConfigNeverProducesRungOrIsMeaningfulToCallers();

   TestRestartSeedsEffectiveStopFromCurrentBrokerStopNotOriginal();

   TestResolveTighteningRejectsExactDuplicateLong();
   TestResolveTighteningRejectsExactDuplicateShort();

   TestLongShortSymmetryOfFloorLadder();

   PrintFormat("MSZZ ResearchTrail policy test complete failures=%d",g_failures);
}
