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
   // Tick-boundary epsilon: raw/tick lands a hair above an integer tick count.
   // Certified behavior subtracts 1e-9 before MathCeil so the value stays on the
   // lower tick (mirrors the Python policy correction of the same F15 divergence).
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::NormalizeStop(-1,100.05000000000001,100.0,0.05)-100.05)<1e-8,
         "short stop honors boundary epsilon (100.05 not 100.10)");
   Check(MathAbs(CMSZZScreeningExecutionPolicyV2::NormalizeTarget(-1,99.80000000000001,100.0,0.05)-99.8)<1e-8,
         "short target honors boundary epsilon (99.80 not 99.85)");
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
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",12,g_failures);
}
