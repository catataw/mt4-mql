/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   RemoveChartObjects();

   // QuickChannel-Sender-Handles schlie�en
   for (int i=ArraySize(hLfxSenderChannels)-1; i >= 0; i--) {
      if (hLfxSenderChannels[i] != NULL) {
         if (!QC_ReleaseSender(hLfxSenderChannels[i]))
            catch("onDeinit(1)->MT4iQuickChannel::QC_ReleaseSender(hChannel=0x"+ IntToHexStr(hLfxSenderChannels[i]) +")   error closing QuickChannel sender: "+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
         hLfxSenderChannels[i] = NULL;
      }
   }

   // QuickChannel-Receiver-Handle schlie�en
   if (hLfxReceiverChannel != NULL) {
      if (!QC_ReleaseReceiver(hLfxReceiverChannel))
         catch("onDeinit(2)->MT4iQuickChannel::QC_ReleaseReceiver(hChannel=0x"+ IntToHexStr(hLfxReceiverChannel) +")   error releasing QuickChannel receiver: "+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
      hLfxReceiverChannel = NULL;
   }

   return(catch("onDeinit(3)"));
}


/**
 * au�erhalb iCustom(): vor Parameter�nderung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // vorhandene Remote-Positionsdaten in Library speichern
   if (!ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data))
      return(SetLastError(ERR_RUNTIME_ERROR));                       // Funktion liegt in stdlib2; Fehler kann dort nicht ausgelesen werden
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): vor Symbol- oder Timeframewechsel
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // vorhandene Remote-Positionsdaten in Library speichern
   if (!ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data))
      return(SetLastError(ERR_RUNTIME_ERROR));                       // Funktion liegt in stdlib2; Fehler kann dort nicht ausgelesen werden
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
 * au�erhalb iCustom(): nach Recompilation, vor Re-Initialisierung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   // vorhandene Remote-Positionsdaten im Chart speichern
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
