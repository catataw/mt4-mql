/**
 * PSAR Martingale Grid
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_PIPVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern int    GridSize                        = 40;
extern double StartLotSize                    = 0.1;
extern double IncrementSize                   = 0.1;

extern int    TrailingStop.Percent            = 100;
extern int    MaxDrawdown.Percent             = 100;

extern string ___________Indicator___________ = "___________________________________";
extern double PSAR.Step                       = 0.02;
extern double PSAR.Maximum                    = 0.2;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int    magicNo = 110413;
string comment = "ld04 PSAR";                                        // order comment
string ea.name = "PSAR Martingale Grid";                             // ShowStatus() EA name

#include <Martingale/expert.mq4>


/**
 *
 */
int Strategy.Long() {
   double psar1 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 1);  // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 2);  // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket;

   // (1) Start
   if (long.level == 0) {
      if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {           // PSAR wechselte von oben nach unten (angeblicher Up-Trend)
         long.startEquity = AccountEquity() - AccountCredit();
         ticket           = OrderSendEx(Symbol(), OP_BUY, StartLotSize, NULL, 0.1, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddLongOrder(ticket, StartLotSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
      return(catch("Strategy.Long(1)"));
   }

   // (2) TakeProfit: if trailingProfit is hit we close everything
   if (long.takeProfit) /*&&*/ if (long.sumProfit <= long.trailingProfit) {
      if (!OrderMultiClose(long.ticket, 0.1, Blue, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetLongStatus();
      return(catch("Strategy.Long(2)"));
   }

   // (3) Martingale: if LossTarget is hit and PSAR crossed we "double up"
   // T�dlich: Martingale-Spirale, da mehrere neue Orders w�hrend derselben Bar ge�ffnet werden k�nnen
   if (long.sumProfit <= long.lossTarget) {
      if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {        // PSAR wechselte von oben nach unten (angeblicher Up-Trend)
         ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(long.sumProfit), NULL, 0.1, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
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
   double psar1 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 1);  // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 2);  // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket;

   // (1) Start
   if (short.level == 0) {
      if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {           // PSAR wechselte von unten nach oben (angeblicher Down-Trend)
         short.startEquity = AccountEquity() - AccountCredit();
         ticket            = OrderSendEx(Symbol(), OP_SELL, StartLotSize, NULL, 0.1, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, StartLotSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
      return(catch("Strategy.Short(1)"));
   }

   // (2) TakeProfit: if trailingProfit is hit we close everything
   if (short.takeProfit) /*&&*/ if (short.sumProfit <= short.trailingProfit) {
      if (!OrderMultiClose(short.ticket, 0.1, Red, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetShortStatus();
      return(catch("Strategy.Short(2)"));
   }

   // (3) Martingale: if LossTarget is hit and PSAR crossed we "double up"
   // T�dlich: Martingale-Spirale, da mehrere neue Orders w�hrend derselben Bar ge�ffnet werden k�nnen
   if (short.sumProfit <= short.lossTarget) {
      if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {        // PSAR wechselte von unten nach oben (angeblicher Down-Trend)
         ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.sumProfit), NULL, 0.1, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   return(catch("Strategy.Short(3)"));
}
