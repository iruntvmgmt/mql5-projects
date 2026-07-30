#ifndef __MSZZ_STRUCTURAL_EVENT_RECORD_MQH__
#define __MSZZ_STRUCTURAL_EVENT_RECORD_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZStructuralEventPolicy
{
private:
   static string I64(const long value) { return IntegerToString(value); }
   static string LP(const string value)
   {
      return IntegerToString(StringLen(value))+":"+value;
   }

   static bool FinitePositive(const double value)
   {
      return MathIsValidNumber(value) && value>0.0;
   }

   static bool Near(const double a,const double b,const double tolerance)
   {
      return MathAbs(a-b)<=tolerance;
   }

public:
   static void Blank(MSZZStructuralEventRecord &record,const string reason="")
   {
      ZeroMemory(record);
      record.valid=false;
      record.speed=MSZZ_SPEED_FAST;
      record.direction=MSZZ_DIR_NONE;
      record.validation_reason=reason;
   }

   static double ProjectLevel(const MSZZPivot &anchor_1,
                              const MSZZPivot &anchor_2,
                              const datetime at_time)
   {
      if(!anchor_1.valid || !anchor_2.valid ||
         anchor_2.pivot_time<=anchor_1.pivot_time)
         return 0.0;
      double seconds=(double)(anchor_2.pivot_time-anchor_1.pivot_time);
      double slope=(anchor_2.price-anchor_1.price)/seconds;
      return anchor_2.price+slope*(double)(at_time-anchor_2.pivot_time);
   }

   static string EventId(const string symbol,const ENUM_TIMEFRAMES timeframe,
                         const ENUM_MSZZ_SPEED speed,
                         const ENUM_MSZZ_DIRECTION direction,
                         const datetime event_time,
                         const string broken_pivot_id,
                         const string anchor_1_id,
                         const string anchor_2_id)
   {
      return "MSZZSE1|"+LP(symbol)+"|"+LP(IntegerToString((int)timeframe))+
             "|"+LP(IntegerToString((int)speed))+
             "|"+LP(IntegerToString((int)direction))+
             "|"+LP(I64((long)event_time))+
             "|"+LP(broken_pivot_id)+"|"+LP(anchor_1_id)+"|"+LP(anchor_2_id);
   }

   static bool Validate(const MSZZStructuralEventRecord &record,
                        const double point_size,string &reason)
   {
      reason="";
      double tolerance=MathMax(point_size*0.1,1.0e-10);
      if(record.event_id=="" || record.source_origin_pivot_id=="" ||
         record.broken_pivot_id=="" || record.projection_anchor_1_id=="" ||
         record.projection_anchor_2_id=="")
      { reason="MISSING_ID"; return false; }
      if(record.direction!=MSZZ_DIR_LONG && record.direction!=MSZZ_DIR_SHORT)
      { reason="INVALID_DIRECTION"; return false; }
      if(record.speed<MSZZ_SPEED_FAST || record.speed>MSZZ_SPEED_SLOW)
      { reason="INVALID_SPEED"; return false; }
      if(record.event_time<=0 || record.previous_bar_time<=0 ||
         record.previous_bar_time>=record.event_time)
      { reason="INVALID_EVENT_TIME"; return false; }
      if(!FinitePositive(record.source_origin_price) ||
         !FinitePositive(record.broken_pivot_price) ||
         !FinitePositive(record.projection_anchor_1_price) ||
         !FinitePositive(record.projection_anchor_2_price) ||
         !FinitePositive(record.projected_level_previous_bar) ||
         !FinitePositive(record.projected_level_event_bar) ||
         !FinitePositive(record.break_close_previous_bar) ||
         !FinitePositive(record.break_close_price) ||
         !FinitePositive(record.impulse_origin_price) ||
         !FinitePositive(record.impulse_extreme_price) ||
         !FinitePositive(record.atr_at_event))
      { reason="INVALID_NUMERIC"; return false; }
      if(record.projection_anchor_1_id==record.projection_anchor_2_id ||
         record.projection_anchor_2_id!=record.broken_pivot_id)
      { reason="INVALID_PROJECTION_IDENTITY"; return false; }
      if(record.projection_anchor_1_time>=record.projection_anchor_2_time ||
         record.source_origin_pivot_time>=record.broken_pivot_time ||
         record.source_origin_confirmation_time>
            record.broken_pivot_confirmation_time ||
         record.broken_pivot_confirmation_time>record.event_time)
      { reason="INVALID_PIVOT_CHRONOLOGY"; return false; }
      if(!Near(record.projection_anchor_2_price,record.broken_pivot_price,tolerance) ||
         record.projection_anchor_2_time!=record.broken_pivot_time ||
         record.projection_anchor_2_confirmation_time!=
            record.broken_pivot_confirmation_time)
      { reason="BROKEN_PIVOT_MISMATCH"; return false; }

      MSZZPivot a1,a2;
      ZeroMemory(a1); ZeroMemory(a2);
      a1.valid=true; a1.price=record.projection_anchor_1_price;
      a1.pivot_time=record.projection_anchor_1_time;
      a2.valid=true; a2.price=record.projection_anchor_2_price;
      a2.pivot_time=record.projection_anchor_2_time;
      double recomputed_previous=ProjectLevel(a1,a2,record.previous_bar_time);
      double recomputed_event=ProjectLevel(a1,a2,record.event_time);
      if(!Near(recomputed_previous,record.projected_level_previous_bar,tolerance) ||
         !Near(recomputed_event,record.projected_level_event_bar,tolerance))
      { reason="PROJECTION_MISMATCH"; return false; }

      double break_distance=MathAbs(record.break_close_price-
                                    record.projected_level_event_bar);
      double impulse_distance=MathAbs(record.impulse_extreme_price-
                                      record.impulse_origin_price);
      if(!Near(break_distance,record.break_distance,tolerance) ||
         !Near(break_distance/record.atr_at_event,
               record.break_distance_atr,tolerance) ||
         !Near(impulse_distance,record.impulse_distance,tolerance) ||
         !Near(impulse_distance/record.atr_at_event,
               record.impulse_distance_atr,tolerance))
      { reason="DISTANCE_MISMATCH"; return false; }

      if(record.direction==MSZZ_DIR_LONG)
      {
         if(record.break_close_previous_bar>
               record.projected_level_previous_bar+tolerance ||
            record.break_close_price<=
               record.projected_level_event_bar+tolerance ||
            record.impulse_origin_price>=
               record.impulse_extreme_price-tolerance)
         { reason="INVALID_BULLISH_GEOMETRY"; return false; }
      }
      else
      {
         if(record.break_close_previous_bar<
               record.projected_level_previous_bar-tolerance ||
            record.break_close_price>=
               record.projected_level_event_bar-tolerance ||
            record.impulse_origin_price<=
               record.impulse_extreme_price+tolerance)
         { reason="INVALID_BEARISH_GEOMETRY"; return false; }
      }
      reason="OK";
      return true;
   }

   static bool Build(const string symbol,const ENUM_TIMEFRAMES timeframe,
                     const ENUM_MSZZ_SPEED speed,
                     const ENUM_MSZZ_DIRECTION direction,
                     const datetime previous_bar_time,
                     const datetime event_time,
                     const double previous_close,
                     const double event_close,
                     const double event_high,
                     const double event_low,
                     const double atr_at_event,
                     const MSZZPivot &projection_anchor_1,
                     const MSZZPivot &projection_anchor_2,
                     const MSZZPivot &source_origin,
                     const double point_size,
                     MSZZStructuralEventRecord &record)
   {
      Blank(record);
      if(!projection_anchor_1.valid || !projection_anchor_2.valid)
      { record.validation_reason="MISSING_PROJECTION_ANCHOR"; return false; }
      if(!source_origin.valid)
      { record.validation_reason="MISSING_ORIGIN_ADJACENCY"; return false; }

      record.speed=speed; record.direction=direction;
      record.event_time=event_time; record.previous_bar_time=previous_bar_time;
      record.source_origin_pivot_id=source_origin.id;
      record.source_origin_price=source_origin.price;
      record.source_origin_pivot_time=source_origin.pivot_time;
      record.source_origin_confirmation_time=source_origin.confirmed_time;
      record.broken_pivot_id=projection_anchor_2.id;
      record.broken_pivot_price=projection_anchor_2.price;
      record.broken_pivot_time=projection_anchor_2.pivot_time;
      record.broken_pivot_confirmation_time=projection_anchor_2.confirmed_time;
      record.projection_anchor_1_id=projection_anchor_1.id;
      record.projection_anchor_1_price=projection_anchor_1.price;
      record.projection_anchor_1_time=projection_anchor_1.pivot_time;
      record.projection_anchor_1_confirmation_time=
         projection_anchor_1.confirmed_time;
      record.projection_anchor_2_id=projection_anchor_2.id;
      record.projection_anchor_2_price=projection_anchor_2.price;
      record.projection_anchor_2_time=projection_anchor_2.pivot_time;
      record.projection_anchor_2_confirmation_time=
         projection_anchor_2.confirmed_time;
      record.projected_level_previous_bar=
         ProjectLevel(projection_anchor_1,projection_anchor_2,previous_bar_time);
      record.projected_level_event_bar=
         ProjectLevel(projection_anchor_1,projection_anchor_2,event_time);
      record.break_close_previous_bar=previous_close;
      record.break_close_price=event_close;
      record.atr_at_event=atr_at_event;
      record.break_distance=MathAbs(event_close-
                                    record.projected_level_event_bar);
      record.break_distance_atr=(atr_at_event>0.0 ?
                                 record.break_distance/atr_at_event : 0.0);
      record.impulse_origin_price=source_origin.price;
      record.impulse_extreme_price=(direction==MSZZ_DIR_LONG ?
         MathMax(event_high,projection_anchor_2.price) :
         MathMin(event_low,projection_anchor_2.price));
      record.impulse_distance=MathAbs(record.impulse_extreme_price-
                                      record.impulse_origin_price);
      record.impulse_distance_atr=(atr_at_event>0.0 ?
                                   record.impulse_distance/atr_at_event : 0.0);
      record.event_id=EventId(symbol,timeframe,speed,direction,event_time,
                              record.broken_pivot_id,
                              record.projection_anchor_1_id,
                              record.projection_anchor_2_id);
      string reason;
      record.valid=Validate(record,point_size,reason);
      record.validation_reason=reason;
      return record.valid;
   }
};

#endif
