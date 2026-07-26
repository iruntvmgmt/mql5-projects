#ifndef __MSZZ_MARGIN_GUARD_MQH__
#define __MSZZ_MARGIN_GUARD_MQH__

// See DECISION_LOG.md D012. First increment of Phase 6 (margin and
// exposure preflight) -- per-order margin sufficiency on the traded
// symbol only, not a general account-wide/cross-symbol exposure cap or
// account safeguards (daily loss limits, kill switch -- Phase 7). See
// D012 for exactly what is and is not covered.

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// CMSZZPositionOwnershipPolicy (D005), CMSZZReconciliationPolicy (D009),
// CMSZZIntentStateMachine (D010), and CMSZZProtectionPolicy (D011).
class CMSZZMarginPolicy
{
public:
   // A buffer_ratio of 1.0 requires free margin to be at least double the
   // bare minimum required margin -- see DECISION_LOG.md D012 for why a
   // check that only confirms the order can be *placed*, leaving zero
   // headroom, defeats the purpose of a margin check that should also
   // confirm the account can *survive* holding the position.
   static bool HasSufficientMargin(const double required_margin,const double free_margin,
                                    const double buffer_ratio)
   {
      if(required_margin<=0.0) return true;
      double needed=required_margin*(1.0+MathMax(0.0,buffer_ratio));
      return free_margin>=needed;
   }
};

// Live wrapper: computes required margin via the broker-authoritative
// OrderCalcMargin() and reads current free margin, then delegates the
// comparison to the policy class. A failed OrderCalcMargin() call is
// treated as insufficient margin, never silently skipped or assumed fine.
class CMSZZMarginGuard
{
public:
   bool CheckMargin(const string symbol,const ENUM_ORDER_TYPE order_type,
                     const double volume,const double price,const double buffer_ratio,
                     double &required_margin_out,double &free_margin_out,string &reason)
   {
      required_margin_out=0.0;
      free_margin_out=AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      double required_margin=0.0;
      if(!OrderCalcMargin(order_type,symbol,volume,price,required_margin))
      {
         reason=StringFormat("OrderCalcMargin failed error=%d",GetLastError());
         return false;
      }
      required_margin_out=required_margin;

      if(!CMSZZMarginPolicy::HasSufficientMargin(required_margin,free_margin_out,buffer_ratio))
      {
         reason=StringFormat("insufficient margin: free=%.2f required=%.2f buffer_ratio=%.2f",
                              free_margin_out,required_margin,buffer_ratio);
         return false;
      }

      reason="";
      return true;
   }
};

#endif
