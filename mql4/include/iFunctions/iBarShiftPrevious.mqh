/**
 * Ermittelt den Bar-Offset eines Zeitpunktes innerhalb einer Datenreihe und gibt bei nicht existierender Bar die letzte
 * vorherige existierende Bar zur�ck.
 *
 * @param  string   symbol    - Symbol der zu untersuchenden Datenreihe  (NULL = aktuelles Symbol)
 * @param  int      period    - Periode der zu untersuchenden Datenreihe (NULL = aktuelle Periode)
 * @param  datetime time      - Zeitpunkt (Serverzeit)
 * @param  int      muteFlags - Ausf�hrungssteuerung: Flags der Fehler, die still gesetzt werden sollen (default: keine)
 *
 * @return int - Bar-Index oder -1, wenn keine entsprechende Bar existiert (Zeitpunkt ist zu alt f�r Datenreihe);
 *               EMPTY_VALUE, falls ein Fehler auftrat
 *
 *
 * @throws ERR_SERIES_NOT_AVAILABLE - Wird still gesetzt, wenn in muteFlags MUTE_ERR_SERIES_NOT_AVAILABLE gesetzt ist.
 *
 *
 * Note: Ein gemeldeter Status ERS_HISTORY_UPDATE ist kein Fehler und wird nicht weitergeleitet.
 *       Er ist nicht relevant f�r die momentan vorhandenen Daten.
 */
int iBarShiftPrevious(string symbol/*=NULL*/, int period/*=NULL*/, datetime time, int muteFlags=NULL) {
   if (symbol == "0")                                       // (string) NULL
      symbol = Symbol();
   if (time < 0) return(_EMPTY_VALUE(catch("iBarShiftPrevious(1)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER)));

   /*
   int iBarShift(symbol, period, time, exact=[true|false]);
      exact = TRUE : Gibt den Index der Bar zur�ck, die den angegebenen Zeitpunkt abdeckt oder, falls keine solche Bar existiert, -1.
      exact = FALSE: Gibt den Index der Bar zur�ck, die den angegebenen Zeitpunkt abdeckt oder, falls keine solche Bar existiert, den Index
                     der vorhergehenden, �lteren Bar. Existiert keine solche vorhergehende Bar, wird der Index der letzten Bar zur�ckgegeben.

      - Existieren keine entsprechenden Daten, gibt iBarShift() -1 zur�ck.
      - Ist das Symbol unbekannt (existiert nicht in "symbols.raw") oder ist der Timeframe kein Standard-Timeframe, meldet iBarShift() keinen Fehler.
      - Ist das Symbol bekannt, wird ggf. der Status ERS_HISTORY_UPDATE gemeldet.
   */

   // Datenreihe holen
   datetime times[];
   int bars  = ArrayCopySeries(times, MODE_TIME, symbol, period);//throws ERR_ARRAY_ERROR, wenn solche Daten (noch) nicht existieren
   int error = GetLastError();

   if (bars<=0 || error) {                                           // Da immer beide Bedingungen gepr�ft werden m�ssen, braucht das ODER nicht optimiert werden.
      if (bars<=0 || error!=ERS_HISTORY_UPDATE) {
         if (!error || error==ERS_HISTORY_UPDATE || error==ERR_ARRAY_ERROR)                                                         // aus ERR_ARRAY_ERROR wird ERR_SERIES_NOT_AVAILABLE
            error = ERR_SERIES_NOT_AVAILABLE;
         if (error==ERR_SERIES_NOT_AVAILABLE && muteFlags & MUTE_ERR_SERIES_NOT_AVAILABLE)
            return(_EMPTY_VALUE(SetLastError(error)));                                                                              // leise
         return(_EMPTY_VALUE(catch("iBarShiftPrevious(2)->ArrayCopySeries("+ symbol +","+ PeriodDescription(period) +") => "+ bars, error)));   // laut
      }
   }
   // bars ist hier immer gr��er 0


   // Bars �berpr�fen
   if (time < times[bars-1]) {
      int bar = -1;                                                  // Zeitpunkt ist zu alt f�r die Reihe
   }
   else {
      bar   = iBarShift(symbol, period, time, false);
      error = GetLastError();
      if (error!=NO_ERROR) /*&&*/ if (error!=ERS_HISTORY_UPDATE)
         return(_EMPTY_VALUE(catch("iBarShiftPrevious(3)->iBarShift("+ symbol +","+ PeriodDescription(period) +") => "+ bar, error)));
   }
   return(bar);
}
