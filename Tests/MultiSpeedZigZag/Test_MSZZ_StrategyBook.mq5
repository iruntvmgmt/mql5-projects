#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

MSZZBookExitConfig ExitConfig(const double target_r)
{
   MSZZBookExitConfig c; ZeroMemory(c);
   c.policy_id=MSZZ_BOOK_EXIT_FIXED_R;
   c.target_r=target_r;
   c.own_family_opposite_exit=true;
   return c;
}

MSZZCandidate Candidate(const ENUM_MSZZ_STRATEGY_ID strategy,
                        const ENUM_MSZZ_STRATEGY_FAMILY family,
                        const ENUM_MSZZ_DIRECTION direction,
                        const string event_id)
{
   MSZZCandidate c; ZeroMemory(c);
   c.valid=true;
   c.strategy_id=strategy;
   c.family_id=family;
   c.direction=direction;
   c.signal_time=D'2026.07.01 10:00';
   c.expiry_time=D'2026.07.01 10:05';
   c.entry=3300.0;
   c.stop=(direction==MSZZ_DIR_LONG ? 3290.0 : 3310.0);
   c.target=(direction==MSZZ_DIR_LONG ? 3320.0 : 3280.0);
   c.score=8.5;
   c.origin_id="ORIGIN|"+event_id;
   c.event_id=event_id;
   c.reason="deterministic book test";
   return c;
}

void OnStart()
{
   int failures=0;
   string reason;
   CMSZZStrategyBook a,sweep,duplicate;
   MSZZBookExitConfig a_exit=ExitConfig(2.0);
   MSZZBookExitConfig sweep_exit=ExitConfig(2.0);
   Check(a.Configure(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                     27000001,true,a_exit,reason),"A book configures",failures);
   Check(sweep.Configure(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                         27000002,true,sweep_exit,reason),"Sweep book configures",failures);
   Check(a.State().book_id!=sweep.State().book_id,"book IDs are unique",failures);
   Check(a.State().magic!=sweep.State().magic,"magics are unique",failures);
   Check(!duplicate.Configure(1,MSZZ_STRAT_NONE,MSZZ_FAMILY_BREAKOUT,
                              27000001,true,a_exit,reason) && reason!="",
         "invalid strategy fails closed with diagnostic",failures);

   MSZZCandidate ac=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                              MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_LONG,"A-EVENT-1");
   Check(a.MarkEntryPending(ac,0.01,0.25,reason),"matching candidate enters pending",failures);
   MSZZStrategyBookState pending=a.State();
   Check(pending.entry_signal_id=="A-EVENT-1" &&
         pending.origin_id=="ORIGIN|A-EVENT-1" &&
         pending.logical_position_id=="MSZZB1|1|A-EVENT-1",
         "signal origin and logical identity survive handoff",failures);
   Check(a.AssignPendingLogicalPositionId("CLUSTER-1",reason) &&
         a.State().logical_position_id=="CLUSTER-1",
         "pending logical ID binds to durable cluster identity",failures);
   Check(!sweep.MarkEntryPending(ac,0.01,0.25,reason) && reason!="",
         "book rejects another strategy candidate",failures);
   Check(a.MarkOpen(a.State().logical_position_id,1001,2001,D'2026.07.01 10:01',
                    3300.0,3290.0,3320.0,0.25,reason),
         "pending entry becomes open",failures);
   Check(a.OwnsTicket(1001) && a.OwnsTicket(2001) && !a.OwnsTicket(9999),
         "book owns only its position and order tickets",failures);
   MSZZStrategyBookState before=a.State();
   Check(!a.MarkOpen("bad",1002,2002,D'2026.07.01 10:02',
                     3300.0,3300.0,3320.0,0.25,reason),
         "invalid repeated/equal-risk open fails closed",failures);
   Check(a.State().broker_position_ticket==before.broker_position_ticket,
         "failed transition does not mutate open book",failures);
   Check(a.MarkFlat("own-family exit"),"book can return flat",failures);
   Check(!a.State().position_open && a.State().broker_position_ticket==0,
         "flat transition clears position ownership",failures);

   // D029 audit remediation, Finding C: partial-protection state machine
   // (UpdatePartialProtectionState guard behavior, ReconstructProtectionStateOnRestart
   // branch coverage). See DECISION_LOG.md D029 audit remediation.
   CMSZZStrategyBook p;
   MSZZBookExitConfig p_exit=ExitConfig(2.0);
   Check(p.Configure(3,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,27000003,true,p_exit,reason),
         "protection-test book configures",failures);
   Check(!p.UpdatePartialProtectionState(MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING,1,3016.43,false),
         "UpdatePartialProtectionState rejected on a flat (not-open) book",failures);
   Check(!p.ReconstructProtectionStateOnRestart(0.55,3016.43,0.01),
         "ReconstructProtectionStateOnRestart rejected on a flat (not-open) book",failures);

   MSZZCandidate pc=Candidate(MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,MSZZ_DIR_LONG,"P-EVENT-1");
   Check(p.MarkEntryPending(pc,1.10,0.25,reason),"protection-test book enters pending",failures);
   Check(p.MarkOpen(p.State().logical_position_id,3001,4001,D'2026.07.01 10:01',
                    3300.0,3290.0,3320.0,0.25,reason),
         "protection-test book opens with logical_volume=1.10",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_NOT_STARTED,
         "protection_state starts NOT_STARTED on a freshly opened book",failures);

   Check(!p.ReconstructProtectionStateOnRestart(1.10,3290.0,0.01),
         "restart reconstruction is a no-op when broker volume matches logical_volume (no partial evident)",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_NOT_STARTED,
         "protection_state remains NOT_STARTED when no partial is evident",failures);

   Check(p.ReconstructProtectionStateOnRestart(0.55,3290.0,0.01),
         "restart reconstruction acts when broker volume shows a partial happened",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING,
         "with no recorded protection target, reconstruction fails CLOSED to PROTECTION_PENDING, never assumes protected",failures);

   Check(!p.ReconstructProtectionStateOnRestart(0.55,3300.0,0.01),
         "reconstruction is a no-op once protection_state has already been reconciled this session",failures);

   Check(p.UpdatePartialProtectionState(MSZZ_PARTIAL_NOT_STARTED,0,3300.0,false),
         "test seed: protection_state reset to NOT_STARTED with a known protection_target_stop",failures);
   Check(p.ReconstructProtectionStateOnRestart(0.55,3300.0,0.01),
         "restart reconstruction acts a second time after reseeding NOT_STARTED",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_PROTECTED &&
         MathAbs(p.State().effective_stop-3300.0)<0.001,
         "a broker stop matching the recorded target resolves to PROTECTED and reseeds effective_stop",failures);

   Check(p.UpdatePartialProtectionState(MSZZ_PARTIAL_NOT_STARTED,0,3300.0,false),
         "test seed: protection_state reset to NOT_STARTED again (mismatch case)",failures);
   Check(p.ReconstructProtectionStateOnRestart(0.55,3290.0,0.01),
         "restart reconstruction acts a third time (target mismatch case)",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING,
         "a broker stop that does NOT match the recorded target stays PROTECTION_PENDING, never silently assumed protected",failures);

   Check(p.UpdatePartialProtectionState(MSZZ_PARTIAL_PROTECTED,0,3300.0,true),
         "UpdatePartialProtectionState succeeds on an open book",failures);
   Check(p.State().protection_state==MSZZ_PARTIAL_PROTECTED && p.State().protection_remove_target,
         "protection fields persist exactly as written",failures);

   PrintFormat("TEST_SUMMARY tests=35 failures=%d",failures);
}
