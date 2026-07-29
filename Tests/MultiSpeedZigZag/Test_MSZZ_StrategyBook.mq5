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

   PrintFormat("TEST_SUMMARY tests=16 failures=%d",failures);
}
