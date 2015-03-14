/**
 * Ermittelt Beginn und Ende der dem Parameter openTime.fxt vorhergehenden Periode und schreibt das Ergebnis in die �bergebenen
 * Variablen. Ist der Parameter openTime.fxt NULL, werden Beginn und Ende der j�ngsten Periode (also ggf. der aktuellen) zur�ckgegeben.
 *
 * @param  _IN_     int       timeframe     - Timeframe der zu ermittelnden Periode (NULL: der aktuelle Timeframe)
 * @param  _IN_OUT_ datetime &openTime.fxt  - Variable zur Aufnahme des Beginns der resultierenden Periode in FXT-Zeit
 * @param  _OUT_    datetime &closeTime.fxt - Variable zur Aufnahme des Endes der resultierenden Periode in FXT-Zeit
 * @param  _OUT_    datetime &openTime.srv  - Variable zur Aufnahme des Beginns der resultierenden Periode in Serverzeit
 * @param  _OUT_    datetime &closeTime.srv - Variable zur Aufnahme des Endes der resultierenden Periode in Serverzeit
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: Diese Funktion greift nicht auf Bars oder Datenserien zu, sondern verwendet nur die aktuelle Systemzeit.
 */
bool iPreviousPeriodTimes(int timeframe/*=NULL*/, datetime &openTime.fxt/*=NULL*/, datetime &closeTime.fxt, datetime &openTime.srv, datetime &closeTime.srv) {
   if (!timeframe)
      timeframe = Period();
   int month, dom, dow, monthOpenTime, monthNow;
   datetime now.fxt;


   // (1) PERIOD_M1
   if (timeframe == PERIOD_M1) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chste Minute initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 1*MINUTE;
      }

      // openTime.fxt auf den Beginn der vorherigen Minute setzen
      openTime.fxt -= (openTime.fxt%MINUTES + 1*MINUTE);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 23*HOURS - 59*MINUTES);    // Freitag 23:59
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 23*HOURS - 59*MINUTES);

      // closeTime.fxt auf das Ende der Minute setzen
      closeTime.fxt = openTime.fxt + 1*MINUTE;
   }


   // (2) PERIOD_M5
   else if (timeframe == PERIOD_M5) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten 5 Minuten initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 5*MINUTES;
      }

      // openTime.fxt auf den Beginn der vorherigen 5 Minuten setzen
      openTime.fxt -= (openTime.fxt%(5*MINUTES) + 5*MINUTES);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 23*HOURS - 55*MINUTES);    // Freitag 23:55
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 23*HOURS - 55*MINUTES);

      // closeTime.fxt auf das Ende der 5 Minuten setzen
      closeTime.fxt = openTime.fxt + 5*MINUTES;
   }


   // (3) PERIOD_M15
   else if (timeframe == PERIOD_M15) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten Viertelstunde initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 15*MINUTES;
      }

      // openTime.fxt auf den Beginn der vorherigen Viertelstunde setzen
      openTime.fxt -= (openTime.fxt%(15*MINUTES) + 15*MINUTES);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 23*HOURS - 45*MINUTES);    // Freitag 23:45
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 23*HOURS - 45*MINUTES);

      // closeTime.fxt auf das Ende der Viertelstunde setzen
      closeTime.fxt = openTime.fxt + 15*MINUTES;
   }


   // (4) PERIOD_M30
   else if (timeframe == PERIOD_M30) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten halben Stunde initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 30*MINUTES;
      }

      // openTime.fxt auf den Beginn der vorherigen halben Stunde setzen
      openTime.fxt -= (openTime.fxt%(30*MINUTES) + 30*MINUTES);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 23*HOURS - 30*MINUTES);    // Freitag 23:30
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 23*HOURS - 30*MINUTES);

      // closeTime.fxt auf das Ende der halben Stunde setzen
      closeTime.fxt = openTime.fxt + 30*MINUTES;
   }


   // (5) PERIOD_H1
   else if (timeframe == PERIOD_H1) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten Stunde initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 1*HOUR;
      }

      // openTime.fxt auf den Beginn der vorherigen Stunde setzen
      openTime.fxt -= (openTime.fxt%HOURS + 1*HOUR);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 23*HOURS);                 // Freitag 23:00
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 23*HOURS);

      // closeTime.fxt auf das Ende der Stunde setzen
      closeTime.fxt = openTime.fxt + 1*HOUR;
   }


   // (6) PERIOD_H4
   else if (timeframe == PERIOD_H4) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten H4-Periode initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 4*HOURS;
      }

      // openTime.fxt auf den Beginn der vorherigen H4-Periode setzen
      openTime.fxt -= (openTime.fxt%(4*HOURS) + 4*HOURS);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= (1*DAY  + openTime.fxt%DAYS - 20*HOURS);                 // Freitag 20:00
      else if (dow == SUNDAY  ) openTime.fxt -= (2*DAYS + openTime.fxt%DAYS - 20*HOURS);

      // closeTime.fxt auf das Ende der H4-Periode setzen
      closeTime.fxt = openTime.fxt + 4*HOURS;
   }


   // (7) PERIOD_D1
   else if (timeframe == PERIOD_D1) {
      /*
      debug("iPreviousPeriodTimes(0.1)  This.IsTesting="+ This.IsTesting() +"  TimeLocal="+ TimeToStr(TimeLocal()) +"  TimeCurrent="+ TimeToStr(TimeCurrent()));
      debug("iPreviousPeriodTimes(0.2)  gmt="+ TimeGMT());

      if (This.IsTesting()) {
         // TODO: Vorsicht, Scripte und Indikatoren sehen bei Aufruf von TimeLocal() im Tester u.U. nicht die modellierte, sondern die reale Zeit.

         gmt = ServerToGmtTime(TimeLocal());                            // TimeLocal() entspricht im Tester der Serverzeit
      }
      else {
         gmt = GetGmtTime();
      }
      */

      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt des n�chsten Tages initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 1*DAY;
      }

      // openTime.fxt auf 00:00 Uhr des vorherigen Tages setzen
      openTime.fxt -= (openTime.fxt%DAYS + 1*DAY);

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt -= 1*DAY;
      else if (dow == SUNDAY  ) openTime.fxt -= 2*DAYS;

      // closeTime.fxt auf das Ende des Tages setzen
      closeTime.fxt = openTime.fxt + 1*DAY;
   }


   // (8) PERIOD_W1
   else if (timeframe == PERIOD_W1) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt der n�chsten Woche initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 7*DAYS;
      }

      // openTime.fxt auf Montag, 00:00 Uhr der vorherigen Woche setzen
      openTime.fxt -= openTime.fxt % DAYS;                                                               // 00:00 des aktuellen Tages
      openTime.fxt -= (TimeDayOfWeekFix(openTime.fxt)+6)%7 * DAYS;                                       // Montag der aktuellen Woche
      openTime.fxt -= 7*DAYS;                                                                            // Montag der Vorwoche

      // closeTime.fxt auf 00:00 des folgenden Samstags setzen
      closeTime.fxt = openTime.fxt + 5*DAYS;
   }


   // (9) PERIOD_MN1
   else if (timeframe == PERIOD_MN1) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt des n�chsten Monats initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 1*MONTH;

         monthNow      = TimeMonth(now.fxt     );                                                        // MONTH ist nicht fix: Sicherstellen, da� openTime.fxt
         monthOpenTime = TimeMonth(openTime.fxt);                                                        // nicht schon auf den �bern�chsten Monat zeigt.
         if (monthNow > monthOpenTime)
            monthOpenTime += 12;
         if (monthOpenTime > monthNow+1)
            openTime.fxt -= 4*DAYS;
      }

      openTime.fxt -= openTime.fxt % DAYS;                                                               // 00:00 des aktuellen Tages

      // closeTime.fxt auf den 1. des folgenden Monats, 00:00 setzen
      dom = TimeDayFix(openTime.fxt);
      closeTime.fxt = openTime.fxt - (dom-1)*DAYS;                                                       // erster des aktuellen Monats

      // openTime.fxt auf den 1. des vorherigen Monats, 00:00 Uhr setzen
      openTime.fxt  = closeTime.fxt - 1*DAYS;                                                            // letzter Tag des vorherigen Monats
      openTime.fxt -= (TimeDayFix(openTime.fxt)-1)*DAYS;                                                 // erster Tag des vorherigen Monats

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt += 2*DAYS;
      else if (dow == SUNDAY  ) openTime.fxt += 1*DAY;

      // Wochenenden in closeTime.fxt �berspringen
      dow = TimeDayOfWeekFix(closeTime.fxt);
      if      (dow == SUNDAY) closeTime.fxt -= 1*DAY;
      else if (dow == MONDAY) closeTime.fxt -= 2*DAYS;
   }


   // (10) PERIOD_Q1
   else if (timeframe == PERIOD_Q1) {
      // ist openTime.fxt nicht gesetzt, Variable mit Zeitpunkt des n�chsten Quartals initialisieren
      if (!openTime.fxt) {
         now.fxt      = TimeFXT(); if (!now.fxt) return(false);
         openTime.fxt = now.fxt + 1*QUARTER;

         monthNow      = TimeMonth(now.fxt     );                                                        // QUARTER ist nicht fix: Sicherstellen, da� openTime.fxt
         monthOpenTime = TimeMonth(openTime.fxt);                                                        // nicht schon auf das �bern�chste Quartal zeigt.
         if (monthNow > monthOpenTime)
            monthOpenTime += 12;
         if (monthOpenTime > monthNow+3)
            openTime.fxt -= 1*MONTH;
      }

      openTime.fxt -= openTime.fxt % DAYS;                                                               // 00:00 des aktuellen Tages

      // closeTime.fxt auf den ersten Tag des folgenden Quartals, 00:00 setzen
      switch (TimeMonth(openTime.fxt)) {
         case JANUARY  :
         case FEBRUARY :
         case MARCH    : closeTime.fxt = openTime.fxt -    (TimeDayOfYear(openTime.fxt)-1)*DAYS; break;  // erster Tag des aktuellen Quartals (01.01.)
         case APRIL    : closeTime.fxt = openTime.fxt -       (TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case MAY      : closeTime.fxt = openTime.fxt - (30+   TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case JUNE     : closeTime.fxt = openTime.fxt - (30+31+TimeDayFix(openTime.fxt)-1)*DAYS; break;  // erster Tag des aktuellen Quartals (01.04.)
         case JULY     : closeTime.fxt = openTime.fxt -       (TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case AUGUST   : closeTime.fxt = openTime.fxt - (31+   TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case SEPTEMBER: closeTime.fxt = openTime.fxt - (31+31+TimeDayFix(openTime.fxt)-1)*DAYS; break;  // erster Tag des aktuellen Quartals (01.07.)
         case OCTOBER  : closeTime.fxt = openTime.fxt -       (TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case NOVEMBER : closeTime.fxt = openTime.fxt - (31+   TimeDayFix(openTime.fxt)-1)*DAYS; break;
         case DECEMBER : closeTime.fxt = openTime.fxt - (31+30+TimeDayFix(openTime.fxt)-1)*DAYS; break;  // erster Tag des aktuellen Quartals (01.10.)
      }

      // openTime.fxt auf den ersten Tag des vorherigen Quartals, 00:00 Uhr setzen
      openTime.fxt = closeTime.fxt - 1*DAY;                                                              // letzter Tag des vorherigen Quartals
      switch (TimeMonth(openTime.fxt)) {
         case MARCH    : openTime.fxt -=    (TimeDayOfYear(openTime.fxt)-1)*DAYS; break;                 // erster Tag des vorherigen Quartals (01.01.)
         case JUNE     : openTime.fxt -= (30+31+TimeDayFix(openTime.fxt)-1)*DAYS; break;                 // erster Tag des vorherigen Quartals (01.04.)
         case SEPTEMBER: openTime.fxt -= (31+31+TimeDayFix(openTime.fxt)-1)*DAYS; break;                 // erster Tag des vorherigen Quartals (01.07.)
         case DECEMBER : openTime.fxt -= (31+30+TimeDayFix(openTime.fxt)-1)*DAYS; break;                 // erster Tag des vorherigen Quartals (01.10.)
      }

      // Wochenenden in openTime.fxt �berspringen
      dow = TimeDayOfWeekFix(openTime.fxt);
      if      (dow == SATURDAY) openTime.fxt += 2*DAYS;
      else if (dow == SUNDAY  ) openTime.fxt += 1*DAY;

      // Wochenenden in closeTime.fxt �berspringen
      dow = TimeDayOfWeekFix(closeTime.fxt);
      if      (dow == SUNDAY) closeTime.fxt -= 1*DAY;
      else if (dow == MONDAY) closeTime.fxt -= 2*DAYS;
   }
   else return(!catch("iPreviousPeriodTimes(1)  invalid parameter timeframe = "+ timeframe, ERR_INVALID_PARAMETER));


   // entsprechende Serverzeiten ermitteln und setzen
   openTime.srv  = FxtToServerTime(openTime.fxt );
   closeTime.srv = FxtToServerTime(closeTime.fxt);

   return(!catch("iPreviousPeriodTimes(2)"));
}
