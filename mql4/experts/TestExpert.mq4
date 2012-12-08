/**
 * TestExpert
 */
#include <core/define.mqh>
#define __TYPE__        T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern string Parameter = "dummy";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   HandleEvent(EVENT_BAR_OPEN, F_PERIOD_M1);
   return(last_error);
}


/**
 * Handler f¸r BarOpen-Events.
 *
 * @param int timeframes[] - IDs der Timeframes, in denen das BarOpen-Event aufgetreten ist
 *
 * @return int - Fehlerstatus
 */
int onBarOpen(int timeframes[]) {
   Signal();
   return(last_error);
}


/**
 *
 * @return int - Fehlerstatus
 */
int Signal() {
   //return(NO_ERROR);

   // (1) Trend des MA der letzten Bars berechnen
   static int signal, trend, bars=4, icError, /*ICUSTOM*/ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   string strTrend;

   for (int bar=bars-1; bar>0; bar--) {                              // Bar 0 wird nicht benˆtigt
      trend = Round(iCustom(NULL, Period(), "Moving Average",
                            35,                                      // MA.Periods
                            "",                                      // MA.Timeframe
                            "SMA",                                   // MA.Method
                            "",                                      // MA.Method.Help
                            "Close",                                 // AppliedPrice
                            "",                                      // AppliedPrice.Help
                            bars + 1,                                // Max.Values
                            ForestGreen,                             // Color.UpTrend
                            Red,                                     // Color.DownTrend
                            "",                                      // _________________
                            ic[IC_PTR],                              // __iCustom__
                            BUFFER_1, bar)) /*throws ERR_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE*/;
      if (IsError(ic[IC_LAST_ERROR])) {
         icError = ic[IC_LAST_ERROR];
         break;
      }
      strTrend = StringConcatenate(strTrend, ifString(trend>0, "+", "-"));
   }


   // (2) Fehlerbehandlung des iCustom()-Calls (Wechselwirkung zwischen ERR_HISTORY_UPDATE/ERR_HISTORY_INSUFFICIENT)
   int error = GetLastError();
   if (IsError(error)) {
      if (error != ERR_HISTORY_UPDATE)         return(catch("Signal(1)", error));
   }
   if (IsError(icError)) {
      if (icError != ERR_HISTORY_INSUFFICIENT) return(SetLastError(icError));                   // wurde bereits im Indikator gemeldet
      if (IsNoError(error))                    return(catch("Signal(2)->iCustom()", icError));
   }
   //debug("Signal()   strTrend="+ strTrend + ifString(error==ERR_HISTORY_UPDATE, "   ERR_HISTORY_UPDATE", ""));


   // (3) Trendwechsel detektieren (2 aufeinanderfolgende dem aktuellen Trend entgegengesetzte Bars)
   if (StringEndsWith(strTrend, "-++")) {
      if (signal != 1) {
         signal = 1;
         debug("Signal()   trend up");
      }
   }
   else if (StringEndsWith(strTrend, "+--")) {
      if (signal != -1) {
         signal = -1;
         debug("Signal()   trend down");
      }
   }

   return(catch("Signal(3)"));
}


// ------------------------------------------------------------------------------------------------------------------------------------------------


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   return(NO_ERROR);
}


// ------------------------------------------------------------------------------------------------------------------------------------------------


/**
 * Parameter‰nderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   return(NO_ERROR);
}


/**
 * EA von Hand entfernt (Chart->Expert->Remove) oder neuer EA dr¸bergeladen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   return(NO_ERROR);
}


/**
 * Symbol- oder Timeframewechsel
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   return(NO_ERROR);
}


/**
 * - Chart geschlossen                       -oder-
 * - Template wird neu geladen               -oder-
 * - Terminal-Shutdown                       -oder-
 * - im Tester nach Bet‰tigen des "Stop"-Buttons oder nach Chart ->Close
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Der "Stop"-Button kann vom EA selbst "bet‰tigt" worden sein (nach Fehler oder vorzeitigem Testabschluﬂ).
 */
int onDeinitChartClose() {
   return(NO_ERROR);
}


/**
 * Kein UninitializeReason gesetzt: im Tester nach regul‰rem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   return(NO_ERROR);
}


/**
 * Recompilation
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   return(NO_ERROR);
}
