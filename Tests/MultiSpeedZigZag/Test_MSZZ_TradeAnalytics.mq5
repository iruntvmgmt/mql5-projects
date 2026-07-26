//+------------------------------------------------------------------+
//| Test_MSZZ_TradeAnalytics.mq5                                     |
//| Covers DECISION_LOG.md D016 requirements (deterministic core).   |
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

//--- RMultiple --------------------------------------------------------

void TestRMultipleLongWin()
{
   double r=CMSZZTradeAnalyticsPolicy::RMultiple(100.0,90.0,120.0,MSZZ_DIR_LONG);
   AssertNear(r,2.0,0.0001,"long win: entry=100 stop=90 close=120 -> +2R");
}

void TestRMultipleLongLoss()
{
   double r=CMSZZTradeAnalyticsPolicy::RMultiple(100.0,90.0,85.0,MSZZ_DIR_LONG);
   AssertNear(r,-1.5,0.0001,"long loss: entry=100 stop=90 close=85 -> -1.5R");
}

void TestRMultipleShortWin()
{
   double r=CMSZZTradeAnalyticsPolicy::RMultiple(100.0,110.0,80.0,MSZZ_DIR_SHORT);
   AssertNear(r,2.0,0.0001,"short win: entry=100 stop=110 close=80 -> +2R");
}

void TestRMultipleShortLoss()
{
   double r=CMSZZTradeAnalyticsPolicy::RMultiple(100.0,110.0,115.0,MSZZ_DIR_SHORT);
   AssertNear(r,-1.5,0.0001,"short loss: entry=100 stop=110 close=115 -> -1.5R");
}

void TestRMultipleZeroRiskGuard()
{
   double r=CMSZZTradeAnalyticsPolicy::RMultiple(100.0,100.0,120.0,MSZZ_DIR_LONG);
   AssertTrue(r==0.0,"zero risk (entry==stop) returns 0.0, not nan/inf");
}

//--- ExcursionInR (MFE/MAE building block) -----------------------------

void TestExcursionInRLongFavorable()
{
   double e=CMSZZTradeAnalyticsPolicy::ExcursionInR(130.0,100.0,90.0,MSZZ_DIR_LONG);
   AssertNear(e,3.0,0.0001,"long: excursion to 130 with entry=100 stop=90 -> +3R");
}

void TestExcursionInRLongAdverse()
{
   double e=CMSZZTradeAnalyticsPolicy::ExcursionInR(95.0,100.0,90.0,MSZZ_DIR_LONG);
   AssertNear(e,-0.5,0.0001,"long: excursion to 95 with entry=100 stop=90 -> -0.5R (adverse)");
}

void TestExcursionInRShortFavorable()
{
   double e=CMSZZTradeAnalyticsPolicy::ExcursionInR(70.0,100.0,110.0,MSZZ_DIR_SHORT);
   AssertNear(e,3.0,0.0001,"short: excursion to 70 with entry=100 stop=110 -> +3R");
}

void TestExcursionInRShortAdverse()
{
   double e=CMSZZTradeAnalyticsPolicy::ExcursionInR(105.0,100.0,110.0,MSZZ_DIR_SHORT);
   AssertNear(e,-0.5,0.0001,"short: excursion to 105 with entry=100 stop=110 -> -0.5R (adverse)");
}

//--- ClassifyExitReason -------------------------------------------------

void TestClassifyExitReasonExactlyAtStop()
{
   ENUM_MSZZ_EXIT_REASON r=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(90.0,90.0,120.0,0.01);
   AssertTrue(r==MSZZ_EXIT_SL,"close exactly at stop classifies as SL");
}

void TestClassifyExitReasonExactlyAtTarget()
{
   ENUM_MSZZ_EXIT_REASON r=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(120.0,90.0,120.0,0.01);
   AssertTrue(r==MSZZ_EXIT_TP,"close exactly at target classifies as TP");
}

void TestClassifyExitReasonWithinToleranceOfStop()
{
   ENUM_MSZZ_EXIT_REASON r=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(90.001,90.0,120.0,0.01);
   AssertTrue(r==MSZZ_EXIT_SL,"close within half-point tolerance of stop still classifies as SL");
}

void TestClassifyExitReasonWithinToleranceOfTarget()
{
   ENUM_MSZZ_EXIT_REASON r=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(119.999,90.0,120.0,0.01);
   AssertTrue(r==MSZZ_EXIT_TP,"close within half-point tolerance of target still classifies as TP");
}

void TestClassifyExitReasonBetweenIsOther()
{
   ENUM_MSZZ_EXIT_REASON r=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(105.0,90.0,120.0,0.01);
   AssertTrue(r==MSZZ_EXIT_OTHER,"close between stop and target (neither) classifies as OTHER");
}

//--- SessionBucket -------------------------------------------------------

void TestSessionBucketBoundaries()
{
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(0)==MSZZ_SESSION_ASIAN,"hour 0 -> Asian");
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(7)==MSZZ_SESSION_ASIAN,"hour 7 -> Asian");
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(8)==MSZZ_SESSION_LONDON,"hour 8 -> London");
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(15)==MSZZ_SESSION_LONDON,"hour 15 -> London");
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(16)==MSZZ_SESSION_NEWYORK,"hour 16 -> NewYork");
   AssertTrue(CMSZZTradeAnalyticsPolicy::SessionBucket(23)==MSZZ_SESSION_NEWYORK,"hour 23 -> NewYork");
}

void OnStart()
{
   TestRMultipleLongWin();
   TestRMultipleLongLoss();
   TestRMultipleShortWin();
   TestRMultipleShortLoss();
   TestRMultipleZeroRiskGuard();
   TestExcursionInRLongFavorable();
   TestExcursionInRLongAdverse();
   TestExcursionInRShortFavorable();
   TestExcursionInRShortAdverse();
   TestClassifyExitReasonExactlyAtStop();
   TestClassifyExitReasonExactlyAtTarget();
   TestClassifyExitReasonWithinToleranceOfStop();
   TestClassifyExitReasonWithinToleranceOfTarget();
   TestClassifyExitReasonBetweenIsOther();
   TestSessionBucketBoundaries();

   PrintFormat("MSZZ trade analytics test complete failures=%d",g_failures);
}
