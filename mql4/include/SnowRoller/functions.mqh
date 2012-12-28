
/**
 * Ermittelt ID und Status der im aktuellen Chart gemanagten Sequenzen.
 *
 * @param  string ids[]    - Array zur Aufnahme der gefundenen Sequenz-ID's
 * @param  int    status[] - Array zur Aufnahme der gefundenen Sequenz-Statuswerte
 *
 * @return bool - ob mindestens eine aktive Sequenz gefunden wurde
 */
bool FindChartSequences(string ids[], int status[]) {
   ArrayResize(ids,    0);
   ArrayResize(status, 0);

   string label = "SnowRoller.status";

   if (ObjectFind(label) == 0) {
      string values[], data[], strValue, text=StringToUpper(StringTrim(ObjectDescription(label)));
      int sizeOfValues = Explode(text, ",", values, NULL);

      for (int i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2) return(_false(catch("FindChartSequences(1)   illegal chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));

         // Sequenz-ID
         strValue  = StringTrim(data[0]);
         bool test = false;
         if (StringLeft(strValue, 1) == "T") {
            test     = true;
            strValue = StringRight(strValue, -1);
         }
         if (!StringIsDigit(strValue))                 return(_false(catch("FindChartSequences(2)   illegal sequence id in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         int iValue = StrToInteger(strValue);
         if (iValue == 0)
            continue;
         string strSequenceId = ifString(test, "T", "") + iValue;

         // Sequenz-Status
         strValue = StringTrim(data[1]);
         if (!StringIsDigit(strValue))                 return(_false(catch("FindChartSequences(3)   illegal sequence status in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         iValue = StrToInteger(strValue);
         if (!IsSequenceStatus(iValue))                return(_false(catch("FindChartSequences(4)   illegal sequence status in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         int sequenceStatus = iValue;

         ArrayPushString(ids,    strSequenceId );
         ArrayPushInt   (status, sequenceStatus);
         //debug("FindChartSequences()   "+ label +" = "+ strSequenceId +"|"+ sequenceStatus);
      }
   }
   return(ArraySize(ids));                                           // (bool) int
}


/**
 * Ob ein Wert einen gültigen Sequenzstatus-Code darstellt.
 *
 * @param  int value
 *
 * @return bool
 */
bool IsSequenceStatus(int value) {
   switch (value) {
      case STATUS_UNINITIALIZED: return(true);
      case STATUS_WAITING      : return(true);
      case STATUS_STARTING     : return(true);
      case STATUS_PROGRESSING  : return(true);
      case STATUS_STOPPING     : return(true);
      case STATUS_STOPPED      : return(true);
   }
   return(false);
}


/**
 * BarOpen-Eventhandler zur Erkennung von MA-Trendwechseln.
 *
 * @param  int    timeframe   - zu verwendender Timeframe
 * @param  string maPeriods   - Indikator-Parameter
 * @param  string maTimeframe - Indikator-Parameter
 * @param  string maMethod    - Indikator-Parameter
 * @param  int    lag         - Trigger-Verzögerung, mindestens 1 (eine Bar)
 * @param  int    bars        - Anzahl zu berechnender Indikatorwerte zur Ermittlung des vorherrschenden Trends
 * @param  int    directions  - Kombination von Trend-Identifiern:
 *                              MODE_UPTREND   - ein Wechsel zum Up-Trend soll signalisiert werden
 *                              MODE_DOWNTREND - ein Wechsel zum Down-Trend soll signalisiert werden
 * @param  int    lpSignal    - Zeiger auf Variable zur Signalaufnahme (+: Wechsel zum Up-Trend, -: Wechsel zum Down-Trend)
 *
 * @return bool - Erfolgsstatus (nicht, ob ein Signal aufgetreten ist)
 *
 *
 *  TODO: 1) refaktorieren und auslagern
 *        2) Die Funktion könnte den Indikator selbst berechnen und nur bei abweichender Periode auf iCustom() zurückgreifen.
 */
bool CheckTrendChange(int timeframe, string maPeriods, string maTimeframe, string maMethod, int lag, int bars, int directions, int &lpSignal) {
   bool detectUp   = _bool(directions & MODE_UPTREND  );
   bool detectDown = _bool(directions & MODE_DOWNTREND);


   // (1) Trend der letzten Bars ermitteln
   int error, /*ICUSTOM*/ic[]; if (!ArraySize(ic)) InitializeICustom(ic, NULL);
   ic[IC_LAST_ERROR] = NO_ERROR;

   int    barTrend, prevBarTrend, trend;
   string strTrend, changePattern;

   for (int bar=bars-1; bar>0; bar--) {                        // Bar 0 ist immer unvollständig und wird nicht berücksichtigt
      // (1.1) Trend der einzelnen Bar bestimmen
      barTrend = iCustom(NULL, timeframe, "Moving Average",    // (int) double ohne Präzisionsfehler (siehe MA-Implementierung)
                         maPeriods,                            // MA.Periods
                         maTimeframe,                          // MA.Timeframe
                         maMethod,                             // MA.Method
                         "",                                   // MA.Method.Help
                         "Close",                              // AppliedPrice
                         "",                                   // AppliedPrice.Help
                         Max(bars+1, 10),                      // Max.Values: +1 wegen fehlendem Trend der ältesten Bar; mind. 10 (Wert beliebig) zur Reduktion ansonsten
                         ForestGreen,                          // Color.UpTrend                                       | identischer Indikator-Instanzen (mit und ohne Lag)
                         Red,                                  // Color.DownTrend
                         "",                                   // _________________
                         ic[IC_PTR],                           // __iCustom__
                         BUFFER_2, bar); //throws ERS_HISTORY_UPDATE, ERR_TIMEFRAME_NOT_AVAILABLE

      error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERS_HISTORY_UPDATE)
         return(_false(catch("CheckTrendChange(1)", error)));
      if (IsError(ic[IC_LAST_ERROR]))
         return(_false(SetLastError(ic[IC_LAST_ERROR])));
      if (!barTrend)
         return(_false(catch("CheckTrendChange(2)->iCustom(Moving Average)   invalid trend for bar="+ bar +": "+ barTrend, ERR_CUSTOM_INDICATOR_ERROR)));

      // (1.2) vorherrschenden Trend bestimmen (mindestens 2 aufeinanderfolgende Bars in derselben Richtung)
      if (barTrend > 0) {
         if (bar > 1 && prevBarTrend > 0)                            // nur Bars > 1 (1 triggert Trendwechsel, 0 ist irrelevant)
            trend = 1;
      }                                                              // TODO: Prüfung in Abhängigkeit von "lag" implementieren
      else /*(barTrend < 0)*/ {
         if (bar > 1 && prevBarTrend < 0)                            // ...
            trend = -1;
      }
      strTrend     = StringConcatenate(strTrend, ifString(barTrend>0, "+", "-"));
      prevBarTrend = barTrend;
   }
   if (error == ERS_HISTORY_UPDATE)
      debug("CheckTrendChange()   ERS_HISTORY_UPDATE");              // TODO: bei ERS_HISTORY_UPDATE die zur Berechnung verwendeten Bars prüfen


   lpSignal = 0;

   // (2) Trendwechsel detektieren
   if (trend < 0) {
      if (detectUp) {
         changePattern = "-"+ StringRepeat("+", lag);                // up change "-++"
         if (StringEndsWith(strTrend, changePattern)) {              // Trendwechsel im Down-Trend
            lpSignal = 1;
            debug("CheckTrendChange()   "+ TimeToStr(TimeCurrent()) +"   trend change up");
         }
      }
   }
   else if (trend > 0) {
      if (detectDown) {
         changePattern = "+"+ StringRepeat("-", lag);                // down change "+--"
         if (StringEndsWith(strTrend, changePattern)) {              // Trendwechsel im Up-Trend
            lpSignal = -1;
            debug("CheckTrendChange()   "+ TimeToStr(TimeCurrent()) +"   trend change down");
         }
      }
   }
   return(!catch("CheckTrendChange(3)"));
}
