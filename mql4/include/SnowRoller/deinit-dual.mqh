
/**
 * Parameter�nderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // nicht-statische Input-Parameter f�r Vergleich mit neuen Werten zwischenspeichern
   last.GridSize        = GridSize;
   last.LotSize         = LotSize;
   last.StartConditions = StringConcatenate(StartConditions, "");    // String-Inputvariablen sind C-Literale und read-only (siehe MQL.doc)
   last.StopConditions  = StringConcatenate(StopConditions,  "");
   return(-1);
}


/**
 * Symbol- oder Timeframewechsel
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // nicht-statische Input-Parameter zwischenspeichern
   return(onDeinitParameterChange());                                // entspricht onDeinitParameterChange()
}


/**
 * Im Tester: - Nach Bet�tigen des "Stop"-Buttons oder nach Chart->Close. Der "Stop"-Button des Testers kann nach Fehler oder Testabschlu�
 *              vom Code "bet�tigt" worden sein.
 *
 * Online:    - Chart wird geschlossen                  - oder -
 *            - Template wird neu geladen               - oder -
 *            - Terminal-Shutdown                       - oder -
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartClose() {
   // (1) Im Tester
   if (IsTesting()) {
      if (!last_error)
         SetLastError(ERR_CANCELLED_BY_USER);
      return(last_error);
   }

   // (2) Nicht im Tester
   StoreStickyStatus();                                              // f�r Terminal-Restart oder Profilwechsel
   return(last_error);
}


/**
 * Kein UninitializeReason gesetzt: nur im Tester nach regul�rem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   if (IsTesting()) {
      if (IsLastError())
         return(onDeinitChartClose());                               // entspricht gewaltsamen Ende
      return(last_error);
   }
   return(catch("onDeinitUndefined()", ERR_RUNTIME_ERROR));          // mal schaun, wer hier wann reintappt
}


/**
 * Nur Online: EA von Hand entfernt (Chart->Expert->Remove) oder neuer EA dr�bergeladen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   DeleteRegisteredObjects(NULL);
   return(NO_ERROR);
}


/**
 * Recompilation
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   StoreStickyStatus();
   return(-1);
}
