#ifndef __MSZZ_EVENT_STORE_MQH__
#define __MSZZ_EVENT_STORE_MQH__

class CMSZZEventStore
{
private:
   string m_events[];
   string m_filename;
   int    m_max_events;

   bool ContainsInternal(const string event_id) const
   {
      for(int i=0;i<ArraySize(m_events);i++)
         if(m_events[i]==event_id) return true;
      return false;
   }

   bool SaveAll()
   {
      int h=FileOpen(m_filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE)
      {
         PrintFormat("MSZZ event store write failed file=%s error=%d",m_filename,GetLastError());
         return false;
      }
      for(int i=0;i<ArraySize(m_events);i++) FileWriteString(h,m_events[i]+"\r\n");
      FileFlush(h);
      FileClose(h);
      return true;
   }

public:
   CMSZZEventStore(void)
   {
      m_filename="MSZZ_ConsumedEvents.txt";
      m_max_events=2000;
   }

   void Configure(const string symbol,const ENUM_TIMEFRAMES timeframe,const long magic,const int max_events=2000)
   {
      string safe_symbol=symbol;
      StringReplace(safe_symbol,"/","_");
      StringReplace(safe_symbol,"\\","_");
      StringReplace(safe_symbol,":","_");
      m_filename=StringFormat("MSZZ_Consumed_%s_%d_%I64d.txt",safe_symbol,(int)timeframe,magic);
      m_max_events=MathMax(100,max_events);
   }

   bool Load()
   {
      ArrayResize(m_events,0);
      int h=FileOpen(m_filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(h==INVALID_HANDLE)
      {
         if(GetLastError()==5004) return true;
         PrintFormat("MSZZ event store read failed file=%s error=%d",m_filename,GetLastError());
         return false;
      }
      while(!FileIsEnding(h))
      {
         string line=FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(line=="" || ContainsInternal(line)) continue;
         int n=ArraySize(m_events);
         ArrayResize(m_events,n+1);
         m_events[n]=line;
      }
      FileClose(h);
      return true;
   }

   bool Contains(const string event_id) const
   {
      if(event_id=="") return false;
      return ContainsInternal(event_id);
   }

   bool Add(const string event_id)
   {
      if(event_id=="" || ContainsInternal(event_id)) return true;
      int n=ArraySize(m_events);
      ArrayResize(m_events,n+1);
      m_events[n]=event_id;
      if(ArraySize(m_events)>m_max_events)
      {
         int remove_count=ArraySize(m_events)-m_max_events;
         for(int i=remove_count;i<ArraySize(m_events);i++) m_events[i-remove_count]=m_events[i];
         ArrayResize(m_events,m_max_events);
      }
      return SaveAll();
   }

   int Count() const { return ArraySize(m_events); }
   string Filename() const { return m_filename; }
};

#endif