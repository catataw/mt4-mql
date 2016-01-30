/**
 * Ermittelt die Anzahl der seit dem letzten Tick modifizierten Bars einer Datenreihe. Entspricht der manuellen Ermittlung
 * der Variable ChangedBars f�r eine andere als die aktuelle Datenreihe.
 *
 * @param  string symbol    - Symbol der zu untersuchenden Zeitreihe  (NULL = aktuelles Symbol)
 * @param  int    period    - Periode der zu untersuchenden Zeitreihe (NULL = aktuelle Periode)
 * @param  int    execFlags - Ausf�hrungssteuerung: Flags der Fehler, die still gesetzt werden sollen (default: keine)
 *
 * @return int - Baranzahl oder -1 (EMPTY), falls ein Fehler auftrat
 *
 *
 * @throws ERR_SERIES_NOT_AVAILABLE - Wird still gesetzt, wenn im Parameter execFlags das Flag MUTE_ERR_SERIES_NOT_AVAILABLE gesetzt ist.
 */
int iChangedBars(string symbol/*=NULL*/, int period/*=NULL*/, int execFlags=NULL) {
   if (__WHEREAMI__ != RF_START) return(0);                          // in init() oder deinit()
   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();

   // W�hrend der Verarbeitung eines Ticks geben die Bar-Funktionen und Bar-Variablen immer dieselbe Anzahl zur�ck, auch wenn die reale
   // Datenreihe sich bereits ge�ndert haben sollte (in einem anderen Thread).
   // Ein Programm, das w�hrend desselben Ticks mehrmals iBars() aufruft, wird w�hrend dieses Ticks also immer dieselbe Anzahl Bars "sehen".

   // TODO: - statische Variablen in Library speichern, um Timeframewechsel zu �berdauern
   //       - statische Variablen bei Accountwechsel zur�cksetzen

   #define I_CB.tick             0                                   // Tick                     (beim letzten Aufruf)
   #define I_CB.bars             1                                   // Anzahl aller Bars        (beim letzten Aufruf)
   #define I_CB.changedBars      2                                   // Anzahl der ChangedBars   (beim letzten Aufruf)
   #define I_CB.oldestBarTime    3                                   // Zeit der �ltesten Bar    (beim letzten Aufruf)
   #define I_CB.newestBarTime    4                                   // Zeit der neuesten Bar    (beim letzten Aufruf)


   // (1) Die Speicherung der statischen Daten je Parameterkombination "Symbol,Periode" erm�glicht den parallelen Aufruf f�r mehrere Datenreihen.
   string keys[];
   int    last[][5];
   int    keysSize = ArraySize(keys);
   string key = StringConcatenate(symbol, ",", period);              // "Hash" der aktuellen Parameterkombination

   for (int i=0; i < keysSize; i++) {
      if (keys[i] == key)
         break;
   }
   if (i == keysSize) {                                              // Schl�ssel nicht gefunden: erster Aufruf f�r Symbol,Periode
      ArrayResize(keys, keysSize+1);
      ArrayResize(last, keysSize+1);
      keys[i] = key;                                                 // Schl�ssel hinzuf�gen
      last[i][I_CB.tick         ] = -1;                              // last[] initialisieren
      last[i][I_CB.bars         ] = -1;
      last[i][I_CB.changedBars  ] = -1;
      last[i][I_CB.oldestBarTime] =  0;
      last[i][I_CB.newestBarTime] =  0;
   }
   // Index i zeigt hier immer auf den aktuellen Datensatz


   // (2) Mehrfachaufruf f�r eine Datenreihe innerhalb desselben Ticks
   if (Tick == last[i][I_CB.tick])
      return(last[i][I_CB.changedBars]);


   /*
   int iBars(symbol, period);

      - Beim ersten Zugriff auf eine leere Datenreihe wird statt ERR_SERIES_NOT_AVAILABLE gew�hnlich ERS_HISTORY_UPDATE gesetzt.
      - Bei weiteren Zugriffen auf eine leere Datenreihe wird ERR_SERIES_NOT_AVAILABLE gesetzt.
      - Ohne Server-Connection ist nach Recompilation und bei fehlenden Daten u.U. gar kein Fehler gesetzt.
   */

   // (3) ChangedBars ermitteln
   int bars  = iBars(symbol, period);
   int error = GetLastError();

   if (!bars || error) {                                             // Da immer beide Bedingungen gepr�ft werden m�ssen, braucht das ODER nicht optimiert werden.
      if (!bars || error!=ERS_HISTORY_UPDATE) {
         if (!error || error==ERS_HISTORY_UPDATE)
            error = ERR_SERIES_NOT_AVAILABLE;
         if (error==ERR_SERIES_NOT_AVAILABLE && execFlags & MUTE_ERR_SERIES_NOT_AVAILABLE)
            return(_EMPTY(SetLastError(error)));                                                                           // leise
         return(_EMPTY(catch("iChangedBars(1)->iBars("+ symbol +","+ PeriodDescription(period) +") => "+ bars, error)));   // laut
      }
   }
   // bars ist hier immer gr��er 0

   datetime oldestBarTime = iTime(symbol, period, bars-1);
   datetime newestBarTime = iTime(symbol, period, 0     );
   int      changedBars;

   if (last[i][I_CB.bars]==-1) {                        changedBars = bars;                           // erster Zugriff auf die Zeitreihe
   }
   else if (bars==last[i][I_CB.bars] && oldestBarTime==last[i][I_CB.oldestBarTime]) {                 // Baranzahl gleich und �lteste Bar noch dieselbe
                                                        changedBars = 1;                              // normaler Tick (mit/ohne L�cke) oder synthetischer/sonstiger Tick: iVolume()
   }                                                                                                  // kann nicht zur Unterscheidung zwischen changedBars=0|1 verwendet werden
   else {
      if (bars == last[i][I_CB.bars])                                                                 // Die letzte Bar hat sich ge�ndert, Bars wurden hinten "hinausgeschoben".
         warn("iChangedBars(2)  bars==last.bars = "+ bars +" (did we hit MAX_CHART_BARS?)");          // In diesem Fall mu� die Bar mit last.newestBarTime gesucht und der Wert von
                                                                                                      // changedBars daraus abgeleitet werden.
      if (newestBarTime != last[i][I_CB.newestBarTime]) changedBars = bars - last[i][I_CB.bars] + 1;  // neue Bars zu Beginn hinzugekommen
      else                                              changedBars = bars;                           // neue Bars in L�cke eingef�gt: nicht eindeutig => alle als modifiziert melden
   }

   last[i][I_CB.tick         ] = Tick;
   last[i][I_CB.bars         ] = bars;
   last[i][I_CB.changedBars  ] = changedBars;
   last[i][I_CB.oldestBarTime] = oldestBarTime;
   last[i][I_CB.newestBarTime] = newestBarTime;

   return(changedBars);
}
