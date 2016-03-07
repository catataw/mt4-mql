/**
 * Auf das XTrade-Framework umgestellte Version des "MetaQuotes Example MA". Die Strategie ist unver�ndert.
 */
#property copyright "(modified MetaQuotes version)"

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern int    MA.Period = 12;
extern int    MA.Shift  =  6;
extern double Lotsize   =  1.0;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>


bool isOpenPosition = false;
int  slippage       = 5;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   //debug("onTick()  Bars="+ Bars +"  Time="+ TimeToStr(MarketInfo(Symbol(), MODE_TIME), TIME_FULL) +"  Bid="+ NumberToStr(Bid, PriceFormat) +"  Ask="+ NumberToStr(Ask, PriceFormat) +"  Vol="+ _int(Volume[0]));

   // check current position
   if (!isOpenPosition) CheckForOpenSignal();
   else                 CheckForCloseSignal();        // Es ist maximal eine Position (Long oder Short) offen.
   return(last_error);
}


/**
 * Check for entry conditions
 */
void CheckForOpenSignal() {
   if (Volume[0] > 1)            // open positions only onBarOpen
      return;

   static double   stopLoss    = NULL;
   static double   takeProfit  = NULL;
   static string   comment     = "";
   static datetime expiration  = NULL;
   static int      magicNumber = NULL;

   // Simple Moving Average of Bar[MA.Shift]
   double ma = iMA(NULL, NULL, MA.Period, MA.Shift, MODE_SMA, PRICE_CLOSE, 0);                              // MA[0] mit MA.Shift entspricht MA[Shift] bei Shift=0.
                                                                                                            // Mit einem SMA(12) liegt jede Bar zumindest in der N�he des
   // Bl�dsinn: Long-Signal, wenn die letzte Bar bullish war und MA[6] innerhalb ihres Bodies liegt.        // MA, die Entry-Signale sind also praktisch zuf�llig.
   if (Open[1] < ma && Close[1] > ma) {
      OrderSend(Symbol(), OP_BUY, Lotsize, Ask, slippage, stopLoss, takeProfit, comment, magicNumber, expiration, Blue);
      isOpenPosition = true;
      return;
   }

   // Bl�dsinn: Short-Signal, wenn kein Long-Signal, die letzte Bar bearish war und MA[6] innerhalb ihres Bodies liegt.
   if (Open[1] > ma && Close[1] < ma) {
      OrderSend(Symbol(), OP_SELL, Lotsize, Bid, slippage, stopLoss, takeProfit, comment, magicNumber, expiration, Red);
      isOpenPosition = true;
      return;
   }
}


/**
 * Check for exit conditions                                                  // Da es keinen TakeProfit gibt und der fast zuf�llige Exit in der N�he des Entries
 *                                                                            // wie ein kleiner StopLoss wirkt, provoziert die Strategie viele kleine Verluste.
 * Es ist maximal eine Position (Long oder Short) offen.                      // Sie verh�lt sich �hnlich einer umgedrehten Scalping-Strategie, entsprechend verursachen
 */                                                                           // Slippage, Spread und Geb�hren massive Schwankungen (in diesem Fall beim Verlust).
void CheckForCloseSignal() {
   if (Volume[0] > 1)                                                         // close only onBarOpen
      return;
   static bool orderLogged = false;


   // Simple Moving Average of MA[Shift]
   double ma = iMA(NULL, NULL, MA.Period, MA.Shift, MODE_SMA, PRICE_CLOSE, 0);

   int orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;

      if (OrderType() == OP_BUY) {                                            // Bl�dsinn analog zum Entry-Signal
         if (Open[1] > ma) /*&&*/ if(Close[1] < ma) {
            OrderClose(OrderTicket(), OrderLots(), Bid, slippage, Gold);      // Exit-Long, wenn die letzte Bar bearisch war und MA[Shift] innerhalb ihres Bodies liegt.
            isOpenPosition = false;
            if (!orderLogged) orderLogged = OrderLog(OrderTicket());
         }
         break;
      }

      if (OrderType() == OP_SELL) {
         if (Open[1] < ma) /*&&*/ if (Close[1] > ma) {                        // Exit-Short, wenn die letzte Bar bullish war und MA[Shift] innerhalb ihres Bodies liegt.
            OrderClose(OrderTicket(), OrderLots(), Ask, slippage, Gold);
            isOpenPosition = false;
            if (!orderLogged) orderLogged = OrderLog(OrderTicket());
         }
         break;
      }
   }
}
