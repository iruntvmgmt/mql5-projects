#property strict
#property script_show_inputs
#include <MultiSpeedZigZag/Research/ScreeningExecutionPolicyV2.mqh>

int g_failures=0;
void Check(const bool ok,const string what)
{
   if(!ok) { PrintFormat("FAIL: %s",what); g_failures++; }
   else PrintFormat("PASS: %s",what);
}

void OnStart()
{
   MSZZScreeningPolicyV2 p=CMSZZScreeningExecutionPolicyV2::Canonical();
   string reason="";
   Check(CMSZZScreeningExecutionPolicyV2::Validate(p,reason),"canonical policy validates");
   Check(p.entry_offset_bars==1 && p.reject_signals_while_open && !p.opposite_signal_closes,
         "next-entry and stop/target-only occupancy policy");
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::NormalizeStop(1,98.017,100.003,0.01)-98.01)<1e-8,
         "long stop rounds conservatively away from entry");
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::NormalizeStop(-1,102.017,100.003,0.01)-102.02)<1e-8,
         "short stop rounds conservatively away from entry");
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::NormalizeTarget(1,104.019,100.003,0.01)-104.01)<1e-8,
         "long target rounds conservatively");
   Check(CMSZZScreeningExecutionPolicyV2::CandidateStatus(true,100,110)==MSZZ_SCREEN_REJECT_FAMILY_OPEN,
         "open family rejects candidate");
   Check(CMSZZScreeningExecutionPolicyV2::CandidateStatus(false,111,110)==MSZZ_SCREEN_REJECT_EXPIRED,
         "expired entry rejects candidate");
   Check(CMSZZScreeningExecutionPolicyV2::ResolveBar(1,98,104,105,97)==MSZZ_SCREEN_EXIT_STOP,
         "same-bar stop and target resolves stop first");
   Check(CMSZZScreeningExecutionPolicyV2::ResolveBar(1,98,104,104,99)==MSZZ_SCREEN_EXIT_TARGET,
         "target-only bar resolves target");
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::GrossR(-1,100,102,102)-(-1.0))<1e-8,
         "short stop reports -1R");
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",10,g_failures);
}
