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
   onInit(T_INDICATOR, WindowExpertName());
   //debug("init()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());
   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   //debug("deinit()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int    bar = 0;
   double ohlc[4];
   int error = iOHLC(NULL, PERIOD_D1, bar, ohlc);

   debug("onTick()   ohlc = "+ PriceArrayToStr(ohlc, PriceFormat, NULL) + ifString(error==NO_ERROR, "", "   error = "+ ErrorToStr(error)));

   return(catch("onTick()"));
}


/**
 * Ermittelt die OHLC-Werte eines Symbols für eine einzelne Bar einer Periode. Im Unterschied zu den eingebauten Funktionen iHigh(), iLow() etc.
 * ermittelt diese Funktion alle 4 Werte mit einem einzigen Funktionsaufruf.
 *
 * @param  string symbol     - Symbol  (default: aktuelles Symbol)
 * @param  int    period     - Periode (default: aktuelle Periode)
 * @param  int    bar        - Bar-Offset
 * @param  double results[4] - Ergebnisarray {Open, Low, High, Close}
 * @param  string timezone   - Zeitzone der Bars, falls period > PERIOD_H1 (default: Tradeserver-Zeitzone)
 *
 * @return int - Fehlerstatus; ERR_NO_RESULT, wenn die angegebene Bar nicht existiert (ggf. ERR_HISTORY_UPDATE)
 *
 */
int iOHLC(string symbol, int period, int bar, double& results[4], string timezone="0") {
   if (symbol == "0")                     // NULL ist Integer (0)
      symbol = Symbol();
   if (bar < 0)
      return(catch("iOHLC(1)  invalid parameter bar = "+ bar, ERR_INVALID_FUNCTION_PARAMVALUE));
   if (ArraySize(results) != 4)
      ArrayResize(results, 4);


   if (timezone == "0") {              // Tradeserver-Timezone, umrechnen nicht nötig
   }
   else {
      string zone = GetTradeServerTimezone();
      if (zone == "") return(stdlib_PeekLastError());

      if (zone == timezone) {          // Tradeserver-Timezone, umrechnen nicht nötig
      }
      else {
         // andere als die Tradeserver-Zeitzone angegeben
      }
   }










   // TODO: um ERR_HISTORY_UPDATE zu vermeiden, möglichst die aktuelle Periode benutzen

   results[MODE_OPEN ] = iOpen (symbol, period, bar);
   results[MODE_HIGH ] = iHigh (symbol, period, bar);
   results[MODE_LOW  ] = iLow  (symbol, period, bar);
   results[MODE_CLOSE] = iClose(symbol, period, bar);

   int error = GetLastError();

   if (error == NO_ERROR) {
      if (EQ(results[MODE_OPEN], 0))
         error = ERR_NO_RESULT;
   }
   else if (error != ERR_HISTORY_UPDATE) {
      catch("iOHLCBar(2)", error);
   }
   return(error);
}
