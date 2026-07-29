#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/VirtualNettingLedger.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

MSZZVirtualBookAllocation Allocation(const long id,
                                     const ENUM_MSZZ_STRATEGY_ID strategy,
                                     const ENUM_MSZZ_STRATEGY_FAMILY family,
                                     const ENUM_MSZZ_DIRECTION direction,
                                     const double volume)
{
   MSZZVirtualBookAllocation a; ZeroMemory(a);
   a.valid=true; a.book_id=id; a.strategy_id=strategy; a.family_id=family;
   a.direction=direction;
   a.signed_volume=(direction==MSZZ_DIR_LONG ? volume : -volume);
   a.entry_basis=3300.0;
   a.stop_price=(direction==MSZZ_DIR_LONG ? 3290.0 : 3310.0);
   a.target_price=(direction==MSZZ_DIR_LONG ? 3320.0 : 3280.0);
   a.logical_position_id="VL-"+IntegerToString(id);
   a.last_update_time=D'2026.07.01 10:00';
   return a;
}

void OnStart()
{
   int failures=0;
   string file="D028_Test_VirtualLedger.csv";
   FileDelete(file);
   CMSZZVirtualNettingLedger ledger;
   Check(ledger.Configure("XAUUSD",file),"ledger configures",failures);
   MSZZVirtualBookAllocation a=Allocation(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                                          MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_LONG,0.02);
   MSZZVirtualBookAllocation b=Allocation(2,MSZZ_STRAT_SWEEP_RECLAIM,
                                          MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.01);
   Check(ledger.Upsert(a) && ledger.Upsert(b),"opposing allocations insert",failures);
   Check(ledger.Count()==2 && MathAbs(ledger.GrossVolume()-0.03)<1e-12 &&
         MathAbs(ledger.NetSignedVolume()-0.01)<1e-12,
         "gross and net allocations reconcile",failures);
   Check(MathAbs(CMSZZVirtualNettingLedger::RequiredBrokerDelta(0.0,0.01)-0.01)<1e-12,
         "broker net increase computes",failures);
   Check(MathAbs(CMSZZVirtualNettingLedger::RequiredBrokerDelta(0.01,0.0)+0.01)<1e-12,
         "broker net reduction computes",failures);
   Check(MathAbs(CMSZZVirtualNettingLedger::RequiredBrokerDelta(0.01,-0.01)+0.02)<1e-12,
         "broker reversal through zero computes",failures);
   Check(MathAbs(CMSZZVirtualNettingLedger::AllocateCostProRata(3.0,1.0,3.0)-1.0)<1e-12,
         "cost allocation is proportional",failures);
   Check(ledger.Reduce(1,0.01,0.5,0.25),"partial close reduces allocation",failures);
   MSZZVirtualBookAllocation reduced;
   Check(ledger.AllocationAt(0,reduced) &&
         MathAbs(reduced.signed_volume-0.01)<1e-12 &&
         MathAbs(reduced.realized_r-0.5)<1e-12 &&
         MathAbs(reduced.allocated_cost-0.25)<1e-12,
         "partial close attribution survives",failures);
   Check(CMSZZVirtualNettingLedger::SyntheticStopTriggered(reduced,3289.0,3289.5),
         "long synthetic stop triggers causally",failures);
   Check(CMSZZVirtualNettingLedger::SyntheticStopTriggered(b,3310.5,3311.0),
         "short synthetic stop triggers causally",failures);
   MSZZVirtualBookAllocation a2=a; a2.book_id=3; a2.logical_position_id="VL-3";
   MSZZVirtualBookAllocation b2=b; b2.book_id=4; b2.logical_position_id="VL-4";
   Check(CMSZZVirtualNettingLedger::SyntheticStopTriggered(a2,3289.0,3289.5) &&
         CMSZZVirtualNettingLedger::SyntheticStopTriggered(b2,3310.5,3311.0),
         "simultaneous independent stop events are both observable",failures);
   Check(CMSZZVirtualNettingLedger::SyntheticTargetTriggered(a2,3321.0,3321.5) &&
         CMSZZVirtualNettingLedger::SyntheticTargetTriggered(b2,3279.0,3279.5),
         "simultaneous independent target events are both observable",failures);
   Check(ledger.Save(),"ledger state saves",failures);
   CMSZZVirtualNettingLedger restarted;
   Check(restarted.Configure("XAUUSD",file) && restarted.Load(),
         "restart state loads",failures);
   Check(restarted.Count()==2 &&
         MathAbs(restarted.NetSignedVolume())<1e-12,
         "restart allocations reconcile exactly",failures);
   MSZZVirtualBookAllocation malformed=b; malformed.logical_position_id="";
   Check(!restarted.Upsert(malformed) && restarted.LastError()!="",
         "malformed allocation fails closed",failures);
   Check(!restarted.Reduce(999,0.01,0.0,0.0) && restarted.LastError()!="",
         "unknown partial close fails closed",failures);
   int corrupt=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(corrupt!=INVALID_HANDLE) { FileWriteString(corrupt,"CORRUPT"); FileClose(corrupt); }
   Check(!restarted.Load() && restarted.LastError()=="virtual ledger header invalid",
         "malformed restart state fails closed deterministically",failures);
   FileDelete(file);
   PrintFormat("TEST_SUMMARY tests=18 failures=%d",failures);
}
