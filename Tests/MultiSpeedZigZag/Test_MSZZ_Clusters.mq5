//+------------------------------------------------------------------+
//| Test_MSZZ_Clusters.mq5                                           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>

void InitCandidate(MSZZCandidate &c,const ENUM_MSZZ_STRATEGY_ID strategy,const double score,
                   const string origin,const string event_id,const double stop,const int evidence)
{
   ZeroMemory(c);
   c.valid=true;
   c.strategy_id=strategy;
   c.direction=MSZZ_DIR_LONG;
   c.origin_type=MSZZ_ORIGIN_FAST_BREAK;
   c.signal_time=D'2026.01.01 10:00';
   c.entry=100.0;
   c.stop=stop;
   c.target=110.0;
   c.score=score;
   c.supporting_models=1;
   c.evidence_mask=evidence;
   c.origin_id=origin;
   c.event_id=event_id;
}

void AssertTrue(const bool condition,const string message,int &failures)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

void OnStart()
{
   int failures=0;
   MSZZCandidate candidates[];
   ArrayResize(candidates,4);

   InitCandidate(candidates[0],MSZZ_STRAT_FAST_BREAKOUT,4.0,"FAST_ORIGIN_1","E1",95.0,MSZZ_EVIDENCE_TRIGGER);
   InitCandidate(candidates[1],MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,6.3,"FAST_ORIGIN_1","E2",95.0,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT);
   InitCandidate(candidates[2],MSZZ_STRAT_NESTED_PULLBACK,8.4,"FAST_ORIGIN_1","E3",94.5,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE);
   InitCandidate(candidates[3],MSZZ_STRAT_MEDIUM_BREAKOUT,5.5,"MED_ORIGIN_2","E4",96.0,MSZZ_EVIDENCE_TRIGGER);

   CMSZZOpportunityClusterEngine engine;
   MSZZOpportunityCluster clusters[];
   int count=engine.Build("XAUUSD",PERIOD_M5,candidates,ArraySize(candidates),clusters);

   AssertTrue(count==2,"three related candidates become one cluster and independent origin stays separate",failures);
   AssertTrue(clusters[0].support_count==3,"support count preserved",failures);
   AssertTrue(clusters[0].owner_strategy_id==MSZZ_STRAT_NESTED_PULLBACK,"specific nested pullback owns cluster",failures);
   AssertTrue((clusters[0].evidence_mask & MSZZ_EVIDENCE_STRUCTURE)!=0,"evidence mask merges structure evidence",failures);
   AssertTrue(clusters[0].stop_disagreement>0.0,"stop disagreement measured",failures);
   AssertTrue(clusters[0].cluster_id!="","stable cluster ID created",failures);

   int best=engine.SelectBest(clusters,count);
   AssertTrue(best>=0,"best cluster selected",failures);
   if(best>=0) AssertTrue(clusters[best].origin_id=="FAST_ORIGIN_1","stronger related cluster selected",failures);

   PrintFormat("MSZZ cluster test complete failures=%d",failures);
}
