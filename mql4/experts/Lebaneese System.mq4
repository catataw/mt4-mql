/**
 * Lebaneese System
 *
 * At the moment implemented for testing only.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

/////////////////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////////////////

extern double Lotsize = 0.1;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>
#include <iCustom/icNonLagMA.mqh>


#define MODE_MA      MovingAverage.MODE_MA            // NonLagMA buffer indices
#define MODE_TREND   MovingAverage.MODE_TREND

bool isOpenPosition;


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   return(catch("onInit(1)"));
}


/**
 * Initialization
 *
 * @return int - error status
 */
int onDeinit() {
   return(catch("onInit(1)"));
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   static int counter;
   if (!counter) {
      //debug("onTick(1)  "+ TimeToStr(TimeCurrent(), TIME_FULL) +"  Bars="+ Bars +"  Spread="+ DoubleToStr((Ask-Bid)/Pip, 1) +"  V="+ _int(Volume[0]));
      counter++;
   }


   // check current position
   if (!isOpenPosition) {
      CheckForOpenSignal();
   }
   else {
      CheckForCloseSignal();
   }

   return(last_error);
}


/**
 * Check for entry conditions
 */
void CheckForOpenSignal() {
   if (Volume[0] > 1)                                          // check on BarOpen only
      return;

   // wait for trend change of last bar
   int trend = GetNonLagMA(1, MODE_TREND);
   if (Abs(trend) == 1) {                                      // trend change
      debug("CheckForOpenSignal(1)  "+ TimeToStr(TimeCurrent(), TIME_FULL) +"  NonLagMA turned "+ ifString(trend==1, "up", "down"));
   }
}


/**
 * Return a NonLagMA indicator value.
 *
 * @param  int bar    - bar index of the value to return
 * @param  int buffer - buffer index of the value to return
 *
 * @return double - indicator value or NULL if an error occurred
 */
double GetNonLagMA(int bar, int buffer) {
   static int    timeframe   = NULL;                           // current timeframe
   static int    cycleLength = 20;
   static string version     = "4";
   static int    maxValues   = 50;

   return(icNonLagMA(timeframe, cycleLength, version, maxValues, buffer, bar));
}


/**
 * Check for exit conditions
 */
void CheckForCloseSignal() {
}
