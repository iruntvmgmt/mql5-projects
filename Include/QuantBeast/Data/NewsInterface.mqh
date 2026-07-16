//+------------------------------------------------------------------+
//|                                        QuantBeast/NewsInterface.mqh|
//|                          XAUUSD Quant Beast EA - News Integration |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_NEWSINTERFACE_MQH
#define QB_NEWSINTERFACE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/TimeUtils.mqh"

//+------------------------------------------------------------------+
//| News Event                                                        |
//+------------------------------------------------------------------+
struct NewsEvent
{
   datetime eventTime;
   string   description;
   int      preLockoutMinutes;
   int      postLockoutMinutes;
};

//+------------------------------------------------------------------+
//| News Interface - manages event-based trading restrictions         |
//+------------------------------------------------------------------+
class CNewsInterface
{
private:
   NewsEvent   m_events[];
   int         m_eventCount;
   bool        m_enabled;
   int         m_preLockoutMinutes;
   int         m_postLockoutMinutes;
   bool        m_initialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CNewsInterface()
   {
      m_eventCount = 0;
      m_enabled    = false;
      m_preLockoutMinutes  = 15;
      m_postLockoutMinutes = 15;
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(bool enabled, int preLockoutMin, int postLockoutMin, string manualNewsCSV)
   {
      m_enabled = enabled;
      m_preLockoutMinutes  = preLockoutMin;
      m_postLockoutMinutes = postLockoutMin;

      if(!enabled)
      {
         QBLogInfo("NewsInterface disabled - no news lockout");
         m_initialized = true;
         return true;
      }

      // Parse manual news times if provided
      if(manualNewsCSV != "")
      {
         ParseManualNews(manualNewsCSV);
      }

      m_initialized = true;
      QBLogInfo("NewsInterface initialized: " + IntegerToString(m_eventCount) +
                " events loaded, pre=" + IntegerToString(m_preLockoutMinutes) +
                "m post=" + IntegerToString(m_postLockoutMinutes) + "m");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Parse manually-configured news times                              |
   //| Format: "YYYY.MM.DD HH:MM,YYYY.MM.DD HH:MM,..."                  |
   //+------------------------------------------------------------------+
   void ParseManualNews(string csv)
   {
      string entries[];
      int count = StringSplit(csv, ',', entries);

      ArrayResize(m_events, count);
      m_eventCount = 0;

      for(int i = 0; i < count; i++)
      {
         StringTrimLeft(entries[i]);
         StringTrimRight(entries[i]);

         datetime t = StringToTime(entries[i]);
         if(t > 0)
         {
            m_events[m_eventCount].eventTime = t;
            m_events[m_eventCount].description = "Manual event";
            m_events[m_eventCount].preLockoutMinutes  = m_preLockoutMinutes;
            m_events[m_eventCount].postLockoutMinutes = m_postLockoutMinutes;
            m_eventCount++;
         }
         else
         {
            QBLogWarn("Cannot parse news time: '" + entries[i] + "'");
         }
      }

      if(m_eventCount > 0)
      {
         // Sort by time
         SortEvents();
      }
   }

   //+------------------------------------------------------------------+
   //| Sort events by time (bubble sort - small arrays)                  |
   //+------------------------------------------------------------------+
   void SortEvents()
   {
      for(int i = 0; i < m_eventCount - 1; i++)
      {
         for(int j = i + 1; j < m_eventCount; j++)
         {
            if(m_events[j].eventTime < m_events[i].eventTime)
            {
               NewsEvent temp = m_events[i];
               m_events[i] = m_events[j];
               m_events[j] = temp;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get current event state for a given time                          |
   //+------------------------------------------------------------------+
   ENUM_EVENT_STATE GetEventState(datetime t)
   {
      if(!m_enabled) return EVENT_NORMAL;

      for(int i = 0; i < m_eventCount; i++)
      {
         datetime eventStart = m_events[i].eventTime;
         int preMin  = m_events[i].preLockoutMinutes;
         int postMin = m_events[i].postLockoutMinutes;

         datetime preStart  = eventStart - preMin * 60;
         datetime postEnd   = eventStart + postMin * 60;

         if(t >= preStart && t < eventStart)
            return EVENT_PRE_NEWS_LOCKOUT;

         if(t >= eventStart && t < postEnd)
            return EVENT_POST_NEWS_DISCOVERY;
      }

      return EVENT_NORMAL;
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed right now                             |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed(datetime t)
   {
      ENUM_EVENT_STATE state = GetEventState(t);
      return (state == EVENT_NORMAL);
   }

   //+------------------------------------------------------------------+
   //| Get minutes until next event                                      |
   //+------------------------------------------------------------------+
   int MinutesToNextEvent(datetime t)
   {
      if(!m_enabled || m_eventCount == 0) return 9999;

      for(int i = 0; i < m_eventCount; i++)
      {
         if(m_events[i].eventTime > t)
         {
            int diff = (int)((m_events[i].eventTime - t) / 60);
            return MathMax(0, diff);
         }
      }
      return 9999;
   }

   //+------------------------------------------------------------------+
   //| Add a news event programmatically                                 |
   //+------------------------------------------------------------------+
   void AddEvent(datetime eventTime, string desc, int preMin, int postMin)
   {
      int idx = m_eventCount;
      ArrayResize(m_events, idx + 1);
      m_events[idx].eventTime = eventTime;
      m_events[idx].description = desc;
      m_events[idx].preLockoutMinutes = preMin;
      m_events[idx].postLockoutMinutes = postMin;
      m_eventCount++;
      SortEvents();
   }

   //+------------------------------------------------------------------+
   //| Get event count                                                   |
   //+------------------------------------------------------------------+
   int GetEventCount() const { return m_eventCount; }

   //+------------------------------------------------------------------+
   //| Is initialized                                                    |
   //+------------------------------------------------------------------+
   bool IsInitialized() const { return m_initialized; }
};

#endif // QB_NEWSINTERFACE_MQH
