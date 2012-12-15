/**
 * TestExpert
 */
#include <core/define.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern string Parameter = "dummy";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int timeframe = PERIOD_M1;
int shift     = 2;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int iNull[];
   if (EventListener.BarOpen(iNull, PeriodFlag(timeframe))) {
      Signal(8);
      Signal(9);
   }
   return(last_error);
}


/**
 * Eventhandler zur Erkennung von Trendwechseln. Wird nur onBarOpen aufgerufen.
 *
 * @return bool - ob ein Trendwechsel entsprechend der Startkonfiguration aufgetreten ist
 */
bool Signal(int bars) {
   debug("Signal()   bars="+ bars);

   int error, /*ICUSTOM*/ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   for (int bar=bars-1; bar>0; bar--) {                                 // Bar 0 ist immer unvollst‰ndig und wird nicht ber¸cksichtigt
      iCustom(NULL, PERIOD_H1, "Moving Average",
              "84",                                                     // MA.Periods
              "H1",                                                     // MA.Timeframe
              "SMA",                                                    // MA.Method
              "",                                                       // MA.Method.Help
              "Close",                                                  // AppliedPrice
              "",                                                       // AppliedPrice.Help
              bars+1,                                                   // Max.Values: +1 wegen ung¸ltigem Trend der ersten Bar (hat keinen Vorg‰nger)
              ForestGreen,                                              // Color.UpTrend
              Red,                                                      // Color.DownTrend
              "",                                                       // _________________
              ic[IC_PTR],                                               // __iCustom__
              BUFFER_2, bar); //throws ERR_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE

      error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_HISTORY_UPDATE)
         return(_false(catch("Signal()", error)));
      if (IsError(ic[IC_LAST_ERROR]))
         return(_false(SetLastError(ic[IC_LAST_ERROR])));
   }
   if (error == ERR_HISTORY_UPDATE)
      debug("Signal()   ERR_HISTORY_UPDATE");                           // TODO: bei ERR_HISTORY_UPDATE die zur Berechnung verwendeten Bars pr¸fen

   return(false);
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
