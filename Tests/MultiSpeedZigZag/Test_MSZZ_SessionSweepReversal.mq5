#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Strategies/SessionSweepReversalStrategy.mqh>

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

void OnStart()
{
   TestLong(); TestShort(); TestMissingInvalidAndExpired();
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
}
