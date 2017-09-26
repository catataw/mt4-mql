/**
 * Funktionen zur Verwaltung von Kursreihen im "history"-Verzeichnis.
 *
 *
 * Anwendungsbeispiele
 * -------------------
 *  1. �ffnen einer existierenden History mit vorhandenen Daten:
 *     int hSet = HistorySet.Get(symbol);
 *
 *  2. Erzeugen einer neuen History (vorhandene Daten werden gel�scht):
 *     int hSet = HistorySet.Create(symbol, description, digits, format);
 */
#property library

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/library.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinStrings.mqh>
#include <structs/mt4/HistoryHeader.mqh>
#include <structs/mt4/Symbol.mqh>
#include <structs/mt4/SymbolGroup.mqh>


// Standard-Timeframes ------------------------------------------------------------------------------------------------------------------------------------
int      periods[] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1 };


// Daten kompletter History-Sets --------------------------------------------------------------------------------------------------------------------------
int      hs.hSet       [];                            // Set-Handle: gr��er 0 = offenes Handle; kleiner 0 = geschlossenes Handle; 0 = ung�ltiges Handle
int      hs.hSet.lastValid;                           // das letzte g�ltige, offene Handle (um ein �bergebenes Handle nicht st�ndig neu validieren zu m�ssen)
string   hs.symbol     [];                            // Symbol
string   hs.symbolUpper[];                            // SYMBOL (Upper-Case)
string   hs.copyright  [];                            // Copyright oder Beschreibung
int      hs.digits     [];                            // Symbol-Digits
string   hs.server     [];                            // Servername des Sets
int      hs.hFile      [][9];                         // HistoryFile-Handles des Sets je Standard-Timeframe
int      hs.format     [];                            // Datenformat f�r neu zu erstellende HistoryFiles


// Daten einzelner History-Files --------------------------------------------------------------------------------------------------------------------------
int      hf.hFile      [];                            // Dateihandle: gr��er 0 = offenes Handle; kleiner 0 = geschlossenes Handle; 0 = ung�ltiges Handle
int      hf.hFile.lastValid;                          // das letzte g�ltige, offene Handle (um ein �bergebenes Handle nicht st�ndig neu validieren zu m�ssen)
string   hf.name       [];                            // Dateiname, ggf. mit Unterverzeichnis "XTrade-Synthetic\"
bool     hf.readAccess [];                            // ob das Handle Lese-Zugriff erlaubt
bool     hf.writeAccess[];                            // ob das Handle Schreib-Zugriff erlaubt

int      hf.header     [][HISTORY_HEADER.intSize];    // History-Header der Datei
int      hf.format     [];                            // Datenformat: 400 | 401
int      hf.barSize    [];                            // Gr��e einer Bar entsprechend dem Datenformat
string   hf.symbol     [];                            // Symbol
string   hf.symbolUpper[];                            // SYMBOL (Upper-Case)
int      hf.period     [];                            // Periode
int      hf.periodSecs [];                            // Dauer einer Periode in Sekunden (nicht g�ltig f�r Perioden > 1 Woche)
int      hf.digits     [];                            // Digits
string   hf.server     [];                            // Servername der Datei

int      hf.stored.bars              [];              // Metadaten: Anzahl der gespeicherten Bars der Datei
int      hf.stored.from.offset       [];              // Offset der ersten gespeicherten Bar der Datei
datetime hf.stored.from.openTime     [];              // OpenTime der ersten gespeicherten Bar der Datei
datetime hf.stored.from.closeTime    [];              // CloseTime der ersten gespeicherten Bar der Datei
datetime hf.stored.from.nextCloseTime[];              // CloseTime der der ersten gespeicherten Bar der Datei folgenden Bar
int      hf.stored.to.offset         [];              // Offset der letzten gespeicherten Bar der Datei
datetime hf.stored.to.openTime       [];              // OpenTime der letzten gespeicherten Bar der Datei
datetime hf.stored.to.closeTime      [];              // CloseTime der letzten gespeicherten Bar der Datei
datetime hf.stored.to.nextCloseTime  [];              // CloseTime der der letzten gespeicherten Bar der Datei folgenden Bar

int      hf.full.bars                [];              // Metadaten: Anzahl der Bars der Datei inkl. ungespeicherter Daten im Schreibpuffer
int      hf.full.from.offset         [];              // Offset der ersten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.from.openTime       [];              // OpenTime der ersten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.from.closeTime      [];              // CloseTime der ersten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.from.nextCloseTime  [];              // CloseTime der der ersten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer folgenden Bar
int      hf.full.to.offset           [];              // Offset der letzten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.to.openTime         [];              // OpenTime der letzten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.to.closeTime        [];              // CloseTime der letzten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer
datetime hf.full.to.nextCloseTime    [];              // CloseTime dre der letzten Bar der Datei inkl. ungespeicherter Daten im Schreibpuffer folgenden Bar


// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Cache der Bar, die in der Historydatei zuletzt gelesen oder geschrieben wurde (eine beliebige in der Datei existierende Bar).
//
// (1) Beim Aktualisieren dieser Bar mit neuen Ticks braucht die Bar nicht jedesmal neu eingelesen werden: siehe HistoryFile.UpdateBar().
// (2) Bei funktions�bergreifenden Abl�ufen mu� diese Bar nicht �berall als Parameter durchgeschleift werden (durch unterschiedliche Arraydimensionen schwierig).
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
int      hf.lastStoredBar.offset       [];            // Offset relativ zum Header: Offset 0 ist die �lteste Bar, initialisiert mit -1
datetime hf.lastStoredBar.openTime     [];            // z.B. 12:00:00      |                  time < openTime:      time liegt irgendwo in einer vorherigen Bar
datetime hf.lastStoredBar.closeTime    [];            //      13:00:00      |      openTime <= time < closeTime:     time liegt genau in der Bar
datetime hf.lastStoredBar.nextCloseTime[];            //      14:00:00      |     closeTime <= time < nextCloseTime: time liegt genau in der n�chsten Bar
double   hf.lastStoredBar.data         [][6];         // Bardaten (T-OHLCV) | nextCloseTime <= time:                 time liegt irgendwo vor der n�chsten Bar


// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Schreibpuffer f�r eintreffende Ticks einer bereits gespeicherten oder noch nicht gespeicherten Bar. Die Variable hf.bufferedBar.modified signalisiert, ob die
// Bardaten in hf.bufferedBar von den in der Datei gespeicherten Daten abweichen.
//
// (1) Diese Bar stimmt mit hf.lastStoredBar nur dann �berein, wenn hf.lastStoredBar die j�ngste Bar der Datei ist und mit HST_BUFFER_TICKS=On weitere Ticks f�r diese
//     j�ngste Bar gepuffert werden. Stimmen beide Bars �berein, werden sie bei �nderungen an einer der Bars jeweils synchronisiert.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
int      hf.bufferedBar.offset       [];              // Offset relativ zum Header: Offset 0 ist die �lteste Bar, initialisiert mit -1
datetime hf.bufferedBar.openTime     [];              // z.B. 12:00:00      |                  time < openTime:      time liegt irgendwo in einer vorherigen Bar
datetime hf.bufferedBar.closeTime    [];              //      13:00:00      |      openTime <= time < closeTime:     time liegt genau in der Bar
datetime hf.bufferedBar.nextCloseTime[];              //      14:00:00      |     closeTime <= time < nextCloseTime: time liegt genau in der n�chsten Bar
double   hf.bufferedBar.data         [][6];           // Bardaten (T-OHLCV) | nextCloseTime <= time:                 time liegt irgendwo vor der n�chsten Bar
bool     hf.bufferedBar.modified     [];              // ob die Daten seit dem letzten Schreiben modifiziert wurden


/**
 * Erzeugt f�r ein Symbol ein neues HistorySet mit den angegebenen Daten und gibt dessen Handle zur�ck. Beim Aufruf der
 * Funktion werden bereits existierende HistoryFiles des Symbols zur�ckgesetzt (vorhandene Bardaten werden gel�scht) und evt.
 * offene HistoryFile-Handles geschlossen. Noch nicht existierende HistoryFiles werden beim ersten Speichern hinzugef�gter Daten
 * automatisch erstellt.
 *
 * Mehrfachaufrufe dieser Funktion f�r dasselbe Symbol geben jeweils ein neues Handle zur�ck, ein vorheriges Handle wird
 * geschlossen.
 *
 * @param  _In_ string symbol    - Symbol
 * @param  _In_ string copyright - Copyright oder Beschreibung
 * @param  _In_ int    digits    - Digits der Datenreihe
 * @param  _In_ int    format    - Speicherformat der Datenreihe: 400 - altes Datenformat (wie MetaTrader <= Build 509)
 *                                                                401 - neues Datenformat (wie MetaTrader  > Build 509)
 * @param  _In_ string server    - Name des Serververzeichnisses, in dem das Set gespeichert wird (default: aktuelles Serververzeichnis)
 *
 * @return int - Set-Handle oder NULL, falls ein Fehler auftrat.
 */
int HistorySet.Create(string symbol, string copyright, int digits, int format, string server="") {
   // Parametervalidierung
   if (!StringLen(symbol))                    return(!catch("HistorySet.Create(1)  invalid parameter symbol = "+ DoubleQuoteStr(symbol), ERR_INVALID_PARAMETER));
   if (StringLen(symbol) > MAX_SYMBOL_LENGTH) return(!catch("HistorySet.Create(2)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (max "+ MAX_SYMBOL_LENGTH +" characters)", ERR_INVALID_PARAMETER));
   if (StringContains(symbol, " "))           return(!catch("HistorySet.Create(3)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (must not contain spaces)", ERR_INVALID_PARAMETER));
   string symbolUpper = StringToUpper(symbol);
   if (!StringLen(copyright))     copyright = "";                                // NULL-Pointer => Leerstring
   if (StringLen(copyright) > 63) copyright = StringLeft(copyright, 63);         // ein zu langer String wird gek�rzt
   if (digits < 0)                            return(!catch("HistorySet.Create(4)  invalid parameter digits = "+ digits +" [hstSet="+ DoubleQuoteStr(symbol) +"]", ERR_INVALID_PARAMETER));
   if (format!=400) /*&&*/ if (format!=401)   return(!catch("HistorySet.Create(5)  invalid parameter format = "+ format +" (can be 400 or 401) [hstSet="+ DoubleQuoteStr(symbol) +"]", ERR_INVALID_PARAMETER));
   if (server == "0")      server = "";                                          // (string) NULL
   if (!StringLen(server)) server = GetServerName();


   // (1) offene Set-Handles durchsuchen und Sets schlie�en
   int size = ArraySize(hs.hSet);
   for (int i=0; i < size; i++) {                                       // Das Handle mu� offen sein.
      if (hs.hSet[i] > 0) /*&&*/ if (hs.symbolUpper[i]==symbolUpper) /*&&*/ if (StringCompareI(hs.server[i], server)) {
         // wenn Symbol gefunden, Set schlie�en...
         if (hs.hSet.lastValid == hs.hSet[i])
            hs.hSet.lastValid = NULL;
         hs.hSet[i] = -1;

         // Dateien des Sets schlie�en...
         size = ArrayRange(hs.hFile, 1);
         for (int n=0; n < size; n++) {
            if (hs.hFile[i][n] > 0) {
               if (!HistoryFile.Close(hs.hFile[i][n]))
                  return(NULL);
               hs.hFile[i][n] = -1;
            }
         }
      }
   }


   // (2) offene File-Handles durchsuchen und Dateien schlie�en
   size = ArraySize(hf.hFile);
   for (i=0; i < size; i++) {                                           // Das Handle mu� offen sein.
      if (hf.hFile[i] > 0) /*&&*/ if (hf.symbolUpper[i]==symbolUpper) /*&&*/ if (StringCompareI(hf.server[i], server)){
         if (!HistoryFile.Close(hf.hFile[i]))
            return(NULL);
      }
   }


   // (3) existierende HistoryFiles zur�cksetzen und ihre Header aktualisieren
   string mqlDir     = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string mqlHstDir  = ".history\\"+ server +"\\";                      // Verzeichnisname f�r MQL-Dateifunktionen
   string fullHstDir = TerminalPath() + mqlDir +"\\files\\"+ mqlHstDir; // Verzeichnisname f�r Win32-Dateifunktionen
   string baseName, mqlFileName, fullFileName;
   int hFile, fileSize, sizeOfPeriods=ArraySize(periods), error;

   /*HISTORY_HEADER*/int hh[]; InitializeByteBuffer(hh, HISTORY_HEADER.size);
   hh_SetBarFormat(hh, format   );
   hh_SetCopyright(hh, copyright);
   hh_SetSymbol   (hh, symbol   );
   hh_SetDigits   (hh, digits   );

   for (i=0; i < sizeOfPeriods; i++) {
      baseName = symbol + periods[i] +".hst";
      mqlFileName  = mqlHstDir  + baseName;                             // Dateiname f�r MQL-Dateifunktionen
      fullFileName = fullHstDir + baseName;                             // Dateiname f�r Win32-Dateifunktionen

      if (IsFile(fullFileName)) {                                       // wenn Datei existiert, auf 0 zur�cksetzen
         hFile = FileOpen(mqlFileName, FILE_BIN|FILE_WRITE);
         if (hFile <= 0) return(!catch("HistorySet.Create(6)  fileName=\""+ mqlFileName +"\"  hFile="+ hFile, ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR)));

         hh_SetPeriod(hh, periods[i]);
         FileWriteArray(hFile, hh, 0, ArraySize(hh));                   // neuen HISTORY_HEADER schreiben
         FileClose(hFile);
         if (!catch("HistorySet.Create(7)  [hstSet="+ DoubleQuoteStr(symbol) +"]"))
            continue;
         return(NULL);
      }
   }
   ArrayResize(hh, 0);


   // (4) neues HistorySet erzeugen
   size = Max(ArraySize(hs.hSet), 1) + 1;                               // minSize=2: auf Index[0] kann kein g�ltiges Handle liegen
   __ResizeSetArrays(size);
   int iH   = size-1;
   int hSet = iH;                                                       // das Set-Handle entspricht jeweils dem Index in hs.*[]

   hs.hSet       [iH] = hSet;
   hs.symbol     [iH] = symbol;
   hs.symbolUpper[iH] = symbolUpper;
   hs.copyright  [iH] = copyright;
   hs.digits     [iH] = digits;
   hs.server     [iH] = server;
   hs.format     [iH] = format;


   // (5) ist das Instrument synthetisch, Symboldatensatz aktualisieren
   if (false) {
      // (5.1) "symgroups.raw": Symbolgruppe finden (ggf. anlegen)
      string groupName, prefix=StringLeft(symbolUpper, 3), suffix=StringRight(symbolUpper, 3);
      string accountStatSuffixes[] = {".EA", ".EX", ".LA", ".PL"};

      // Gruppe bestimmen und deren Index ermitteln
      bool isAccountStat = StringInArray(accountStatSuffixes, suffix);

      if (This.IsTesting()) {
         if (isAccountStat) groupName = "Tester Results";               // es k�nnen nur Testdaten sein
         else               groupName = "Tester Other";
      }
      else {
         if (isAccountStat) groupName = "Account Statistics";           // es k�nnen Accountdaten sein
         else               groupName = "Other";                        // es kann etwas anderes sein
      }

      // (5.2) "symbols.raw": Symboldatensatz �ber- bzw. neuschreiben
   }

   return(hSet);
}


/**
 * Gibt ein Handle f�r das gesamte HistorySet eines Symbols zur�ck. Wurde das HistorySet vorher nicht mit HistorySet.Create()
 * erzeugt, mu� mindestens ein HistoryFile des Symbols existieren. Noch nicht existierende HistoryFiles werden beim Speichern
 * der ersten hinzugef�gten Daten automatisch im alten Datenformat (400) erstellt.
 *
 * - Mehrfachaufrufe dieser Funktion f�r dasselbe Symbol geben dasselbe Handle zur�ck.
 * - Die Funktion greift ggf. auf genau eine Historydatei lesend zu. Sie h�lt keine Dateien offen.
 *
 * @param  _In_ string symbol - Symbol
 * @param  _In_ string server - Name des Serververzeichnisses, in dem das Set gespeichert wird (default: aktuelles Serververzeichnis)
 *
 * @return int - � Set-Handle oder -1, falls kein HistoryFile dieses Symbols existiert. In diesem Fall mu� mit HistorySet.Create() ein neues Set erzeugt werden.
 *               � NULL, falls ein Fehler auftrat.
 *
 *
 * NOTE: evt. Timeframe-Flags f�r selektive Sets implementieren (z.B. alles au�er W1 und MN1)
 */
int HistorySet.Get(string symbol, string server="") {
   if (!StringLen(symbol))                    return(!catch("HistorySet.Get(1)  invalid parameter symbol = "+ DoubleQuoteStr(symbol), ERR_INVALID_PARAMETER));
   if (StringLen(symbol) > MAX_SYMBOL_LENGTH) return(!catch("HistorySet.Get(2)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (max "+ MAX_SYMBOL_LENGTH +" characters)", ERR_INVALID_PARAMETER));
   if (StringContains(symbol, " "))           return(!catch("HistorySet.Get(3)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (must not contain spaces)", ERR_INVALID_PARAMETER));
   string symbolUpper = StringToUpper(symbol);
   if (server == "0")      server = "";                                 // (string) NULL
   if (!StringLen(server)) server = GetServerName();


   // (1) offene Set-Handles durchsuchen
   int size = ArraySize(hs.hSet);
   for (int i=0; i < size; i++) {                                       // Das Handle mu� offen sein.
      if (hs.hSet[i] > 0) /*&&*/ if (hs.symbolUpper[i]==symbolUpper) /*&&*/ if (StringCompareI(hs.server[i], server))
         return(hs.hSet[i]);
   }                                                                    // kein offenes Set-Handle gefunden

   int iH, hSet=-1;

   // (2) offene File-Handles durchsuchen
   size = ArraySize(hf.hFile);
   for (i=0; i < size; i++) {                                           // Das Handle mu� offen sein.
      if (hf.hFile[i] > 0) /*&&*/ if (hf.symbolUpper[i]==symbolUpper) /*&&*/ if (StringCompareI(hf.server[i], server)) {
         size = Max(ArraySize(hs.hSet), 1) + 1;                         // neues HistorySet erstellen (minSize=2: auf Index[0] kann kein g�ltiges Handle liegen)
         __ResizeSetArrays(size);
         iH   = size-1;
         hSet = iH;                                                     // das Set-Handle entspricht jeweils dem Index in hs.*[]

         hs.hSet       [iH] = hSet;
         hs.symbol     [iH] = hf.symbol     [i];
         hs.symbolUpper[iH] = hf.symbolUpper[i];
         hs.copyright  [iH] = hhs_Copyright(hf.header, i);
         hs.digits     [iH] = hf.digits     [i];
         hs.server     [iH] = hf.server     [i];
         hs.format     [iH] = 400;                                      // Default f�r neu zu erstellende HistoryFiles

         return(hSet);
      }
   }                                                                    // kein offenes File-Handle gefunden


   // (3) existierende HistoryFiles suchen
   string mqlDir     = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string mqlHstDir  = ".history\\"+ server +"\\";                      // Verzeichnisname f�r MQL-Dateifunktionen
   string fullHstDir = TerminalPath() + mqlDir +"\\files\\"+ mqlHstDir; // Verzeichnisname f�r Win32-Dateifunktionen

   string baseName, mqlFileName, fullFileName;
   int hFile, fileSize, sizeOfPeriods=ArraySize(periods);

   for (i=0; i < sizeOfPeriods; i++) {
      baseName     = symbol + periods[i] +".hst";
      mqlFileName  = mqlHstDir  + baseName;                             // Dateiname f�r MQL-Dateifunktionen
      fullFileName = fullHstDir + baseName;                             // Dateiname f�r Win32-Dateifunktionen

      if (IsFile(fullFileName)) {                                       // wenn Datei existiert, �ffnen
         hFile = FileOpen(mqlFileName, FILE_BIN|FILE_READ);             // FileOpenHistory() kann Unterverzeichnisse nicht handhaben => alle Zugriffe per FileOpen(symlink)
         if (hFile <= 0) return(!catch("HistorySet.Get(4)  hFile(\""+ mqlFileName +"\") = "+ hFile, ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR)));

         fileSize = FileSize(hFile);                                    // Datei ge�ffnet
         if (fileSize < HISTORY_HEADER.size) {
            FileClose(hFile);
            warn("HistorySet.Get(5)  invalid history file \""+ mqlFileName +"\" found (size="+ fileSize +")");
            continue;
         }
                                                                        // HISTORY_HEADER auslesen
         /*HISTORY_HEADER*/int hh[]; ArrayResize(hh, HISTORY_HEADER.intSize);
         FileReadArray(hFile, hh, 0, HISTORY_HEADER.intSize);
         FileClose(hFile);

         size = Max(ArraySize(hs.hSet), 1) + 1;                         // neues HistorySet erstellen (minSize=2: auf Index[0] kann kein g�ltiges Handle liegen)
         __ResizeSetArrays(size);
         iH   = size-1;
         hSet = iH;                                                     // das Set-Handle entspricht jeweils dem Index in hs.*[]

         hs.hSet       [iH] = hSet;
         hs.symbol     [iH] = hh_Symbol   (hh);
         hs.symbolUpper[iH] = StringToUpper(hs.symbol[iH]);
         hs.copyright  [iH] = hh_Copyright(hh);
         hs.digits     [iH] = hh_Digits   (hh);
         hs.server     [iH] = server;
         hs.format     [iH] = 400;                                      // Default f�r neu zu erstellende HistoryFiles

         ArrayResize(hh, 0);
         return(hSet);                                                  // R�ckkehr nach der ersten ausgewerteten Datei
      }
   }


   if (!catch("HistorySet.Get(6)  [hstSet="+ DoubleQuoteStr(symbol) +"]"))
      return(-1);
   return(NULL);
}


/**
 * Schlie�t das HistorySet mit dem angegebenen Handle.
 *
 * @param  _In_ int hSet - Set-Handle
 *
 * @return bool - Erfolgsstatus
 */
bool HistorySet.Close(int hSet) {
   // Validierung
   if (hSet <= 0)                     return(!catch("HistorySet.Close(1)  invalid set handle "+ hSet, ERR_INVALID_PARAMETER));
   if (hSet != hs.hSet.lastValid) {
      if (hSet >= ArraySize(hs.hSet)) return(!catch("HistorySet.Close(2)  invalid set handle "+ hSet, ERR_INVALID_PARAMETER));
      if (hs.hSet[hSet] == 0)         return(!catch("HistorySet.Close(3)  unknown set handle "+ hSet +" [hstSet="+ DoubleQuoteStr(hs.symbol[hSet]) +"]", ERR_INVALID_PARAMETER));
   }
   else {
      hs.hSet.lastValid = NULL;
   }
   if (hs.hSet[hSet] < 0) return(true);                              // Handle wurde bereits geschlossen (kann ignoriert werden)

   int sizeOfPeriods = ArraySize(periods);

   for (int i=0; i < sizeOfPeriods; i++) {
      if (hs.hFile[hSet][i] > 0) {                                   // alle offenen Dateihandles schlie�en
         if (!HistoryFile.Close(hs.hFile[hSet][i])) return(false);
         hs.hFile[hSet][i] = -1;
      }
   }
   hs.hSet[hSet] = -1;
   return(true);
}


/**
 * F�gt dem HistorySet eines Symbols einen Tick hinzu. Der Tick wird als letzter Tick (Close) der entsprechenden Bar gespeichert.
 *
 * @param  _In_ int      hSet  - Set-Handle des Symbols
 * @param  _In_ datetime time  - Zeitpunkt des Ticks
 * @param  _In_ double   value - Datenwert
 * @param  _In_ int      flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                               � HST_BUFFER_TICKS: buffert aufeinanderfolgende Ticks und schreibt die Daten erst beim jeweils n�chsten BarOpen-Event
 *                               � HST_FILL_GAPS:    f�llt entstehende Gaps mit dem letzten Schlu�kurs vor dem Gap
 *
 * @return bool - Erfolgsstatus
 */
bool HistorySet.AddTick(int hSet, datetime time, double value, int flags=NULL) {
   // Validierung
   if (hSet <= 0)                     return(!catch("HistorySet.AddTick(1)  invalid parameter hSet = "+ hSet, ERR_INVALID_PARAMETER));
   if (hSet != hs.hSet.lastValid) {
      if (hSet >= ArraySize(hs.hSet)) return(!catch("HistorySet.AddTick(2)  invalid parameter hSet = "+ hSet, ERR_INVALID_PARAMETER));
      if (hs.hSet[hSet] == 0)         return(!catch("HistorySet.AddTick(3)  invalid parameter hSet = "+ hSet +" (unknown handle) [hstSet="+ DoubleQuoteStr(hs.symbol[hSet]) +"]", ERR_INVALID_PARAMETER));
      if (hs.hSet[hSet] <  0)         return(!catch("HistorySet.AddTick(4)  invalid parameter hSet = "+ hSet +" (closed handle) [hstSet="+ DoubleQuoteStr(hs.symbol[hSet]) +"]", ERR_INVALID_PARAMETER));
      hs.hSet.lastValid = hSet;
   }
   if (time <= 0)                     return(!catch("HistorySet.AddTick(5)  invalid parameter time = "+ time +" [hstSet="+ DoubleQuoteStr(hs.symbol[hSet]) +"]", ERR_INVALID_PARAMETER));

   // Dateihandles holen und jeweils Tick hinzuf�gen
   int hFile, sizeOfPeriods=ArraySize(periods);

   for (int i=0; i < sizeOfPeriods; i++) {
      hFile = hs.hFile[hSet][i];
      if (!hFile) {                                                  // noch unge�ffnete Dateien �ffnen
         hFile = HistoryFile.Open(hs.symbol[hSet], periods[i], hs.copyright[hSet], hs.digits[hSet], hs.format[hSet], FILE_READ|FILE_WRITE, hs.server[hSet]);
         if (!hFile) return(false);
         hs.hFile[hSet][i] = hFile;
      }
      if (!HistoryFile.AddTick(hFile, time, value, flags)) return(false);
   }
   return(true);
}


/**
 * �ffnet eine Historydatei im angegeben Access-Mode und gibt deren Handle zur�ck.
 *
 * � Ist FILE_WRITE angegeben und die Datei existiert nicht, wird sie erstellt.
 * � Ist FILE_WRITE jedoch nicht FILE_READ angegeben und die Datei existiert, wird sie zur�ckgesetzt und vorhandene Daten gel�scht.
 *
 * @param  _In_ string symbol    - Symbol des Instruments
 * @param  _In_ int    timeframe - Timeframe der Zeitreihe
 * @param  _In_ string copyright - Copyright oder Beschreibung (falls die Historydatei neu erstellt wird)
 * @param  _In_ int    digits    - Digits der Werte            (falls die Historydatei neu erstellt wird)
 * @param  _In_ int    format    - Datenformat der Zeitreihe   (falls die Historydatei neu erstellt wird)
 * @param  _In_ int    mode      - Access-Mode: FILE_READ|FILE_WRITE
 * @param  _In_ string server    - Name des Serververzeichnisses, in dem die Datei gespeichert wird (default: aktuelles Serververzeichnis)
 *
 * @return int - � Dateihandle oder
 *               � -1, falls nur FILE_READ angegeben wurde und die Datei nicht existiert oder
 *               � NULL, falls ein anderer Fehler auftrat
 *
 *
 * NOTES: (1) Das Dateihandle kann nicht modul-�bergreifend verwendet werden.
 *        (2) Mit den MQL-Dateifunktionen k�nnen je Modul maximal 64 Dateien gleichzeitig offen gehalten werden.
 */
int HistoryFile.Open(string symbol, int timeframe, string copyright, int digits, int format, int mode, string server="") {
   if (!StringLen(symbol))                    return(_NULL(catch("HistoryFile.Open(1)  invalid parameter symbol = "+ DoubleQuoteStr(symbol), ERR_INVALID_PARAMETER)));
   if (StringLen(symbol) > MAX_SYMBOL_LENGTH) return(_NULL(catch("HistoryFile.Open(2)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (max "+ MAX_SYMBOL_LENGTH +" characters)", ERR_INVALID_PARAMETER)));
   if (StringContains(symbol, " "))           return(_NULL(catch("HistoryFile.Open(3)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (must not contain spaces)", ERR_INVALID_PARAMETER)));
   string symbolUpper = StringToUpper(symbol);
   if (timeframe <= 0)                        return(_NULL(catch("HistoryFile.Open(4)  invalid parameter timeframe = "+ timeframe +" [hstFile="+ DoubleQuoteStr(symbol) +"]", ERR_INVALID_PARAMETER)));
   if (!(mode & (FILE_READ|FILE_WRITE)))      return(_NULL(catch("HistoryFile.Open(5)  invalid file access mode = "+ mode +" (must be FILE_READ and/or FILE_WRITE) [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ERR_INVALID_PARAMETER)));
   mode &= (FILE_READ|FILE_WRITE);                                                  // alle anderen Bits l�schen
   bool read_only  = !(mode & FILE_WRITE);
   bool write_only = !(mode & FILE_READ);
   bool read_write =  (mode & FILE_READ) && (mode & FILE_WRITE);

   if (server == "0")      server = "";                                             // (string) NULL
   if (!StringLen(server)) server = GetServerName();


   // (1) Datei �ffnen
   string mqlDir      = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string mqlHstDir   = ".history\\"+ server +"\\";                                 // Verzeichnisname f�r MQL-Dateifunktionen
   string fullHstDir  = TerminalPath() + mqlDir +"\\files\\"+ mqlHstDir;            // Verzeichnisname f�r Win32-Dateifunktionen
   string baseName    = symbol + timeframe +".hst";
   string mqlFileName = mqlHstDir  + baseName;
   // Schreibzugriffe werden nur auf ein existierendes Serververzeichnis erlaubt.
   if (!read_only) /*&&*/ if (!IsDirectory(fullHstDir)) return(_NULL(catch("HistoryFile.Open(6)  directory "+ DoubleQuoteStr(fullHstDir) +" doesn't exist [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ERR_RUNTIME_ERROR)));

   int hFile;

   // (1.1) read-only                                                               // Bei read-only kann die Existenz nicht mit FileOpen() gepr�ft werden, da die
   if (read_only) {                                                                 // Funktion das Log bei fehlender Datei mit Warnungen ERR_CANNOT_OPEN_FILE zum�llt.
      if (!IsMqlFile(mqlFileName)) return(-1);                                      // file not found
      hFile = FileOpen(mqlFileName, mode|FILE_BIN);
      if (hFile <= 0) return(_NULL(catch("HistoryFile.Open(7)->FileOpen(\""+ mqlFileName +"\", FILE_READ) => "+ hFile +" [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR))));
   }

   // (1.2) read-write
   else if (read_write) {
      hFile = FileOpen(mqlFileName, mode|FILE_BIN);
      if (hFile <= 0) return(_NULL(catch("HistoryFile.Open(8)->FileOpen(\""+ mqlFileName +"\", FILE_READ|FILE_WRITE) => "+ hFile +" [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR))));
   }

   // (1.3) write-only
   else if (write_only) {
      hFile = FileOpen(mqlFileName, mode|FILE_BIN);
      if (hFile <= 0) return(_NULL(catch("HistoryFile.Open(9)->FileOpen(\""+ mqlFileName +"\", FILE_WRITE) => "+ hFile +" [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR))));
   }


   /*HISTORY_HEADER*/int hh[]; InitializeByteBuffer(hh, HISTORY_HEADER.size);
   int      bars=0, from.offset=-1, to.offset=-1, fileSize=FileSize(hFile), periodSecs=timeframe * MINUTES;
   datetime from.openTime=0, from.closeTime=0, from.nextCloseTime=0, to.openTime=0, to.closeTime=0, to.nextCloseTime=0;


   // (2) ggf. neuen HISTORY_HEADER schreiben
   if (write_only || (read_write && fileSize < HISTORY_HEADER.size)) {
      // Parameter validieren
      if (!StringLen(copyright))     copyright = "";                                // NULL-Pointer => Leerstring
      if (StringLen(copyright) > 63) copyright = StringLeft(copyright, 63);         // ein zu langer String wird gek�rzt
      if (digits < 0)                          return(_NULL(catch("HistoryFile.Open(10)  invalid parameter digits = "+ digits +" [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ERR_INVALID_PARAMETER)));
      if (format!=400) /*&&*/ if (format!=401) return(_NULL(catch("HistoryFile.Open(11)  invalid parameter format = "+ format +" (must be 400 or 401) [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ERR_INVALID_PARAMETER)));

      hh_SetBarFormat(hh, format   );
      hh_SetCopyright(hh, copyright);
      hh_SetSymbol   (hh, symbol   );
      hh_SetPeriod   (hh, timeframe);
      hh_SetDigits   (hh, digits   );
      FileWriteArray(hFile, hh, 0, HISTORY_HEADER.intSize);
   }


   // (3.1) ggf. vorhandenen HISTORY_HEADER auslesen
   else if (read_only || fileSize > 0) {
      if (FileReadArray(hFile, hh, 0, HISTORY_HEADER.intSize) != HISTORY_HEADER.intSize) {
         FileClose(hFile);
         return(_NULL(catch("HistoryFile.Open(12)  invalid history file \""+ mqlFileName +"\" (size="+ fileSize +") [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR))));
      }

      // (3.2) ggf. Bar-Statistik auslesen
      if (fileSize > HISTORY_HEADER.size) {
         int barSize = ifInt(hh_BarFormat(hh)==400, HISTORY_BAR_400.size, HISTORY_BAR_401.size);
         bars        = (fileSize-HISTORY_HEADER.size) / barSize;
         if (bars > 0) {
            from.offset   = 0;
            from.openTime = FileReadInteger(hFile);
            to.offset     = bars-1; FileSeek(hFile, HISTORY_HEADER.size + to.offset*barSize, SEEK_SET);
            to.openTime   = FileReadInteger(hFile);

            if (timeframe <= PERIOD_W1) {
               from.closeTime     = from.openTime  + periodSecs;
               from.nextCloseTime = from.closeTime + periodSecs;
               to.closeTime       = to.openTime    + periodSecs;
               to.nextCloseTime   = to.closeTime   + periodSecs;
            }
            else if (timeframe == PERIOD_MN1) {
               from.closeTime     = DateTime(TimeYearFix(from.openTime), TimeMonth(from.openTime)+1);    // 00:00, 1. des n�chsten Monats
               from.nextCloseTime = DateTime(TimeYearFix(from.openTime), TimeMonth(from.openTime)+2);    // 00:00, 1. des �bern�chsten Monats
               to.closeTime       = DateTime(TimeYearFix(to.openTime  ), TimeMonth(to.openTime  )+1);    // 00:00, 1. des n�chsten Monats
               to.nextCloseTime   = DateTime(TimeYearFix(to.openTime  ), TimeMonth(to.openTime  )+2);    // 00:00, 1. des �bern�chsten Monats
            }
         }
      }
   }


   // (4) Daten zwischenspeichern
   if (hFile >= ArraySize(hf.hFile))                                 // neues Datei-Handle: Arrays vergr��er
      __ResizeFileArrays(hFile+1);                                   // andererseits von FileOpen() wiederverwendetes Handle

   hf.hFile                      [hFile]        = hFile;
   hf.name                       [hFile]        = baseName;
   hf.readAccess                 [hFile]        = !write_only;
   hf.writeAccess                [hFile]        = !read_only;

   ArraySetInts(hf.header,        hFile,          hh);               // entspricht: hf.header[hFile] = hh;
   hf.format                     [hFile]        = hh_BarFormat(hh);
   hf.barSize                    [hFile]        = ifInt(hf.format[hFile]==400, HISTORY_BAR_400.size, HISTORY_BAR_401.size);
   hf.symbol                     [hFile]        = hh_Symbol(hh);
   hf.symbolUpper                [hFile]        = symbolUpper;
   hf.period                     [hFile]        = timeframe;
   hf.periodSecs                 [hFile]        = periodSecs;
   hf.digits                     [hFile]        = hh_Digits(hh);
   hf.server                     [hFile]        = server;

   hf.stored.bars                [hFile]        = bars;                 // bei leerer History: 0
   hf.stored.from.offset         [hFile]        = from.offset;          // ...                -1
   hf.stored.from.openTime       [hFile]        = from.openTime;        // ...                 0
   hf.stored.from.closeTime      [hFile]        = from.closeTime;       // ...                 0
   hf.stored.from.nextCloseTime  [hFile]        = from.nextCloseTime;   // ...                 0
   hf.stored.to.offset           [hFile]        = to.offset;            // ...                -1
   hf.stored.to.openTime         [hFile]        = to.openTime;          // ...                 0
   hf.stored.to.closeTime        [hFile]        = to.closeTime;         // ...                 0
   hf.stored.to.nextCloseTime    [hFile]        = to.nextCloseTime;     // ...                 0

   hf.full.bars                  [hFile]        = hf.stored.bars              [hFile];
   hf.full.from.offset           [hFile]        = hf.stored.from.offset       [hFile];
   hf.full.from.openTime         [hFile]        = hf.stored.from.openTime     [hFile];
   hf.full.from.closeTime        [hFile]        = hf.stored.from.closeTime    [hFile];
   hf.full.from.nextCloseTime    [hFile]        = hf.stored.from.nextCloseTime[hFile];
   hf.full.to.offset             [hFile]        = hf.stored.to.offset         [hFile];
   hf.full.to.openTime           [hFile]        = hf.stored.to.openTime       [hFile];
   hf.full.to.closeTime          [hFile]        = hf.stored.to.closeTime      [hFile];
   hf.full.to.nextCloseTime      [hFile]        = hf.stored.to.nextCloseTime  [hFile];

   hf.lastStoredBar.offset       [hFile]        = -1;                   // vorhandene Bardaten zur�cksetzen: wichtig, da MQL die ID eines vorher geschlossenen Dateihandles
   hf.lastStoredBar.openTime     [hFile]        =  0;                   //                                   wiederverwenden kann
   hf.lastStoredBar.closeTime    [hFile]        =  0;
   hf.lastStoredBar.nextCloseTime[hFile]        =  0;
   hf.lastStoredBar.data         [hFile][BAR_T] =  0;
   hf.lastStoredBar.data         [hFile][BAR_O] =  0;
   hf.lastStoredBar.data         [hFile][BAR_H] =  0;
   hf.lastStoredBar.data         [hFile][BAR_L] =  0;
   hf.lastStoredBar.data         [hFile][BAR_C] =  0;
   hf.lastStoredBar.data         [hFile][BAR_V] =  0;

   hf.bufferedBar.offset         [hFile]        = -1;
   hf.bufferedBar.openTime       [hFile]        =  0;
   hf.bufferedBar.closeTime      [hFile]        =  0;
   hf.bufferedBar.nextCloseTime  [hFile]        =  0;
   hf.bufferedBar.data           [hFile][BAR_T] =  0;
   hf.bufferedBar.data           [hFile][BAR_O] =  0;
   hf.bufferedBar.data           [hFile][BAR_H] =  0;
   hf.bufferedBar.data           [hFile][BAR_L] =  0;
   hf.bufferedBar.data           [hFile][BAR_C] =  0;
   hf.bufferedBar.data           [hFile][BAR_V] =  0;
   hf.bufferedBar.modified       [hFile]        = false;

   ArrayResize(hh, 0);

   int error = GetLastError();
   if (!error)
      return(hFile);
   return(!catch("HistoryFile.Open(13)  [hstFile="+ DoubleQuoteStr(symbol +","+ PeriodDescription(timeframe)) +"]", error));
}


/**
 * Schlie�t die Historydatei mit dem angegebenen Handle. Ungespeicherte Daten im Schreibpuffer werden geschrieben.
 * Die Datei mu� vorher mit HistoryFile.Open() ge�ffnet worden sein.
 *
 * @param  _In_ int hFile - Dateihandle
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.Close(int hFile) {
   if (hFile <= 0)                      return(!catch("HistoryFile.Close(1)  invalid file handle "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.Close(2)  unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.Close(3)  unknown file handle "+ hFile +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   }
   else hf.hFile.lastValid = NULL;

   if (hf.hFile[hFile] < 0) return(true);                            // Handle wurde bereits geschlossen (kann ignoriert werden)


   // (1) alle ungespeicherten Daten speichern
   if (hf.bufferedBar.offset[hFile] != -1) if (!HistoryFile._WriteBufferedBar(hFile)) return(false);
   hf.bufferedBar.offset  [hFile] = -1;                              // BufferedBar sicherheitshalber zur�cksetzen
   hf.lastStoredBar.offset[hFile] = -1;                              // LastStoredBar sicherheitshalber zur�cksetzen


   // (2) Datei schlie�en
   int error = GetLastError();                                       // vor FileClose() alle Fehler abfangen
   if (IsError(error)) return(!catch("HistoryFile.Close(4)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));

   hf.hFile[hFile] = -1;                                             // Handle vorm Schlie�en zur�cksetzen
   FileClose(hFile);

   error = GetLastError();
   if (!error)                         return(true);
   if (error == ERR_INVALID_PARAMETER) return(true);                 // Datei wurde bereits geschlossen (kann ignoriert werden)
   return(!catch("HistoryFile.Close(5)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));
}


/**
 * Findet den Offset der Bar, die den angegebenen Zeitpunkt abdeckt oder abdecken w�rde, und signalisiert, ob diese Bar bereits existiert.
 * Die Bar existiert z.B. nicht, wenn die Zeitreihe am angegebenen Zeitpunkt eine L�cke aufweist (am zur�ckgegebenen Offset befindet sich eine
 * andere Bar) oder wenn der Zeitpunkt au�erhalb des von den vorhandenen Daten abgedeckten Bereichs liegt.
 *
 * @param  _In_  int      hFile          - Handle der Historydatei
 * @param  _In_  datetime time           - Zeitpunkt
 * @param  _Out_ bool     lpBarExists[1] - Variable, die nach R�ckkehr anzeigt, ob die Bar am zur�ckgegebenen Offset existiert
 *                                         (als Array implementiert, um Zeiger�bergabe an eine Library zu erm�glichen)
 *                                         � TRUE:  Bar existiert          @see  HistoryFile.UpdateBar() und HistoryFile.WriteBar()
 *                                         � FALSE: Bar existiert nicht    @see  HistoryFile.InsertBar()
 *
 * @return int - Bar-Offset relativ zum Dateiheader (Offset 0 ist die �lteste Bar) oder -1 (EMPTY), falls ein Fehler auftrat
 */
int HistoryFile.FindBar(int hFile, datetime time, bool &lpBarExists[]) {
   /**
    * NOTE: Der Parameter lpBarExists ist f�r den externen Gebrauch implementiert (Aufruf der Funktion von au�erhalb der Library). Beim internen Gebrauch
    *       l��t sich �ber die Metadaten der Historydatei einfacher herausfinden, ob eine Bar an einem Offset existiert oder nicht.
    *       @see  int hf.full.bars[]
    */
   if (hFile <= 0)                      return(_EMPTY(catch("HistoryFile.FindBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("HistoryFile.FindBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] == 0)         return(_EMPTY(catch("HistoryFile.FindBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <  0)         return(_EMPTY(catch("HistoryFile.FindBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER)));
      hf.hFile.lastValid = hFile;
   }
   if (time <= 0)                       return(_EMPTY(catch("HistoryFile.FindBar(5)  invalid parameter time = "+ time +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER)));
   if (ArraySize(lpBarExists) == 0)
      ArrayResize(lpBarExists, 1);


   // (1) History leer?
   if (!hf.full.bars[hFile]) {
      lpBarExists[0] = false;
      return(0);
   }

   datetime openTime = time;
   int      offset;


   // (3) alle bekannten Daten abpr�fen
   if (hf.stored.bars[hFile] > 0) {
      // (3.1) hf.stored.from
      if (openTime < hf.stored.from.openTime     [hFile]) { lpBarExists[0] = false;                     return(0); }    // Zeitpunkt liegt zeitlich vor der ersten Bar
      if (openTime < hf.stored.from.closeTime    [hFile]) { lpBarExists[0] = true;                      return(0); }    // Zeitpunkt liegt in der ersten Bar
      if (openTime < hf.stored.from.nextCloseTime[hFile]) { lpBarExists[0] = (hf.full.bars[hFile] > 1); return(1); }    // Zeitpunkt liegt in der zweiten Bar

      // (3.2) hf.stored.to
      if      (openTime < hf.stored.to.openTime     [hFile]) {}
      else if (openTime < hf.stored.to.closeTime    [hFile]) { lpBarExists[0] = true;                                          return(hf.stored.to.offset[hFile]); }    // Zeitpunkt liegt in der letzten gespeicherten Bar
      else if (openTime < hf.stored.to.nextCloseTime[hFile]) { lpBarExists[0] = (hf.full.bars[hFile] > hf.stored.bars[hFile]); return(hf.stored.bars     [hFile]); }    // Zeitpunkt liegt in der darauf folgenden Bar
      else                                                   { lpBarExists[0] = false;                                         return(hf.full.bars       [hFile]); }    // Zeitpunkt liegt in der ersten neuen Bar

      // (3.3) hf.lastStoredBar
      if (hf.lastStoredBar.offset[hFile] > 0) {                         // LastStoredBar ist definiert und entspricht nicht hf.stored.from (schon gepr�ft)
         if (hf.lastStoredBar.offset[hFile] != hf.stored.to.offset[hFile]) {
            if      (openTime < hf.lastStoredBar.openTime     [hFile]) {}
            else if (openTime < hf.lastStoredBar.closeTime    [hFile]) { lpBarExists[0] = true;                                 return(hf.lastStoredBar.offset[hFile]); }   // Zeitpunkt liegt in LastStoredBar
            else if (openTime < hf.lastStoredBar.nextCloseTime[hFile]) { offset         = hf.lastStoredBar.offset[hFile] + 1;
                                                                         lpBarExists[0] = (hf.full.to.offset[hFile] >= offset); return(offset); }                           // Zeitpunkt liegt in der darauf folgenden Bar
            else                                                       { offset = hf.lastStoredBar.offset[hFile] + 1 + (hf.full.to.offset[hFile] > hf.lastStoredBar.offset[hFile]);
                                                                         lpBarExists[0] = (hf.full.to.offset[hFile] >= offset); return(offset); }                           // Zeitpunkt liegt in der ersten neuen Bar
         }
      }
   }

   if (hf.bufferedBar.offset[hFile] >= 0) {                             // BufferedBar ist definiert
      // (3.4) hf.full.from
      if (hf.full.from.offset[hFile] != hf.stored.from.offset[hFile]) { // bei Gleichheit identisch zu hf.stored.from (schon gepr�ft)
         if (openTime < hf.full.from.openTime     [hFile]) { lpBarExists[0] = false;                     return(0); }                           // Zeitpunkt liegt zeitlich vor der ersten Bar
         if (openTime < hf.full.from.closeTime    [hFile]) { lpBarExists[0] = true;                      return(0); }                           // Zeitpunkt liegt in der ersten Bar
         if (openTime < hf.full.from.nextCloseTime[hFile]) { lpBarExists[0] = (hf.full.bars[hFile] > 1); return(1); }                           // Zeitpunkt liegt in der zweiten Bar
      }

      // (3.5) hf.full.to
      if (hf.full.to.offset[hFile] != hf.stored.to.offset[hFile]) {     // bei Gleichheit identisch zu hf.stored.to (schon gepr�ft)
         if      (openTime < hf.full.to.openTime [hFile]) {}
         else if (openTime < hf.full.to.closeTime[hFile]) { lpBarExists[0] = true;                       return(hf.full.to.offset[hFile]); }    // Zeitpunkt liegt in der letzten absoluten Bar
         else                                             { lpBarExists[0] = false;                      return(hf.full.bars     [hFile]); }    // Zeitpunkt liegt in der ersten neuen Bar
      }

      // (3.6) hf.bufferedBar                                           // eine definierte BufferedBar ist immer identisch zu hf.full.to (schon gepr�ft)
   }



   // (4) bin�re Suche in der Datei                            TODO: implementieren
   return(_EMPTY(catch("HistoryFile.FindBar(6)  bars="+ hf.full.bars[hFile] +", from='"+ TimeToStr(hf.full.from.openTime[hFile], TIME_FULL) +"', to='"+ TimeToStr(hf.full.to.openTime[hFile], TIME_FULL) +"')  Suche nach time='"+ TimeToStr(time, TIME_FULL) +"' innerhalb der Zeitreihe noch nicht implementiert [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_NOT_IMPLEMENTED)));
}


/**
 * Liest die Bar am angegebenen Offset einer Historydatei.
 *
 * @param  _In_  int    hFile  - Handle der Historydatei
 * @param  _In_  int    offset - Offset der zu lesenden Bar relativ zum Dateiheader (Offset 0 ist die �lteste Bar)
 * @param  _Out_ double bar[6] - Array zur Aufnahme der Bar-Daten (TOHLCV)
 *
 * @return bool - Erfolgsstatus
 *
 * NOTE: Time und Volume der gelesenen Bar werden validert, nicht jedoch die Barform.
 */
bool HistoryFile.ReadBar(int hFile, int offset, double &bar[]) {
   if (hFile <= 0)                      return(!catch("HistoryFile.ReadBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.ReadBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.ReadBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.ReadBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   if (offset < 0)                      return(!catch("HistoryFile.ReadBar(5)  invalid parameter offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (offset >= hf.full.bars[hFile])   return(!catch("HistoryFile.ReadBar(6)  invalid parameter offset = "+ offset +" ("+ hf.full.bars[hFile] +" full bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (ArraySize(bar) != 6) ArrayResize(bar, 6);


   // (1) vorzugsweise bereits bekannte Bars zur�ckgeben             // ACHTUNG: hf.lastStoredBar wird nur aktualisiert, wenn die Bar tats�chlich neu gelesen wurde.
   if (offset == hf.lastStoredBar.offset[hFile]) {                   //
      bar[BAR_T] = hf.lastStoredBar.data[hFile][BAR_T];
      bar[BAR_O] = hf.lastStoredBar.data[hFile][BAR_O];
      bar[BAR_H] = hf.lastStoredBar.data[hFile][BAR_H];
      bar[BAR_L] = hf.lastStoredBar.data[hFile][BAR_L];
      bar[BAR_C] = hf.lastStoredBar.data[hFile][BAR_C];
      bar[BAR_V] = hf.lastStoredBar.data[hFile][BAR_V];
      return(true);
   }
   if (offset == hf.bufferedBar.offset[hFile]) {
      bar[BAR_T] = hf.bufferedBar.data[hFile][BAR_T];
      bar[BAR_O] = hf.bufferedBar.data[hFile][BAR_O];
      bar[BAR_H] = hf.bufferedBar.data[hFile][BAR_H];
      bar[BAR_L] = hf.bufferedBar.data[hFile][BAR_L];
      bar[BAR_C] = hf.bufferedBar.data[hFile][BAR_C];
      bar[BAR_V] = hf.bufferedBar.data[hFile][BAR_V];
      return(true);
   }


   // (2) FilePointer positionieren, Bar lesen, normalisieren und validieren
   int position = HISTORY_HEADER.size + offset*hf.barSize[hFile], digits=hf.digits[hFile];
   if (!FileSeek(hFile, position, SEEK_SET)) return(!catch("HistoryFile.ReadBar(7)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]"));

   if (hf.format[hFile] == 400) {
      bar[BAR_T] =                 FileReadInteger(hFile);
      bar[BAR_O] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_L] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_H] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_C] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_V] =           Round(FileReadDouble (hFile));
   }
   else {               // 401
      bar[BAR_T] =                 FileReadInteger(hFile);           // int64
                                   FileReadInteger(hFile);
      bar[BAR_O] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_H] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_L] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_C] = NormalizeDouble(FileReadDouble (hFile), digits);
      bar[BAR_V] =                 FileReadInteger(hFile);           // uint64: ticks
   }
   datetime openTime = bar[BAR_T]; if (!openTime) return(!catch("HistoryFile.ReadBar(8)  invalid bar["+ offset +"].time = "+ openTime +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));
   int      V        = bar[BAR_V]; if (!V)        return(!catch("HistoryFile.ReadBar(9)  invalid bar["+ offset +"].volume = "+ V +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));


   // (4) CloseTime/NextCloseTime ermitteln und hf.lastStoredBar aktualisieren
   datetime closeTime, nextCloseTime;
   if (hf.period[hFile] <= PERIOD_W1) {
      closeTime     = openTime  + hf.periodSecs[hFile];
      nextCloseTime = closeTime + hf.periodSecs[hFile];
   }
   else if (hf.period[hFile] == PERIOD_MN1) {
      closeTime     = DateTime(TimeYearFix(openTime), TimeMonth(openTime)+1);    // 00:00, 1. des n�chsten Monats
      nextCloseTime = DateTime(TimeYearFix(openTime), TimeMonth(openTime)+2);    // 00:00, 1. des �bern�chsten Monats
   }

   hf.lastStoredBar.offset       [hFile]        = offset;
   hf.lastStoredBar.openTime     [hFile]        = openTime;
   hf.lastStoredBar.closeTime    [hFile]        = closeTime;
   hf.lastStoredBar.nextCloseTime[hFile]        = nextCloseTime;
   hf.lastStoredBar.data         [hFile][BAR_T] = bar[BAR_T];
   hf.lastStoredBar.data         [hFile][BAR_O] = bar[BAR_O];
   hf.lastStoredBar.data         [hFile][BAR_H] = bar[BAR_H];
   hf.lastStoredBar.data         [hFile][BAR_L] = bar[BAR_L];
   hf.lastStoredBar.data         [hFile][BAR_C] = bar[BAR_C];
   hf.lastStoredBar.data         [hFile][BAR_V] = bar[BAR_V];

   int error = GetLastError();
   if (!error)
      return(true);
   return(!catch("HistoryFile.ReadBar(10)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));
}


/**
 * Schreibt eine Bar am angegebenen Offset einer Historydatei. Eine dort vorhandene Bar wird �berschrieben. Ist die Bar noch nicht vorhanden,
 * mu� ihr Offset an die vorhandenen Bars genau anschlie�en. Sie darf kein physisches Gap verursachen.
 *
 * @param  _In_ int    hFile  - Handle der Historydatei
 * @param  _In_ int    offset - Offset der zu schreibenden Bar relativ zum Dateiheader (Offset 0 ist die �lteste Bar)
 * @param  _In_ double bar[]  - Bardaten (T-OHLCV):
 * @param  _In_ int    flags  - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                              � HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 * NOTE: Time und Volume der zu schreibenden Bar werden auf != NULL validert, alles andere nicht. Insbesondere wird nicht �berpr�ft,
 *       ob die Bar-Time eine normalisierte OpenTime f�r den Timeframe der Historydatei ist.
 */
bool HistoryFile.WriteBar(int hFile, int offset, double bar[], int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.WriteBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.WriteBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.WriteBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.WriteBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   if (offset < 0)                      return(!catch("HistoryFile.WriteBar(5)  invalid parameter offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (offset > hf.full.bars[hFile])    return(!catch("HistoryFile.WriteBar(6)  invalid parameter offset = "+ offset +" ("+ hf.full.bars[hFile] +" full bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (ArraySize(bar) != 6)             return(!catch("HistoryFile.WriteBar(7)  invalid size of parameter bar[] = "+ ArraySize(bar) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INCOMPATIBLE_ARRAYS));


   // (1) Bar validieren
   datetime openTime = Round(bar[BAR_T]); if (!openTime) return(!catch("HistoryFile.WriteBar(8)  invalid bar["+ offset +"].time = "+ openTime +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   int      V        = Round(bar[BAR_V]); if (!V)        return(!catch("HistoryFile.WriteBar(9)  invalid bar["+ offset +"].volume = "+ V +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));


   // (2) Sicherstellen, da� bekannte Bars nicht mit einer anderen Bar �berschrieben werden              // TODO: if-Tests reduzieren
   if (offset==hf.stored.from.offset  [hFile]) /*&&*/ if (openTime!=hf.stored.from.openTime  [hFile]) return(!catch("HistoryFile.WriteBar(10)  bar["+ offset +"].time="+ TimeToStr(openTime, TIME_FULL) +" collides with hf.stored.from.time="                                        + TimeToStr(hf.stored.from.openTime  [hFile], TIME_FULL) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_ILLEGAL_STATE));
   if (offset==hf.stored.to.offset    [hFile]) /*&&*/ if (openTime!=hf.stored.to.openTime    [hFile]) return(!catch("HistoryFile.WriteBar(11)  bar["+ offset +"].time="+ TimeToStr(openTime, TIME_FULL) +" collides with hf.stored.to.time="                                          + TimeToStr(hf.stored.to.openTime    [hFile], TIME_FULL) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_ILLEGAL_STATE));
   if (offset==hf.full.to.offset      [hFile]) /*&&*/ if (openTime!=hf.full.to.openTime      [hFile]) return(!catch("HistoryFile.WriteBar(12)  bar["+ offset +"].time="+ TimeToStr(openTime, TIME_FULL) +" collides with hf.full.to.time="                                            + TimeToStr(hf.full.to.openTime      [hFile], TIME_FULL) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_ILLEGAL_STATE));
   if (offset==hf.lastStoredBar.offset[hFile]) /*&&*/ if (openTime!=hf.lastStoredBar.openTime[hFile]) return(!catch("HistoryFile.WriteBar(13)  bar["+ offset +"].time="+ TimeToStr(openTime, TIME_FULL) +" collides with hf.lastStoredBar["+ hf.lastStoredBar.offset[hFile] +"].time="+ TimeToStr(hf.lastStoredBar.openTime[hFile], TIME_FULL) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_ILLEGAL_STATE));
   // hf.bufferedBar.offset: entspricht hf.full.to.offset (schon gepr�ft)


   // (3) TODO: Sicherstellen, da� nach bekannten Bars keine �lteren Bars geschrieben werden             // TODO: if-Tests reduzieren
   if (offset==hf.stored.from.offset  [hFile]+1) {}
   if (offset==hf.stored.to.offset    [hFile]+1) {}
   if (offset==hf.full.to.offset      [hFile]+1) {}
   if (offset==hf.lastStoredBar.offset[hFile]+1) {}


   // (4) L�st die Bar f�r eine BufferedBar ein BarClose-Event aus, zuerst die BufferedBar schreiben
   if (hf.bufferedBar.offset[hFile] >= 0) /*&&*/ if (offset > hf.bufferedBar.offset[hFile]) {
      if (!HistoryFile._WriteBufferedBar(hFile, flags)) return(false);
      hf.bufferedBar.offset[hFile] = -1;                                // BufferedBar zur�cksetzen
   }


   // (5) FilePointer positionieren, Bar normalisieren (Funktionsparameter nicht modifizieren) und schreiben
   int position = HISTORY_HEADER.size + offset*hf.barSize[hFile], digits=hf.digits[hFile];
   if (!FileSeek(hFile, position, SEEK_SET)) return(!catch("HistoryFile.WriteBar(14)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]"));

   double O = NormalizeDouble(bar[BAR_O], digits);
   double H = NormalizeDouble(bar[BAR_H], digits);
   double L = NormalizeDouble(bar[BAR_L], digits);
   double C = NormalizeDouble(bar[BAR_C], digits);

   if (hf.format[hFile] == 400) {
      FileWriteInteger(hFile, openTime);
      FileWriteDouble (hFile, O       );
      FileWriteDouble (hFile, L       );
      FileWriteDouble (hFile, H       );
      FileWriteDouble (hFile, C       );
      FileWriteDouble (hFile, V       );
   }
   else {               // 401
      FileWriteInteger(hFile, openTime);     // int64
      FileWriteInteger(hFile, 0       );
      FileWriteDouble (hFile, O       );
      FileWriteDouble (hFile, H       );
      FileWriteDouble (hFile, L       );
      FileWriteDouble (hFile, C       );
      FileWriteInteger(hFile, V       );     // uint64: ticks
      FileWriteInteger(hFile, 0       );
      FileWriteInteger(hFile, 0       );     // int:    spread
      FileWriteInteger(hFile, 0       );     // uint64: real_volume
      FileWriteInteger(hFile, 0       );
   }

   datetime closeTime=hf.lastStoredBar.closeTime[hFile], nextCloseTime=hf.lastStoredBar.nextCloseTime[hFile];


   // (6) hf.lastStoredBar aktualisieren
   if (offset != hf.lastStoredBar.offset[hFile]) {
      if (hf.period[hFile] <= PERIOD_W1) {
         closeTime     = openTime  + hf.periodSecs[hFile];
         nextCloseTime = closeTime + hf.periodSecs[hFile];
      }
      else if (hf.period[hFile] == PERIOD_MN1) {
         closeTime     = DateTime(TimeYearFix(openTime), TimeMonth(openTime)+1); // 00:00, 1. des n�chsten Monats
         nextCloseTime = DateTime(TimeYearFix(openTime), TimeMonth(openTime)+2); // 00:00, 1. des �bern�chsten Monats
      }
      hf.lastStoredBar.offset       [hFile] = offset;
      hf.lastStoredBar.openTime     [hFile] = openTime;
      hf.lastStoredBar.closeTime    [hFile] = closeTime;
      hf.lastStoredBar.nextCloseTime[hFile] = nextCloseTime;
   }
   hf.lastStoredBar.data[hFile][BAR_T] = openTime;
   hf.lastStoredBar.data[hFile][BAR_O] = O;
   hf.lastStoredBar.data[hFile][BAR_H] = H;
   hf.lastStoredBar.data[hFile][BAR_L] = L;
   hf.lastStoredBar.data[hFile][BAR_C] = C;
   hf.lastStoredBar.data[hFile][BAR_V] = V;


   // (7) Metadaten aktualisieren: � (7.1) Die Bar kann (a) erste Bar einer leeren History sein, (b) mittendrin liegen oder (c) neue Bar am Ende sein.
   //                              � (7.2) Die Bar kann auf einer ungespeicherten BufferedBar liegen, jedoch nicht j�nger als diese sein: siehe (3).
   //                              � (7.3) Die Bar kann zwischen der letzten gespeicherten Bar und einer ungespeicherten BufferedBar liegen. Dazu mu� sie
   //                                      mit HistoryFile.InsertBar() eingef�gt worden sein, das die entsprechende L�cke zwischen beiden Bars einrichtet.
   //                                      Ohne diese L�cke wurde in (2) abgebrochen [siehe oben].
   //
   // (7.1) Bar ist neue Bar: (a) erste Bar leerer History oder (c) neue Bar am Ende der gespeicherten Bars
   if (offset >= hf.stored.bars[hFile]) {
                         hf.stored.bars              [hFile] = offset + 1;

      if (offset == 0) { hf.stored.from.offset       [hFile] = 0;                hf.full.from.offset       [hFile] = hf.stored.from.offset       [hFile];
                         hf.stored.from.openTime     [hFile] = openTime;         hf.full.from.openTime     [hFile] = hf.stored.from.openTime     [hFile];
                         hf.stored.from.closeTime    [hFile] = closeTime;        hf.full.from.closeTime    [hFile] = hf.stored.from.closeTime    [hFile];
                         hf.stored.from.nextCloseTime[hFile] = nextCloseTime;    hf.full.from.nextCloseTime[hFile] = hf.stored.from.nextCloseTime[hFile]; }
                                                                                 //                ^               ^               ^
                         hf.stored.to.offset         [hFile] = offset;           // Wird die Bar wie in (6.3) eingef�gt, wurde der Offset der BufferedBar um eins
                         hf.stored.to.openTime       [hFile] = openTime;         // vergr��ert. Ist die History noch leer und die BufferedBar war die erste Bar, steht
                         hf.stored.to.closeTime      [hFile] = closeTime;        // hf.full.from bis zu dieser Zuweisung *�ber mir* auf 0 (Zeiten unbekannt, da die
                         hf.stored.to.nextCloseTime  [hFile] = nextCloseTime;    // neue Startbar gerade eingef�gt wird).
   }
   if (hf.stored.bars[hFile] > hf.full.bars[hFile]) {
      hf.full.bars            [hFile] = hf.stored.bars            [hFile];

      hf.full.to.offset       [hFile] = hf.stored.to.offset       [hFile];
      hf.full.to.openTime     [hFile] = hf.stored.to.openTime     [hFile];
      hf.full.to.closeTime    [hFile] = hf.stored.to.closeTime    [hFile];
      hf.full.to.nextCloseTime[hFile] = hf.stored.to.nextCloseTime[hFile];
   }


   // (8) Ist die geschriebene Bar gleichzeitig die BufferedBar, wird deren ver�nderlicher Status aktualisiert.
   if (offset == hf.bufferedBar.offset[hFile]) {
      hf.bufferedBar.data    [hFile][BAR_O] = hf.lastStoredBar.data[hFile][BAR_O];
      hf.bufferedBar.data    [hFile][BAR_H] = hf.lastStoredBar.data[hFile][BAR_H];
      hf.bufferedBar.data    [hFile][BAR_L] = hf.lastStoredBar.data[hFile][BAR_L];
      hf.bufferedBar.data    [hFile][BAR_C] = hf.lastStoredBar.data[hFile][BAR_C];
      hf.bufferedBar.data    [hFile][BAR_V] = hf.lastStoredBar.data[hFile][BAR_V];
      hf.bufferedBar.modified[hFile]        = false;                          // Bar wurde gerade gespeichert
   }

   int error = GetLastError();
   if (!error)
      return(true);
   return(!catch("HistoryFile.WriteBar(15)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));
}


/**
 * Aktualisiert den Schlu�kurs der Bar am angegebenen Offset einer Historydatei. Die Bar mu� existieren, entweder in der Datei (gespeichert)
 * oder im Barbuffer (ungespeichert).
 *
 * @param  _In_ int    hFile  - Handle der Historydatei
 * @param  _In_ int    offset - Offset der zu aktualisierenden Bar relativ zum Dateiheader (Offset 0 ist die �lteste Bar)
 * @param  _In_ double value  - neuer Schlu�kurs (z.B. ein weiterer Tick der j�ngsten Bar)
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.UpdateBar(int hFile, int offset, double value) {
   if (hFile <= 0)                      return(!catch("HistoryFile.UpdateBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.UpdateBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.UpdateBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.UpdateBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   if (offset < 0 )                     return(!catch("HistoryFile.UpdateBar(5)  invalid parameter offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (offset >= hf.full.bars[hFile])   return(!catch("HistoryFile.UpdateBar(6)  invalid parameter offset = "+ offset +" ("+ hf.full.bars[hFile] +" full bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));


   // (1) vorzugsweise bekannte Bars aktualisieren
   if (offset == hf.bufferedBar.offset[hFile]) {                                 // BufferedBar
      //.bufferedBar.data[hFile][BAR_T] = ...                                    // unver�ndert
      //.bufferedBar.data[hFile][BAR_O] = ...                                    // unver�ndert
      hf.bufferedBar.data[hFile][BAR_H] = MathMax(hf.bufferedBar.data[hFile][BAR_H], value);
      hf.bufferedBar.data[hFile][BAR_L] = MathMin(hf.bufferedBar.data[hFile][BAR_L], value);
      hf.bufferedBar.data[hFile][BAR_C] = value;
      hf.bufferedBar.data[hFile][BAR_V]++;
      return(HistoryFile._WriteBufferedBar(hFile));
   }


   // (2) ist die zu aktualisierende Bar nicht die LastStoredBar, gesuchte Bar einlesen und damit zur LastStoredBar machen
   if (offset != hf.lastStoredBar.offset[hFile]) {
      double bar[6];                                                             // bar[] wird in Folge nicht verwendet
      if (!HistoryFile.ReadBar(hFile, offset, bar)) return(false);               // setzt LastStoredBar auf die gelesene Bar
   }


   // (3) LastStoredBar aktualisieren und speichern
   //.lastStoredBar.data[hFile][BAR_T] = ...                                     // unver�ndert
   //.lastStoredBar.data[hFile][BAR_O] = ...                                     // unver�ndert
   hf.lastStoredBar.data[hFile][BAR_H] = MathMax(hf.lastStoredBar.data[hFile][BAR_H], value);
   hf.lastStoredBar.data[hFile][BAR_L] = MathMin(hf.lastStoredBar.data[hFile][BAR_L], value);
   hf.lastStoredBar.data[hFile][BAR_C] = value;
   hf.lastStoredBar.data[hFile][BAR_V]++;
   return(HistoryFile._WriteLastStoredBar(hFile));
}


/**
 * F�gt eine Bar am angegebenen Offset einer Historydatei ein. Eine dort vorhandene Bar wird nicht �berschrieben, stattdessen werden die vorhandene und alle
 * folgenden Bars um eine Position nach vorn verschoben. Ist die einzuf�gende Bar die j�ngste Bar, mu� ihr Offset an die vorhandenen Bars genau anschlie�en.
 * Sie darf kein physisches Gap verursachen.
 *
 * @param  _In_ int    hFile  - Handle der Historydatei
 * @param  _In_ int    offset - Offset der einzuf�genden Bar relativ zum Dateiheader (Offset 0 ist die �lteste Bar)
 * @param  _In_ double bar[6] - Bardaten (T-OHLCV)
 * @param  _In_ int    flags  - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                              � HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 * NOTE: Time und Volume der einzuf�genden Bar werden auf != NULL validert, alles andere nicht. Insbesondere wird nicht �berpr�ft,
 *       ob die Bar-Time eine normalisierte OpenTime f�r den Timeframe der Historydatei ist.
 */
bool HistoryFile.InsertBar(int hFile, int offset, double bar[], int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.InsertBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.InsertBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.InsertBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.InsertBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   if (offset < 0)                      return(!catch("HistoryFile.InsertBar(5)  invalid parameter offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (offset > hf.full.bars[hFile])    return(!catch("HistoryFile.InsertBar(6)  invalid parameter offset = "+ offset +" ("+ hf.full.bars[hFile] +" full bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (ArraySize(bar) != 6)             return(!catch("HistoryFile.InsertBar(7)  invalid size of parameter data[] = "+ ArraySize(bar) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INCOMPATIBLE_ARRAYS));


   // (1) ggf. L�cke f�r einzuf�gende Bar schaffen
   if (offset < hf.full.bars[hFile])
      if (!HistoryFile.MoveBars(hFile, offset, offset+1)) return(false);

   // (2) Bar schreiben, HistoryFile.WriteBar() f�hrt u.a. folgende Tasks aus: � validiert die Bar
   //                                                                          � speichert eine durch die einzuf�gende Bar geschlossene BufferedBar
   //                                                                          � aktualisiert die Metadaten der Historydatei
   return(HistoryFile.WriteBar(hFile, offset, bar, flags));
}


/**
 * Schreibt die LastStoredBar in die Historydatei. Die Bar existiert in der Historydatei bereits.
 *
 * @param  _In_ int hFile - Handle der Historydatei
 * @param  _In_ int flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                          � HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 * @access private
 */
bool HistoryFile._WriteLastStoredBar(int hFile, int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile._WriteLastStoredBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile._WriteLastStoredBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile._WriteLastStoredBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile._WriteLastStoredBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   int offset = hf.lastStoredBar.offset[hFile];
   if (offset < 0)                      return(_true(warn("HistoryFile._WriteLastStoredBar(5)  undefined lastStoredBar: hf.lastStoredBar.offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]")));
   if (offset >= hf.stored.bars[hFile]) return(!catch("HistoryFile._WriteLastStoredBar(6)  invalid hf.lastStoredBar.offset = "+ offset +" ("+ hf.stored.bars[hFile] +" stored bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));


   // (1) Bar validieren
   datetime openTime = hf.lastStoredBar.openTime[hFile];         if (!openTime) return(!catch("HistoryFile._WriteLastStoredBar(8)  invalid hf.lastStoredBar["+ offset +"].time = "+ openTime +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));
   int      V  = Round(hf.lastStoredBar.data    [hFile][BAR_V]); if (!V)        return(!catch("HistoryFile._WriteLastStoredBar(9)  invalid hf.lastStoredBar["+ offset +"].volume = "+ V +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));


   // (2) FilePointer positionieren, Daten normalisieren und schreiben
   int position = HISTORY_HEADER.size + offset*hf.barSize[hFile], digits=hf.digits[hFile];
   if (!FileSeek(hFile, position, SEEK_SET)) return(!catch("HistoryFile._WriteLastStoredBar(7)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]"));

   if (hf.format[hFile] == 400) {
      FileWriteInteger(hFile, openTime);
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_O], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_L], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_H], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_C], digits));
      FileWriteDouble (hFile, V);
   }
   else {               // 401
      FileWriteInteger(hFile, openTime);                                                     // int64
      FileWriteInteger(hFile, 0);
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_O], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_H], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_L], digits));
      FileWriteDouble (hFile, NormalizeDouble(hf.lastStoredBar.data[hFile][BAR_C], digits));
      FileWriteInteger(hFile, V);                                                            // uint64: ticks
      FileWriteInteger(hFile, 0);
      FileWriteInteger(hFile, 0);                                                            // int:    spread
      FileWriteInteger(hFile, 0);                                                            // uint64: volume
      FileWriteInteger(hFile, 0);
   }


   // (3) Die Bar existierte bereits in der History, die Metadaten �ndern sich nicht.


   // (7) Ist die LastStoredBar gleichzeitig die BufferedBar, wird deren ver�nderlicher Status auch aktualisiert.
   if (offset == hf.bufferedBar.offset[hFile])
      hf.bufferedBar.modified[hFile] = false;               // Bar wurde gerade gespeichert

   int error = GetLastError();
   if (!error)
      return(true);
   return(!catch("HistoryFile._WriteLastStoredBar(8)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));
}


/**
 * Schreibt den Inhalt der BufferedBar in die Historydatei. Sie ist immer die j�ngste Bar und kann in der History bereits existieren, mu� es aber nicht.
 *
 * @param  _In_ int hFile - Handle der Historydatei
 * @param  _In_ int flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                          � HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 * @access private
 */
bool HistoryFile._WriteBufferedBar(int hFile, int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile._WriteBufferedBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile._WriteBufferedBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile._WriteBufferedBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile._WriteBufferedBar(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   int offset = hf.bufferedBar.offset[hFile];
   if (offset < 0)                      return(_true(warn("HistoryFile._WriteBufferedBar(5)  undefined bufferedBar: hf.bufferedBar.offset = "+ offset +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]")));
   if (offset != hf.full.bars[hFile]-1) return(!catch("HistoryFile._WriteBufferedBar(6)  invalid hf.bufferedBar.offset = "+ offset +" ("+ hf.full.bars[hFile] +" full bars) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));


   // Die Bar wird nur dann geschrieben, wenn sie sich seit dem letzten Schreiben ge�ndert hat.
   if (hf.bufferedBar.modified[hFile]) {
      // (1) Bar validieren
      datetime openTime = hf.bufferedBar.openTime[hFile];         if (!openTime) return(!catch("HistoryFile._WriteBufferedBar(7)  invalid hf.lastStoredBar["+ offset +"].time = "+ openTime +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));
      int      V  = Round(hf.bufferedBar.data    [hFile][BAR_V]); if (!V)        return(!catch("HistoryFile._WriteBufferedBar(8)  invalid hf.lastStoredBar["+ offset +"].volume = "+ V +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_RUNTIME_ERROR));


      // (2) FilePointer positionieren, Daten normalisieren und schreiben
      int position = HISTORY_HEADER.size + offset*hf.barSize[hFile], digits=hf.digits[hFile];
      if (!FileSeek(hFile, position, SEEK_SET)) return(!catch("HistoryFile._WriteBufferedBar(9)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]"));

      hf.bufferedBar.data[hFile][BAR_O] = NormalizeDouble(hf.bufferedBar.data[hFile][BAR_O], digits);
      hf.bufferedBar.data[hFile][BAR_H] = NormalizeDouble(hf.bufferedBar.data[hFile][BAR_H], digits);
      hf.bufferedBar.data[hFile][BAR_L] = NormalizeDouble(hf.bufferedBar.data[hFile][BAR_L], digits);
      hf.bufferedBar.data[hFile][BAR_C] = NormalizeDouble(hf.bufferedBar.data[hFile][BAR_C], digits);
      hf.bufferedBar.data[hFile][BAR_V] = V;

      if (hf.format[hFile] == 400) {
         FileWriteInteger(hFile, openTime);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_O]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_L]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_H]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_C]);
         FileWriteDouble (hFile, V);
      }
      else {               // 401
         FileWriteInteger(hFile, openTime);                             // int64
         FileWriteInteger(hFile, 0);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_O]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_H]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_L]);
         FileWriteDouble (hFile, hf.bufferedBar.data[hFile][BAR_C]);
         FileWriteInteger(hFile, V);                                    // uint64: ticks
         FileWriteInteger(hFile, 0);
         FileWriteInteger(hFile, 0);                                    // int:    spread
         FileWriteInteger(hFile, 0);                                    // uint64: volume
         FileWriteInteger(hFile, 0);
      }
      hf.bufferedBar.modified[hFile] = false;


      // (3) Das Schreiben macht die BufferedBar zus�tzlich zur LastStoredBar.
      hf.lastStoredBar.offset       [hFile]        = hf.bufferedBar.offset       [hFile];
      hf.lastStoredBar.openTime     [hFile]        = hf.bufferedBar.openTime     [hFile];
      hf.lastStoredBar.closeTime    [hFile]        = hf.bufferedBar.closeTime    [hFile];
      hf.lastStoredBar.nextCloseTime[hFile]        = hf.bufferedBar.nextCloseTime[hFile];
      hf.lastStoredBar.data         [hFile][BAR_T] = hf.bufferedBar.data         [hFile][BAR_T];
      hf.lastStoredBar.data         [hFile][BAR_O] = hf.bufferedBar.data         [hFile][BAR_O];
      hf.lastStoredBar.data         [hFile][BAR_H] = hf.bufferedBar.data         [hFile][BAR_H];
      hf.lastStoredBar.data         [hFile][BAR_L] = hf.bufferedBar.data         [hFile][BAR_L];
      hf.lastStoredBar.data         [hFile][BAR_C] = hf.bufferedBar.data         [hFile][BAR_C];
      hf.lastStoredBar.data         [hFile][BAR_V] = hf.bufferedBar.data         [hFile][BAR_V];


      // (4) Metadaten aktualisieren: � Die Bar kann (a) erste Bar einer leeren History sein, (b) existierende j�ngste Bar oder (c) neue j�ngste Bar sein.
      //                              � Die Bar ist immer die j�ngste (letzte) Bar.
      //                              � Die Metadaten von hf.full.* �ndern sich nicht.
      //                              � Nach dem Speichern stimmen hf.stored.* und hf.full.* �berein.
      hf.stored.bars              [hFile] = hf.full.bars              [hFile];

      hf.stored.from.offset       [hFile] = hf.full.from.offset       [hFile];
      hf.stored.from.openTime     [hFile] = hf.full.from.openTime     [hFile];
      hf.stored.from.closeTime    [hFile] = hf.full.from.closeTime    [hFile];
      hf.stored.from.nextCloseTime[hFile] = hf.full.from.nextCloseTime[hFile];

      hf.stored.to.offset         [hFile] = hf.full.to.offset         [hFile];
      hf.stored.to.openTime       [hFile] = hf.full.to.openTime       [hFile];
      hf.stored.to.closeTime      [hFile] = hf.full.to.closeTime      [hFile];
      hf.stored.to.nextCloseTime  [hFile] = hf.full.to.nextCloseTime  [hFile];
   }

   int error = GetLastError();
   if (!error)
      return(true);
   return(!catch("HistoryFile._WriteBufferedBar(10)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", error));
}


/**
 * Verschiebt alle Bars beginnend vom angegebenen from-Offset bis zum Ende der Historydatei an den angegebenen Ziel-Offset.
 *
 * @param  _In_ int hFile      - Handle der Historydatei
 * @param  _In_ int fromOffset - Start-Offset
 * @param  _In_ int destOffset - Ziel-Offset: Ist dieser Wert kleiner als der Start-Offset, wird die Historydatei entsprechend gek�rzt.
 *
 * @return bool - Erfolgsstatus                                            TODO: Implementieren
 */
bool HistoryFile.MoveBars(int hFile, int fromOffset, int destOffset) {
   return(!catch("HistoryFile.MoveBars(1)  [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_NOT_IMPLEMENTED));
}


/**
 * F�gt einer Historydatei einen weiteren Tick hinzu. Der Tick mu� zur j�ngsten Bar der Datei geh�ren und wird als Close-Preis gespeichert.
 *
 * @param  _In_ int      hFile - Handle der Historydatei
 * @param  _In_ datetime time  - Zeitpunkt des Ticks
 * @param  _In_ double   value - Datenwert
 * @param  _In_ int      flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                               � HST_BUFFER_TICKS: puffert aufeinanderfolgende Ticks und schreibt die Daten erst beim jeweils n�chsten BarOpen-Event
 *                               � HST_FILL_GAPS:    f�llt entstehende Gaps mit dem letzten Schlu�kurs vor dem Gap
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.AddTick(int hFile, datetime time, double value, int flags=NULL) {
   if (hFile <= 0)                        return(!catch("HistoryFile.AddTick(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.lastValid) {
      if (hFile >= ArraySize(hf.hFile))   return(!catch("HistoryFile.AddTick(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)           return(!catch("HistoryFile.AddTick(3)  invalid parameter hFile = "+ hFile +" (unknown handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)           return(!catch("HistoryFile.AddTick(4)  invalid parameter hFile = "+ hFile +" (closed handle) [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
      hf.hFile.lastValid = hFile;
   }
   if (time <= 0)                         return(!catch("HistoryFile.AddTick(5)  invalid parameter time = "+ time +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));
   if (time < hf.full.to.openTime[hFile]) return(!catch("HistoryFile.AddTick(6)  cannot add tick to a closed bar: tickTime="+ TimeToStr(time, TIME_FULL) +", last bar.time="+ TimeToStr(hf.full.to.openTime[hFile], TIME_FULL) +" [hstFile="+ DoubleQuoteStr(hf.symbol[hFile] +","+ PeriodDescription(hf.period[hFile])) +"]", ERR_INVALID_PARAMETER));

   double bar[6];
   bool   barExists[1];


   // (1) Offset und OpenTime der Tick-Bar bestimmen
   datetime tick.time=time, tick.openTime;
   int      tick.offset      = -1;                                                     // Offset der Bar, zu der der Tick geh�rt
   double   tick.value       = NormalizeDouble(value, hf.digits[hFile]);
   bool     bufferedBarClose = false;                                                  // ob der Tick f�r die BufferedBar ein BarClose-Event ausl�st

   // (1.1) Vorzugsweise (h�ufigster Fall) BufferedBar benutzen (bevor diese ggf. durch ein BarClose-Event geschlossen wird).
   if (hf.bufferedBar.offset[hFile] >= 0) {                                            // BufferedBar ist definiert (und ist immer j�ngste Bar)
      if (tick.time < hf.bufferedBar.closeTime[hFile]) {
         tick.offset   = hf.bufferedBar.offset  [hFile];                               // Tick liegt in BufferedBar
         tick.openTime = hf.bufferedBar.openTime[hFile];
      }
      else {
         if (tick.time < hf.bufferedBar.nextCloseTime[hFile]) {
            tick.offset   = hf.bufferedBar.offset   [hFile] + 1;                       // Tick liegt in der BufferedBar folgenden Bar
            tick.openTime = hf.bufferedBar.closeTime[hFile];
         }
         bufferedBarClose = true;                                                      // und l�st f�r die BufferedBar ein BarClose-Event aus
      }
   }
   // (1.2) Danach LastStoredBar benutzen (bevor diese ggf. von HistoryFile._WriteBufferedBar() �berschrieben wird).
   if (tick.offset==-1) /*&&*/ if (hf.lastStoredBar.offset[hFile] >= 0) {              // LastStoredBar ist definiert
      if (time >= hf.lastStoredBar.openTime[hFile]) {
         if (tick.time < hf.lastStoredBar.closeTime[hFile]) {
            tick.offset   = hf.lastStoredBar.offset  [hFile];                          // Tick liegt in LastStoredBar
            tick.openTime = hf.lastStoredBar.openTime[hFile];
         }
         else if (tick.time < hf.lastStoredBar.nextCloseTime[hFile]) {
            tick.offset   = hf.lastStoredBar.offset   [hFile] + 1;                     // Tick liegt in der LastStoredBar folgenden Bar
            tick.openTime = hf.lastStoredBar.closeTime[hFile];
         }
      }
   }
   // (1.3) eine geschlossene BufferedBar schreiben
   if (bufferedBarClose) {
      if (!HistoryFile._WriteBufferedBar(hFile, flags)) return(false);
      hf.bufferedBar.offset[hFile] = -1;                                               // BufferedBar zur�cksetzen
   }


   // (2) HST_BUFFER_TICKS=true:  Tick buffern
   if (HST_BUFFER_TICKS & flags && 1) {
      // (2.1) ist BufferedBar leer, Tickbar laden oder neue Bar beginnen und zur BufferedBar machen
      if (hf.bufferedBar.offset[hFile] < 0) {                                          // BufferedBar ist leer
         if (tick.offset == -1) {
            if      (hf.period[hFile] <= PERIOD_D1 ) tick.openTime = tick.time - tick.time%hf.periodSecs[hFile];
            else if (hf.period[hFile] == PERIOD_W1 ) tick.openTime = tick.time - tick.time%DAYS - (TimeDayOfWeekFix(tick.time)+6)%7*DAYS;       // 00:00, Montag
            else if (hf.period[hFile] == PERIOD_MN1) tick.openTime = tick.time - tick.time%DAYS - (TimeDayFix(tick.time)-1)*DAYS;               // 00:00, 1. des Monats
            tick.offset = HistoryFile.FindBar(hFile, tick.openTime, barExists); if (tick.offset < 0) return(false);
         }
         if (tick.offset < hf.full.bars[hFile]) {                                      // Tickbar existiert, laden
            if (!HistoryFile.ReadBar(hFile, tick.offset, bar)) return(false);          // ReadBar() setzt LastStoredBar auf die Tickbar
            hf.bufferedBar.offset       [hFile]        = hf.lastStoredBar.offset       [hFile];
            hf.bufferedBar.openTime     [hFile]        = hf.lastStoredBar.openTime     [hFile];
            hf.bufferedBar.closeTime    [hFile]        = hf.lastStoredBar.closeTime    [hFile];
            hf.bufferedBar.nextCloseTime[hFile]        = hf.lastStoredBar.nextCloseTime[hFile];
            hf.bufferedBar.data         [hFile][BAR_T] = hf.lastStoredBar.data         [hFile][BAR_T];
            hf.bufferedBar.data         [hFile][BAR_O] = hf.lastStoredBar.data         [hFile][BAR_O];
            hf.bufferedBar.data         [hFile][BAR_H] = hf.lastStoredBar.data         [hFile][BAR_H];
            hf.bufferedBar.data         [hFile][BAR_L] = hf.lastStoredBar.data         [hFile][BAR_L];
            hf.bufferedBar.data         [hFile][BAR_C] = hf.lastStoredBar.data         [hFile][BAR_C];
            hf.bufferedBar.data         [hFile][BAR_V] = hf.lastStoredBar.data         [hFile][BAR_V];
            hf.bufferedBar.modified     [hFile]        = false;
         }
         else {                                                                        // Tickbar existiert nicht, neue BufferedBar initialisieren
            datetime closeTime, nextCloseTime;
            if (hf.period[hFile] <= PERIOD_W1) {
               closeTime     = tick.openTime + hf.periodSecs[hFile];
               nextCloseTime = closeTime     + hf.periodSecs[hFile];
            }
            else if (hf.period[hFile] == PERIOD_MN1) {
               closeTime     = DateTime(TimeYearFix(tick.openTime), TimeMonth(tick.openTime)+1);   // 00:00, 1. des n�chsten Monats
               nextCloseTime = DateTime(TimeYearFix(tick.openTime), TimeMonth(tick.openTime)+2);   // 00:00, 1. des �bern�chsten Monats
            }
            hf.bufferedBar.offset       [hFile]        = tick.offset;
            hf.bufferedBar.openTime     [hFile]        = tick.openTime;
            hf.bufferedBar.closeTime    [hFile]        = closeTime;
            hf.bufferedBar.nextCloseTime[hFile]        = nextCloseTime;
            hf.bufferedBar.data         [hFile][BAR_T] = tick.openTime;
            hf.bufferedBar.data         [hFile][BAR_O] = tick.value;
            hf.bufferedBar.data         [hFile][BAR_H] = tick.value;
            hf.bufferedBar.data         [hFile][BAR_L] = tick.value;
            hf.bufferedBar.data         [hFile][BAR_C] = tick.value;
            hf.bufferedBar.data         [hFile][BAR_V] = 0;                            // das Volume wird erst in Schritt (2.2) auf 1 gesetzt
            hf.bufferedBar.modified     [hFile]        = true;

            // Metadaten aktualisieren: � Die Bar kann (a) erste Bar einer leeren History oder (b) neue Bar am Ende sein.
            //                          � Die Bar ist immer die j�ngste (letzte) Bar.
            //                          � Die Bar existiert in der Historydatei nicht, die Metadaten von hf.stored.* �ndern sich daher nicht.
                                    hf.full.bars              [hFile] = tick.offset + 1;

            if (tick.offset == 0) { hf.full.from.offset       [hFile] = tick.offset;
                                    hf.full.from.openTime     [hFile] = tick.openTime;
                                    hf.full.from.closeTime    [hFile] = closeTime;
                                    hf.full.from.nextCloseTime[hFile] = nextCloseTime; }

                                    hf.full.to.offset         [hFile] = tick.offset;
                                    hf.full.to.openTime       [hFile] = tick.openTime;
                                    hf.full.to.closeTime      [hFile] = closeTime;
                                    hf.full.to.nextCloseTime  [hFile] = nextCloseTime;
         }
      }

      // (2.2) BufferedBar aktualisieren
      //.bufferedBar.data    [hFile][BAR_T] = ...                                      // unver�ndert
      //.bufferedBar.data    [hFile][BAR_O] = ...                                      // unver�ndert
      hf.bufferedBar.data    [hFile][BAR_H] = MathMax(hf.bufferedBar.data[hFile][BAR_H], tick.value);
      hf.bufferedBar.data    [hFile][BAR_L] = MathMin(hf.bufferedBar.data[hFile][BAR_L], tick.value);
      hf.bufferedBar.data    [hFile][BAR_C] = tick.value;
      hf.bufferedBar.data    [hFile][BAR_V]++;
      hf.bufferedBar.modified[hFile]        = true;

      return(true);
   }// end if HST_BUFFER_TICKS=true


   // (3)   HST_BUFFER_TICKS=false:  Tick schreiben
   // (3.1) ist BufferedBar definiert (HST_BUFFER_TICKS war beim letzten Tick ON und ist jetzt OFF), BufferedBar mit Tick aktualisieren, schreiben und zur�cksetzen
   if (hf.bufferedBar.offset[hFile] >= 0) {                                            // BufferedBar ist definiert, der Tick mu� dazu geh�ren
      //.bufferedBar.data[hFile][BAR_T] = ...                                          // unver�ndert
      //.bufferedBar.data[hFile][BAR_O] = ...                                          // unver�ndert
      hf.bufferedBar.data[hFile][BAR_H] = MathMax(hf.bufferedBar.data[hFile][BAR_H], tick.value);
      hf.bufferedBar.data[hFile][BAR_L] = MathMin(hf.bufferedBar.data[hFile][BAR_L], tick.value);
      hf.bufferedBar.data[hFile][BAR_C] = tick.value;
      hf.bufferedBar.data[hFile][BAR_V]++;
      if (!HistoryFile._WriteBufferedBar(hFile, flags)) return(false);
      hf.bufferedBar.offset[hFile] = -1;                                               // BufferedBar zur�cksetzen
      return(true);
   }

   // (3.2) BufferedBar ist leer: Tickbar mit Tick aktualisieren oder neue Bar mit Tick zu History hinzuf�gen
   if (tick.offset == -1) {
      if      (hf.period[hFile] <= PERIOD_D1 ) tick.openTime = tick.time - tick.time%hf.periodSecs[hFile];
      else if (hf.period[hFile] == PERIOD_W1 ) tick.openTime = tick.time - tick.time%DAYS - (TimeDayOfWeekFix(tick.time)+6)%7*DAYS;       // 00:00, Montag
      else if (hf.period[hFile] == PERIOD_MN1) tick.openTime = tick.time - tick.time%DAYS - (TimeDayFix(tick.time)-1)*DAYS;               // 00:00, 1. des Monats
      tick.offset = HistoryFile.FindBar(hFile, tick.openTime, barExists); if (tick.offset < 0) return(false);
   }
   if (tick.offset < hf.full.bars[hFile]) {
      if (!HistoryFile.UpdateBar(hFile, tick.offset, tick.value)) return(false);       // existierende Bar aktualisieren
   }
   else {
      bar[BAR_T] = tick.openTime;                                                      // oder neue Bar einf�gen
      bar[BAR_O] = tick.value;
      bar[BAR_H] = tick.value;
      bar[BAR_L] = tick.value;
      bar[BAR_C] = tick.value;
      bar[BAR_V] = 1;
      if (!HistoryFile.InsertBar(hFile, tick.offset, bar, flags|HST_TIME_IS_OPENTIME)) return(false);
   }

   return(true);
}


/**
 * Setzt die Gr��e der internen HistorySet-Datenarrays auf den angegebenen Wert.
 *
 * @param  int size - neue Gr��e
 *
 * @return int - neue Gr��e der Arrays
 *
 * @access private
 */
int __ResizeSetArrays(int size) {
   if (size != ArraySize(hs.hSet)) {
      ArrayResize(hs.hSet,        size);
      ArrayResize(hs.symbol,      size);
      ArrayResize(hs.symbolUpper, size);
      ArrayResize(hs.copyright,   size);
      ArrayResize(hs.digits,      size);
      ArrayResize(hs.server,      size);
      ArrayResize(hs.hFile,       size);
      ArrayResize(hs.format,      size);
   }
   return(size);
}


/**
 * Setzt die Gr��e der internen HistoryFile-Datenarrays auf den angegebenen Wert.
 *
 * @param  int size - neue Gr��e
 *
 * @return int - neue Gr��e der Arrays
 *
 * @access private
 */
int __ResizeFileArrays(int size) {
   int oldSize = ArraySize(hf.hFile);

   if (size != oldSize) {
      ArrayResize(hf.hFile,                       size);
      ArrayResize(hf.name,                        size);
      ArrayResize(hf.readAccess,                  size);
      ArrayResize(hf.writeAccess,                 size);

      ArrayResize(hf.header,                      size);
      ArrayResize(hf.format,                      size);
      ArrayResize(hf.barSize,                     size);
      ArrayResize(hf.symbol,                      size);
      ArrayResize(hf.symbolUpper,                 size);
      ArrayResize(hf.period,                      size);
      ArrayResize(hf.periodSecs,                  size);
      ArrayResize(hf.digits,                      size);
      ArrayResize(hf.server,                      size);

      ArrayResize(hf.stored.bars,                 size);
      ArrayResize(hf.stored.from.offset,          size);
      ArrayResize(hf.stored.from.openTime,        size);
      ArrayResize(hf.stored.from.closeTime,       size);
      ArrayResize(hf.stored.from.nextCloseTime,   size);
      ArrayResize(hf.stored.to.offset,            size);
      ArrayResize(hf.stored.to.openTime,          size);
      ArrayResize(hf.stored.to.closeTime,         size);
      ArrayResize(hf.stored.to.nextCloseTime,     size);

      ArrayResize(hf.full.bars,                   size);
      ArrayResize(hf.full.from.offset,            size);
      ArrayResize(hf.full.from.openTime,          size);
      ArrayResize(hf.full.from.closeTime,         size);
      ArrayResize(hf.full.from.nextCloseTime,     size);
      ArrayResize(hf.full.to.offset,              size);
      ArrayResize(hf.full.to.openTime,            size);
      ArrayResize(hf.full.to.closeTime,           size);
      ArrayResize(hf.full.to.nextCloseTime,       size);

      ArrayResize(hf.lastStoredBar.offset,        size);
      ArrayResize(hf.lastStoredBar.openTime,      size);
      ArrayResize(hf.lastStoredBar.closeTime,     size);
      ArrayResize(hf.lastStoredBar.nextCloseTime, size);
      ArrayResize(hf.lastStoredBar.data,          size);

      ArrayResize(hf.bufferedBar.offset,          size);
      ArrayResize(hf.bufferedBar.openTime,        size);
      ArrayResize(hf.bufferedBar.closeTime,       size);
      ArrayResize(hf.bufferedBar.nextCloseTime,   size);
      ArrayResize(hf.bufferedBar.data,            size);
      ArrayResize(hf.bufferedBar.modified,        size);

      for (int i=size-1; i >= oldSize; i--) {                        // falls Arrays vergr��ert werden, neue Offsets initialisieren
         hf.lastStoredBar.offset [i] = -1;
         hf.bufferedBar.offset[i] = -1;
      }
   }
   return(size);
}


/**
 * Clean up opened files and issue a warning if an unclosed file was found.
 *
 * @return bool - success status
 *
 * @access private
 */
bool __CheckFileHandles() {
   int error, size=ArraySize(hf.hFile);

   for (int i=0; i < size; i++) {
      if (hf.hFile[i] > 0) {
         warn("__CheckFileHandles(1)  open file handle #"+ hf.hFile[i] +" found [hstFile="+ DoubleQuoteStr(hf.symbol[i] +","+ PeriodDescription(hf.period[i])) +"]");
         if (!HistoryFile.Close(hf.hFile[i]))
            error = last_error;
      }
   }
   return(!error);
}


/**
 * Wird von Expert::Library::init() bei Init-Cycle im Tester aufgerufen, um die verwendeten globalen Variablen vor dem n�chsten
 * Test zur�ckzusetzen.
 */
void Tester.ResetGlobalLibraryVars() {
   __ResizeSetArrays (0);
   __ResizeFileArrays(0);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   __CheckFileHandles();
   return(last_error);
}


/**
 * Erzeugt in der Konfiguration des angegebenen AccountServers ein neues Symbol.
 *
 * @param  string symbol         - Symbol
 * @param  string description    - Symbolbeschreibung
 * @param  string group          - Name der Gruppe, in der das Symbol gelistet wird
 * @param  int    digits         - Digits
 * @param  string baseCurrency   - Basisw�hrung
 * @param  string marginCurrency - Marginw�hrung
 * @param  string server         - Name des Accountservers, in dessen Konfiguration das Symbol angelegt wird (default: der aktuelle AccountServer)
 *
 * @return int - ID des Symbols (non-negative) oder EMPTY (-1), falls ein Fehler auftrat (z.B. wenn das angegebene Symbol bereits existiert)
 */
int CreateSymbol(string symbol, string description, string group, int digits, string baseCurrency, string marginCurrency, string server="") {
   if (!StringLen(symbol))                         return(_EMPTY(catch("CreateSymbol(1)  invalid parameter symbol = "+ DoubleQuoteStr(symbol), ERR_INVALID_PARAMETER)));
   if (StringLen(symbol) > MAX_SYMBOL_LENGTH)      return(_EMPTY(catch("CreateSymbol(2)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (max "+ MAX_SYMBOL_LENGTH +" characters)", ERR_INVALID_PARAMETER)));
   if (StringContains(symbol, " "))                return(_EMPTY(catch("CreateSymbol(3)  invalid parameter symbol = "+ DoubleQuoteStr(symbol) +" (must not contain spaces)", ERR_INVALID_PARAMETER)));
   if (StringLen(group) > MAX_SYMBOL_GROUP_LENGTH) return(_EMPTY(catch("CreateSymbol(4)  invalid parameter group = "+ DoubleQuoteStr(group) +" (max "+ MAX_SYMBOL_GROUP_LENGTH +" characters)", ERR_INVALID_PARAMETER)));

   int   groupIndex;
   color groupColor = CLR_NONE;

   // alle Symbolgruppen einlesen
   /*SYMBOL_GROUP[]*/int sgs[];
   int size = GetSymbolGroups(sgs, server); if (size < 0) return(-1);

   // angegebene Gruppe suchen
   for (int i=0; i < size; i++) {
      if (sgs_Name(sgs, i) == group)
         break;
   }
   if (i == size) {                                                  // Gruppe nicht gefunden, neu anlegen
      i = AddSymbolGroup(sgs, group, group, groupColor); if (i < 0) return(-1);
      if (!SaveSymbolGroups(sgs, server))                           return(-1);
   }
   groupIndex = i;
   groupColor = sgs_BackgroundColor(sgs, i);

   // Symbol anlegen
   /*SYMBOL*/int iSymbol[]; InitializeByteBuffer(iSymbol, SYMBOL.size);
   if (!SetSymbolTemplate                  (iSymbol, SYMBOL_TYPE_INDEX))             return(-1);
   if (!StringLen(symbol_SetName           (iSymbol, symbol           )))            return(_EMPTY(catch("CreateSymbol(5)->symbol_SetName() => NULL", ERR_RUNTIME_ERROR)));
   if (!StringLen(symbol_SetDescription    (iSymbol, description      )))            return(_EMPTY(catch("CreateSymbol(6)->symbol_SetDescription() => NULL", ERR_RUNTIME_ERROR)));
   if (          !symbol_SetDigits         (iSymbol, digits           ))             return(_EMPTY(catch("CreateSymbol(7)->symbol_SetDigits() => FALSE", ERR_RUNTIME_ERROR)));
   if (!StringLen(symbol_SetBaseCurrency   (iSymbol, baseCurrency     )))            return(_EMPTY(catch("CreateSymbol(8)->symbol_SetBaseCurrency() => NULL", ERR_RUNTIME_ERROR)));
   if (!StringLen(symbol_SetMarginCurrency (iSymbol, marginCurrency   )))            return(_EMPTY(catch("CreateSymbol(9)->symbol_SetMarginCurrency() => NULL", ERR_RUNTIME_ERROR)));
   if (           symbol_SetGroup          (iSymbol, groupIndex       ) < 0)         return(_EMPTY(catch("CreateSymbol(10)->symbol_SetGroup() => -1", ERR_RUNTIME_ERROR)));
   if (           symbol_SetBackgroundColor(iSymbol, groupColor       ) == CLR_NONE) return(_EMPTY(catch("CreateSymbol(11)->symbol_SetBackgroundColor() => CLR_NONE", ERR_RUNTIME_ERROR)));

   if (!InsertSymbol(iSymbol, server)) return(-1);
   return(symbol_Id(iSymbol));
}


/**
 * Gibt alle Symbolgruppen des angegebenen AccountServers zur�ck.
 *
 * @param  SYMBOL_GROUP sgs[]      - Array zur Aufnahme der eingelesenen Symbolgruppen
 * @param  string       serverName - Name des AccountServers (default: der aktuelle AccountServer)
 *
 * @return int - Anzahl der gelesenen Gruppen oder -1 (EMPTY), falls ein Fehler auftrat
 */
int GetSymbolGroups(/*SYMBOL_GROUP*/int sgs[], string serverName="") {
   if (serverName == "0")      serverName = "";                      // (string) NULL
   if (!StringLen(serverName)) serverName = GetServerName(); if (serverName == "") return(EMPTY);

   ArrayResize(sgs, 0);

   // (1) "symgroups.raw" auf Existenz pr�fen                        // Extra-Pr�fung, da bei Read-only-Zugriff FileOpen[History]() bei nicht existierender
   string mqlFileName = ".history\\"+ serverName +"\\symgroups.raw"; // Datei das Log mit Warnungen ERR_CANNOT_OPEN_FILE �berschwemmt.
   if (!IsMqlFile(mqlFileName))
      return(0);

   // (2) Datei �ffnen und Gr��e validieren
   int hFile = FileOpen(mqlFileName, FILE_READ|FILE_BIN);
   int error = GetLastError();
   if (IsError(error) || hFile <= 0)  return(_EMPTY(catch("GetSymbolGroups(1)->FileOpen(\""+ mqlFileName +"\", FILE_READ) => "+ hFile, ifInt(error, error, ERR_RUNTIME_ERROR))));
   int fileSize = FileSize(hFile);
   if (fileSize % SYMBOL_GROUP.size != 0) {
      FileClose(hFile);               return(_EMPTY(catch("GetSymbolGroups(2)  invalid size of \""+ mqlFileName +"\" (not an even SYMBOL_GROUP size, "+ (fileSize % SYMBOL_GROUP.size) +" trailing bytes)", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR))));
   }
   if (!fileSize) { FileClose(hFile); return(0); }                   // Eine leere Datei wird akzeptiert. Eigentlich mu� sie immer 32 * SYMBOL_GROUP.size gro� sein,
                                                                     // doch im Moment der Erstellung (von jemand anderem) kann sie vor�bergehend 0 Bytes gro� sein.
   // (3) Datei einlesen
   InitializeByteBuffer(sgs, fileSize);
   int ints = FileReadArray(hFile, sgs, 0, fileSize/4);
   error = GetLastError();
   FileClose(hFile);
   if (IsError(error) || ints!=fileSize/4) return(_EMPTY(catch("GetSymbolGroups(3)  error reading \""+ mqlFileName +"\" ("+ ints*4 +" of "+ fileSize +" bytes read)", ifInt(error, error, ERR_RUNTIME_ERROR))));

   return(fileSize/SYMBOL_GROUP.size);
}


/**
 * F�gt einer Liste von Symbolgruppen eine weitere hinzu. Die Gruppe wird an der ersten verf�gbaren Position der Liste gespeichert.
 *
 * @param  SYMBOL_GROUP sgs[] - Liste von Symbolgruppen, der die neue Gruppe hinzugef�gt werden soll
 * @param  string name        - Gruppenname
 * @param  string description - Gruppenbeschreibung
 * @param  color  bgColor     - Hintergrundfarbe der Symbolgruppe im "Market Watch"-Window
 *
 * @return int - Index der Gruppe innerhalb der Liste oder -1 (EMPTY), falls ein Fehler auftrat (z.B. wenn die angegebene Gruppe bereits existiert)
 */
int AddSymbolGroup(/*SYMBOL_GROUP*/int sgs[], string name, string description, color bgColor) {
   int byteSize = ArraySize(sgs) * 4;
   if (byteSize % SYMBOL_GROUP.size != 0)         return(_EMPTY(catch("AddSymbolGroup(1)  invalid size of sgs[] (not an even SYMBOL_GROUP size, "+ (byteSize % SYMBOL_GROUP.size) +" trailing bytes)", ERR_RUNTIME_ERROR)));
   if (name == "0") name = "";                    // (string) NULL
   if (!StringLen(name))                          return(_EMPTY(catch("AddSymbolGroup(2)  invalid parameter name = "+ DoubleQuoteStr(name), ERR_INVALID_PARAMETER)));
   if (StringLen(name) > MAX_SYMBOL_GROUP_LENGTH) return(_EMPTY(catch("AddSymbolGroup(3)  invalid parameter name = "+ DoubleQuoteStr(name) +" (max "+ MAX_SYMBOL_GROUP_LENGTH +" characters)", ERR_INVALID_PARAMETER)));
   if (description == "0") description = "";      // (string) NULL
   if (bgColor!=CLR_NONE && bgColor & 0xFF000000) return(_EMPTY(catch("AddSymbolGroup(4)  invalid parameter bgColor = 0x"+ IntToHexStr(bgColor) +" (not a color)", ERR_INVALID_PARAMETER)));

   // �berpr�fen, ob die angegebene Gruppe bereits existiert und dabei den ersten freien Index ermitteln
   int groupsSize = byteSize/SYMBOL_GROUP.size;
   int iFree = -1;
   for (int i=0; i < groupsSize; i++) {
      string foundName = sgs_Name(sgs, i);
      if (name == foundName)                      return(_EMPTY(catch("AddSymbolGroup(5)  a group named "+ DoubleQuoteStr(name) +" already exists", ERR_RUNTIME_ERROR)));
      if (iFree==-1) /*&&*/ if (foundName=="")
         iFree = i;
   }

   // ohne freien Index das Array entsprechend vergr��ern
   if (iFree == -1) {
      ArrayResize(sgs, (groupsSize+1)*SYMBOL_GROUP.intSize);
      iFree = groupsSize;
      groupsSize++;
   }

   // neue Gruppe erstellen und an freien Index kopieren
   /*SYMBOL_GROUP*/int sg[]; InitializeByteBuffer(sg, SYMBOL_GROUP.size);
   if (!StringLen(sg_SetName           (sg, name       )))            return(_EMPTY(catch("AddSymbolGroup(6)->sg_SetName() => NULL", ERR_RUNTIME_ERROR)));
   if (!StringLen(sg_SetDescription    (sg, description)))            return(_EMPTY(catch("AddSymbolGroup(7)->sg_SetDescription() => NULL", ERR_RUNTIME_ERROR)));
   if (           sg_SetBackgroundColor(sg, bgColor    ) == CLR_NONE) return(_EMPTY(catch("AddSymbolGroup(8)->sg_SetBackgroundColor() => CLR_NONE", ERR_RUNTIME_ERROR)));

   int src  = GetIntsAddress(sg);
   int dest = GetIntsAddress(sgs) + iFree*SYMBOL_GROUP.size;
   CopyMemory(dest, src, SYMBOL_GROUP.size);
   ArrayResize(sg, 0);

   return(iFree);
}


/**
 * Speichert die �bergebenen Symbolgruppen in der Datei "symgroups.raw" des angegebenen AccountServers. Eine existierende Datei wird �berschrieben.
 *
 * @param  SYMBOL_GROUP sgs[]      - Array von Symbolgruppen
 * @param  string       serverName - Name des Accountservers, in dessen Verzeichnis die Gruppen gespeichert werden (default: der aktuelle AccountServer)
 *
 * @return bool - Erfolgsstatus
 */
bool SaveSymbolGroups(/*SYMBOL_GROUP*/int sgs[], string serverName="") {
   int byteSize = ArraySize(sgs) * 4;
   if (byteSize % SYMBOL_GROUP.size != 0)                                          return(!catch("SaveSymbolGroups(1)  invalid size of sgs[] (not an even SYMBOL_GROUP size, "+ (byteSize % SYMBOL_GROUP.size) +" trailing bytes)", ERR_RUNTIME_ERROR));
   if (byteSize > 32*SYMBOL_GROUP.size)                                            return(!catch("SaveSymbolGroups(2)  invalid number of groups in sgs[] (max 32)", ERR_RUNTIME_ERROR));
   if (serverName == "0")      serverName = "";                      // (string) NULL
   if (!StringLen(serverName)) serverName = GetServerName(); if (serverName == "") return(false);

   // "symgroups.raw" mu� immer 32 Gruppen enthalten (ggf. undefiniert)
   int sgs.copy[]; ArrayResize(sgs.copy, 0);
   if (ArraySize(sgs) < 32*SYMBOL_GROUP.intSize)
      InitializeByteBuffer(sgs.copy, 32*SYMBOL_GROUP.size);          // um das �bergebene Array nicht zu ver�ndern, erweitern wir ggf. eine Kopie
   ArrayCopy(sgs.copy, sgs);

   // Datei �ffnen                                                   // TODO: Verzeichnis �berpr�fen und ggf. erstellen
   string mqlFileName = ".history\\"+ serverName +"\\symgroups.raw";
   int hFile = FileOpen(mqlFileName, FILE_WRITE|FILE_BIN);
   int error = GetLastError();
   if (IsError(error) || hFile <= 0)  return(!catch("SaveSymbolGroups(3)->FileOpen(\""+ mqlFileName +"\", FILE_WRITE) => "+ hFile, ifInt(error, error, ERR_RUNTIME_ERROR)));

   // Daten schreiben
   int arraySize = ArraySize(sgs.copy);
   int ints = FileWriteArray(hFile, sgs.copy, 0, arraySize);
   error = GetLastError();
   FileClose(hFile);
   if (IsError(error) || ints!=arraySize) return(!catch("SaveSymbolGroups(4)  error writing SYMBOL_GROUP[] to \""+ mqlFileName +"\" ("+ ints*4 +" of "+ arraySize*4 +" bytes written)", ifInt(error, error, ERR_RUNTIME_ERROR)));

   ArrayResize(sgs.copy, 0);
   return(true);
}


/**
 * Kopiert das Template des angegebenen Symbol-Typs in das �bergebene Symbol.
 *
 * @param  SYMBOL symbol[] - Symbol
 * @param  int    type     - Symbol-Typ
 *
 * @return bool - Erfolgsstatus
 */
bool SetSymbolTemplate(/*SYMBOL*/int symbol[], int type) {
   // Parameter validieren und Template-Datei bestimmen
   string fileName;
   switch (type) {
      case SYMBOL_TYPE_FOREX  : fileName = "templates/SYMBOL_TYPE_FOREX.raw";   break;
      case SYMBOL_TYPE_CFD    : fileName = "templates/SYMBOL_TYPE_CFD.raw";     break;
      case SYMBOL_TYPE_INDEX  : fileName = "templates/SYMBOL_TYPE_INDEX.raw";   break;
      case SYMBOL_TYPE_FUTURES: fileName = "templates/SYMBOL_TYPE_FUTURES.raw"; break;

      default: return(!catch("SetSymbolTemplate(1)  invalid parameter type = "+ type +" (not a symbol type)", ERR_INVALID_PARAMETER));
   }

   // Template-File auf Existenz pr�fen                              // Extra-Pr�fung, da bei Read-only-Zugriff FileOpen() bei nicht existierender
   if (!IsMqlFile(fileName))                                         // Datei das Log mit Warnungen ERR_CANNOT_OPEN_FILE zum�llt.
      return(false);

   // Datei �ffnen und Gr��e validieren
   int hFile = FileOpen(fileName, FILE_READ|FILE_BIN);
   int error = GetLastError();
   if (IsError(error) || hFile <= 0)       return(!catch("SetSymbolTemplate(2)->FileOpen(\""+ fileName +"\", FILE_READ) => "+ hFile, ifInt(error, error, ERR_RUNTIME_ERROR)));
   int fileSize = FileSize(hFile);
   if (fileSize != SYMBOL.size) {
      FileClose(hFile);                    return(!catch("SetSymbolTemplate(3)  invalid size "+ fileSize +" of \""+ fileName +"\" (not a SYMBOL size)", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR)));
   }

   // Datei in das �bergebene Symbol einlesen
   InitializeByteBuffer(symbol, fileSize);
   int ints = FileReadArray(hFile, symbol, 0, fileSize/4);
   error = GetLastError();
   FileClose(hFile);
   if (IsError(error) || ints!=fileSize/4) return(!catch("SetSymbolTemplate(3)  error reading \""+ fileName +"\" ("+ ints*4 +" of "+ fileSize +" bytes read)", ifInt(error, error, ERR_RUNTIME_ERROR)));

   return(true);
}


/**
 * F�gt das Symbol der angegebenen AccountServer-Konfiguration hinzu.
 *
 * @param  SYMBOL symbol[]   - Symbol
 * @param  string serverName - Name des Accountservers (default: der aktuelle AccountServer)
 *
 * @return bool - Erfolgsstatus
 */
bool InsertSymbol(/*SYMBOL*/int symbol[], string serverName="") {
   if (ArraySize(symbol) != SYMBOL.intSize)                                        return(!catch("InsertSymbol(1)  invalid size "+ ArraySize(symbol) +" of parameter symbol[] (not SYMBOL.intSize)", ERR_RUNTIME_ERROR));
   string name, newName=symbol_Name(symbol);
   if (!StringLen(newName))                                                        return(!catch("InsertSymbol(2)  invalid parameter symbol[], SYMBOL.name = "+ DoubleQuoteStr(newName), ERR_RUNTIME_ERROR));
   if (serverName == "0")      serverName = "";    // (string) NULL
   if (!StringLen(serverName)) serverName = GetServerName(); if (serverName == "") return(false);


   // (1.1) Symboldatei �ffnen und Gr��e validieren
   string mqlFileName = ".history\\"+ serverName +"\\symbols.raw";
   int hFile = FileOpen(mqlFileName, FILE_READ|FILE_WRITE|FILE_BIN);
   int error = GetLastError();
   if (IsError(error) || hFile <= 0) return(!catch("InsertSymbol(3)->FileOpen(\""+ mqlFileName +"\", FILE_READ|FILE_WRITE) => "+ hFile, ifInt(error, error, ERR_RUNTIME_ERROR)));
   int fileSize = FileSize(hFile);
   if (fileSize % SYMBOL.size != 0) {
      FileClose(hFile); return(!catch("InsertSymbol(4)  invalid size of \""+ mqlFileName +"\" (not an even SYMBOL size, "+ (fileSize % SYMBOL.size) +" trailing bytes)", ifInt(SetLastError(GetLastError()), last_error, ERR_RUNTIME_ERROR)));
   }
   int symbolsSize=fileSize/SYMBOL.size, maxId=-1;
   /*SYMBOL[]*/int symbols[]; InitializeByteBuffer(symbols, fileSize);

   if (fileSize > 0) {
      // (1.2) vorhandene Symbole einlesen
      int ints = FileReadArray(hFile, symbols, 0, fileSize/4);
      error = GetLastError();
      if (IsError(error) || ints!=fileSize/4) { FileClose(hFile); return(!catch("InsertSymbol(5)  error reading \""+ mqlFileName +"\" ("+ ints*4 +" of "+ fileSize +" bytes read)", ifInt(error, error, ERR_RUNTIME_ERROR))); }

      // (1.3) sicherstellen, da� das neue Symbol noch nicht existiert und gr��te Symbol-ID finden
      for (int i=0; i < symbolsSize; i++) {
         if (symbols_Name(symbols, i) == newName) { FileClose(hFile); return(!catch("InsertSymbol(6)   a symbol named "+ DoubleQuoteStr(newName) +" already exists", ERR_RUNTIME_ERROR)); }
         maxId = Max(maxId, symbols_Id(symbols, i));
      }
   }

   // (2) neue Symbol-ID setzen und Symbol am Ende anf�gen
   if (symbol_SetId(symbol, maxId+1) == -1) { FileClose(hFile); return(!catch("InsertSymbol(7)->symbol_SetId() => -1", ERR_RUNTIME_ERROR)); }

   ArrayResize(symbols, (symbolsSize+1)*SYMBOL.intSize);
   i = symbolsSize;
   symbolsSize++;
   int src  = GetIntsAddress(symbol);
   int dest = GetIntsAddress(symbols) + i*SYMBOL.size;
   CopyMemory(dest, src, SYMBOL.size);


   // (3) Array sortieren und Symbole speichern                      // TODO: "symbols.sel" synchronisieren oder l�schen
   if (!SortSymbols(symbols, symbolsSize)) { FileClose(hFile); return(!catch("InsertSymbol(8)->SortSymbols() => FALSE", ERR_RUNTIME_ERROR)); }

   if (!FileSeek(hFile, 0, SEEK_SET)) { FileClose(hFile);      return(!catch("InsertSymbol(9)->FileSeek(hFile, 0, SEEK_SET) => FALSE", ERR_RUNTIME_ERROR)); }
   int elements = symbolsSize * SYMBOL.size / 4;
   ints  = FileWriteArray(hFile, symbols, 0, elements);
   error = GetLastError();
   FileClose(hFile);
   if (IsError(error) || ints!=elements)                       return(!catch("InsertSymbol(10)  error writing SYMBOL[] to \""+ mqlFileName +"\" ("+ ints*4 +" of "+ symbolsSize*SYMBOL.size +" bytes written)", ifInt(error, error, ERR_RUNTIME_ERROR)));

   return(true);
}
