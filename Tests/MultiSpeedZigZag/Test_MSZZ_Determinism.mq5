//+------------------------------------------------------------------+
//| Test_MSZZ_Determinism.mq5                                        |
//| Run as an MQL5 Script on any chart.                              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>

input int InpBars=800;

bool SamePivot(const MSZZPivot &a,const MSZZPivot &b)
{
   if(a.valid!=b.valid) return false;
   if(!a.valid) return true;
   return a.id==b.id && a.pivot_time==b.pivot_time && a.confirmed_time==b.confirmed_time &&
          MathAbs(a.price-b.price)<=_Point*0.1 && a.structure_label==b.structure_label;
}

bool SameSnapshot(const MSZZSpeedSnapshot &a,const MSZZSpeedSnapshot &b)
{
   return a.leg_direction==b.leg_direction && SamePivot(a.last_high,b.last_high) &&
          SamePivot(a.prior_high,b.prior_high) && SamePivot(a.last_low,b.last_low) &&
          SamePivot(a.prior_low,b.prior_low) && a.bullish_event_id==b.bullish_event_id &&
          a.bearish_event_id==b.bearish_event_id;
}

void OnStart()
{
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,_Period,0,MathMax(300,InpBars),rates);
   if(copied<200)
   {
      PrintFormat("TEST FAIL: insufficient bars copied=%d",copied);
      return;
   }
   int closed=copied-1;

   CMSZZTripleZigZagEngine a,b;
   a.Configure(14,1.0,14,2.0,14,3.5,3);
   b.Configure(14,1.0,14,2.0,14,3.5,3);
   bool oka=a.Rebuild(_Symbol,_Period,rates,closed);
   bool okb=b.Rebuild(_Symbol,_Period,rates,closed);
   if(!oka || !okb)
   {
      Print("TEST FAIL: rebuild returned false");
      return;
   }

   bool pass=true;
   for(int s=0;s<3;s++)
   {
      MSZZSpeedSnapshot sa=a.Snapshot((ENUM_MSZZ_SPEED)s);
      MSZZSpeedSnapshot sb=b.Snapshot((ENUM_MSZZ_SPEED)s);
      if(!SameSnapshot(sa,sb))
      {
         pass=false;
         PrintFormat("TEST FAIL: speed=%d produced different state on identical history",s);
      }
   }
   Print(pass ? "TEST PASS: deterministic rebuild" : "TEST FAIL: deterministic rebuild");
}
