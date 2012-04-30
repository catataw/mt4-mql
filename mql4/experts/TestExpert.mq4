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

   /*
   static bool boolWInit = false;
   static bool boolWoInit;

   debug("onTick()   boolWInit="+ BoolToStr(boolWInit) +"   boolWoInit="+ BoolToStr(boolWoInit));

   boolWInit  = !boolWInit;
   boolWoInit = !boolWoInit;

   return(NO_ERROR);


   static datetime startTime;
   if (startTime == 0)
      startTime = TimeCurrent();


   static bool done1, done2, done3, done4, done5;
   static int ticket, ticket1, ticket2, ticket3, ticket4, ticket5, partial, button;

   double execution[] = {NULL};


   if (!done1) {
      if (TimeCurrent() > startTime + 1*HOUR) {
         done1 = true;
         debug("onTick(1)          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");

         execution[EXEC_FLAGS] = NULL;
         ticket1 = OrderSendEx(Symbol(), OP_BUY, 0.7, NULL, NULL, NULL, NULL, "order comment", 111, NULL, Blue, execution);
         if (ticket1 == -1)
            return(SetLastError(stdlib_PeekLastError()));
      }
   }

   if (!done2) {
      if (TimeCurrent() > startTime + 2*HOURS) {
         done2 = true;

         execution[EXEC_FLAGS] = NULL;
         ticket2 = OrderSendEx(Symbol(), OP_SELL, 1, NULL, NULL, NULL, NULL, "order comment", 222, NULL, Red, execution);
         if (ticket2 == -1)
            return(SetLastError(stdlib_PeekLastError()));
      }
   }

   if (!done3) {
      if (TimeCurrent() > startTime + 3*HOURS) {
         done3 = true;

         execution[EXEC_FLAGS] = NULL;
         ticket3 = OrderSendEx(Symbol(), OP_SELL, 2.7, NULL, NULL, NULL, NULL, "order comment", 222, NULL, Red, execution);
         if (ticket3 == -1)
            return(SetLastError(stdlib_PeekLastError()));
      }
   }

   if (!done4) {
      if (TimeCurrent() > startTime + 4*HOURS) {
         done4 = true;

         WaitForTicket(ticket1, false);
         debug("onTick(4)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         WaitForTicket(ticket2, false);
         debug("onTick(4)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         WaitForTicket(ticket3, false);
         debug("onTick(4)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         int tickets[]; ArrayResize(tickets, 0);
         ArrayPushInt(tickets, ticket1);
         ArrayPushInt(tickets, ticket2);
         ArrayPushInt(tickets, ticket3);

         execution[EXEC_FLAGS] = NULL;
         if (!OrderMultiClose(tickets, NULL, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         ExecutionToStr(execution, true);
      }
   }

   if (!done5) {
      if (TimeCurrent() > startTime + 5*HOURS) {
         done5 = true;

         ArrayResize(tickets, 0);
         for (int i=0; i < OrdersHistoryTotal(); i++) {
            OrderSelect(i, SELECT_BY_POS, MODE_HISTORY);
            ArrayPushInt(tickets, OrderTicket());
         }
         ArraySort(tickets);

         for (i=0; i < ArraySize(tickets); i++) {
            WaitForTicket(tickets[i], false);
            debug("onTick(5)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         }
      }
   }

   if (!done3) {
      if (TimeCurrent() > startTime + 3*HOURS) {
         done3 = true;

         WaitForTicket(ticket1, false);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         WaitForTicket(ticket2, false);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         int tickets[];
         ArrayPushInt(tickets, ticket1);
         ArrayPushInt(tickets, ticket2);

         execution[EXEC_FLAGS] = NULL;
         if (!OrderMultiClose(tickets, NULL, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(3) ->OrderMultiClose = "+ ExecutionToStr(execution, false));

         WaitForTicket(ticket1, false);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         WaitForTicket(ticket2, false);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         int orders = OrdersHistoryTotal();
         for (int i=0; i < orders; i++) {
            OrderSelect(i, SELECT_BY_POS, MODE_HISTORY);
            debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad( ifString(OrderCloseTime()==0, "", NumberToStr(OrderClosePrice(), PriceFormat)), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         }
      }
   }
   */
   return(catch("onTick()"));
}
