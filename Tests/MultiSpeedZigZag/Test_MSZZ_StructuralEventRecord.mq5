#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Core/StructuralEventRecord.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Research/StructuralReplay.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

MSZZPivot Pivot(const ENUM_MSZZ_SPEED speed,const ENUM_MSZZ_PIVOT_KIND kind,
                const string id,const datetime pivot_time,
                const datetime confirmed_time,const double price)
{
   MSZZPivot p; ZeroMemory(p);
   p.valid=true; p.speed=speed; p.kind=kind; p.id=id;
   p.pivot_time=pivot_time; p.confirmed_time=confirmed_time;
   p.price=price;
   return p;
}

bool SameRecord(const MSZZStructuralEventRecord &a,
                const MSZZStructuralEventRecord &b)
{
   return a.valid==b.valid && a.validation_reason==b.validation_reason &&
      a.event_id==b.event_id && a.speed==b.speed &&
      a.direction==b.direction && a.event_time==b.event_time &&
      a.source_origin_pivot_id==b.source_origin_pivot_id &&
      a.source_origin_price==b.source_origin_price &&
      a.source_origin_pivot_time==b.source_origin_pivot_time &&
      a.source_origin_confirmation_time==b.source_origin_confirmation_time &&
      a.broken_pivot_id==b.broken_pivot_id &&
      a.broken_pivot_price==b.broken_pivot_price &&
      a.broken_pivot_time==b.broken_pivot_time &&
      a.broken_pivot_confirmation_time==b.broken_pivot_confirmation_time &&
      a.projection_anchor_1_id==b.projection_anchor_1_id &&
      a.projection_anchor_1_price==b.projection_anchor_1_price &&
      a.projection_anchor_1_time==b.projection_anchor_1_time &&
      a.projection_anchor_1_confirmation_time==
         b.projection_anchor_1_confirmation_time &&
      a.projection_anchor_2_id==b.projection_anchor_2_id &&
      a.projection_anchor_2_price==b.projection_anchor_2_price &&
      a.projection_anchor_2_time==b.projection_anchor_2_time &&
      a.projection_anchor_2_confirmation_time==
         b.projection_anchor_2_confirmation_time &&
      a.previous_bar_time==b.previous_bar_time &&
      a.projected_level_previous_bar==b.projected_level_previous_bar &&
      a.projected_level_event_bar==b.projected_level_event_bar &&
      a.break_close_previous_bar==b.break_close_previous_bar &&
      a.break_close_price==b.break_close_price &&
      a.break_distance==b.break_distance &&
      a.break_distance_atr==b.break_distance_atr &&
      a.impulse_origin_price==b.impulse_origin_price &&
      a.impulse_extreme_price==b.impulse_extreme_price &&
      a.impulse_distance==b.impulse_distance &&
      a.impulse_distance_atr==b.impulse_distance_atr &&
      a.atr_at_event==b.atr_at_event;
}

void WriteParityRow(const int handle,const datetime bar_time,
                    const MSZZStructuralEventRecord &engine_record,
                    const MSZZStructuralEventRecord &replay_record)
{
   FileWrite(handle,TimeToString(bar_time,TIME_DATE|TIME_SECONDS),
      (int)engine_record.speed,MSZZDirectionText(engine_record.direction),
      engine_record.event_id,replay_record.event_id,
      engine_record.projection_anchor_1_id,
      engine_record.projection_anchor_2_id,
      DoubleToString(engine_record.projected_level_previous_bar,10),
      DoubleToString(replay_record.projected_level_previous_bar,10),
      DoubleToString(engine_record.projected_level_event_bar,10),
      DoubleToString(replay_record.projected_level_event_bar,10),
      engine_record.source_origin_pivot_id,
      replay_record.source_origin_pivot_id,
      engine_record.broken_pivot_id,replay_record.broken_pivot_id,
      DoubleToString(engine_record.atr_at_event,10),
      DoubleToString(replay_record.atr_at_event,10),
      DoubleToString(engine_record.break_distance,10),
      DoubleToString(replay_record.break_distance,10),
      DoubleToString(engine_record.impulse_distance,10),
      DoubleToString(replay_record.impulse_distance,10),
      (SameRecord(engine_record,replay_record) ? "PASS" : "FAIL"));
}

bool BuildBullish(const ENUM_MSZZ_SPEED speed,
                  MSZZStructuralEventRecord &record,
                  const string anchor_2_id="BH2")
{
   datetime t=D'2026.01.05 10:00:00';
   MSZZPivot a1=Pivot(speed,MSZZ_PIVOT_HIGH,"BH1",t,t+60,100.0);
   MSZZPivot origin=Pivot(speed,MSZZ_PIVOT_LOW,"BL1",t+300,t+360,95.0);
   MSZZPivot a2=Pivot(speed,MSZZ_PIVOT_HIGH,anchor_2_id,t+600,t+660,101.0);
   return CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,speed,MSZZ_DIR_LONG,t+900,t+1200,
      101.5,102.5,103.0,101.8,1.0,a1,a2,origin,0.01,record);
}

bool BuildBearish(const ENUM_MSZZ_SPEED speed,
                  MSZZStructuralEventRecord &record)
{
   datetime t=D'2026.01.05 11:00:00';
   MSZZPivot a1=Pivot(speed,MSZZ_PIVOT_LOW,"BS1",t,t+60,100.0);
   MSZZPivot origin=Pivot(speed,MSZZ_PIVOT_HIGH,"BH1",t+300,t+360,105.0);
   MSZZPivot a2=Pivot(speed,MSZZ_PIVOT_LOW,"BS2",t+600,t+660,99.0);
   return CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,speed,MSZZ_DIR_SHORT,t+900,t+1200,
      98.5,97.5,98.2,97.0,1.0,a1,a2,origin,0.01,record);
}

void TestValidConstruction()
{
   MSZZStructuralEventRecord bull,bear;
   AssertTrue(BuildBullish(MSZZ_SPEED_FAST,bull),
              "valid bullish event");
   AssertTrue(BuildBearish(MSZZ_SPEED_MEDIUM,bear),
              "valid bearish event");
   AssertTrue(bull.broken_pivot_id==bull.projection_anchor_2_id &&
              bull.source_origin_pivot_time<bull.broken_pivot_time,
              "bullish ownership and chronology");
   AssertTrue(bear.broken_pivot_id==bear.projection_anchor_2_id &&
              bear.source_origin_pivot_time<bear.broken_pivot_time,
              "bearish ownership and chronology");
   AssertTrue(MathAbs(bull.projected_level_previous_bar-101.5)<1e-10 &&
              MathAbs(bull.projected_level_event_bar-102.0)<1e-10,
              "projection anchors reproduce exact levels");
   AssertTrue(MathAbs(bull.break_distance-0.5)<1e-10 &&
              MathAbs(bull.impulse_distance-8.0)<1e-10,
              "break and impulse distances");
}

void TestDeterminismAndSeparation()
{
   MSZZStructuralEventRecord a,b,medium,slow,different_basis,bear;
   BuildBullish(MSZZ_SPEED_FAST,a);
   BuildBullish(MSZZ_SPEED_FAST,b);
   BuildBullish(MSZZ_SPEED_MEDIUM,medium);
   BuildBullish(MSZZ_SPEED_SLOW,slow);
   BuildBullish(MSZZ_SPEED_FAST,different_basis,"BH-DIFFERENT");
   BuildBearish(MSZZ_SPEED_FAST,bear);
   AssertTrue(SameRecord(a,b),"same input byte-equivalent record");
   AssertTrue(a.event_id!=medium.event_id && medium.event_id!=slow.event_id,
              "fast medium slow IDs separated");
   AssertTrue(a.event_id!=different_basis.event_id,
              "projection basis changes event ID");
   AssertTrue(a.event_id!=bear.event_id,
              "bullish bearish IDs separated");
}

void TestFailClosed()
{
   datetime t=D'2026.01.05 12:00:00';
   MSZZPivot a1=Pivot(MSZZ_SPEED_FAST,MSZZ_PIVOT_HIGH,"A1",t,t+60,100);
   MSZZPivot a2=Pivot(MSZZ_SPEED_FAST,MSZZ_PIVOT_HIGH,"A2",t+600,t+660,101);
   MSZZPivot blank; ZeroMemory(blank);
   MSZZStructuralEventRecord r;
   AssertTrue(!CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,MSZZ_SPEED_FAST,MSZZ_DIR_LONG,t+900,t+1200,
      101.5,102.5,103,102,1,a1,a2,blank,0.01,r) &&
      r.validation_reason=="MISSING_ORIGIN_ADJACENCY",
      "missing adjacency fails closed");

   MSZZPivot late_origin=Pivot(MSZZ_SPEED_FAST,MSZZ_PIVOT_LOW,"LATE",
      t+700,t+720,95);
   AssertTrue(!CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,MSZZ_SPEED_FAST,MSZZ_DIR_LONG,t+900,t+1200,
      101.5,102.5,103,102,1,a1,a2,late_origin,0.01,r) &&
      r.validation_reason=="INVALID_PIVOT_CHRONOLOGY",
      "invalid origin chronology fails closed");

   MSZZPivot origin=Pivot(MSZZ_SPEED_FAST,MSZZ_PIVOT_LOW,"ORIGIN",
      t+300,t+360,95);
   AssertTrue(!CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,MSZZ_SPEED_FAST,MSZZ_DIR_LONG,t+900,t+1200,
      101.5,102.5,103,102,0,a1,a2,origin,0.01,r) &&
      r.validation_reason=="INVALID_NUMERIC",
      "zero ATR fails closed");
   AssertTrue(!CMSZZStructuralEventPolicy::Build(
      "XAUUSD",PERIOD_M5,MSZZ_SPEED_FAST,MSZZ_DIR_LONG,t+900,t+1200,
      101.5,101.9,103,102,1,a1,a2,origin,0.01,r) &&
      r.validation_reason=="INVALID_BULLISH_GEOMETRY",
      "directionally invalid close fails closed");

   BuildBullish(MSZZ_SPEED_FAST,r);
   r.projected_level_event_bar+=0.1;
   string reason;
   AssertTrue(!CMSZZStructuralEventPolicy::Validate(r,0.01,reason) &&
              reason=="PROJECTION_MISMATCH",
              "projection mismatch fails validation");
}

void TestLifetimeCopy()
{
   MSZZStructuralEventRecord original,copied;
   BuildBullish(MSZZ_SPEED_FAST,original);
   string frozen_id=original.event_id;
   copied=original;
   CMSZZStructuralEventPolicy::Blank(original,"NEXT_BAR_NO_EVENT");
   AssertTrue(!original.valid && original.event_id=="",
              "next snapshot clears current event");
   AssertTrue(copied.valid && copied.event_id==frozen_id,
              "prior copied record survives next snapshot clear");
}

void TestEngineReplayRealHistory()
{
   MqlRates rates[];
   int copied=CopyRates("XAUUSD",PERIOD_M5,D'2025.06.01 00:00:00',
                        D'2025.07.01 00:00:00',rates);
   if(copied<200)
   {
      AssertTrue(false,"real-history engine/replay data available");
      return;
   }

   int certified_events=0,mismatches=0,same_rebuild_mutations=0;
   string ids[];
   int parity_handle=FileOpen("MSZZ_StructuralEventParity.csv",
      FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(parity_handle!=INVALID_HANDLE)
      FileWrite(parity_handle,"bar_time","speed","direction",
         "engine_event_id","replay_event_id","projection_anchor_1_id",
         "projection_anchor_2_id","engine_projected_previous",
         "replay_projected_previous","engine_projected_event",
         "replay_projected_event","engine_origin_pivot",
         "replay_origin_pivot","engine_broken_pivot","replay_broken_pivot",
         "engine_atr","replay_atr","engine_break_distance",
         "replay_break_distance","engine_impulse_distance",
         "replay_impulse_distance","field_parity");
   for(int si=0;si<3;si++)
   {
      ENUM_MSZZ_SPEED speed=(ENUM_MSZZ_SPEED)si;
      double multiplier=(speed==MSZZ_SPEED_FAST ? 1.0 :
                         (speed==MSZZ_SPEED_MEDIUM ? 2.0 : 3.5));
      MSZZSpeedBarState history[];
      bool replay_ok=CMSZZStructuralReplay::BuildBarHistory(
         "XAUUSD",PERIOD_M5,rates,copied,14,multiplier,3,speed,history);
      AssertTrue(replay_ok,StringFormat("replay builds speed=%d",si));
      if(!replay_ok) continue;

      for(int i=24;i<copied;i++)
      {
         bool have_bull=history[i].bullish_structural_event.valid;
         bool have_bear=history[i].bearish_structural_event.valid;
         if(!have_bull && !have_bear) continue;

         CMSZZTripleZigZagEngine engine;
         engine.Configure(14,1.0,14,2.0,14,3.5,3);
         if(!engine.Rebuild("XAUUSD",PERIOD_M5,rates,i+1))
         { mismatches++; continue; }
         MSZZSpeedSnapshot snap=engine.Snapshot(speed);
         if(have_bull)
         {
            certified_events++;
            if(parity_handle!=INVALID_HANDLE)
               WriteParityRow(parity_handle,rates[i].time,
                  snap.bullish_structural_event,
                  history[i].bullish_structural_event);
            if(!SameRecord(history[i].bullish_structural_event,
                           snap.bullish_structural_event))
               mismatches++;
            int n=ArraySize(ids); ArrayResize(ids,n+1);
            ids[n]=history[i].bullish_structural_event.event_id;
         }
         if(have_bear)
         {
            certified_events++;
            if(parity_handle!=INVALID_HANDLE)
               WriteParityRow(parity_handle,rates[i].time,
                  snap.bearish_structural_event,
                  history[i].bearish_structural_event);
            if(!SameRecord(history[i].bearish_structural_event,
                           snap.bearish_structural_event))
               mismatches++;
            int n=ArraySize(ids); ArrayResize(ids,n+1);
            ids[n]=history[i].bearish_structural_event.event_id;
         }
         if((history[i].new_high_pivot || history[i].new_low_pivot) &&
            (have_bull || have_bear))
            same_rebuild_mutations++;
      }
   }
   if(parity_handle!=INVALID_HANDLE)
   {
      FileFlush(parity_handle);
      FileClose(parity_handle);
   }

   int duplicates=0;
   for(int i=0;i<ArraySize(ids);i++)
      for(int j=i+1;j<ArraySize(ids);j++)
         if(ids[i]==ids[j]) duplicates++;

   AssertTrue(certified_events>0,
              StringFormat("real-history certified events=%d",
                           certified_events));
   AssertTrue(mismatches==0,
              StringFormat("engine replay mismatches=%d",mismatches));
   AssertTrue(duplicates==0,
              StringFormat("event ID duplicates=%d",duplicates));
   AssertTrue(same_rebuild_mutations>0,
              StringFormat("same-rebuild pivot mutation events=%d",
                           same_rebuild_mutations));
}

void OnStart()
{
   TestValidConstruction();
   TestDeterminismAndSeparation();
   TestFailClosed();
   TestLifetimeCopy();
   TestEngineReplayRealHistory();
   PrintFormat("MSZZ structural event record test complete failures=%d",
               g_failures);
}
