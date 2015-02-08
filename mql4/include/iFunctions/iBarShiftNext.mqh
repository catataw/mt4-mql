/**
 * Ermittelt den Bar-Offset eines Zeitpunktes innerhalb einer Datenreihe und gibt bei nicht existierender Bar die n�chste existierende Bar zur�ck.
 *
 * @param  string   symbol - Symbol der zu untersuchenden Datenreihe  (NULL = aktuelles Symbol)
 * @param  int      period - Periode der zu untersuchenden Datenreihe (NULL = aktuelle Periode)
 * @param  datetime time   - Zeitpunkt (Serverzeit)
 *
 * @return int - Bar-Index oder -1, wenn keine entsprechende Bar existiert (Zeitpunkt ist zu jung f�r die Datenreihe);
 *               EMPTY_VALUE, falls ein Fehler auftrat
 *
 *
 * Note: Ein ausgel�ster Status ERS_HISTORY_UPDATE wird nicht als Fehler interpretiert und nicht weitergeleitet.
 *       Er ist nicht relevant f�r die momentan vorhanden Daten.
 */
int iBarShiftNext(string symbol/*=NULL*/, int period/*=NULL*/, datetime time) {
   if (symbol == "0")                                       // (string) NULL
      symbol = Symbol();
   if (time < 0) return(_EMPTY_VALUE(catch("iBarShiftNext(1)  invalid parameter time = "+ time, ERR_INVALID_PARAMETER)));

   /*
   int iBarShift(symbol, period, time, exact=false);
      exact = TRUE : Gibt den Index der Bar zur�ck, die den angegebenen Zeitpunkt abdeckt oder, falls keine solche Bar existiert, -1.
      exact = FALSE: Gibt den Index der Bar zur�ck, die den angegebenen Zeitpunkt abdeckt oder, falls keine solche Bar existiert, den Index
                     der vorhergehenden, �lteren Bar. Existiert keine solche vorhergehende Bar, wird der Index der letzten Bar zur�ckgegeben.
   */
   int bar   = iBarShift(symbol, period, time, true);
   int error = GetLastError();
      if (error == ERS_HISTORY_UPDATE) error = NO_ERROR;
      if (error != NO_ERROR) return(_EMPTY_VALUE(catch("iBarShiftNext(2: "+ symbol +","+ PeriodDescription(period) +") => bar="+ bar, error)));
   if (bar != -1)
      return(bar);


   // exact war TRUE und bar==-1: keine abdeckende Bar gefunden
   // Datenreihe holen
   datetime times[];
   int bars = ArrayCopySeries(times, MODE_TIME, symbol, period);
   error    = GetLastError();
      if (error == ERS_HISTORY_UPDATE) error = NO_ERROR;
      if (error != NO_ERROR) return(_EMPTY_VALUE(catch("iBarShiftNext(3: "+ symbol +","+ PeriodDescription(period) +") => bars="+ bars, error)));
   if (!bars)                return(_EMPTY_VALUE(catch("iBarShiftNext(4: "+ symbol +","+ PeriodDescription(period) +") => bars="+ bars, ERR_SERIES_NOT_AVAILABLE)));


   // Bars manuell �berpr�fen
   if (time < times[bars-1]) {                                 // Zeitpunkt ist zu alt f�r die Reihe, die �lteste Bar zur�ckgeben
      bar = bars-1;
   }
   else if (time < times[0]) {                                 // Kursl�cke, die n�chste existierende Bar zur�ckgeben
      bar   = iBarShift(symbol, period, time) - 1;
      error = GetLastError();
      if (error == ERS_HISTORY_UPDATE) error = NO_ERROR;
      if (error != NO_ERROR) return(_EMPTY_VALUE(catch("iBarShiftNext(5: "+ symbol +","+ PeriodDescription(period) +") => bar="+ bar, error)));
   }
   else /*time > times[0]*/ {                                  // Zeitpunkt ist zu jung f�r die Reihe
      //bar ist und bleibt -1
   }
   return(bar);
}
