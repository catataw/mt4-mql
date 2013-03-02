
/**
 * Parameter�nderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // nicht-statische Input-Parameter f�r Vergleich mit neuen Werten zwischenspeichern
   last.Sequence.ID             = StringConcatenate(Sequence.ID,             "");   // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
   last.Sequence.StatusLocation = StringConcatenate(Sequence.StatusLocation, "");
   last.GridDirection           = StringConcatenate(GridDirection,           "");
   last.GridSize                = GridSize;
   last.LotSize                 = LotSize;
   last.StartConditions         = StringConcatenate(StartConditions,         "");
   last.StopConditions          = StringConcatenate(StopConditions,          "");
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
      /**
       * !!! Vorsicht: Die start()-Funktion wurde gewaltsam beendet, die primitiven Variablen k�nnen Datenm�ll enthalten !!!
       *
       * Das Flag "Statusfile nicht l�schen" kann nicht �ber primitive Variablen oder den Chart kommuniziert werden.
       *  => Strings/Arrays testen (ansonsten globale Variable mit Thread-ID)
       */
      if (__STATUS_ERROR) {
         // Statusfile l�schen
         FileDelete(GetMqlStatusFileName());
         GetLastError();                                             // falls in FileDelete() ein Fehler auftrat

         // Der Fenstertitel des Testers kann nicht zur�ckgesetzt werden: SendMessage() f�hrt in deinit() zu Deadlock.
      }
      else {
         SetLastError(ERR_CANCELLED_BY_USER);
      }
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
      if (__STATUS_ERROR)
         return(onDeinitChartClose());                               // entspricht gewaltsamen Ende

      if (status==STATUS_WAITING || status==STATUS_PROGRESSING) {
         if (UpdateStatus(bNull, iNulls))
            StopSequence();                                          // ruft intern SaveStatus() auf
         ShowStatus();
      }
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
   RemoveChartObjects();
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
