/**
 * PSAR Grid v1.5
 *
 * @copyright  http://www.lifesdream.org/
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
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


string key = "PSAR Grid v1.5";

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
double buy_max_profit,   buy_close_profit;
double sell_max_profit,  sell_close_profit;

double balance, equity;

int    retry_attempts       = 10;                                    // OrderReliable
double sleep_time           =  4.0;
double sleep_maximum        = 25;                                    // in seconds
string OrderReliable_Fname  = "OrderReliable fname unset";
string OrderReliableVersion = "V1_1_1";
int    _OR_err;


/**
 *
 */
int onTick() {
   if (!IsTradeAllowed()) {
      Comment("Copyright © 2011, www.lifesdream.org\nTrading not allowed.");
      return(catch("onTick(1)"));
   }

   // Updating current status
   InitVars();
   UpdateVars();
   SortByLots();
   ShowStatus();
   ShowLines();

   Robot();

   return(catch("onTick(2)"));
}


/**
 *
 */
void InitVars() {
   // Reset number of buy/sell orders
   buys  = 0;
   sells = 0;

   // Reset arrays
   for (int i=0; i<50; i++) {
      buy_tickets [i] = 0;
      buy_lots    [i] = 0;
      buy_profit  [i] = 0;
      buy_price   [i] = 0;
      sell_tickets[i] = 0;
      sell_lots   [i] = 0;
      sell_profit [i] = 0;
      sell_price  [i] = 0;
   }
   catch("InitVars()");
}


/**
 *
 */
void BuyResetAfterClose() {
   buy_max_profit   = 0;
   buy_close_profit = 0;
   ObjectDelete("line_buy"   );
   ObjectDelete("line_buy_ts");

   catch("BuyResetAfterClose()");
}


/**
 *
 */
void SellResetAfterClose() {
   sell_max_profit   = 0;
   sell_close_profit = 0;
   ObjectDelete("line_sell"   );
   ObjectDelete("line_sell_ts");

   catch("SellResetAfterClose()");
}


/**
 *
 */
void UpdateVars() {
   int    aux_buys, aux_sells;
   double aux_total_buy_profit, aux_total_sell_profit;
   double aux_total_buy_lots,   aux_total_sell_lots;

   // We are going to introduce data from opened orders in arrays
   for (int i=0; i<OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderType()==OP_BUY) {
            buy_tickets[aux_buys] = OrderTicket();
            buy_lots   [aux_buys] = OrderLots();
            buy_profit [aux_buys] = OrderProfit() + OrderCommission() + OrderSwap();
            buy_price  [aux_buys] = OrderOpenPrice();
            aux_total_buy_profit  = aux_total_buy_profit + buy_profit[aux_buys];
            aux_total_buy_lots    = aux_total_buy_lots + OrderLots();
            aux_buys++;
         }
         if (OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderType()==OP_SELL) {
            sell_tickets[aux_sells] = OrderTicket();
            sell_lots   [aux_sells] = OrderLots();
            sell_profit [aux_sells] = OrderProfit() + OrderCommission() + OrderSwap();
            sell_price  [aux_sells] = OrderOpenPrice();
            aux_total_sell_profit   = aux_total_sell_profit + sell_profit[aux_sells];
            aux_total_sell_lots     = aux_total_sell_lots + OrderLots();
            aux_sells++;
         }
      }
   }

   // Update global vars
   buys              = aux_buys;
   sells             = aux_sells;
   total_buy_profit  = aux_total_buy_profit;
   total_sell_profit = aux_total_sell_profit;
   total_buy_lots    = aux_total_buy_lots;
   total_sell_lots   = aux_total_sell_lots;

   catch("UpdateVars()");
}


/**
 *
 */
void SortByLots() {
   int aux_tickets;
   double aux_lots, aux_profit, aux_price;

   // We are going to sort orders by volume
   // m[0] smallest volume m[size-1] largest volume

   // BUY ORDERS
   for (int i=0; i<buys-1; i++) {
      for (int j=i+1; j<buys; j++) {
         if (buy_lots[i] > 0 && buy_lots[j] > 0) {
            // at least 2 orders
            if (buy_lots[j] < buy_lots[i]) {
               // sorting...
               // ...lots
               aux_lots       = buy_lots[i];
               buy_lots[i]    = buy_lots[j];
               buy_lots[j]    = aux_lots;
               // ...tickets
               aux_tickets    = buy_tickets[i];
               buy_tickets[i] = buy_tickets[j];
               buy_tickets[j] = aux_tickets;
               // ...profits
               aux_profit     = buy_profit[i];
               buy_profit[i]  = buy_profit[j];
               buy_profit[j]  = aux_profit;
               // ...open price
               aux_price      = buy_price[i];
               buy_price[i]   = buy_price[j];
               buy_price[j]   = aux_price;
            }
         }
      }
   }

   // SELL ORDERS
   for (i=0; i<sells-1; i++) {
      for (j=i+1; j<sells; j++) {
         if (sell_lots[i] > 0 && sell_lots[j] > 0) {
            // at least 2 orders
            if (sell_lots[j] < sell_lots[i]) {
               // sorting...
               // ...lots
               aux_lots        = sell_lots[i];
               sell_lots[i]    = sell_lots[j];
               sell_lots[j]    = aux_lots;
               // ...tickets
               aux_tickets     = sell_tickets[i];
               sell_tickets[i] = sell_tickets[j];
               sell_tickets[j] = aux_tickets;
               // ...profits
               aux_profit      = sell_profit[i];
               sell_profit[i]  = sell_profit[j];
               sell_profit[j]  = aux_profit;
               // ...open price
               aux_price       = sell_price[i];
               sell_price[i]   = sell_price[j];
               sell_price[j]   = aux_price;
            }
         }
      }
   }
   catch("SortByLots()");
}


/**
 *
 */
void ShowLines() {
   double aux_tp_buy, aux_tp_sell;
   double buy_tar, sell_tar;
   double buy_a, sell_a;
   double buy_b, sell_b;
   double buy_pip, sell_pip;
   double buy_v[50], sell_v[50];
   int i, factor=1;

   if (buys >= 1) {
      aux_tp_buy = CalculateTP(buy_lots[0]);
   }

   if (sells >= 1) {
      aux_tp_sell = CalculateTP(sell_lots[0]);
   }

   if (buys >= 1) {
      buy_pip = CalculatePipValue(buy_lots[0]);
      for (i=0; i<50; i++)
         buy_v[i] = 0;

      for (i=0; i<buys; i++) {
         buy_v[i] = MathRound(buy_lots[i]/buy_lots[0]);
      }

      for (i=0; i<buys; i++) {
         buy_a = buy_a + buy_v[i];
         buy_b = buy_b + buy_v[i] * buy_price[i];
      }

      buy_tar = aux_tp_buy/(buy_pip/Pip);
      buy_tar = buy_tar + buy_b;
      buy_tar = buy_tar / buy_a;
      HorizontalLine(buy_tar, "line_buy", DodgerBlue, STYLE_SOLID, 2);

      if (buy_close_profit > 0) {
         buy_tar = buy_close_profit/(buy_pip/Pip);
         buy_tar = buy_tar + buy_b;
         buy_tar = buy_tar / buy_a;
         HorizontalLine(buy_tar, "line_buy_ts", DodgerBlue, STYLE_DASH, 1);
      }
   }

   if (sells >= 1) {
      sell_pip = CalculatePipValue(sell_lots[0]);
      for (i=0; i<50; i++)
         sell_v[i] = 0;

      for (i=0; i<sells; i++) {
         sell_v[i] = MathRound(sell_lots[i]/sell_lots[0]);
      }

      for (i=0; i<sells; i++) {
         sell_a = sell_a + sell_v[i];
         sell_b = sell_b + sell_v[i] * sell_price[i];
      }

      sell_tar = -1*(aux_tp_sell/(sell_pip/Pip));
      sell_tar = sell_tar + sell_b;
      sell_tar = sell_tar / sell_a;
      HorizontalLine(sell_tar, "line_sell", Tomato, STYLE_SOLID, 2);

      if (sell_close_profit > 0) {
         sell_tar = -1*(sell_close_profit/(sell_pip/Pip));
         sell_tar = sell_tar + sell_b;
         sell_tar = sell_tar / sell_a;
         HorizontalLine(sell_tar, "line_sell_ts", Tomato, STYLE_DASH, 1);
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

   if (buys >= 1) {
      aux_tp_buy = CalculateTP(buy_lots[0]);
   }

   if (sells >= 1) {
      aux_tp_sell = CalculateTP(sell_lots[0]);
   }

   txt = "\nCopyright © 2011, www.lifesdream.org" +
         "\nPSAR Grid v1.5 is running."+
         "\n"                          +
         "\nSETTINGS: "                +
         "\nGrid size: "               + grid_size +
         "\nProfit locked: "           + DoubleToStr(100*profit_lock, 2) + "%"+
         "\nMinimum lots: "            + DoubleToStr(min_lots, 2) +
         "\nAccount risk: "            + DoubleToStr(account_risk, 0) + "%"+
         "\nPSAR step: "               + DoubleToStr(psar_step, 0) +
         "\nPSAR maximum: "            + DoubleToStr(psar_maximum, 0) +
         "\nPSAR shift: "              + DoubleToStr(shift, 0) +

         "\n"                          +
         "\nBUY ORDERS"                +
         "\nNumber of orders: "        + buys +
         "\nTotal lots: "              + DoubleToStr(total_buy_lots, 2) +
         "\nCurrent profit: "          + DoubleToStr(total_buy_profit, 2) +
         "\nProfit goal: $"            + DoubleToStr(aux_tp_buy, 2) +
         "\nMaximum profit reached: $" + DoubleToStr(buy_max_profit, 2) +
         "\nProfit locked: $"          + DoubleToStr(buy_close_profit, 2) +

         "\n"                          +
         "\nSELL ORDERS"               +
         "\nNumber of orders: "        + sells +
         "\nTotal lots: "              + DoubleToStr(total_sell_lots, 2) +
         "\nCurrent profit: "          + DoubleToStr(total_sell_profit, 2) +
         "\nProfit goal: $"            + DoubleToStr(aux_tp_sell, 2) +
         "\nMaximum profit reached: $" + DoubleToStr(sell_max_profit, 2) +
         "\nProfit locked: $"          + DoubleToStr(sell_close_profit, 2);
   Comment(txt);

   catch("ShowData()");
}


/**
 *
 */
void HorizontalLine(double value, string name, color c, int style, int thickness) {
   if(ObjectFind(name) == -1) {
      ObjectCreate(name, OBJ_HLINE, 0, Time[0], value);
      ObjectSet   (name, OBJPROP_STYLE, style);
      ObjectSet   (name, OBJPROP_COLOR, c);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   else {
      ObjectSet   (name, OBJPROP_PRICE1, value);
      ObjectSet   (name, OBJPROP_STYLE, style);
      ObjectSet   (name, OBJPROP_COLOR, c);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   catch("HorizontalLine()");
}


/**
 *
 */
double CalculateStartingVolume() {
   int n;
   double aux = min_lots;

   if (aux > MarketInfo(Symbol(), MODE_MAXLOT))
      aux = MarketInfo(Symbol(), MODE_MAXLOT);

   if (aux < MarketInfo(Symbol(), MODE_MINLOT))
      aux = MarketInfo(Symbol(), MODE_MINLOT);

   catch("CalculateStartingVolume()");
   return(aux);
}


/**
 *
 */
double CalculateDecimals(double volume) {
   double aux;
   int decimals;

   if (min_lots_increment >= 1) {
      decimals = 0;
   }
   else {
      decimals = 0;
      aux = volume;
      while (aux < 1) {
         decimals++;
         aux *= 10;
      }
   }
   catch("CalculateDecimals()");
   return(decimals);
}


/**
 *
 */
double MartingaleVolume(double losses) {
   double grid_value = CalculateTP(min_lots); // minimum grid value
   double multiplier = MathFloor(MathAbs(losses/grid_value));
   double aux        = NormalizeDouble(multiplier*min_lots_increment, CalculateDecimals(min_lots_increment));

   if (aux < min_lots)                          aux = min_lots;
   if (aux > MarketInfo(Symbol(), MODE_MAXLOT)) aux = MarketInfo(Symbol(), MODE_MAXLOT);
   if (aux < MarketInfo(Symbol(), MODE_MINLOT)) aux = MarketInfo(Symbol(), MODE_MINLOT);

   catch("MartingaleVolume()");
   return(aux);
}


/**
 *
 */
double CalculatePipValue(double volume) {
   double aux_mm_value;
   double aux_mm_tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double aux_mm_tick_size  = MarketInfo(Symbol(), MODE_TICKSIZE );
   int    aux_mm_digits     = MarketInfo(Symbol(), MODE_DIGITS   );
   double aux_mm_veces_lots;

   if (volume != 0) {
      aux_mm_veces_lots = 1/volume;

      if (aux_mm_digits==5 || aux_mm_digits==3) {
         aux_mm_value = aux_mm_tick_value * 10;
      }
      else if (aux_mm_digits==4 || aux_mm_digits==2) {
         aux_mm_value = aux_mm_tick_value;
      }
      aux_mm_value /= aux_mm_veces_lots;
   }

   catch("CalculatePipValue()");
   return(aux_mm_value);
}


/**
 *
 */
double CalculateTP(double volume) {
   int aux_take_profit = grid_size * CalculatePipValue(volume);

   catch("CalculateTP()");
   return(aux_take_profit);
}


/**
 *
 */
double CalculateSL(double volume) {
   int aux_stop_loss = -grid_size * CalculatePipValue(volume);

   catch("CalculateSL()");
   return(aux_stop_loss);
}


/**
 *
 */
void Robot() {
   int i, ticket=-1;
   bool closed;

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
         closed = OrderCloseEx(buy_tickets[i], buy_lots[i], MarketInfo(Symbol(), MODE_BID), 0.2, Blue, oeFlags, oe);
      }
      // Closing sell orders
      for (i=0; i<=sells-1; i++) {
         closed = OrderCloseEx(sell_tickets[i], sell_lots[i], MarketInfo(Symbol(), MODE_ASK), 0.2, Red, oeFlags, oe);
      }
      BuyResetAfterClose();
      SellResetAfterClose();
   }

   // **************************************************
   // BUYS==0
   // **************************************************
   if (buys == 0) {
      if (psar1<price1 && psar2>price2)
         ticket = OrderSendEx(Symbol(), OP_BUY, CalculateStartingVolume(), MarketInfo(Symbol(), MODE_ASK), 0.2, 0, 0, key, magic, 0, Blue, oeFlags, oe);
   }

   // **************************************************
   // BUYS>=1
   // **************************************************
   if (buys >= 1) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (total_buy_profit < CalculateSL(total_buy_lots)) {
         if (buys<50 && psar1<price1 && psar2>price2) {
            ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(total_buy_profit), MarketInfo(Symbol(), MODE_ASK), 0.2, 0, 0, key, magic, 0, Blue, oeFlags, oe);
         }
      }

      // CASE 2.1 >>> We reach Take Profit so we activate profit lock
      if (buy_max_profit==0 && total_buy_profit > CalculateTP(buy_lots[0])) {
         buy_max_profit   = total_buy_profit;
         buy_close_profit = profit_lock * buy_max_profit;
      }

      // CASE 2.2 >>> Profit locked is updated in real time
      if (buy_max_profit > 0) {
         if (total_buy_profit > buy_max_profit) {
            buy_max_profit   = total_buy_profit;
            buy_close_profit = profit_lock * total_buy_profit;
         }
      }

      // CASE 2.3 >>> If profit falls below profit locked we close all orders
      if (buy_max_profit>0 && buy_close_profit>0 && buy_max_profit>buy_close_profit && total_buy_profit<buy_close_profit) {
         for (i=0; i<=buys-1; i++) {
            closed = OrderCloseEx(buy_tickets[i], buy_lots[i], MarketInfo(Symbol(), MODE_BID), 0.2, Blue, oeFlags, oe);
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateVars() on next start() execution
         BuyResetAfterClose();
      }
   }

   // **************************************************
   // SELLS==0
   // **************************************************
   if (sells == 0) {
      if (psar1>price1 && psar2<price2)
         ticket = OrderSendEx(Symbol(), OP_SELL, CalculateStartingVolume(), MarketInfo(Symbol(), MODE_BID), 0.2, 0, 0, key, magic, 0, Red, oeFlags, oe);
   }

   // **************************************************
   // SELLS>=1
   // **************************************************
   if (sells >= 1) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (total_sell_profit < CalculateSL(total_sell_lots)) {
         if (sells<50 && psar1>price1 && psar2<price2) {
            ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(total_sell_profit), MarketInfo(Symbol(), MODE_BID), 0.2, 0, 0, key, magic, 0, Red, oeFlags, oe);
         }
      }

      // CASE 2.1 >>> We reach Take Profit so we activate profit lock
      if (sell_max_profit==0 && total_sell_profit>CalculateTP(sell_lots[0])) {
         sell_max_profit   = total_sell_profit;
         sell_close_profit = profit_lock*sell_max_profit;
      }

      // CASE 2.2 >>> Profit locked is updated in real time
      if (sell_max_profit>0) {
         if (total_sell_profit > sell_max_profit) {
            sell_max_profit   = total_sell_profit;
            sell_close_profit = profit_lock*sell_max_profit;
         }
      }

      // CASE 2.3 >>> If profit falls below profit locked we close all orders
      if (sell_max_profit>0 && sell_close_profit>0 && sell_max_profit>sell_close_profit && total_sell_profit<sell_close_profit) {
         for (i=0; i<=sells-1; i++) {
            closed = OrderCloseEx(sell_tickets[i], sell_lots[i], MarketInfo(Symbol(), MODE_ASK), 0.2, Red, oeFlags, oe);
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateVars() on next start() execution
         SellResetAfterClose();
      }
   }
   catch("Robot()");
}
