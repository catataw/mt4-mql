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
   if (IsError(prev_error))
      return(prev_error);

   static bool done1, done2, done3;
   static int ticket, partial;

   double execution[] = {NULL};

   if (!done1) {
      if (TimeCurrent() > D'2012.03.19 11:00:00') {
         done1 = true;
         debug("onTick(1)          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");

         execution[EXEC_FLAGS] = NULL;
         ticket = OrderSendEx(Symbol(), OP_BUYSTOP, 1, Ask+1000*Pip, NULL, NULL, NULL, "order comment", 666, NULL, Blue, execution);
         if (ticket == -1)
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick(1)->open        #"+ ticket +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket, "onTick(1)"))
            return(last_error);
         //debug("onTick(1) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done2) {
      if (TimeCurrent() > D'2012.03.20 12:00:00') {
         done2 = true;

         if (!OrderSelectByTicket(ticket, "onTick(2)"))
            return(last_error);
         debug("onTick(2)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         execution[EXEC_FLAGS] = NULL;
         if (!OrderDeleteEx(ticket, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(2)->delete      #"+ ticket +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(OrderTicket(), "onTick(3)"))
            return(last_error);
         debug("onTick(2) delete"+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }



   /*
   if (!done1) {
      if (TimeCurrent() > D'2012.03.19 11:00:00') {
         done1 = true;
         debug("onTick(1)          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");

         execution[EXEC_FLAGS] = NULL;
         ticket = OrderSendEx(Symbol(), OP_BUY, 1.0, NULL, NULL, NULL, NULL, "order comment", 666, NULL, Blue, execution);
         if (ticket == -1)
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(1)->open        #"+ ticket +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket, "onTick(1)"))
            return(last_error);
         debug("onTick(1) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done2) {
      if (TimeCurrent() > D'2012.03.20 12:00:00') {
         done2 = true;

         if (!OrderSelectByTicket(ticket, "onTick(2)"))
            return(last_error);
         debug("onTick(2)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         execution[EXEC_FLAGS] = NULL;
         if (!OrderCloseEx(ticket, 0.7, NULL, NULL, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(2)->close       #"+ ticket +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(OrderTicket(), "onTick(3)"))
            return(last_error);
         debug("onTick(2) close "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         partial = execution[EXEC_TICKET] +0.1;
         if (partial != 0) {
            if (!OrderSelectByTicket(partial, "onTick(4)"))
               return(last_error);
            debug("onTick(2)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         }
      }
   }

   if (!done3) {
      if (TimeCurrent() > D'2012.03.21 14:00:00') {
         done3 = true;

         if (partial != 0) {
            if (!OrderSelectByTicket(partial, "onTick(5)"))
               return(last_error);
            debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

            execution[EXEC_FLAGS] = NULL;
            if (!OrderCloseEx(partial, NULL, NULL, NULL, Orange, execution))
               return(SetLastError(stdlib_PeekLastError()));
            debug("onTick(3)->close       #"+ partial +" = "+ ExecutionToStr(execution));

            if (!OrderSelectByTicket(partial, "onTick(6)"))
               return(last_error);
            debug("onTick(3) close "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         }
      }
   }
   */

   return(catch("onTick(7)"));
}
