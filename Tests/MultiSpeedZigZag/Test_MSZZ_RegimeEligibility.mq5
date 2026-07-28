//+------------------------------------------------------------------+
//| Test_MSZZ_RegimeEligibility.mq5                                   |
//| D027: deterministic tests for CMSZZRegimeEligibilityPolicy (Layer |
//| 3). See DECISION_LOG.md D027.                                     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/RegimeEligibilityPolicy.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZRegimeState MakeRegime(const bool valid,const ENUM_MSZZ_ALIGNMENT_STATE align,
                            const ENUM_MSZZ_VOLATILITY_STATE vol,const ENUM_MSZZ_MARKET_PHASE phase,
                            const ENUM_MSZZ_REGIME_DIRECTION dir=MSZZ_REGIME_DIR_BULLISH)
{
   MSZZRegimeState r; ZeroMemory(r);
   r.valid=valid; r.alignment_state=align; r.volatility_state=vol; r.market_phase=phase; r.direction=dir;
   return r;
}

void TestLabelOnlyAlwaysEligibleRegardlessOfGarbageRegime()
{
   MSZZRegimeState bad=MakeRegime(false,MSZZ_ALIGN_MIXED,MSZZ_VOL_CONTRACTING,MSZZ_PHASE_UNCLASSIFIED,MSZZ_REGIME_DIR_NEUTRAL);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_LABEL_ONLY,MSZZ_FAMILY_BREAKOUT,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,bad,reason);
   AssertTrue(ok,"LABEL_ONLY mode is eligible even for an invalid/garbage regime -- it never filters: "+reason);
}

void TestResearchFilterInvalidRegimeRejected()
{
   MSZZRegimeState bad=MakeRegime(false,MSZZ_ALIGN_FULLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_BREAKOUT);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_BREAKOUT,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,bad,reason);
   AssertTrue(!ok,"RESEARCH_FILTER rejects an invalid regime outright: "+reason);
}

void TestBreakoutFamilyEligible()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_FULLY_ALIGNED,MSZZ_VOL_EXPANDING,MSZZ_PHASE_BREAKOUT);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_BREAKOUT,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,r,reason);
   AssertTrue(ok,"breakout family eligible when aligned+expanding vol+BREAKOUT phase: "+reason);
}

void TestBreakoutFamilyIneligibleWrongPhase()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_FULLY_ALIGNED,MSZZ_VOL_EXPANDING,MSZZ_PHASE_RANGE);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_BREAKOUT,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,r,reason);
   AssertTrue(!ok,"breakout family ineligible in RANGE phase even with good alignment/volatility: "+reason);
}

void TestPullbackFamilyEligible()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_PARTIALLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_PULLBACK,MSZZ_REGIME_DIR_BULLISH);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_PULLBACK,MSZZ_STRAT_ALIGNED_FAST_PULLBACK,r,reason);
   AssertTrue(ok,"pullback family eligible with a slow direction, aligned/correcting, PULLBACK phase: "+reason);
}

void TestPullbackFamilyIneligibleNeutralDirection()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_PARTIALLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_PULLBACK,MSZZ_REGIME_DIR_NEUTRAL);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_PULLBACK,MSZZ_STRAT_ALIGNED_FAST_PULLBACK,r,reason);
   AssertTrue(!ok,"pullback family requires a non-neutral slow direction: "+reason);
}

void TestRetestFamilyEligible()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_FULLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_TREND_CONTINUATION);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_RETEST,MSZZ_STRAT_BREAKOUT_RETEST,r,reason);
   AssertTrue(ok,"retest family eligible when phase=TREND_CONTINUATION: "+reason);
}

void TestSweepReclaimAlwaysIneligibleUntilFailedBreakImplemented()
{
   // Even a maximally favorable-looking regime cannot make sweep/reclaim
   // eligible, because its predeclared hypothesis needs FAILED_BREAK,
   // which the classifier never emits in this pass -- this is an honest
   // limitation, not a bug, and this test locks that behavior in so it
   // can't silently change without a deliberate, documented decision.
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_PARTIALLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_TRANSITION);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_REVERSAL,MSZZ_STRAT_SWEEP_RECLAIM,r,reason);
   AssertTrue(!ok,"sweep/reclaim is always ineligible under RESEARCH_FILTER until FAILED_BREAK is implemented: "+reason);
}

void TestStructureTransitionEligible()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_PARTIALLY_ALIGNED,MSZZ_VOL_NORMAL,MSZZ_PHASE_TRANSITION);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_REVERSAL,MSZZ_STRAT_STRUCTURE_TRANSITION,r,reason);
   AssertTrue(ok,"structure-transition eligible when phase=TRANSITION and not OPPOSED: "+reason);
}

void TestStructureTransitionIneligibleWhenOpposed()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_OPPOSED,MSZZ_VOL_NORMAL,MSZZ_PHASE_TRANSITION);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_REVERSAL,MSZZ_STRAT_STRUCTURE_TRANSITION,r,reason);
   AssertTrue(!ok,"structure-transition ineligible when alignment is OPPOSED even in TRANSITION phase: "+reason);
}

void TestCompressionFamilyEligible()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_MIXED,MSZZ_VOL_CONTRACTING,MSZZ_PHASE_COMPRESSION);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_COMPRESSION,MSZZ_STRAT_COMPRESSION_BREAKOUT,r,reason);
   AssertTrue(ok,"compression family eligible when volatility contracting and phase=COMPRESSION: "+reason);
}

void TestEnsembleFamilyHasNoPredeclaredHypothesis()
{
   MSZZRegimeState r=MakeRegime(true,MSZZ_ALIGN_FULLY_ALIGNED,MSZZ_VOL_EXPANDING,MSZZ_PHASE_BREAKOUT);
   string reason;
   bool ok=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,MSZZ_FAMILY_ENSEMBLE,MSZZ_STRAT_WEIGHTED_ENSEMBLE,r,reason);
   AssertTrue(!ok,"ensemble family has no predeclared RESEARCH_FILTER hypothesis in D027 -- explicitly ineligible, not defaulted to true: "+reason);
}

void OnStart()
{
   TestLabelOnlyAlwaysEligibleRegardlessOfGarbageRegime();
   TestResearchFilterInvalidRegimeRejected();
   TestBreakoutFamilyEligible();
   TestBreakoutFamilyIneligibleWrongPhase();
   TestPullbackFamilyEligible();
   TestPullbackFamilyIneligibleNeutralDirection();
   TestRetestFamilyEligible();
   TestSweepReclaimAlwaysIneligibleUntilFailedBreakImplemented();
   TestStructureTransitionEligible();
   TestStructureTransitionIneligibleWhenOpposed();
   TestCompressionFamilyEligible();
   TestEnsembleFamilyHasNoPredeclaredHypothesis();
   PrintFormat("MSZZ RegimeEligibility test complete failures=%d",g_failures);
}
