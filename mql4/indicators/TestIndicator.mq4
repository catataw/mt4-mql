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
   return(onInit(T_INDICATOR));
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

   // (1) Beginn- und Endzeit der aktuellen Session ermitteln
   datetime time = TimeCurrent();
   datetime sessionStart = GetServerSessionStartTime(time);
   while (sessionStart == -1) {
      last_error = stdlib_PeekLastError();
      if (last_error != ERR_MARKET_CLOSED)
         return(last_error);
      time -= 1*DAY;
      sessionStart = GetServerSessionStartTime(time);
   }
   datetime sessionEnd = sessionStart + 1*DAY;
   //debug("onTick()   sessionStart = "+ TimeToStr(sessionStart, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"   sessionEnd = "+ TimeToStr(sessionEnd, TIME_DATE|TIME_MINUTES|TIME_SECONDS));

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


/*
double ohlc[4];
int bar   = 4000;
int error = iOHLC(NULL, PERIOD_H1, bar, ohlc);
debug("onTick()   ohlc = "+ RatesToStr(ohlc, NULL) + ifString(error==NO_ERROR, "", "   error = "+ ErrorToStr(error)));
*/
