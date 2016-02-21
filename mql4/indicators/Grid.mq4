/**
 * Chart-Grid. Die vertikalen Separatoren sind auf der ersten Bar der Session positioniert und tragen im Label das Datum der begonnenen Session.
 */
#property indicator_chart_window

#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_TIMEZONE};
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern color Color.RegularGrid = Gainsboro;                          // C'220,220,220'
extern color Color.SuperGrid   = LightGray;                          // C'211,211,211'

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <iFunctions/iBarShiftNext.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // Datenanzeige ausschalten
   SetIndexLabel(0, NULL);
   return(catch("onInit()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   DeleteRegisteredObjects(NULL);
   return(catch("onDeinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // TODO: Handler onAccountChanged() integrieren und alle Separatoren l�schen.

   // Grid zeichnen
   if (!ValidBars)
      DrawGrid();

   return(last_error);
}


/**
 * Zeichnet das Grid (ERR_INVALID_TIMEZONE_CONFIG wird in onInit() abgefangen).
 *
 * @return int - Fehlerstatus
 */
int DrawGrid() {
   datetime firstWeekDay, separatorTime, chartTime, lastChartTime;
   int      dow, dd, mm, yyyy, bar, sepColor, sepStyle;
   string   label, lastLabel;


   // (1) Zeitpunkte des �ltesten und j�ngsten Separators berechen
   datetime fromFXT = GetNextSessionStartTime.fxt(ServerToFxtTime(Time[Bars-1]) - 1*SECOND);
   datetime now.fxt = TimeFXT(); if (!now.fxt) return(last_error);
   datetime toFXT   = GetNextSessionStartTime.fxt(now.fxt);                   // nicht TimeCurrent() verwenden, kann 0 sein

   // Tagesseparatoren
   if (Period() < PERIOD_H4) {                                                // fromFXT bleibt unver�ndert
      toFXT += (8-TimeDayOfWeekFix(toFXT))%7 * DAYS;                          // toFXT ist der n�chste Montag (die restliche Woche wird komplett dargestellt)
   }

   // Wochenseparatoren
   else if (Period() == PERIOD_H4) {
      fromFXT += (8-TimeDayOfWeekFix(fromFXT))%7 * DAYS;                      // fromFXT ist der erste Montag
      toFXT   += (8-TimeDayOfWeekFix(toFXT))%7 * DAYS;                        // toFXT ist der n�chste Montag
   }

   // Monatsseparatoren
   else if (Period() == PERIOD_D1) {
      yyyy = TimeYearFix(fromFXT);                                            // fromFXT ist der erste Wochentag des ersten vollen Monats
      mm   = TimeMonth(fromFXT);
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm);

      if (firstWeekDay < fromFXT) {
         if (mm == 12) { yyyy++; mm = 0; }
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm+1);
      }
      fromFXT = firstWeekDay;
      // ------------------------------------------------------
      yyyy = TimeYearFix(toFXT);                                              // toFXT ist der erste Wochentag des n�chsten Monats
      mm   = TimeMonth(toFXT);
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm);

      if (firstWeekDay < toFXT) {
         if (mm == 12) { yyyy++; mm = 0; }
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm+1);
      }
      toFXT = firstWeekDay;
   }

   // Jahresseparatoren
   else if (Period() > PERIOD_D1) {
      yyyy = TimeYearFix(fromFXT);                                            // fromFXT ist der erste Wochentag des ersten vollen Jahres
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, 1);
      if (firstWeekDay < fromFXT)
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy+1, 1);
      fromFXT = firstWeekDay;
      // ------------------------------------------------------
      yyyy = TimeYearFix(toFXT);                                              // toFXT ist der erste Wochentag des n�chsten Jahres
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, 1);
      if (firstWeekDay < toFXT)
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy+1, 1);
      toFXT = firstWeekDay;
   }
   //debug("DrawGrid()  from \""+ DateTimeToStr(fromFXT, "w, D.M.Y H:I") +"\" to \""+ DateTimeToStr(fromFXT, "w, D.M.Y H:I") +"\"");


   // (2) Separatoren zeichnen
   for (datetime time=fromFXT; time <= toFXT; time+=1*DAY) {
      separatorTime = FxtToServerTime(time);                                  // ERR_INVALID_TIMEZONE_CONFIG wird in onInit() abgefangen
      dow           = TimeDayOfWeekFix(time);

      // Bar und Chart-Time des Separators ermitteln
      if (Time[0] < separatorTime) {                                          // keine entsprechende Bar: aktuelle Session oder noch laufendes ERS_HISTORY_UPDATE
         bar = -1;
         chartTime = separatorTime;                                           // urspr�ngliche Zeit verwenden
         if (dow == MONDAY)
            chartTime -= 2*DAYS;                                              // bei zuk�nftigen Separatoren Wochenenden von Hand "kollabieren" TODO: Bug bei Periode > H4
      }
      else {                                                                  // Separator liegt innerhalb der Bar-Range, Zeit der ersten existierenden Bar verwenden
         bar = iBarShiftNext(NULL, NULL, separatorTime);
         if (bar == EMPTY_VALUE) return(last_error);
         chartTime = Time[bar];
      }

      // Label des Separators zusammenstellen (ie. "Fri 23.12.2011")
      label = TimeToStr(time);
      label = StringConcatenate(DateTimeToStr(time, "w"), " ", StringSubstr(label, 8, 2), ".", StringSubstr(label, 5, 2), ".", StringSubstr(label, 0, 4));

      if (lastChartTime == chartTime)                                         // Bars der vorherigen Periode fehlen (noch laufendes ERS_HISTORY_UPDATE oder Kursl�cke)
         ObjectDelete(lastLabel);                                             // Separator f�r die fehlende Periode wieder l�schen

      // Separator zeichnen
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      if (ObjectCreate(label, OBJ_VLINE, 0, chartTime, 0)) {
         sepStyle = STYLE_DOT;
         sepColor = Color.RegularGrid;
         if (Period() < PERIOD_H4) {
            if (dow == MONDAY) {
               sepStyle = STYLE_DASHDOTDOT;
               sepColor = Color.SuperGrid;
            }
         }
         else if (Period() == PERIOD_H4) {
            sepStyle = STYLE_DASHDOTDOT;
            sepColor = Color.SuperGrid;
         }
         ObjectSet(label, OBJPROP_STYLE, sepStyle);
         ObjectSet(label, OBJPROP_COLOR, sepColor);
         ObjectSet(label, OBJPROP_BACK , true  );
         ObjectRegister(label);
      }
      else GetLastError();
      lastChartTime = chartTime;
      lastLabel     = label;                                                  // Daten des letzten Separators f�r L�ckenerkennung merken


      // (2.1) je nach Periode einen Tag *vor* den n�chsten Separator springen
      // Tagesseparatoren
      if (Period() < PERIOD_H4) {
         if (dow == FRIDAY)                                                   // Wochenenden �berspringen
            time += 2*DAYS;
      }
      // Wochenseparatoren
      else if (Period() == PERIOD_H4) {
         time += 6*DAYS;                                                      // TimeDayOfWeek(time) == MONDAY
      }
      // Monatsseparatoren
      else if (Period() == PERIOD_D1) {                                       // erster Wochentag des Monats
         yyyy = TimeYearFix(time);
         mm   = TimeMonth(time);
         if (mm == 12) { yyyy++; mm = 0; }
         time = GetFirstWeekdayOfMonth(yyyy, mm+1) - 1*DAY;
      }
      // Jahresseparatoren
      else if (Period() > PERIOD_D1) {                                        // erster Wochentag des Jahres
         yyyy = TimeYearFix(time);
         time = GetFirstWeekdayOfMonth(yyyy+1, 1) - 1*DAY;
      }
   }
   return(catch("DrawGrid(2)"));
}


/**
 * Ermittelt den ersten Wochentag eines Monats.
 *
 * @param  int year  - Jahr (1970 bis 2037)
 * @param  int month - Monat
 *
 * @return datetime - erster Wochentag des Monats oder -1 (EMPTY), falls ein Fehler auftrat
 */
datetime GetFirstWeekdayOfMonth(int year, int month) {
   if (year  < 1970 || 2037 < year ) return(_EMPTY(catch("GetFirstWeekdayOfMonth(1)  illegal parameter year = "+ year +" (not between 1970 and 2037)", ERR_INVALID_PARAMETER)));
   if (month <    1 ||   12 < month) return(_EMPTY(catch("GetFirstWeekdayOfMonth(2)  invalid parameter month = "+ month, ERR_INVALID_PARAMETER)));

   datetime firstDayOfMonth = StrToTime(StringConcatenate(year, ".", StringRight("0"+month, 2), ".01 00:00:00"));

   int dow = TimeDayOfWeekFix(firstDayOfMonth);
   if (dow == SATURDAY) return(firstDayOfMonth + 2*DAYS);
   if (dow == SUNDAY  ) return(firstDayOfMonth + 1*DAY );

   return(firstDayOfMonth);
}
