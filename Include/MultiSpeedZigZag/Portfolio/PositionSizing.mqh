#ifndef __MSZZ_POSITION_SIZING_MQH__
#define __MSZZ_POSITION_SIZING_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

// D029 Phase 1: pure, deterministic percentage-of-equity position sizing.
// No MT5 API calls -- the caller (EA) is responsible for supplying real
// equity/symbol metadata, exactly the same discipline this project has
// followed for every other pure-calculation module (e.g. D026's
// CMSZZResearchTrailPolicy). See DECISION_LOG.md D029 Phase 1 and
// Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md for every frozen
// rule this implements.

enum ENUM_MSZZ_SIZING_RESULT
{
   MSZZ_SIZING_OK       = 0,
   MSZZ_SIZING_REJECTED = 1
};

struct MSZZSizingResult
{
   double                   equity_snapshot;
   double                   requested_risk_pct;
   double                   requested_risk_money;
   double                   entry_price;
   double                   stop_price;
   double                   stop_distance_points;
   double                   tick_size;
   double                   tick_value;
   double                   loss_per_lot;
   double                   raw_volume;
   double                   normalized_volume;
   double                   actual_risk_money;
   double                   actual_risk_pct;
   double                   normalization_error;
   bool                     minimum_volume_ok;
   bool                     partial_capable;
   ENUM_MSZZ_SIZING_RESULT  sizing_result;
   string                   reject_reason;
};

class CMSZZPositionSizing
{
public:
   // Recommended conservative rule (frozen, D029 Phase 0): normalize down
   // to the nearest valid broker volume step, never up beyond requested
   // risk. Never silently forces the minimum lot if that would exceed the
   // requested risk -- see the min-volume rejection path in Calculate().
   static double NormalizeDown(const double raw_volume,const double volume_step,
                                const double volume_max)
   {
      if(volume_step<=0.0) return 0.0;
      double steps=MathFloor(raw_volume/volume_step+1e-9);
      double normalized=NormalizeDouble(steps*volume_step,8);
      if(volume_max>0.0 && normalized>volume_max)
         normalized=NormalizeDouble(MathFloor(volume_max/volume_step)*volume_step,8);
      return normalized;
   }

   // Fails closed (returns false, sizing_result=MSZZ_SIZING_REJECTED,
   // reject_reason populated) on: invalid equity/risk percent, invalid
   // tick metadata, invalid volume metadata, zero/negative stop distance,
   // nonpositive loss-per-lot, normalized volume below the broker minimum,
   // or (defense-in-depth; unreachable by construction given the
   // normalize-down rule) normalized actual risk exceeding requested risk.
   static bool Calculate(const double equity,const double risk_pct,
                          const double entry_price,const double stop_price,
                          const double tick_size,const double tick_value,
                          const double volume_min,const double volume_step,
                          const double volume_max,
                          MSZZSizingResult &result)
   {
      ZeroMemory(result);
      result.equity_snapshot=equity;
      result.requested_risk_pct=risk_pct;
      result.entry_price=entry_price;
      result.stop_price=stop_price;
      result.tick_size=tick_size;
      result.tick_value=tick_value;
      result.sizing_result=MSZZ_SIZING_REJECTED;

      if(equity<=0.0 || risk_pct<=0.0)
      { result.reject_reason="invalid equity or risk percent"; return false; }
      if(tick_size<=0.0 || tick_value<=0.0)
      { result.reject_reason="invalid tick metadata"; return false; }
      if(volume_min<=0.0 || volume_step<=0.0)
      { result.reject_reason="invalid volume metadata"; return false; }

      double stop_distance=MathAbs(entry_price-stop_price);
      result.stop_distance_points=stop_distance;
      if(stop_distance<=0.0)
      { result.reject_reason="stop distance is zero or negative"; return false; }

      result.requested_risk_money=equity*risk_pct/100.0;
      double loss_per_lot=(stop_distance/tick_size)*tick_value;
      result.loss_per_lot=loss_per_lot;
      if(loss_per_lot<=0.0)
      { result.reject_reason="calculated loss per lot is nonpositive"; return false; }

      double raw_volume=result.requested_risk_money/loss_per_lot;
      result.raw_volume=raw_volume;
      if(raw_volume<=0.0)
      { result.reject_reason="raw volume nonpositive"; return false; }

      double normalized=NormalizeDown(raw_volume,volume_step,volume_max);
      result.normalized_volume=normalized;

      if(normalized<volume_min-1e-9)
      {
         result.minimum_volume_ok=false;
         result.reject_reason="normalized volume below broker minimum -- not silently forced up";
         return false;
      }
      result.minimum_volume_ok=true;

      double actual_risk_money=normalized*loss_per_lot;
      result.actual_risk_money=actual_risk_money;
      result.actual_risk_pct=(equity>0.0)?(actual_risk_money/equity*100.0):0.0;
      result.normalization_error=result.requested_risk_money-actual_risk_money;

      if(actual_risk_money>result.requested_risk_money+1e-6)
      {
         result.reject_reason="normalized volume exceeds requested risk";
         return false;
      }

      result.partial_capable=(normalized>=2.0*volume_step-1e-9);
      result.sizing_result=MSZZ_SIZING_OK;
      result.reject_reason="";
      return true;
   }
};

#endif
