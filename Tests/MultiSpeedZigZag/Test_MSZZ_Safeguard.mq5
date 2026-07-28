//+------------------------------------------------------------------+
//| Test_MSZZ_Safeguard.mq5                                          |
//| Covers DECISION_LOG.md D013 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/AccountSafeguard.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void TestTradeCountBelowLimitPasses()
{
   AssertTrue(!CMSZZAccountSafeguardPolicy::TradeCountLimitReached(5,20),
              "trade count (5) below the limit (20) is not reached");
}

void TestTradeCountAtLimitIsBlocked()
{
   AssertTrue(CMSZZAccountSafeguardPolicy::TradeCountLimitReached(20,20),
              "trade count exactly at the limit (20/20) is reached");
}

void TestTradeCountAboveLimitIsBlocked()
{
   AssertTrue(CMSZZAccountSafeguardPolicy::TradeCountLimitReached(25,20),
              "trade count above the limit (25/20) is reached");
}

void TestNonPositiveMaxTradesDisablesCheck()
{
   AssertTrue(!CMSZZAccountSafeguardPolicy::TradeCountLimitReached(1000,0),
              "a max_trades of 0 disables the trade-count check entirely");
   AssertTrue(!CMSZZAccountSafeguardPolicy::TradeCountLimitReached(1000,-5),
              "a negative max_trades disables the trade-count check entirely");
}

void TestLossBelowLimitPasses()
{
   AssertTrue(!CMSZZAccountSafeguardPolicy::DailyLossLimitReached(50.0,100.0),
              "loss magnitude (50) below the limit (100) is not reached");
}

void TestLossAtLimitIsBlocked()
{
   AssertTrue(CMSZZAccountSafeguardPolicy::DailyLossLimitReached(100.0,100.0),
              "loss magnitude exactly at the limit (100/100) is reached");
}

void TestLossAboveLimitIsBlocked()
{
   AssertTrue(CMSZZAccountSafeguardPolicy::DailyLossLimitReached(150.0,100.0),
              "loss magnitude above the limit (150/100) is reached");
}

void TestNonPositiveMaxLossDisablesCheck()
{
   AssertTrue(!CMSZZAccountSafeguardPolicy::DailyLossLimitReached(100000.0,0.0),
              "a max_daily_loss_amount of 0.0 disables the loss check entirely (the documented default)");
   AssertTrue(!CMSZZAccountSafeguardPolicy::DailyLossLimitReached(100000.0,-50.0),
              "a negative max_daily_loss_amount disables the loss check entirely");
}

void TestZeroLossNeverBlocksRegardlessOfPositiveLimit()
{
   AssertTrue(!CMSZZAccountSafeguardPolicy::DailyLossLimitReached(0.0,100.0),
              "zero loss magnitude never blocks even with a positive, enabled limit");
}

void OnStart()
{
   TestTradeCountBelowLimitPasses();
   TestTradeCountAtLimitIsBlocked();
   TestTradeCountAboveLimitIsBlocked();
   TestNonPositiveMaxTradesDisablesCheck();
   TestLossBelowLimitPasses();
   TestLossAtLimitIsBlocked();
   TestLossAboveLimitIsBlocked();
   TestNonPositiveMaxLossDisablesCheck();
   TestZeroLossNeverBlocksRegardlessOfPositiveLimit();

   PrintFormat("MSZZ safeguard test complete failures=%d",g_failures);
}
