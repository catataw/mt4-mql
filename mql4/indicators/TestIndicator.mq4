/**
 * TestIndicator
 */
#include <stdlib.mqh>
#include <win32api.mqh>

#property indicator_chart_window


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   onInit(T_INDICATOR, WindowExpertName());  // INIT_TIMEZONE
   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {

   // Ermittlung von OHLC der letzten Session
   // ---------------------------------------

   // (1) Beginn- und Endzeit der letzten Session ermitteln
   datetime time = TimeCurrent();
   datetime sessionStart = GetServerSessionStartTime(time);
   while (sessionStart == -1) {
      if (last_error != ERR_MARKET_CLOSED)
         return(last_error);
      time -= 1*DAY;
      sessionStart = GetServerSessionStartTime(time);
   }
   datetime sessionEnd = sessionStart + 1*DAY;
   debug("onTick()   sessionStart = "+ TimeToStr(sessionStart, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"   sessionEnd = "+ TimeToStr(sessionEnd, TIME_DATE|TIME_MINUTES|TIME_SECONDS));

   // (2) geeignete Periode wählen
   int period = Period();
   if (period==PERIOD_M1 || period > PERIOD_H1)    // M1-History-Update ist unzuverlässig, größer als H1 ist ungeeignet
      period = PERIOD_H1;

   // (3) Beginn- und Endbar der Session ermitteln
   int startBar = iBarShiftNext(Symbol(), period, sessionStart);


   // (4) OHLC-Werte ermitteln
   /*
   Open  = iOpen (NULL, period, BeginBar);
   High  = iHigh (NULL, period, iHighest(NULL, period, MODE_HIGH, BeginBar-EndBar+1, EndBar));
   Low   = iLow  (NULL, period, iLowest (NULL, period, MODE_LOW,  BeginBar-EndBar+1, EndBar));
   Close = iClose(NULL, period, EndBar);
   */

   return(catch("onTick()"));
}


/**
 * Gibt die Tradeserver-Startzeit der Handelssession für den angegebenen Zeitpunkt zurück.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Startzeit oder -1, falls ein Fehler auftrat
 */
datetime GetServerSessionStartTime(datetime serverTime) {
   if (serverTime < 1) {
      catch("GetServerSessionStartTime(1)  invalid parameter serverTime: "+ serverTime, ERR_INVALID_FUNCTION_PARAMVALUE);
      return(-1);
   }

   int fxtOffset = GetServerToFxtOffset(datetime serverTime);
   if (fxtOffset == EMPTY_VALUE)
      return(-1);

   datetime fxt  = serverTime - fxtOffset;
   int dayOfWeek = TimeDayOfWeek(fxt);

   if (dayOfWeek==SATURDAY || dayOfWeek==SUNDAY) {
      SetLastError(ERR_MARKET_CLOSED);
      return(-1);
   }

   fxt       -= TimeHour(fxt)*HOURS + TimeMinute(fxt)*MINUTES + TimeSeconds(fxt)*SECONDS;
   serverTime = fxt + fxtOffset;

   int error = GetLastError();
   if (error != NO_ERROR) {
      catch("GetServerSessionStartTime(2)", error);
      return(-1);
   }
   return(serverTime);
}


/**
 * Gibt den Offset der angegebenen Serverzeit zu FXT (Forex Standard Time) zurück (positive Werte für östlich von FXT liegende Zeitzonen).
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetServerToFxtOffset(datetime serverTime) {
   if (serverTime < 1) {
      catch("GetServerToFxtOffset(1)   invalid parameter serverTime = "+ serverTime, ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(EMPTY_VALUE);

   // schnelle Rückkehr, wenn der Tradeserver unter FXT läuft
   if (zone == "FXT")
      return(0);

   // Offset von Server zu GMT ermitteln
   int serverToGmtOffset;
   if (zone != "GMT") {
      serverToGmtOffset = GetServerToGmtOffset(serverTime);
      if (serverToGmtOffset == EMPTY_VALUE)
         return(EMPTY_VALUE);
   }
   datetime gmt = serverTime - serverToGmtOffset;

   // Offset von GMT zu FXT ermitteln
   int gmtToFxtOffset = GetGmtToFxtOffset(gmt);
   if (gmtToFxtOffset == EMPTY_VALUE)
      return(EMPTY_VALUE);

   int error = GetLastError();
   if (error != NO_ERROR) {
      catch("GetServerToFxtOffset(2)", error);
      return(EMPTY_VALUE);
   }
   return(serverToGmtOffset + gmtToFxtOffset);
}


#include <timezones.mqh>


/**
 * Gibt den Offset der angegebenen GMT-Zeit zu FXT (Forex Standard Time) zurück (entgegengesetzter Wert des Offsets von FXT zu GMT).
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetGmtToFxtOffset(datetime gmtTime) {
   if (gmtTime < 1) {
      catch("GetGmtToFxtOffset(1)  invalid parameter gmtTime = "+ gmtTime, ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   int offset, year = TimeYear(gmtTime)-1970;

   // FXT                                       GMT+0200,GMT+0300
   if      (gmtTime < FXT_transitions[year][2]) offset = -2 * HOURS;
   else if (gmtTime < FXT_transitions[year][3]) offset = -3 * HOURS;
   else                                         offset = -2 * HOURS;

   if (catch("GetGmtToFxtOffset(2)") != NO_ERROR)
      return(EMPTY_VALUE);

   return(offset);
}












/*
double ohlc[4];
int bar   = 4000;
int error = iOHLC(NULL, PERIOD_H1, bar, ohlc);
debug("onTick()   ohlc = "+ PriceArrayToStr(ohlc, PriceFormat, NULL) + ifString(error==NO_ERROR, "", "   error = "+ ErrorToStr(error)));
*/
