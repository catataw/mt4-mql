/**
 * RSI Martingale Grid
 *
 * Der RSI ist im wesentlichen eine andere Darstellung eines Bollinger-Bands, also ein Momentum-Indikator.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_PIPVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <history.mqh>

#include <core/expert.mqh>


#import "history.ex4"
   int    hstlib_init(int type, string name, int whereami, bool isChart, bool isOfflineChart, int _iCustom, int initFlags, int uninitializeReason);
   int    hstlib_deinit(int deinitFlags, int uninitializeReason);
#import


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern int    GridSize                        = 70;
extern double StartLotSize                    = 0.1;
extern double IncrementSize                   = 0.1;

extern int    TrailingStop.Percent            = 100;
extern int    MaxDrawdown.Percent             = 100;

extern string ___________Indicator___________ = "___________________________________";
extern int    RSI.Period                      =  7;
extern double RSI.SignalLevel                 = 20;
extern int    RSI.Shift                       =  0;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


#define STRATEGY_ID  105                                             // eindeutige ID der Strategie (Bereich 101-1023)

int     magicNo = 50854;
string  comment = "M.RSI";                                           // order comment
string  ea.name = "RSI Martingale Grid";                             // ShowStatus() EA name

#include <Martingale/expert.mq4>


/**
 *
 */
int Strategy.Long() {
   double rsi = iRSI(Symbol(), NULL, RSI.Period, PRICE_CLOSE, RSI.Shift);  // Bar[0] (current unfinished bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket;


   // (1) Start
   if (long.level == 0) {
      if (rsi < 100-RSI.SignalLevel) {                                     // RSI liegt "irgendwo" unterm High (um nach TakeProfit sofortigen Wiedereinstieg zu triggern)
         long.startEquity = AccountEquity() - AccountCredit();
         ticket           = OrderSendEx(Symbol(), OP_BUY, StartLotSize, NULL, 0.1, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddLongOrder(ticket, StartLotSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
      return(catch("Strategy.Long(1)"));
   }

   // (2) TakeProfit if trailingProfit is hit
   if (long.takeProfit) /*&&*/ if (long.profit <= long.trailingProfit) {
      if (!OrderMultiClose(long.ticket, 0.1, Blue, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetLongStatus();
      return(catch("Strategy.Long(2)"));
   }

   // (3) Martingale if lossTarget is hit and RSI signals
   // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
   if (long.profit <= long.lossTarget) {
      if (rsi < RSI.SignalLevel) {                                         // RSI crossed low signal line: starkes Down-Momentum
         ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(long.profit), NULL, 0.1, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddLongOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   return(catch("Strategy.Long(3)"));
}


/**
 *
 */
int Strategy.Short() {
   double rsi = iRSI(Symbol(), NULL, RSI.Period, PRICE_CLOSE, RSI.Shift);  // Bar[0] (current unfinished bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket;

   // (1) Start
   if (short.level == 0) {
      if (rsi > RSI.SignalLevel) {                                         // RSI liegt "irgendwo" überm Low (um nach TakeProfit sofortigen Wiedereinstieg zu triggern)
         short.startEquity = AccountEquity() - AccountCredit();
         ticket            = OrderSendEx(Symbol(), OP_SELL, StartLotSize, NULL, 0.1, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, StartLotSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
      return(catch("Strategy.Short(1)"));
   }

   // (2) TakeProfit if trailingProfit is hit
   if (short.takeProfit) /*&&*/ if (short.profit <= short.trailingProfit) {
      if (!OrderMultiClose(short.ticket, 0.1, Red, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetShortStatus();
      return(catch("Strategy.Short(2)"));
   }

   // (3) Martingale if lossTarget is hit and RSI signals
   // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
   if (short.profit <= short.lossTarget) {
      if (rsi > 100-RSI.SignalLevel) {                                     // RSI crossed high signal line: starkes Up-Momentum
         ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.profit), NULL, 0.1, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   return(catch("Strategy.Short(3)"));
}



/**
 * 2011.09.01-2011.12.01 GBPUSD,M5::ld  RSI Grid::onDeinit()   time=41.1 sec   days=91   (0.452 sec/day) - Original-Orderfunktionen
 *                       GBPUSD,M5::ld  RSI Grid::onDeinit()   time=34.7 sec   days=91   (0.382 sec/day) - virtuelle Orderfunktionen: 18% schneller
 *
int onDeinit() {
   double test.duration = (Test.stopMillis-Test.startMillis)/1000.0;
   double test.days     = (Test.toDate-Test.fromDate) * 1.0 /DAYS;
   debug("onDeinit()   time="+ DoubleToStr(test.duration, 1) +" sec   days="+ Round(test.days) +"   ("+ DoubleToStr(test.duration/test.days, 3) +" sec/day)");
   return(last_error);
}
 */
