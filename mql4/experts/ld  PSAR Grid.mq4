/**
 * PSAR Martingale Grid
 *
 * @copyright  http://www.lifesdream.org/
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_PIPVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern int    magic                   = 110412;

// Configuration
extern string CommonSettings          = "---------------------------------------------";
extern int    grid_size               = 40;
extern double profit_lock             =  0.90;

// Money Management
extern string MoneyManagementSettings = "---------------------------------------------";
extern double min_lots                =   0.1;
extern double min_lots_increment      =   0.1;
extern double account_risk            = 100;

// Indicator
extern string IndicatorSettings       = "---------------------------------------------";
extern double psar_step               = 0.02;
extern double psar_maximum            = 0.2;
extern int    shift                   = 1;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int    buy_tickets [50];                                             // Ticket
double buy_lots    [50];                                             // Lots
double buy_price   [50];                                             // Open Price
double buy_profit  [50];                                             // Current Profit

int    sell_tickets[50];
double sell_lots   [50];
double sell_price  [50];
double sell_profit [50];

double psar1, psar2, price1, price2;                                 // Indicator

int    buys;                                                         // Number of orders
int    sells;
double total_buy_profit, total_sell_profit;
double total_buy_lots,   total_sell_lots;
double buy_max_profit,   buy_locked_profit;
double sell_max_profit,  sell_locked_profit;

double balance, equity;

double slippage = 0.1;                                               // order slippage
string comment  = "PSAR Grid";                                       // order comment


/**
 *
 */
int onTick() {
   UpdateVars();
   ShowLines();
   ShowStatus();

   Robot();

   return(catch("onTick()"));
}


/**
 *
 */
void BuyResetAfterClose() {
   buy_max_profit    = 0;
   buy_locked_profit = 0;
   ObjectDelete("line_buy_tp");
   ObjectDelete("line_buy_ts");

   catch("BuyResetAfterClose()");
}


/**
 *
 */
void SellResetAfterClose() {
   sell_max_profit    = 0;
   sell_locked_profit = 0;
   ObjectDelete("line_sell_tp");
   ObjectDelete("line_sell_ts");

   catch("SellResetAfterClose()");
}


/**
 *
 */
void UpdateVars() {
   // reset vars
   buys              = 0;
   sells             = 0;
   total_buy_profit  = 0;
   total_sell_profit = 0;
   total_buy_lots    = 0;
   total_sell_lots   = 0;

   ArrayInitialize(buy_tickets,  0);
   ArrayInitialize(buy_lots,     0);
   ArrayInitialize(buy_profit,   0);
   ArrayInitialize(buy_price,    0);
   ArrayInitialize(sell_tickets, 0);
   ArrayInitialize(sell_lots,    0);
   ArrayInitialize(sell_profit,  0);
   ArrayInitialize(sell_price,   0);

   // we are going to introduce data from opened orders in arrays
   for (int i=0; i < OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol()==Symbol()) /*&&*/ if (OrderMagicNumber()==magic) {
            if (OrderType() == OP_BUY) {
               buy_tickets[buys] = OrderTicket();
               buy_lots   [buys] = OrderLots();
               buy_profit [buys] = OrderProfit() + OrderCommission() + OrderSwap();
               buy_price  [buys] = OrderOpenPrice();
               total_buy_profit += buy_profit[buys];
               total_buy_lots   += OrderLots();
               buys++;
            }
            else if (OrderType() == OP_SELL) {
               sell_tickets[sells] = OrderTicket();
               sell_lots   [sells] = OrderLots();
               sell_profit [sells] = OrderProfit() + OrderCommission() + OrderSwap();
               sell_price  [sells] = OrderOpenPrice();
               total_sell_profit  += sell_profit[sells];
               total_sell_lots    += OrderLots();
               sells++;
            }
         }
      }
   }

   SortByLots();

   catch("UpdateVars()");
}


/**
 *
 */
void SortByLots() {
   int    iTmp;
   double dTmp;

   // We are going to sort orders by volume
   // m[0] smallest volume m[size-1] largest volume

   // BUY ORDERS
   for (int i=0; i < buys-1; i++) {
      // at least 2 orders
      for (int j=i+1; j < buys; j++) {
         if (buy_lots[j] < buy_lots[i]) {
            // ...lots
            dTmp           = buy_lots[i];
            buy_lots[i]    = buy_lots[j];
            buy_lots[j]    = dTmp;
            // ...tickets
            iTmp           = buy_tickets[i];
            buy_tickets[i] = buy_tickets[j];
            buy_tickets[j] = iTmp;
            // ...profits
            dTmp           = buy_profit[i];
            buy_profit[i]  = buy_profit[j];
            buy_profit[j]  = dTmp;
            // ...open price
            dTmp           = buy_price[i];
            buy_price[i]   = buy_price[j];
            buy_price[j]   = dTmp;
         }
      }
   }

   // SELL ORDERS
   for (i=0; i < sells-1; i++) {
      // at least 2 orders
      for (j=i+1; j < sells; j++) {
         if (sell_lots[j] < sell_lots[i]) {
            // ...lots
            dTmp            = sell_lots[i];
            sell_lots[i]    = sell_lots[j];
            sell_lots[j]    = dTmp;
            // ...tickets
            iTmp            = sell_tickets[i];
            sell_tickets[i] = sell_tickets[j];
            sell_tickets[j] = iTmp;
            // ...profits
            dTmp            = sell_profit[i];
            sell_profit[i]  = sell_profit[j];
            sell_profit[j]  = dTmp;
            // ...open price
            dTmp            = sell_price[i];
            sell_price[i]   = sell_price[j];
            sell_price[j]   = dTmp;
         }
      }
   }
   catch("SortByLots()");
}


/**
 *
 */
void ShowLines() {
   int units, sumUnits;
   double sumOpenPrice, takeProfit, trailingStop;

   if (buys > 0) {
      sumUnits     = 0;
      sumOpenPrice = 0;
      for (int i=0; i<buys; i++) {
         units         = Round(buy_lots[i] / min_lots);
         sumUnits     +=  units;
         sumOpenPrice += (units * buy_price[i]);
      }
      takeProfit = (sumOpenPrice + grid_size*Pip) / sumUnits;
      HorizontalLine(takeProfit, "line_buy_tp", DodgerBlue, STYLE_SOLID, 2);

      if (buy_locked_profit > 0) {
         trailingStop = (sumOpenPrice + buy_locked_profit/PipValue(min_lots)*Pip) / sumUnits;
         HorizontalLine(trailingStop, "line_buy_ts", DodgerBlue, STYLE_DASH, 1);
      }
   }

   if (sells > 0) {
      sumUnits     = 0;
      sumOpenPrice = 0;
      for (i=0; i<sells; i++) {
         units         =  Round(sell_lots[i] / min_lots);
         sumUnits     +=  units;
         sumOpenPrice += (units * sell_price[i]);
      }
      takeProfit = (sumOpenPrice - grid_size*Pip) / sumUnits;
      HorizontalLine(takeProfit, "line_sell_tp", Tomato, STYLE_SOLID, 2);

      if (sell_locked_profit > 0) {
         trailingStop = (sumOpenPrice - sell_locked_profit/PipValue(min_lots)*Pip) / sumUnits;
         HorizontalLine(trailingStop, "line_sell_ts", Tomato, STYLE_DASH, 1);
      }
   }
   catch("ShowLines()");
}


/**
 *
 */
int ShowStatus() {
   string txt;
   double aux_tp_buy, aux_tp_sell;

   if (buys > 0) {
      aux_tp_buy = GridValue(min_lots);
   }

   if (sells > 0) {
      aux_tp_sell = GridValue(min_lots);
   }

   txt = NL +
         "\nPSAR Martingale Grid"    +
         "\n"                        +
         "\nSETTINGS: "              +
         "\nGrid size: "             + grid_size +
         "\nProfit locked: "         + DoubleToStr(100*profit_lock, 2) + "%"+
         "\nMinimum lots: "          + DoubleToStr(min_lots, 2) +
         "\nAccount risk: "          + DoubleToStr(account_risk, 0) + "%"+
         "\nPSAR step: "             + DoubleToStr(psar_step, 0) +
         "\nPSAR maximum: "          + DoubleToStr(psar_maximum, 0) +
         "\nPSAR shift: "            + DoubleToStr(shift, 0) +
         "\n"                        +
         "\nBUY ORDERS"              +
         "\nNumber of orders: "      + buys +
         "\nTotal lots: "            + DoubleToStr(total_buy_lots, 2) +
         "\nCurrent profit: "        + DoubleToStr(total_buy_profit, 2) +
         "\nProfit target: "         + DoubleToStr(aux_tp_buy, 2) +
         "\nMaximum profit reached: "+ DoubleToStr(buy_max_profit, 2) +
         "\nProfit locked: "         + DoubleToStr(buy_locked_profit, 2) +
         "\n"                        +
         "\nSELL ORDERS"             +
         "\nNumber of orders: "      + sells +
         "\nTotal lots: "            + DoubleToStr(total_sell_lots, 2) +
         "\nCurrent profit: "        + DoubleToStr(total_sell_profit, 2) +
         "\nProfit target: "         + DoubleToStr(aux_tp_sell, 2) +
         "\nMaximum profit reached: "+ DoubleToStr(sell_max_profit, 2) +
         "\nProfit locked: "         + DoubleToStr(sell_locked_profit, 2);
   Comment(txt);

   catch("ShowData()");
}


/**
 *
 */
void HorizontalLine(double value, string name, color lineColor, int style, int thickness) {
   if (ObjectFind(name) == -1) {
      ObjectCreate(name, OBJ_HLINE, 0, Time[0], value);
      ObjectSet   (name, OBJPROP_STYLE, style    );
      ObjectSet   (name, OBJPROP_COLOR, lineColor);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   else {
      ObjectSet   (name, OBJPROP_PRICE1, value);
      ObjectSet   (name, OBJPROP_STYLE, style    );
      ObjectSet   (name, OBJPROP_COLOR, lineColor);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   catch("HorizontalLine()");
}


/**
 *
 */
double MartingaleVolume(double losses) {
   double grid_value = GridValue(min_lots);
   double multiplier = MathFloor(MathAbs(losses/grid_value));
   double lots       = NormalizeDouble(multiplier * min_lots_increment, CountDecimals(min_lots_increment));

   if (lots < min_lots)                          lots = min_lots;
   if (lots > MarketInfo(Symbol(), MODE_MAXLOT)) lots = MarketInfo(Symbol(), MODE_MAXLOT);
   if (lots < MarketInfo(Symbol(), MODE_MINLOT)) lots = MarketInfo(Symbol(), MODE_MINLOT);

   catch("MartingaleVolume()");
   return(lots);
}


/**
 *
 */
double GridValue(double volume) {
   return(grid_size * PipValue(volume));
}


/**
 *
 */
void Robot() {
   int i, ticket=-1;

   psar1  =   iSAR(Symbol(), 0, psar_step, psar_maximum, shift  );
   psar2  =   iSAR(Symbol(), 0, psar_step, psar_maximum, shift+1);
   price1 = iClose(Symbol(), 0, shift  );
   price2 = iClose(Symbol(), 0, shift+1);

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);

   // *************************
   // ACCOUNT RISK CONTROL
   // *************************
   if ((100-account_risk)/100 * AccountBalance() > AccountEquity()) {
      // Closing buy orders
      for (i=0; i<=buys-1; i++) {
         if (!OrderCloseEx(buy_tickets[i], buy_lots[i], Bid, slippage, Blue, oeFlags, oe))
            return(_NULL(SetLastError(oe.Error(oe))));
      }
      // Closing sell orders
      for (i=0; i<=sells-1; i++) {
         if (!OrderCloseEx(sell_tickets[i], sell_lots[i], Ask, slippage, Red, oeFlags, oe))
            return(_NULL(SetLastError(oe.Error(oe))));
      }
      BuyResetAfterClose();
      SellResetAfterClose();
   }

   // **************************************************
   // BUYS == 0
   // **************************************************
   if (buys == 0) {
      if (psar1 < price1) /*&&*/ if (psar2 > price2) {
         ticket = OrderSendEx(Symbol(), OP_BUY, min_lots, Ask, slippage, 0, 0, comment, magic, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(_NULL(SetLastError(oe.Error(oe))));
      }
   }

   // **************************************************
   // BUYS > 0
   // **************************************************
   if (buys > 0) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (total_buy_profit < -GridValue(total_buy_lots)) {
         if (buys < 50 && psar1 < price1 && psar2 > price2) {
            ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(total_buy_profit), Ask, slippage, 0, 0, comment, magic, 0, Blue, oeFlags, oe);
            if (ticket <= 0)
               return(_NULL(SetLastError(oe.Error(oe))));
         }
      }

      // CASE 2.1 >>> We reach Take Profit so we activate profit lock
      if (buy_max_profit==0 && total_buy_profit > GridValue(min_lots)) {
         buy_max_profit    = total_buy_profit;
         buy_locked_profit = profit_lock * buy_max_profit;
      }

      // CASE 2.2 >>> Profit locked is updated in real time
      if (buy_max_profit > 0) {
         if (total_buy_profit > buy_max_profit) {
            buy_max_profit    = total_buy_profit;
            buy_locked_profit = profit_lock * total_buy_profit;
         }
      }

      // CASE 2.3 >>> If profit falls below profit locked we close all orders
      if (buy_max_profit>0 && buy_locked_profit>0 && buy_max_profit>buy_locked_profit && total_buy_profit<buy_locked_profit) {
         for (i=0; i<=buys-1; i++) {
            if (!OrderCloseEx(buy_tickets[i], buy_lots[i], Bid, slippage, Blue, oeFlags, oe))
               return(_NULL(SetLastError(oe.Error(oe))));
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateVars() on next start() execution
         BuyResetAfterClose();
      }
   }

   // **************************************************
   // SELLS == 0
   // **************************************************
   if (sells == 0) {
      if (psar1 > price1) /*&&*/ if (psar2 < price2) {
         ticket = OrderSendEx(Symbol(), OP_SELL, min_lots, Bid, slippage, 0, 0, comment, magic, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(_NULL(SetLastError(oe.Error(oe))));
      }
   }

   // **************************************************
   // SELLS > 0
   // **************************************************
   if (sells > 0) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (total_sell_profit < -GridValue(total_sell_lots)) {
         if (sells<50 && psar1>price1 && psar2<price2) {
            ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(total_sell_profit), Bid, slippage, 0, 0, comment, magic, 0, Red, oeFlags, oe);
            if (ticket <= 0)
               return(_NULL(SetLastError(oe.Error(oe))));
         }
      }

      // CASE 2.1 >>> We reach Take Profit so we activate profit lock
      if (sell_max_profit==0 && total_sell_profit > GridValue(min_lots)) {
         sell_max_profit    = total_sell_profit;
         sell_locked_profit = profit_lock*sell_max_profit;
      }

      // CASE 2.2 >>> Profit locked is updated in real time
      if (sell_max_profit > 0) {
         if (total_sell_profit > sell_max_profit) {
            sell_max_profit    = total_sell_profit;
            sell_locked_profit = profit_lock*sell_max_profit;
         }
      }

      // CASE 2.3 >>> If profit falls below profit locked we close all orders
      if (sell_max_profit>0 && sell_locked_profit>0 && sell_max_profit>sell_locked_profit && total_sell_profit<sell_locked_profit) {
         for (i=0; i<=sells-1; i++) {
            if (!OrderCloseEx(sell_tickets[i], sell_lots[i], Ask, slippage, Red, oeFlags, oe))
               return(_NULL(SetLastError(oe.Error(oe))));
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateVars() on next start() execution
         SellResetAfterClose();
      }
   }
   catch("Robot()");
}
