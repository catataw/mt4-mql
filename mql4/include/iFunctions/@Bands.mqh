/**
 * Indikator-Styles setzen. Workaround um diverse Terminalbugs (Farb-/Style�nderungen nach Recompilation), die erfordern, da�
 * die Styles normalerweise in init(), nach Recompilation jedoch in start() gesetzt werden m�ssen, um korrekt angezeigt zu
 * werden.
 */
void @Bands.SetIndicatorStyles(color mainColor, color bandsColor) {
   if (mainColor == CLR_NONE) SetIndexStyle(Bands.MODE_MAIN, DRAW_NONE, EMPTY, EMPTY, mainColor);
   else                       SetIndexStyle(Bands.MODE_MAIN, DRAW_LINE, EMPTY, EMPTY, mainColor);

   SetIndexStyle(Bands.MODE_UPPER, DRAW_LINE, EMPTY, EMPTY, bandsColor);
   SetIndexStyle(Bands.MODE_LOWER, DRAW_LINE, EMPTY, EMPTY, bandsColor);
}


/**
 * Aktualisiert die Legende eines Band-Indikators.
 */
void @Bands.UpdateLegend(string legendLabel, string legendDescription, color bandsColor, double currentUpperValue, double currentLowerValue) {
   static double lastUpperValue;                                        // Value des vorherigen Ticks

   currentUpperValue = NormalizeDouble(currentUpperValue, SubPipDigits);

   if (currentUpperValue != lastUpperValue) {
      ObjectSetText(legendLabel, StringConcatenate(legendDescription, "    ", NumberToStr(currentUpperValue, SubPipPriceFormat), " / ", NumberToStr(NormalizeDouble(currentLowerValue, SubPipDigits), SubPipPriceFormat)), 9, "Arial Fett", bandsColor);
      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)  // bei offenem Properties-Dialog oder Object::onDrag()
         return(catch("@Bands.UpdateLegend()", error));
   }
   lastUpperValue = currentUpperValue;
}
