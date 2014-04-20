/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   RemoveChartObjects();
   StopQuickChannels();
   return(last_error);
}


/**
 * au�erhalb iCustom(): bei Parameter�nderung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // vorhandene Remote-Positionsdaten in Library speichern
   int error = ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data);
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
   // vorhandene Remote-Positionsdaten in Library speichern
   int error = ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data);
   if (IsError(error))
      return(SetLastError(error));
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen
 * innerhalb iCustom(): in allen deinit()-F�llen
 *
 * @return int - Fehlerstatus
 *
int onDeinitRemove() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): bei Recompilation
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   // Remote-Positionsdaten in "remote_positions.ini" speichern
   return(NO_ERROR);
}


/**
 * Deinitialisierung Postprocessing
 *
 * @return int - Fehlerstatus
 *
int afterDeinit() {
   return(NO_ERROR);
}
*/
