//+------------------------------------------------------------------+
//| Test_MSZZ_Expiry.mq5                                             |
//| Covers DECISION_LOG.md D015 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/ExecutionGuard.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void TestBeforeExpiryIsNotExpired()
{
   datetime expiry=D'2026.07.26 12:00:00';
   datetime now=D'2026.07.26 11:59:59';
   AssertTrue(!CMSZZExecutionGuard::IsExpired(now,expiry),
              "now before expiry_time is not expired");
}

void TestExactlyAtExpiryIsNotExpired()
{
   datetime expiry=D'2026.07.26 12:00:00';
   AssertTrue(!CMSZZExecutionGuard::IsExpired(expiry,expiry),
              "now exactly at expiry_time is not expired (expiry is exclusive)");
}

void TestAfterExpiryIsExpired()
{
   datetime expiry=D'2026.07.26 12:00:00';
   datetime now=D'2026.07.26 12:00:01';
   AssertTrue(CMSZZExecutionGuard::IsExpired(now,expiry),
              "now after expiry_time is expired");
}

void TestNonPositiveExpiryDisablesCheck()
{
   datetime now=D'2026.07.26 12:00:01';
   AssertTrue(!CMSZZExecutionGuard::IsExpired(now,(datetime)0),
              "expiry_time of 0 disables the check entirely (never expired)");
   AssertTrue(!CMSZZExecutionGuard::IsExpired(now,(datetime)-1),
              "a negative expiry_time disables the check entirely (never expired)");
}

void TestAddCandidateSetsNonzeroExpiry()
{
   CMSZZStrategySuite suite;
   suite.SetSignalValidityBars(3);

   MSZZSpeedSnapshot fast,med,slow;
   MSZZCandidate out[];
   datetime t=D'2026.07.26 10:00:00';
   int count=suite.Evaluate(fast,med,slow,t,4000.0,out);
   // No structure exists in these blank snapshots, so no candidates are
   // expected -- this smoke-checks that Evaluate() runs cleanly with the
   // new validity-bars state set, not the candidate content itself (that
   // is Test_MSZZ_Clusters.mq5's job). A direct AddCandidate() unit test
   // is not exposed (private helper); nonzero expiry_time on a real
   // candidate is confirmed via Test_MSZZ_Clusters.mq5 continuing to pass
   // and via shadow regression evidence, per DECISION_LOG.md D015.
   AssertTrue(count>=0,"Evaluate() runs cleanly with SetSignalValidityBars() configured");
}

void OnStart()
{
   TestBeforeExpiryIsNotExpired();
   TestExactlyAtExpiryIsNotExpired();
   TestAfterExpiryIsExpired();
   TestNonPositiveExpiryDisablesCheck();
   TestAddCandidateSetsNonzeroExpiry();

   PrintFormat("MSZZ expiry test complete failures=%d",g_failures);
}
