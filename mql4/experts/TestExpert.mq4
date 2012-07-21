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


      /*ORDER_EXECUTION*/int oes[1][ORDER_EXECUTION.length]; InitializeBuffer(oes, ORDER_EXECUTION.size);
      oes.setSymbol         (oes, 0, Symbol());
      oes.setDigits         (oes, 0, Digits);
      oes.setBid            (oes, 0, Bid);
      oes.setAsk            (oes, 0, Ask);
      oes.setTicket         (oes, 0, 12345678);
      oes.setType           (oes, 0, OP_BUY);
      oes.setLots           (oes, 0, 0.03);
      oes.setOpenTime       (oes, 0, TimeCurrent());
      oes.setOpenPrice      (oes, 0, (Bid+Ask)/2);
      oes.setStopLoss       (oes, 0, Bid-100*Pip);
      oes.setTakeProfit     (oes, 0, Bid+100*Pip);
      oes.setCloseTime      (oes, 0, TimeCurrent());
      oes.setClosePrice     (oes, 0, (Bid+Ask)/2);
      oes.addSwap           (oes, 0, 0.19);
      oes.addCommission     (oes, 0, 8.00);
      oes.addProfit         (oes, 0, -7.77);
      oes.setComment        (oes, 0, "SR.12345.+5");
      oes.setDuration       (oes, 0, 234);
      oes.setRequotes       (oes, 0, 2);
      oes.setSlippage       (oes, 0, 1.1);
      oes.setRemainingTicket(oes, 0, 0);
      oes.setRemainingLots  (oes, 0, 0.01);
      ORDER_EXECUTION.toStr(oes, true);


      done = true;
   }
   return(catch("onTick()"));
}
