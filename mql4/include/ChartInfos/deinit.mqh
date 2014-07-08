/**
 * Deinitialisierung Preprocessing-Hook
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   RemoveChartObjects();
   QC.StopChannels();
   return(last_error);
}


/**
 * au�erhalb iCustom(): bei Parameter�nderung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   string symbol[1]; symbol[0] = Symbol();

   // LFX-Orders in Library zwischenspeichern, um aktuellen P/L nicht zu verlieren
   int error = ChartInfos.CopyLfxOrders(true, symbol, lfxOrders);
   if (IsError(error))
      return(SetLastError(error));
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): bei Symbol- oder Timeframewechsel
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   string symbol[1]; symbol[0] = Symbol();

   // LFX-Orders in Library zwischenspeichern, um aktuellen P/L nicht zu verlieren
   int error = ChartInfos.CopyLfxOrders(true, symbol, lfxOrders);
   if (IsError(error))
      return(SetLastError(error));
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen, auch vorm Laden eines Profils oder Templates
 * innerhalb iCustom(): in allen deinit()-F�llen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // LFX-Orders in Datei speichern, um aktuellen P/L nicht zu verlieren
   if (!LFX.SaveOrders(lfxOrders))
         return(last_error);
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): bei Recompilation
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   // LFX-Orders in Datei speichern, um aktuellen P/L nicht zu verlieren
   if (!LFX.SaveOrders(lfxOrders))
         return(last_error);
   return(NO_ERROR);
}


/**
 * Deinitialisierung Postprocessing-Hook
 *
 * @return int - Fehlerstatus
 *
int afterDeinit() {
   return(NO_ERROR);
}
*/
