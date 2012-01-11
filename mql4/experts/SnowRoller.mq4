/**
 * SnowRoller Anti-Martingale EA
 *
 * @see 7bit strategy:  http://www.forexfactory.com/showthread.php?t=226059
 *      7bit journal:   http://www.forexfactory.com/showthread.php?t=239717
 *      7bit code base: http://sites.google.com/site/prof7bit/snowball
 */
#include <stdlib.mqh>


#define STATUS_WAITING        0           // mˆgliche Sequenzstatus-Werte
#define STATUS_PROGRESSING    1
#define STATUS_FINISHED       2
#define STATUS_DISABLED       3


int Strategy.Id = 103;                    // eindeutige ID der Strategie (Bereich 101-1023)


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern string Entry.Condition  = "BollingerBands(35xM15, EMA, 2.0)";    // {LimitValue} | [Bollinger]Bands(35xM5,EMA,2.0) | Env[elopes](75xM15,ALMA,2.0)
extern int    Gridsize         = 20;
extern double Lotsize          =  0.1;
extern int    TakeProfitLevels =  5;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   intern.Entry.Condition;                                     // Input-Parameter sind nicht statisch. Werden sie aus einer Preset-Datei geladen,
int      intern.Gridsize;                                            // werden sie bei REASON_CHARTCHANGE mit den obigen Default-Werten ¸berschrieben.
double   intern.Lotsize;                                             // Um dies zu verhindern, werden sie in deinit() in intern.* zwischengespeichert
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
   Zuerst wird die aktuelle Sequenz-ID bestimmt. Danach wird deren Konfiguration geladen. Zum Schluﬂ werden die Sequenzdaten restauriert.
   Es gibt 4 unterschiedliche init()-Szenarien:

   (1.1) Neustart des EA, evt. im Tester (keine internen Daten, externe Sequenz-ID evt. vorhanden)
   (1.2) Recompilation                   (keine internen Daten, externe Sequenz-ID immer vorhanden)
   (1.3) Parameter‰nderung               (alle internen Daten vorhanden, externe Sequenz-ID unnˆtig)
   (1.4) Timeframe-Wechsel               (alle internen Daten vorhanden, externe Sequenz-ID unnˆtig)
   */

   // (1) Sind keine internen Daten vorhanden, befinden wir uns in Szenario 1.1 oder 1.2.
   if (sequenceId == 0) {

      // (1.1) Neustart ---------------------------------------------------------------------------------------------------------------------------------------
      if (UninitializeReason() != REASON_RECOMPILE) {
      }

      // (1.2) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      else if (RestoreSequenceId()) {                                // externe Referenz immer vorhanden: restaurieren und validieren
      }
      else catch("init(1)   REASON_RECOMPILE, no stored sequence id found in chart", ERR_RUNTIME_ERROR);
   }

   // (1.3) Parameter‰nderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // alle internen Daten sind vorhanden
   }

   // (1.4) Timeframewechsel ----------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_CHARTCHANGE) {
      Entry.Condition  = intern.Entry.Condition;                     // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      Gridsize         = intern.Gridsize;                            // Inputvariablen restauriert.
      Lotsize          = intern.Lotsize;
      TakeProfitLevels = intern.TakeProfitLevels;
   }

   // ---------------------------------------------------------------------------------------------------------------------------------------------------------
   else catch("init(1)   unknown init() scenario", ERR_RUNTIME_ERROR);


   // (2) Status anzeigen
   ShowStatus();
   if (IsLastError())
      return(last_error);


   // (3) ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(UninitializeReason(), reasons1)) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten


   // (4) nicht auf den n‰chsten Tick warten (auﬂer bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
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
   // vor Recompile aktuelle Sequenze-ID im Chart speichern
   if (UninitializeReason() == REASON_RECOMPILE) {
      StoreSequenceId();
   }
   else {
      // Input-Parameter sind nicht statisch: f¸r's n‰chste init() in intern.* zwischenspeichern
      intern.Entry.Condition  = Entry.Condition;
      intern.Gridsize         = Gridsize;
      intern.Lotsize          = Lotsize;
      intern.TakeProfitLevels = TakeProfitLevels;
   }
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
   if (IsLastError())
      sequenceStatus = STATUS_DISABLED;

   string msg = "";

   switch (sequenceStatus) {
      case STATUS_WAITING:     msg = StringConcatenate(":  sequence ", sequenceId, " waiting"/* for ", Entry.Condition*/);                      break;
      case STATUS_PROGRESSING: msg = StringConcatenate(":  sequence ", sequenceId, " progressing at level ", IntToSignedStr(progressionLevel)); break;
      case STATUS_FINISHED:    msg = StringConcatenate(":  sequence ", sequenceId, " finished");                                                break;
      case STATUS_DISABLED:    msg = StringConcatenate(":  sequence ", sequenceId, " disabled");
                               if (IsLastError())
                                  msg = StringConcatenate(msg, "  [", ErrorDescription(last_error), "]");                                       break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ sequenceStatus, ERR_RUNTIME_ERROR));
   }

   msg = StringConcatenate(__SCRIPT__, msg,                                                     NL,
                                                                                                NL,
                           "GridSize:       ", Gridsize, " pip",                                NL,
                           "LotSize:         ", NumberToStr(Lotsize, ".+"), " = 12.00 / stop",  NL,
                           "Realized:       12 stops = -144.00  (-12/+4)",                      NL,
                         //"TakeProfit:    ", TakeProfitLevels, " levels  (1.6016'5 = 875.00)", NL,
                           "Breakeven:   1.5956'5 / 1.6047'5",                                  NL,
                           "Profit/Loss:    147.95",                                            NL);

   // einige Zeilen Abstand nach oben f¸r Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));

   if (catch("ShowStatus(2)") == NO_ERROR)
      last_error = error;                                            // bei Funktionseintritt bereits existierenden Fehler restaurieren
   return(last_error);
}


/**
 * Gibt die vorzeichenbehaftete String-Repr‰sentation eines Integers zur¸ck.
 *
 * @param  int value
 *
 * @return string
 */
string IntToSignedStr(int value) {
   string strValue = value;
   if (value > 0)
      return(StringConcatenate("+", strValue));
   return(strValue);
}


/**
 * Speichert die ID der aktuellen Sequenz im Chart, sodaﬂ sie nach einem Recompile-Event restauriert werden kann.
 *
 * @return int - Fehlerstatus
 */
int StoreSequenceId() {
   int    hWnd  = WindowHandle(Symbol(), Period());
   string label = __SCRIPT__ +".stored_sequence_id";

   if (ObjectFind(label) != -1)
      ObjectDelete(label);
   ObjectCreate(label, OBJ_LABEL, 0, 0, 0);
   ObjectSet(label, OBJPROP_XDISTANCE, -sequenceId);                 // negative Werte (im nicht sichtbaren Bereich)
   ObjectSet(label, OBJPROP_YDISTANCE, -hWnd);

   //debug("StoreSequenceId()     sequenceId="+ sequenceId +"   hWnd="+ hWnd);
   return(catch("StoreSequenceId()"));
}


/**
 * Restauriert eine im Chart ggf. gespeicherte Sequenz-ID.
 *
 * @return bool - ob eine Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreSequenceId() {
   string label = __SCRIPT__ +".stored_sequence_id";

   if (ObjectFind(label)!=-1) /*&&*/ if (ObjectType(label)==OBJ_LABEL) {
      int storedHWnd       = MathAbs(ObjectGet(label, OBJPROP_YDISTANCE)) +0.1;
      int storedSequenceId = MathAbs(ObjectGet(label, OBJPROP_XDISTANCE)) +0.1;  // (int) double

      if (WindowHandle(Symbol(), NULL) == storedHWnd) {
         sequenceId = storedSequenceId;
         //debug("RestoreSequenceId()   restored sequenceId="+ storedSequenceId +" for hWnd="+ storedHWnd);
         return(!IsError(catch("RestoreSequenceId(1)")));
      }
   }

   catch("RestoreSequenceId(2)");
   return(false);
}
