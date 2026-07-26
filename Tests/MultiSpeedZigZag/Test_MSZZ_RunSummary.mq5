//+------------------------------------------------------------------+
//| Test_MSZZ_RunSummary.mq5                                         |
//| Covers DECISION_LOG.md D017 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void AssertNear(const double actual,const double expected,const double tolerance,const string message)
{
   AssertTrue(MathAbs(actual-expected)<=tolerance,
              StringFormat("%s (actual=%.6f expected=%.6f)",message,actual,expected));
}

//--- Average -------------------------------------------------------------

void TestAverageKnownSet()
{
   double v[4]={1.0,2.0,3.0,4.0};
   AssertNear(CMSZZRunSummaryPolicy::Average(v,4),2.5,0.0001,"Average of [1,2,3,4] is 2.5");
}

void TestAverageEmptySet()
{
   double v[1];
   AssertTrue(CMSZZRunSummaryPolicy::Average(v,0)==0.0,"Average of an empty set is 0.0, not nan");
}

//--- WinRate ---------------------------------------------------------------

void TestWinRateMixedWithBreakeven()
{
   double r[5]={1.0,-1.0,2.0,0.0,-0.5}; // 2 wins, 2 losses, 1 breakeven
   AssertNear(CMSZZRunSummaryPolicy::WinRate(r,5),0.4,0.0001,
              "win rate with a breakeven (r=0.0) not counted as a win: 2/5 = 0.4");
}

void TestWinRateAllWins()
{
   double r[3]={1.0,2.0,3.0};
   AssertNear(CMSZZRunSummaryPolicy::WinRate(r,3),1.0,0.0001,"all-wins set has win rate 1.0");
}

//--- ProfitFactorR -----------------------------------------------------------

void TestProfitFactorNormalMix()
{
   double r[4]={2.0,2.0,-1.0,-1.0}; // gross win 4, gross loss 2 -> PF 2.0
   AssertNear(CMSZZRunSummaryPolicy::ProfitFactorR(r,4),2.0,0.0001,"normal mix: gross win 4 / gross loss 2 = PF 2.0");
}

void TestProfitFactorAllWinsSentinel()
{
   double r[3]={1.0,2.0,3.0};
   AssertTrue(CMSZZRunSummaryPolicy::ProfitFactorR(r,3)==-1.0,
              "all-wins, zero losses returns the -1.0 undefined sentinel, not inf");
}

void TestProfitFactorAllLosses()
{
   double r[3]={-1.0,-2.0,-3.0};
   AssertTrue(CMSZZRunSummaryPolicy::ProfitFactorR(r,3)==0.0,
              "all-losses, zero wins returns 0.0");
}

//--- MaxDrawdownR --------------------------------------------------------------

void TestMaxDrawdownMonotonicallyImproving()
{
   double r[3]={1.0,1.0,1.0};
   AssertNear(CMSZZRunSummaryPolicy::MaxDrawdownR(r,3),0.0,0.0001,
              "a monotonically-improving equity curve has zero drawdown");
}

void TestMaxDrawdownSingleLargeLossAfterWins()
{
   double r[3]={1.0,1.0,-3.0}; // peak=2.0 after two wins, then drops to -1.0 -> dd=3.0
   AssertNear(CMSZZRunSummaryPolicy::MaxDrawdownR(r,3),3.0,0.0001,
              "peak of 2.0R then a -3.0R loss produces a 3.0R drawdown");
}

void TestMaxDrawdownPeakTroughRecovery()
{
   double r[5]={2.0,-1.0,-1.0,1.0,3.0}; // cum: 2,1,0,1,4 -> peak 2 at i0, trough 0 at i2 -> dd=2.0
   AssertNear(CMSZZRunSummaryPolicy::MaxDrawdownR(r,5),2.0,0.0001,
              "peak-trough-recovery shape correctly measures the drawdown at the trough, not the final value");
}

void OnStart()
{
   TestAverageKnownSet();
   TestAverageEmptySet();
   TestWinRateMixedWithBreakeven();
   TestWinRateAllWins();
   TestProfitFactorNormalMix();
   TestProfitFactorAllWinsSentinel();
   TestProfitFactorAllLosses();
   TestMaxDrawdownMonotonicallyImproving();
   TestMaxDrawdownSingleLargeLossAfterWins();
   TestMaxDrawdownPeakTroughRecovery();

   PrintFormat("MSZZ run summary test complete failures=%d",g_failures);
}
