//+------------------------------------------------------------------+
//|                                     QuantBeast/AllocationEngine.mqh|
//|                          XAUUSD Quant Beast EA - Allocation Engine|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_ALLOCATIONENGINE_MQH
#define QB_ALLOCATIONENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Enums.mqh"
#include "../Core/MathUtils.mqh"

//+------------------------------------------------------------------+
//| Allocation Engine - distributes the risk budget across strategies |
//|                                                                   |
//| Returns a per-strategy weight applied to the base risk percent:   |
//|   effective risk% = base risk% x GetWeight(strategyId).           |
//| Weights are normalized so their mean across known strategies is   |
//| 1.0 (the total risk budget is conserved -- reallocated, not       |
//| inflated). ALLOC_EQUAL (default) returns 1.0 for every strategy,  |
//| so enabling the engine is a no-op until the mode is changed.      |
//+------------------------------------------------------------------+
class CAllocationEngine
{
private:
   ENUM_ALLOCATION_MODE m_mode;
   string  m_ids[8];
   double  m_confSum[8];
   int     m_confN[8];
   double  m_rSum[8];
   int     m_rN[8];
   int     m_count;

   int IndexOf(const string id)
   {
      for(int i = 0; i < m_count; i++)
         if(m_ids[i] == id) return i;
      if(m_count >= 8) return -1;
      int idx = m_count++;
      m_ids[idx] = id;
      m_confSum[idx] = 0; m_confN[idx] = 0;
      m_rSum[idx] = 0;    m_rN[idx] = 0;
      return idx;
   }

   // Raw allocation score for a strategy under the active mode.
   double RawScore(int i) const
   {
      if(i < 0) return 1.0;
      if(m_mode == ALLOC_CONFIDENCE)
         return (m_confN[i] > 0) ? (m_confSum[i] / m_confN[i]) : 0.5;
      if(m_mode == ALLOC_PERFORMANCE)
      {
         double avgR = (m_rN[i] > 0) ? (m_rSum[i] / m_rN[i]) : 0.0;
         return MathMax(0.1, 1.0 + avgR); // keep positive; better R -> more budget
      }
      return 1.0;
   }

public:
   CAllocationEngine()
   {
      m_mode = ALLOC_EQUAL;
      m_count = 0;
   }

   void Init(ENUM_ALLOCATION_MODE mode)
   {
      m_mode = mode;
      m_count = 0;
   }

   //+------------------------------------------------------------------+
   //| Record a strategy's signal confidence (for ALLOC_CONFIDENCE).     |
   //+------------------------------------------------------------------+
   void RecordSignal(const string id, double confidence)
   {
      int i = IndexOf(id);
      if(i < 0) return;
      m_confSum[i] += confidence;
      m_confN[i]++;
   }

   //+------------------------------------------------------------------+
   //| Record a strategy's realized R outcome (for ALLOC_PERFORMANCE).   |
   //+------------------------------------------------------------------+
   void RecordOutcome(const string id, double r)
   {
      int i = IndexOf(id);
      if(i < 0) return;
      m_rSum[i] += r;
      m_rN[i]++;
   }

   //+------------------------------------------------------------------+
   //| Weight for a strategy, normalized so the mean across known        |
   //| strategies is 1.0. ALLOC_EQUAL (or no history) returns 1.0.       |
   //+------------------------------------------------------------------+
   double GetWeight(const string id)
   {
      if(m_mode == ALLOC_EQUAL || m_count == 0) return 1.0;

      int self = -1;
      double sum = 0.0;
      for(int i = 0; i < m_count; i++)
      {
         if(m_ids[i] == id) self = i;
         sum += RawScore(i);
      }
      if(self < 0 || sum <= 0.0) return 1.0;
      double mean = sum / m_count;
      if(mean <= 0.0) return 1.0;
      double w = RawScore(self) / mean;
      return Clamp(w, 0.25, 4.0); // bound the reallocation
   }

   ENUM_ALLOCATION_MODE GetMode() const { return m_mode; }
};

#endif // QB_ALLOCATIONENGINE_MQH
