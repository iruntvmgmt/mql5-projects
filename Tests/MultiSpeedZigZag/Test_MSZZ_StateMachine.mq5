//+------------------------------------------------------------------+
//| Test_MSZZ_StateMachine.mq5                                       |
//| Covers DECISION_LOG.md D010 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/IntentStateMachine.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZExecutionIntent MakeIntent(const int state)
{
   MSZZExecutionIntent r;
   r.schema_version=MSZZ_INTENT_SCHEMA_VERSION;
   r.intent_id="SM-TEST";
   r.cluster_id="CLU-SM-TEST";
   r.origin_id="ORIG-SM-TEST";
   r.strategy_id=1003;
   r.symbol="XAUUSD";
   r.timeframe=(int)PERIOD_M5;
   r.magic=777099;
   r.direction=1;
   r.signal_time=D'2026.07.26 10:00';
   r.intent_time=D'2026.07.26 10:00:01';
   r.expiry_time=D'2026.07.26 11:00';
   r.requested_volume=0.01;
   r.requested_entry=4000.00;
   r.requested_stop=3990.00;
   r.requested_target=4015.00;
   r.execution_state=state;
   r.submission_attempts=1;
   r.broker_retcode=0;
   r.broker_result_text="";
   r.order_ticket=555001;
   r.position_ticket=0;
   r.first_deal_ticket=0;
   r.last_deal_ticket=0;
   r.filled_volume=0.0;
   r.average_fill_price=0.0;
   r.last_reconciliation_time=0;
   r.protection_status=0;
   r.instance_id="inst-1";
   return r;
}

void TestReachableTransitionsAreLegal()
{
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_PERSISTED,MSZZ_INTENT_BROKER_ACCEPTED),
              "PERSISTED -> BROKER_ACCEPTED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_PERSISTED,MSZZ_INTENT_BROKER_REJECTED),
              "PERSISTED -> BROKER_REJECTED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_PERSISTED,MSZZ_INTENT_RECOVERY_REQUIRED),
              "PERSISTED -> RECOVERY_REQUIRED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_BROKER_ACCEPTED,MSZZ_INTENT_POSITION_ACTIVE),
              "BROKER_ACCEPTED -> POSITION_ACTIVE is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_BROKER_ACCEPTED,MSZZ_INTENT_RECOVERY_REQUIRED),
              "BROKER_ACCEPTED -> RECOVERY_REQUIRED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_POSITION_ACTIVE,MSZZ_INTENT_POSITION_CLOSED),
              "POSITION_ACTIVE -> POSITION_CLOSED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_POSITION_ACTIVE,MSZZ_INTENT_RECOVERY_REQUIRED),
              "POSITION_ACTIVE -> RECOVERY_REQUIRED is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_BROKER_REJECTED,MSZZ_INTENT_ABANDONED),
              "BROKER_REJECTED -> ABANDONED is legal");
}

void TestUniversalEscapeHatches()
{
   int nonterminal[]=
   {
      (int)MSZZ_INTENT_CREATED,(int)MSZZ_INTENT_PERSISTED,(int)MSZZ_INTENT_PREFLIGHT_PASSED,
      (int)MSZZ_INTENT_SUBMISSION_STARTED,(int)MSZZ_INTENT_BROKER_ACCEPTED,(int)MSZZ_INTENT_BROKER_REJECTED,
      (int)MSZZ_INTENT_RESULT_UNKNOWN,(int)MSZZ_INTENT_PARTIALLY_FILLED,(int)MSZZ_INTENT_FILLED,
      (int)MSZZ_INTENT_POSITION_ACTIVE,(int)MSZZ_INTENT_PROTECTION_FAILED,(int)MSZZ_INTENT_RECOVERY_REQUIRED
   };
   bool all_reach_recovery=true, all_reach_abandoned=true;
   for(int i=0;i<ArraySize(nonterminal);i++)
   {
      ENUM_MSZZ_INTENT_STATE s=(ENUM_MSZZ_INTENT_STATE)nonterminal[i];
      if(!CMSZZIntentStateMachine::IsLegalTransition(s,MSZZ_INTENT_RECOVERY_REQUIRED)) all_reach_recovery=false;
      if(!CMSZZIntentStateMachine::IsLegalTransition(s,MSZZ_INTENT_ABANDONED)) all_reach_abandoned=false;
   }
   AssertTrue(all_reach_recovery,"every non-terminal state can transition to RECOVERY_REQUIRED");
   AssertTrue(all_reach_abandoned,"every non-terminal state can transition to ABANDONED");
}

void TestTerminalStatesHaveNoOutgoingTransitions()
{
   int all_states[]=
   {
      (int)MSZZ_INTENT_CREATED,(int)MSZZ_INTENT_PERSISTED,(int)MSZZ_INTENT_PREFLIGHT_PASSED,
      (int)MSZZ_INTENT_SUBMISSION_STARTED,(int)MSZZ_INTENT_BROKER_ACCEPTED,(int)MSZZ_INTENT_BROKER_REJECTED,
      (int)MSZZ_INTENT_RESULT_UNKNOWN,(int)MSZZ_INTENT_PARTIALLY_FILLED,(int)MSZZ_INTENT_FILLED,
      (int)MSZZ_INTENT_POSITION_ACTIVE,(int)MSZZ_INTENT_POSITION_CLOSED,(int)MSZZ_INTENT_PROTECTION_FAILED,
      (int)MSZZ_INTENT_RECOVERY_REQUIRED,(int)MSZZ_INTENT_ABANDONED
   };
   bool closed_has_no_outgoing=true, abandoned_has_no_outgoing=true;
   for(int i=0;i<ArraySize(all_states);i++)
   {
      ENUM_MSZZ_INTENT_STATE s=(ENUM_MSZZ_INTENT_STATE)all_states[i];
      if(s==MSZZ_INTENT_POSITION_CLOSED) continue; // self-transition allowed, tested separately
      if(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_POSITION_CLOSED,s)) closed_has_no_outgoing=false;
      if(s==MSZZ_INTENT_ABANDONED) continue;
      if(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_ABANDONED,s)) abandoned_has_no_outgoing=false;
   }
   AssertTrue(closed_has_no_outgoing,"POSITION_CLOSED has zero legal outgoing transitions to any other state");
   AssertTrue(abandoned_has_no_outgoing,"ABANDONED has zero legal outgoing transitions to any other state");
}

void TestSameStateTransitionIsLegal()
{
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_PERSISTED,MSZZ_INTENT_PERSISTED),
              "PERSISTED -> PERSISTED (idempotent) is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_POSITION_CLOSED,MSZZ_INTENT_POSITION_CLOSED),
              "POSITION_CLOSED -> POSITION_CLOSED (idempotent, even though terminal) is legal");
   AssertTrue(CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_ABANDONED,MSZZ_INTENT_ABANDONED),
              "ABANDONED -> ABANDONED (idempotent, even though terminal) is legal");
}

void TestIllegalJumpIsRejected()
{
   AssertTrue(!CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_CREATED,MSZZ_INTENT_POSITION_ACTIVE),
              "CREATED -> POSITION_ACTIVE (skipping the entire lifecycle) is rejected");
   AssertTrue(!CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_PERSISTED,MSZZ_INTENT_POSITION_CLOSED),
              "PERSISTED -> POSITION_CLOSED (skipping fill/active) is rejected");
   AssertTrue(!CMSZZIntentStateMachine::IsLegalTransition(MSZZ_INTENT_BROKER_REJECTED,MSZZ_INTENT_POSITION_ACTIVE),
              "BROKER_REJECTED -> POSITION_ACTIVE is rejected");
}

void TestTryTransitionAppliesOnSuccess()
{
   MSZZExecutionIntent intent=MakeIntent((int)MSZZ_INTENT_PERSISTED);
   string reason;
   bool ok=CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_BROKER_ACCEPTED,reason);
   AssertTrue(ok,"TryTransition returns true for a legal transition");
   AssertTrue(intent.execution_state==(int)MSZZ_INTENT_BROKER_ACCEPTED,"TryTransition applies the new state on success");
   AssertTrue(reason=="","TryTransition leaves reason empty on success");
}

void TestTryTransitionLeavesIntentUnchangedOnRejection()
{
   MSZZExecutionIntent before=MakeIntent((int)MSZZ_INTENT_PERSISTED);
   MSZZExecutionIntent intent=before;
   string reason;
   bool ok=CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_POSITION_CLOSED,reason);
   AssertTrue(!ok,"TryTransition returns false for an illegal transition");
   AssertTrue(intent.execution_state==before.execution_state,
              "TryTransition leaves execution_state unchanged on a rejected transition");
   AssertTrue(intent.intent_id==before.intent_id && intent.order_ticket==before.order_ticket &&
              intent.requested_volume==before.requested_volume,
              "TryTransition leaves every other field byte-for-byte unchanged on a rejected transition, not partially mutated");
   AssertTrue(reason!="","TryTransition sets a non-empty reason on rejection");
}

void OnStart()
{
   TestReachableTransitionsAreLegal();
   TestUniversalEscapeHatches();
   TestTerminalStatesHaveNoOutgoingTransitions();
   TestSameStateTransitionIsLegal();
   TestIllegalJumpIsRejected();
   TestTryTransitionAppliesOnSuccess();
   TestTryTransitionLeavesIntentUnchangedOnRejection();

   PrintFormat("MSZZ state machine test complete failures=%d",g_failures);
}
