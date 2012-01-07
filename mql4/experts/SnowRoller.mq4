/**
 * SnowRoller Anti-Martingale EA
 *
 * @see 7bit strategy:  http://www.forexfactory.com/showthread.php?t=226059
 *      7bit journal:   http://www.forexfactory.com/showthread.php?t=239717
 *      7bit code base: http://sites.google.com/site/prof7bit/snowball
 */
#include <stdlib.mqh>


int Strategy.Id = 103;                                   // eindeutige ID der Strategie (Bereich 101-1023)


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern string Entry.Condition  = "BollingerBands(35xM15, EMA, 2.0)";    // {LimitValue} | [Bollinger]Bands(35xM5,EMA,2.0) | Env[elopes](75xM15,ALMA,2.0)
extern double Lotsize          =  0.1;
extern int    Gridsize         = 20;
extern int    TakeProfitLevels =  5;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   intern.Entry.Condition;                                     // Werden die Input-Parameter aus einer Preset-Datei geladen, werden sie bei REASON_CHARTCHANGE
double   intern.Lotsize;                                             // mit den obigen Default-Werten überschrieben. Um dies zu verhindern, werden sie in deinit()
int      intern.Gridsize;                                            // in intern.* zwischengespeichert und in init() wieder daraus restauriert.
int      intern.TakeProfitLevels;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (onInit(T_EXPERT) != NO_ERROR)
      return(last_error);

   if (UninitializeReason() == REASON_CHARTCHANGE) {
      Entry.Condition  = intern.Entry.Condition;                     // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      Lotsize          = intern.Lotsize;                             // Inputvariablen restauriert.
      Gridsize         = intern.Gridsize;
      TakeProfitLevels = intern.TakeProfitLevels;
   }
   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   // Input-Parameter sind nicht statisch: für's nächste init() intern.* speichern
   intern.Entry.Condition  = Entry.Condition;
   intern.Lotsize          = Lotsize;
   intern.Gridsize         = Gridsize;
   intern.TakeProfitLevels = TakeProfitLevels;
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   return(catch("onTick()"));
}
