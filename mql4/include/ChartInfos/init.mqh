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

   // Pr�fen, ob wir auf einem LFX-Chart laufen und wenn ja, LFX-Details initialisieren
   if      (StringStartsWith(Symbol(), "LFX")) { isLfxChart = true; lfxCurrency = StringRight(Symbol(), -3); }
   else if (StringEndsWith  (Symbol(), "LFX")) { isLfxChart = true; lfxCurrency = StringLeft (Symbol(), -3); }
   else                                        { isLfxChart = false;                                         }
   if (isLfxChart) {
      lfxCurrencyId = GetCurrencyId(lfxCurrency);
      if (!LFX.CheckAccount())
         return(last_error);
   }

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
      // offene Remote-Orders einlesen
      LFX.GetOrders(lfxOrders);

      // in Library gespeicherte Remote-Positionsdaten restaurieren, k�nnen aktueller als die gelesenen Remote-Orderdaten sein
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
      // in Library gespeicherte Remote-Orders restaurieren
      int error = ChartInfos.CopyLfxOrders(false, lfxOrders);
      if (IsError(error))
         return(SetLastError(error));

      // in Library gespeicherte Remote-Positionsdaten restaurieren, k�nnen aktueller als die Remote-Orderdaten sein
      error = ChartInfos.CopyRemotePositions(false, remote.position.tickets, remote.position.types, remote.position.data);
      if (IsError(error))
         return(SetLastError(error));
   }
   return(NO_ERROR);
}


/**
 * Kein UninitializeReason gesetzt.
 *
 * au�erhalb iCustom(): wenn Template mit Indikator darin geladen wird (auch bei Terminal-Start und im Tester bei VisualMode=On|Off), kein Input-Dialog
 * innerhalb iCustom(): in allen init()-F�llen, kein Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitUndefined() {
   if (isLfxChart) {
      // offene Remote-Orders einlesen
      LFX.GetOrders(lfxOrders);
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
      // offene Remote-Orders einlesen
      LFX.GetOrders(lfxOrders);
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
