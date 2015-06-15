/**
 * Funktionen zur Verwaltung von Historydateien (Kursreihen im "history"-Verzeichnis).
 *
 * TODO: Offsets analog zur Chart-Indizierung implementieren (Offset 0 = j�ngste Bar)
 */
#property library

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/library.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <structs/mt4/HISTORY_HEADER.mqh>


/**
 * Gibt den letzten in der Library aufgetretenen Fehler zur�ck. Der Aufruf dieser Funktion setzt den Fehlercode *nicht* zur�ck.
 *
 * @return int - Fehlerstatus
 */
int history.GetLastError() {
   return(last_error);
}


// Daten einzelner HistoryFiles ----------------------------------------------------------------------------------------------------------------------------
int      hf.hFile     [];                          // Dateihandle: Arrayindex, wenn Datei offen; kleiner/gleich 0, wenn geschlossen/ung�ltig
int      hf.hFile.valid = -1;                      // das letzte g�ltige Handle (um ein �bergebenes Handle nicht st�ndig neu validieren zu m�ssen)
string   hf.name      [];                          // Dateiname
bool     hf.read      [];                          // ob das Handle Lese-Zugriff erlaubt
bool     hf.write     [];                          // ob das Handle Schreib-Zugriff erlaubt
int      hf.size      [];                          // aktuelle Gr��e der Datei (inkl. noch ungeschriebener Daten im Schreibpuffer)

int      hf.header    [][HISTORY_HEADER.intSize];  // History-Header der Datei
string   hf.symbol    [];                          // Symbol  (wie im History-Header)
int      hf.period    [];                          // Periode (wie im History-Header)
int      hf.periodSecs[];                          // Dauer einer Periode in Sekunden
int      hf.digits    [];                          // Digits  (wie im History-Header)

int      hf.bars      [];                          // Anzahl der Bars der Datei
datetime hf.from      [];                          // OpenTime der ersten Bar der Datei
datetime hf.to        [];                          // OpenTime der letzten Bar der Datei

// Cache der aktuellen Bar (an der Position des File-Pointers)
int      hf.currentBar.offset       [];            // relativ zum Header: Offset 0 ist die �lteste Bar
datetime hf.currentBar.openTime     [];            //
datetime hf.currentBar.closeTime    [];            //
datetime hf.currentBar.nextCloseTime[];            //
double   hf.currentBar.data         [][5];         // Bar-Infos (OHLCV)

// Ticks einer ungespeicherten Bar (bei HST_CACHE_TICKS=On)
int      hf.tickBar.offset          [];            // relativ zum Header: Offset 0 ist die �lteste Bar
datetime hf.tickBar.openTime        [];            //
datetime hf.tickBar.closeTime       [];            //
datetime hf.tickBar.nextCloseTime   [];            //
double   hf.tickBar.data            [][5];         // Bar-Infos (OHLCV)


// Daten einzelner History-Sets ----------------------------------------------------------------------------------------------------------------------------
int      h.hHst       [];                          // History-Handle: Arrayindex, wenn Handle g�ltig; kleiner/gleich 0, wenn Handle geschlossen/ung�ltig
int      h.hHst.valid = -1;                        // das letzte g�ltige Handle (um ein �bergebenes Handle nicht st�ndig neu validieren zu m�ssen)
string   h.symbol     [];                          // Symbol
string   h.description[];                          // Symbolbeschreibung
int      h.digits     [];                          // Symboldigits
int      h.hFile      [][9];                       // HistoryFile-Handles des Sets je Standard-Timeframe
int      h.periods    [] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};


/**
 * Erzeugt f�r das angegebene Symbol eine neue History und gibt deren Handle zur�ck. Existiert f�r das angegebene Symbol bereits eine History,
 * wird sie gel�scht. Offene History-Handles f�r dasselbe Symbol werden geschlossen.
 *
 * @param  string symbol      - Symbol
 * @param  string description - Beschreibung des Symbols
 * @param  int    digits      - Digits der Datenreihe
 *
 * @return int - History-Handle oder 0, falls ein Fehler auftrat
 */
int CreateHistory(string symbol, string description, int digits) {
   int size = Max(ArraySize(h.hHst), 1);                             // ersten Index �berspringen (0 ist kein g�ltiges Handle)
   __h.ResizeArrays(size+1);

   // (1) neuen History-Datensatz erstellen
   h.hHst       [size] = size;
   h.symbol     [size] = symbol;
   h.description[size] = description;
   h.digits     [size] = digits;

   int sizeOfPeriods = ArraySize(h.periods);

   for (int i=0; i < sizeOfPeriods; i++) {
      int hFile = HistoryFile.Open(symbol, description, digits, h.periods[i], FILE_READ|FILE_WRITE);
      if (hFile <= 0)
         return(_NULL(__h.ResizeArrays(size)));                      // interne Arrays auf Ausgangsgr��e zur�cksetzen
      h.hFile[size][i] = hFile;
   }

   // (2) offene History-Handles desselben Symbols schlie�en
   for (i=size-1; i > 0; i--) {                                      // erstes (ung�ltiges) und letztes (gerade erzeugtes) Handle �berspringen
      if (h.symbol[i] == symbol) {
         if (h.hHst[i] > 0)
            h.hHst[i] = -1;
      }
   }

   h.hHst.valid = size;
   return(size);
}


/**
 * Sucht die History des angegebenen Symbols und gibt ein Handle f�r sie zur�ck.
 *
 * @param  string symbol - Symbol
 *
 * @return int - History-Handle oder 0, falls keine History gefunden wurde oder ein Fehler auftrat
 */
int FindHistory(string symbol) {
   int size = ArraySize(h.hHst);

   // Schleife, da es mehrere Handles je Symbol, jedoch nur ein offenes (das letzte) geben kann
   for (int i=size-1; i > 0; i--) {                                  // auf Index 0 kann kein g�ltiges Handle liegen
      if (h.symbol[i] == symbol) {
         if (h.hHst[i] > 0)
            return(h.hHst[i]);
      }
   }
   return(0);
}


/**
 * Setzt die angegebene History zur�ck. Alle gespeicherten Kursreihen werden gel�scht.
 *
 * @param  int hHst - History-Handle
 *
 * @return bool - Erfolgsstatus
 */
bool ResetHistory(int hHst) {
   return(!catch("ResetHistory(1)", ERR_NOT_IMPLEMENTED));
}


/**
 * F�gt der gesamten History eines Symbols einen Tick hinzu (au�er PERIOD_W1 und PERIOD_MN1). Der Tick wird in allen Timeframes als letzter Tick (Close)
 * der entsprechenden Bars gespeichert.
 *
 * @param  int      hHst  - History-Handle des Symbols wie von FindHistory() zur�ckgegeben
 * @param  datetime time  - Zeitpunkt des Ticks
 * @param  double   value - Datenwert
 * @param  int      flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                          HST_CACHE_TICKS: speichert aufeinanderfolgende Ticks zwischen und schreibt die Daten erst beim jeweils n�chsten BarOpen-Event
 *                          HST_FILL_GAPS:   f�llt entstehende Gaps mit dem letzten Schlu�kurs vor dem Gap
 *
 * @return bool - Erfolgsstatus
 */
bool History.AddTick(int hHst, datetime time, double value, int flags=NULL) {
   // Validierung
   if (hHst <= 0)                    return(!catch("History.AddTick(1)  invalid parameter hHst = "+ hHst, ERR_INVALID_PARAMETER));
   if (hHst != h.hHst.valid) {
      if (hHst >= ArraySize(h.hHst)) return(!catch("History.AddTick(2)  invalid parameter hHst = "+ hHst, ERR_INVALID_PARAMETER));
      if (h.hHst[hHst] == 0)         return(!catch("History.AddTick(3)  invalid parameter hHst = "+ hHst +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (h.hHst[hHst] <  0)         return(!catch("History.AddTick(4)  invalid parameter hHst = "+ hHst +" (closed handle)", ERR_INVALID_PARAMETER));
      h.hHst.valid = hHst;
   }
   if (time <= 0)                    return(!catch("History.AddTick(5)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER));

   // Dateihandles bis D1 (=> 7) holen und Tick jeweils hinzuf�gen
   for (int i=0; i < 7; i++) {
      if (!HistoryFile.AddTick(h.hFile[hHst][i], time, value, flags))
         return(false);
   }
   return(true);
}


/**
 * F�gt einer einzelnen Historydatei einen Tick hinzu. Der Tick wird als letzter Tick (Close) der entsprechenden Bar gespeichert.
 *
 * @param  int      hFile - Dateihandle der Historydatei
 * @param  datetime time  - Zeitpunkt des Ticks
 * @param  double   value - Datenwert
 * @param  int      flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                          HST_CACHE_TICKS: speichert aufeinanderfolgende Ticks zwischen und schreibt die Daten beim jeweils n�chsten BarOpen-Event
 *                          HST_FILL_GAPS:   f�llt entstehende Gaps mit dem letzten Schlu�kurs vor dem Gap
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: Zur Performancesteigerung werden die Tickdaten nicht zus�tzlich validiert.
 */
bool HistoryFile.AddTick(int hFile, datetime time, double value, int flags=NULL) {
   // Validierung
   if (hFile <= 0)                      return(!catch("HistoryFile.AddTick(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.AddTick(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.AddTick(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.AddTick(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }
   if (time <= 0)                       return(!catch("HistoryFile.AddTick(5)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER));


   bool   barExists[1], bHST_CACHE_TICKS=flags & HST_CACHE_TICKS, bHST_FILL_GAPS=flags & HST_FILL_GAPS;
   int    offset, iNull[];
   double data[5];


   // (1) Tick ggf. zwischenspeichern -------------------------------------------------------------------------------------------------------------
   if (bHST_CACHE_TICKS) {
      if (time < hf.tickBar.openTime[hFile] || time >= hf.tickBar.closeTime[hFile]) {
         // (1.1) Queue leer oder Tick geh�rt zu anderer Bar (davor oder dahinter)
         offset = HistoryFile.FindBar(hFile, time, barExists);                // Offset der Bar, zu der der Tick geh�rt
         if (offset < 0)
            return(false);

         if (hf.tickBar.openTime[hFile] == 0) {
            // (1.1.1) Queue leer
            if (barExists[0]) {                                               // Bar-Initialisierung
               if (!HistoryFile.ReadBar(hFile, offset, iNull, data))          // vorhandene Bar in Queue einlesen (als Ausgangsbasis)
                  return(false);
               hf.tickBar.data[hFile][BAR_O] =         data[BAR_O];           // Tick hinzuf�gen
               hf.tickBar.data[hFile][BAR_H] = MathMax(data[BAR_H], value);
               hf.tickBar.data[hFile][BAR_L] = MathMin(data[BAR_L], value);
               hf.tickBar.data[hFile][BAR_C] =                      value;
               hf.tickBar.data[hFile][BAR_V] =         data[BAR_V] + 1;
            }
            else {
               hf.tickBar.data[hFile][BAR_O] = value;                         // Bar existiert nicht: neue Bar beginnen
               hf.tickBar.data[hFile][BAR_H] = value;
               hf.tickBar.data[hFile][BAR_L] = value;
               hf.tickBar.data[hFile][BAR_C] = value;
               hf.tickBar.data[hFile][BAR_V] = 1;
            }
         }
         else {
            // (1.1.2) Queue gef�llt und Queue-Bar ist komplett
            if (hf.tickBar.offset[hFile] >= hf.bars[hFile]) /*&&*/ if (!barExists[0])
               offset++;   // Wenn die Queue-Bar real noch nicht existiert, mu� 'offset' vergr��ert werden, falls die neue Bar ebenfalls nicht existiert.

            if (!HistoryFile.WriteTickBar(hFile, flags))
               return(false);
            hf.tickBar.data[hFile][BAR_O] = value;                            // neue Bar beginnen
            hf.tickBar.data[hFile][BAR_H] = value;
            hf.tickBar.data[hFile][BAR_L] = value;
            hf.tickBar.data[hFile][BAR_C] = value;
            hf.tickBar.data[hFile][BAR_V] = 1;
         }
         hf.tickBar.offset       [hFile] = offset;
         hf.tickBar.openTime     [hFile] = time - time % hf.periodSecs[hFile];
         hf.tickBar.closeTime    [hFile] = hf.tickBar.openTime [hFile] + hf.periodSecs[hFile];
         hf.tickBar.nextCloseTime[hFile] = hf.tickBar.closeTime[hFile] + hf.periodSecs[hFile];
      }
      else {
         // (1.2) Tick geh�rt zur Queue-Bar
         //.tickBar.data[hFile][BAR_O] = ...                                  // unver�ndert
         hf.tickBar.data[hFile][BAR_H] = MathMax(hf.tickBar.data[hFile][BAR_H], value);
         hf.tickBar.data[hFile][BAR_L] = MathMin(hf.tickBar.data[hFile][BAR_L], value);
         hf.tickBar.data[hFile][BAR_C] = value;
         hf.tickBar.data[hFile][BAR_V]++;
      }
      return(true);
   }
   // ---------------------------------------------------------------------------------------------------------------------------------------------


   // (2) gef�llte Queue-Bar schreiben ------------------------------------------------------------------------------------------------------------
   if (hf.tickBar.offset[hFile] >= 0) {                                       // HST_CACHE_TICKS wechselte zur Laufzeit
      bool tick_in_queue = (time >= hf.tickBar.openTime[hFile] && time < hf.tickBar.closeTime[hFile]);
      if (tick_in_queue) {
       //hf.tickBar.data[hFile][BAR_O] = ... (unver�ndert)                    // Tick zur Queue hinzuf�gen
         hf.tickBar.data[hFile][BAR_H] = MathMax(hf.tickBar.data[hFile][BAR_H], value);
         hf.tickBar.data[hFile][BAR_L] = MathMin(hf.tickBar.data[hFile][BAR_L], value);
         hf.tickBar.data[hFile][BAR_C] = value;
         hf.tickBar.data[hFile][BAR_V]++;
      }
      if (!HistoryFile.WriteTickBar(hFile, flags))                            // Queue-Bar schreiben (unwichtig, ob komplett, da HST_CACHE_TICKS=Off)
         return(false);
      hf.tickBar.offset       [hFile] = -1;                                   // Queue-Bar zur�cksetzen
      hf.tickBar.openTime     [hFile] =  0;
      hf.tickBar.closeTime    [hFile] =  0;
      hf.tickBar.nextCloseTime[hFile] =  0;

      if (tick_in_queue)
         return(true);
   }
   // ---------------------------------------------------------------------------------------------------------------------------------------------


   // (3) Tick schreiben --------------------------------------------------------------------------------------------------------------------------
   datetime openTime = time - time%hf.periodSecs[hFile];                      // OpenTime der Tickbar ermitteln
   offset = HistoryFile.FindBar(hFile, openTime, barExists);                  // Offset der Tickbar ermitteln
   if (offset < 0)
      return(false);

   if (barExists[0])                                                          // existierende Bar aktualisieren...
      return(HistoryFile.UpdateBar(hFile, offset, value));

   data[BAR_O] = value;                                                       // ...oder neue Bar einf�gen
   data[BAR_H] = value;
   data[BAR_L] = value;
   data[BAR_C] = value;
   data[BAR_V] = 1;
   return(HistoryFile.InsertBar(hFile, offset, openTime, data, flags));
   // ---------------------------------------------------------------------------------------------------------------------------------------------
}


/**
 * Findet den Offset der Bar innerhalb einer Historydatei, die den angegebenen Zeitpunkt abdeckt, und signalisiert, ob an diesem Offset
 * bereits eine Bar existiert. Eine Bar existiert z.B. dann nicht, wenn die Zeitreihe am angegebenen Zeitpunkt eine L�cke aufweist oder
 * wenn der Zeitpunkt au�erhalb des von der Zeitreihe abgedeckten Datenbereichs liegt.
 *
 * @param  int      hFile          - Dateihandle der Historydatei
 * @param  datetime time           - Zeitpunkt
 * @param  bool     lpBarExists[1] - Zeiger auf Variable, die nach R�ckkehr anzeigt, ob die Bar am zur�ckgegebenen Offset existiert
 *                                   (als Array implementiert, um Zeiger�bergabe an eine Library zu erm�glichen)
 *                                   TRUE:  Bar existiert       (zum Aktualisieren dieser Bar mu� HistoryFile.UpdateBar() verwendet werden)
 *                                   FALSE: Bar existiert nicht (zum Aktualisieren dieser Bar mu� HistoryFile.InsertBar() verwendet werden)
 *
 * @return int - Bar-Offset oder -1 (EMPTY), falls ein Fehler auftrat
 */
int HistoryFile.FindBar(int hFile, datetime time, bool &lpBarExists[]) {
   if (hFile <= 0)                      return(_EMPTY(catch("HistoryFile.FindBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("HistoryFile.FindBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] == 0)         return(_EMPTY(catch("HistoryFile.FindBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <  0)         return(_EMPTY(catch("HistoryFile.FindBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER)));
      hf.hFile.valid = hFile;
   }
   if (time <= 0)                       return(_EMPTY(catch("HistoryFile.FindBar(5)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER)));
   if (ArraySize(lpBarExists) == 0)
      ArrayResize(lpBarExists, 1);

   // OpenTime der entsprechenden Bar berechnen
   time -= time%(hhs.Period(hf.header, hFile)*MINUTES);

   // (1) Zeitpunkt ist der Zeitpunkt der letzten Bar          // die beiden am h�ufigsten auftretenden F�lle zu Beginn pr�fen
   if (time == hf.to[hFile]) {
      lpBarExists[0] = true;
      return(hf.bars[hFile] - 1);
   }

   // (2) Zeitpunkt liegt zeitlich nach der letzten Bar        // die beiden am h�ufigsten auftretenden F�lle zu Beginn pr�fen
   if (time > hf.to[hFile]) {
      lpBarExists[0] = false;
      return(hf.bars[hFile]);
   }

   // (3) History leer
   if (hf.bars[hFile] == 0) {
      lpBarExists[0] = false;
      return(0);
   }

   // (4) Zeitpunkt ist der Zeitpunkt der ersten Bar
   if (time == hf.from[hFile]) {
      lpBarExists[0] = true;
      return(0);
   }

   // (5) Zeitpunkt liegt zeitlich vor der ersten Bar
   if (time < hf.from[hFile]) {
      lpBarExists[0] = false;
      return(0);
   }

   // (6) Zeitpunkt liegt irgendwo innerhalb der Zeitreihe
   int offset;
   return(_EMPTY(catch("HistoryFile.FindBar(6)  Suche nach Zeitpunkt innerhalb der Zeitreihe noch nicht implementiert", ERR_NOT_IMPLEMENTED)));

   if (!catch("HistoryFile.FindBar(7)", ERR_NOT_IMPLEMENTED))
      return(offset);
   return(EMPTY);
}


/**
 * Liest die Bar am angegebenen Offset einer Historydatei.
 *
 * @param  int      hFile   - Dateihandle der Historydatei
 * @param  int      offset  - Offset der Bar (relativ zum History-Header; Offset 0 ist �lteste Bar)
 * @param  datetime time[1] - Array zur Aufnahme von Bar-Time
 * @param  double   data[5] - Array zur Aufnahme der �brigen Bar-Daten (OHLCV)
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.ReadBar(int hFile, int offset, datetime &time[], double &data[]) {
   if (hFile <= 0)                             return(!catch("HistoryFile.ReadBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile))        return(!catch("HistoryFile.ReadBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)                return(!catch("HistoryFile.ReadBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)                return(!catch("HistoryFile.ReadBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }
   if (offset < 0 || offset >= hf.bars[hFile]) return(!catch("HistoryFile.ReadBar(5)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER));
   if (ArraySize(time) < 1) ArrayResize(time, 1);
   if (ArraySize(data) < 5) ArrayResize(data, 5);

   // Bar lesen
   int position = HISTORY_HEADER.size + offset*RATE_INFO.size;
   if (!FileSeek(hFile, position, SEEK_SET))
      return(!catch("HistoryFile.ReadBar(6)"));

   time[0] = FileReadInteger(hFile);
             FileReadArray  (hFile, data, 0, 5);

   hf.currentBar.offset       [hFile]        = offset;               // Cache aktualisieren
   hf.currentBar.openTime     [hFile]        = time[0];
   hf.currentBar.closeTime    [hFile]        = time[0] + hf.periodSecs[hFile];
   hf.currentBar.nextCloseTime[hFile]        = time[0] + hf.periodSecs[hFile]<<1;   // schneller f�r * 2
   hf.currentBar.data         [hFile][BAR_O] = data[BAR_O];
   hf.currentBar.data         [hFile][BAR_H] = data[BAR_H];
   hf.currentBar.data         [hFile][BAR_L] = data[BAR_L];
   hf.currentBar.data         [hFile][BAR_C] = data[BAR_C];
   hf.currentBar.data         [hFile][BAR_V] = data[BAR_V];

   return(!catch("HistoryFile.ReadBar(7)"));
}


/**
 * Aktualisiert die Bar am angegebenen Offset einer Historydatei.
 *
 * @param  int    hFile  - Dateihandle der Historydatei
 * @param  int    offset - Offset der zu aktualisierenden Bar innerhalb der Zeitreihe
 * @param  double value  - hinzuzuf�gender Wert
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: Zur Performancesteigerung werden die Tickdaten nicht zus�tzlich validiert.
 */
bool HistoryFile.UpdateBar(int hFile, int offset, double value) {
   if (hFile <= 0)                             return(!catch("HistoryFile.UpdateBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile))        return(!catch("HistoryFile.UpdateBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)                return(!catch("HistoryFile.UpdateBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)                return(!catch("HistoryFile.UpdateBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }
   if (offset < 0 || offset >= hf.bars[hFile]) return(!catch("HistoryFile.UpdateBar(5)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER));

   // (1) Bar ggf. neu in den Cache einlesen...
   if (offset != hf.currentBar.offset[hFile]) {
      int    time[1];
      double data[5];
      if (!HistoryFile.ReadBar(hFile, offset, time, data))
         return(false);
   }

   // (2) ...und zur Performancesteigerung direkt im Cache modifizieren
 //hf.currentBar.data[hFile][BAR_O] = ...                            // unver�ndert
   hf.currentBar.data[hFile][BAR_H] = MathMax(hf.currentBar.data[hFile][BAR_H], value);
   hf.currentBar.data[hFile][BAR_L] = MathMin(hf.currentBar.data[hFile][BAR_L], value);
   hf.currentBar.data[hFile][BAR_C] = value;
   hf.currentBar.data[hFile][BAR_V]++;

   // (3) Bar schreiben
   return(HistoryFile.WriteCurrentBar(hFile));
}


/**
 * F�gt eine neue Bar am angegebenen Offset einer Historydatei ein. Die Funktion �berpr�ft *nicht* die Plausibilit�t der einzuf�genden Daten.
 *
 * @param  int      hFile   - Dateihandle der Historydatei
 * @param  int      offset  - Offset der einzuf�genden Bar innerhalb der Zeitreihe (die erste Bar hat den Offset 0)
 * @param  datetime time    - Bar-Time
 * @param  double   data[5] - Bardaten
 * @param  int      flags   - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                            HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: Zur Performancesteigerung werden die Tickdaten nicht zus�tzlich validiert.
 */
bool HistoryFile.InsertBar(int hFile, int offset, datetime time, double data[], int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.InsertBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.InsertBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.InsertBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.InsertBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }
   if (offset < 0)                      return(!catch("HistoryFile.InsertBar(5)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER));
   if (time  <= 0)                      return(!catch("HistoryFile.InsertBar(6)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER));
   if (ArraySize(data) != 5)            return(!catch("HistoryFile.InsertBar(7)  invalid size of parameter data[] = "+ ArraySize(data), ERR_INCOMPATIBLE_ARRAYS));


   // (1) ggf. L�cke f�r neue Bar schaffen
   if (offset < hf.bars[hFile]) {
      if (!HistoryFile.MoveBars(hFile, offset, offset+1))
         return(false);
   }

   // (2) Bar schreiben
   return(HistoryFile.WriteBar(hFile, offset, time, data, flags));
}


/**
 * Schreibt eine Bar in die angegebene Historydatei. Eine ggf. vorhandene Bar mit dem selben Open-Zeitpunkt wird �berschrieben.
 *
 * @param  int      hFile   - Dateihandle der Historydatei
 * @param  int      offset  - Offset der zu schreibenden Bar (relativ zum Dateiheader; Offset 0 ist die �lteste Bar)
 * @param  datetime time    - Bar-Time
 * @param  double   data[5] - Bar-Daten (OHLCV)
 * @param  int      flags   - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                            HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: Zur Performancesteigerung werden die Bardaten *nicht* zus�tzlich validiert.
 */
bool HistoryFile.WriteBar(int hFile, int offset, datetime time, double data[], int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.WriteBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.WriteBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.WriteBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.WriteBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }
   if (offset < 0)                      return(!catch("HistoryFile.WriteBar(5)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER));
   if (time  <= 0)                      return(!catch("HistoryFile.WriteBar(6)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER));
   if (ArraySize(data) != 5)            return(!catch("HistoryFile.WriteBar(7)  invalid size of parameter data[] = "+ ArraySize(data), ERR_INCOMPATIBLE_ARRAYS));


   // (1) Bar schreiben
   int position = HISTORY_HEADER.size + offset*RATE_INFO.size;
   if (!FileSeek(hFile, position, SEEK_SET))
      return(!catch("HistoryFile.WriteBar(8)"));

   FileWriteInteger(hFile, time);
   FileWriteArray  (hFile, data, 0, 5);


   // (2) interne Daten aktualisieren
   if (offset >= hf.bars[hFile]) { hf.size                    [hFile]        = position + RATE_INFO.size;
                                   hf.bars                    [hFile]        = offset + 1; }
   if (offset == 0)                hf.from                    [hFile]        = time;
   if (offset == hf.bars[hFile]-1) hf.to                      [hFile]        = time;

                                   hf.currentBar.offset       [hFile]        = offset;
                                   hf.currentBar.openTime     [hFile]        = time;
                                   hf.currentBar.closeTime    [hFile]        = time + hf.periodSecs[hFile];
                                   hf.currentBar.nextCloseTime[hFile]        = time + hf.periodSecs[hFile]<<1;
                                   hf.currentBar.data         [hFile][BAR_O] = data[BAR_O];
                                   hf.currentBar.data         [hFile][BAR_H] = data[BAR_H];
                                   hf.currentBar.data         [hFile][BAR_L] = data[BAR_L];
                                   hf.currentBar.data         [hFile][BAR_C] = data[BAR_C];
                                   hf.currentBar.data         [hFile][BAR_V] = data[BAR_V];

   return(!catch("HistoryFile.WriteBar(9)"));
}


/**
 * Schreibt die aktuellen Bardaten in die Historydatei.
 *
 * @param  int hFile - Dateihandle der Historydatei
 * @param  int flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                     HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.WriteCurrentBar(int hFile, int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.WriteCurrentBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.WriteCurrentBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.WriteCurrentBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.WriteCurrentBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }

   datetime time   = hf.currentBar.openTime[hFile];
   int      offset = hf.currentBar.offset  [hFile];
   if (offset < 0)                      return(!catch("HistoryFile.WriteCurrentBar(5)  invalid hf.currentBar.offset["+ hFile +"] value = "+ offset, ERR_RUNTIME_ERROR));

   // (1) Bar schreiben
   int position = HISTORY_HEADER.size + offset*RATE_INFO.size;
   if (!FileSeek(hFile, position, SEEK_SET))
      return(!catch("HistoryFile.WriteCurrentBar(6)"));

   FileWriteInteger(hFile, time                            );
   FileWriteDouble (hFile, hf.currentBar.data[hFile][BAR_O]);
   FileWriteDouble (hFile, hf.currentBar.data[hFile][BAR_L]);
   FileWriteDouble (hFile, hf.currentBar.data[hFile][BAR_H]);
   FileWriteDouble (hFile, hf.currentBar.data[hFile][BAR_C]);
   FileWriteDouble (hFile, hf.currentBar.data[hFile][BAR_V]);


   // (2) interne Daten aktualisieren
   if (offset >= hf.bars[hFile]) { hf.size[hFile] = position + RATE_INFO.size;
                                   hf.bars[hFile] = offset + 1; }
   if (offset == 0)                hf.from[hFile] = time;
   if (offset == hf.bars[hFile]-1) hf.to  [hFile] = time;

   return(!catch("HistoryFile.WriteCurrentBar(7)"));
}


/**
 * Schreibt die zwischengespeicherten Tickdaten in die Historydatei.
 *
 * @param  int hFile - Dateihandle der Historydatei
 * @param  int flags - zus�tzliche, das Schreiben steuernde Flags (default: keine)
 *                     HST_FILL_GAPS: beim Schreiben entstehende Gaps werden mit dem Schlu�kurs der letzten Bar vor dem Gap gef�llt
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.WriteTickBar(int hFile, int flags=NULL) {
   if (hFile <= 0)                      return(!catch("HistoryFile.WriteTickBar(1)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.WriteTickBar(2)  invalid parameter hFile = "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.WriteTickBar(3)  invalid parameter hFile = "+ hFile +" (unknown handle)", ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <  0)         return(!catch("HistoryFile.WriteTickBar(4)  invalid parameter hFile = "+ hFile +" (closed handle)", ERR_INVALID_PARAMETER));
      hf.hFile.valid = hFile;
   }

   datetime time   = hf.tickBar.openTime[hFile];
   int      offset = hf.tickBar.offset  [hFile];
   if (offset < 0)                      return(!catch("HistoryFile.WriteTickBar(5)  invalid hf.tickBar.offset["+ hFile +"] value = "+ offset, ERR_RUNTIME_ERROR));


   // (1) Bar schreiben
   int position = HISTORY_HEADER.size + offset*RATE_INFO.size;
   if (!FileSeek(hFile, position, SEEK_SET))
      return(!catch("HistoryFile.WriteTickBar(6)"));

   FileWriteInteger(hFile, time                         );
   FileWriteDouble (hFile, hf.tickBar.data[hFile][BAR_O]);
   FileWriteDouble (hFile, hf.tickBar.data[hFile][BAR_L]);
   FileWriteDouble (hFile, hf.tickBar.data[hFile][BAR_H]);
   FileWriteDouble (hFile, hf.tickBar.data[hFile][BAR_C]);
   FileWriteDouble (hFile, hf.tickBar.data[hFile][BAR_V]);


   // (2) interne Daten aktualisieren
   if (offset >= hf.bars[hFile]) { hf.size                    [hFile]        = position + RATE_INFO.size;
                                   hf.bars                    [hFile]        = offset + 1; }
   if (offset == 0)                hf.from                    [hFile]        = time;
   if (offset == hf.bars[hFile]-1) hf.to                      [hFile]        = time;

                                   // Das Schreiben macht die TickBar zus�tzlich zur aktuellen Bar.
                                   hf.currentBar.offset       [hFile]        = hf.tickBar.offset       [hFile];
                                   hf.currentBar.openTime     [hFile]        = hf.tickBar.openTime     [hFile];
                                   hf.currentBar.closeTime    [hFile]        = hf.tickBar.closeTime    [hFile];
                                   hf.currentBar.nextCloseTime[hFile]        = hf.tickBar.nextCloseTime[hFile];
                                   hf.currentBar.data         [hFile][BAR_O] = hf.tickBar.data         [hFile][BAR_O];
                                   hf.currentBar.data         [hFile][BAR_L] = hf.tickBar.data         [hFile][BAR_L];
                                   hf.currentBar.data         [hFile][BAR_H] = hf.tickBar.data         [hFile][BAR_H];
                                   hf.currentBar.data         [hFile][BAR_C] = hf.tickBar.data         [hFile][BAR_C];
                                   hf.currentBar.data         [hFile][BAR_V] = hf.tickBar.data         [hFile][BAR_V];

   return(!catch("HistoryFile.WriteTickBar(7)"));
}


/**
 *
 * @param  int hFile       - Dateihandle der Historydatei
 * @param  int startOffset
 * @param  int destOffset
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.MoveBars(int hFile, int startOffset, int destOffset) {
   return(!catch("HistoryFile.MoveBars(1)", ERR_NOT_IMPLEMENTED));
}


/**
 * �ffnet eine Historydatei und gibt das resultierende Dateihandle zur�ck. Ist der Access-Mode FILE_WRITE angegeben und die Datei existiert nicht,
 * wird sie erstellt und ein HISTORY_HEADER geschrieben.
 *
 * @param  string symbol      - Symbol des Instruments
 * @param  string description - Beschreibung des Instruments (falls die Historydatei neu erstellt wird)
 * @param  int    digits      - Digits der Werte             (falls die Historydatei neu erstellt wird)
 * @param  int    timeframe   - Timeframe der Zeitreihe
 * @param  int    mode        - Access-Mode: FILE_READ | FILE_WRITE
 *
 * @return int - Dateihandle
 *
 *
 * NOTE: Das zur�ckgegebene Handle darf nicht modul-�bergreifend verwendet werden. Mit den MQL-Dateifunktionen k�nnen je Modul maximal 32 Dateien
 *       gleichzeitig offen gehalten werden.
 */
int HistoryFile.Open(string symbol, string description, int digits, int timeframe, int mode) {
   if (StringLen(symbol) > MAX_SYMBOL_LENGTH)               return(_NULL(catch("HistoryFile.Open(1)  illegal parameter symbol = "+ symbol +" (max "+ MAX_SYMBOL_LENGTH +" chars)", ERR_INVALID_PARAMETER)));
   if (digits <  0)                                         return(_NULL(catch("HistoryFile.Open(2)  illegal parameter digits = "+ digits, ERR_INVALID_PARAMETER)));
   if (timeframe <= 0)                                      return(_NULL(catch("HistoryFile.Open(3)  illegal parameter timeframe = "+ timeframe, ERR_INVALID_PARAMETER)));
   if (mode & FILE_CSV || !(mode & (FILE_READ|FILE_WRITE))) return(_NULL(catch("HistoryFile.Open(4)  illegal history file access mode "+ FileAccessModeToStr(mode), ERR_INVALID_PARAMETER)));

   string fileName = StringConcatenate(symbol, timeframe, ".hst");
   mode |= FILE_BIN;
   int hFile = FileOpenHistory(fileName, mode);
   if (hFile < 0)
      return(_NULL(catch("HistoryFile.Open(5)->FileOpenHistory(\""+ fileName +"\")")));

   /*HISTORY_HEADER*/int hh[]; InitializeByteBuffer(hh, HISTORY_HEADER.size);

   int bars, from, to, fileSize=FileSize(hFile);

   if (fileSize < HISTORY_HEADER.size) {
      if (!(mode & FILE_WRITE)) {                                    // read-only mode
         FileClose(hFile);
         return(_NULL(catch("HistoryFile.Open(6)  corrupted history file \""+ fileName +"\" (size = "+ fileSize +")", ERR_RUNTIME_ERROR)));
      }
      // neuen HISTORY_HEADER schreiben
      datetime now = TimeCurrentFix();                               // TODO: ServerTime() implementieren (TimeCurrent() ist Zeit des letzten Ticks)
      hh.setVersion      (hh, 400        );
      hh.setDescription  (hh, description);
      hh.setSymbol       (hh, symbol     );
      hh.setPeriod       (hh, timeframe  );
      hh.setDigits       (hh, digits     );
      hh.setDbVersion    (hh, now        );                          // wird beim n�chsten Online-Refresh mit Server-DbVersion �berschrieben
      hh.setPrevDbVersion(hh, now        );                          // derselbe Wert, wird beim n�chsten Online-Refresh *nicht* �berschrieben
      FileWriteArray(hFile, hh, 0, ArraySize(hh));
      fileSize = HISTORY_HEADER.size;
   }
   else {
      // vorhandenen HISTORY_HEADER auslesen
      FileReadArray(hFile, hh, 0, ArraySize(hh));

      // Bar-Infos auslesen
      if (fileSize > HISTORY_HEADER.size) {
         bars = (fileSize-HISTORY_HEADER.size) / RATE_INFO.size;
         if (bars > 0) {
            from = FileReadInteger(hFile);
            FileSeek(hFile, HISTORY_HEADER.size + (bars-1)*RATE_INFO.size, SEEK_SET);
            to   = FileReadInteger(hFile);
         }
      }
   }

   // Daten zwischenspeichern
   if (hFile >= ArraySize(hf.hFile)) {
      __hf.ResizeArrays(hFile+1);
   }
                    hf.hFile     [hFile] = hFile;
                    hf.name      [hFile] = fileName;
                    hf.read      [hFile] = mode & FILE_READ;
                    hf.write     [hFile] = mode & FILE_WRITE;
                    hf.size      [hFile] = fileSize;

   ArraySetIntArray(hf.header,    hFile, hh);                        // entspricht: hf.header[hFile] = hh;
                    hf.symbol    [hFile] = symbol;
                    hf.period    [hFile] = timeframe;
                    hf.periodSecs[hFile] = timeframe * MINUTES;
                    hf.digits    [hFile] = digits;

                    hf.bars      [hFile] = bars;
                    hf.from      [hFile] = from;
                    hf.to        [hFile] = to;

   hf.hFile.valid = hFile;

   ArrayResize(hh, 0);

   if (!catch("HistoryFile.Open(7)"))
      return(hFile);
   return(0);
}


/**
 * Schlie�t die Historydatei mit dem angegebenen Dateihandle. Die Datei mu� vorher mit HistoryFile.Open() ge�ffnet worden sein.
 *
 * @param  int hFile - Dateihandle
 *
 * @return bool - Erfolgsstatus
 */
bool HistoryFile.Close(int hFile) {
   if (hFile <= 0)                      return(!catch("HistoryFile.Close(1)  invalid file handle "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("HistoryFile.Close(2)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR));
      if (hf.hFile[hFile] == 0)         return(!catch("HistoryFile.Close(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR));
   }
   else {
      hf.hFile.valid = -1;
   }

   if (hf.hFile[hFile] < 0)                                          // Datei ist bereits geschlossen worden
      return(true);

   int error = GetLastError();
   if (IsError(error))
      return(!catch("HistoryFile.Close(4)", error));

   FileClose(hFile);
   hf.hFile[hFile] = -1;

   error = GetLastError();
   if (error == ERR_INVALID_PARAMETER) {                   // Datei war bereits geschlossen: kann ignoriert werden
   }
   else if (IsError(error)) {
      return(!catch("HistoryFile.Close(5)", error));
   }
   return(true);
}


/**
 * Setzt die Gr��e der internen HistoryFile-Datenarrays auf den angegebenen Wert.
 *
 * @param  int size - neue Gr��e
 *
 * @return int - neue Gr��e der Arrays
 *
private*/ int __hf.ResizeArrays(int size) {
   int oldSize = ArraySize(hf.hFile);

   if (size != oldSize) {
      ArrayResize(hf.hFile,                    size);
      ArrayResize(hf.name,                     size);
      ArrayResize(hf.read,                     size);
      ArrayResize(hf.write,                    size);
      ArrayResize(hf.size,                     size);

      ArrayResize(hf.header,                   size);
      ArrayResize(hf.symbol,                   size);
      ArrayResize(hf.period,                   size);
      ArrayResize(hf.periodSecs,               size);
      ArrayResize(hf.digits,                   size);

      ArrayResize(hf.bars,                     size);
      ArrayResize(hf.from,                     size);
      ArrayResize(hf.to,                       size);

      ArrayResize(hf.currentBar.offset,        size);
      ArrayResize(hf.currentBar.openTime,      size);
      ArrayResize(hf.currentBar.closeTime,     size);
      ArrayResize(hf.currentBar.nextCloseTime, size);
      ArrayResize(hf.currentBar.data,          size);

      ArrayResize(hf.tickBar.offset,           size);
      ArrayResize(hf.tickBar.openTime,         size);
      ArrayResize(hf.tickBar.closeTime,        size);
      ArrayResize(hf.tickBar.nextCloseTime,    size);
      ArrayResize(hf.tickBar.data,             size);
   }

   for (int i=size-1; i >= oldSize; i--) {                           // falls Arrays vergr��ert werden, neue Offsets initialisieren
      hf.currentBar.offset[i] = -1;
      hf.tickBar.offset   [i] = -1;
   }

   return(size);
}


/**
 * Setzt die Gr��e der internen History-Datenarrays auf den angegebenen Wert.
 *
 * @param  int size - neue Gr��e
 *
 * @return int - neue Gr��e der Arrays
 *
private*/ int __h.ResizeArrays(int size) {
   if (size != ArraySize(h.hHst)) {
      ArrayResize(h.hHst,        size);
      ArrayResize(h.symbol,      size);
      ArrayResize(h.description, size);
      ArrayResize(h.digits,      size);
      ArrayResize(h.hFile,       size);
   }
   return(size);
}


/**
 * Gibt den Namen der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return string - Dateiname oder Leerstring, falls ein Fehler auftrat
 */
string hf.Name(int hFile) {
   if (hFile <= 0)                      return(_EMPTY_STR(catch("hf.Name(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY_STR(catch("hf.Name(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY_STR(catch("hf.Name(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY_STR(catch("hf.Name(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.name[hFile]);
}


/**
 * Ob das Handle einer Historydatei Lesezugriff erlaubt.
 *
 * @param  int hFile - Dateihandle
 *
 * @return bool - Ergebnis oder FALSE, falls ein Fehler auftrat
 */
bool hf.Read(int hFile) {
   if (hFile <= 0)                      return(!catch("hf.Read(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("hf.Read(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(!catch("hf.Read(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR));
                                        return(!catch("hf.Read(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.read[hFile]);
}


/**
 * Ob das Handle einer Historydatei Schreibzugriff erlaubt.
 *
 * @param  int hFile - Dateihandle
 *
 * @return bool - Ergebnis oder FALSE, falls ein Fehler auftrat
 */
bool hf.Write(int hFile) {
   if (hFile <= 0)                      return(!catch("hf.Write(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(!catch("hf.Write(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(!catch("hf.Write(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR));
                                        return(!catch("hf.Write(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.write[hFile]);
}


/**
 * Gibt die aktuelle Gr��e der zu einem Handle geh�renden Historydatei zur�ck (inkl. noch ungeschriebener Daten im Schreibpuffer).
 *
 * @param  int hFile - Dateihandle
 *
 * @return int - Gr��e oder -1 (EMPTY), falls ein Fehler auftrat
 */
int hf.Size(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.Size(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.Size(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.Size(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.Size(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.size[hFile]);
}


/**
 * Gibt die aktuelle Anzahl der Bars der zu einem Handle geh�renden Historydatei zur�ck (inkl. noch ungeschriebener Daten im Schreibpuffer).
 *
 * @param  int hFile - Dateihandle
 *
 * @return int - Anzahl oder -1 (EMPTY), falls ein Fehler auftrat
 */
int hf.Bars(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.Bars(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.Bars(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.Bars(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.Bars(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.bars[hFile]);
}


/**
 * Gibt den Zeitpunkt der �ltesten Bar der zu einem Handle geh�renden Historydatei zur�ck (inkl. noch ungeschriebener Daten im Schreibpuffer).
 *
 * @param  int hFile - Dateihandle
 *
 * @return datetime - Zeitpunkt oder -1 (EMPTY), falls ein Fehler auftrat
 */
datetime hf.From(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.From(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.From(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.From(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.From(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.from[hFile]);
}


/**
 * Gibt den Zeitpunkt der j�ngsten Bar der zu einem Handle geh�renden Historydatei zur�ck (inkl. noch ungeschriebener Daten im Schreibpuffer).
 *
 * @param  int hFile - Dateihandle
 *
 * @return datetime - Zeitpunkt oder -1 (EMPTY), falls ein Fehler auftrat
 */
datetime hf.To(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.To(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.To(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.To(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.To(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.to[hFile]);
}


/**
 * Gibt den Header der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile   - Dateihandle
 * @param  int array[] - Array zur Aufnahme der Headerdaten
 *
 * @return int - Fehlerstatus
 */
int hf.Header(int hFile, int array[]) {
   if (hFile <= 0)                      return(catch("hf.Header(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(catch("hf.Header(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(catch("hf.Header(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR));
                                        return(catch("hf.Header(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR));
      }
      hf.hFile.valid = hFile;
   }
   if (ArrayDimension(array) > 1)       return(catch("hf.Header(5)  too many dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS));

   ArrayResize(array, HISTORY_HEADER.intSize);                       // entspricht: array = hf.header[hFile];
   int src  = GetBufferAddress(hf.header) + hFile*HISTORY_HEADER.size;
   int dest = GetBufferAddress(array);
   CopyMemory(dest, src, HISTORY_HEADER.size);
   return(NO_ERROR);
}


/**
 * Gibt die Formatversion der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return int - Version oder NULL, falls ein Fehler auftrat
 */
int hf.Version(int hFile) {
   if (hFile <= 0)                      return(_NULL(catch("hf.Version(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_NULL(catch("hf.Version(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_NULL(catch("hf.Version(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_NULL(catch("hf.Version(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hhs.Version(hf.header, hFile));
}


/**
 * Gibt das Symbol der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return string - Symbol oder Leerstring, falls ein Fehler auftrat
 */
string hf.Symbol(int hFile) {
   if (hFile <= 0)                      return(_EMPTY_STR(catch("hf.Symbol(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY_STR(catch("hf.Symbol(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY_STR(catch("hf.Symbol(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY_STR(catch("hf.Symbol(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.symbol[hFile]);
}


/**
 * Gibt die Beschreibung der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return string - Beschreibung oder Leerstring, falls ein Fehler auftrat
 */
string hf.Description(int hFile) {
   if (hFile <= 0)                      return(_EMPTY_STR(catch("hf.Description(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY_STR(catch("hf.Description(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY_STR(catch("hf.Description(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY_STR(catch("hf.Description(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hhs.Description(hf.header, hFile));
}


/**
 * Gibt den Timeframe der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return int - Timeframe oder NULL, falls ein Fehler auftrat
 */
int hf.Period(int hFile) {
   if (hFile <= 0)                      return(_NULL(catch("hf.Period(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_NULL(catch("hf.Period(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_NULL(catch("hf.Period(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_NULL(catch("hf.Period(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.period[hFile]);
}


/**
 * Gibt die Anzahl der Digits der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return int - Digits oder -1 (EMPTY), falls ein Fehler auftrat
 */
int hf.Digits(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.Digits(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.Digits(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.Digits(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.Digits(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hf.digits[hFile]);
}


/**
 * Gibt die DB-Version der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return datetime - Versions-Zeitpunkt oder -1 (EMPTY), falls ein Fehler auftrat
 */
int hf.DbVersion(int hFile) {
   if (hFile <= 0)                      return(_EMPTY(catch("hf.DbVersion(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.DbVersion(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.DbVersion(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.DbVersion(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hhs.DbVersion(hf.header, hFile));
}


/**
 * Gibt die vorherige DB-Version der zu einem Handle geh�renden Historydatei zur�ck.
 *
 * @param  int hFile - Dateihandle
 *
 * @return datetime - Versions-Zeitpunkt oder -1 (EMPTY), falls ein Fehler auftrat
 */
int hf.PrevDbVersion(int hFile) {
   // 2 oder mehr Tests
   if (hFile <= 0)                      return(_EMPTY(catch("hf.PrevDbVersion(1)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
   if (hFile != hf.hFile.valid) {
      if (hFile >= ArraySize(hf.hFile)) return(_EMPTY(catch("hf.PrevDbVersion(2)  invalid or unknown file handle "+ hFile, ERR_INVALID_PARAMETER)));
      if (hf.hFile[hFile] <= 0) {
         if (hf.hFile[hFile] == 0)      return(_EMPTY(catch("hf.PrevDbVersion(3)  unknown file handle "+ hFile, ERR_RUNTIME_ERROR)));
                                        return(_EMPTY(catch("hf.PrevDbVersion(4)  closed file handle "+ hFile, ERR_RUNTIME_ERROR)));
      }
      hf.hFile.valid = hFile;
   }
   return(hhs.PrevDbVersion(hf.header, hFile));
}


/**
 * Schlie�t alle noch offenen Dateien.
 *
 * @param  bool warn - ob f�r noch offene Dateien eine Warnung ausgegeben werden soll (default: nein)
 *
 * @return bool - Erfolgsstatus
 */
bool History.CloseFiles(bool warn=false) {
   warn = warn!=0;

   int error, size=ArraySize(hf.hFile);

   for (int i=0; i < size; i++) {
      if (hf.hFile[i] > 0) {
         if (warn) warn(StringConcatenate("History.CloseFiles()  open file handle "+ hf.hFile[i] +" found: \"", hf.name[i], "\""));

         if (!HistoryFile.Close(hf.hFile[i]))
            error = last_error;
      }
   }
   return(!error);
}


/**
 * Wird nur im Tester aus Library::init() aufgerufen, um alle verwendeten globalen Arrays zur�ckzusetzen (EA-Bugfix).
 */
void Tester.ResetGlobalArrays() {
   ArrayResize(stack.orderSelections      , 0);

   // Daten einzelner HistoryFiles
   ArrayResize(hf.hFile                   , 0);
   ArrayResize(hf.name                    , 0);
   ArrayResize(hf.read                    , 0);
   ArrayResize(hf.write                   , 0);
   ArrayResize(hf.size                    , 0);

   ArrayResize(hf.header                  , 0);
   ArrayResize(hf.symbol                  , 0);
   ArrayResize(hf.period                  , 0);
   ArrayResize(hf.periodSecs              , 0);
   ArrayResize(hf.digits                  , 0);

   ArrayResize(hf.bars                    , 0);
   ArrayResize(hf.from                    , 0);
   ArrayResize(hf.to                      , 0);

   // Cache der aktuellen Bar
   ArrayResize(hf.currentBar.offset       , 0);
   ArrayResize(hf.currentBar.openTime     , 0);
   ArrayResize(hf.currentBar.closeTime    , 0);
   ArrayResize(hf.currentBar.nextCloseTime, 0);
   ArrayResize(hf.currentBar.data         , 0);

   // Ticks einer ungespeicherten Bar
   ArrayResize(hf.tickBar.offset          , 0);
   ArrayResize(hf.tickBar.openTime        , 0);
   ArrayResize(hf.tickBar.closeTime       , 0);
   ArrayResize(hf.tickBar.nextCloseTime   , 0);
   ArrayResize(hf.tickBar.data            , 0);

   // Daten einzelner History-Sets
   ArrayResize(h.hHst                     , 0);
   ArrayResize(h.symbol                   , 0);
   ArrayResize(h.description              , 0);
   ArrayResize(h.digits                   , 0);
   ArrayResize(h.hFile                    , 0);
 //ArrayResize(h.periods...                           // hat Initializer und wird nicht modifiziert
}
