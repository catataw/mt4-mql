/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // Datenanzeige ausschalten
   SetIndexLabel(0, NULL);

   // Konfiguration f�r Preisanzeige auswerten
   string price = "bid";
   if (!IsVisualMode())                                              // im Tester wird immer PRICE_BID verwendet (ist ausreichend und schneller)
      price = StringToLower(GetGlobalConfigString("AppliedPrice", StdSymbol(), "median"));
   if      (price == "bid"   ) appliedPrice = PRICE_BID;
   else if (price == "ask"   ) appliedPrice = PRICE_ASK;
   else if (price == "median") appliedPrice = PRICE_MEDIAN;
   else return(catch("onInit(1)   invalid configuration value [AppliedPrice], "+ StdSymbol() +" = \""+ price +"\"", ERR_INVALID_CONFIG_PARAMVALUE));

   // Pr�fen, ob wir auf einem LFX-Chart laufen und wenn ja, LFX-Account-Details initialisieren
   isLfxChart = (StringLeft(Symbol(), 3)=="LFX" || StringRight(Symbol(), 3)=="LFX");
   if (isLfxChart) /*&&*/ if (!LFX.CheckAccount())
      return(last_error);

   // Label erzeugen
   CreateLabels();
   return(catch("onInit(2)"));
}


/**
 * au�erhalb iCustom(): erste Parameter-Eingabe bei neuem Indikator, Parameter-Wechsel bei vorhandenem Indikator (auch im Tester bei VisualMode=On), Input-Dialog
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onInitParameterChange() {
   if (isLfxChart) {
      // offene Remote-Tickets einlesen
      if (Symbol() == "AUDLFX") {
         /*LFX_ORDER*/int los[][LFX_ORDER.intSize];
         LFX.ReadOpenOrders(los);

         LFX_ORDER.toStr(los, true);
         ArrayResize(los, 0);
      }

      // in Library gespeicherte Remote-Ticketdaten restaurieren (k�nnen aktueller als (1) sein)
      int error = ChartInfos.CopyRemotePositions(false, remote.position.tickets, remote.position.types, remote.position.data);
      if (IsError(error))
         return(SetLastError(error));
   }
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): nach Symbol- oder Timeframe-Wechsel bei vorhandenem Indikator, kein Input-Dialog
 * innerhalb iCustom(): ?
 *
 * @return int - Fehlerstatus
 */
int onInitChartChange() {
   // bei Symbolwechsel
   // ???

   // bei Timeframe-Wechsel
   if (isLfxChart) {
      // entweder komplette offene Tickets in Library zwischenspeichern oder offene Tickets neu einlesen

      // in Library gespeicherte Remote-Ticketdaten restaurieren
      int error = ChartInfos.CopyRemotePositions(false, remote.position.tickets, remote.position.types, remote.position.data);
      if (IsError(error))
         return(SetLastError(error));
   }
   return(NO_ERROR);
}


/**
 * Kein UninitializeReason gesetzt.
 *
 * au�erhalb iCustom(): wenn Indikator im Template (auch bei Terminal-Start und im Tester bei VisualMode=On|Off), kein Input-Dialog
 * innerhalb iCustom(): in allen init()-F�llen, kein Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitUndefined() {
   if (isLfxChart) {
      // offene Remote-Tickets einlesen
      if (Symbol() == "AUDLFX") {
         /*LFX_ORDER*/int los[][LFX_ORDER.intSize];
         LFX.ReadOpenOrders(los);

         LFX_ORDER.toStr(los, true);
         ArrayResize(los, 0);
      }
   }
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): ???
 * innerhalb iCustom(): im Tester nach Test-Restart bei VisualMode=Off, kein Input-Dialog
 *
 * @return int - Fehlerstatus
 *
int onInitRemove() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): nach Recompilation, vorhandener Indikator, kein Input-Dialog
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onInitRecompile() {
   if (isLfxChart) {
      // offene Remote-Tickets einlesen
      if (Symbol() == "AUDLFX") {
         /*LFX_ORDER*/int los[][LFX_ORDER.intSize];
         LFX.ReadOpenOrders(los);

         LFX_ORDER.toStr(los, true);
         ArrayResize(los, 0);
      }
   }
   return(NO_ERROR);
}


/**
 * Initialisierung Postprocessing
 *
 * @return int - Fehlerstatus
 *
int afterInit() {
   return(NO_ERROR);
}
*/
