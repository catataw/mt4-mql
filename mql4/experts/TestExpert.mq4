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


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int    timeframe   = PERIOD_M5;
   string maPeriods   = "20";
   string maTimeframe = PeriodDescription(timeframe);
   string maMethod    = "SMA";
   int    bars        = 1 + 2 + 5;                                   // + 2 + einige Bars mehr
   int    lag         = 1;

   int iNull[];
   if (EventListener.BarOpen(iNull, PeriodFlag(timeframe))) {
      IsTrendChange(timeframe, maPeriods, maTimeframe, maMethod, bars,  true, lag);
      IsTrendChange(timeframe, maPeriods, maTimeframe, maMethod, bars, false, lag);
   }
   return(last_error);
}


/**
 * BarOpen-Eventhandler zur Erkennung von MA-Trendwechseln.
 *
 * @param  int    timeframe   - zu verwendender Timeframe
 * @param  string maPeriods   - Indikator-Parameter
 * @param  string maTimeframe - Indikator-Parameter
 * @param  string maMethod    - Indikator-Parameter
 * @param  int    bars        - Anzahl zu berechnender Indikatorwerte
 * @param  bool   detectUp    - TRUE,  wenn ein Wechsel zum Up-Trend signalisiert werden soll;
 *                              FALSE, wenn ein Wechsel zum Down-Trend signalisiert werden soll
 * @param  int    lag         - Trigger-Verzögerung (default: 1 Bar)
 *
 * @return bool - ob ein entsprechender Trendwechsel aufgetreten ist
 */
bool IsTrendChange(int timeframe, string maPeriods, string maTimeframe, string maMethod, int bars, bool detectUp, int lag=1) {
   bool detectDown = !detectUp;

   // (1) Trend der letzten Bars ermitteln
   int error, /*ICUSTOM*/ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   int    trend, barTrend, prevBarTrend;
   string strTrend, strChangePattern;

   for (int bar=bars-1; bar>0; bar--) {                              // Bar 0 ist immer unvollständig und wird nicht berücksichtigt
      // (1.1) Trend der einzelnen Bar bestimmen
      barTrend = Round(iCustom(NULL, timeframe, "Moving Average",
                               maPeriods,                            // MA.Periods
                               maTimeframe,                          // MA.Timeframe
                               maMethod,                             // MA.Method
                               "",                                   // MA.Method.Help
                               "Close",                              // AppliedPrice
                               "",                                   // AppliedPrice.Help
                               Max(bars+1, 10),                      // Max.Values: +1 wegen ungültigem Trend der ersten Bar, mind. 10 zur Reduktion identischer Instanzen
                               ForestGreen,                          // Color.UpTrend
                               Red,                                  // Color.DownTrend
                               "",                                   // _________________
                               ic[IC_PTR],                           // __iCustom__
                               BUFFER_2, bar)); //throws ERR_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE

      error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_HISTORY_UPDATE)
         return(_false(catch("IsTrendChange(1)", error)));
      if (IsError(ic[IC_LAST_ERROR]))
         return(_false(SetLastError(ic[IC_LAST_ERROR])));
      if (!barTrend)
         return(_false(catch("IsTrendChange(2)->iCustom(Moving Average)   invalid trend for bar="+ bar +": "+ barTrend, ERR_CUSTOM_INDICATOR_ERROR)));

      // (1.2) vorherrschenden Trend bestimmen (mindestens 2 aufeinanderfolgende Bars in derselben Richtung)
      if (barTrend > 0) {
         if (bar > 1 && prevBarTrend > 0)                            // nur Bars > 1 (1 triggert Trendwechsel, 0 ist irrelevant)
            trend = 1;
      }
      else /*(barTrend < 0)*/ {
         if (bar > 1 && prevBarTrend < 0)                            // ...
            trend = -1;
      }
      strTrend     = StringConcatenate(strTrend, ifString(barTrend>0, "+", "-"));
      prevBarTrend = barTrend;
   }
   if (error == ERR_HISTORY_UPDATE)
      debug("IsTrendChange()   ERR_HISTORY_UPDATE");                 // TODO: bei ERR_HISTORY_UPDATE die zur Berechnung verwendeten Bars prüfen


   // (2) Trendwechsel detektieren
   if (/*trend < 0 &&*/ detectUp) {
      strChangePattern = "-"+ StringRepeat("+", lag);                // up change "-++"
      if (StringEndsWith(strTrend, strChangePattern)) {              // Trendwechsel im Down-Trend
         debug("IsTrendChange()   trend change up   "+ TimeToStr(TimeCurrent()));
         return(true);
      }
   }
   if (/*trend > 0 &&*/ detectDown) {
      strChangePattern = "+"+ StringRepeat("-", lag);                // down change "+--"
      if (StringEndsWith(strTrend, strChangePattern)) {              // Trendwechsel im Up-Trend
         debug("IsTrendChange()   trend change down "+ TimeToStr(TimeCurrent()));
         return(true);
      }
   }
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
 * Parameteränderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   return(NO_ERROR);
}


/**
 * EA von Hand entfernt (Chart->Expert->Remove) oder neuer EA drübergeladen
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
 * - im Tester nach Betätigen des "Stop"-Buttons oder nach Chart ->Close
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Der "Stop"-Button kann vom EA selbst "betätigt" worden sein (nach Fehler oder vorzeitigem Testabschluß).
 */
int onDeinitChartClose() {
   return(NO_ERROR);
}


/**
 * Kein UninitializeReason gesetzt: im Tester nach regulärem Ende (Testperiode zu Ende)
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
