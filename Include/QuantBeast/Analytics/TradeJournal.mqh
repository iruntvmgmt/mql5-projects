//+------------------------------------------------------------------+
//|                                        QuantBeast/TradeJournal.mqh|
//|                          XAUUSD Quant Beast EA - Journal System  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TRADEJOURNAL_MQH
#define QB_TRADEJOURNAL_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Trade Journal - unified logging for signals, orders, trades       |
//+------------------------------------------------------------------+
class CTradeJournal
{
private:
   int   m_signalHandle;
   int   m_orderHandle;
   int   m_tradeHandle;
   int   m_perfHandle;
   bool  m_enabledSignal;
   bool  m_enabledOrder;
   bool  m_enabledTrade;
   bool  m_initialized;

   PerformanceSummary m_perf;
   double m_sumR;
   double m_curvePnL;
   double m_curvePeak;
   int    m_currentConsecWins;
   int    m_currentConsecLosses;

public:
   //+------------------------------------------------------------------+
   CTradeJournal()
   {
      m_signalHandle  = INVALID_HANDLE;
      m_orderHandle   = INVALID_HANDLE;
      m_tradeHandle   = INVALID_HANDLE;
      m_perfHandle    = INVALID_HANDLE;
      m_enabledSignal = false;
      m_enabledOrder  = false;
      m_enabledTrade  = false;
      m_initialized   = false;
      ZeroMemory(m_perf);
      m_sumR = 0;
      m_curvePnL = 0;
      m_curvePeak = 0;
      m_currentConsecWins = 0;
      m_currentConsecLosses = 0;
   }

   //+------------------------------------------------------------------+
   ~CTradeJournal()
   {
      CloseAll();
   }

   //+------------------------------------------------------------------+
   void CloseAll()
   {
      if(m_signalHandle != INVALID_HANDLE) { FileClose(m_signalHandle); m_signalHandle = INVALID_HANDLE; }
      if(m_orderHandle  != INVALID_HANDLE) { FileClose(m_orderHandle);  m_orderHandle  = INVALID_HANDLE; }
      if(m_tradeHandle  != INVALID_HANDLE) { FileClose(m_tradeHandle);  m_tradeHandle  = INVALID_HANDLE; }
      if(m_perfHandle   != INVALID_HANDLE) { FileClose(m_perfHandle);   m_perfHandle   = INVALID_HANDLE; }
   }

   //+------------------------------------------------------------------+
   bool Init(bool enableSignal, bool enableOrder, bool enableTrade, bool isTester=false)
   {
      m_enabledSignal = enableSignal;
      m_enabledOrder  = enableOrder;
      m_enabledTrade  = enableTrade;
      bool success = true;

      if(m_enabledSignal)
      {
         m_signalHandle = OpenJournalFile(QB_SIGNAL_LOG,
            "Timestamp,Symbol,Mode,Strategy,Direction,SignalID,SetupCode,TriggerCode," +
            "Accepted,RejectionCode,RejectionReason,RegimeTrend,RegimeVol,Session," +
            "Spread,ATR_Points,Entry,Stop,Target,ExpectedR,Confidence", isTester);
         if(m_signalHandle == INVALID_HANDLE) success = false;
      }

      if(m_enabledOrder)
      {
         m_orderHandle = OpenJournalFile(QB_ORDER_LOG,
            "RequestTime,OrderType,RequestedPrice,RequestedVolume,Stop,Target," +
            "BrokerRetcode,FillPrice,SlippagePts,Retries,FinalState,Comment", isTester);
         if(m_orderHandle == INVALID_HANDLE) success = false;
      }

      if(m_enabledTrade)
      {
         m_tradeHandle = OpenJournalFile(QB_TRADE_LOG,
            "Strategy,SignalID,EntryTime,ExitTime,Direction,Entry,Exit,Volume," +
            "Stop,Target,GrossPnL,Commission,Swap,NetPnL,RMultiple,MFE,MAE," +
            "ExitReason,EntryRegime,ExitRegime,EntrySpread,Slippage", isTester);
         if(m_tradeHandle == INVALID_HANDLE) success = false;
      }

      m_initialized = success;
      return success;
   }

   //+------------------------------------------------------------------+
   //| Log a strategy signal (accepted or rejected)                      |
   //+------------------------------------------------------------------+
   bool LogSignal(const StrategySignal &sig, const MarketSnapshot &snap,
                  const RegimeState &regime, const FeatureSnapshot &feat,
                  string symbol, ENUM_QB_MODE mode)
   {
      if(!m_enabledSignal || m_signalHandle == INVALID_HANDLE) return false;

      string fields[22];
      fields[0]  = FormatTime(sig.signal_time);
      fields[1]  = symbol;
      fields[2]  = IntegerToString(mode);
      fields[3]  = sig.strategy_id;
      fields[4]  = (sig.direction == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      fields[5]  = sig.strategy_id + "_" +
                   (sig.direction == ORDER_TYPE_BUY ? "BUY_" : "SELL_") +
                   IntegerToString(sig.signal_time);
      fields[6]  = IntegerToString(sig.setup_code);
      fields[7]  = IntegerToString(sig.trigger_code);
      fields[8]  = sig.valid ? "ACCEPTED" : "REJECTED";
      fields[9]  = IntegerToString(sig.rejection_code);
      fields[10] = sig.reason;
      fields[11] = IntegerToString(regime.trend);
      fields[12] = IntegerToString(regime.volatility);
      fields[13] = IntegerToString(regime.session);
      fields[14] = DoubleToString(snap.spread_points, 1);
      fields[15] = DoubleToString(feat.atr_points, 1);
      fields[16] = DoubleToString(sig.proposed_entry, 5);
      fields[17] = DoubleToString(sig.proposed_stop, 5);
      fields[18] = DoubleToString(sig.proposed_target, 5);
      fields[19] = DoubleToString(sig.expected_reward_r, 2);
      fields[20] = DoubleToString(sig.confidence, 3);

      string row = MakeCSVRow(fields, 21);
      WriteCSVLine(m_signalHandle, row);
      FileFlush(m_signalHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Log an order execution record                                     |
   //+------------------------------------------------------------------+
   void LogOrder(const ExecutionRecord &rec)
   {
      if(!m_enabledOrder || m_orderHandle == INVALID_HANDLE) return;

      string fields[12];
      fields[0]  = FormatTime(rec.request_time);
      fields[1]  = EnumToString(rec.order_type);
      fields[2]  = DoubleToString(rec.requested_price, 5);
      fields[3]  = DoubleToString(rec.requested_volume, 2);
      fields[4]  = DoubleToString(rec.stop_loss, 5);
      fields[5]  = DoubleToString(rec.take_profit, 5);
      fields[6]  = IntegerToString((long)rec.retcode);
      fields[7]  = DoubleToString(rec.fill_price, 5);
      fields[8]  = DoubleToString(rec.slippage_points, 1);
      fields[9]  = IntegerToString(rec.retry_count);
      fields[10] = IntegerToString(rec.state);
      fields[11] = rec.comment;

      string row = MakeCSVRow(fields, 12);
      WriteCSVLine(m_orderHandle, row);
      FileFlush(m_orderHandle);
   }

   //+------------------------------------------------------------------+
   //| Log a completed trade                                             |
   //+------------------------------------------------------------------+
   void LogTrade(const PositionContext &ctx, double exitPrice,
                  double grossPnL, double commission, double swap,
                  ENUM_EXIT_REASON exitReason, ENUM_TREND_REGIME exitRegimeTrend,
                  ENUM_VOLATILITY_REGIME exitRegimeVol)
   {
      // MT5 commission and swap deal values are signed (normally negative).
      double netPnL = grossPnL + commission + swap;
      double riskDist = MathAbs(ctx.original_entry - ctx.original_stop);
      double rMultiple = (riskDist > 0) ? (exitPrice - ctx.original_entry) / riskDist : 0;
      int dir = (ctx.position_type == POSITION_TYPE_BUY) ? 1 : -1;
      rMultiple *= dir;

      if(m_enabledTrade && m_tradeHandle != INVALID_HANDLE)
      {
         string fields[22];
         fields[0]  = ctx.strategy_id;
         fields[1]  = IntegerToString(ctx.signal_id);
         fields[2]  = FormatTime(ctx.entry_time);
         fields[3]  = FormatTime(TimeCurrent());
         fields[4]  = (dir > 0) ? "LONG" : "SHORT";
         fields[5]  = DoubleToString(ctx.original_entry, 5);
         fields[6]  = DoubleToString(exitPrice, 5);
         fields[7]  = DoubleToString(ctx.initial_volume, 2);
         fields[8]  = DoubleToString(ctx.original_stop, 5);
         fields[9]  = DoubleToString(ctx.initial_target, 5);
         fields[10] = DoubleToString(grossPnL, 2);
         fields[11] = DoubleToString(commission, 2);
         fields[12] = DoubleToString(swap, 2);
         fields[13] = DoubleToString(netPnL, 2);
         fields[14] = DoubleToString(rMultiple, 2);
         fields[15] = DoubleToString(ctx.mfe, 5);
         fields[16] = DoubleToString(ctx.mae, 5);
         fields[17] = IntegerToString(exitReason);
         fields[18] = IntegerToString(ctx.entry_regime_trend);
         fields[19] = IntegerToString(exitRegimeTrend);
         fields[20] = DoubleToString(ctx.entry_spread, 1);
         fields[21] = DoubleToString(ctx.entry_slippage, 1);

         string row = MakeCSVRow(fields, 22);
         WriteCSVLine(m_tradeHandle, row);
         FileFlush(m_tradeHandle);
      }

      // Tester/performance accounting is independent of optional file output.
      UpdatePerformance(netPnL, rMultiple);
   }

   //+------------------------------------------------------------------+
   //| Update rolling performance summary                                |
   //+------------------------------------------------------------------+
   void UpdatePerformance(double netPnL, double rMultiple)
   {
      m_perf.total_trades++;

      if(netPnL > 0)
      {
         m_perf.winning_trades++;
         m_currentConsecWins++;
         m_currentConsecLosses = 0;
         m_perf.consec_wins = MathMax(m_perf.consec_wins, m_currentConsecWins);
      }
      else
      {
         m_perf.losing_trades++;
         m_currentConsecLosses++;
         m_currentConsecWins = 0;
         m_perf.consec_losses = MathMax(m_perf.consec_losses, m_currentConsecLosses);
      }

      m_perf.win_rate = (double)m_perf.winning_trades / m_perf.total_trades;
      m_perf.gross_profit += (netPnL > 0) ? netPnL : 0;
      m_perf.gross_loss   += (netPnL < 0) ? -netPnL : 0;
      m_perf.net_profit = m_perf.gross_profit - m_perf.gross_loss;
      m_perf.profit_factor = (m_perf.gross_loss > 0) ? m_perf.gross_profit / m_perf.gross_loss : 999;
      m_perf.avg_winner = (m_perf.winning_trades > 0) ?
                          m_perf.gross_profit / m_perf.winning_trades : 0;
      m_perf.avg_loser = (m_perf.losing_trades > 0) ?
                         -m_perf.gross_loss / m_perf.losing_trades : 0;
      m_perf.expectancy = m_perf.win_rate * m_perf.avg_winner +
                          (1.0 - m_perf.win_rate) * m_perf.avg_loser;
      m_sumR += rMultiple;
      m_perf.avg_r = m_sumR / m_perf.total_trades;

      m_curvePnL += netPnL;
      if(m_curvePnL > m_curvePeak) m_curvePeak = m_curvePnL;
      m_perf.max_drawdown = MathMax(m_perf.max_drawdown, m_curvePeak - m_curvePnL);
   }

   //+------------------------------------------------------------------+
   PerformanceSummary GetPerformance() const { return m_perf; }
};

#endif // QB_TRADEJOURNAL_MQH
