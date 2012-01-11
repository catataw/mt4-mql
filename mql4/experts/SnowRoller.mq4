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

extern int    Gridsize                       = 20;
extern double Lotsize                        =  0.1;
extern string StartCondition                 = "BollingerBands(35xM15, EMA, 2.0)";    // {LimitValue} | [Bollinger]Bands(35xM5,EMA,2.0) | Env[elopes](75xM15,ALMA,2.0)
extern int    TakeProfitLevels               =  5;
extern string ______________________________ = "==== Sequence to Manage =============";
extern string Sequence.ID                    = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int    intern.Gridsize;                                              // Input-Parameter sind nicht statisch. Werden sie aus einer Preset-Datei geladen,
double intern.Lotsize;                                               // werden sie bei REASON_CHARTCHANGE mit den obigen Default-Werten überschrieben.
string intern.StartCondition;                                        // Um dies zu verhindern, werden sie in deinit() in intern.* zwischengespeichert
int    intern.TakeProfitLevels;                                      // und in init() wieder daraus restauriert.
string intern.Sequence.ID;

int    sequenceId;
int    sequenceStatus = STATUS_WAITING;
int    progressionLevel;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
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
         if (IsInputSequenceId()) {                                  // Zuerst eine ausdrücklich angegebene Sequenz-ID restaurieren...
            if (RestoreInputSequenceId()) {
            }
         }
         else if (RestoreChartSequenceId()) {                        // ...dann ggf. eine im Chart gespeicherte Sequenz-ID restaurieren...
         }
         else if (RestoreRunningSequenceId()) {                      // ...dann ID aus laufender Sequenz restaurieren.
         }
      }

      // (1.2) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      else if (RestoreChartSequenceId()) {                           // externe Referenz immer vorhanden: restaurieren und validieren
      }
      else catch("init(1)   REASON_RECOMPILE, no stored sequence id found in chart", ERR_RUNTIME_ERROR);
   }

   // (1.3) Parameteränderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // alle internen Daten sind vorhanden
   }

   // (1.4) Timeframewechsel ----------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_CHARTCHANGE) {
      Gridsize         = intern.Gridsize;                            // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      Lotsize          = intern.Lotsize;                             // Inputvariablen restauriert.
      StartCondition   = intern.StartCondition;
      TakeProfitLevels = intern.TakeProfitLevels;
      Sequence.ID      = intern.Sequence.ID;
   }

   // ---------------------------------------------------------------------------------------------------------------------------------------------------------
   else catch("init(2)   unknown init() scenario", ERR_RUNTIME_ERROR);


   // (2) Status anzeigen
   ShowStatus();
   if (IsLastError())
      return(last_error);


   // (3) ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(UninitializeReason(), reasons1)) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten


   // (4) nicht auf den nächsten Tick warten (außer bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
   int reasons2[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT, REASON_PARAMETERS, REASON_RECOMPILE };
   if (IntInArray(UninitializeReason(), reasons2)) /*&&*/ if (!IsTesting())
      SendTick(false);

   return(catch("init(3)"));
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
      // Input-Parameter sind nicht statisch: für's nächste init() in intern.* zwischenspeichern
      intern.Gridsize         = Gridsize;
      intern.Lotsize          = Lotsize;
      intern.StartCondition   = StartCondition;
      intern.TakeProfitLevels = TakeProfitLevels;
      intern.Sequence.ID      = Sequence.ID;
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
      case STATUS_WAITING:     msg = StringConcatenate(":  sequence ", sequenceId, " waiting"/* for ", StartCondition*/);                       break;
      case STATUS_PROGRESSING: msg = StringConcatenate(":  sequence ", sequenceId, " progressing at level ", IntToSignedStr(progressionLevel)); break;
      case STATUS_FINISHED:    msg = StringConcatenate(":  sequence ", sequenceId, " finished");                                                break;
      case STATUS_DISABLED:    msg = StringConcatenate(":  sequence ", sequenceId, " disabled");
                               if (IsLastError())
                                  msg = StringConcatenate(msg, "  [", ErrorDescription(last_error), "]");                                       break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ sequenceStatus, ERR_RUNTIME_ERROR));
   }

   msg = StringConcatenate(__SCRIPT__, msg,                                                                      NL,
                                                                                                                 NL,
                           "GridSize:       ", Gridsize, " pip",                                                 NL,
                           "LotSize:         ", NumberToStr(Lotsize, ".+"), " = 12.00 / stop",                   NL,
                           "Realized:       12 stops = -144.00  (-12/+4)",                                       NL,
                         //"TakeProfit:    ", TakeProfitLevels, " levels  (1.6016'5 = 875.00)",                  NL,
                           "Breakeven:   ", NumberToStr(Bid, PriceFormat), " / ", NumberToStr(Ask, PriceFormat), NL,
                           "Profit/Loss:    147.95",                                                             NL);

   // einige Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));

   if (!IsError(catch("ShowStatus(2)")))
      last_error = error;                                            // bei Funktionseintritt bereits existierenden Fehler restaurieren
   return(last_error);
}


/**
 * Gibt die vorzeichenbehaftete String-Repräsentation eines Integers zurück.
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
 * Ob in den Input-Parametern ausdrücklich eine zu benutzende Sequenz-ID angegeben wurde. Hier wird nur geprüft,
 * ob ein Wert angegeben wurde. Die Gültigkeit einer ID wird erst in RestoreInputSequenceId() überprüft.
 *
 * @return bool
 */
bool IsInputSequenceId() {
   return(StringLen(StringTrim(Sequence.ID)) > 0);
}


/**
 * Validiert und setzt die in der Konfiguration angegebene Sequenz-ID.
 *
 * @return bool - ob eine gültige Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreInputSequenceId() {
   if (IsInputSequenceId()) {
      string strValue = StringTrim(Sequence.ID);

      if (StringIsInteger(strValue)) {
         int iValue = StrToInteger(strValue);
         if (1000 <= iValue) /*&&*/ if (iValue <= 16383) {
            sequenceId  = iValue;
            Sequence.ID = strValue;
            return(true);
         }
      }
      catch("RestoreInputSequenceId()  Invalid input parameter Sequence.ID = \""+ Sequence.ID +"\"", ERR_INVALID_INPUT_PARAMVALUE);
   }
   return(false);
}


/**
 * Speichert die ID der aktuellen Sequenz im Chart, sodaß sie nach einem Recompile-Event restauriert werden kann.
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
bool RestoreChartSequenceId() {
   string label = __SCRIPT__ +".stored_sequence_id";

   if (ObjectFind(label)!=-1) /*&&*/ if (ObjectType(label)==OBJ_LABEL) {
      int storedHWnd       = MathAbs(ObjectGet(label, OBJPROP_YDISTANCE)) +0.1;
      int storedSequenceId = MathAbs(ObjectGet(label, OBJPROP_XDISTANCE)) +0.1;  // (int) double

      if (WindowHandle(Symbol(), NULL) == storedHWnd) {
         sequenceId = storedSequenceId;
         //debug("RestoreChartSequenceId()   restored sequenceId="+ storedSequenceId +" for hWnd="+ storedHWnd);
         catch("RestoreChartSequenceId(1)");
         return(true);
      }
   }

   catch("RestoreChartSequenceId(2)");
   return(false);
}


/**
 * Restauriert die Sequenz-ID einer laufenden Sequenz.
 *
 * @return bool - ob eine laufende Sequenz gefunden und die ID restauriert wurde
 */
bool RestoreRunningSequenceId() {
   // offene Positionen einlesen
   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: während des Auslesens wird in einem anderen Thread eine offene Order entfernt
         continue;

      if (IsMyOrder()) {
         sequenceId = OrderMagicNumber() >> 8 & 0x3FFF;              // 14 Bits (Bits 9-22) => sequenceId
         catch("RestoreRunningSequenceId(1)");
         return(true);
      }
   }

   catch("RestoreRunningSequenceId(2)");
   return(false);
}


/**
 * Ob die aktuell selektierte Order zu dieser Strategie gehört. Wird eine Sequenz-ID angegeben, wird zusätzlich überprüft,
 * ob die Order zur angegebenen Sequenz gehört.
 *
 * @param  int sequenceId - ID einer Sequenz (default: NULL)
 *
 * @return bool
 */
bool IsMyOrder(int sequenceId = NULL) {
   if (OrderSymbol() == Symbol()) {
      if (OrderMagicNumber() >> 22 == Strategy.Id) {
         if (sequenceId == NULL)
            return(true);
         return(sequenceId == OrderMagicNumber() >> 8 & 0x3FFF);     // 14 Bits (Bits 9-22) => sequenceId
      }
   }
   return(false);
}
