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
 * @throws ERS_HISTORY_UPDATE       - Wird still gesetzt, wenn im Parameter execFlags das Flag MUTE_ERS_HISTORY_UPDATE gesetzt ist. In diesem Fall wird der
 *                                    regul�re Wert der modifizierten Bars zur�ckgegeben. Anderenfalls ist der R�ckgabewert -1 (Fehler).
 *
 * @throws ERR_SERIES_NOT_AVAILABLE - Wird still gesetzt, wenn im Parameter execFlags das Flag MUTE_ERR_SERIES_NOT_AVAILABLE gesetzt ist. Der R�ckgabewert
 *                                    der Funktion bei Auftreten dieses Fehlers ist unabh�ngig von diesem Flag immer -1 (Fehler).
 */
int iChangedBars(string symbol/*=NULL*/, int period/*=NULL*/, int execFlags=NULL) {
   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();
   /*
   TODO:
   -----
   - statische Variablen m�ssen je Symbol und Periode zwichengespeichert werden
   - statische Variablen in Library speichern, um Timeframewechsel zu �berdauern
   - statische Variablen bei Accountwechsel zur�cksetzen
   */

   static int      prev.bars         = -1;
   static datetime prev.lastBarTime  =  0;
   static datetime prev.firstBarTime =  0;

   int bars  = iBars(symbol, period);
   int error = GetLastError();

   // Fehlerbehandlung je nach execFlags
   if (!bars || error) {
      if (!bars && error!=ERR_SERIES_NOT_AVAILABLE) {
         // - Beim ersten Zugriff auf eine leere Datenreihe wird statt ERR_SERIES_NOT_AVAILABLE gew�hnlich ERS_HISTORY_UPDATE gesetzt.
         // - Bei weiteren Zugriffen auf eine leere Datenreihe wird ERR_SERIES_NOT_AVAILABLE gesetzt.
         // - Ohne Server-Connection ist nach Recompilation jedoch u.U. gar kein Fehler gesetzt (trotz fehlender Daten).
         if (!error || error==ERS_HISTORY_UPDATE) error = ERR_SERIES_NOT_AVAILABLE;                // NO_ERROR und ERS_HISTORY_UPDATE �berschreiben
         else warn("iChangedBars(1: "+ symbol +","+ PeriodDescription(period) +") => bars="+ bars, error);
      }

      if (error == ERR_SERIES_NOT_AVAILABLE) {
         prev.bars = 0;
         if (!execFlags & MUTE_ERR_SERIES_NOT_AVAILABLE) return(_EMPTY(catch("iChangedBars(2: "+ symbol +","+ PeriodDescription(period) +")", error)));
         else                                            return(_EMPTY(SetLastError(error)));
      }
      if (error!=ERS_HISTORY_UPDATE || !execFlags & MUTE_ERS_HISTORY_UPDATE) {
         prev.bars = bars;                               return(_EMPTY(catch("iChangedBars(3: "+ symbol +","+ PeriodDescription(period) +")", error)));
      }
      SetLastError(error);                                                                         // ERS_HISTORY_UPDATE still setzen und fortfahren
   }
   // bars ist hier immer gr��er 0

   datetime lastBarTime  = iTime(symbol, period, bars-1);
   datetime firstBarTime = iTime(symbol, period, 0     );
   int      changedBars;

   if      (error==ERS_HISTORY_UPDATE || prev.bars==-1)       changedBars = bars;                  // erster Zugriff auf die Zeitreihe
   else if (bars==prev.bars && lastBarTime==prev.lastBarTime) changedBars = 1;                     // Baranzahl gleich und �lteste Bar noch dieselbe = normaler Tick (mit/ohne L�cke)
   else if (firstBarTime != prev.firstBarTime)                changedBars = bars - prev.bars + 1;  // neue Bars zu Beginn hinzugekommen
   else                                                       changedBars = bars;                  // neue Bars in L�cke eingef�gt (nicht eindeutig => alle als modifiziert melden)

   prev.bars         = bars;
   prev.lastBarTime  = lastBarTime;
   prev.firstBarTime = firstBarTime;

   error = GetLastError();
   if (!error)
      return(changedBars);
   return(_EMPTY(catch("iChangedBars(4: "+ symbol +","+ PeriodDescription(period) +")", error)));
}
