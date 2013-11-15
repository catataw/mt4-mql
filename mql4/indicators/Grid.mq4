/**
 * Chart-Grid. Die vertikalen Separatoren sind auf der ersten Bar der Session positioniert und tragen im Label das Datum der begonnenen Session.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_TIMEZONE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

////////////////////////////////////////////////////////////////////////////// Externe Parameter //////////////////////////////////////////////////////////////////////////////

extern color Grid.Color = LightGray;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>

#property indicator_chart_window


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
   RemoveChartObjects();
   return(catch("onDeinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (prev_error == ERS_HISTORY_UPDATE) {
      ValidBars   = 0;
      ChangedBars = Bars - ValidBars;
   }

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
   datetime fromFST = GetFSTNextSessionStartTime(ServerToFST(Time[Bars-1]) - 1*SECOND);
   datetime toFST   = GetFSTNextSessionStartTime(ServerToFST(TimeCurrent()));

   // Tagesseparatoren
   if (Period() < PERIOD_H4) {                                       // fromFST bleibt unver�ndert
      toFST += (8-TimeDayOfWeek(toFST))%7 * DAYS;                    // toFST ist der n�chste Montag (die restliche Woche wird komplett dargestellt)
   }

   // Wochenseparatoren
   else if (Period() == PERIOD_H4) {
      fromFST += (8-TimeDayOfWeek(fromFST))%7 * DAYS;                // fromFST ist der erste Montag
      toFST   += (8-TimeDayOfWeek(toFST))%7 * DAYS;                  // toFST ist der n�chste Montag
   }

   // Monatsseparatoren
   else if (Period() == PERIOD_D1) {
      yyyy = TimeYear(fromFST);                                      // fromFST ist der erste Wochentag des ersten vollen Monats
      mm   = TimeMonth(fromFST);
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm);

      if (firstWeekDay < fromFST) {
         if (mm == 12) { yyyy++; mm = 0; }
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm+1);
      }
      fromFST = firstWeekDay;
      // ------------------------------------------------------
      yyyy = TimeYear(toFST);                                        // toFST ist der erste Wochentag des n�chsten Monats
      mm   = TimeMonth(toFST);
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm);

      if (firstWeekDay < toFST) {
         if (mm == 12) { yyyy++; mm = 0; }
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy, mm+1);
      }
      toFST = firstWeekDay;
   }

   // Jahresseparatoren
   else if (Period() > PERIOD_D1) {
      yyyy = TimeYear(fromFST);                                      // fromFST ist der erste Wochentag des ersten vollen Jahres
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, 1);
      if (firstWeekDay < fromFST)
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy+1, 1);
      fromFST = firstWeekDay;
      // ------------------------------------------------------
      yyyy = TimeYear(toFST);                                        // toFST ist der erste Wochentag des n�chsten Jahres
      firstWeekDay = GetFirstWeekdayOfMonth(yyyy, 1);
      if (firstWeekDay < toFST)
         firstWeekDay = GetFirstWeekdayOfMonth(yyyy+1, 1);
      toFST = firstWeekDay;
   }
   //debug("DrawGrid()   from \""+ GetDayOfWeek(fromFST, false) +" "+ TimeToStr(fromFST) +"\" to \""+ GetDayOfWeek(toFST, false) +" "+ TimeToStr(toFST) +"\"");


   // (2) Separatoren zeichnen
   for (datetime time=fromFST; time <= toFST; time+=1*DAY) {
      separatorTime = FSTToServerTime(time);                         // ERR_INVALID_TIMEZONE_CONFIG wird in onInit() abgefangen
      dow           = TimeDayOfWeek(time);

      // Bar und Chart-Time des Separators ermitteln
      if (Time[0] < separatorTime) {                                 // keine entsprechende Bar: aktuelle Session oder noch laufendes ERS_HISTORY_UPDATE
         bar = -1;
         chartTime = separatorTime;                                  // urspr�ngliche Zeit verwenden
         if (dow == MONDAY)
            chartTime -= 2*DAYS;                                     // bei zuk�nftigen Separatoren Wochenenden von Hand "kollabieren" TODO: Bug bei Periode > H4
      }
      else {                                                         // Separator liegt innerhalb der Bar-Range, Zeit der ersten existierenden Bar verwenden
         bar = iBarShiftNext(NULL, NULL, separatorTime);
         if (bar == EMPTY_VALUE) {                                   // ERS_HISTORY_UPDATE ???
            if (SetLastError(stdlib_GetLastError()) != ERS_HISTORY_UPDATE)
               catch("DrawGrid(1)", last_error);
            return(last_error);
         }
         chartTime = Time[bar];
      }

      // Label des Separators zusammenstellen (ie. "Fri 23.12.2011")
      label = TimeToStr(time);
      label = StringConcatenate(GetDayOfWeek(time, false), " ", StringSubstr(label, 8, 2), ".", StringSubstr(label, 5, 2), ".", StringSubstr(label, 0, 4));

      if (lastChartTime == chartTime)                                // Bars der vorherigen Periode fehlen (noch laufendes ERS_HISTORY_UPDATE oder Kursl�cke)
         ObjectDelete(lastLabel);                                    // Separator f�r die fehlende Periode wieder l�schen

      // Separator zeichnen
      if (ObjectFind(label) > -1)
         ObjectDelete(label);
      if (ObjectCreate(label, OBJ_VLINE, 0, chartTime, 0)) {
         sepStyle = STYLE_DOT;
         sepColor = Grid.Color;
         if (Period() < PERIOD_H4) {
            if (dow == MONDAY) {
               sepStyle = STYLE_DASHDOTDOT;
               sepColor = C'231,192,221';
            }
         }
         else if (Period() == PERIOD_H4) {
            sepStyle = STYLE_DASHDOTDOT;
            sepColor = C'231,192,221';
         }
         ObjectSet (label, OBJPROP_STYLE, sepStyle);
         ObjectSet (label, OBJPROP_COLOR, sepColor);
         ObjectSet (label, OBJPROP_BACK , true  );
         PushObject(label);
      }
      else GetLastError();
      lastChartTime = chartTime;
      lastLabel     = label;                                         // Daten des letzten Separators f�r L�ckenerkennung merken


      // (2.1) je nach Periode einen Tag *vor* den n�chsten Separator springen
      // Tagesseparatoren
      if (Period() < PERIOD_H4) {
         if (dow == FRIDAY)                                          // Wochenenden �berspringen
            time += 2*DAYS;
      }
      // Wochenseparatoren
      else if (Period() == PERIOD_H4) {
         time += 6*DAYS;                                             // TimeDayOfWeek(time) == MONDAY
      }
      // Monatsseparatoren
      else if (Period() == PERIOD_D1) {                              // erster Wochentag des Monats
         yyyy = TimeYear(time);
         mm   = TimeMonth(time);
         if (mm == 12) { yyyy++; mm = 0; }
         time = GetFirstWeekdayOfMonth(yyyy, mm+1) - 1*DAY;
      }
      // Jahresseparatoren
      else if (Period() > PERIOD_D1) {                               // erster Wochentag des Jahres
         yyyy = TimeYear(time);
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
 * @return datetime - erster Wochentag des Monats oder -1, falls ein Fehler auftrat
 */
datetime GetFirstWeekdayOfMonth(int year, int month) {
   if (year  < 1970 || 2037 < year ) return(_int(-1, catch("GetFirstWeekdayOfMonth(1)   illegal parameter year = "+ year +" (not between 1970 and 2037)", ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (month <    1 ||   12 < month) return(_int(-1, catch("GetFirstWeekdayOfMonth(2)   invalid parameter month = "+ month, ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime firstDayOfMonth = StrToTime(StringConcatenate(year, ".", month, ".01 00:00:00"));

   int dow = TimeDayOfWeek(firstDayOfMonth);
   if (dow == SATURDAY) return(firstDayOfMonth + 2*DAYS);
   if (dow == SUNDAY  ) return(firstDayOfMonth + 1*DAY );

   return(firstDayOfMonth);
}
