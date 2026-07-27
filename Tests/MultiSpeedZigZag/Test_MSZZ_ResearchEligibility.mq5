//+------------------------------------------------------------------+
//| Test_MSZZ_ResearchEligibility.mq5                                |
//| Covers DECISION_LOG.md D019 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ResearchEligibilityPolicy.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

// Fixed stand-ins for the two ENUM_ACCOUNT_TRADE_MODE values the policy
// compares -- passed as plain longs so the policy file has zero MT5 API
// dependency (deterministically testable without a live terminal).
#define TEST_TRADE_MODE_DEMO   0
#define TEST_TRADE_MODE_REAL   2
#define TEST_EXPECTED_LOGIN    870012

void TestOverrideDisabledAlwaysAuthorized()
{
   AssertTrue(CMSZZResearchEligibilityPolicy::IsAuthorized(0.0,false,false,TEST_TRADE_MODE_REAL,111111,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override<=0 authorized even with acknowledge=false, real-money mode, wrong login");
   AssertTrue(CMSZZResearchEligibilityPolicy::IsAuthorized(-1.0,false,false,TEST_TRADE_MODE_REAL,111111,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "negative override also fully disables the mechanism");
}

void TestOverrideWithoutAcknowledgeFails()
{
   AssertTrue(!CMSZZResearchEligibilityPolicy::IsAuthorized(3.5,false,true,TEST_TRADE_MODE_DEMO,TEST_EXPECTED_LOGIN,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override>0 with acknowledge=false fails even in Tester with correct login/mode");
}

void TestOverrideRealMoneyNotTesterFails()
{
   AssertTrue(!CMSZZResearchEligibilityPolicy::IsAuthorized(3.5,true,false,TEST_TRADE_MODE_REAL,TEST_EXPECTED_LOGIN,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override>0, acknowledged, not in Tester, real-money trade mode -- fails");
}

void TestOverrideWrongLoginNotTesterFails()
{
   AssertTrue(!CMSZZResearchEligibilityPolicy::IsAuthorized(3.5,true,false,TEST_TRADE_MODE_DEMO,999999,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override>0, acknowledged, not in Tester, demo mode but wrong login -- fails");
}

void TestOverrideInTesterIgnoresLogin()
{
   AssertTrue(CMSZZResearchEligibilityPolicy::IsAuthorized(3.5,true,true,TEST_TRADE_MODE_REAL,1,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override>0, acknowledged, in Tester -- passes regardless of trade_mode/login");
}

void TestOverrideCorrectDemoLoginNotTesterPasses()
{
   AssertTrue(CMSZZResearchEligibilityPolicy::IsAuthorized(3.5,true,false,TEST_TRADE_MODE_DEMO,TEST_EXPECTED_LOGIN,TEST_EXPECTED_LOGIN,TEST_TRADE_MODE_DEMO),
              "override>0, acknowledged, not in Tester, correct demo login -- passes");
}

void OnStart()
{
   TestOverrideDisabledAlwaysAuthorized();
   TestOverrideWithoutAcknowledgeFails();
   TestOverrideRealMoneyNotTesterFails();
   TestOverrideWrongLoginNotTesterFails();
   TestOverrideInTesterIgnoresLogin();
   TestOverrideCorrectDemoLoginNotTesterPasses();

   PrintFormat("MSZZ research eligibility test complete failures=%d",g_failures);
}
