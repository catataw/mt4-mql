/**
 * Deinitialisierung Preprocessing-Hook
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   DeleteRegisteredObjects(NULL);
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
   // LFX-Status in Library zwischenspeichern, um in init() Neuladen zu vermeiden
   if (ChartInfos.CopyLfxStatus(true, lfxOrders, lfxOrders.ivolatile, lfxOrders.dvolatile) == -1)
      return(SetLastError(ERR_RUNTIME_ERROR));

   // Fenster-Status  speichern
   if (!StoreWindowStatus())
      return(last_error);

   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): bei Symbol- oder Timeframewechsel
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // LFX-Status in Library zwischenspeichern, um in init() Neuladen zu vermeiden
   if (ChartInfos.CopyLfxStatus(true, lfxOrders, lfxOrders.ivolatile, lfxOrders.dvolatile) == -1)
      return(SetLastError(ERR_RUNTIME_ERROR));

   // Fenster-Status  speichern
   if (!StoreWindowStatus())
      return(last_error);

   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen, auch vorm Laden eines Profils oder Templates
 * innerhalb iCustom(): in allen deinit()-F�llen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // Terminal-Exit und bei Profilwechsel

   // volatilen LFX-Status in globalen Variablen speichern
   if (!SaveVolatileLfxStatus())
      return(last_error);

   // Fenster-Status  speichern
   if (!StoreWindowStatus())
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

   // Fenster-Status  speichern
   if (!StoreWindowStatus())
      return(last_error);

   return(NO_ERROR);
}


/**
 * Deinitialisierung Postprocessing-Hook
 *
 * @return int - Fehlerstatus
 */
int afterDeinit() {
   return(NO_ERROR);
}
