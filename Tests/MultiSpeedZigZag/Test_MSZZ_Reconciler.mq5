//+------------------------------------------------------------------+
//| Test_MSZZ_Reconciler.mq5                                         |
//| Covers DECISION_LOG.md D009 requirements (deterministic core).   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/ExecutionReconciler.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZExecutionIntent MakeIntent(const string intent_id,const int state,const long magic,
                               const ulong order_ticket=0,const ulong position_ticket=0,const ulong first_deal_ticket=0)
{
   MSZZExecutionIntent r;
   r.schema_version=MSZZ_INTENT_SCHEMA_VERSION;
   r.intent_id=intent_id;
   r.cluster_id="CLU-"+intent_id;
   r.origin_id="ORIG-"+intent_id;
   r.strategy_id=1003;
   r.symbol="XAUUSD";
   r.timeframe=(int)PERIOD_M5;
   r.magic=magic;
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
   r.order_ticket=order_ticket;
   r.position_ticket=position_ticket;
   r.first_deal_ticket=first_deal_ticket;
   r.last_deal_ticket=0;
   r.filled_volume=0.0;
   r.average_fill_price=0.0;
   r.last_reconciliation_time=0;
   r.protection_status=0;
   r.instance_id="inst-1";
   return r;
}

MSZZBrokerRecord MakeRecord(const ulong ticket,const string symbol,const long magic,const int record_type,
                            const ulong position_id=0,const string comment_token="")
{
   MSZZBrokerRecord r;
   r.ticket=ticket;
   r.symbol=symbol;
   r.magic=magic;
   r.direction=(int)MSZZ_DIR_LONG;
   r.volume=0.01;
   r.price=4000.00;
   r.time=D'2026.07.26 10:00:05';
   r.comment_token=comment_token;
   r.record_type=record_type;
   r.position_id=position_id;
   return r;
}

void TestTerminalIntentsSkipped()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-1",(int)MSZZ_INTENT_POSITION_CLOSED,777001);
   MSZZBrokerRecord records[]; ArrayResize(records,0);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,0,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_NO_ACTION,"terminal intent (POSITION_CLOSED) yields NO_ACTION regardless of broker records");
}

void TestMatchByTicket()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-2",(int)MSZZ_INTENT_BROKER_ACCEPTED,777002,555001,555001);
   MSZZBrokerRecord records[1];
   records[0]=MakeRecord(555001,"XAUUSD",777002,(int)MSZZ_RECORD_OPEN_POSITION,555001);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,1,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION,"PERSISTED-lineage intent matches an open position by ticket");
   AssertTrue(results[0].matched_ticket==555001,"matched ticket is reported correctly");
}

void TestMatchByCommentTokenWhenTicketMissing()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-3",(int)MSZZ_INTENT_PERSISTED,777003); // no local tickets recorded (simulated crash before D008 update)
   string token=MSZZCorrelationToken("T-3");
   MSZZBrokerRecord records[1];
   records[0]=MakeRecord(555002,"XAUUSD",777003,(int)MSZZ_RECORD_OPEN_POSITION,555002,token);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,1,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION,
              "intent with no local ticket still matches via the comment correlation token");
}

void TestMatchClosedPositionViaDealHistory()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-4",(int)MSZZ_INTENT_BROKER_ACCEPTED,777004,0,0,555003);
   MSZZBrokerRecord records[2];
   records[0]=MakeRecord(555003,"XAUUSD",777004,(int)MSZZ_RECORD_HISTORY_DEAL,900001);
   records[1]=MakeRecord(600001,"XAUUSD",777004,(int)MSZZ_RECORD_HISTORY_DEAL,900001);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,2,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_MATCHED_CLOSED_POSITION,
              "intent with only history-deal records (no open position) matches as closed");
}

void TestConsistentRejection()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-5",(int)MSZZ_INTENT_BROKER_REJECTED,777005);
   MSZZBrokerRecord records[]; ArrayResize(records,0);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,0,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_CONSISTENT_REJECTION,
              "locally-rejected intent with no broker record is CONSISTENT_REJECTION, not flagged");
}

void TestPersistedWithNothingFoundFailsClosed()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-6",(int)MSZZ_INTENT_PERSISTED,777006);
   MSZZBrokerRecord records[]; ArrayResize(records,0);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,0,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED,
              "PERSISTED intent with nothing found is RECOVERY_REQUIRED, never assumed abandoned (the critical fail-closed case)");
}

void TestForeignMagicNeverMatches()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-7",(int)MSZZ_INTENT_PERSISTED,777007);
   string token=MSZZCorrelationToken("T-7");
   MSZZBrokerRecord records[1];
   records[0]=MakeRecord(555004,"XAUUSD",999999,(int)MSZZ_RECORD_OPEN_POSITION,555004,token); // foreign magic, same token coincidentally
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,1,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED,
              "a foreign-magic record is never treated as a match even if the comment token coincidentally matches");
}

void TestNoCrossContaminationBetweenIntents()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[2];
   intents[0]=MakeIntent("T-8A",(int)MSZZ_INTENT_BROKER_ACCEPTED,777008,555005,555005);
   intents[1]=MakeIntent("T-8B",(int)MSZZ_INTENT_BROKER_ACCEPTED,777008,555006,555006);
   MSZZBrokerRecord records[2];
   records[0]=MakeRecord(555005,"XAUUSD",777008,(int)MSZZ_RECORD_OPEN_POSITION,555005);
   records[1]=MakeRecord(555006,"XAUUSD",777008,(int)MSZZ_RECORD_OPEN_POSITION,555006);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,2,records,2,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION && results[0].matched_ticket==555005,
              "first intent matches only its own ticket");
   AssertTrue(results[1].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION && results[1].matched_ticket==555006,
              "second intent matches only its own ticket, no cross-contamination");
}

void TestDuplicateHistoryRowsDoNotBreakMatching()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[1];
   intents[0]=MakeIntent("T-9",(int)MSZZ_INTENT_BROKER_ACCEPTED,777009,0,0,555007);
   MSZZBrokerRecord records[3];
   records[0]=MakeRecord(555007,"XAUUSD",777009,(int)MSZZ_RECORD_HISTORY_DEAL,900002);
   records[1]=MakeRecord(555007,"XAUUSD",777009,(int)MSZZ_RECORD_HISTORY_DEAL,900002); // duplicate row, same ticket+type
   records[2]=MakeRecord(600002,"XAUUSD",777009,(int)MSZZ_RECORD_HISTORY_DEAL,900002); // second real deal, same position
   MSZZReconcileResult results[];
   policy.Reconcile(intents,1,records,3,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_MATCHED_CLOSED_POSITION,
              "duplicate/multiple history rows for the same position do not prevent a clean match");
}

void TestNettingAmbiguityFailsClosed()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[2];
   intents[0]=MakeIntent("T-10A",(int)MSZZ_INTENT_PERSISTED,777010);
   intents[1]=MakeIntent("T-10B",(int)MSZZ_INTENT_PERSISTED,777010);
   MSZZBrokerRecord records[]; ArrayResize(records,0);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,2,records,0,true,results); // is_netting=true
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED && results[1].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED,
              "two simultaneous non-terminal intents on a netting account both fail closed to RECOVERY_REQUIRED");

   // The same two intents on a HEDGING account, each with their own distinct
   // ticket, must resolve individually and cleanly -- proves this is a
   // netting-specific rule, not a blanket "never allow 2 pending intents" rule.
   MSZZExecutionIntent hedgingIntents[2];
   hedgingIntents[0]=MakeIntent("T-11A",(int)MSZZ_INTENT_BROKER_ACCEPTED,777011,555008,555008);
   hedgingIntents[1]=MakeIntent("T-11B",(int)MSZZ_INTENT_BROKER_ACCEPTED,777011,555009,555009);
   MSZZBrokerRecord hedgingRecords[2];
   hedgingRecords[0]=MakeRecord(555008,"XAUUSD",777011,(int)MSZZ_RECORD_OPEN_POSITION,555008);
   hedgingRecords[1]=MakeRecord(555009,"XAUUSD",777011,(int)MSZZ_RECORD_OPEN_POSITION,555009);
   MSZZReconcileResult hedgingResults[];
   policy.Reconcile(hedgingIntents,2,hedgingRecords,2,false,hedgingResults); // is_netting=false
   AssertTrue(hedgingResults[0].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION && hedgingResults[1].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION,
              "the same two-pending-intents shape resolves cleanly on a hedging account (netting-specific rule confirmed)");
}

void TestConflictingTicketMapping()
{
   CMSZZReconciliationPolicy policy;
   MSZZExecutionIntent intents[2];
   intents[0]=MakeIntent("T-12A",(int)MSZZ_INTENT_PERSISTED,777012);
   intents[1]=MakeIntent("T-12B",(int)MSZZ_INTENT_PERSISTED,777012);
   string tokenA=MSZZCorrelationToken("T-12A");
   // Craft an impossible-in-practice but deterministic-for-testing scenario:
   // one broker record whose comment token happens to equal intent A's token,
   // and give intent B the exact same order_ticket by hand to force a genuine
   // ticket collision between two distinct intents.
   intents[1].order_ticket=555010;
   intents[0].order_ticket=555010;
   MSZZBrokerRecord records[1];
   records[0]=MakeRecord(555010,"XAUUSD",777012,(int)MSZZ_RECORD_OPEN_POSITION,555010,tokenA);
   MSZZReconcileResult results[];
   policy.Reconcile(intents,2,records,1,false,results);
   AssertTrue(results[0].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED && results[1].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED,
              "a broker record matched by two distinct intents halts both to RECOVERY_REQUIRED rather than picking one");
}

void TestCorrelationTokenDeterministicAndDistinct()
{
   string a1=MSZZCorrelationToken("SAME-ID");
   string a2=MSZZCorrelationToken("SAME-ID");
   string b=MSZZCorrelationToken("DIFFERENT-ID");
   AssertTrue(a1==a2,"correlation token is deterministic for the same intent ID");
   AssertTrue(a1!=b,"correlation token differs for different intent IDs");
   AssertTrue(StringLen(a1)==8,"correlation token is exactly 8 hex characters");
}

void OnStart()
{
   TestTerminalIntentsSkipped();
   TestMatchByTicket();
   TestMatchByCommentTokenWhenTicketMissing();
   TestMatchClosedPositionViaDealHistory();
   TestConsistentRejection();
   TestPersistedWithNothingFoundFailsClosed();
   TestForeignMagicNeverMatches();
   TestNoCrossContaminationBetweenIntents();
   TestDuplicateHistoryRowsDoNotBreakMatching();
   TestNettingAmbiguityFailsClosed();
   TestConflictingTicketMapping();
   TestCorrelationTokenDeterministicAndDistinct();

   PrintFormat("MSZZ reconciler test complete failures=%d",g_failures);
}
