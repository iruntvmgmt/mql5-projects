#ifndef __MSZZ_INTENT_STATE_MACHINE_MQH__
#define __MSZZ_INTENT_STATE_MACHINE_MQH__

// See DECISION_LOG.md D010. First increment of Phase 3 (execution state
// machine) -- a pure, auditable transition-legality table plus a single
// gated setter, not a redesign of ExecutionIntentStore's schema or a new
// set of states actually emitted by the EA. See D010 for exactly what is
// and is not covered.

#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// CMSZZPositionOwnershipPolicy (D005) and CMSZZReconciliationPolicy (D009).
class CMSZZIntentStateMachine
{
public:
   // RECOVERY_REQUIRED and ABANDONED are reachable from every non-terminal
   // state by design (see D010 "Rejected alternatives" for why this is two
   // blanket rows rather than special-cased per source state). POSITION_CLOSED
   // and ABANDONED are terminal: zero legal outgoing transitions, matching
   // CMSZZExecutionReconciler::IsTerminal()'s existing definition exactly.
   // A state transitioning to itself is always legal (idempotent re-application).
   static bool IsLegalTransition(const ENUM_MSZZ_INTENT_STATE from,const ENUM_MSZZ_INTENT_STATE to)
   {
      if(from==to) return true;

      // Terminal states: no outgoing transitions at all, not even to
      // RECOVERY_REQUIRED/ABANDONED -- once terminal, always terminal.
      if(from==MSZZ_INTENT_POSITION_CLOSED || from==MSZZ_INTENT_ABANDONED) return false;

      // Universal escape hatches from every other (non-terminal) state.
      if(to==MSZZ_INTENT_RECOVERY_REQUIRED || to==MSZZ_INTENT_ABANDONED) return true;

      switch(from)
      {
         case MSZZ_INTENT_CREATED:
            return to==MSZZ_INTENT_PERSISTED;
         case MSZZ_INTENT_PERSISTED:
            return to==MSZZ_INTENT_PREFLIGHT_PASSED || to==MSZZ_INTENT_BROKER_ACCEPTED ||
                   to==MSZZ_INTENT_BROKER_REJECTED;
         case MSZZ_INTENT_PREFLIGHT_PASSED:
            return to==MSZZ_INTENT_SUBMISSION_STARTED;
         case MSZZ_INTENT_SUBMISSION_STARTED:
            return to==MSZZ_INTENT_BROKER_ACCEPTED || to==MSZZ_INTENT_BROKER_REJECTED ||
                   to==MSZZ_INTENT_RESULT_UNKNOWN;
         case MSZZ_INTENT_BROKER_ACCEPTED:
            return to==MSZZ_INTENT_PARTIALLY_FILLED || to==MSZZ_INTENT_FILLED ||
                   to==MSZZ_INTENT_POSITION_ACTIVE;
         case MSZZ_INTENT_BROKER_REJECTED:
            return false; // only the universal escape hatches above apply
         case MSZZ_INTENT_RESULT_UNKNOWN:
            return false; // only the universal escape hatches above apply
         case MSZZ_INTENT_PARTIALLY_FILLED:
            return to==MSZZ_INTENT_FILLED || to==MSZZ_INTENT_POSITION_ACTIVE;
         case MSZZ_INTENT_FILLED:
            return to==MSZZ_INTENT_POSITION_ACTIVE;
         case MSZZ_INTENT_POSITION_ACTIVE:
            return to==MSZZ_INTENT_POSITION_CLOSED || to==MSZZ_INTENT_PROTECTION_FAILED;
         case MSZZ_INTENT_PROTECTION_FAILED:
            return to==MSZZ_INTENT_POSITION_CLOSED;
         case MSZZ_INTENT_RECOVERY_REQUIRED:
            return to==MSZZ_INTENT_POSITION_ACTIVE || to==MSZZ_INTENT_POSITION_CLOSED;
         default:
            return false;
      }
   }

   // On success: sets intent.execution_state and returns true. On failure:
   // leaves intent completely unchanged (not partially mutated) and returns
   // false with a human-readable reason. The caller decides what "fail
   // closed" means in its own context -- this class never mutates state on
   // a rejected transition, by construction.
   static bool TryTransition(MSZZExecutionIntent &intent,const ENUM_MSZZ_INTENT_STATE new_state,string &reason)
   {
      ENUM_MSZZ_INTENT_STATE current=(ENUM_MSZZ_INTENT_STATE)intent.execution_state;
      if(!IsLegalTransition(current,new_state))
      {
         reason=StringFormat("illegal transition %s -> %s",
                              MSZZIntentStateText(current),MSZZIntentStateText(new_state));
         return false;
      }
      intent.execution_state=(int)new_state;
      reason="";
      return true;
   }
};

#endif
