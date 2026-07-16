//+------------------------------------------------------------------+
//|                                        QuantBeast/PositionSizer.mqh|
//|                          XAUUSD Quant Beast EA - Position Sizing  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_POSITIONSIZER_MQH
#define QB_POSITIONSIZER_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/MathUtils.mqh"
#include "../Data/MarketData.mqh"

//+------------------------------------------------------------------+
//| Position Sizer - calculates lot size from risk parameters         |
//+------------------------------------------------------------------+
class CPositionSizer
{
private:
   CSymbolAdapter*  m_adapter;
   ENUM_MODE_LOTS   m_lotMode;
   double           m_fixedLots;
   double           m_fixedRiskCurrency;
   double           m_riskPercent;
   double           m_volAdjRiskTarget;
   double           m_minLot;
   double           m_maxLot;
   double           m_slippageAllowancePts;
   double           m_commissionEstimate; // Per lot per round-turn

   double LossPerLot(double entry, double stop)
   {
      if(entry <= 0 || stop <= 0 || MathAbs(entry - stop) < QB_EPSILON)
         return 0;

      ENUM_ORDER_TYPE type = (stop < entry) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double stopProfit = 0;
      if(!OrderCalcProfit(type, m_adapter.Symbol(), 1.0, entry, stop, stopProfit))
         return 0;

      double adversePrice = entry + ((type == ORDER_TYPE_BUY) ? -1.0 : 1.0) *
                                      m_slippageAllowancePts * m_adapter.Point();
      double slippageProfit = 0;
      if(!OrderCalcProfit(type, m_adapter.Symbol(), 1.0, entry, adversePrice, slippageProfit))
         slippageProfit = 0;

      return MathAbs(stopProfit) + MathAbs(slippageProfit) +
             MathMax(0, m_commissionEstimate);
   }

public:
   //+------------------------------------------------------------------+
   CPositionSizer()
   {
      m_adapter         = NULL;
      m_lotMode         = LOTS_MODE_RISK_PCT;
      m_fixedLots       = 0.01;
      m_fixedRiskCurrency = 20.0;
      m_riskPercent     = 1.0;
      m_volAdjRiskTarget = 1.0;
      m_minLot          = 0.01;
      m_maxLot          = 1.0;
      m_slippageAllowancePts = 10.0;
      m_commissionEstimate    = 7.0;
   }

   //+------------------------------------------------------------------+
   void Init(CSymbolAdapter &adapter, ENUM_MODE_LOTS mode,
             double fixedLots, double fixedRisk, double riskPct,
             double volAdjTarget, double minLot, double maxLot,
             double slippagePts, double commissionEst)
   {
      m_adapter           = &adapter;
      m_lotMode           = mode;
      m_fixedLots         = fixedLots;
      m_fixedRiskCurrency = fixedRisk;
      m_riskPercent       = riskPct;
      m_volAdjRiskTarget  = volAdjTarget;
      m_minLot            = MathMax(minLot, adapter.MinLot());
      m_maxLot            = MathMin(maxLot, adapter.MaxLot());
      m_slippageAllowancePts = slippagePts;
      m_commissionEstimate    = commissionEst;
   }

   //+------------------------------------------------------------------+
   //| Calculate lot size from entry, stop, and account equity           |
   //+------------------------------------------------------------------+
   double CalculateLots(double entry, double stop, double equity,
                         double atrPoints, string &reason)
   {
      double stopDist = MathAbs(entry - stop);

      if(stopDist <= 0)
      {
         reason = "Zero stop distance";
         return 0;
      }

      double lots = 0;

      switch(m_lotMode)
      {
         case LOTS_MODE_FIXED:
         {
            lots = m_fixedLots;
            break;
         }

         case LOTS_MODE_RISK_FIXED:
         {
            double riskPerLot = LossPerLot(entry, stop);
            if(riskPerLot <= 0)
            {
               reason = "OrderCalcProfit failed for fixed-risk sizing";
               return 0;
            }
            lots = m_fixedRiskCurrency / riskPerLot;
            break;
         }

         case LOTS_MODE_RISK_PCT:
         {
            // Risk percentage of equity
            double riskAmount = equity * m_riskPercent / 100.0;

            double riskPerLot = LossPerLot(entry, stop);
            if(riskPerLot <= 0)
            {
               reason = "OrderCalcProfit failed for percent-risk sizing";
               return 0;
            }
            lots = riskAmount / riskPerLot;
            break;
         }

         case LOTS_MODE_VOL_ADJ:
         {
            if(atrPoints <= 0)
            {
               reason = "Cannot calculate: zero ATR";
               return 0;
            }

            double riskAmount = equity * m_riskPercent / 100.0;
            ENUM_ORDER_TYPE type = (stop < entry) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            double atrStop = entry + ((type == ORDER_TYPE_BUY) ? -1.0 : 1.0) *
                                     atrPoints * m_volAdjRiskTarget * m_adapter.Point();
            double riskPerLotVol = MathMax(LossPerLot(entry, stop),
                                            LossPerLot(entry, atrStop));
            if(riskPerLotVol <= 0)
            {
               reason = "Vol-adjusted risk per lot is zero";
               return 0;
            }
            lots = riskAmount / riskPerLotVol;
            break;
         }
      }

      // Never force a sub-minimum risk calculation up to the minimum lot.
      if(lots + QB_EPSILON < m_minLot)
      {
         reason = "Calculated lot (" + DoubleToString(lots, 4) +
                  ") below minimum (" + DoubleToString(m_minLot, 2) + ")";
         return 0;
      }

      double lotStep = m_adapter.LotStep();
      if(lotStep > 0)
         lots = MathFloor((lots + QB_EPSILON) / lotStep) * lotStep;
      lots = MathMin(lots, m_maxLot);
      lots = NormalizeDouble(lots, 8);

      if(lots + QB_EPSILON < m_minLot)
      {
         reason = "Normalized lot below minimum";
         return 0;
      }

      return lots;
   }

   //+------------------------------------------------------------------+
   //| Estimate risk for a given position size                           |
   //+------------------------------------------------------------------+
   double EstimateRisk(double lots, double entry, double stop)
   {
      return MathAbs(lots) * LossPerLot(entry, stop);
   }

   //+------------------------------------------------------------------+
   //| Estimate margin required                                          |
   //+------------------------------------------------------------------+
   double EstimateMargin(double lots, double price, ENUM_ORDER_TYPE type)
   {
      double margin = 0;
      if(!OrderCalcMargin(type, m_adapter.Symbol(), lots, price, margin))
         return 999999; // Huge number on failure
      return margin;
   }

   //+------------------------------------------------------------------+
   //| Set challenge mode risk percent (override)                        |
   //+------------------------------------------------------------------+
   void SetRiskPercent(double pct)
   {
      m_riskPercent = pct;
   }

   double GetRiskPercent() const { return m_riskPercent; }
};

#endif // QB_POSITIONSIZER_MQH
