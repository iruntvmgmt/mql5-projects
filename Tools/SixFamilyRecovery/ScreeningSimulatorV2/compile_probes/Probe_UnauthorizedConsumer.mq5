#property strict
// NEGATIVE probe (must FAIL to compile): an ordinary research include without the
// fixture macro must NOT be able to reach the execution core. The expected
// diagnostic is recorded in expected_negative_probe.txt. Do NOT add this file to
// the regression compile roster.
#include <MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh>
void OnStart()
{
   MSZZScreeningCandidateV2 c[]; MSZZScreeningCandidateManifestV2 cm; MSZZScreeningMarketBarV2 bars[];
   MSZZScreeningMarketManifestV2 mm; MSZZScreeningInstrumentParamsV2 p; MSZZScreeningOutcomeV2 o[];
   string s=CMSZZScreeningSimulatorV2::RunScreeningCoreForFixtures(c,cm,bars,"XAUUSD",5,"x",mm,p,"POLICY",-1,o);
   Print(s,ArraySize(o));
}
