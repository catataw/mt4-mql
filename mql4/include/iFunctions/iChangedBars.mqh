/**
 * Ermittelt die Anzahl der seit dem letzten Tick modifizierten Bars einer Datenreihe. Entspricht der manuellen Ermittlung
 * der Variable ChangedBars f�r eine andere als die aktuelle Datenreihe.
 *
 * @param  string symbol    - Symbol der zu untersuchenden Zeitreihe  (NULL = aktuelles Symbol)
 * @param  int    period    - Periode der zu untersuchenden Zeitreihe (NULL = aktuelle Periode)
 * @param  int    execFlags - Ausf�hrungssteuerung: Flags der Fehler, die still gesetzt werden sollen (default: keine)
 *
 * @return int - Baranzahl oder EMPTY (-1), falls ein Fehler auftrat
 *
 *
 * @throws ERR_SERIES_NOT_AVAILABLE - Wird still gesetzt, wenn im Parameter execFlags das Flag MUTE_ERR_SERIES_NOT_AVAILABLE gesetzt ist.
 */
int iChangedBars(string symbol/*=NULL*/, int period/*=NULL*/, int execFlags=NULL) {
   if (__WHEREAMI__ != FUNC_START) return(0);                        // in init() oder deinit()
   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();

   // Die Anzahl der Bars einer Datenreihe �ndert sich innerhalb eines Ticks nicht, auch wenn die reale Datenreihe selbst sich �ndern sollte.
   // Ein Programm, das w�hrend desselben Ticks mehrmals iBars() aufruft, wird w�hrend dieses Ticks immer dieselbe konstante Anzahl Bars "sehen".

   // TODO: - statische Variablen in Library speichern, um Timeframewechsel zu �berdauern
   //       - statische Variablen bei Accountwechsel zur�cksetzen

   #define I_TICK             0                                      // Tick                   (beim letzten Aufruf)
   #define I_BARS             1                                      // Anzahl aller Bars      (beim letzten Aufruf)
   #define I_CHANGED_BARS     2                                      // Anzahl der ChangedBars (beim letzten Aufruf)
   #define I_FIRST_BAR_TIME   3                                      // Zeit der j�ngsten Bar  (beim letzten Aufruf)
   #define I_LAST_BAR_TIME    4                                      // Zeit der �ltestens Bar (beim letzten Aufruf)


   // (1) Speicherung der statischen Daten je Parameterkombination "Symbol,Periode" erm�glicht den parallelen Aufruf f�r mehrere Datenreihen
   string keys[];
   int    prev[][5];
   int    keysSize = ArraySize(keys);
   string key = StringConcatenate(symbol, ",", period);              // "Hash" der aktuellen Parameterkombination

   for (int i=0; i < keysSize; i++) {
      if (keys[i] == key)
         break;
   }
   if (i == keysSize) {                                              // Schl�ssel nicht gefunden: erster Aufruf f�r Symbol,Periode
      ArrayResize(keys, keysSize+1);
      ArrayResize(prev, keysSize+1);
      keys[i] = key;                                                 // Schl�ssel hinzuf�gen
      prev[i][I_TICK          ] = -1;
      prev[i][I_BARS          ] = -1;
      prev[i][I_CHANGED_BARS  ] = -1;
      prev[i][I_FIRST_BAR_TIME] =  0;
      prev[i][I_LAST_BAR_TIME ] =  0;
   }
   // Index i zeigt hier immer auf den aktuellen Datensatz


   // (2) Mehrfachaufruf f�r eine Datenreihe innerhalb desselben Ticks
   if (Tick == prev[i][I_TICK])
      return(prev[i][I_CHANGED_BARS]);


   // (3) ChangedBars ermitteln
   int bars  = iBars(symbol, period);
   int error = GetLastError();

   // - Beim ersten Zugriff auf eine leere Datenreihe wird statt ERR_SERIES_NOT_AVAILABLE gew�hnlich ERS_HISTORY_UPDATE gesetzt.
   // - Bei weiteren Zugriffen auf eine leere Datenreihe wird ERR_SERIES_NOT_AVAILABLE gesetzt.
   // - Ohne Server-Connection ist nach Recompilation jedoch u.U. gar kein Fehler gesetzt (trotz fehlender Daten).
   if (!bars || error) {                                             // in jedem Fall m�ssen immer beide Bedingungen gepr�ft werden, eine Optimierung w�rde also nichts bringen
      if (!bars || error!=ERS_HISTORY_UPDATE) {
         if (!error || error==ERS_HISTORY_UPDATE)
            error = ERR_SERIES_NOT_AVAILABLE;
         if (error==ERR_SERIES_NOT_AVAILABLE && execFlags & MUTE_ERR_SERIES_NOT_AVAILABLE)
            return(_EMPTY(SetLastError(error)));                                                         // leise
         return(_EMPTY(catch("iChangedBars(1: "+ symbol +","+ PeriodDescription(period) +")", error)));  // laut
      }
   }
   // bars ist hier immer gr��er 0

   datetime firstBarTime = iTime(symbol, period, 0     );
   datetime lastBarTime  = iTime(symbol, period, bars-1);
   int      changedBars;

   if      (prev[i][I_BARS]==-1)                                            changedBars = bars;    // erster Zugriff auf die Zeitreihe
   else if (bars==prev[i][I_BARS] && lastBarTime==prev[i][I_LAST_BAR_TIME]) changedBars = 1;       // Baranzahl gleich und �lteste Bar noch dieselbe = normaler Tick (mit/ohne L�cke)
   else {
      if (bars == prev[i][I_BARS])                                                                 // Wenn dies passiert (im Tester?) und Bars "hinten hinausgeschoben" wurden, mu� die Bar
         warn("iChangedBars(2)  bars==prev.bars = "+ bars +" (did we hit MAX_CHART_BARS?)");       // mit prev.firstBarTime gesucht und der Wert von changedBars daraus abgeleitet werden.

      if (firstBarTime != prev[i][I_FIRST_BAR_TIME]) changedBars = bars - prev[i][I_BARS] + 1;     // neue Bars zu Beginn hinzugekommen
      else                                           changedBars = bars;                           // neue Bars in L�cke eingef�gt: nicht eindeutig => alle als modifiziert melden
   }

   prev[i][I_TICK          ] = Tick;
   prev[i][I_BARS          ] = bars;
   prev[i][I_CHANGED_BARS  ] = changedBars;
   prev[i][I_FIRST_BAR_TIME] = firstBarTime;
   prev[i][I_LAST_BAR_TIME ] = lastBarTime;

   return(changedBars);
}
