//+------------------------------------------------------------------+
//| Export_MSZZ_Parity.mq5                                           |
//| Exports closed-bar MSZZ state for Pine/MQL5 comparison.          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>
#include <MultiSpeedZigZag/Diagnostics/ParityExporter.mqh>

input int    InpBars=1000;
input int    InpFastATRLen=14;
input double InpFastATRMult=1.0;
input int    InpMedATRLen=14;
input double InpMedATRMult=2.0;
input int    InpSlowATRLen=14;
input double InpSlowATRMult=3.5;
input int    InpMinBarsBetween=3;
input double InpRiskReward=1.5;
input string InpRunId="manual";
input string InpCommitSha="unknown";

void OnStart()
{
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,_Period,0,MathMax(300,InpBars),rates);
   if(copied<200)
   {
      PrintFormat("MSZZ parity export failed: copied=%d error=%d",copied,GetLastError());
      return;
   }

   int closed_total=copied-1;
   CMSZZParityExporter exporter;
   string run_id=StringFormat("%s_%s_%d_%I64d",InpRunId,_Symbol,(int)_Period,(long)rates[closed_total-1].time);
   exporter.Configure(run_id);
   exporter.WriteManifest("0.20",InpCommitSha,_Symbol,_Period,rates[0].time,rates[closed_total-1].time,
                          InpFastATRLen,InpFastATRMult,InpMedATRLen,InpMedATRMult,
                          InpSlowATRLen,InpSlowATRMult,InpMinBarsBetween,
                          "WICK_EXTREMES","CLOSE_CROSS","ELAPSED_SECONDS");

   CMSZZTripleZigZagEngine engine;
   CMSZZStrategySuite suite;
   CMSZZOpportunityClusterEngine cluster_engine;
   suite.SetRiskReward(InpRiskReward);

   int warmup=MathMax(InpFastATRLen,MathMax(InpMedATRLen,InpSlowATRLen))+20;
   for(int count=warmup;count<=closed_total;count++)
   {
      engine.Configure(InpFastATRLen,InpFastATRMult,InpMedATRLen,InpMedATRMult,
                       InpSlowATRLen,InpSlowATRMult,InpMinBarsBetween);
      if(!engine.Rebuild(_Symbol,_Period,rates,count)) continue;

      int bar_index=count-1;
      MSZZSpeedSnapshot fast=engine.Snapshot(MSZZ_SPEED_FAST);
      MSZZSpeedSnapshot med=engine.Snapshot(MSZZ_SPEED_MEDIUM);
      MSZZSpeedSnapshot slow=engine.Snapshot(MSZZ_SPEED_SLOW);

      exporter.WriteBar(bar_index,rates[bar_index],fast.atr,med.atr,slow.atr);
      exporter.WriteSnapshot(bar_index,rates[bar_index].time,fast);
      exporter.WriteSnapshot(bar_index,rates[bar_index].time,med);
      exporter.WriteSnapshot(bar_index,rates[bar_index].time,slow);

      if(fast.new_pivot)
      {
         exporter.WritePivot("MQL5",fast.last_high);
         exporter.WritePivot("MQL5",fast.last_low);
      }
      if(med.new_pivot)
      {
         exporter.WritePivot("MQL5",med.last_high);
         exporter.WritePivot("MQL5",med.last_low);
      }
      if(slow.new_pivot)
      {
         exporter.WritePivot("MQL5",slow.last_high);
         exporter.WritePivot("MQL5",slow.last_low);
      }

      MSZZCandidate candidates[];
      int candidate_count=suite.Evaluate(fast,med,slow,rates[bar_index].time,rates[bar_index].close,candidates);
      for(int i=0;i<candidate_count;i++) exporter.WriteCandidate(bar_index,candidates[i]);

      MSZZOpportunityCluster clusters[];
      int cluster_count=cluster_engine.Build(_Symbol,_Period,candidates,candidate_count,clusters);
      for(int c=0;c<cluster_count;c++) exporter.WriteCluster(bar_index,rates[bar_index].time,clusters[c]);
   }

   PrintFormat("MSZZ parity export complete run_id=%s closed_bars=%d",run_id,closed_total);
}
