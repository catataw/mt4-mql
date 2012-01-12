/**
 * SnowRoller Anti-Martingale EA
 *
 * @see 7bit strategy:  http://www.forexfactory.com/showthread.php?t=226059
 *      7bit journal:   http://www.forexfactory.com/showthread.php?t=239717
 *      7bit code base: http://sites.google.com/site/prof7bit/snowball
 */
#include <stdlib.mqh>
#include <win32api.mqh>


#define STATUS_WAITING        0           // mögliche Sequenzstatus-Werte
#define STATUS_PROGRESSING    1
#define STATUS_FINISHED       2
#define STATUS_DISABLED       3


int Strategy.Id = 103;                    // eindeutige ID der Strategie (Bereich 101-1023)


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern int    Gridsize                       = 20;
extern double Lotsize                        = 0.1;
extern string StartCondition                 = "";    // BollingerBands(35xM15, EMA, 2.0) // {LimitValue} | [Bollinger]Bands(35xM5,EMA,2.0) | Env[elopes](75xM15,ALMA,2.0)
extern int    TakeProfitLevels               = 5;
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

bool   firstTick = true;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
      return(ShowStatus());

   /*
   Zuerst wird die aktuelle Sequenz-ID bestimmt, dann deren Konfiguration geladen und validiert. Zum Schluß werden die Daten der ggf. laufenden Sequenz restauriert.
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
            if (RestoreInputSequenceId())
               if (RestoreConfiguration())
                  if (ValidateConfiguration())
                     ReadSequence();
         }
         else if (RestoreChartSequenceId()) {                        // ...dann ggf. eine im Chart gespeicherte Sequenz-ID restaurieren...
            if (RestoreConfiguration())
               if (ValidateConfiguration())
                  ReadSequence();
         }
         else if (RestoreRunningSequenceId()) {                      // ...dann ID aus laufender Sequenz restaurieren.
            if (RestoreConfiguration())
               if (ValidateConfiguration())
                  ReadSequence();
         }
         else if (ValidateConfiguration()) {                            // Zum Schluß neue Sequenz anlegen.
            sequenceId = CreateSequenceId();
            //if (StartCondition != "")                              // Ohne StartCondition erfolgt sofortiger Einstieg, in diesem Fall wird die
               SaveConfiguration();                                  // Konfiguration erst nach Sicherheitsabfrage in StartSequence() gespeichert.
         }
      }

      // (1.2) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      else if (RestoreChartSequenceId()) {                           // externe Referenz immer vorhanden: restaurieren und validieren
         if (RestoreConfiguration())
            if (ValidateConfiguration())
               ReadSequence();
      }
      else catch("init(1)   REASON_RECOMPILE, no stored sequence id found in chart", ERR_RUNTIME_ERROR);
   }

   // (1.3) Parameteränderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // alle internen Daten sind vorhanden
      if (ValidateConfiguration())
         SaveConfiguration();
      // TODO: die manuelle Sequence.ID kann geändert worden sein
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
   if (sequenceStatus==STATUS_FINISHED || sequenceStatus==STATUS_DISABLED)
      return(last_error);


   firstTick = false;


   // Status anzeigen
   ShowStatus();

   if (IsLastError())
      return(last_error);
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
      case STATUS_WAITING:     msg = StringConcatenate(":  sequence ", sequenceId, " waiting");
                               if (StringLen(StartCondition) > 0)
                                  msg = StringConcatenate(msg, " for ", StartCondition);                                                        break;
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
   string label = __SCRIPT__ +".sequence_id";

   if (ObjectFind(label) != -1)
      ObjectDelete(label);
   ObjectCreate(label, OBJ_LABEL, 0, 0, 0);
   ObjectSet(label, OBJPROP_XDISTANCE, -sequenceId);                 // negative Werte (im nicht sichtbaren Bereich)
   ObjectSet(label, OBJPROP_YDISTANCE, -hWnd);

   return(catch("StoreSequenceId()"));
}


/**
 * Restauriert eine im Chart ggf. gespeicherte Sequenz-ID.
 *
 * @return bool - ob eine Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreChartSequenceId() {
   string label = __SCRIPT__ +".sequence_id";

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


/**
 * Generiert eine neue Sequenz-ID.
 *
 * @return int - Sequenz-ID im Bereich 1000-16383 (14 bit)
 */
int CreateSequenceId() {
   MathSrand(GetTickCount());
   int id;
   while (id < 2000) {                                               // Das abschließende Shiften halbiert den Wert und wir wollen mindestens eine 4-stellige ID haben.
      id = MathRand();
   }
   return(id >> 1);
}


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @return bool - ob die Konfiguration gültig ist
 */
bool ValidateConfiguration() {
   // Gridsize
   if (Gridsize < 1)   return(catch("ValidateConfiguration(1)  Invalid input parameter Gridsize = "+ Gridsize, ERR_INVALID_INPUT_PARAMVALUE)==NO_ERROR);

   // Lotsize
   if (LE(Lotsize, 0)) return(catch("ValidateConfiguration(2)  Invalid input parameter Lotsize = "+ NumberToStr(Lotsize, ".+"), ERR_INVALID_INPUT_PARAMVALUE)==NO_ERROR);

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                      return(catch("ValidateConfiguration(3)   symbol=\""+ Symbol() +"\"", error)==NO_ERROR);
   if (LT(Lotsize, minLot))                 return(catch("ValidateConfiguration(4)   Invalid input parameter Lotsize = "+ NumberToStr(Lotsize, ".+") +" (MinLot="+  NumberToStr(minLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE));
   if (GT(Lotsize, maxLot))                 return(catch("ValidateConfiguration(5)   Invalid input parameter Lotsize = "+ NumberToStr(Lotsize, ".+") +" (MaxLot="+  NumberToStr(maxLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE));
   if (NE(MathModFix(Lotsize, lotStep), 0)) return(catch("ValidateConfiguration(6)   Invalid input parameter Lotsize = "+ NumberToStr(Lotsize, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", ERR_INVALID_INPUT_PARAMVALUE));


   // StartCondition
   StartCondition = StringTrim(StartCondition);                      // zur Zeit noch keine Validierung

   // TakeProfitLevels
   if (TakeProfitLevels < 1) return(catch("ValidateConfiguration(7)  Invalid input parameter TakeProfitLevels = "+ TakeProfitLevels, ERR_INVALID_INPUT_PARAMVALUE)==NO_ERROR);

   // Sequence.ID: falls gesetzt, wurde sie schon in RestoreInputSequenceId() validiert

   // TODO: Nach Parameteränderung die neue Konfiguration mit einer evt. bereits laufenden Sequenz abgleichen
   //       oder Parameter werden geändert, ohne vorher im Input-Dialog die Konfigurationsdatei der Sequenz zu laden.

   return(catch("ValidateConfiguration(8)")==NO_ERROR);
}


/**
 * Speichert aktuelle Konfiguration und Laufzeitdaten der Instanz, um die nahtlose Wiederauf- und Übernahme durch eine
 * andere Instanz im selben oder einem anderen Terminal zu ermöglichen.
 *
 * @return int - Fehlerstatus
 */
int SaveConfiguration() {
   if (sequenceId == 0)
      return(catch("SaveConfiguration(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR));

   // (1) Daten zusammenstellen
   string lines[];  ArrayResize(lines, 0);
   ArrayPushString(lines, /*string*/ "Sequence.ID="     +             sequenceId      );
   ArrayPushString(lines, /*int   */ "Gridsize="        +             Gridsize        );
   ArrayPushString(lines, /*double*/ "Lotsize="         + NumberToStr(Lotsize, ".+")  );
   ArrayPushString(lines, /*string*/ "StartCondition="  +             StartCondition  );
   ArrayPushString(lines, /*int   */ "TakeProfitLevels="+             TakeProfitLevels);


   // (2) Daten in lokale Datei schreiben
   string filename = "presets\\SR."+ sequenceId +".set";             // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch ist
                                                                     // das Presets-Verzeichnis für die MQL-Dateifunktionen erreichbar.
   int hFile = FileOpen(filename, FILE_CSV|FILE_WRITE);
   if (hFile < 0)
      return(catch("SaveConfiguration(2)  FileOpen(file=\""+ filename +"\")"));

   for (int i=0; i < ArraySize(lines); i++) {
      if (FileWrite(hFile, lines[i]) < 0) {
         int error = GetLastError();
         FileClose(hFile);
         return(catch("SaveConfiguration(3)  FileWrite(line #"+ (i+1) +")", error));
      }
   }
   FileClose(hFile);


   // (3) Datei auf Server laden
   if (!IsTesting()) {
      error = UploadConfiguration(ShortAccountCompany(), AccountNumber(), GetStandardSymbol(Symbol()), filename);
      if (IsError(error))
         return(error);
   }
   return(catch("SaveConfiguration(4)"));
}


/**
 * Lädt die angegebene Konfigurationsdatei auf den Server.
 *
 * @param  string company     - Account-Company
 * @param  int    account     - Account-Number
 * @param  string symbol      - Symbol der Konfiguration
 * @param  string presetsFile - Dateiname, relativ zu "{terminal-directory}\experts"
 *
 * @return int - Fehlerstatus
 */
int UploadConfiguration(string company, int account, string symbol, string presetsFile) {
   if (IsTesting()) {
      debug("UploadConfiguration()   skipping in tester");
      return(NO_ERROR);
   }

   // TODO: Existenz von wget.exe prüfen

   string parts[]; int size = Explode(presetsFile, "\\", parts, NULL);
   string file = parts[size-1];                                         // einfacher Dateiname ohne Verzeichnisse

   // Befehlszeile für Shellaufruf zusammensetzen
   string presetsPath  = TerminalPath() +"\\experts\\" + presetsFile;   // Dateinamen mit vollständigen Pfaden
   string responsePath = presetsPath +".response";
   string logPath      = presetsPath +".log";
   string url          = "http://sub.domain.tld/uploadSRConfiguration.php?company="+ UrlEncode(company) +"&account="+ account +"&symbol="+ UrlEncode(symbol) +"&name="+ UrlEncode(file);
   string cmdLine      = "wget.exe -b \""+ url +"\" --post-file=\""+ presetsPath +"\" --header=\"Content-Type: text/plain\" -O \""+ responsePath +"\" -a \""+ logPath +"\"";

   // Existenz der Datei prüfen
   if (!IsFile(presetsPath))
      return(catch("UploadConfiguration(1)   file not found: \""+ presetsPath +"\"", ERR_FILE_NOT_FOUND));

   // Datei hochladen, WinExec() kehrt ohne zu warten zurück, wget -b beschleunigt zusätzlich
   int error = WinExec(cmdLine, SW_HIDE);                               // SW_SHOWNORMAL|SW_HIDE
   if (error < 32)
      return(catch("UploadConfiguration(2) ->kernel32.WinExec(cmdLine=\""+ cmdLine +"\"), error="+ error +" ("+ ShellExecuteErrorToStr(error) +")", ERR_WIN32_ERROR));

   return(catch("UploadConfiguration(3)"));
}


/**
 * Liest die Konfiguration einer Sequenz ein und setzt die internen Variablen entsprechend. Ohne lokale Konfiguration
 * wird die Konfiguration vom Server geladen und lokal gespeichert.
 *
 * @return bool - ob die Konfiguration erfolgreich restauriert wurde
 */
bool RestoreConfiguration() {
   if (sequenceId == 0)
      return(!IsError(catch("RestoreConfiguration(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   // TODO: Existenz von wget.exe prüfen

   // (1) bei nicht existierender lokaler Konfiguration die Datei vom Server laden
   string filesDir = TerminalPath() +"\\experts\\files\\";           // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch
   string fileName = "presets\\SR."+ sequenceId +".set";             // ist das Presets-Verzeichnis für die MQL-Dateifunktionen erreichbar.

   if (!IsFile(filesDir + fileName)) {
      // Befehlszeile für Shellaufruf zusammensetzen
      string url        = "http://sub.domain.tld/downloadSRConfiguration.php?company="+ UrlEncode(ShortAccountCompany()) +"&account="+ AccountNumber() +"&symbol="+ UrlEncode(GetStandardSymbol(Symbol())) +"&sequence="+ sequenceId;
      string targetFile = filesDir +"\\"+ fileName;
      string logFile    = filesDir +"\\"+ fileName +".log";
      string cmdLine    = "wget.exe \""+ url +"\" -O \""+ targetFile +"\" -o \""+ logFile +"\"";

      debug("RestoreConfiguration()   downloading configuration for sequence "+ sequenceId);

      int error = WinExecAndWait(cmdLine, SW_HIDE);                  // SW_SHOWNORMAL|SW_HIDE
      if (IsError(error))
         return(SetLastError(error)==NO_ERROR);

      debug("RestoreConfiguration()   configuration for sequence "+ sequenceId +" successfully downloaded");
      FileDelete(fileName +".log");
   }

   // (2) Datei einlesen
   string config[];
   int lines = FileReadLines(fileName, config, true);
   if (lines < 0)
      return(SetLastError(stdlib_PeekLastError())==NO_ERROR);
   if (lines == 0) {
      FileDelete(fileName);
      return(catch("RestoreConfiguration(2)   no configuration found for sequence "+ sequenceId, ERR_RUNTIME_ERROR)==NO_ERROR);
   }

   // (3) Zeilen in Schlüssel-Wert-Paare aufbrechen, Datentypen validieren und Daten übernehmen
   int keys[4]; ArrayInitialize(keys, 0);
   #define I_GRIDSIZE          0
   #define I_LOTSIZE           1
   #define I_START_CONDITION   2
   #define I_TAKEPROFIT_LEVELS 3

   string parts[];
   for (int i=0; i < lines; i++) {
      if (Explode(config[i], "=", parts, 2) != 2) return(catch("RestoreConfiguration(3)   invalid configuration file \""+ fileName +"\" (line \""+ config[i] +"\")", ERR_RUNTIME_ERROR)==NO_ERROR);
      string key=parts[0], value=parts[1];

      Sequence.ID = sequenceId;

      if (key == "Gridsize") {
         if (!StringIsDigit(value))               return(catch("RestoreConfiguration(4)   invalid configuration file \""+ fileName +"\" (line \""+ config[i] +"\")", ERR_RUNTIME_ERROR)==NO_ERROR);
         Gridsize = StrToInteger(value);
         keys[I_GRIDSIZE] = 1;
      }
      else if (key == "Lotsize") {
         if (!StringIsNumeric(value))             return(catch("RestoreConfiguration(5)   invalid configuration file \""+ fileName +"\" (line \""+ config[i] +"\")", ERR_RUNTIME_ERROR)==NO_ERROR);
         Lotsize = StrToDouble(value);
         keys[I_LOTSIZE] = 1;
      }
      else if (key == "StartCondition") {
         StartCondition = value;
         keys[I_START_CONDITION] = 1;
      }
      else if (key == "TakeProfitLevels") {
         if (!StringIsDigit(value))               return(catch("RestoreConfiguration(6)   invalid configuration file \""+ fileName +"\" (line \""+ config[i] +"\")", ERR_RUNTIME_ERROR)==NO_ERROR);
         TakeProfitLevels = StrToInteger(value);
         keys[I_TAKEPROFIT_LEVELS] = 1;
      }
   }
   if (IntInArray(0, keys))                       return(catch("RestoreConfiguration(7)   one or more configuration values missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)==NO_ERROR);

   return(catch("RestoreConfiguration(8)")==NO_ERROR);
}


/**
 * Liest die aktuelle Sequenz neu ein. Die Variable sequenceId und die Konfiguration der Sequenz sind beim Aufruf immer gültig.
 *
 * @return bool - Erfolgsstatus
 */
bool ReadSequence() {
   return(catch("ReadSequence()")==NO_ERROR);
}
