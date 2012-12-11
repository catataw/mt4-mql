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


int timeframe = PERIOD_M5;
int shift     = 2;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   //HandleEvent(EVENT_BAR_OPEN, PeriodFlag(timeframe));
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

   // (1) (1) Trend der letzten Bars berechnen
   int error, /*ICUSTOM*/ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   int    bars         = shift + 2 + 4;                              // +2 (Bar 0 u. Vorg‰nger) + einige Bars mehr, um aktuellen Trend sicher zu bestimmen
 //int    timeframe    = ...
   string MA.Periods   = "60";
   string MA.Timeframe = PeriodDescription(timeframe);
   string MA.Method    = "LWMA";
   string strTrend;

   for (int bar=bars-1; bar>0; bar--) {                              // Bar 0 ist immer unvollst‰ndig und wird nicht ber¸cksichtigt
      double trend = iCustom(NULL, timeframe, "Moving Average",
                             MA.Periods,                             // MA.Periods
                             MA.Timeframe,                           // MA.Timeframe
                             MA.Method,                              // MA.Method
                             "",                                     // MA.Method.Help
                             "Close",                                // AppliedPrice
                             "",                                     // AppliedPrice.Help
                             bars + 1,                               // Max.Values: +1 wegen ung¸ltiger Trendberechnung der ersten Bar (hat keinen Vorg‰nger)
                             ForestGreen,                            // Color.UpTrend
                             Red,                                    // Color.DownTrend
                             "",                                     // _________________
                             ic[IC_PTR],                             // __iCustom__
                             BUFFER_2, bar); //throws ERR_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE

      debug("Signal()   bar="+ bar +"   trend="+ NumberToStr(trend, ".+"));

      error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_HISTORY_UPDATE)
         return(catch("Signal(1)", error));
      if (IsError(ic[IC_LAST_ERROR]))
         return(SetLastError(ic[IC_LAST_ERROR]));

      strTrend = StringConcatenate(strTrend, ifString(trend>0, "+", "-"));
   }
   if (error == ERR_HISTORY_UPDATE)
      debug("Signal()   ERR_HISTORY_UPDATE");                        // TODO: bei ERR_HISTORY_UPDATE die zur Berechnung verwendeten Bars pr¸fen


   static int signal;


   // (2) Trendwechsel detektieren (2 dem alten Trend entgegengesetzte Bars)
   if (StringEndsWith(strTrend, "-++")) {
      if (signal != 1) {
         signal = 1;
         debug("Signal()   trend change up");
      }
   }
   else if (StringEndsWith(strTrend, "+--")) {
      if (signal != -1) {
         signal = -1;
         debug("Signal()   trend change down");
      }
   }

   return(catch("Signal(2)"));
}


// ------------------------------------------------------------------------------------------------------------------------------------------------


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {

   if (IsTesting()) {
      ForceSound("notify.wav");
      int button = ForceMessageBox(__NAME__ +" - StartSequence()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to do something now?", MB_ICONQUESTION|MB_OKCANCEL);
      if (button != IDOK) {
         __STATUS__CANCELLED = true;
         return(_false(catch("onInit()")));
      }
   }

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
