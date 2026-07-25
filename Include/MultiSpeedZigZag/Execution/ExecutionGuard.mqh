#ifndef __MSZZ_EXECUTION_GUARD_MQH__
#define __MSZZ_EXECUTION_GUARD_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZExecutionGuard
{
private:
   string m_symbol;
   int    m_digits;
   double m_point;
   double m_min_volume;
   double m_max_volume;
   double m_volume_step;
   long   m_stops_level_points;
   long   m_freeze_level_points;

public:
   CMSZZExecutionGuard(void)
   {
      m_symbol=""; m_digits=0; m_point=0.0;
      m_min_volume=0.0; m_max_volume=0.0; m_volume_step=0.0;
      m_stops_level_points=0; m_freeze_level_points=0;
   }

   bool Load(const string symbol)
   {
      m_symbol=symbol;
      m_digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      m_point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      m_min_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      m_max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      m_volume_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      m_stops_level_points=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      m_freeze_level_points=SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      return (m_point>0.0 && m_min_volume>0.0 && m_max_volume>=m_min_volume && m_volume_step>0.0);
   }

   double NormalizeVolume(const double requested) const
   {
      if(m_volume_step<=0.0) return 0.0;
      double clipped=MathMax(m_min_volume,MathMin(m_max_volume,requested));
      double steps=MathFloor((clipped-m_min_volume)/m_volume_step+1e-9);
      double volume=m_min_volume+steps*m_volume_step;
      if(volume<m_min_volume) volume=m_min_volume;
      if(volume>m_max_volume) volume=m_max_volume;
      int volume_digits=0;
      double step=m_volume_step;
      while(volume_digits<8 && MathAbs(step-MathRound(step))>1e-9)
      {
         step*=10.0;
         volume_digits++;
      }
      return NormalizeDouble(volume,volume_digits);
   }

   bool SpreadAllowed(const double max_spread_points,double &spread_points) const
   {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol,tick) || m_point<=0.0) return false;
      spread_points=(tick.ask-tick.bid)/m_point;
      if(max_spread_points<=0.0) return true;
      return spread_points<=max_spread_points;
   }

   bool TradingAllowed(string &reason) const
   {
      long trade_mode=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
      if(trade_mode==SYMBOL_TRADE_MODE_DISABLED)
      {
         reason="symbol trading disabled";
         return false;
      }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      {
         reason="terminal trading disabled";
         return false;
      }
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         reason="EA trading permission disabled";
         return false;
      }
      reason="";
      return true;
   }

   bool ValidateStops(const MSZZCandidate &candidate,double &normalized_stop,double &normalized_target,string &reason) const
   {
      normalized_stop=NormalizeDouble(candidate.stop,m_digits);
      normalized_target=NormalizeDouble(candidate.target,m_digits);
      if(candidate.entry<=0.0 || normalized_stop<=0.0 || normalized_target<=0.0)
      {
         reason="non-positive entry/stop/target";
         return false;
      }
      double min_distance=(double)MathMax(m_stops_level_points,m_freeze_level_points)*m_point;
      if(candidate.direction==MSZZ_DIR_LONG)
      {
         if(normalized_stop>=candidate.entry || normalized_target<=candidate.entry)
         {
            reason="invalid long stop/target orientation";
            return false;
         }
         if(candidate.entry-normalized_stop<min_distance || normalized_target-candidate.entry<min_distance)
         {
            reason="long stop/target inside broker minimum distance";
            return false;
         }
      }
      else if(candidate.direction==MSZZ_DIR_SHORT)
      {
         if(normalized_stop<=candidate.entry || normalized_target>=candidate.entry)
         {
            reason="invalid short stop/target orientation";
            return false;
         }
         if(normalized_stop-candidate.entry<min_distance || candidate.entry-normalized_target<min_distance)
         {
            reason="short stop/target inside broker minimum distance";
            return false;
         }
      }
      else
      {
         reason="missing trade direction";
         return false;
      }
      reason="";
      return true;
   }
};

#endif