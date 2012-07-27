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
      oe.setError          (oe, ERR_RUNTIME_ERROR);
      oe.setSymbol         (oe, Symbol());
      oe.setDigits         (oe, Digits);
      oe.setBid            (oe, Bid);
      oe.setAsk            (oe, Ask);
      oe.setTicket         (oe, 12345678);
      oe.setType           (oe, OP_BUY);
      oe.setLots           (oe, 0.03);
      oe.setOpenTime       (oe, TimeCurrent());
      oe.setOpenPrice      (oe, (Bid+Ask)/2);
      oe.setStopLoss       (oe, Bid-100*Pip);
      oe.setTakeProfit     (oe, Bid+100*Pip);
      oe.setCloseTime      (oe, TimeCurrent());
      oe.setClosePrice     (oe, (Bid+Ask)/2);
      oe.addSwap           (oe, 0.19);
      oe.addCommission     (oe, 8.00);
      oe.addProfit         (oe, -7.77);
      oe.setComment        (oe, "SR.12345.+5");
      oe.setDuration       (oe, 234);
      oe.setRequotes       (oe, 2);
      oe.setSlippage       (oe, 1.1);
      oe.setRemainingTicket(oe, 0);
      oe.setRemainingLots  (oe, 0.01);
      ORDER_EXECUTION.toStr(oe, true);

      done = true;
   }
   return(catch("onTick()"));
}
