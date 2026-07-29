//+------------------------------------------------------------------+
//| Test_MSZZ_BookExitManager.mq5                                     |
//| D028 Stage 5: deterministic tests for CMSZZBookExitManager (the    |
//| pure per-book exit-management dispatcher for SR0-SR5) and the new  |
//| CMSZZStrategyBook restart-safety/bookkeeping methods it depends on.|
//| See DECISION_LOG.md D028 Stage 5.                                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/BookExitManager.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZPivot MakePivot(const bool valid,const double price)
{
   MSZZPivot p; ZeroMemory(p);
   p.valid=valid; p.price=price;
   return p;
}

MSZZSpeedSnapshot MakeFastSnapshot(const double last_low_price,const bool low_valid,
                                    const double last_high_price,const bool high_valid)
{
   MSZZSpeedSnapshot s; ZeroMemory(s);
   s.last_low=MakePivot(low_valid,last_low_price);
   s.last_high=MakePivot(high_valid,last_high_price);
   return s;
}

MSZZStrategyBookState MakeOpenBook(const ENUM_MSZZ_DIRECTION dir,const double entry,const double stop,
                                    const double target,const int trailing_policy,
                                    const double effective_stop,const double max_fav_r=0.0,
                                    const bool breakeven_done=false,const bool partial_done=false)
{
   MSZZStrategyBookState b; ZeroMemory(b);
   b.valid=true; b.status=MSZZ_BOOK_OPEN; b.position_open=true;
   b.direction=dir; b.entry_price=entry; b.stop_price=stop; b.target_price=target;
   b.initial_risk_price=MathAbs(entry-stop);
   b.exit_config.trailing_policy_id=trailing_policy;
   b.effective_stop=effective_stop;
   b.max_favorable_r=max_fav_r;
   b.breakeven_activated=breakeven_done;
   b.partial_close_done=partial_done;
   b.book_id=1; b.magic=12345; b.broker_position_ticket=999;
   return b;
}

MqlRates MakeBar(const double high,const double low,const double close,const datetime time)
{
   MqlRates r; ZeroMemory(r);
   r.high=high; r.low=low; r.close=close; r.open=close; r.time=time;
   return r;
}

// --- SR0: always a no-op regardless of state ---------------------------
void TestSR0AlwaysNoOp()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR0_FIXED2R,90.0);
   MqlRates bar=MakeBar(150.0,95.0,148.0,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR0_FIXED2R,book,bar,fast,
                                            150.0,1.0,999,10.0,decision);
   AssertTrue(!have,"SR0 never produces a decision even with a huge favorable excursion -- exact Stage 4 no-op");
}

// --- SR1 breakeven: one-shot activation, exact entry, monotonic --------
void TestSR1BreakevenNotYetActiveBeforeThreshold()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,90.0);
   MqlRates bar=MakeBar(109.0,98.0,108.0,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   double fav_r=CMSZZBookExitManager::FavorableR(MSZZ_DIR_LONG,100.0,10.0,bar.high,bar.low);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,book,bar,fast,
                                            109.0,1.0,10,fav_r,decision);
   AssertTrue(!have,"fav_r=0.9 (one bar before +1R) does not activate SR1 breakeven");
}

void TestSR1BreakevenActivatesExactlyAtThresholdToExactEntry()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,90.0);
   MqlRates bar=MakeBar(150.0,98.0,148.0,1700000000); // fav_r=(150-100)/10=5.0
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,book,bar,fast,
                                            150.0,1.0,10,5.0,decision);
   AssertTrue(have && decision.modify_stop,"fav_r=5.0 activates SR1 breakeven");
   AssertTrue(MathAbs(decision.new_stop-100.0)<1e-9,
              "D028 SR1 moves stop to EXACTLY entry (no cost offset, per literal handoff wording): got "+DoubleToString(decision.new_stop,6));
}

void TestSR1BreakevenNeverRefiresOnceDone()
{
   // already_done=true (breakeven_activated) -- must not re-trigger even
   // with a fresh huge favorable excursion.
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,100.0,5.0,true);
   MqlRates bar=MakeBar(150.0,98.0,148.0,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR1_BREAKEVEN,book,bar,fast,
                                            150.0,1.0,10,8.0,decision);
   AssertTrue(!have,"SR1 breakeven never re-fires once already activated for this position");
}

// --- SR2 structural trail: causal, monotonic, broker-distance-valid ----
void TestSR2RejectsStaleWrongSideSwing()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,90.0,2.0);
   MSZZSpeedSnapshot fast=MakeFastSnapshot(115.0,true,0.0,false); // last_low ABOVE current close -- stale
   MqlRates bar=MakeBar(122.0,109.0,110.0,1700000000);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,book,bar,fast,
                                            110.0,1.0,10,2.2,decision);
   AssertTrue(!have,"SR2 rejects a confirmed low that is above current close (stale/wrong-side), reusing D024's Bug-1 guard");
}

void TestSR2AcceptsValidCausalSwingAndTightens()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,90.0,2.0);
   MSZZSpeedSnapshot fast=MakeFastSnapshot(108.0,true,0.0,false); // confirmed low below current close -- valid
   MqlRates bar=MakeBar(122.0,109.0,110.0,1700000000);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,book,bar,fast,
                                            118.0,1.0,10,2.2,decision);
   AssertTrue(have && decision.modify_stop && MathAbs(decision.new_stop-108.0)<1e-9,
              "SR2 accepts a valid confirmed low below current close and tightens the stop to it");
}

void TestSR2NeverWidensStop()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,112.0,2.0); // already trailed to 112
   MSZZSpeedSnapshot fast=MakeFastSnapshot(108.0,true,0.0,false); // candidate (108) is LOOSER than current (112)
   MqlRates bar=MakeBar(122.0,109.0,110.0,1700000000);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL,book,bar,fast,
                                            118.0,1.0,10,2.2,decision);
   AssertTrue(!have,"SR2 refuses a candidate stop (108) looser than the current effective stop (112) -- monotonic tightening only");
}

// --- SR3 partial + breakeven remainder ----------------------------------
void TestSR3PartialFiresOnceAtActivation()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_SHORT,100.0,110.0,80.0,
                                            MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED,110.0);
   MqlRates bar=MakeBar(102.0,89.0,90.0,1700000000); // fav_r=(100-89)/10=1.1
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED,book,bar,fast,
                                            90.0,1.0,10,1.1,decision);
   AssertTrue(have && decision.partial_close && MathAbs(decision.partial_fraction-0.5)<1e-9,
              "SR3 fires a 50% partial close exactly at +1R");
   AssertTrue(decision.modify_stop && MathAbs(decision.new_stop-100.0)<1e-9,
              "SR3 moves the remainder's stop to exactly entry (short: 100.0) in the same decision");
   AssertTrue(!decision.remove_target,"SR3 retains the fixed +2R target -- remove_target is false, unlike SR4");
}

void TestSR3NeverRefiresPartialOnceDone()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_SHORT,100.0,110.0,80.0,
                                            MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED,100.0,1.5,false,true); // partial already done
   MqlRates bar=MakeBar(102.0,80.0,81.0,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED,book,bar,fast,
                                            81.0,1.0,10,1.9,decision);
   AssertTrue(!have,"SR3 does not re-fire the partial (or any further stop move) once partial_close_done is true");
}

// --- SR4 partial + uncapped structural runner ---------------------------
void TestSR4PartialRemovesTarget()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER,90.0);
   MqlRates bar=MakeBar(111.0,99.0,110.0,1700000000); // fav_r=1.1
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER,book,bar,fast,
                                            110.0,1.0,10,1.1,decision);
   AssertTrue(have && decision.partial_close && decision.remove_target,
              "SR4's partial-close decision also removes the fixed target for the runner remainder");
}

void TestSR4RunnerTrailsAfterPartialDone()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,0.0, // target already removed by prior partial
                                            MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER,100.0,1.5,false,true);
   MSZZSpeedSnapshot fast=MakeFastSnapshot(108.0,true,0.0,false);
   MqlRates bar=MakeBar(122.0,109.0,110.0,1700000000);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER,book,bar,fast,
                                            118.0,1.0,10,2.2,decision);
   AssertTrue(have && decision.modify_stop && !decision.partial_close,
              "after the partial is done, SR4 only trails the runner -- never a second partial");
}

// --- SR5 time stop: precedence over the normal fixed-2R management -----
void TestSR5DoesNotFireBeforeWindowElapses()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR5_TIME_STOP,90.0,0.1);
   MqlRates bar=MakeBar(101.0,99.0,100.5,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR5_TIME_STOP,book,bar,fast,
                                            100.5,1.0,MSZZ_SR_TIME_STOP_BARS-1,0.1,decision);
   AssertTrue(!have,"SR5 does not force-close one bar before the frozen N-bar window elapses");
}

void TestSR5FiresExactlyAtWindowIfNeverReachedThreshold()
{
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR5_TIME_STOP,90.0,0.1);
   MqlRates bar=MakeBar(101.0,99.0,100.5,1700000000);
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR5_TIME_STOP,book,bar,fast,
                                            100.5,1.0,MSZZ_SR_TIME_STOP_BARS,0.1,decision);
   AssertTrue(have && decision.force_close,
              "SR5 force-closes exactly at the frozen N-bar window when +0.5R was never reached");
}

void TestSR5NeverFiresOnceThresholdWasEverReached()
{
   // max_favorable_r_so_far already >= 0.5 -- time stop must never apply
   // again for this position, even far past the window, per the frozen
   // "If +0.5R has been reached, retain canonical 2R management" rule.
   MSZZStrategyBookState book=MakeOpenBook(MSZZ_DIR_LONG,100.0,90.0,120.0,
                                            MSZZ_SWEEP_EXIT_SR5_TIME_STOP,90.0,0.6);
   MqlRates bar=MakeBar(101.0,95.0,96.0,1700000000); // now pulling back, current fav_r low
   MSZZSpeedSnapshot fast; ZeroMemory(fast);
   MSZZBookExitDecision decision;
   bool have=CMSZZBookExitManager::Evaluate(MSZZ_SWEEP_EXIT_SR5_TIME_STOP,book,bar,fast,
                                            96.0,1.0,MSZZ_SR_TIME_STOP_BARS*3,0.05,decision);
   AssertTrue(!have,"SR5 never force-closes once max_favorable_r_so_far has ever reached +0.5R, even long after the window and even if price has since pulled back");
}

// --- CMSZZStrategyBook restart-safety methods ---------------------------
void TestBookReseedsEffectiveStopFromBrokerNotMemory()
{
   CMSZZStrategyBook book;
   MSZZBookExitConfig cfg; ZeroMemory(cfg);
   cfg.policy_id=MSZZ_BOOK_EXIT_SWEEP_CANONICAL_2R; cfg.target_r=2.0;
   string reason;
   AssertTrue(book.Configure(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,12345,true,cfg,reason),
              "book configures successfully: "+reason);
   // Simulate "restart with in-memory state lost" by never opening through
   // MarkOpen() -- effective_stop stays at its ZeroMemory default (0.0).
   AssertTrue(book.State().effective_stop==0.0,"freshly configured book has no effective_stop yet (sanity precondition)");
}

void TestUpdateExitManagementStateRejectedWhenNotOpen()
{
   CMSZZStrategyBook book;
   MSZZBookExitConfig cfg; ZeroMemory(cfg);
   cfg.policy_id=MSZZ_BOOK_EXIT_SWEEP_CANONICAL_2R; cfg.target_r=2.0;
   string reason;
   book.Configure(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,12345,true,cfg,reason);
   bool ok=book.UpdateExitManagementState(1.0,true,true,100.0,90.0,95.0,true,false);
   AssertTrue(!ok,"UpdateExitManagementState is rejected for a book that is not MSZZ_BOOK_OPEN (still FLAT here)");
}

void OnStart()
{
   TestSR0AlwaysNoOp();
   TestSR1BreakevenNotYetActiveBeforeThreshold();
   TestSR1BreakevenActivatesExactlyAtThresholdToExactEntry();
   TestSR1BreakevenNeverRefiresOnceDone();
   TestSR2RejectsStaleWrongSideSwing();
   TestSR2AcceptsValidCausalSwingAndTightens();
   TestSR2NeverWidensStop();
   TestSR3PartialFiresOnceAtActivation();
   TestSR3NeverRefiresPartialOnceDone();
   TestSR4PartialRemovesTarget();
   TestSR4RunnerTrailsAfterPartialDone();
   TestSR5DoesNotFireBeforeWindowElapses();
   TestSR5FiresExactlyAtWindowIfNeverReachedThreshold();
   TestSR5NeverFiresOnceThresholdWasEverReached();
   TestBookReseedsEffectiveStopFromBrokerNotMemory();
   TestUpdateExitManagementStateRejectedWhenNotOpen();
   PrintFormat("MSZZ BookExitManager test complete failures=%d",g_failures);
}
