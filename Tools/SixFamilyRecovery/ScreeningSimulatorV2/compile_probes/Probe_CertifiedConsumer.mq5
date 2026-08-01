#property strict
// POSITIVE probe: a certified consumer includes only the binding adapter and can
// call the bundle-only public entry. Must compile 0 errors / 0 warnings.
#include <MultiSpeedZigZag/Research/ScreeningJournalBindingV2.mqh>
void OnStart()
{
   MSZZVerifiedScreeningJournalV2 b; MSZZScreeningMarketBarV2 bars[];
   MSZZScreeningMarketManifestV2 mm; MSZZScreeningInstrumentParamsV2 p; MSZZScreeningOutcomeV2 o[];
   string s=CMSZZScreeningJournalBindingV2::RunScreening(b,bars,"XAUUSD",5,"x",mm,p,"POLICY",-1,o);
   Print(s,ArraySize(o));
}
