#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Core/CandidateHandoff.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>

int g_tests=0;
int g_failures=0;

void AssertTrue(const bool condition,const string name)
{
   g_tests++;
   if(condition) Print("PASS: ",name);
   else { g_failures++; Print("FAIL: ",name); }
}

MSZZCandidate Candidate(const ENUM_MSZZ_STRATEGY_ID strategy,
                        const ENUM_MSZZ_STRATEGY_FAMILY family,
                        const ENUM_MSZZ_DIRECTION direction,
                        const string identity,const double score)
{
   MSZZCandidate c; ZeroMemory(c);
   c.valid=true;
   c.strategy_id=strategy;
   c.family_id=family;
   c.direction=direction;
   c.origin_type=(strategy==MSZZ_STRAT_SWEEP_RECLAIM ?
                  MSZZ_ORIGIN_PIVOT_SWEEP : MSZZ_ORIGIN_FAST_BREAK);
   c.signal_time=D'2026.01.02 10:00';
   c.expiry_time=D'2026.01.02 10:15';
   c.entry=(direction==MSZZ_DIR_LONG ? 100.0 : 110.0);
   c.stop=(direction==MSZZ_DIR_LONG ? 95.0 : 115.0);
   c.target=(direction==MSZZ_DIR_LONG ? 110.0 : 100.0);
   c.score=score;
   c.supporting_models=2;
   c.evidence_mask=MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT;
   c.setup_name=identity;
   c.origin_id="ORIGIN|"+identity;
   c.event_id="EVENT|"+identity;
   c.reason="deterministic handoff fixture";
   return c;
}

bool SameIdentity(const MSZZCandidate &a,const MSZZCandidate &b)
{
   return a.strategy_id==b.strategy_id &&
          a.family_id==b.family_id &&
          a.direction==b.direction &&
          a.event_id==b.event_id &&
          a.origin_id==b.origin_id &&
          a.score==b.score &&
          a.entry==b.entry &&
          a.stop==b.stop &&
          a.target==b.target;
}

void TestFirstAppend()
{
   MSZZCandidate out[];
   int count=0,index=-1; string diagnostic;
   MSZZCandidate a=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                             MSZZ_DIR_LONG,"A",8.0);
   bool ok=CMSZZCandidateHandoff::Append(out,count,a,index,diagnostic);
   AssertTrue(ok && index==0 && count==1 && ArraySize(out)==1,
              "first appended candidate is logical index zero");
   AssertTrue(SameIdentity(a,out[0]),"all required candidate identity survives first append");
}

void TestAppendAfterSixteen()
{
   MSZZCandidate out[];
   int count=0,index=-1; string diagnostic;
   for(int i=0;i<16;i++)
   {
      MSZZCandidate c=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                                MSZZ_DIR_LONG,"A"+IntegerToString(i),8.0);
      AssertTrue(CMSZZCandidateHandoff::Append(out,count,c,index,diagnostic),
                 "fixture append before index sixteen "+IntegerToString(i));
   }
   MSZZCandidate sweep=Candidate(MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,"SWEEP",7.6);
   bool ok=CMSZZCandidateHandoff::Append(out,count,sweep,index,diagnostic);
   AssertTrue(ok && index==16 && count==17 && ArraySize(out)==17,
              "candidate after sixteen existing slots uses real logical index");
   AssertTrue(SameIdentity(sweep,out[16]),"index sixteen preserves SweepReclaim identity");
}

void TestSparseAndInvalidFailClosed()
{
   MSZZCandidate sparse[]; ArrayResize(sparse,16);
   sparse[0]=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                       MSZZ_DIR_LONG,"A",8.0);
   int count=1,index=-1; string diagnostic;
   MSZZCandidate sweep=Candidate(MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,"SWEEP",7.6);
   bool ok=CMSZZCandidateHandoff::Append(sparse,count,sweep,index,diagnostic);
   AssertTrue(!ok && index==-1 && diagnostic=="append_to_sparse_collection count=1 size=16",
              "sparse physical capacity fails closed with deterministic diagnostic");

   CMSZZOpportunityClusterEngine engine; MSZZOpportunityCluster clusters[];
   int built=engine.Build("XAUUSD",PERIOD_M5,sparse,1,clusters);
   AssertTrue(built==-1 &&
              engine.LastDiagnostic()=="sparse_candidate_collection count=1 size=16",
              "cluster engine rejects sparse/uninitialized slots");

   MSZZCandidate compact[]; ArrayResize(compact,1); ZeroMemory(compact[0]);
   built=engine.Build("XAUUSD",PERIOD_M5,compact,1,clusters);
   AssertTrue(built==-1 &&
              engine.LastDiagnostic()=="invalid_candidate index=0 reason=candidate_not_explicitly_initialized",
              "malformed candidate never reaches clustering");

   MSZZCandidate empty[];
   built=engine.Build("XAUUSD",PERIOD_M5,empty,1,clusters);
   AssertTrue(built==-1 &&
              engine.LastDiagnostic()=="candidate_count_exceeds_array_size count=1 size=0",
              "out-of-bounds logical count fails closed deterministically");
}

void TestTwoStrategiesAndReordering()
{
   MSZZCandidate a=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                             MSZZ_DIR_LONG,"A",8.0);
   MSZZCandidate s=Candidate(MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                             MSZZ_DIR_SHORT,"SWEEP",7.6);
   MSZZCandidate first[],second[];
   int first_count=0,second_count=0,index=-1; string diagnostic;
   bool ok=CMSZZCandidateHandoff::Append(first,first_count,a,index,diagnostic) &&
           CMSZZCandidateHandoff::Append(first,first_count,s,index,diagnostic) &&
           CMSZZCandidateHandoff::Append(second,second_count,s,index,diagnostic) &&
           CMSZZCandidateHandoff::Append(second,second_count,a,index,diagnostic);
   AssertTrue(ok && first_count==2 && second_count==2 &&
              ArraySize(first)==2 && ArraySize(second)==2,
              "two enabled strategies have two initialized candidates");
   AssertTrue(SameIdentity(first[0],second[1]) && SameIdentity(first[1],second[0]),
              "enabled-strategy reordering preserves both candidate identities");

   string reason;
   AssertTrue(CMSZZCandidateHandoff::ValidateCollection(first,first_count,reason),
              "candidate count equals initialized candidate count");
}

void TestEveryRequiredIdentityField()
{
   MSZZCandidate base=Candidate(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                                MSZZ_DIR_LONG,"BASE",8.0);
   string expected[]={
      "invalid_strategy_id","invalid_family_id","invalid_direction","missing_event_id",
      "missing_origin_id","invalid_score","invalid_entry","invalid_stop","invalid_target"
   };
   for(int i=0;i<ArraySize(expected);i++)
   {
      MSZZCandidate c=base;
      if(i==0) c.strategy_id=MSZZ_STRAT_NONE;
      if(i==1) c.family_id=MSZZ_FAMILY_NONE;
      if(i==2) c.direction=MSZZ_DIR_NONE;
      if(i==3) c.event_id="";
      if(i==4) c.origin_id="";
      if(i==5) c.score=MathSqrt(-1.0);
      if(i==6) c.entry=0.0;
      if(i==7) c.stop=0.0;
      if(i==8) c.target=0.0;
      string reason;
      AssertTrue(!CMSZZCandidateHandoff::Validate(c,reason) && reason==expected[i],
                 "required identity fails closed: "+expected[i]);
   }
}

void TestSessionSweepProductionIdentity()
{
   MSZZCandidate ssr=Candidate(MSZZ_STRAT_SESSION_SWEEP_REVERSAL,MSZZ_FAMILY_REVERSAL,
                               MSZZ_DIR_LONG,"SSR",7.0);
   ssr.origin_type=MSZZ_ORIGIN_PIVOT_SWEEP;
   string reason;
   AssertTrue(CMSZZCandidateHandoff::Validate(ssr,reason),
              "production SSR 1090 is accepted by the candidate handoff");
}

void OnStart()
{
   TestFirstAppend();
   TestAppendAfterSixteen();
   TestSparseAndInvalidFailClosed();
   TestTwoStrategiesAndReordering();
   TestEveryRequiredIdentityField();
   TestSessionSweepProductionIdentity();
   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
   if(g_failures>0) ExpertRemove();
}
