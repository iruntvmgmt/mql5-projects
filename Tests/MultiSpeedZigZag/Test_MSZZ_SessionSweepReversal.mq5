#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Strategies/SessionSweepReversalStrategy.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>

int g_tests=0,g_failures=0;
void Check(const bool ok,const string name)
{
   g_tests++;
   if(ok) Print("PASS: ",name);
   else { g_failures++; Print("FAIL: ",name); }
}
MqlRates Bar(const datetime t,const double low,const double high,const double close)
{
   MqlRates b; ZeroMemory(b); b.time=t; b.low=low; b.high=high;
   b.open=close; b.close=close; return b;
}
MSZZSpeedSnapshot Fast()
{
   MSZZSpeedSnapshot f; ZeroMemory(f); f.atr=10.0; return f;
}

void TestLong()
{
   CMSZZSessionSweepReversalStrategy s; s.Configure(300,3);
   MSZZCandidate out[]; MSZZSpeedSnapshot f=Fast();
   s.Evaluate(f,Bar(D'2026.02.04 03:00',100,110,105),out);
   Check(s.Evaluate(f,Bar(D'2026.02.04 08:00',98,108,99),out)==0,
         "long sweep arms without emitting");
   int n=s.Evaluate(f,Bar(D'2026.02.04 08:05',99,103,101),out);
   Check(n==1 && out[0].direction==MSZZ_DIR_LONG &&
         out[0].strategy_id==MSZZ_STRAT_SESSION_SWEEP_REVERSAL &&
         out[0].family_id==MSZZ_FAMILY_REVERSAL,
         "valid long SSR candidate uses production identity");
   Check(out[0].stop==97.5 && out[0].target==108.0,
         "long stop uses frozen buffer and target is fixed 2R");
}

void TestShort()
{
   CMSZZSessionSweepReversalStrategy s; s.Configure(300,3);
   MSZZCandidate out[]; MSZZSpeedSnapshot f=Fast();
   s.Evaluate(f,Bar(D'2026.02.05 03:00',100,110,105),out);
   Check(s.Evaluate(f,Bar(D'2026.02.05 08:00',102,112,111),out)==0,
         "short sweep arms without emitting");
   int n=s.Evaluate(f,Bar(D'2026.02.05 08:05',106,111,109),out);
   Check(n==1 && out[0].direction==MSZZ_DIR_SHORT &&
         out[0].stop==112.5 && out[0].target==102.0,
         "valid short SSR candidate has frozen stop and fixed 2R target");
}

void TestMissingInvalidAndExpired()
{
   MSZZCandidate out[]; MSZZSpeedSnapshot f=Fast();
   CMSZZSessionSweepReversalStrategy missing; missing.Configure(300,3);
   Check(missing.Evaluate(f,Bar(D'2026.02.06 03:00',100,110,105),out)==0 &&
         missing.Evaluate(f,Bar(D'2026.02.06 07:55',101,109,105),out)==0,
         "missing sweep prerequisite emits nothing");

   CMSZZSessionSweepReversalStrategy invalid; invalid.Configure(300,3);
   invalid.Evaluate(f,Bar(D'2026.02.07 03:00',100,110,105),out);
   invalid.Evaluate(f,Bar(D'2026.02.07 08:00',98,108,99),out);
   Check(invalid.Evaluate(f,Bar(D'2026.02.07 08:05',92,99,94),out)==0,
         "accepted failure invalidates the active setup");

   CMSZZSessionSweepReversalStrategy expired; expired.Configure(300,3);
   expired.Evaluate(f,Bar(D'2026.02.08 03:00',100,110,105),out);
   expired.Evaluate(f,Bar(D'2026.02.08 08:00',98,108,99),out);
   for(int i=1;i<=7;i++)
      expired.Evaluate(f,Bar(D'2026.02.08 08:00'+i*300,99,101,99),out);
   Check(expired.Evaluate(f,Bar(D'2026.02.08 08:40',99,103,101),out)==0,
         "expired setup cannot emit on a later reclaim");
}

void TestEventScopedIdentity()
{
   CMSZZSessionSweepReversalStrategy s; s.Configure(300,3);
   MSZZCandidate out[]; MSZZSpeedSnapshot f=Fast();
   s.Evaluate(f,Bar(D'2026.02.09 03:00',100,110,105),out);

   s.Evaluate(f,Bar(D'2026.02.09 08:00',98,108,99),out);
   int n1=s.Evaluate(f,Bar(D'2026.02.09 08:05',99,103,101),out);
   MSZZCandidate first=out[0];

   s.Evaluate(f,Bar(D'2026.02.09 08:10',98,103,99),out);
   int n2=s.Evaluate(f,Bar(D'2026.02.09 08:15',99,103,101),out);
   MSZZCandidate second=out[0];

   Check(n1==1 && n2==1 && first.origin_id!=second.origin_id,
         "two separate long arms on one day use distinct production origins");
   Check(StringFind(first.origin_id,"SSRP|ASIA_LOW|20260209|")==0 &&
         StringFind(second.origin_id,"SSRP|ASIA_LOW|20260209|")==0,
         "long origins preserve daily reference plus arm timestamp sequence");
   Check(first.event_id==first.origin_id+"|FINAL" &&
         second.event_id==second.origin_id+"|FINAL",
         "event ID remains sequence origin plus FINAL");
   Check(first.entry==second.entry && first.stop==second.stop &&
         first.target==second.target && first.direction==second.direction,
         "identity-only re-arm fixture preserves candidate geometry");

   CMSZZOpportunityClusterEngine engine; MSZZOpportunityCluster clusters[];
   MSZZCandidate repeated[]; ArrayResize(repeated,2);
   repeated[0]=first; repeated[1]=first;
   int same_count=engine.Build("XAUUSD",PERIOD_M5,repeated,2,clusters);
   string same_id=(same_count==1 ? clusters[0].cluster_id : "");
   MSZZOpportunityCluster clusters_again[];
   int again_count=engine.Build("XAUUSD",PERIOD_M5,repeated,2,clusters_again);
   Check(same_count==1 && again_count==1 &&
         same_id==clusters_again[0].cluster_id,
         "same SSR sequence evaluated twice forms one deterministic cluster");

   MSZZCandidate distinct[]; ArrayResize(distinct,2);
   distinct[0]=first; distinct[1]=second;
   int distinct_count=engine.Build("XAUUSD",PERIOD_M5,distinct,2,clusters);
   Check(distinct_count==2 && clusters[0].cluster_id!=clusters[1].cluster_id,
         "different same-day SSR sequence origins form two clusters");

   CMSZZSessionSweepReversalStrategy shorts; shorts.Configure(300,3);
   shorts.Evaluate(f,Bar(D'2026.02.10 03:00',100,110,105),out);
   shorts.Evaluate(f,Bar(D'2026.02.10 08:00',102,112,111),out);
   shorts.Evaluate(f,Bar(D'2026.02.10 08:05',106,111,109),out);
   MSZZCandidate short1=out[0];
   shorts.Evaluate(f,Bar(D'2026.02.10 16:00',106,112,111),out);
   int short_n2=shorts.Evaluate(f,Bar(D'2026.02.10 16:05',106,111,109),out);
   MSZZCandidate short2=out[0];
   Check(short_n2==1 && short1.origin_id!=short2.origin_id &&
         StringFind(short2.origin_id,"SSRP|ASIA_HIGH|20260210|")==0,
         "separate London and New York short arms use distinct IDs");

   MSZZCandidate directions[]; ArrayResize(directions,2);
   directions[0]=first; directions[1]=short1;
   Check(engine.Build("XAUUSD",PERIOD_M5,directions,2,clusters)==2,
         "long and short SSR events form distinct clusters");

   s.Evaluate(f,Bar(D'2026.02.11 03:00',100,110,105),out);
   s.Evaluate(f,Bar(D'2026.02.11 08:00',98,108,99),out);
   int next_day=s.Evaluate(f,Bar(D'2026.02.11 08:05',99,103,101),out);
   Check(next_day==1 &&
         StringFind(out[0].origin_id,"SSRP|ASIA_LOW|20260211|")==0 &&
         out[0].origin_id!=first.origin_id,
         "day rollover produces deterministic new event identity");
}

void TestCanonicalConfiguration()
{
   string reason;
   Check(CMSZZSessionSweepReversalStrategy::IsCanonicalConfiguration(
            3,2.0,reason) && reason=="",
         "canonical SSR validity and target are accepted");
   Check(!CMSZZSessionSweepReversalStrategy::IsCanonicalConfiguration(
            2,2.0,reason) &&
         StringFind(reason,"InpSignalValidityBars=3")>=0,
         "noncanonical SSR validity fails closed");
   Check(!CMSZZSessionSweepReversalStrategy::IsCanonicalConfiguration(
            3,1.5,reason) &&
         StringFind(reason,"InpSSRBookTargetR=2.0")>=0,
         "noncanonical SSR target fails closed");
}

void TestSameBarRearmOrdering()
{
   MSZZSpeedSnapshot f=Fast(); MSZZCandidate out[];

   CMSZZSessionSweepReversalStrategy expired; expired.Configure(300,3);
   expired.Evaluate(f,Bar(D'2026.02.12 03:00',100,110,105),out);
   expired.Evaluate(f,Bar(D'2026.02.12 08:00',98,108,99),out);
   expired.Evaluate(f,Bar(D'2026.02.12 08:35',98,103,99),out);
   int expired_count=expired.Evaluate(
      f,Bar(D'2026.02.12 08:40',99,103,101),out);
   Check(expired_count==1 &&
         StringFind(out[0].origin_id,
                    "SSRP|ASIA_LOW|20260212|1770885300")==0,
         "expired setup re-arms on its terminal bar before next reclaim");

   CMSZZSessionSweepReversalStrategy invalidated;
   invalidated.Configure(300,3);
   invalidated.Evaluate(f,Bar(D'2026.02.13 03:00',100,110,105),out);
   invalidated.Evaluate(f,Bar(D'2026.02.13 08:00',98,108,99),out);
   invalidated.Evaluate(f,Bar(D'2026.02.13 08:05',93,102,94),out);
   int invalidated_count=invalidated.Evaluate(
      f,Bar(D'2026.02.13 08:10',99,103,101),out);
   Check(invalidated_count==1 &&
         StringFind(out[0].origin_id,
                    "SSRP|ASIA_LOW|20260213|1770969900")==0,
         "invalidated setup re-arms on its terminal bar before next reclaim");
}

void OnStart()
{
   TestLong(); TestShort(); TestMissingInvalidAndExpired();
   TestEventScopedIdentity();
   TestCanonicalConfiguration();
   TestSameBarRearmOrdering();
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
}
