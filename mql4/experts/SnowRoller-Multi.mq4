/**
 * SnowRoller-Strategy (Multi-Sequence-SnowRoller)
 */
#property stacksize 32768

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
//#include <history.mqh>
//#include <win32api.mqh>

#include <core/expert.mqh>
//#include <SnowRoller/define.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern /*sticky*/ string StartConditions = "@trend(ALMA:3.5xD1)";    // @trend(ALMA:3.5xD1)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

string   last.StartConditions = "";                                  // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE mit
                                                                     // den angegebenen Default-Werten überschrieben. Um das zu verhindern und die Werte mit den vorherigen
                                                                     // Werten vergleichen zu können, werden sie in deinit() in last.* zwischengespeichert und in init()
                                                                     // daraus restauriert.
bool     start.trend.condition;
string   start.trend.condition.txt;
int      start.trend.eventTimeframeFlag;                             // maximal PERIOD_H1
double   start.trend.periods;
int      start.trend.timeframe;
string   start.trend.method;
int      start.trend.lag;


#include <SnowRoller/init.strategy.mqh>
#include <SnowRoller/deinit.strategy.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int signal = CheckStartSignal();

   if (signal != 0) {
      if (signal > 0) {}            // Buy signal
      else            {}            // Sell signal
   }
   return(catch("onTick()")|last_error);
}


/**
 * Signalgeber für Start einer neuen Sequence
 *
 * @return int - +1 für ein Buy-Signal; -1 für ein Sell-Signal; 0 für kein Signal
 */
int CheckStartSignal() {
   if (__STATUS_CANCELLED || __STATUS_ERROR)
      return(0);

   // -- start.trend: bei Trendwechsel erfüllt -----------------------------------------------------------------------
   if (start.trend.condition) {
      int iNull[];
      if (EventListener.BarOpen(iNull, start.trend.eventTimeframeFlag)) {

         debug("CheckStartSignal()   event BarOpen");

      /*
         int    timeframe   = start.trend.timeframe;
         string maPeriods   = NumberToStr(start.trend.periods, ".+");
         string maTimeframe = PeriodDescription(start.trend.timeframe);
         string maMethod    = start.trend.method;
         int    bars        = start.trend.lag + 2 + 4;            // +2 (Bar 0 + Vorgänger) + einige Bars mehr, um vorherrschenden Trend sicher zu bestimmen
         int    lag         = start.trend.lag;

         if (IsTrendChange(timeframe, maPeriods, maTimeframe, maMethod, bars, direction, lag)) {
            if (__LOG) log(StringConcatenate("CheckStartSignal()   start condition \"", start.trend.condition.txt, "\" met"));
            return(true);
         }
      */
      }
   }
   return(0);
}


/**
 * Speichert die aktuelle Konfiguration zwischen, um sie bei Fehleingaben nach Parameteränderungen restaurieren zu können.
 *
 * @return void
 */
void StoreConfiguration(bool save=true) {
   static string _StartConditions;

   static bool   _start.trend.condition;
   static string _start.trend.condition.txt;
   static int    _start.trend.eventTimeframeFlag;
   static double _start.trend.periods;
   static int    _start.trend.timeframe;
   static string _start.trend.method;
   static int    _start.trend.lag;

   if (save) {
      _StartConditions                = StringConcatenate(StartConditions, "");  // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)

      _start.trend.condition          = start.trend.condition;
      _start.trend.condition.txt      = start.trend.condition.txt;
      _start.trend.eventTimeframeFlag = start.trend.eventTimeframeFlag;
      _start.trend.periods            = start.trend.periods;
      _start.trend.timeframe          = start.trend.timeframe;
      _start.trend.method             = start.trend.method;
      _start.trend.lag                = start.trend.lag;
   }
   else {
      StartConditions                 = _StartConditions;

      start.trend.condition           = _start.trend.condition;
      start.trend.condition.txt       = _start.trend.condition.txt;
      start.trend.eventTimeframeFlag  = _start.trend.eventTimeframeFlag;
      start.trend.periods             = _start.trend.periods;
      start.trend.timeframe           = _start.trend.timeframe;
      start.trend.method              = _start.trend.method;
      start.trend.lag                 = _start.trend.lag;
   }
}


/**
 * Restauriert eine zuvor gespeicherte Konfiguration.
 *
 * @return void
 */
void RestoreConfiguration() {
   StoreConfiguration(false);
}
