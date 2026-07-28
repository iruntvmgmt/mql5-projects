//+------------------------------------------------------------------+
//| Test_MSZZ_Margin.mq5                                             |
//| Covers DECISION_LOG.md D012 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/MarginGuard.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void TestComfortableMarginPasses()
{
   AssertTrue(CMSZZMarginPolicy::HasSufficientMargin(100.0,1000.0,1.0),
              "free margin comfortably above the buffered requirement (100 required, 1.0 buffer -> need 200, have 1000) passes");
}

void TestExactBufferedBoundaryPasses()
{
   AssertTrue(CMSZZMarginPolicy::HasSufficientMargin(100.0,200.0,1.0),
              "free margin exactly at the buffered boundary (100 required, 1.0 buffer -> need exactly 200, have 200) passes");
}

void TestJustBelowBufferedBoundaryFails()
{
   AssertTrue(!CMSZZMarginPolicy::HasSufficientMargin(100.0,199.99,1.0),
              "free margin just below the buffered boundary (need 200, have 199.99) fails");
}

void TestZeroRequiredMarginIsTriviallySufficient()
{
   AssertTrue(CMSZZMarginPolicy::HasSufficientMargin(0.0,0.0,1.0),
              "zero required margin is trivially sufficient regardless of free margin");
}

void TestZeroFreeMarginWithNonzeroRequiredFails()
{
   AssertTrue(!CMSZZMarginPolicy::HasSufficientMargin(50.0,0.0,1.0),
              "zero free margin with nonzero required margin fails");
}

void TestZeroBufferReducesToBareComparison()
{
   AssertTrue(CMSZZMarginPolicy::HasSufficientMargin(100.0,100.0,0.0),
              "a buffer ratio of 0 reduces to a bare free>=required comparison (equal passes)");
   AssertTrue(!CMSZZMarginPolicy::HasSufficientMargin(100.0,99.99,0.0),
              "a buffer ratio of 0 still fails when free is below the bare requirement");
}

void TestNegativeBufferTreatedAsZero()
{
   AssertTrue(CMSZZMarginPolicy::HasSufficientMargin(100.0,100.0,-5.0),
              "a negative buffer ratio is clamped to zero, not allowed to reduce the requirement below bare minimum");
}

void OnStart()
{
   TestComfortableMarginPasses();
   TestExactBufferedBoundaryPasses();
   TestJustBelowBufferedBoundaryFails();
   TestZeroRequiredMarginIsTriviallySufficient();
   TestZeroFreeMarginWithNonzeroRequiredFails();
   TestZeroBufferReducesToBareComparison();
   TestNegativeBufferTreatedAsZero();

   PrintFormat("MSZZ margin test complete failures=%d",g_failures);
}
