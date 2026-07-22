//+------------------------------------------------------------------+
//|                                   QuantBeast/CounterfactualTracker.mqh|
//|                          XAUUSD Quant Beast EA - Counterfactuals  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_COUNTERFACTUALTRACKER_MQH
#define QB_COUNTERFACTUALTRACKER_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Counterfactual Tracker - logs the hypothetical entry/stop/target |
//| of *rejected* signals that nonetheless reached a computable setup |
//| (non-zero geometry), so the edge of the rejection filters can be  |
//| measured offline.                                                 |
//|                                                                   |
//| Rows are BUFFERED in memory during the run and written once at    |
//| Close() -- there is deliberately no per-signal file I/O, so the   |
//| tracker is guaranteed side-effect-free with respect to trading    |
//| (enabling it never perturbs signal timing). Disabled by default.  |
//+------------------------------------------------------------------+
#define QB_CF_MAX_ROWS 20000

class CCounterfactualTracker
{
private:
   bool   m_enabled;
   bool   m_isTester;
   string m_rows[QB_CF_MAX_ROWS];
   int    m_rowCount;

public:
   CCounterfactualTracker()
   {
      m_enabled  = false;
      m_isTester = false;
      m_rowCount = 0;
   }

   ~CCounterfactualTracker() { Close(); }

   bool Init(bool enabled, bool isTester = false)
   {
      m_enabled  = enabled;
      m_isTester = isTester;
      m_rowCount = 0;
      return true;
   }

   bool IsEnabled() const { return m_enabled; }
   int  RowCount()  const { return m_rowCount; }

   //+------------------------------------------------------------------+
   //| Buffer a rejected signal that had a computable hypothetical trade.|
   //| No file I/O here -- purely appends to an in-memory array, so it   |
   //| cannot affect trading behavior. No-op when disabled or when the   |
   //| geometry was never computed.                                      |
   //+------------------------------------------------------------------+
   void LogRejection(const StrategySignal &sig, const MarketSnapshot &snap,
                     const RegimeState &regime, const FeatureSnapshot &feat,
                     string symbol)
   {
      if(!m_enabled) return;
      if(sig.valid) return;                          // only rejected signals
      if(sig.proposed_entry <= 0 || sig.proposed_stop <= 0 || sig.proposed_target <= 0)
         return;                                      // no computable hypothetical trade
      if(m_rowCount >= QB_CF_MAX_ROWS) return;        // bounded buffer

      string fields[19];
      fields[0]  = FormatTime(sig.signal_time);
      fields[1]  = symbol;
      fields[2]  = sig.strategy_id;
      fields[3]  = (sig.direction == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      fields[4]  = IntegerToString(sig.setup_code);
      fields[5]  = IntegerToString(sig.rejection_code);
      fields[6]  = sig.reason;
      fields[7]  = DoubleToString(sig.proposed_entry, 5);
      fields[8]  = DoubleToString(sig.proposed_stop, 5);
      fields[9]  = DoubleToString(sig.proposed_target, 5);
      fields[10] = DoubleToString(sig.expected_reward_r, 2);
      fields[11] = DoubleToString(sig.confidence, 3);
      fields[12] = IntegerToString(regime.trend);
      fields[13] = IntegerToString(regime.volatility);
      fields[14] = DoubleToString(snap.spread_points, 1);
      fields[15] = DoubleToString(feat.atr_points, 1);
      fields[16] = sig.strategy_family;
      fields[17] = sig.strategy_template;
      fields[18] = sig.strategy_tags;

      m_rows[m_rowCount] = MakeCSVRow(fields, 19);
      m_rowCount++;
   }

   //+------------------------------------------------------------------+
   //| Flush the buffered rows to CounterfactualJournal.csv. Called at   |
   //| OnDeinit; the only file I/O the tracker ever performs.            |
   //+------------------------------------------------------------------+
   void Close()
   {
      if(!m_enabled || m_rowCount <= 0) return;

      int handle = OpenJournalFile(QB_COUNTERFACTUAL_LOG,
         "Timestamp,Symbol,Strategy,Direction,SetupCode,RejectionCode," +
         "RejectionReason,HypoEntry,HypoStop,HypoTarget,ExpectedR,Confidence," +
         "RegimeTrend,RegimeVol,Spread,ATR_Points,StrategyFamily,StrategyTemplate,StrategyTags", m_isTester);
      if(handle == INVALID_HANDLE) return;

      for(int i = 0; i < m_rowCount; i++)
         WriteCSVLine(handle, m_rows[i]);
      FileFlush(handle);
      FileClose(handle);
      m_rowCount = 0;
   }
};

#endif // QB_COUNTERFACTUALTRACKER_MQH
