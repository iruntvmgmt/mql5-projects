//+------------------------------------------------------------------+
//|                                   QuantBeast/TPOutcomeTracker.mqh |
//|                 XAUUSD Quant Beast EA - TP Forward Outcome Track |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TPOUTCOMETRACKER_MQH
#define QB_TPOUTCOMETRACKER_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Strategies/TrendPullbackEngine.mqh"

//+------------------------------------------------------------------+
//| Observation-only forward-outcome tracker for TP resume_candidate  |
//| events.                                                            |
//|                                                                    |
//| Registers exactly one event per naturally reached resume_candidate|
//| bar (see CheckAndRegister), freezes its direction and reference    |
//| values at that instant, then measures forward MFE/MAE in           |
//| nominated-direction ATR units over predeclared 3/6/12/24-bar       |
//| horizons as future completed bars arrive (see UpdatePending). It   |
//| NEVER creates a StrategySignal, places a trade, invokes            |
//| arbitration/risk, or modifies portfolio/eligibility state -- its   |
//| entire API surface only accepts MarketSnapshot/FeatureSnapshot/    |
//| RegimeState (by const-ish reference) and reads const accessors on  |
//| CTrendPullbackEngine, so there is no execution path reachable from |
//| this class at all.                                                 |
//+------------------------------------------------------------------+
#define QB_TP_OUTCOME_HORIZON_COUNT   4          // 0=H3, 1=H6, 2=H12, 3=H24
#define QB_TP_OUTCOME_SCHEMA_VERSION  1
#define QB_TP_OUTCOME_MAX_PENDING     64          // steady-state pending is bounded by the largest horizon (24)

struct TPOutcomeEvent
{
   string   event_id;
   string   symbol;
   datetime registration_time;
   string   direction;                // "up" / "down" -- frozen at registration, never re-derived
   double   ref_price;                 // closed_close of the registration bar
   double   atr_ref;                   // atr of the registration bar (fixed normalizer for all horizons)
   string   seed_source;               // "structural" / "tp_specific"
   datetime impulse_start_time;
   double   impulse_start_price;
   double   impulse_extreme;
   double   impulse_span_atr;
   double   retracement_depth;         // |extreme-refPrice| / |extreme-start|
   int      lifecycle_bars;
   ENUM_TREND_REGIME      regime_trend;
   ENUM_VOLATILITY_REGIME regime_vol;
   ENUM_STRUCTURE_REGIME  regime_structure;
   ENUM_SESSION_TYPE      session;
   double   spread_points;
   double   dir_efficiency;
   int      trend_persistence;
   double   slope_norm;
   double   displacement;

   int      bars_elapsed;              // forward completed bars observed since registration

   double   mfe_atr[QB_TP_OUTCOME_HORIZON_COUNT];
   double   mae_atr[QB_TP_OUTCOME_HORIZON_COUNT];
   double   close_return_atr[QB_TP_OUTCOME_HORIZON_COUNT];   // only meaningful once status==COMPLETE
   int      reached_p25[QB_TP_OUTCOME_HORIZON_COUNT];        // bar index first reached; 0 = not reached
   int      reached_p50[QB_TP_OUTCOME_HORIZON_COUNT];
   int      reached_p100[QB_TP_OUTCOME_HORIZON_COUNT];
   int      reachedNeg_p25[QB_TP_OUTCOME_HORIZON_COUNT];
   int      reachedNeg_p50[QB_TP_OUTCOME_HORIZON_COUNT];
   int      reachedNeg_p100[QB_TP_OUTCOME_HORIZON_COUNT];
   string   first_threshold[QB_TP_OUTCOME_HORIZON_COUNT];    // "", "FAVORABLE", "ADVERSE", "AMBIGUOUS_SAME_BAR"
   int      bars_to_mfe[QB_TP_OUTCOME_HORIZON_COUNT];
   int      bars_to_mae[QB_TP_OUTCOME_HORIZON_COUNT];
   string   status[QB_TP_OUTCOME_HORIZON_COUNT];             // "PENDING","COMPLETE","TRUNCATED"
};

class CTPOutcomeTracker
{
private:
   bool           m_enabled;
   bool           m_isTester;
   int            m_handle;
   int            m_horizons[QB_TP_OUTCOME_HORIZON_COUNT];
   TPOutcomeEvent m_pending[QB_TP_OUTCOME_MAX_PENDING];
   int            m_pendingCount;
   datetime       m_lastUpdateCalcTime;
   datetime       m_lastRegisterCalcTime;
   long           m_totalRegistered;
   long           m_totalFinalized;
   TPOutcomeEvent m_lastFinalized;      // test-inspection only; not used by production write path

   //+------------------------------------------------------------------+
   string BuildEventID(datetime impulseStart, string direction, datetime registrationTime) const
   {
      return "TP_" + IntegerToString((long)impulseStart) + "_" + direction +
             "_" + IntegerToString((long)registrationTime);
   }

   //+------------------------------------------------------------------+
   //| depth = 0 at the impulse extreme, 1.0 at a full retrace to the    |
   //| impulse start, >1.0 on an overshoot. Returns -1.0 (skip sentinel) |
   //| for a degenerate (near-zero-span) impulse.                        |
   //+------------------------------------------------------------------+
   double ComputeRetracementDepth(double extreme, double start, double refPrice) const
   {
      double span = MathAbs(extreme - start);
      if(span <= QB_EPSILON) return -1.0;
      return MathAbs(extreme - refPrice) / span;
   }

   //+------------------------------------------------------------------+
   void InitEventHorizons(TPOutcomeEvent &e)
   {
      for(int h = 0; h < QB_TP_OUTCOME_HORIZON_COUNT; h++)
      {
         e.mfe_atr[h] = 0.0;
         e.mae_atr[h] = 0.0;
         e.close_return_atr[h] = 0.0;
         e.reached_p25[h] = 0;
         e.reached_p50[h] = 0;
         e.reached_p100[h] = 0;
         e.reachedNeg_p25[h] = 0;
         e.reachedNeg_p50[h] = 0;
         e.reachedNeg_p100[h] = 0;
         e.first_threshold[h] = "";
         e.bars_to_mfe[h] = 0;
         e.bars_to_mae[h] = 0;
         e.status[h] = "PENDING";
      }
   }

   //+------------------------------------------------------------------+
   void RemoveAt(int idx)
   {
      for(int i = idx; i < m_pendingCount - 1; i++)
         m_pending[i] = m_pending[i + 1];
      m_pendingCount--;
   }

   //+------------------------------------------------------------------+
   void WriteRow(const TPOutcomeEvent &e, string finalizeReason)
   {
      if(m_handle == INVALID_HANDLE) return;

      string fields[76];
      int i = 0;
      fields[i++] = e.event_id;
      fields[i++] = e.symbol;
      fields[i++] = IntegerToString(QB_TP_OUTCOME_SCHEMA_VERSION);
      fields[i++] = FormatTime(e.registration_time);
      fields[i++] = e.direction;
      fields[i++] = DoubleToString(e.ref_price, 5);
      fields[i++] = DoubleToString(e.atr_ref, 5);
      fields[i++] = e.seed_source;
      fields[i++] = FormatTime(e.impulse_start_time);
      fields[i++] = DoubleToString(e.impulse_start_price, 5);
      fields[i++] = DoubleToString(e.impulse_extreme, 5);
      fields[i++] = DoubleToString(e.impulse_span_atr, 3);
      fields[i++] = DoubleToString(e.retracement_depth, 3);
      fields[i++] = IntegerToString(e.lifecycle_bars);
      fields[i++] = EnumToString(e.regime_trend);
      fields[i++] = EnumToString(e.regime_vol);
      fields[i++] = EnumToString(e.regime_structure);
      fields[i++] = EnumToString(e.session);
      fields[i++] = DoubleToString(e.spread_points, 1);
      fields[i++] = DoubleToString(e.dir_efficiency, 3);
      fields[i++] = IntegerToString(e.trend_persistence);
      fields[i++] = DoubleToString(e.slope_norm, 3);
      fields[i++] = DoubleToString(e.displacement, 3);
      fields[i++] = finalizeReason;

      for(int h = 0; h < QB_TP_OUTCOME_HORIZON_COUNT; h++)
      {
         fields[i++] = DoubleToString(e.mfe_atr[h], 3);
         fields[i++] = DoubleToString(e.mae_atr[h], 3);
         fields[i++] = (e.status[h] == "COMPLETE") ? DoubleToString(e.close_return_atr[h], 3) : "";
         fields[i++] = IntegerToString(e.reached_p25[h]);
         fields[i++] = IntegerToString(e.reached_p50[h]);
         fields[i++] = IntegerToString(e.reached_p100[h]);
         fields[i++] = IntegerToString(e.reachedNeg_p25[h]);
         fields[i++] = IntegerToString(e.reachedNeg_p50[h]);
         fields[i++] = IntegerToString(e.reachedNeg_p100[h]);
         fields[i++] = e.first_threshold[h];
         fields[i++] = IntegerToString(e.bars_to_mfe[h]);
         fields[i++] = IntegerToString(e.bars_to_mae[h]);
         fields[i++] = e.status[h];
      }

      string row = MakeCSVRow(fields, 76);
      WriteCSVLine(m_handle, row);
      FileFlush(m_handle);
      m_totalFinalized++;
      m_lastFinalized = e;
   }

   //+------------------------------------------------------------------+
   void FinalizeAndRemove(int idx, string finalizeReason)
   {
      WriteRow(m_pending[idx], finalizeReason);
      RemoveAt(idx);
   }

public:
   //+------------------------------------------------------------------+
   CTPOutcomeTracker()
   {
      m_enabled = false;
      m_isTester = false;
      m_handle = INVALID_HANDLE;
      m_horizons[0] = 3;
      m_horizons[1] = 6;
      m_horizons[2] = 12;
      m_horizons[3] = 24;
      m_pendingCount = 0;
      m_lastUpdateCalcTime = 0;
      m_lastRegisterCalcTime = 0;
      m_totalRegistered = 0;
      m_totalFinalized = 0;
   }

   ~CTPOutcomeTracker() { Close(); }

   //+------------------------------------------------------------------+
   bool Init(bool enabled, bool isTester = false)
   {
      m_enabled = enabled;
      m_isTester = isTester;
      m_pendingCount = 0;
      m_lastUpdateCalcTime = 0;
      m_lastRegisterCalcTime = 0;
      m_totalRegistered = 0;
      m_totalFinalized = 0;
      m_handle = INVALID_HANDLE;

      if(!m_enabled) return true;

      m_handle = OpenJournalFile(QB_TP_OUTCOME_LOG,
         "EventID,Symbol,SchemaVersion,RegistrationTime,Direction,RefPrice,ATR_Ref," +
         "SeedSource,ImpulseStartTime,ImpulseStartPrice,ImpulseExtreme,ImpulseSpanATR," +
         "RetracementDepth,LifecycleBars,RegimeTrend,RegimeVol,RegimeStructure,Session," +
         "SpreadPoints,DirEfficiency,TrendPersistence,SlopeNorm,Displacement,FinalizeReason," +
         "H3_MFE_ATR,H3_MAE_ATR,H3_CloseReturn_ATR,H3_Reached_p25,H3_Reached_p50,H3_Reached_p100," +
         "H3_ReachedNeg_p25,H3_ReachedNeg_p50,H3_ReachedNeg_p100,H3_FirstThreshold,H3_BarsToMFE,H3_BarsToMAE,H3_Status," +
         "H6_MFE_ATR,H6_MAE_ATR,H6_CloseReturn_ATR,H6_Reached_p25,H6_Reached_p50,H6_Reached_p100," +
         "H6_ReachedNeg_p25,H6_ReachedNeg_p50,H6_ReachedNeg_p100,H6_FirstThreshold,H6_BarsToMFE,H6_BarsToMAE,H6_Status," +
         "H12_MFE_ATR,H12_MAE_ATR,H12_CloseReturn_ATR,H12_Reached_p25,H12_Reached_p50,H12_Reached_p100," +
         "H12_ReachedNeg_p25,H12_ReachedNeg_p50,H12_ReachedNeg_p100,H12_FirstThreshold,H12_BarsToMFE,H12_BarsToMAE,H12_Status," +
         "H24_MFE_ATR,H24_MAE_ATR,H24_CloseReturn_ATR,H24_Reached_p25,H24_Reached_p50,H24_Reached_p100," +
         "H24_ReachedNeg_p25,H24_ReachedNeg_p50,H24_ReachedNeg_p100,H24_FirstThreshold,H24_BarsToMFE,H24_BarsToMAE,H24_Status",
         isTester);

      return (m_handle != INVALID_HANDLE);
   }

   bool IsEnabled()        const { return m_enabled; }
   int  PendingCount()     const { return m_pendingCount; }
   long TotalRegistered()  const { return m_totalRegistered; }
   long TotalFinalized()   const { return m_totalFinalized; }

   //+------------------------------------------------------------------+
   //| Read-only inspection of a still-pending event, for tests. Never   |
   //| used by production/EA code -- the tracker's own file writer is    |
   //| the only consumer of finalized event data outside this class.    |
   //+------------------------------------------------------------------+
   TPOutcomeEvent GetPending(int idx) const { return m_pending[idx]; }

   //+------------------------------------------------------------------+
   //| Read-only inspection of the most recently finalized (written) event,|
   //| for tests -- lets a test verify what Close()/horizon-completion    |
   //| actually wrote without reading the CSV file back from disk.       |
   //+------------------------------------------------------------------+
   TPOutcomeEvent GetLastFinalized() const { return m_lastFinalized; }

   //+------------------------------------------------------------------+
   //| Register a new event iff the engine is settled at resume_candidate|
   //| for a bar not already registered. Purely reads const accessors on |
   //| tp -- no mutation of the engine occurs.                           |
   //+------------------------------------------------------------------+
   void CheckAndRegister(CTrendPullbackEngine &tp, const MarketSnapshot &market,
                         const FeatureSnapshot &f, const RegimeState &regime, string symbol)
   {
      if(!m_enabled) return;
      if(f.calc_time == m_lastRegisterCalcTime) return;         // defensive dedupe (Test 66)
      if(tp.GetLifecyclePhase() != "resume_candidate") return;
      m_lastRegisterCalcTime = f.calc_time;

      if(f.atr <= 0)
      {
         QBLogDebug("TPOutcomeTracker: skip registration, atr<=0");
         return;
      }

      double depth = ComputeRetracementDepth(tp.GetImpulseExtreme(), tp.GetImpulseStartPrice(), f.closed_close);
      if(depth < 0)
      {
         QBLogDebug("TPOutcomeTracker: skip registration, degenerate impulse span");
         return;
      }

      if(m_pendingCount >= QB_TP_OUTCOME_MAX_PENDING)
      {
         QBLogWarn("TPOutcomeTracker: pending cap reached, dropping registration");
         return;
      }

      int n = m_pendingCount;
      m_pending[n].event_id = BuildEventID(tp.GetImpulseStartTime(), tp.GetLifecycleDirection(), f.calc_time);
      m_pending[n].symbol = symbol;
      m_pending[n].registration_time = f.calc_time;
      m_pending[n].direction = tp.GetLifecycleDirection();
      m_pending[n].ref_price = f.closed_close;
      m_pending[n].atr_ref = f.atr;
      m_pending[n].seed_source = tp.GetLifecycleSeedSource();
      m_pending[n].impulse_start_time = tp.GetImpulseStartTime();
      m_pending[n].impulse_start_price = tp.GetImpulseStartPrice();
      m_pending[n].impulse_extreme = tp.GetImpulseExtreme();
      m_pending[n].impulse_span_atr = tp.GetImpulseSpanATR();
      m_pending[n].retracement_depth = depth;
      m_pending[n].lifecycle_bars = tp.GetLifecycleBars();
      m_pending[n].regime_trend = regime.trend;
      m_pending[n].regime_vol = regime.volatility;
      m_pending[n].regime_structure = regime.structure;
      m_pending[n].session = regime.session;
      m_pending[n].spread_points = market.spread_points;
      m_pending[n].dir_efficiency = f.dir_efficiency;
      m_pending[n].trend_persistence = f.trend_persistence;
      m_pending[n].slope_norm = f.slope_norm;
      m_pending[n].displacement = f.displacement;
      m_pending[n].bars_elapsed = 0;
      InitEventHorizons(m_pending[n]);

      m_pendingCount++;
      m_totalRegistered++;
   }

   //+------------------------------------------------------------------+
   //| Fold one new completed bar into every still-pending event. Only   |
   //| ever reads closed_* fields of a bar strictly after registration -- |
   //| the registration bar itself is never folded in, since bars_elapsed|
   //| starts at 0 and is incremented before any MFE/MAE update.         |
   //+------------------------------------------------------------------+
   void UpdatePending(const FeatureSnapshot &f)
   {
      if(!m_enabled || m_pendingCount == 0) return;
      if(f.calc_time == m_lastUpdateCalcTime) return;
      m_lastUpdateCalcTime = f.calc_time;
      if(f.closed_high <= 0 || f.closed_low <= 0) return;

      for(int idx = m_pendingCount - 1; idx >= 0; idx--)
      {
         int dirSign = (m_pending[idx].direction == "up") ? 1 : -1;
         m_pending[idx].bars_elapsed++;
         int bars = m_pending[idx].bars_elapsed;

         double favorable = (dirSign > 0) ? (f.closed_high - m_pending[idx].ref_price)
                                           : (m_pending[idx].ref_price - f.closed_low);
         double adverse   = (dirSign > 0) ? (m_pending[idx].ref_price - f.closed_low)
                                           : (f.closed_high - m_pending[idx].ref_price);
         double favATR = favorable / m_pending[idx].atr_ref;
         double advATR = adverse   / m_pending[idx].atr_ref;

         bool largestHorizonResolved = false;
         for(int h = 0; h < QB_TP_OUTCOME_HORIZON_COUNT; h++)
         {
            if(m_pending[idx].status[h] != "PENDING" || bars > m_horizons[h]) continue;

            if(favATR > m_pending[idx].mfe_atr[h])
            {
               m_pending[idx].mfe_atr[h] = favATR;
               m_pending[idx].bars_to_mfe[h] = bars;
            }
            if(advATR > m_pending[idx].mae_atr[h])
            {
               m_pending[idx].mae_atr[h] = advATR;
               m_pending[idx].bars_to_mae[h] = bars;
            }

            bool favHit = false, advHit = false;
            if(favATR >= 1.00 && m_pending[idx].reached_p100[h] == 0) { m_pending[idx].reached_p100[h] = bars; favHit = true; }
            if(favATR >= 0.50 && m_pending[idx].reached_p50[h]  == 0) { m_pending[idx].reached_p50[h]  = bars; favHit = true; }
            if(favATR >= 0.25 && m_pending[idx].reached_p25[h]  == 0) { m_pending[idx].reached_p25[h]  = bars; favHit = true; }
            if(advATR >= 1.00 && m_pending[idx].reachedNeg_p100[h] == 0) { m_pending[idx].reachedNeg_p100[h] = bars; advHit = true; }
            if(advATR >= 0.50 && m_pending[idx].reachedNeg_p50[h]  == 0) { m_pending[idx].reachedNeg_p50[h]  = bars; advHit = true; }
            if(advATR >= 0.25 && m_pending[idx].reachedNeg_p25[h]  == 0) { m_pending[idx].reachedNeg_p25[h]  = bars; advHit = true; }

            if(m_pending[idx].first_threshold[h] == "" && (favHit || advHit))
               m_pending[idx].first_threshold[h] = (favHit && advHit) ? "AMBIGUOUS_SAME_BAR" :
                                                    (favHit ? "FAVORABLE" : "ADVERSE");

            if(bars == m_horizons[h])
            {
               m_pending[idx].close_return_atr[h] = dirSign * (f.closed_close - m_pending[idx].ref_price) /
                                                     m_pending[idx].atr_ref;
               m_pending[idx].status[h] = "COMPLETE";
            }
         }

         if(bars >= m_horizons[QB_TP_OUTCOME_HORIZON_COUNT - 1])
            largestHorizonResolved = true;

         if(largestHorizonResolved)
            FinalizeAndRemove(idx, "HORIZON_COMPLETE");
      }
   }

   //+------------------------------------------------------------------+
   //| Finalize any still-pending events as TRUNCATED and flush the file.|
   //+------------------------------------------------------------------+
   void Close()
   {
      if(m_enabled)
      {
         for(int idx = m_pendingCount - 1; idx >= 0; idx--)
         {
            for(int h = 0; h < QB_TP_OUTCOME_HORIZON_COUNT; h++)
               if(m_pending[idx].status[h] == "PENDING")
                  m_pending[idx].status[h] = "TRUNCATED";
            FinalizeAndRemove(idx, "RUN_END_TRUNCATED");
         }
      }

      if(m_handle != INVALID_HANDLE)
      {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
      }
   }
};

#endif // QB_TPOUTCOMETRACKER_MQH
