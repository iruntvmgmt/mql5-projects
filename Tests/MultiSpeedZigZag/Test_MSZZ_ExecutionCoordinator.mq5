#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/ExecutionCoordinator.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

MSZZStrategyBookState Pending(const long book_id,const long magic,
                              const ENUM_MSZZ_DIRECTION direction)
{
   MSZZStrategyBookState b; ZeroMemory(b);
   b.valid=true; b.enabled=true; b.status=MSZZ_BOOK_ENTRY_PENDING;
   b.book_id=book_id; b.magic=magic; b.direction=direction;
   b.logical_volume=0.01; b.stop_price=3290.0; b.target_price=3320.0;
   b.logical_position_id="LP-"+IntegerToString(book_id);
   return b;
}

void OnStart()
{
   int failures=0;
   string reason;
   CMSZZExecutionCoordinator hedging,netting,exchange_mode;
   Check(hedging.ConfigureForMode("XAUUSD",26000000,
          MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_ACCOUNT_HEDGING,reason),
         "hedging abstraction configures",failures);
   Check(netting.ConfigureForMode("XAUUSD",26000000,
          MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_ACCOUNT_NETTING,reason),
         "netting abstraction configures",failures);
   Check(exchange_mode.ConfigureForMode("XAUUSD",26000000,
          MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_ACCOUNT_EXCHANGE,reason),
         "exchange abstraction configures",failures);
   long a_magic=hedging.BookMagic(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,1);
   long s_magic=hedging.BookMagic(MSZZ_STRAT_SWEEP_RECLAIM,2);
   Check(a_magic>0 && s_magic>0 && a_magic!=s_magic,"book magics are unique",failures);

   MSZZExecutionPlan plan;
   MSZZStrategyBookState long_book=Pending(1,a_magic,MSZZ_DIR_LONG);
   Check(hedging.BuildOpenPlan(long_book,0.0,plan,reason) &&
         plan.action==MSZZ_COORDINATOR_OPEN_PHYSICAL &&
         !plan.synthetic_protection_required &&
         MathAbs(plan.broker_delta_volume-0.01)<1e-12,
         "hedging plan isolates physical ticket",failures);
   Check(netting.BuildOpenPlan(long_book,0.0,plan,reason) &&
         plan.action==MSZZ_COORDINATOR_ADJUST_NET &&
         plan.synthetic_protection_required &&
         MathAbs(plan.broker_net_volume_after-0.01)<1e-12,
         "netting increase plans broker delta",failures);
   MSZZStrategyBookState short_book=Pending(2,s_magic,MSZZ_DIR_SHORT);
   Check(netting.BuildOpenPlan(short_book,0.01,plan,reason) &&
         MathAbs(plan.broker_net_volume_after)<1e-12 &&
         MathAbs(plan.broker_delta_volume+0.01)<1e-12,
         "netting offset reaches flat",failures);
   Check(netting.BuildOpenPlan(short_book,-0.01,plan,reason) &&
         MathAbs(plan.broker_net_volume_after+0.02)<1e-12,
         "netting same-direction allocation increases short",failures);
   Check(exchange_mode.BuildOpenPlan(long_book,-0.01,plan,reason) &&
         plan.synthetic_protection_required &&
         MathAbs(plan.broker_net_volume_after)<1e-12,
         "exchange reversal step passes through flat",failures);
   MSZZStrategyBookState invalid=long_book; invalid.status=MSZZ_BOOK_FLAT;
   Check(!hedging.BuildOpenPlan(invalid,0.0,plan,reason) && reason!="",
         "non-pending plan fails closed with diagnostic",failures);
   Check(!hedging.ConfigureForMode("XAUUSD",26000000,
          MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_ACCOUNT_UNSUPPORTED,reason),
         "unsupported mode fails closed",failures);

   PrintFormat("TEST_SUMMARY tests=11 failures=%d",failures);
}
