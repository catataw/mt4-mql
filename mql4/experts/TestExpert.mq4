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
   /*ICUSTOM*/int ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   int bar    = 0;
   int buffer = 0;

   double value = iCustom(NULL, PERIOD_H1, "Moving Average",   // throws ERR_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE
                          100,            // MA.Periods
                          "H1",           // MA.Timeframe
                          "SMA",          // MA.Method
                          "",             // MA.Method.Help
                          "Close",        // AppliedPrice
                          "",             // AppliedPrice.Help
                          2000,           // Max.Values
                          ForestGreen,    // Color.UpTrend
                          Red,            // Color.DownTrend
                          "",             // _________________
                          ic[IC_PTR],     // __iCustom__
                          buffer, bar);

   int error = GetLastError();
   if (IsError(error)) {
      if (error == ERR_HISTORY_UPDATE) debug("onTick()->iCustom()   ERR_HISTORY_UPDATE");
      else                             catch("onTick()", error);
   }
   if (!IsLastError())
      last_error = ic[IC_LAST_ERROR];
   return(last_error);
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
