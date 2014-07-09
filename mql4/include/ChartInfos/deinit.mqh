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

   // LFX-Status in Library zwischenspeichern, um in init() Neuladen zu vermeiden
   if (ChartInfos.CopyLfxStatus(true, symbol, lfxOrders, lfxOrders.iVolatile, lfxOrders.dVolatile) == -1)
      return(SetLastError(ERR_RUNTIME_ERROR));
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

   // LFX-Status in Library zwischenspeichern, um in init() Neuladen zu vermeiden
   if (ChartInfos.CopyLfxStatus(true, symbol, lfxOrders, lfxOrders.iVolatile, lfxOrders.dVolatile) == -1)
      return(SetLastError(ERR_RUNTIME_ERROR));
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen, auch vorm Laden eines Profils oder Templates
 * innerhalb iCustom(): in allen deinit()-F�llen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // volatilen LFX-Status in globalen Variablen speichern
   if (!SaveVolatileLfxStatus())
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
   // volatilen LFX-Status in globalen Variablen speichern
   if (!SaveVolatileLfxStatus())
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
