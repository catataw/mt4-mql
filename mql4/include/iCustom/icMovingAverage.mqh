/**
 * Berechnet den angegebenen Wert des Custom-Indikators "Moving Average" und gibt ihn zur�ck.
 *
 * @param  int    timeframe      - Timeframe, in dem der Indikator geladen wird
 * @param  string maPeriods      - Indikator-Parameter
 * @param  string maTimeframe    - Indikator-Parameter
 * @param  string maMethod       - Indikator-Parameter
 * @param  string maAppliedPrice - Indikator-Parameter
 * @param  int    iBuffer        - Bufferindex des zur�ckzugebenden Wertes
 * @param  int    iBar           - Barindex des zur�ckzugebenden Wertes
 *
 * @return double - Wert oder 0, falls ein Fehler auftrat
 *
 *
 * NOTE: In Headerdatei implementiert, da im Tester die Zeichenbuffer des aufgerufenen Indikators nach Testende nur dann gezeichnet werden,
 *       wenn der Aufruf von iCustom() direkt im Expert erfolgt (nicht jedoch bei Aufruf in einer Library).
 */
double icMovingAverage(int timeframe, string maPeriods, string maTimeframe, string maMethod, string maAppliedPrice, int iBuffer, int iBar) {
   if (IsLastError())
      return(0);

   int maMaxValues    = 10;                                          // mindestens 10 Werte berechnen, um vorherrschenden Trend korrekt zu detektieren
   int lpLocalContext = GetBufferAddress(__ExecutionContext);

   double value = iCustom(NULL, timeframe, "Moving Average",
                          maPeriods,                                 // MA.Periods
                          maTimeframe,                               // MA.Timeframe
                          maMethod,                                  // MA.Method
                          maAppliedPrice,                            // AppliedPrice
                          ForestGreen,                               // Color.UpTrend
                          Red,                                       // Color.DownTrend
                          0,                                         // Shift.H
                          0,                                         // Shift.V
                          maMaxValues,                               // Max.Values
                          "",                                        // ________________
                          lpLocalContext,                            // __SuperContext__
                          iBuffer, iBar);                            // throws ERS_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE

   int error = GetLastError();

   if (IsError(error)) {
      if (error != ERS_HISTORY_UPDATE)
         return(_NULL(catch("icMovingAverage(1)", error)));
      warn("icMovingAverage(2)   ERS_HISTORY_UPDATE (tick="+ Tick +")");   // TODO: geladene Bars pr�fen
   }

   error = ec.LastError(__ExecutionContext);                               // TODO: Synchronisation von Original und Kopie sicherstellen
   if (!error)
      return(value);
   return(_NULL(SetLastError(error)));
}
