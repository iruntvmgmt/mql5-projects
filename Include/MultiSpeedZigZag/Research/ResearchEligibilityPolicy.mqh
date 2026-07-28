#property strict
//+------------------------------------------------------------------+
//| ResearchEligibilityPolicy.mqh                                    |
//| D019: pure authorization decision for InpResearchMinScoreOverride|
//| -- fail-closed, all-or-nothing, no partial/silent-fallback path. |
//+------------------------------------------------------------------+

// Pure, static, no MT5 API calls -- every input is passed in explicitly
// so this is deterministically unit-testable without a live terminal.
class CMSZZResearchEligibilityPolicy
{
public:
   // override<=0.0 means research mode was never requested -- always
   // authorized (the mechanism is fully disabled), independent of every
   // other argument.
   static bool IsAuthorized(const double override_value,
                             const bool acknowledge,
                             const bool is_tester,
                             const long trade_mode,          // ENUM_ACCOUNT_TRADE_MODE, passed as long
                             const long account_login,
                             const long expected_demo_login,
                             const long account_trade_mode_demo) // ACCOUNT_TRADE_MODE_DEMO, passed as long
   {
      if(override_value<=0.0) return true;
      if(!acknowledge) return false;
      if(is_tester) return true; // Tester runs are inherently sandboxed regardless of login
      if(trade_mode!=account_trade_mode_demo) return false;
      if(account_login!=expected_demo_login) return false;
      return true;
   }
};
