#property strict
// POSITIVE probe: a fixture build opts into the execution core via the macro and
// can call it. Must compile 0 errors / 0 warnings.
#define MSZZ_SCREENING_FIXTURE_ACCESS
#include <MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh>
void OnStart()
{
   MSZZScreeningCandidateV2 c[]; MSZZScreeningCandidateManifestV2 cm; MSZZScreeningMarketBarV2 bars[];
   MSZZScreeningMarketManifestV2 mm; MSZZScreeningInstrumentParamsV2 p; MSZZScreeningOutcomeV2 o[];
   string s=CMSZZScreeningSimulatorV2::RunScreeningCoreForFixtures(c,cm,bars,"XAUUSD",5,"x",mm,p,"POLICY",-1,o);
   Print(s,ArraySize(o));
}
