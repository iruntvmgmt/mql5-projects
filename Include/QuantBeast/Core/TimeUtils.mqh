//+------------------------------------------------------------------+
//|                                          QuantBeast/TimeUtils.mqh |
//|                          XAUUSD Quant Beast EA - Time Utilities   |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TIMEUTILS_MQH
#define QB_TIMEUTILS_MQH

//+------------------------------------------------------------------+
//| Check if two datetimes are on the same calendar day (broker time) |
//+------------------------------------------------------------------+
bool IsSameDay(datetime t1, datetime t2)
{
   MqlDateTime dt1, dt2;
   TimeToStruct(t1, dt1);
   TimeToStruct(t2, dt2);
   return (dt1.year == dt2.year && dt1.mon == dt2.mon && dt1.day == dt2.day);
}

//+------------------------------------------------------------------+
//| Check if two datetimes are in the same week (Monday-based)       |
//+------------------------------------------------------------------+
bool IsSameWeek(datetime t1, datetime t2)
{
   MqlDateTime dt1, dt2;
   TimeToStruct(t1, dt1);
   TimeToStruct(t2, dt2);

   // Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
   // Calculate Monday of each week
   int dow1 = dt1.day_of_week;
   int dow2 = dt2.day_of_week;

   // Adjust Sunday (0) to 7 for easier week calculation
   if(dow1 == 0) dow1 = 7;
   if(dow2 == 0) dow2 = 7;

   // Calculate seconds to Monday 00:00 for each date
   datetime monday1 = t1 - (dow1 - 1) * 86400 - dt1.hour * 3600 - dt1.min * 60 - dt1.sec;
   datetime monday2 = t2 - (dow2 - 1) * 86400 - dt2.hour * 3600 - dt2.min * 60 - dt2.sec;

   return (monday1 == monday2);
}

//+------------------------------------------------------------------+
//| Get start of current day (00:00:00 broker time)                   |
//+------------------------------------------------------------------+
datetime GetDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Get start of current week (Monday 00:00)                          |
//+------------------------------------------------------------------+
datetime GetWeekStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);

   int dow = dt.day_of_week;
   if(dow == 0) dow = 7; // Sunday -> end of week

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime dayStart = StructToTime(dt);
   return dayStart - (dow - 1) * 86400;
}

//+------------------------------------------------------------------+
//| Get day of week (1=Mon, 5=Fri, 6=Sat, 7=Sun)                     |
//+------------------------------------------------------------------+
int GetDayOfWeekISO(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int dow = dt.day_of_week;
   if(dow == 0) dow = 7; // Sunday -> 7
   return dow;
}

//+------------------------------------------------------------------+
//| Check if time is on a weekend                                      |
//+------------------------------------------------------------------+
bool IsWeekend(datetime t)
{
   int dow = GetDayOfWeekISO(t);
   return (dow >= 6);
}

//+------------------------------------------------------------------+
//| Check if time is on Friday                                        |
//+------------------------------------------------------------------+
bool IsFriday(datetime t)
{
   return (GetDayOfWeekISO(t) == 5);
}

//+------------------------------------------------------------------+
//| Get time in minutes since midnight (broker time)                  |
//+------------------------------------------------------------------+
int GetMinutesSinceMidnight(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

//+------------------------------------------------------------------+
//| Create datetime from day start + hour + minute                    |
//+------------------------------------------------------------------+
datetime MakeTime(datetime dayBase, int hour, int minute)
{
   MqlDateTime dt;
   TimeToStruct(dayBase, dt);
   dt.hour = hour;
   dt.min  = minute;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Format timestamp to readable string for logging                    |
//+------------------------------------------------------------------+
string FormatTime(datetime t)
{
   return TimeToString(t, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
}

//+------------------------------------------------------------------+
//| Get seconds since midnight                                        |
//+------------------------------------------------------------------+
int GetSecondsSinceMidnight(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
}

#endif // QB_TIMEUTILS_MQH
