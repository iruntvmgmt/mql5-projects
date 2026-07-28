//+------------------------------------------------------------------+
//| Test_MSZZ_ExecutionGuard.mq5                                      |
//| D025: deterministic tests for CMSZZExecutionGuard::ValidateStops's|
//| disable_target bypass (variant F, InpDisableFixedTarget). Default  |
//| (disable_target=false) behavior is asserted unchanged from before |
//| this change. See DECISION_LOG.md D025.                            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/ExecutionGuard.mqh>

input string InpSymbol="XAUUSD";

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZCandidate MakeCandidate(const ENUM_MSZZ_DIRECTION dir,const double entry,const double stop,const double target)
{
   MSZZCandidate c; ZeroMemory(c);
   c.direction=dir; c.entry=entry; c.stop=stop; c.target=target;
   return c;
}

void TestDefaultBehaviorUnchangedLong()
{
   CMSZZExecutionGuard guard;
   AssertTrue(guard.Load(InpSymbol),"guard loads symbol");
   double ns,nt; string reason;
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_LONG,2900.0,2890.0,2920.0);
   bool ok=guard.ValidateStops(c,ns,nt,reason);
   AssertTrue(ok,"default (disable_target=false) long with valid stop/target still passes: "+reason);
   AssertTrue(nt>0.0,"normalized_target is still populated by default");
}

void TestDefaultBehaviorUnchangedRejectsBadTarget()
{
   CMSZZExecutionGuard guard;
   guard.Load(InpSymbol);
   double ns,nt; string reason;
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_LONG,2900.0,2890.0,0.0); // no target, default mode
   bool ok=guard.ValidateStops(c,ns,nt,reason);
   AssertTrue(!ok,"default mode still rejects a zero/non-positive target (unchanged prior behavior)");
}

void TestDisableTargetAcceptsZeroTargetLong()
{
   CMSZZExecutionGuard guard;
   guard.Load(InpSymbol);
   double ns,nt; string reason;
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_LONG,2900.0,2890.0,0.0);
   bool ok=guard.ValidateStops(c,ns,nt,reason,true);
   AssertTrue(ok,"disable_target=true accepts a long with no target at all: "+reason);
   AssertTrue(nt==0.0,"normalized_target is forced to 0.0 when disable_target=true");
}

void TestDisableTargetAcceptsZeroTargetShort()
{
   CMSZZExecutionGuard guard;
   guard.Load(InpSymbol);
   double ns,nt; string reason;
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_SHORT,2900.0,2910.0,0.0);
   bool ok=guard.ValidateStops(c,ns,nt,reason,true);
   AssertTrue(ok,"disable_target=true accepts a short with no target at all: "+reason);
}

void TestDisableTargetStillValidatesStop()
{
   CMSZZExecutionGuard guard;
   guard.Load(InpSymbol);
   double ns,nt; string reason;
   // stop on the wrong side of entry for a long -- must still be rejected
   // even with disable_target=true (stop validation is unaffected).
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_LONG,2900.0,2910.0,0.0);
   bool ok=guard.ValidateStops(c,ns,nt,reason,true);
   AssertTrue(!ok,"disable_target=true still rejects an invalid (wrong-side) stop: "+reason);
}

void TestDisableTargetIgnoresGarbageTargetValue()
{
   CMSZZExecutionGuard guard;
   guard.Load(InpSymbol);
   double ns,nt; string reason;
   // even if a caller mistakenly left a real (but wrong-orientation) target
   // value set, disable_target=true must not evaluate it at all.
   MSZZCandidate c=MakeCandidate(MSZZ_DIR_LONG,2900.0,2890.0,2880.0); // target below entry -- invalid orientation if checked
   bool ok=guard.ValidateStops(c,ns,nt,reason,true);
   AssertTrue(ok,"disable_target=true ignores a leftover garbage target value entirely: "+reason);
}

void OnStart()
{
   TestDefaultBehaviorUnchangedLong();
   TestDefaultBehaviorUnchangedRejectsBadTarget();
   TestDisableTargetAcceptsZeroTargetLong();
   TestDisableTargetAcceptsZeroTargetShort();
   TestDisableTargetStillValidatesStop();
   TestDisableTargetIgnoresGarbageTargetValue();
   PrintFormat("MSZZ ExecutionGuard test complete failures=%d",g_failures);
}
