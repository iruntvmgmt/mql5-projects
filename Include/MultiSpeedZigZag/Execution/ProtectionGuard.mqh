#ifndef __MSZZ_PROTECTION_GUARD_MQH__
#define __MSZZ_PROTECTION_GUARD_MQH__

// See DECISION_LOG.md D011. First increment of Phase 4 (protection
// verification and repair) -- a one-shot post-fill SL/TP check plus at
// most one repair attempt, not a general position-management or
// trailing-stop system. See D011 for exactly what is and is not covered.

#include <Trade/Trade.mqh>

enum ENUM_MSZZ_PROTECTION_VERDICT
{
   MSZZ_PROTECTION_OK = 0,
   MSZZ_PROTECTION_REPAIRED,
   MSZZ_PROTECTION_REPAIR_FAILED,
   MSZZ_PROTECTION_POSITION_NOT_FOUND
};

string MSZZProtectionVerdictText(const ENUM_MSZZ_PROTECTION_VERDICT v)
{
   switch(v)
   {
      case MSZZ_PROTECTION_OK:                  return "OK";
      case MSZZ_PROTECTION_REPAIRED:             return "REPAIRED";
      case MSZZ_PROTECTION_REPAIR_FAILED:        return "REPAIR_FAILED";
      case MSZZ_PROTECTION_POSITION_NOT_FOUND:   return "POSITION_NOT_FOUND";
      default:                                   return "UNKNOWN";
   }
}

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// CMSZZPositionOwnershipPolicy (D005), CMSZZReconciliationPolicy (D009),
// and CMSZZIntentStateMachine (D010).
class CMSZZProtectionPolicy
{
public:
   // Tolerance is half a point, to absorb broker-side rounding without
   // spuriously flagging a correctly-set SL/TP as needing repair. A zero
   // (unset) actual value when a nonzero one was expected always needs
   // repair, regardless of tolerance.
   static bool NeedsRepair(const double actual_sl,const double actual_tp,
                            const double expected_sl,const double expected_tp,
                            const double point)
   {
      double tolerance=(point>0.0 ? point/2.0 : 0.0000001);
      if(expected_sl>0.0 && MathAbs(actual_sl-expected_sl)>tolerance) return true;
      if(expected_tp>0.0 && MathAbs(actual_tp-expected_tp)>tolerance) return true;
      return false;
   }
};

// Live wrapper: reads the actual position's SL/TP and, if they don't match
// what was requested, attempts exactly one repair via CTrade::PositionModify.
// No retry loop -- see DECISION_LOG.md D011 "Rejected alternatives" for why
// an unbounded retry is itself a risk, not a fix.
class CMSZZProtectionGuard
{
public:
   ENUM_MSZZ_PROTECTION_VERDICT VerifyAndRepair(CTrade &trade,const ulong ticket,
                                                 const double expected_stop,const double expected_target,
                                                 string &reason)
   {
      reason="";
      if(!PositionSelectByTicket(ticket))
      {
         reason="position ticket does not resolve to a live position";
         return MSZZ_PROTECTION_POSITION_NOT_FOUND;
      }

      string symbol=PositionGetString(POSITION_SYMBOL);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double actual_sl=PositionGetDouble(POSITION_SL);
      double actual_tp=PositionGetDouble(POSITION_TP);

      if(!CMSZZProtectionPolicy::NeedsRepair(actual_sl,actual_tp,expected_stop,expected_target,point))
      {
         reason="protection already correct";
         return MSZZ_PROTECTION_OK;
      }

      if(!trade.PositionModify(ticket,expected_stop,expected_target))
      {
         reason=StringFormat("repair attempt failed retcode=%u %s",
                              trade.ResultRetcode(),trade.ResultRetcodeDescription());
         return MSZZ_PROTECTION_REPAIR_FAILED;
      }

      if(!PositionSelectByTicket(ticket))
      {
         reason="position disappeared immediately after repair";
         return MSZZ_PROTECTION_POSITION_NOT_FOUND;
      }
      actual_sl=PositionGetDouble(POSITION_SL);
      actual_tp=PositionGetDouble(POSITION_TP);
      if(CMSZZProtectionPolicy::NeedsRepair(actual_sl,actual_tp,expected_stop,expected_target,point))
      {
         reason="repair reported success but re-read protection still does not match";
         return MSZZ_PROTECTION_REPAIR_FAILED;
      }

      reason="repaired successfully";
      return MSZZ_PROTECTION_REPAIRED;
   }
};

#endif
