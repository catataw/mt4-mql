/**
 * SnowRoller-Strategy (Multi-Sequence-SnowRoller)
 *
 *  TODO:
 *  -----
 *  - Sequenz-IDs auf Eindeutigkeit prüfen
 *  - im Tester fortlaufende Sequenz-IDs generieren
 */
#property stacksize 32768

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
//#include <history.mqh>
//#include <win32api.mqh>

#include <core/expert.mqh>
#include <SnowRoller/define.mqh>
#include <SnowRoller/functions.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern /*sticky*/ string StartConditions = "@trend(ALMA:3.5xD1)";    // @trend(ALMA:3.5xD1)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

string   last.StartConditions = "";                                  // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE
                                                                     // mit den Default-Werten überschrieben. Um dies zu verhindern und um neue mit vorherigen Werten
bool     start.trend.condition;                                      // vergleichen zu können, werden sie in deinit() in diesen Variablen zwischengespeichert und in
string   start.trend.condition.txt;                                  // init() wieder daraus restauriert.
double   start.trend.periods;                                        //
int      start.trend.timeframe, start.trend.timeframeFlag;           // maximal PERIOD_H1
string   start.trend.method;
int      start.trend.lag;

int      sequence.id         [];
bool     sequence.test       [];                                     // ob die Sequenz eine Testsequenz ist (entweder im Tester oder im Online-Chart)
int      sequence.status     [];
string   sequence.status.file[][2];                                  // [0] MQL-Verzeichnisname (unterhalb "...\files\"), [1] Dateiname der Statusdatei


#include <SnowRoller/init.strategy.mqh>
#include <SnowRoller/deinit.strategy.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int signal;

   if (IsStartSignal(signal)) {
      //debug("IsStartSignal()   "+ TimeToStr(TimeCurrent()) +"   signal "+ ifString(signal>0, "up", "down"));
      Strategy.CreateSequence(ifInt(signal>0, D_LONG, D_SHORT));
   }
   return(last_error);
}


/**
 * Erzeugt und startet eine neue Sequenz.
 *
 * @param  int direction - Sequenztyp: D_LONG | D_SHORT
 *
 * @return int - ID der erzeugten Sequenz (>= SID_MIN) oder Sequenz-Management-Code (< SID_MIN);
 *               0, falls ein Fehler auftrat
 */
int Strategy.CreateSequence(int direction) {
   if (__STATUS_ERROR)                                   return(0);
   if (direction!=D_LONG) /*&&*/ if (direction!=D_SHORT) return(_NULL(catch("Strategy.CreateSequence(1)   illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE)));

   // (1) Sequenz erzeugen
   int  sid    = CreateSequenceId();
   bool test   = IsTesting();
   int  status = STATUS_WAITING;                            // TODO: Sequence-Management einbauen

   int six = Strategy.AddSequence(sid, test, status);
   if (six == -1)
      return(0);
   if      (sid >= SID_MIN) debug("Strategy.CreateSequence()   "+ directionDescr[direction] +" sequence created: "+ sid);
   else if (sid != 0      ) debug("Strategy.CreateSequence()   "+ directionDescr[direction] +" sequence denied");


   // (2) Sequenz starten
   if (!StartSequence(six))
      return(0);

   return(sid);
}


/**
 * Startet eine neue Trade-Sequenz.
 *
 * @param  int six - Verwaltungsindex der Sequenz
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence(int six) {
   if (__STATUS_ERROR)                            return( false);
   if (six < 0 || six > ArraySize(sequence.id)-1) return(_false(catch("StartSequence(1)   invalid parameter six = "+ six, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (sequence.status[six] != STATUS_WAITING)    return(_false(catch("StartSequence(2)   cannot start "+ StatusDescription(sequence.status[six]) +" sequence "+ sequence.id[six], ERR_RUNTIME_ERROR)));

   if (Tick==1) /*&&*/ if (!ConfirmTick1Trade("StartSequence()", "Do you really want to start the new sequence "+ sequence.id[six] +" now?"))
      return(_false(SetLastError(ERR_CANCELLED_BY_USER), catch("StartSequence(3)")));

   // Logfile umschalten
   //SetCustomLog();
   //SetInstanceId(sequence.id[six]);

   if (__LOG) log("StartSequence()   starting sequence "+ sequence.id[six]);

   sequence.status[six] = STATUS_STARTING;


   // (1) Startvariablen setzen
   datetime startTime  = TimeCurrent();
   double   startPrice = ifDouble(grid.direction==D_SHORT, Bid, Ask);

   ArrayPushInt   (sequenceStart.event,  CreateEventId());
   ArrayPushInt   (sequenceStart.time,   startTime      );
   ArrayPushDouble(sequenceStart.price,  startPrice     );
   ArrayPushDouble(sequenceStart.profit, 0              );

   ArrayPushInt   (sequenceStop.event,  0);                          // Größe von sequenceStarts/Stops synchron halten
   ArrayPushInt   (sequenceStop.time,   0);
   ArrayPushDouble(sequenceStop.price,  0);
   ArrayPushDouble(sequenceStop.profit, 0);

   sequenceStartEquity = NormalizeDouble(AccountEquity()-AccountCredit(), 2);


   // (2) Gridbasis setzen (zeitlich nach sequenceStart.event)
   double gridBase = startPrice;
   if (start.conditions) /*&&*/ if (start.level.condition) {
      grid.level    = start.level.value;
      grid.maxLevel = grid.level;
      gridBase      = NormalizeDouble(startPrice - grid.level*GridSize*Pips, Digits);
   }
   Grid.BaseReset(startTime, gridBase);


   // (3) ggf. Startpositionen in den Markt legen und Sequenzstart aktualisieren
   if (grid.level != 0) {
      datetime iNull;
      if (!UpdateOpenPositions(iNull, startPrice))
         return(false);
      sequenceStart.price[ArraySize(sequenceStart.price)-1] = startPrice;
   }


   status = STATUS_PROGRESSING;


   // (4) StartConditions deaktivieren und Weekend-Stop aktualisieren
   start.conditions = false; SS.StartStopConditions();
   UpdateWeekendStop();


   // (5) Stop-Orders in den Markt legen
   if (!UpdatePendingOrders())
      return(false);

   RedrawStartStop();

   if (__LOG) log(StringConcatenate("StartSequence()   sequence started at ", NumberToStr(startPrice, PriceFormat), ifString(grid.level, " and level "+ grid.level, "")));
   return(!last_error|catch("StartSequence(4)"));
}


/**
 * Erzeugt und startet eine neue Sequenz.
 *
 * @param  int  sid    - Sequenz-ID
 * @param  bool test   - Teststatus der Sequenz
 * @param  int  status - Laufzeit-Status der Sequenz
 *
 * @return int - Verwaltungsindex der Sequenz oder -1, falls ein Fehler auftrat
 */
int Strategy.AddSequence(int sid, bool test, int status) {
   if (__STATUS_ERROR)                    return(-1);
   if (IntInArray(sequence.id, sid))      return(_int(-1, catch("Strategy.AddSequence(1)   sequence "+ sid +" already exists", ERR_RUNTIME_ERROR)));
   if (BoolInArray(sequence.test, !test)) return(_int(-1, catch("Strategy.AddSequence(2)   illegal mix of test/non-test sequences: tried to add "+ sid +" (test="+ test +"), found "+ sequence.id[SearchBoolArray(sequence.test, !test)] +" (test="+ (!test) +")", ERR_RUNTIME_ERROR)));
   if (!IsValidSequenceStatus(status))    return(_int(-1, catch("Strategy.AddSequence(3)   invalid parameter status = "+ status, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int size=ArraySize(sequence.id), six=size;
   Strategy.ResizeArrays(size+1);

   sequence.id    [six] = sid;
   sequence.test  [six] = test;
   sequence.status[six] = status;
   InitStatusLocation(six);
   return(six);
}


/**
 * Initialisiert die Dateinamensvariablen der Statusdatei mit den Ausgangswerten einer neuen Sequenz.
 *
 * @param  int six - Verwaltungsindex der Sequenz
 *
 * @return bool - Erfolgsstatus
 */
bool InitStatusLocation(int six) {
   if (__STATUS_ERROR)                            return( false);
   if (six < 0 || six > ArraySize(sequence.id)-1) return(_false(catch("InitStatusLocation(1)   invalid parameter six = "+ six, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if      (IsTesting())        sequence.status.file[six][0] = "presets\\";
   else if (sequence.test[six]) sequence.status.file[six][0] = "presets\\tester\\";
   else                         sequence.status.file[six][0] = "presets\\"+ ShortAccountCompany() +"\\";

   sequence.status.file[six][1] = StringConcatenate(StringToLower(StdSymbol()), ".SR.", sequence.id[six], ".set");

   return(!catch("InitStatusLocation(2)"));
}


/**
 * Setzt die Größe der Arrays für die Sequenzverwaltung auf den angegebenen Wert.
 *
 * @param  int size - neue Größe
 *
 * @return int - neue Größe der Arrays
 */
int Strategy.ResizeArrays(int size) {
   int oldSize = ArraySize(sequence.id);

   if (size != oldSize) {
      ArrayResize(sequence.id,          size);
      ArrayResize(sequence.test,        size);
      ArrayResize(sequence.status,      size);
      ArrayResize(sequence.status.file, size);
   }
   return(size);
}


/**
 * Signalgeber für Start einer neuen Sequence
 *
 * @param  int lpSignal - Zeiger auf Variable zur Signalaufnahme (+: Buy-Signal, -: Sell-Signal)
 *
 * @return bool - ob ein Signal aufgetreten ist
 */
bool IsStartSignal(int &lpSignal) {
   if (__STATUS_ERROR)
      return(false);

   lpSignal = 0;

   // -- start.trend: bei Trendwechsel erfüllt -----------------------------------------------------------------------
   if (start.trend.condition) {
      int iNull[];
      if (EventListener.BarOpen(iNull, start.trend.timeframeFlag)) {

         int    timeframe   = start.trend.timeframe;
         string maPeriods   = NumberToStr(start.trend.periods, ".+");
         string maTimeframe = PeriodDescription(start.trend.timeframe);
         string maMethod    = start.trend.method;
         int    lag         = start.trend.lag;
         int    directions  = MODE_UPTREND | MODE_DOWNTREND;

         if (CheckTrendChange(timeframe, maPeriods, maTimeframe, maMethod, lag, directions, lpSignal)) {
            if (!lpSignal)
               return(false);
            if (__LOG) log(StringConcatenate("IsStartSignal()   start signal \"", start.trend.condition.txt, "\" ", ifString(lpSignal>0, "up", "down")));
            return(true);
         }
      }
   }
   return(false);
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
   static double _start.trend.periods;
   static int    _start.trend.timeframe;
   static int    _start.trend.timeframeFlag;
   static string _start.trend.method;
   static int    _start.trend.lag;

   if (save) {
      _StartConditions           = StringConcatenate(StartConditions, "");  // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)

      _start.trend.condition     = start.trend.condition;
      _start.trend.condition.txt = start.trend.condition.txt;
      _start.trend.periods       = start.trend.periods;
      _start.trend.timeframe     = start.trend.timeframe;
      _start.trend.timeframeFlag = start.trend.timeframeFlag;
      _start.trend.method        = start.trend.method;
      _start.trend.lag           = start.trend.lag;
   }
   else {
      StartConditions            = _StartConditions;

      start.trend.condition      = _start.trend.condition;
      start.trend.condition.txt  = _start.trend.condition.txt;
      start.trend.periods        = _start.trend.periods;
      start.trend.timeframe      = _start.trend.timeframe;
      start.trend.timeframeFlag  = _start.trend.timeframeFlag;
      start.trend.method         = _start.trend.method;
      start.trend.lag            = _start.trend.lag;
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


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @param  bool interactive - ob fehlerhafte Parameter interaktiv korrigiert werden können
 *
 * @return bool - ob die Konfiguration gültig ist
 */
bool ValidateConfiguration(bool interactive) {
   if (__STATUS_ERROR)
      return(false);

   bool reasonParameters = (UninitializeReason() == REASON_PARAMETERS);
   if (reasonParameters)
      interactive = true;


   // (5) StartConditions, AND-verknüpft: "(@trend(xxMA:7xD1[+2]"
   // ----------------------------------------------------------------------------------------------------------------------
   if (!reasonParameters || StartConditions!=last.StartConditions) {
      start.trend.condition = false;

      // (5.1) StartConditions in einzelne Ausdrücke zerlegen
      string exprs[], expr, elems[], key, value;
      int    iValue, time, sizeOfElems, sizeOfExprs=Explode(StartConditions, "&&", exprs, NULL);
      double dValue;

      // (5.2) jeden Ausdruck parsen und validieren
      for (int i=0; i < sizeOfExprs; i++) {
         expr = StringToLower(StringTrim(exprs[i]));
         if (StringLen(expr) == 0) {
            if (sizeOfExprs > 1)                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(16)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            break;
         }
         if (StringGetChar(expr, 0) != '@')            return(_false(ValidateConfig.HandleError("ValidateConfiguration(17)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         if (Explode(expr, "(", elems, NULL) != 2)     return(_false(ValidateConfig.HandleError("ValidateConfiguration(18)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         if (!StringEndsWith(elems[1], ")"))           return(_false(ValidateConfig.HandleError("ValidateConfiguration(19)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         key   = StringTrim(elems[0]);
         value = StringTrim(StringLeft(elems[1], -1));
         if (StringLen(value) == 0)                    return(_false(ValidateConfig.HandleError("ValidateConfiguration(20)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));

         if (key == "@trend") {
            if (start.trend.condition)                 return(_false(ValidateConfig.HandleError("ValidateConfiguration(21)", "Invalid StartConditions = \""+ StartConditions +"\" (multiple trend conditions)", interactive)));
            if (Explode(value, ":", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(24)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            key   = StringToUpper(StringTrim(elems[0]));
            value = StringToUpper(elems[1]);
            // key="ALMA"
            if      (key == "SMA" ) start.trend.method = key;
            else if (key == "EMA" ) start.trend.method = key;
            else if (key == "SMMA") start.trend.method = key;
            else if (key == "LWMA") start.trend.method = key;
            else if (key == "ALMA") start.trend.method = key;
            else                                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(25)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            // value="7XD1[+2]"
            if (Explode(value, "+", elems, NULL) == 1) {
               start.trend.lag = 0;
            }
            else {
               value = StringTrim(elems[1]);
               if (!StringIsDigit(value))              return(_false(ValidateConfig.HandleError("ValidateConfiguration(26)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               start.trend.lag = StrToInteger(value);
               if (start.trend.lag < 0)                return(_false(ValidateConfig.HandleError("ValidateConfiguration(27)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               value = elems[0];
            }
            // value="7XD1"
            if (Explode(value, "X", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(28)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            elems[1]              = StringTrim(elems[1]);
            start.trend.timeframe = PeriodToId(elems[1]);
            if (start.trend.timeframe == -1)           return(_false(ValidateConfig.HandleError("ValidateConfiguration(29)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            value = StringTrim(elems[0]);
            if (!StringIsNumeric(value))               return(_false(ValidateConfig.HandleError("ValidateConfiguration(30)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            dValue = StrToDouble(value);
            if (dValue <= 0)                           return(_false(ValidateConfig.HandleError("ValidateConfiguration(31)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            if (NE(MathModFix(dValue, 0.5), 0))        return(_false(ValidateConfig.HandleError("ValidateConfiguration(32)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            elems[0] = NumberToStr(dValue, ".+");
            switch (start.trend.timeframe) {           // Timeframes > H1 auf H1 umrechnen, iCustom() soll unabhängig vom MA mit maximal PERIOD_H1 laufen
               case PERIOD_MN1:                        return(_false(ValidateConfig.HandleError("ValidateConfiguration(33)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               case PERIOD_H4 : { dValue *=   4; start.trend.timeframe = PERIOD_H1; break; }
               case PERIOD_D1 : { dValue *=  24; start.trend.timeframe = PERIOD_H1; break; }
               case PERIOD_W1 : { dValue *= 120; start.trend.timeframe = PERIOD_H1; break; }
            }
            start.trend.periods       = NormalizeDouble(dValue, 1);
            start.trend.timeframeFlag = PeriodFlag(start.trend.timeframe);
            start.trend.condition     = true;
            start.trend.condition.txt = "@trend("+ start.trend.method +":"+ elems[0] +"x"+ elems[1] + ifString(!start.trend.lag, "", "+"+ start.trend.lag) +")";
            exprs[i]                  = start.trend.condition.txt;
         }
         else                                          return(_false(ValidateConfig.HandleError("ValidateConfiguration(45)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      }
      StartConditions = JoinStrings(exprs, " && ");
   }


   // (8) __STATUS_INVALID_INPUT zurücksetzen
   if (interactive)
      __STATUS_INVALID_INPUT = false;

   return(!last_error|catch("ValidateConfiguration(77)"));
}


/**
 * Exception-Handler für ungültige Input-Parameter. Je nach Situation wird der Fehler weitergereicht oder zur Korrektur aufgefordert.
 *
 * @param  string location    - Ort, an dem der Fehler auftrat
 * @param  string message     - Fehlermeldung
 * @param  bool   interactive - ob der Fehler interaktiv behandelt werden kann
 *
 * @return int - der resultierende Fehlerstatus
 */
int ValidateConfig.HandleError(string location, string message, bool interactive) {
   if (IsTesting())
      interactive = false;
   if (!interactive)
      return(catch(location +"   "+ message, ERR_INVALID_CONFIG_PARAMVALUE));

   if (__LOG) log(StringConcatenate(location, "   ", message), ERR_INVALID_INPUT);
   ForceSound("chord.wav");
   int button = ForceMessageBox(__NAME__ +" - "+ location, message, MB_ICONERROR|MB_RETRYCANCEL);

   __STATUS_INVALID_INPUT = true;

   if (button == IDRETRY)
      __STATUS_RELAUNCH_INPUT = true;

   return(NO_ERROR);
}


/**
 * Speichert die Konfiguartionsdaten des EA's im Chart, sodaß der Status nach einem Recompile oder Terminal-Restart daraus wiederhergestellt werden kann.
 * Diese Werte umfassen die Input-Parameter, das Flag __STATUS_INVALID_INPUT und den Fehler ERR_CANCELLED_BY_USER.
 *
 * @return int - Fehlerstatus
 */
int StoreStickyStatus() {
   string label = StringConcatenate(__NAME__, ".sticky.StartConditions");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StartConditions, 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS_INVALID_INPUT), 1);

   label = StringConcatenate(__NAME__, ".sticky.CANCELLED_BY_USER");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", (last_error==ERR_CANCELLED_BY_USER)), 1);

   return(catch("StoreStickyStatus()"));
}


/**
 * Restauriert die im Chart gespeicherten Konfigurationsdaten.
 *
 * @return bool - ob gespeicherte Daten gefunden wurden
 */
bool RestoreStickyStatus() {
   string label, strValue;
   bool   statusFound;

   label = StringConcatenate(__NAME__, ".sticky.StartConditions");
   if (ObjectFind(label) == 0) {
      StartConditions = StringTrim(ObjectDescription(label));
      statusFound     = true;

      label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(1)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS_INVALID_INPUT = StrToInteger(strValue) != 0;
      }

      label = StringConcatenate(__NAME__, ".sticky.CANCELLED_BY_USER");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(2)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         if (StrToInteger(strValue) != 0)
            SetLastError(ERR_CANCELLED_BY_USER);
      }
   }

   return(statusFound && !(last_error|catch("RestoreStickyStatus(3)")));
}


/**
 * Löscht alle im Chart gespeicherten Konfigurationsdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearStickyStatus() {
   string label, prefix=StringConcatenate(__NAME__, ".sticky.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearStickyStatus()"));
}


/**
 * Unterdrückt unnütze Compilerwarnungen.
 */
void DummyCalls() {
   string sNulls[];
   int    iNulls[];
   FindChartSequences(sNulls, iNulls);
   IsSequenceStatus(NULL);
}
