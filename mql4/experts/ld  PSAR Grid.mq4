/**
 * PSAR Martingale Grid
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_PIPVALUE};
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern int    GridSize                        = 40;
extern double StartLotSize                    = 0.1;
extern double IncrementSize                   = 0.1;

extern int    TrailingStop.Percent            = 100;
extern int    MaxDrawdown.Percent             = 100;

extern string ___________Indicator___________ = "___________________________________";
extern double PSAR.Step                       = 0.02;
extern double PSAR.Maximum                    = 0.2;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinStrings.mqh>
#include <stdlib.mqh>
#include <history.mqh>
#include <structs/myfx/ORDER_EXECUTION.mqh>


#define STRATEGY_ID  104                                             // eindeutige ID der Strategie (Bereich 101-1023)

int     magicNo = 110413;
string  comment = "MG.PSAR";                                         // order comment
string  ea.name = "PSAR Martingale Grid";                            // ShowStatus() EA name

#include <Martingale/expert.mq4>


/**
 *
 */
int Strategy.Long() {
   double psar1 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 1);  // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 2);  // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeByteBuffer(oe, ORDER_EXECUTION.size);
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

   // (2) TakeProfit if trailingProfit is hit
   if (long.takeProfit) /*&&*/ if (long.profit <= long.trailingProfit) {
      if (!OrderMultiClose(long.ticket, 0.1, Blue, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetLongStatus();
      return(catch("Strategy.Long(2)"));
   }

   // (3) Martingale if lossTarget is hit and PSAR signals
   // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
   if (long.profit <= long.lossTarget) {
      if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {        // PSAR wechselte von oben nach unten (angeblicher Up-Trend)
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
   double psar1 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 1);  // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), NULL, PSAR.Step, PSAR.Maximum, 2);  // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeByteBuffer(oe, ORDER_EXECUTION.size);
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

   // (2) TakeProfit if trailingProfit is hit
   if (short.takeProfit) /*&&*/ if (short.profit <= short.trailingProfit) {
      if (!OrderMultiClose(short.ticket, 0.1, Red, oeFlags, oes))
         return(SetLastError(oes.Error(oes, 0)));
      ResetShortStatus();
      return(catch("Strategy.Short(2)"));
   }

   // (3) Martingale if lossTarget is hit and PSAR signals
   // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
   if (short.profit <= short.lossTarget) {
      if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {        // PSAR wechselte von unten nach oben (angeblicher Down-Trend)
         ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.profit), NULL, 0.1, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   return(catch("Strategy.Short(3)"));
}
