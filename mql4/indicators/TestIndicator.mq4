/**
 * TestIndicator
 */
#include <types.mqh>
#define     __TYPE__      T_INDICATOR
int   __INIT_FLAGS__[] = {INIT_TIMEZONE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


#property indicator_chart_window


bool done;

datetime weekend.stop.time.condition   = D'1970.01.01 23:37';     // StopSequence()-Zeit vor Wochenend-Pause (Freitags abend)
datetime weekend.stop.time.value;

datetime weekend.resume.time.condition = D'1970.01.01 01:10';     // späteste ResumeSequence()-Zeit nach Wochenend-Pause (Montags morgen)
datetime weekend.resume.time.value;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {
      datetime now;

      now = ServerToFXT(D'2012.07.26 13:50'); UpdateWeekendStop(now);
      now = ServerToFXT(D'2012.07.27 13:50'); UpdateWeekendStop(now);
      now = ServerToFXT(D'2012.07.27 23:50'); UpdateWeekendStop(now);
      now = ServerToFXT(D'2012.07.28 23:50'); UpdateWeekendStop(now);

      //UpdateWeekendResume();
      done = true;
   }
   return(catch("onTick()"+ now));
}


/**
 * Aktualisiert die Bedingungen für StopSequence() vor der Wochenend-Pause.
 */
void UpdateWeekendStop(datetime now) {
   datetime friday;

   switch (TimeDayOfWeek(now)) {
      case SUNDAY   : friday = /*0*/now + 5*DAYS; break;
      case MONDAY   : friday = /*1*/now + 4*DAYS; break;
      case TUESDAY  : friday = /*2*/now + 3*DAYS; break;
      case WEDNESDAY: friday = /*3*/now + 2*DAYS; break;
      case THURSDAY : friday = /*4*/now + 1*DAY ; break;
      case FRIDAY   : friday = /*5*/now + 0*DAYS; break;
      case SATURDAY : friday = /*6*/now + 6*DAYS; break;
   }
   weekend.stop.time.value = (friday/DAYS)*DAYS + weekend.stop.time.condition%DAY;

   if (weekend.stop.time.value < now)
      weekend.stop.time.value = (friday/DAYS)*DAYS + D'1970.01.01 23:55'%DAY;       // 5 Minuten vor Schluß

   weekend.stop.time.value = FXTToServerTime(weekend.stop.time.value);

   debug("Stop()   now='"+ GetDayOfWeek(now, false) +", "+ TimeToStr(now, TIME_FULL) +"'   stop='"+ GetDayOfWeek(weekend.stop.time.value, false) +", "+ TimeToStr(weekend.stop.time.value, TIME_FULL) +"'");
}


/**
 * Aktualisiert die Bedingungen für ResumeSequence() nach der Wochenend-Pause.
 */
void UpdateWeekendResume() {
   debug("UpdateWeekendResume()   resume='"+ TimeToStr(weekend.resume.time.value, TIME_FULL) +"'");
}


/**
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   return(catch("onDeinit()"));
   UpdateWeekendStop(NULL);
   UpdateWeekendResume();
}
