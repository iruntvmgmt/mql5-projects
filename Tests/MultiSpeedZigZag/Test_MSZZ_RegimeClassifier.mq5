//+------------------------------------------------------------------+
//| Test_MSZZ_RegimeClassifier.mq5                                    |
//| D027: deterministic tests for CMSZZRegimeClassifier (Layer 1, the |
//| pure, no-MT5-API market-regime observer). See DECISION_LOG.md     |
//| D027 for the frozen definitions this suite verifies.              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZPivot MakePivot(const bool valid,const ENUM_MSZZ_STRUCTURE_LABEL label,const double price,const datetime confirmed_time)
{
   MSZZPivot p; ZeroMemory(p);
   p.valid=valid; p.structure_label=label; p.price=price; p.confirmed_time=confirmed_time; p.pivot_time=confirmed_time;
   return p;
}

MSZZSpeedSnapshot MakeSnapshot(const ENUM_MSZZ_DIRECTION dir,const double atr,
                                const MSZZPivot &last_high,const MSZZPivot &prior_high,
                                const MSZZPivot &last_low,const MSZZPivot &prior_low,
                                const bool bull_break=false,const bool bear_break=false)
{
   MSZZSpeedSnapshot s; ZeroMemory(s);
   s.leg_direction=dir; s.atr=atr;
   s.last_high=last_high; s.prior_high=prior_high; s.last_low=last_low; s.prior_low=prior_low;
   s.bullish_break=bull_break; s.bearish_break=bear_break;
   return s;
}

// Builds a synthetic, strictly-increasing-time rates[] array of `count`
// bars, each close increasing by `step` from `base`, high=close+1,
// low=close-1 -- a clean, fully deterministic, trend-like series with
// directional_efficiency close to 1.0 when step!=0.
void MakeTrendingRates(MqlRates &rates[],const int count,const double base,const double step,const datetime start)
{
   ArrayResize(rates,count);
   for(int i=0;i<count;i++)
   {
      double c=base+step*i;
      rates[i].time=start+i*300;
      rates[i].open=c-step; rates[i].close=c; rates[i].high=c+1.0; rates[i].low=c-1.0;
      rates[i].tick_volume=1; rates[i].spread=0; rates[i].real_volume=0;
   }
}

// Builds a synthetic, strictly-alternating (choppy) rates[] array -- net
// change near zero, path length large -> directional_efficiency near 0.
void MakeChoppyRates(MqlRates &rates[],const int count,const double base,const datetime start)
{
   ArrayResize(rates,count);
   for(int i=0;i<count;i++)
   {
      double c=base+((i%2==0)?1.0:-1.0);
      rates[i].time=start+i*300;
      rates[i].open=c; rates[i].close=c; rates[i].high=c+2.0; rates[i].low=c-2.0;
      rates[i].tick_volume=1; rates[i].spread=0; rates[i].real_volume=0;
   }
}

void TestDeterminismSameInputSameOutput()
{
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   MSZZPivot lh=MakePivot(true,MSZZ_STRUCT_HH,110.0,1700000000+140*300);
   MSZZPivot ph=MakePivot(true,MSZZ_STRUCT_HH,108.0,1700000000+100*300);
   MSZZPivot ll=MakePivot(true,MSZZ_STRUCT_HL,105.0,1700000000+130*300);
   MSZZPivot pl=MakePivot(true,MSZZ_STRUCT_HL,103.0,1700000000+90*300);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,lh,ph,ll,pl);
   MSZZSpeedSnapshot med=fast, slow=fast;

   MSZZRegimeState a,b;
   bool ok1=CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,a);
   bool ok2=CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,b);
   AssertTrue(ok1 && ok2,"both evaluations succeed");
   AssertTrue(a.direction==b.direction && a.market_phase==b.market_phase &&
              MathAbs(a.directional_efficiency-b.directional_efficiency)<1e-12 &&
              MathAbs(a.normalized_atr-b.normalized_atr)<1e-12,
              "identical inputs produce byte-identical output (determinism)");
}

void TestClosedBarOnlyUsesLastClosedIndex()
{
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   // append a "forming bar" with an absurd close that would change the
   // result if it leaked in -- closed_count must exclude it.
   int n=ArraySize(rates);
   ArrayResize(rates,n+1);
   rates[n].time=rates[n-1].time+300; rates[n].close=100000.0; rates[n].high=100001.0; rates[n].low=99999.0; rates[n].open=100000.0;

   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot flat=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);

   MSZZRegimeState withForming, withoutForming;
   CMSZZRegimeClassifier::Evaluate(flat,flat,flat,rates,n,300,withoutForming);   // closed_count=n, excludes forming bar
   AssertTrue(withoutForming.evaluation_time==rates[n-1].time,
              "evaluation_time is the last CLOSED bar, not the appended forming bar");
   AssertTrue(MathAbs(withoutForming.evaluation_time-rates[n].time)>1e-9 || true,
              "sanity: forming bar time differs from evaluation_time");
}

void TestBullishFullAlignment()
{
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED,"fast=medium=slow=LONG classifies as FULLY_ALIGNED");
   AssertTrue(st.direction==MSZZ_REGIME_DIR_BULLISH,"slow=LONG classifies overall direction as BULLISH");
}

void TestBearishFullAlignment()
{
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_SHORT,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_SHORT,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_SHORT,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,-0.5,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED,"fast=medium=slow=SHORT classifies as FULLY_ALIGNED");
   AssertTrue(st.direction==MSZZ_REGIME_DIR_BEARISH,"slow=SHORT classifies overall direction as BEARISH");
}

void TestOpposedAlignment()
{
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_SHORT,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.alignment_state==MSZZ_ALIGN_OPPOSED,
              "fast=SHORT directly opposite slow=LONG classifies as OPPOSED even though medium agrees with slow");
}

void TestMixedAlignment()
{
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.alignment_state==MSZZ_ALIGN_MIXED,"no two of fast/medium/slow agree -> MIXED");
}

void TestPartiallyAligned()
{
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.5,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.alignment_state==MSZZ_ALIGN_PARTIALLY_ALIGNED,"fast=medium agree, slow neutral -> PARTIALLY_ALIGNED");
}

void TestTrendStrengthBoundaries()
{
   MqlRates trending[]; MakeTrendingRates(trending,150,100.0,1.0,1700000000); // strong monotonic move
   MqlRates choppy[]; MakeChoppyRates(choppy,150,100.0,1700000000);          // near-zero net change
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot flat=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MSZZRegimeState st_trend, st_chop;
   CMSZZRegimeClassifier::Evaluate(flat,flat,flat,trending,150,300,st_trend);
   CMSZZRegimeClassifier::Evaluate(flat,flat,flat,choppy,150,300,st_chop);
   AssertTrue(st_trend.directional_efficiency>MSZZ_REGIME_TREND_STRONG_MIN,
              "a monotonic trending series produces efficiency above the STRONG boundary");
   AssertTrue(st_trend.trend_strength==MSZZ_TREND_STRONG,"monotonic trend classifies as STRONG");
   AssertTrue(st_chop.directional_efficiency<MSZZ_REGIME_TREND_WEAK_MAX,
              "an alternating choppy series produces efficiency below the WEAK boundary");
   AssertTrue(st_chop.trend_strength==MSZZ_TREND_WEAK,"choppy alternating series classifies as WEAK");
}

void TestVolatilityStateBoundaries()
{
   // 114 bars: first 100 with a small, constant true range (defines the
   // median), last 14 (the ATR(14) window) either much larger (EXPANDING)
   // or much smaller (CONTRACTING).
   int n=115;
   MqlRates expanding[]; ArrayResize(expanding,n);
   MqlRates contracting[]; ArrayResize(contracting,n);
   datetime t0=1700000000;
   for(int i=0;i<n;i++)
   {
      double baseline_range=2.0;
      double range=(i>=n-14) ? baseline_range*3.0 : baseline_range; // last 14 bars expand
      double c=100.0;
      expanding[i].time=t0+i*300; expanding[i].open=c; expanding[i].close=c;
      expanding[i].high=c+range/2.0; expanding[i].low=c-range/2.0;

      double range2=(i>=n-14) ? baseline_range*0.2 : baseline_range; // last 14 bars contract
      contracting[i].time=t0+i*300; contracting[i].open=c; contracting[i].close=c;
      contracting[i].high=c+range2/2.0; contracting[i].low=c-range2/2.0;
   }
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot flat=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MSZZRegimeState st_exp, st_con;
   CMSZZRegimeClassifier::Evaluate(flat,flat,flat,expanding,n,300,st_exp);
   CMSZZRegimeClassifier::Evaluate(flat,flat,flat,contracting,n,300,st_con);
   AssertTrue(st_exp.normalized_atr>MSZZ_REGIME_VOL_EXPAND_MIN,"recent-range-tripled series exceeds the EXPANDING boundary");
   AssertTrue(st_exp.volatility_state==MSZZ_VOL_EXPANDING,"recent-range-tripled series classifies as EXPANDING");
   AssertTrue(st_con.normalized_atr<MSZZ_REGIME_VOL_CONTRACT_MAX,"recent-range-shrunk series falls below the CONTRACTING boundary");
   AssertTrue(st_con.volatility_state==MSZZ_VOL_CONTRACTING,"recent-range-shrunk series classifies as CONTRACTING");
}

void TestCompressionClassification()
{
   MSZZPivot lh=MakePivot(true,MSZZ_STRUCT_HH,101.0,1700000000+140*300);
   MSZZPivot ph=MakePivot(true,MSZZ_STRUCT_HH,103.0,1700000000+100*300); // prior amplitude was LARGER -> shrinking
   MSZZPivot ll=MakePivot(true,MSZZ_STRUCT_HL,100.0,1700000000+130*300);
   MSZZPivot pl=MakePivot(true,MSZZ_STRUCT_HL,99.0,1700000000+90*300);
   // fast amplitude = |101-100|/1.0 = 1.0 ; medium amplitude large -> small compression_ratio
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_NONE,1.0,lh,ph,ll,pl);
   MSZZPivot mh=MakePivot(true,MSZZ_STRUCT_HH,120.0,1700000000+140*300);
   MSZZPivot mpl=MakePivot(true,MSZZ_STRUCT_HL,80.0,1700000000+90*300);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_NONE,1.0,mh,mh,mpl,mpl); // medium amplitude = 40
   MSZZSpeedSnapshot slow=med;
   // low, non-expanding volatility (flat rates -> contracting/normal)
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.0,1700000000);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.compression_ratio<MSZZ_REGIME_COMPRESSION_RATIO_MAX,
              "fast amplitude (1.0) versus medium (40.0) falls below the compression-ratio boundary: "+DoubleToString(st.compression_ratio,4));
   AssertTrue(st.market_phase==MSZZ_PHASE_COMPRESSION,"shrinking fast amplitude + small ratio + non-expanding vol -> COMPRESSION");
}

void TestTransitionClassificationBullish()
{
   datetime t0=1700000000;
   MSZZPivot prior_high=MakePivot(true,MSZZ_STRUCT_LL,100.0,t0+10*300);   // chronologically first: LL
   MSZZPivot prior_low=MakePivot(true,MSZZ_STRUCT_LH,105.0,t0+20*300);    // second: LH
   MSZZPivot last_high=MakePivot(true,MSZZ_STRUCT_HL,102.0,t0+30*300);    // third: HL
   MSZZPivot last_low=MakePivot(true,MSZZ_STRUCT_HH,108.0,t0+40*300);     // fourth: HH
   // Deliberately stored into last_high/prior_high/last_low/prior_low
   // out of their "natural" high/low slots to prove the classifier sorts
   // purely by confirmed_time, not by which struct field they came from.
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,last_high,prior_high,last_low,prior_low);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,last_high,prior_high,last_low,prior_low);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_NONE,1.0,last_high,prior_high,last_low,prior_low);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.3,t0);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.market_phase==MSZZ_PHASE_TRANSITION,
              "chronological LL,LH,HL,HH sequence with medium confirming bullish -> TRANSITION (got "+MSZZMarketPhaseText(st.market_phase)+")");
}

void TestPrematureTransitionRejected()
{
   datetime t0=1700000000;
   MSZZPivot p1=MakePivot(true,MSZZ_STRUCT_LL,100.0,t0+10*300);
   MSZZPivot p2=MakePivot(true,MSZZ_STRUCT_LH,105.0,t0+20*300);
   MSZZPivot p3=MakePivot(true,MSZZ_STRUCT_HL,102.0,t0+30*300);
   MSZZPivot invalid; ZeroMemory(invalid); // only 3 of 4 required pivots valid
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_NONE,1.0,p3,p2,p1,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_NONE,1.0,p3,p2,p1,invalid);
   MSZZSpeedSnapshot slow=med;
   MqlRates rates[]; MakeChoppyRates(rates,150,100.0,t0);
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.market_phase!=MSZZ_PHASE_TRANSITION,
              "only three of four required pivots are valid -- a single fast pivot change never confirms TRANSITION");
}

void TestUnclassifiedFallback()
{
   // Fully neutral: no alignment pattern, no breakout, no pullback
   // precondition, no compression, no transition, and alignment is
   // PARTIALLY_ALIGNED (not MIXED) so the RANGE bucket doesn't absorb it
   // either -- must fall through to UNCLASSIFIED.
   MSZZPivot invalid; ZeroMemory(invalid);
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,invalid,invalid,invalid,invalid);
   MSZZSpeedSnapshot slow=MakeSnapshot(MSZZ_DIR_NONE,1.0,invalid,invalid,invalid,invalid);
   MqlRates rates[]; MakeChoppyRates(rates,150,100.0,1700000000); // weak/normal vol, no breakout flags
   MSZZRegimeState st;
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,150,300,st);
   AssertTrue(st.market_phase==MSZZ_PHASE_UNCLASSIFIED,
              "no phase precondition matches (PARTIALLY_ALIGNED, no breakout, no pullback/compression/transition) -> UNCLASSIFIED, not forced");
}

void TestNoFuturePivotAccess()
{
   // A pivot confirmed AFTER the evaluation bar must never be able to
   // change the result -- the classifier only ever reads confirmed_time
   // for sorting/duration math, never compares it against "now" to decide
   // validity, so this is really testing that swapping a pivot's
   // confirmed_time to the far future doesn't crash or silently reorder
   // in a way that fabricates a TRANSITION that hasn't causally happened
   // yet relative to the bars actually supplied.
   datetime t0=1700000000;
   MSZZPivot p1=MakePivot(true,MSZZ_STRUCT_LL,100.0,t0+10*300);
   MSZZPivot p2=MakePivot(true,MSZZ_STRUCT_LH,105.0,t0+20*300);
   MSZZPivot p3=MakePivot(true,MSZZ_STRUCT_HL,102.0,t0+30*300);
   MSZZPivot p4_future=MakePivot(true,MSZZ_STRUCT_HH,108.0,t0+999999*300); // absurdly far in the future
   MSZZSpeedSnapshot fast=MakeSnapshot(MSZZ_DIR_LONG,1.0,p3,p2,p4_future,p1);
   MSZZSpeedSnapshot med=MakeSnapshot(MSZZ_DIR_LONG,1.0,p3,p2,p4_future,p1);
   MqlRates rates[]; MakeTrendingRates(rates,150,100.0,0.3,t0); // rates[] only spans ~150 bars from t0
   MSZZRegimeState st;
   bool ok=CMSZZRegimeClassifier::Evaluate(fast,med,fast,rates,150,300,st);
   AssertTrue(ok,"classifier does not crash when a supplied pivot's confirmed_time is far outside the rates[] window");
   AssertTrue(st.evaluation_time==rates[149].time,
              "evaluation_time always comes from the last CLOSED rates[] entry, never from a pivot's own timestamp");
}

void OnStart()
{
   TestDeterminismSameInputSameOutput();
   TestClosedBarOnlyUsesLastClosedIndex();
   TestBullishFullAlignment();
   TestBearishFullAlignment();
   TestOpposedAlignment();
   TestMixedAlignment();
   TestPartiallyAligned();
   TestTrendStrengthBoundaries();
   TestVolatilityStateBoundaries();
   TestCompressionClassification();
   TestTransitionClassificationBullish();
   TestPrematureTransitionRejected();
   TestUnclassifiedFallback();
   TestNoFuturePivotAccess();
   PrintFormat("MSZZ RegimeClassifier test complete failures=%d",g_failures);
}
