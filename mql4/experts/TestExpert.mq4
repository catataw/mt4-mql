/**
 * TestExpert
 */
#include <core/define.mqh>
#define __TYPE__        T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern string Parameter = "dummy";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   //----------------------------
   int    MA.Periods   = 100;
   string MA.Timeframe = "H1";
   string MA.Method    = "SMA";
   string AppliedPrice = "Close";
   int    Max.Values   = 2000;
   //----------------------------
   int bar = 0;

   double value = iCustom(NULL, PERIOD_H1, "Moving Average",
                          MA.Periods,
                          MA.Timeframe,
                          MA.Method,
                          "",                                        // MA.Method.Help,
                          AppliedPrice,
                          "",                                        // AppliedPrice.Help,
                          Max.Values,
                          BUFFER_0, bar); // throws ERR_HISTORY_UPDATE

   debug("onTick()");

   int error = GetLastError();
   if (error == ERR_HISTORY_UPDATE) debug("onTick()   ERR_HISTORY_UPDATE");
   else                             catch("onTick()", error);

   return(last_error);
}


// ------------------------------------------------------------------------------------------------------------------------------------------------


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   return(NO_ERROR);
}


// ------------------------------------------------------------------------------------------------------------------------------------------------


/**
 * Parameteränderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   return(NO_ERROR);
}


/**
 * EA von Hand entfernt (Chart->Expert->Remove) oder neuer EA drübergeladen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   return(NO_ERROR);
}


/**
 * Symbol- oder Timeframewechsel
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   return(NO_ERROR);
}


/**
 * - Chart geschlossen                       -oder-
 * - Template wird neu geladen               -oder-
 * - Terminal-Shutdown                       -oder-
 * - im Tester nach Betätigen des "Stop"-Buttons oder nach Chart ->Close
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Der "Stop"-Button kann vom EA selbst "betätigt" worden sein (nach Fehler oder vorzeitigem Testabschluß).
 */
int onDeinitChartClose() {
   return(NO_ERROR);
}


/**
 * Kein UninitializeReason gesetzt: im Tester nach regulärem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   return(NO_ERROR);
}


/**
 * Recompilation
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   return(NO_ERROR);
}

/*
// EA im Tester
M15::TestExpert::stdlib::onTick()       ---------------------------------
M15::TestExpert::stdlib::onTick()       Predefined variables for "EURUSD"
M15::TestExpert::stdlib::onTick()       ---------------------------------
M15::TestExpert::stdlib::onTick()       Pip         = 0.0001'0
M15::TestExpert::stdlib::onTick()       PipDigits   = 4
M15::TestExpert::stdlib::onTick()       Digits  (b) = 5
M15::TestExpert::stdlib::onTick()       Point   (b) = 0.0000'1
M15::TestExpert::stdlib::onTick()       PipPoints   = 10
M15::TestExpert::stdlib::onTick()       Bid/Ask (b) = 1.2711'2/1.2714'0
M15::TestExpert::stdlib::onTick()       Bars    (b) = 1001
M15::TestExpert::stdlib::onTick()       PriceFormat = ".4'"
M15::TestExpert::stdlib::onTick()       -------------------------
M15::TestExpert::stdlib::onTick()       MarketInfo() for "EURUSD"
M15::TestExpert::stdlib::onTick()       -------------------------
M15::TestExpert::stdlib::onTick()       MODE_LOW               = 0.0000'0                 // falsch: nicht modelliert
M15::TestExpert::stdlib::onTick()       MODE_HIGH              = 0.0000'0                 // falsch: nicht modelliert
M15::TestExpert::stdlib::onTick()       MODE_TIME              = '2012.11.12 00:00:00'
M15::TestExpert::stdlib::onTick()       MODE_BID               = 1.2711'2
M15::TestExpert::stdlib::onTick()       MODE_ASK               = 1.2714'0
M15::TestExpert::stdlib::onTick()       MODE_POINT             = 0.0000'1
M15::TestExpert::stdlib::onTick()       MODE_DIGITS            = 5
M15::TestExpert::stdlib::onTick()       MODE_SPREAD            = 28
M15::TestExpert::stdlib::onTick()       MODE_STOPLEVEL         = 20
M15::TestExpert::stdlib::onTick()       MODE_LOTSIZE           = 100000
M15::TestExpert::stdlib::onTick()       MODE_TICKVALUE         = 1
M15::TestExpert::stdlib::onTick()       MODE_TICKSIZE          = 0.0000'1
M15::TestExpert::stdlib::onTick()       MODE_SWAPLONG          = -1.3
M15::TestExpert::stdlib::onTick()       MODE_SWAPSHORT         = 0.5
M15::TestExpert::stdlib::onTick()       MODE_STARTING          = 0
M15::TestExpert::stdlib::onTick()       MODE_EXPIRATION        = 0
M15::TestExpert::stdlib::onTick()       MODE_TRADEALLOWED      = 0                        // falsch modelliert
M15::TestExpert::stdlib::onTick()       MODE_MINLOT            = 0.01
M15::TestExpert::stdlib::onTick()       MODE_LOTSTEP           = 0.01
M15::TestExpert::stdlib::onTick()       MODE_MAXLOT            = 2
M15::TestExpert::stdlib::onTick()       MODE_SWAPTYPE          = 0
M15::TestExpert::stdlib::onTick()       MODE_PROFITCALCMODE    = 0
M15::TestExpert::stdlib::onTick()       MODE_MARGINCALCMODE    = 0
M15::TestExpert::stdlib::onTick()       MODE_MARGININIT        = 0
M15::TestExpert::stdlib::onTick()       MODE_MARGINMAINTENANCE = 0
M15::TestExpert::stdlib::onTick()       MODE_MARGINHEDGED      = 50000
M15::TestExpert::stdlib::onTick()       MODE_MARGINREQUIRED    = 254.25
M15::TestExpert::stdlib::onTick()       MODE_FREEZELEVEL       = 0

// Indikator im Tester, via iCustom()
H1::Moving Average::stdlib::onTick()    ---------------------------------
H1::Moving Average::stdlib::onTick()    Predefined variables for "EURUSD"
H1::Moving Average::stdlib::onTick()    ---------------------------------
H1::Moving Average::stdlib::onTick()    Pip         = 0.0001'0
H1::Moving Average::stdlib::onTick()    PipDigits   = 4
H1::Moving Average::stdlib::onTick()    Digits  (b) = 5
H1::Moving Average::stdlib::onTick()    Point   (b) = 0.0000'1
H1::Moving Average::stdlib::onTick()    PipPoints   = 10
H1::Moving Average::stdlib::onTick()    Bid/Ask (b) = 1.2711'2/1.2714'0
H1::Moving Average::stdlib::onTick()    Bars    (b) = 1001
H1::Moving Average::stdlib::onTick()    PriceFormat = ".4'"
H1::Moving Average::stdlib::onTick()    -------------------------
H1::Moving Average::stdlib::onTick()    MarketInfo() for "EURUSD"
H1::Moving Average::stdlib::onTick()    -------------------------
H1::Moving Average::stdlib::onTick()    MODE_LOW               = 0.0000'0                 // falsch übernommen
H1::Moving Average::stdlib::onTick()    MODE_HIGH              = 0.0000'0                 // falsch übernommen
H1::Moving Average::stdlib::onTick()    MODE_TIME              = '2012.11.12 00:00:00'
H1::Moving Average::stdlib::onTick()    MODE_BID               = 1.2711'2
H1::Moving Average::stdlib::onTick()    MODE_ASK               = 1.2714'0
H1::Moving Average::stdlib::onTick()    MODE_POINT             = 0.0000'1
H1::Moving Average::stdlib::onTick()    MODE_DIGITS            = 5
H1::Moving Average::stdlib::onTick()    MODE_SPREAD            = 0                        // völlig falsch
H1::Moving Average::stdlib::onTick()    MODE_STOPLEVEL         = 20
H1::Moving Average::stdlib::onTick()    MODE_LOTSIZE           = 100000
H1::Moving Average::stdlib::onTick()    MODE_TICKVALUE         = 1
H1::Moving Average::stdlib::onTick()    MODE_TICKSIZE          = 0.0000'1
H1::Moving Average::stdlib::onTick()    MODE_SWAPLONG          = -1.3
H1::Moving Average::stdlib::onTick()    MODE_SWAPSHORT         = 0.5
H1::Moving Average::stdlib::onTick()    MODE_STARTING          = 0
H1::Moving Average::stdlib::onTick()    MODE_EXPIRATION        = 0
H1::Moving Average::stdlib::onTick()    MODE_TRADEALLOWED      = 1
H1::Moving Average::stdlib::onTick()    MODE_MINLOT            = 0.01
H1::Moving Average::stdlib::onTick()    MODE_LOTSTEP           = 0.01
H1::Moving Average::stdlib::onTick()    MODE_MAXLOT            = 2
H1::Moving Average::stdlib::onTick()    MODE_SWAPTYPE          = 0
H1::Moving Average::stdlib::onTick()    MODE_PROFITCALCMODE    = 0
H1::Moving Average::stdlib::onTick()    MODE_MARGINCALCMODE    = 0
H1::Moving Average::stdlib::onTick()    MODE_MARGININIT        = 0
H1::Moving Average::stdlib::onTick()    MODE_MARGINMAINTENANCE = 0
H1::Moving Average::stdlib::onTick()    MODE_MARGINHEDGED      = 50000
H1::Moving Average::stdlib::onTick()    MODE_MARGINREQUIRED    = 259.73                   // falsch: online
H1::Moving Average::stdlib::onTick()    MODE_FREEZELEVEL       = 0

// Indikator im Tester, standalone
M15::Moving Average::stdlib::onTick()   ---------------------------------
M15::Moving Average::stdlib::onTick()   Predefined variables for "EURUSD"
M15::Moving Average::stdlib::onTick()   ---------------------------------
M15::Moving Average::stdlib::onTick()   Pip         = 0.0001'0
M15::Moving Average::stdlib::onTick()   PipDigits   = 4
M15::Moving Average::stdlib::onTick()   Digits  (b) = 5
M15::Moving Average::stdlib::onTick()   Point   (b) = 0.0000'1
M15::Moving Average::stdlib::onTick()   PipPoints   = 10
M15::Moving Average::stdlib::onTick()   Bid/Ask (b) = 1.2983'9/1.2986'7                   // falsch: online
M15::Moving Average::stdlib::onTick()   Bars    (b) = 1001
M15::Moving Average::stdlib::onTick()   PriceFormat = ".4'"
M15::Moving Average::stdlib::onTick()   -------------------------
M15::Moving Average::stdlib::onTick()   MarketInfo() for "EURUSD"
M15::Moving Average::stdlib::onTick()   -------------------------
M15::Moving Average::stdlib::onTick()   MODE_LOW               = 1.2967'6                 // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_HIGH              = 1.3027'3                 // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_TIME              = '2012.11.30 23:59:52'    // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_BID               = 1.2983'9                 // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_ASK               = 1.2986'7                 // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_POINT             = 0.0000'1
M15::Moving Average::stdlib::onTick()   MODE_DIGITS            = 5
M15::Moving Average::stdlib::onTick()   MODE_SPREAD            = 28                       // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_STOPLEVEL         = 20
M15::Moving Average::stdlib::onTick()   MODE_LOTSIZE           = 100000
M15::Moving Average::stdlib::onTick()   MODE_TICKVALUE         = 1
M15::Moving Average::stdlib::onTick()   MODE_TICKSIZE          = 0.0000'1
M15::Moving Average::stdlib::onTick()   MODE_SWAPLONG          = -1.3
M15::Moving Average::stdlib::onTick()   MODE_SWAPSHORT         = 0.5
M15::Moving Average::stdlib::onTick()   MODE_STARTING          = 0
M15::Moving Average::stdlib::onTick()   MODE_EXPIRATION        = 0
M15::Moving Average::stdlib::onTick()   MODE_TRADEALLOWED      = 1
M15::Moving Average::stdlib::onTick()   MODE_MINLOT            = 0.01
M15::Moving Average::stdlib::onTick()   MODE_LOTSTEP           = 0.01
M15::Moving Average::stdlib::onTick()   MODE_MAXLOT            = 2
M15::Moving Average::stdlib::onTick()   MODE_SWAPTYPE          = 0
M15::Moving Average::stdlib::onTick()   MODE_PROFITCALCMODE    = 0
M15::Moving Average::stdlib::onTick()   MODE_MARGINCALCMODE    = 0
M15::Moving Average::stdlib::onTick()   MODE_MARGININIT        = 0
M15::Moving Average::stdlib::onTick()   MODE_MARGINMAINTENANCE = 0
M15::Moving Average::stdlib::onTick()   MODE_MARGINHEDGED      = 50000
M15::Moving Average::stdlib::onTick()   MODE_MARGINREQUIRED    = 259.73                   // falsch: online
M15::Moving Average::stdlib::onTick()   MODE_FREEZELEVEL       = 0
*/
