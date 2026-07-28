//+------------------------------------------------------------------+
//| Test_MSZZ_Protection.mq5                                         |
//| Covers DECISION_LOG.md D011 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/ProtectionGuard.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void TestMatchingWithinToleranceNeedsNoRepair()
{
   AssertTrue(!CMSZZProtectionPolicy::NeedsRepair(4000.00,4020.00,4000.00,4020.00,0.01),
              "exact-match SL/TP needs no repair");
}

void TestSlOffNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(3999.00,4020.00,4000.00,4020.00,0.01),
              "SL off by 1.00 (far beyond tolerance) needs repair");
}

void TestTpOffNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(4000.00,4019.00,4000.00,4020.00,0.01),
              "TP off by 1.00 (far beyond tolerance) needs repair");
}

void TestBothOffNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(3999.00,4019.00,4000.00,4020.00,0.01),
              "both SL and TP off needs repair");
}

void TestZeroSlWhenExpectedNonzeroNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(0.0,4020.00,4000.00,4020.00,0.01),
              "unset (zero) SL when a nonzero SL was expected needs repair");
}

void TestZeroTpWhenExpectedNonzeroNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(4000.00,0.0,4000.00,4020.00,0.01),
              "unset (zero) TP when a nonzero TP was expected needs repair");
}

void TestZeroBothWhenExpectedNonzeroNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(0.0,0.0,4000.00,4020.00,0.01),
              "unset (zero) SL and TP when both were expected needs repair");
}

void TestFloatingPointBoundaryDoesNotSpuriouslyTriggerRepair()
{
   double expected_sl=4000.00;
   double actual_sl=4000.00+0.0000001; // sub-tolerance floating-point noise
   AssertTrue(!CMSZZProtectionPolicy::NeedsRepair(actual_sl,4020.00,expected_sl,4020.00,0.01),
              "sub-tolerance floating-point noise does not spuriously trigger repair");
}

void TestExactlyAtToleranceBoundaryNeedsNoRepair()
{
   // half-point tolerance for point=0.01 is 0.005; an offset of exactly
   // half that should stay comfortably within tolerance.
   AssertTrue(!CMSZZProtectionPolicy::NeedsRepair(4000.002,4020.00,4000.00,4020.00,0.01),
              "an offset well inside half-point tolerance needs no repair");
}

void TestOffsetBeyondHalfPointToleranceNeedsRepair()
{
   AssertTrue(CMSZZProtectionPolicy::NeedsRepair(4000.01,4020.00,4000.00,4020.00,0.01),
              "an offset of a full point (beyond half-point tolerance) needs repair");
}

void OnStart()
{
   TestMatchingWithinToleranceNeedsNoRepair();
   TestSlOffNeedsRepair();
   TestTpOffNeedsRepair();
   TestBothOffNeedsRepair();
   TestZeroSlWhenExpectedNonzeroNeedsRepair();
   TestZeroTpWhenExpectedNonzeroNeedsRepair();
   TestZeroBothWhenExpectedNonzeroNeedsRepair();
   TestFloatingPointBoundaryDoesNotSpuriouslyTriggerRepair();
   TestExactlyAtToleranceBoundaryNeedsNoRepair();
   TestOffsetBeyondHalfPointToleranceNeedsRepair();

   PrintFormat("MSZZ protection test complete failures=%d",g_failures);
}
