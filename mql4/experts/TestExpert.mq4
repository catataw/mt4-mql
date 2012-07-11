/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {

      /*ORDER_EXECUTION*/int oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);
      oe.setSymbol    (oe, Symbol());
      oe.setDigits    (oe, Digits);
      oe.setBid       (oe, Bid);
      oe.setAsk       (oe, Ask);
      oe.setType      (oe, OP_BUY);
      oe.setLots      (oe, 0.01);
      oe.setTicket    (oe, 12345678);
      oe.setTime      (oe, TimeCurrent());
      oe.setPrice     (oe, (Bid+Ask)/2);
      oe.setStopLoss  (oe, Bid-100*Pip);
      oe.setTakeProfit(oe, Bid+100*Pip);
      oe.setSwap      (oe, 0.19);
      oe.setCommission(oe, 8.00);
      oe.setProfit    (oe, -7.77);
      oe.setComment   (oe, "SR.12345.+5");
      oe.setDuration  (oe, 234);
      oe.setRequotes  (oe, 2);
      oe.setSlippage  (oe, 1.1);

      ORDER_EXECUTION.toStr(oe, true);

      done = true;
   }
   return(catch("onTick()"));
}

