#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/CrossFamilyPolicy.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

void OnStart()
{
   int failures=0;
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,false,true)==MSZZ_CROSS_ACTION_REVERSE,
         "legacy control permits shared reverse",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_IGNORE,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,true,true)==MSZZ_CROSS_ACTION_IGNORE,
         "ignore prohibits cross-family mutation",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,true,true)==MSZZ_CROSS_ACTION_IGNORE,
         "independent books prohibit cross-family exit",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_FLATTEN_ONLY,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,false,true)==MSZZ_CROSS_ACTION_IGNORE,
         "flatten-only ignores unqualified signal",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_FLATTEN_ONLY,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,true,true)==MSZZ_CROSS_ACTION_FLATTEN,
         "flatten-only permits explicit invalidation",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_REGIME_EXCLUSIVE,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_REVERSAL,false,false)==MSZZ_CROSS_ACTION_REJECT_REGIME,
         "regime-exclusive rejects ineligible family",failures);
   Check(CMSZZCrossFamilyPolicy::Resolve(
         MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS,MSZZ_FAMILY_BREAKOUT,
         MSZZ_FAMILY_BREAKOUT,false,true)==MSZZ_CROSS_ACTION_REVERSE,
         "own-family signal retains own exit policy",failures);
   Check(CMSZZCrossFamilyPolicy::Text(MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS)=="INDEPENDENT_BOOKS",
         "policy text is deterministic",failures);
   Check(!CMSZZCrossFamilyPolicy::IsKnown((ENUM_MSZZ_CROSS_FAMILY_POLICY)99),
         "unknown policy fails validation",failures);
   PrintFormat("TEST_SUMMARY tests=9 failures=%d",failures);
}
