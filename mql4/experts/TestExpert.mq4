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

   static bool done1, done2, done3, done4;
   static int ticket, ticket1, ticket2, partial;

   double execution[] = {NULL};

   if (!done1) {
      if (TimeCurrent() > D'2012.03.19 11:00:00') {
         done1 = true;
         debug("onTick(1)          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");

         execution[EXEC_FLAGS] = NULL;
         ticket1 = OrderSendEx(Symbol(), OP_BUY, 0.7, NULL, NULL, NULL, NULL, "order comment", 111, NULL, Blue, execution);
         if (ticket1 == -1)
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick(1)->open        #"+ ticket1 +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket1, "onTick(1)"))
            return(last_error);
         //debug("onTick(1) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done2) {
      if (TimeCurrent() > D'2012.03.19 14:00:00') {
         done2 = true;

         execution[EXEC_FLAGS] = NULL;
         ticket2 = OrderSendEx(Symbol(), OP_SELL, 1, NULL, NULL, NULL, NULL, "order comment", 222, NULL, Red, execution);
         if (ticket2 == -1)
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick(2)->open        #"+ ticket2 +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket2, "onTick(2)"))
            return(last_error);
         //debug("onTick(2) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done3) {
      if (TimeCurrent() > D'2012.03.20 20:00:00') {
         done3 = true;

         if (!OrderSelectByTicket(ticket1, "onTick(3)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         if (!OrderSelectByTicket(ticket2, "onTick(4)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         /*
         if (!OrderCloseBy(ticket2, ticket1, Orange))
            return(catch("onTick(5)->OrderCloseBy()", ifInt(IsError(SetLastError(GetLastError())), last_error, ERR_RUNTIME_ERROR)));
         */

         execution[EXEC_FLAGS] = NULL;
         if (!OrderCloseByEx(ticket1, ticket2, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(3)->closeBy     #"+ ticket1 +" = "+ ExecutionToStr(execution));


         if (!OrderSelectByTicket(ticket1, "onTick(6)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         if (!OrderSelectByTicket(ticket2, "onTick(7)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         int orders = OrdersTotal();
         for (int i=0; i < orders; i++) {
            OrderSelect(i, SELECT_BY_POS);
            if (OrderTicket() == ticket1) continue;
            if (OrderTicket() == ticket2) continue;
            debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

            execution[EXEC_FLAGS] = NULL;
            if (!OrderCloseEx(OrderTicket(), NULL, NULL, NULL, Orange, execution))
               return(SetLastError(stdlib_PeekLastError()));
            if (!OrderSelectByTicket(OrderTicket(), "onTick(6)"))
               return(last_error);
            debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
            break;
         }
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
