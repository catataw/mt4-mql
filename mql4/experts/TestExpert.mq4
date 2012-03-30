/**
 * TestExpert
 */
#include <stdlib.mqh>
#include <win32api.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
      return(last_error);
   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   if (IsError(onDeinit()))
      return(last_error);
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   static bool done1, done2, done3, partial;
   static int ticket;

   double execution[] = {NULL};


   if (!done1) {
      if (TimeCurrent() > D'2012.03.26 11:00:00') {
         done1 = true;
         execution[EXEC_FLAGS] = NULL;

         ticket = OrderSendEx(Symbol(), OP_BUY, 1.0, NULL, NULL, NULL, NULL, "order comment", 666, NULL, Blue, execution);
         if (ticket == -1)
            return(SetLastError(stdlib_PeekLastError()));


         if (!OrderSelectByTicket(ticket, "onTick(1)"))
            return(last_error);
         debug("onTick()          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");
         debug("onTick() open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done2) {
      if (TimeCurrent() > D'2012.03.26 12:00:00') {
         done2 = true;
         execution[EXEC_FLAGS] = NULL;

         if (!OrderCloseEx(ticket, 0.7, NULL, NULL, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick()->OrderCloseEx()  #"+ ticket +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket, "onTick(2)"))
            return(last_error);
         debug("onTick() close "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         if (OrderComment() == "partial close") {
            partial = true;
            int orders = OrdersTotal();

            for (int i=0; i < orders; i++) {
               if (!OrderSelect(i, SELECT_BY_POS))
                  return(catch("onTick(3)"));
               if (OrderTicket() == ticket)
                  continue;
               debug("onTick()       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
            }

         }
         debug("onTick()->close   #"+ ticket +" = "+ ExecutionToStr(execution));
      }
   }

   if (!done3) {
      if (TimeCurrent() > D'2012.03.26 14:00:00') {
         done3 = true;
         if (partial) {
            execution[EXEC_FLAGS] = NULL;

            if (!OrderCloseEx(2, NULL, NULL, NULL, Orange, execution))
               return(SetLastError(stdlib_PeekLastError()));

            if (!OrderSelectByTicket(2, "onTick(4)"))
               return(last_error);
            debug("onTick() close "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
            debug("onTick()->close   #"+ ticket +" = "+ ExecutionToStr(execution));
         }
      }
   }

   return(catch("onTick(5)"));
}
