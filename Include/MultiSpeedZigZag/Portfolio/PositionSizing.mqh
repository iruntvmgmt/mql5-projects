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

   // D029 audit remediation, Finding D: the original signature checked
   // only `>= 2*volume_step`, silently assuming volume_min==volume_step.
   // This is wrong whenever the broker's minimum tradable size exceeds its
   // step size (e.g. min=0.10, step=0.01) -- a split could pass the old
   // check while producing a leg below the broker's actual minimum, which
   // would be rejected at the broker, not caught here. volume_min is now a
   // required, independently-checked parameter: BOTH legs must individually
   // clear it, not just the whole position clearing 2x the step. Reused by
   // the EA's SR3-PCT/SR4-PCT partial-close handling and the entry-time
   // eligibility gate so this arithmetic is defined and tested in exactly
   // one place. remaining_out is `original - partial_out`, not separately
   // re-normalized -- it is always already a valid step multiple because
   // original_volume itself is always a valid step multiple (it came from
   // CMSZZPositionSizing::Calculate() or InpFixedLots, both already
   // normalized). Returns false (both outputs zero, reason populated) on
   // any invalid input, a partial leg that would be zero or consume the
   // entire position, or either leg falling below volume_min.
   static bool ComputePartialSplit(const double original_volume,const double fraction,
                                    const double volume_min,const double volume_step,
                                    double &partial_out,double &remaining_out,string &reason)
   {
      partial_out=0.0; remaining_out=0.0; reason="";
      if(original_volume<=0.0)
      { reason="invalid original volume"; return false; }
      if(volume_min<=0.0 || volume_step<=0.0)
      { reason="invalid volume metadata"; return false; }
      if(fraction<=0.0 || fraction>=1.0)
      { reason="fraction must be strictly between 0 and 1"; return false; }

      double partial=NormalizeDown(original_volume*fraction,volume_step,0.0);
      if(partial<=0.0)
      { reason="partial leg normalizes to zero"; return false; }
      if(partial>=original_volume-1e-9)
      { reason="partial leg would consume the entire position -- not a valid split"; return false; }
      double remaining=NormalizeDouble(original_volume-partial,8);
      if(remaining<=0.0)
      { reason="remaining leg is zero or negative"; return false; }
      if(partial<volume_min-1e-9)
      { reason="partial leg falls below broker minimum volume"; return false; }
      if(remaining<volume_min-1e-9)
      { reason="remaining leg falls below broker minimum volume"; return false; }

      partial_out=partial;
      remaining_out=remaining;
      return true;
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

      // D029 audit remediation, Finding D: partial_capable now reuses the
      // SAME corrected split logic as ComputePartialSplit() (both legs
      // individually >= volume_min, not just the whole position >= 2x
      // step) at the frozen D029 Phase 0 partial fraction (0.5) -- fixes
      // the prior "normalized>=2*volume_step" check, which silently
      // assumed volume_min==volume_step.
      {
         double dummy_partial,dummy_remaining; string dummy_reason;
         result.partial_capable=ComputePartialSplit(normalized,0.5,volume_min,volume_step,
                                                     dummy_partial,dummy_remaining,dummy_reason);
      }
      result.sizing_result=MSZZ_SIZING_OK;
      result.reject_reason="";
      return true;
   }
};

#endif
