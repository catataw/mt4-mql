/**
 * SnowRoller Anti-Martingale EA
 *
 * @see 7bit strategy:  http://www.forexfactory.com/showthread.php?t=226059
 *      7bit journal:   http://www.forexfactory.com/showthread.php?t=239717
 *      7bit code base: http://sites.google.com/site/prof7bit/snowball
 */
#include <stdlib.mqh>


#define STATUS_WAITING        0           // mögliche Sequenzstatus-Werte
#define STATUS_PROGRESSING    1
#define STATUS_FINISHED       2
#define STATUS_DISABLED       3


int Strategy.Id = 103;                    // eindeutige ID der Strategie (Bereich 101-1023)


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern string Entry.Condition  = "BollingerBands(35xM15, EMA, 2.0)";    // {LimitValue} | [Bollinger]Bands(35xM5,EMA,2.0) | Env[elopes](75xM15,ALMA,2.0)
extern double Lotsize          =  0.1;
extern int    Gridsize         = 20;
extern int    TakeProfitLevels =  5;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   intern.Entry.Condition;                                     // Input-Parameter sind nicht statisch. Werden sie aus einer Preset-Datei geladen,
double   intern.Lotsize;                                             // werden sie bei REASON_CHARTCHANGE mit den obigen Default-Werten überschrieben.
int      intern.Gridsize;                                            // Um dies zu verhindern, werden sie in deinit() in intern.* zwischengespeichert
int      intern.TakeProfitLevels;                                    // und in init() wieder daraus restauriert.

int      sequenceId;
int      sequenceStatus = STATUS_WAITING;
int      progressionLevel;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (onInit(T_EXPERT) != NO_ERROR)
      return(ShowStatus());

   /*
   Zuerst wird die aktuelle Sequenz-ID bestimmt. Danach wird deren Konfiguration geladen. Zum Schluß werden die Sequenzdaten restauriert.
   Es gibt 4 unterschiedliche init()-Szenarien:

   (1.1) Neustart des EA, evt. im Tester (keine internen Daten, externe Sequenz-ID evt. vorhanden)
   (1.2) Recompilation                   (keine internen Daten, externe Sequenz-ID immer vorhanden)
   (1.3) Parameteränderung               (alle internen Daten vorhanden, externe Sequenz-ID unnötig)
   (1.4) Timeframe-Wechsel               (alle internen Daten vorhanden, externe Sequenz-ID unnötig)
   */

   // (1) Sind keine internen Daten vorhanden, befinden wir uns in Szenario 1.1 oder 1.2.
   if (sequenceId == 0) {

      // (1.1) Neustart ---------------------------------------------------------------------------------------------------------------------------------------
      if (UninitializeReason() != REASON_RECOMPILE) {
      }

      // (1.2) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      else {                                                         // Externe Referenz immer vorhanden: restaurieren und validieren.
      }
   }

   // (1.3) Parameteränderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // Alle internen Daten sind vorhanden.
   }

   // (1.4) Timeframewechsel ----------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_CHARTCHANGE) {
      Entry.Condition  = intern.Entry.Condition;                     // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      Lotsize          = intern.Lotsize;                             // Inputvariablen restauriert.
      Gridsize         = intern.Gridsize;
      TakeProfitLevels = intern.TakeProfitLevels;
   }

   // ---------------------------------------------------------------------------------------------------------------------------------------------------------
   else catch("init(1)   unknown init() scenario", ERR_RUNTIME_ERROR);


   // (2) Status anzeigen
   ShowStatus();
   if (last_error != NO_ERROR)
      return(last_error);


   // (3) ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(UninitializeReason(), reasons1)) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten


   // (4) nicht auf den nächsten Tick warten (außer bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
   int reasons2[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT, REASON_PARAMETERS, REASON_RECOMPILE };
   if (IntInArray(UninitializeReason(), reasons2)) /*&&*/ if (!IsTesting())
      SendTick(false);

   return(catch("init(2)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   // Input-Parameter sind nicht statisch: für's nächste init() in intern.* speichern
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


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @return int - Fehlerstatus
 */
int ShowStatus() {
   int error = last_error;                                           // bei Funktionseintritt bereits existierenden Fehler zwischenspeichern
   if (last_error != NO_ERROR)
      sequenceStatus = STATUS_DISABLED;

   string msg = "";
   switch (sequenceStatus) {
      case STATUS_WAITING:     msg = StringConcatenate(":  sequence ", sequenceId, " waiting for ", Entry.Condition); break;
      case STATUS_PROGRESSING: msg = StringConcatenate(":  sequence ", sequenceId, " progressing...");                break;
      case STATUS_FINISHED:    msg = StringConcatenate(":  sequence ", sequenceId, " finished");                      break;
      case STATUS_DISABLED:    msg = StringConcatenate(":  sequence ", sequenceId, " disabled");
                               if (last_error != NO_ERROR)
                                  msg = StringConcatenate(msg, "  [", ErrorDescription(last_error), "]");             break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ sequenceStatus, ERR_RUNTIME_ERROR));
   }
   msg = StringConcatenate(__SCRIPT__, msg);

   // einige Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, NL, NL, NL, NL, msg));

   if (catch("ShowStatus(2)") == NO_ERROR)
      last_error = error;                                            // bei Funktionseintritt bereits existierenden Fehler restaurieren
   return(last_error);
}
