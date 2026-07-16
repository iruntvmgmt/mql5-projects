//+------------------------------------------------------------------+
//|                                         QuantBeast/SessionEngine.mqh|
//|                          XAUUSD Quant Beast EA - Session Classifier|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_SESSIONENGINE_MQH
#define QB_SESSIONENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/TimeUtils.mqh"

//+------------------------------------------------------------------+
//| Session configuration (per-instance)                              |
//+------------------------------------------------------------------+
struct SessionConfig
{
   int asiaStartHour,       asiaStartMin;
   int londonPreopenHour,   londonPreopenMin;
   int londonOpenHour,      londonOpenMin;
   int nyPreopenHour,       nyPreopenMin;
   int nyOpenHour,          nyOpenMin;
   int nyAfternoonHour,     nyAfternoonMin;
   int rolloverHour,        rolloverMin;
   int fridayCloseHour,     fridayCloseMin;
   int brokerUTCOffsetHours;
   bool brokerIsDST;
};

//+------------------------------------------------------------------+
//| Session Engine - classifies the current session                   |
//+------------------------------------------------------------------+
class CSessionEngine
{
private:
   SessionConfig      m_config;
   ENUM_SESSION_TYPE  m_currentSession;
   ENUM_SESSION_TYPE  m_prevSession;
   datetime           m_sessionStart;
   int                m_sessionMinutes;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSessionEngine()
   {
      ZeroMemory(m_config);
      m_currentSession = SESSION_UNKNOWN;
      m_prevSession    = SESSION_UNKNOWN;
      m_sessionStart   = 0;
      m_sessionMinutes = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize from configuration inputs                              |
   //+------------------------------------------------------------------+
   void Init(const SessionConfig &config)
   {
      m_config = config;
      QBLogInfo("SessionEngine initialized (Broker UTC offset=" +
                IntegerToString(config.brokerUTCOffsetHours) + "h)");
   }

   //+------------------------------------------------------------------+
   //| Get session start time in minutes since midnight (server time)    |
   //+------------------------------------------------------------------+
   int SessionTimeToMinutes(int hour, int minute) const
   {
      return hour * 60 + minute;
   }

   //+------------------------------------------------------------------+
   //| Classify the session for a given datetime                         |
   //+------------------------------------------------------------------+
   ENUM_SESSION_TYPE Classify(datetime t)
   {
      // Weekend check first
      if(IsWeekend(t))
         return SESSION_WEEKEND;

      int dow = GetDayOfWeekISO(t);
      int minutes = GetMinutesSinceMidnight(t);

      // Friday close
      if(dow == 5)
      {
         int fridayClose = SessionTimeToMinutes(m_config.fridayCloseHour, m_config.fridayCloseMin);
         if(minutes >= fridayClose)
            return SESSION_FRIDAY_CLOSE;
      }

      // Rollover
      int rolloverMin = SessionTimeToMinutes(m_config.rolloverHour, m_config.rolloverMin);
      if(minutes >= rolloverMin)
         return SESSION_ROLLOVER;

      // NY Afternoon
      int nyAfterMin = SessionTimeToMinutes(m_config.nyAfternoonHour, m_config.nyAfternoonMin);
      if(minutes >= nyAfterMin)
         return SESSION_NY_AFTERNOON;

      // London/NY Overlap
      int nyOpenMin = SessionTimeToMinutes(m_config.nyOpenHour, m_config.nyOpenMin);
      int londonCloseHour = m_config.nyAfternoonHour - 1; // Approximate London close
      if(londonCloseHour < 0) londonCloseHour = 16;
      int londonCloseMin = SessionTimeToMinutes(londonCloseHour, 0);

      if(minutes >= nyOpenMin && minutes < MathMin(londonCloseMin, nyAfterMin))
         return SESSION_LONDON_NY_OVERLAP;

      // NY Open
      int nyPreMin = SessionTimeToMinutes(m_config.nyPreopenHour, m_config.nyPreopenMin);
      if(minutes >= nyPreMin && minutes < nyOpenMin)
         return SESSION_NY_PREOPEN;

      if(minutes >= nyOpenMin && minutes < nyAfterMin)
         return SESSION_NY_OPEN;

      // London Open
      int londonOpenMin = SessionTimeToMinutes(m_config.londonOpenHour, m_config.londonOpenMin);
      int londonPreMin  = SessionTimeToMinutes(m_config.londonPreopenHour, m_config.londonPreopenMin);

      if(minutes >= londonPreMin && minutes < londonOpenMin)
         return SESSION_LONDON_PREOPEN;

      if(minutes >= londonOpenMin && minutes < nyPreMin)
      {
         // If in London session but before NY overlap
         // Check if it's the first hour for "London Open"
         if(minutes < londonOpenMin + 60)
            return SESSION_LONDON_OPEN;
         return SESSION_LONDON;
      }

      // Asia
      int asiaStartMin = SessionTimeToMinutes(m_config.asiaStartHour, m_config.asiaStartMin);
      if(minutes >= asiaStartMin && minutes < londonPreMin)
         return SESSION_ASIA;

      // Pre-Asia (early morning before Asia opens)
      return SESSION_ASIA;
   }

   //+------------------------------------------------------------------+
   //| Update session classification                                    |
   //+------------------------------------------------------------------+
   void Update(datetime t)
   {
      m_prevSession = m_currentSession;
      ENUM_SESSION_TYPE newSession = Classify(t);

      if(newSession != m_currentSession)
      {
         m_sessionStart = t;
         m_currentSession = newSession;
         QBLogDebug("Session changed: " + EnumToString(m_prevSession) +
                    " -> " + EnumToString(m_currentSession));
      }

      m_sessionMinutes = GetMinutesSinceMidnight(t);
   }

   //+------------------------------------------------------------------+
   //| Get current session                                               |
   //+------------------------------------------------------------------+
   ENUM_SESSION_TYPE GetCurrentSession() const { return m_currentSession; }

   //+------------------------------------------------------------------+
   //| Check if current session is active/tradeable                      |
   //+------------------------------------------------------------------+
   bool IsTradeableSession() const
   {
      switch(m_currentSession)
      {
         case SESSION_WEEKEND:
         case SESSION_FRIDAY_CLOSE:
         case SESSION_ROLLOVER:
            return false;
         default:
            return true;
      }
   }

   //+------------------------------------------------------------------+
   //| Check if we're in a high-liquidity session                        |
   //+------------------------------------------------------------------+
   bool IsHighLiquiditySession() const
   {
      switch(m_currentSession)
      {
         case SESSION_LONDON:
         case SESSION_LONDON_OPEN:
         case SESSION_NY_OPEN:
         case SESSION_LONDON_NY_OVERLAP:
            return true;
         default:
            return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Check if we're in a low-liquidity session                         |
   //+------------------------------------------------------------------+
   bool IsLowLiquiditySession() const
   {
      switch(m_currentSession)
      {
         case SESSION_ASIA:
         case SESSION_FRIDAY_CLOSE:
         case SESSION_ROLLOVER:
         case SESSION_NY_AFTERNOON:
            return true;
         default:
            return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Get session name string                                           |
   //+------------------------------------------------------------------+
   string GetSessionName() const
   {
      return EnumToString(m_currentSession);
   }

   //+------------------------------------------------------------------+
   //| Get minutes until session end (approximate)                       |
   //+------------------------------------------------------------------+
   int GetMinutesToSessionEnd() const
   {
      switch(m_currentSession)
      {
         case SESSION_ASIA:
            return SessionTimeToMinutes(m_config.londonPreopenHour, m_config.londonPreopenMin) - m_sessionMinutes;
         case SESSION_LONDON_PREOPEN:
            return SessionTimeToMinutes(m_config.londonOpenHour, m_config.londonOpenMin) - m_sessionMinutes;
         case SESSION_LONDON_OPEN:
            return 60 - (m_sessionMinutes - SessionTimeToMinutes(m_config.londonOpenHour, m_config.londonOpenMin));
         case SESSION_LONDON:
            return SessionTimeToMinutes(m_config.nyPreopenHour, m_config.nyPreopenMin) - m_sessionMinutes;
         case SESSION_NY_PREOPEN:
            return SessionTimeToMinutes(m_config.nyOpenHour, m_config.nyOpenMin) - m_sessionMinutes;
         case SESSION_NY_OPEN:
            return SessionTimeToMinutes(m_config.nyAfternoonHour, m_config.nyAfternoonMin) - m_sessionMinutes;
         case SESSION_LONDON_NY_OVERLAP:
            return SessionTimeToMinutes(m_config.nyAfternoonHour, m_config.nyAfternoonMin) - m_sessionMinutes;
         case SESSION_NY_AFTERNOON:
            return SessionTimeToMinutes(m_config.rolloverHour, m_config.rolloverMin) - m_sessionMinutes;
         case SESSION_ROLLOVER:
            return 60; // Approximately
         default:
            return 0;
      }
   }

   //+------------------------------------------------------------------+
   //| Print session diagnostics                                         |
   //+------------------------------------------------------------------+
   void PrintDiagnostics(datetime t)
   {
      ENUM_SESSION_TYPE sess = Classify(t);
      QBLogInfoS("Current Session", EnumToString(sess));
      QBLogInfoV("Server Time", (double)GetMinutesSinceMidnight(t)/60.0, 2);
   }
};

#endif // QB_SESSIONENGINE_MQH
