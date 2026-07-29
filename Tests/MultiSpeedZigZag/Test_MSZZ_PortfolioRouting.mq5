#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/PortfolioBookRouting.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

void OnStart()
{
   int failures=0;
   Check(CMSZZPortfolioBookRouting::IsSupportedSelection(1,true,false),
         "FastMed single book supported",failures);
   Check(CMSZZPortfolioBookRouting::IsSupportedSelection(1,false,true),
         "Sweep single book supported",failures);
   Check(CMSZZPortfolioBookRouting::IsSupportedSelection(2,true,true),
         "exact combined pair supported",failures);
   Check(!CMSZZPortfolioBookRouting::IsSupportedSelection(2,true,false),
         "malformed two-count selection rejected",failures);
   Check(!CMSZZPortfolioBookRouting::IsSupportedSelection(3,true,true),
         "extra enabled strategy rejected",failures);
   string a=CMSZZPortfolioBookRouting::ConsumedKey(
      MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,"CLUSTER");
   string sweep=CMSZZPortfolioBookRouting::ConsumedKey(
      MSZZ_STRAT_SWEEP_RECLAIM,"CLUSTER");
   Check(a!="" && sweep!="" && a!=sweep,
         "duplicate keys are strategy-qualified",failures);
   Check(CMSZZPortfolioBookRouting::ConsumedKey(MSZZ_STRAT_NONE,"CLUSTER")=="",
         "unsupported strategy key fails closed",failures);
   Check(CMSZZPortfolioBookRouting::FirstStrategy()==
         MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE &&
         CMSZZPortfolioBookRouting::SecondStrategy()==MSZZ_STRAT_SWEEP_RECLAIM,
         "combined arbitration is deterministically core-first",failures);
   MSZZStrategyBookState book; ZeroMemory(book);
   book.valid=true; book.position_open=true; book.broker_position_ticket=1001;
   Check(CMSZZPortfolioBookRouting::OwnsPositionTicket(book,1001),
         "book recognizes its own ticket",failures);
   Check(!CMSZZPortfolioBookRouting::OwnsPositionTicket(book,2002),
         "book rejects foreign ticket",failures);
   Check(CMSZZPortfolioBookRouting::CloseReason(true)=="OWN_FAMILY_OPPOSITE" &&
         CMSZZPortfolioBookRouting::CloseReason(false)=="BROKER_SL_TP_OR_TEST_END",
         "close attribution reason survives reconciliation timing",failures);
   PrintFormat("TEST_SUMMARY tests=11 failures=%d",failures);
}
