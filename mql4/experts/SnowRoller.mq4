/**
 * SnowRoller Anti-Martingale EA
 *
 * @see 7bit Strategy:  http://www.forexfactory.com/showthread.php?t=226059
 *      7bit Journal:   http://www.forexfactory.com/showthread.php?t=239717
 *      7bit code base: http://sites.google.com/site/prof7bit/snowball
 *
 *      FXEZ Strategy:  http://www.forexfactory.com/showthread.php?t=286352
 *      FXEZ code base: http://sites.google.com/site/marketformula/snowroller
 *
 * Ausgangsversion: 2010.6.11.1
 */
#include <stdlib.mqh>


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern double Lotsize          =  0.1;                      // lots to use per trade
extern int    Gridsize         = 20;
extern int    TakeProfitLevels =  2;                        // TakeProfit (roughly) this many levels above Breakeven
extern bool   IsCriminalECN    = false;

extern color  clr_breakeven_level    = Lime;
extern color  clr_gridline           = DeepSkyBlue;
extern color  clr_stopline_active    = Magenta;
extern color  clr_stopline_triggered = Aqua;

extern string sound_grid_step        = "expert.wav";
extern string sound_grid_trail       = "alert2.wav";
extern string sound_order_triggered  = "alert.wav";
extern string sound_stop_all         = "alert.wav";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


color Color.Buy                 = Blue;
color Color.Sell                = Red;

color Crossline.Color.Active    = Magenta;
int   Crossline.Width.Active    = 1;
int   Crossline.Style.Active    = STYLE_DASH;

color Crossline.Color.Triggered = Gray;
int   Crossline.Width.Triggered = 1;
int   Crossline.Style.Triggered = STYLE_SOLID;



string name = "snow";

string comment;
int    magic;
bool   running;
int    direction;
double last_line;
int    level;                                // current level, signed, minus=short, calculated in trade()
double realized;                             // total realized (all time) (calculated in info())
double cycle_total_profit;                   // total profit since cycle started (calculated in info())
double stop_value;                           // dollars (account) per single level (calculated in info())
double auto_tp_price;                        // the price where auto_tp should trigger, calculated during break even calc.
double auto_tp_profit;                       // rough estimation of auto_tp profit, calculated during break even calc.

// trading direction
#define BIDIR 0
#define LONG  1
#define SHORT 2

string objects[];



/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (onInit(T_EXPERT) != NO_ERROR)
      return(last_error);

   comment = name +"_"+ GetStandardSymbol(Symbol());
   magic   = makeMagicNumber(name + "_" + Symbol());

   if (last_line == 0){
      last_line = getLine();
   }

   if (IsTesting()){
      setGlobal("realized", 0);
      setGlobal("running", 0);
   }

   readVariables();

   if (IsTesting() && !IsVisualMode()){
      Print("This is not an automated strategy! Starting in bidirectional mode...");
      running   = true;
      direction = BIDIR;
      placeLine(Bid);
   }

   info();


   // ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(UninitializeReason(), reasons1)) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten

   // nach Reload nicht auf den nächsten Tick warten (nur bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
   int reasons2[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT, REASON_PARAMETERS, REASON_RECOMPILE };
   if (IntInArray(UninitializeReason(), reasons2)) /*&&*/ if (!IsTesting())
      SendTick(false);

   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   deleteStartButtons();
   deleteStopButtons();
   storeVariables();

   if (UninitializeReason() == REASON_PARAMETERS) {
      Comment("Parameters changed, pending orders deleted, will be replaced with the next tick");
      closeOpenOrders(OP_SELLSTOP, magic);
      closeOpenOrders(OP_BUYSTOP, magic);
   }
   else {
      Comment("EA removed, open orders, trades and status untouched!");
   }

   int reasons[] = { REASON_REMOVE, REASON_CHARTCLOSE };
   if (IntInArray(UninitializeReason(), reasons))
      RemoveChartObjects(objects);
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   //recordEquity(name+ GetStandardSymbol(Symbol()), PERIOD_M1, magic);

   checkLines();
   checkButtons();
   trade();
   info();
   checkAutoTP();

   if (!IsTesting()) {
      plotNewOpenTrades(magic);
      plotNewClosedTrades(magic);
   }

   return(catch("onTick()"));
}


/**
 *
 */
void storeVariables() {
   setGlobal("running", running);
   setGlobal("direction", direction);
   return(catch("storeVariables()"));
}


/**
 *
 */
void readVariables() {
   running   = getGlobal("running");
   direction = getGlobal("direction");
   return(catch("readVariables()"));
}


/**
 *
 */
void deleteStartButtons() {
   ObjectDelete("start_long");
   ObjectDelete("start_short");
   ObjectDelete("start_bidir");
}


/**
 *
 */
void deleteStopButtons() {
   ObjectDelete("stop");
   ObjectDelete("pause");
}


/**
 * mark the start (or resume) of the cycle in the chart
 */
void startArrow() {
   string aname = "cycle_start_" + TimeToStr(TimeCurrent());
   ObjectCreate(aname, OBJ_ARROW, 0, TimeCurrent(), Close[0]);
   ObjectSet(aname, OBJPROP_ARROWCODE, 5);
   ObjectSet(aname, OBJPROP_COLOR, clr_gridline);
   ObjectSet(aname, OBJPROP_BACK, true);
   ArrayPushString(objects, name);

   return(catch("startArrow()"));
}


/**
 * mark the end (or pause) of the cycle in the chart
 */
void endArrow() {
   string aname = "cycle_end_" + TimeToStr(Time[0]);
   ObjectCreate(aname, OBJ_ARROW, 0, TimeCurrent(), Close[0]);
   ObjectSet(aname, OBJPROP_ARROWCODE, 6);
   ObjectSet(aname, OBJPROP_COLOR, clr_gridline);
   ObjectSet(aname, OBJPROP_BACK, true);
   ArrayPushString(objects, name);

   return(catch("endArrow()"));
}


/**
 *
 */
void stop() {
   endArrow();
   deleteStopButtons();
   closeOpenOrders(-1, magic);
   running = false;
   storeVariables();
   setGlobal("realized", getProfitRealized(magic)); // store this only on pyramid close
   if (sound_stop_all != ""){
      PlaySound(sound_stop_all);
   }

   return(catch("stop()"));
}


/**
 *
 */
void go(int mode) {
   startArrow();
   deleteStartButtons();
   running = true;
   direction = mode;
   storeVariables();
   resume();

   return(catch("go()"));
}


/**
 *
 */
void pause() {
   endArrow();
   deleteStopButtons();
   label("paused_level", 15, 100, 1, level, Yellow);
   closeOpenOrders(-1, magic);
   running = false;
   storeVariables();
   if (sound_stop_all != ""){
      PlaySound(sound_stop_all);
   }

   return(catch("pause()"));
}


/**
 * resume trading after we paused it.
 * Find the text label containing the level where we hit pause
 * and re-open the corresponding amounts of lots, then delete the label.
 */
void resume() {
   int i;
   double sl;
   double line = getLine();

   if (ObjectFind("paused_level") == -1)
      return(catch("resume(1)"));

   level = StrToInteger(ObjectDescription("paused_level"));

   if (direction == LONG){
      level = MathAbs(level);
   }

   if (direction == SHORT){
      level = -MathAbs(level);
   }

   if (level > 0){
      for (i=1; i<=level; i++){
         sl = line - i * Gridsize*Pip;
         buy(Lotsize, sl, 0, magic, comment);
      }
   }

   if (level < 0){
      for (i=1; i<=-level; i++){
         sl = line + i * Gridsize*Pip;
         sell(Lotsize, sl, 0, magic, comment);
      }
   }

   ObjectDelete("paused_level");
   return(catch("resume(2)"));
}


/**
 *
 */
void checkLines() {
   if (crossedLine("stop"       )) stop();
   if (crossedLine("pause"      )) pause();
   if (crossedLine("start long" )) go(LONG);
   if (crossedLine("start short")) go(SHORT);
   if (crossedLine("start bidir")) go(BIDIR);

   return(catch("checkLines()"));
}


/**
 *
 */
void checkButtons() {
   if(!running){
      deleteStopButtons();
      if (labelButton("start_long", 15, 60, 1, "start long", Blue)){
         go(LONG);
      }
      if (labelButton("start_short", 15, 75, 1, "start short", Blue)){
         go(SHORT);
      }
      if (labelButton("start_bidir", 15, 90, 1, "start bidirectional", Blue)){
         go(BIDIR);
      }
   }

   if (running){
      deleteStartButtons();
      if (labelButton("stop", 15, 60, 1, "stop", Red)){
         stop();
      }
      if (labelButton("pause", 15, 75, 1, "pause", Red)){
         pause();
      }
   }
   return(catch("checkButtons()"));
}


/**
 *
 */
void checkAutoTP() {
   if (TakeProfitLevels > 0 && auto_tp_price > 0){
      if (level > 0 && Close[0] >= auto_tp_price){
         stop();
      }
      if (level < 0 && Close[0] <= auto_tp_price){
         stop();
      }
   }
   return(catch("checkAutoTP()"));
}


/**
 *
 */
void placeLine(double price) {
   horizLine("last_order", price, clr_gridline, "grid position");
   last_line = price;
   WindowRedraw();
   return(catch("placeLine()"));
}


/**
 *
 */
double getLine() {
   double value = ObjectGet("last_order", OBJPROP_PRICE1);

   int error = GetLastError();
   if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST)
      catch("getLine()", error);

   return(value);
}


/**
 *
 */
bool lineMoved() {
   bool result = false;
   double line = getLine();

   if (line != last_line) {
      // line has been moved by external forces (hello wb ;-)
      if (MathAbs(line - last_line) < Gridsize*Pip) {
         // minor adjustment by user
         last_line = line;
         result = true;
      }
      // something strange (gap? crash? line deleted?)
      else if (MathAbs(Bid - last_line) < Gridsize*Pip) {
         // last_line variable still near price and thus is valid.
         placeLine(last_line);   // simply replace line
         result = false;         // no action needed
      }
      // line is far off or completely missing and last_line doesn't help also
      else {
         placeLine(Bid);// make a completely new line at Bid
         result = true;
      }
   }

   catch("lineMoved()");
   return(result);
}


/**
 * manage all the entry order placement
 */
void trade() {
   double start;
   static int last_level;

   if (lineMoved()){
      closeOpenOrders(OP_SELLSTOP, magic);
      closeOpenOrders(OP_BUYSTOP, magic);
   }
   start = getLine();

   // calculate global variable level here // FIXME: global variable side-effect hell.
   level = getNumOpenOrders(OP_BUY, magic) - getNumOpenOrders(OP_SELL, magic);

   if (running) {
      // are we flat?
      if (level == 0) {
         if (direction == SHORT && Ask > start) {
            if (getNumOpenOrders(OP_SELLSTOP, magic) != 2){
               closeOpenOrders(OP_SELLSTOP, magic);
            }else{
               moveOrders(Ask - start);
            }
            placeLine(Ask);
            start = Ask;
            plotBreakEven();
            if (sound_grid_trail != ""){
               PlaySound(sound_grid_trail);
            }
         }

         if (direction == LONG && Bid < start) {
            if (getNumOpenOrders(OP_BUYSTOP, magic) != 2){
               closeOpenOrders(OP_BUYSTOP, magic);
            }else{
               moveOrders(Bid - start);
            }
            placeLine(Bid);
            start = Bid;
            plotBreakEven();
            if (sound_grid_trail != ""){
               PlaySound(sound_grid_trail);
            }
         }

         // make sure first long orders are in place
         if (direction == BIDIR || direction == LONG){
            longOrders(start);
         }

         // make sure first short orders are in place
         if (direction == BIDIR || direction == SHORT){
            shortOrders(start);
         }
      }

      // are we already long?
      if (level > 0){
         // make sure the next long orders are in place
         longOrders(start);
      }

      // are we short?
      if (level < 0){
         // make sure the next short orders are in place
         shortOrders(start);
      }

      // we have two different models how to move the grid line.
      // If we are *not* flat we can snap it to the nearest grid level,
      // ths is better for handling situations where the order is triggered
      // by the exact pip and price is immediately reversing.
      // If we are currently flat we *must* move it only when we have reached
      // it *exactly*, because otherwise this would badly interfere with
      // the trailing of the grid in the unidirectional modes. Also in
      // bidirectional mode this would have some unwanted effects.
      if (level != 0){
         // snap to grid
         if (Ask + (Gridsize*Pip / 6) >= start + Gridsize*Pip){
            jumpGrid(1);
         }

         // snap to grid
         if (Bid - (Gridsize*Pip / 6) <= start - Gridsize*Pip){
            jumpGrid(-1);
         }
      }else{
         // grid reached exactly
         if (Ask  >= start + Gridsize*Pip){
            jumpGrid(1);
         }

         // grid reached exactly
         if (Bid  <= start - Gridsize*Pip){
            jumpGrid(-1);
         }
      }

      // alert on level change (order triggered, not line moved)
      if (level != last_level){
         if (sound_order_triggered != ""){
            PlaySound(sound_order_triggered);
         }
         last_level = level;
      }

   }
   else { // not running
      placeLine(Bid);
   }

   return(catch("trade()"));
}


/**
 * move the line 1 stop_didtance up or down.
 * 1 means up, -1 means down.
 */
void jumpGrid(int dir) {
   placeLine(getLine() + dir * Gridsize*Pip);
   if (sound_grid_step != ""){
      PlaySound(sound_grid_step);
   }
   return(catch("jumpGrid()"));
}


/**
 * do we need to place a new entry order at this price?
 * This is done by looking for a stoploss below or above the price
 * where=-1 searches for stoploss below, where=1 for stoploss above price
 * return false if there is already an order (open or pending)
 */
bool needsOrder(double price, int where) {
   //return(false);
   int i;
   int total = OrdersTotal();
   int type;
   // search for a stoploss at exactly one grid distance away from price
   for (i=0; i<total; i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      type = OrderType();
      if (where < 0){ // look only for buy orders (stop below)
         if (OrderMagicNumber() == magic && (type == OP_BUY || type == OP_BUYSTOP)){
            if (EQ(OrderStopLoss(), price + where * Gridsize*Pip))
               return(false);
         }
      }
      if (where > 0){ // look only for sell orders (stop above)
         if (OrderMagicNumber() == magic && (type == OP_SELL || type == OP_SELLSTOP)){
            if (EQ(OrderStopLoss(), price + where * Gridsize*Pip))
               return(false);
         }
      }
   }
   return(true);
}


/**
 * Make sure there are the next two long orders above start in place.
 * If they are already there do nothing, else replace the missing ones.
 */
void longOrders(double start) {
   double a = start + Gridsize*Pip;
   double b = start + 2 * Gridsize*Pip;
   if (needsOrder(a, -1)){
      buyStop(Lotsize, a, start, 0, magic, comment);
   }
   if (needsOrder(b, -1)){
      buyStop(Lotsize, b, a, 0, magic, comment);
   }

   return(catch("longOrders()"));
}


/**
 * Make sure there are the next two short orders below start in place.
 * If they are already there do nothing, else replace the missing ones.
 */
void shortOrders(double start) {
   double a = start - Gridsize*Pip;
   double b = start - 2 * Gridsize*Pip;
   if (needsOrder(a, 1)){
      sellStop(Lotsize, a, start, 0, magic, comment);
   }
   if (needsOrder(b, 1)){
      sellStop(Lotsize, b, a, 0, magic, comment);
   }

   return(catch("shortOrders()"));
}


/**
 * move all entry orders by the amount of d
 */
void moveOrders(double d) {
   int i;
   for(i=0; i<OrdersTotal(); i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if (OrderMagicNumber() == magic){
         if (MathAbs(OrderOpenPrice() - getLine()) > 3 * Gridsize*Pip){
            orderDeleteReliable(OrderTicket());
         }else{
            orderModifyReliable(
               OrderTicket(),
               OrderOpenPrice() + d,
               OrderStopLoss() + d,
               0,
               0,
               CLR_NONE
            );
         }
      }
   }

   return(catch("moveOrders()"));
}


/**
 *
 */
void info() {
   double floating;
   double pb, lp, tp;
   static int last_ticket;
   static datetime last_be_plot = 0;
   string dir;

   int ticket = last_ticket;

   int orders = OrdersHistoryTotal();
   if (orders > 0) {
      OrderSelect(orders-1, SELECT_BY_POS, MODE_HISTORY);
      ticket = OrderTicket();
   }

   if (ticket != last_ticket){
      // history changed, need to recalculate realized profit
      realized = getProfitRealized(magic);
      last_ticket = ticket;
      // enforce a new break-even arrow plot immediately
      last_be_plot = 0;
   }

   floating = getProfit(magic);

   // the variable realized is the total realized of all time.
   // the MT4-global variable _realized is a snapshot of this value when
   // the EA was reset the last time. The difference is what we made
   // during the current cycle. Add floating to it and we have the
   // profit of the current cycle.
   cycle_total_profit = realized - getGlobal("realized") + floating;

   if (!running) {
      dir = "trading stopped";
   }
   else {
      switch (direction) {
         case LONG:
            dir = "trading long";  break;
         case SHORT:
            dir = "trading short"; break;
         default:
            dir = "trading both directions";
      }
   }
   catch("info(1)");

   int    level_abs  = MathAbs(getNumOpenOrders(OP_BUY, magic) - getNumOpenOrders(OP_SELL, magic));
   double pointValue = MarketInfo(Symbol(), MODE_TICKVALUE) / (MarketInfo(Symbol(), MODE_TICKSIZE)/Point);
   double pipValue   = pointValue * MathPow(10, Digits-PipDigits);
   stop_value        = Lotsize * Gridsize * pipValue;

   Comment(StringConcatenate(NL, NL, NL, NL, NL, NL,
                             name, magic, ", ", dir,                                                                                                                        NL,
                             "stop distance: ", Gridsize, " pips, lot size: ", NumberToStr(Lotsize, ".+"),                                                                NL,
                             "every stop equals ", DoubleToStr(stop_value, 2), " ", AccountCurrency(),                                                                      NL,
                             "realized: ", DoubleToStr(realized - getGlobal("realized"), 2), "  floating: ", DoubleToStr(floating, 2),                                      NL,
                             "profit: ", DoubleToStr(cycle_total_profit, 2), " ", AccountCurrency(), "  current level: ", level_abs,                                        NL,
                             "takeprofit: ", TakeProfitLevels, " levels (", NumberToStr(auto_tp_price, PriceFormat), ", ", DoubleToStr(auto_tp_profit, 2), " ", AccountCurrency(), ")", NL));

   if (last_be_plot==0 || TimeCurrent()-last_be_plot > 300) { // every 5 minutes
      plotBreakEven();
      last_be_plot = TimeCurrent();
   }

   // If you put a text object (not a label!) with the name "profit",
   // anywhere on the chart then this can be used as a profit calculator.
   // The following code will find the position of this text object
   // and calculate your profit, should price reach this position
   // and then write this number into the text object. You can
   // move it around on the chart to get profit projections for
   // any price level you want.
   if (ObjectFind("profit") != -1){
      pb = getPyramidBase();
      lp = ObjectGet("profit", OBJPROP_PRICE1);
      if (pb ==0){
         if (direction == SHORT){
            pb = getLine() - Gridsize*Pip;
         }
         if (direction == LONG){
            pb = getLine() + Gridsize*Pip;
         }
         if (direction == BIDIR){
            if (lp < getLine()){
               pb = getLine() - Gridsize*Pip;
            }
            if (lp >= getLine()){
               pb = getLine() + Gridsize*Pip;
            }
         }
      }
      tp = getTheoreticProfit(MathAbs(lp - pb));
      ObjectSetText("profit", "¯¯¯ " + DoubleToStr(MathRound(realized - getGlobal("realized") + tp), 0) + " " + AccountCurrency() + " profit projection ¯¯¯");
   }

   return(catch("info(2)"));
}


/**
 * Plot an arrow. Default is the price-exact dash symbol
 * This function might be moved into common_functions soon
 */
string arrow(string name="", double price=0, datetime time=0, color clr=Red, int arrow_code=4) {
   if (time == 0){
      time = TimeCurrent();
   }
   if (name == ""){
      name = "arrow_" + time;
   }
   if (price == 0){
      price = Bid;
   }
   if (ObjectFind(name) < 0) {
      ObjectCreate(name, OBJ_ARROW, 0, time, price);
      ArrayPushString(objects, name);
   }
   else {
      ObjectSet(name, OBJPROP_PRICE1, price);
      ObjectSet(name, OBJPROP_TIME1, time);
   }
   ObjectSet(name, OBJPROP_ARROWCODE, arrow_code);
   ObjectSet(name, OBJPROP_SCALE, 1);
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_BACK, true);
   return(name);
}


/**
 * plot the break even price into the chart
 */
void plotBreakEvenArrow(string arrow_name, double price) {
   arrow(arrow_name + TimeCurrent(), price, 0, clr_breakeven_level);

   return(catch("plotBreakEvenArrow()"));
}


/**
 * plot the break-even Point (only a rough estimate plusminus less than one stop_distance,
 * it will be most inaccurate just before hitting a stoploss (last trade negative).
 * and this will be more obvious at the beginning of a new cycle when losses are still small
 * and break even steps increments are still be big.
 *
 * Side effects: This function will also calculate auto-tp price and profit.
 *
 * FIXME: This whole break even calculation sucks comets through drinking straws!
 * FIXME: Isn't there a more elegant way to calculate break even?
 */
void plotBreakEven() {
   double base = getPyramidBase();
   double be = 0;

   // loss is roughly the amount of realized stop hits. But I can't use this number
   // directly because after resuming a paused pyramid this number is wrong. So
   // I have to estimate it with the (always accurate) total profit and the current
   // distance from base. In mose cases the outcome of this calculation is equal
   // to the realized losses as displayed on the screen, only when resuming a pyramid
   // it will differ and have the value it would have if the pyramid never had been paused.
   double distance = MathAbs(Close[0] - base);
   if ((level > 0 && Close[0] < base) || (level < 0 && Close[0] > base) || level == 0){
      distance = 0;
   }
   double loss = -(cycle_total_profit - getTheoreticProfit(distance));

   // this value should always be positive
   // or 0 (or slightly below (rounding error)) in case we have a fresh pyramid.
   // If it is not positive (no loss yet) then we dont need to plot break even.
   if (loss <= 0 || !running){
      auto_tp_price = 0;
      auto_tp_profit = 0;
      return(0);
   }

   if (direction == LONG){
      if (base==0){
         base = getLine() + Gridsize*Pip;
      }
      be = base + getBreakEven(loss);
      plotBreakEvenArrow("breakeven_long", be);
      auto_tp_price = be + TakeProfitLevels * Gridsize * Pip;
      auto_tp_profit = getTheoreticProfit(MathAbs(auto_tp_price - base)) - loss;
   }

   if (direction == SHORT){
      if (base==0){
         base = getLine() - Gridsize*Pip;
      }
      be = base - getBreakEven(loss);
      plotBreakEvenArrow("breakeven_short", be);
      auto_tp_price = be - TakeProfitLevels * Gridsize * Pip;
      auto_tp_profit = getTheoreticProfit(MathAbs(auto_tp_price - base)) - loss;
   }

   if (direction == BIDIR){
      if (base == 0){
         base = getLine() + Gridsize*Pip;
         plotBreakEvenArrow("breakeven_long", base + getBreakEven(loss));
         base = getLine() - Gridsize*Pip;
         plotBreakEvenArrow("breakeven_short", base - getBreakEven(loss));
         auto_tp_price = 0;
         auto_tp_profit = 0;
      }else{
         if (getLotsOnTableSigned(magic) > 0){
            be = base + getBreakEven(loss);
            plotBreakEvenArrow("breakeven_long", be);
            auto_tp_price = be + TakeProfitLevels * Gridsize * Pip;
            auto_tp_profit = getTheoreticProfit(MathAbs(auto_tp_price - base)) - loss;
         }else{
            be = base - getBreakEven(loss);
            plotBreakEvenArrow("breakeven_short", be);
            auto_tp_price = be - TakeProfitLevels * TakeProfitLevels * Pip;
            auto_tp_profit = getTheoreticProfit(MathAbs(auto_tp_price - base)) - loss;
         }
      }
   }

   if (TakeProfitLevels < 1) {
      auto_tp_price = 0;
      auto_tp_profit = 0;
   }

   return(catch("plotBreakEven()"));
}


/**
 * return the entry price of the first order of the pyramid.
 * return 0 if we are flat.
 */
double getPyramidBase() {
   double d, max_d, sl;
   int i;
   int type   = -1;
   int orders = OrdersTotal();

   // find the stoploss that is farest away from current price
   // we cannot just use the order open price because we might
   // be in resume mode and then all trades would be opened at
   // the same price. the only thing that works reliable is
   // looking at the stoplossses
   for (i=0; i < orders; i++) {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if (OrderMagicNumber()==magic && OrderType() < 2){
         d = MathAbs(Close[0] - OrderStopLoss());
         if (d > max_d){
            max_d = d;
            sl   = OrderStopLoss();
            type = OrderType();
         }
      }
   }

   if (type == OP_BUY)
      return(sl + Gridsize*Pip);

   if (type == OP_SELL)
      return(sl - Gridsize*Pip);

   return(0);
}


/**
 * return the floating profit that would result if
 * price would be the specified distance away from
 * the base of the pyramid
 */
double getTheoreticProfit(double distance) {
   int n = MathFloor(distance / (Gridsize*Pip));
   double remain = distance - n * Gridsize*Pip;
   int mult = n * (n + 1) / 2;

   double pointValue = MarketInfo(Symbol(), MODE_TICKVALUE) / (MarketInfo(Symbol(), MODE_TICKSIZE)/Point);
   double pipValue   = pointValue * MathPow(10, Digits-PipDigits);
   double profit     = Lotsize * Gridsize * pipValue * mult;

   profit = profit + MarketInfo(Symbol(), MODE_TICKVALUE) * Lotsize * (remain/Point) * (n + 1);    // pewa: Bug
   return(profit);
}


/**
 * return the price move relative to base required to compensate realized losses
 * FIXME: This algorithm does not qualify as "elegant", not even remotely.
 */
double getBreakEven(double loss) {
   double i = 0;

   while (true) {
      if (getTheoreticProfit(i*Pip) > loss)
         break;
      i += Gridsize;
   }

   i -= Gridsize;
   while (true) {
      if (getTheoreticProfit(i*Pip) > loss)
         break;
      i += 0.1;
   }
   return(i*Pip);
}


/**
 *
 */
void setGlobal(string key, double value) {
   GlobalVariableSet(name + magic + "_" + key, value);
   GetLastError();
}


/**
 *
 */
double getGlobal(string key) {
   double value = GlobalVariableGet(name + magic + "_" + key);
   GetLastError();
   return(value);
}


/**
 * create a positive integer for the use as a magic number.
 *
 * The function takes a string as argument and calculates
 * an 31 bit hash value from it. The hash does certainly not
 * have the strength of a real cryptographic hash function
 * but it should be more than sufficient for generating a
 * unique ID from a string and collissions should not occur.
 *
 * use it in your init() function like this:
 *    magic = makeMagicNumber(WindowExpertName() + Symbol() + Period());
 *
 * where name would be the name of your EA. Your EA will then
 * get a unique magic number for each instrument and timeframe
 * and this number will always be the same, whenever you put
 * the same EA onto the same chart.
 *
 * Numbers generated during testing mode will differ from those
 * numbers generated on a live chart.
 */
int makeMagicNumber(string key) {
   int i, k;
   int h = 0;

   if (IsTesting()){
      key = "_" + key;
   }

   for (i=0; i<StringLen(key); i++){
      k = StringGetChar(key, i);
      h = h + k;
      h = bitRotate(h, 5); // rotate 5 bits
   }

   for (i=0; i<StringLen(key); i++){
      k = StringGetChar(key, i);
      h = h + k;
      // rotate depending on character value
      h = bitRotate(h, k & 0x0000000F);
   }

   // now we go backwards in our string
   for (i=StringLen(key); i>0; i--){
      k = StringGetChar(key, i - 1);
      h = h + k;
      // rotate depending on the last 4 bits of h
      h = bitRotate(h, h & 0x0000000F);
   }

   catch("makeMagicNumber()");
   return(h & 0x7fffffff);
}


/**
 * Rotate a 32 bit integer value bit-wise
 * the specified number of bits to the right.
 * This function is needed for calculations
 * in the hash function makeMacicNumber()
 */
int bitRotate(int value, int count){
   int i, tmp, mask;
   mask = (0x00000001 << count) - 1;
   tmp = value & mask;
   value = value >> count;
   value = value | (tmp << (32 - count));

   catch("bitRotate()");
   return(value);
}


/**
 * place a market buy with stop loss, target, magic and Comment
 * keeps trying in an infinite loop until the position is open.
 */
int buy(double lots, double sl, double tp, int magic=42, string comment="") {
   int ticket;
   if (!IsCriminalECN) {
      ticket = orderSendReliable(Symbol(), OP_BUY, lots, Ask, 100, sl, tp, comment, magic, 0, Color.Buy);
   }
   else {
      ticket = orderSendReliable(Symbol(), OP_BUY, lots, Ask, 100, 0, 0, comment, magic, 0, Color.Buy);
      if (sl + tp > 0)
         orderModifyReliable(ticket, 0, sl, tp, 0);
   }

   catch("buy()");
   return(ticket);
}


/**
 * place a market sell with stop loss, target, magic and comment
 * keeps trying in an infinite loop until the position is open.
 */
int sell(double lots, double sl, double tp, int magic=42, string comment=""){
   int ticket;
   if (!IsCriminalECN) {
      ticket = orderSendReliable(Symbol(), OP_SELL, lots, Bid, 100, sl, tp, comment, magic, 0, Color.Sell);
   }
   else {
      ticket = orderSendReliable(Symbol(), OP_SELL, lots, Bid, 100, 0, 0, comment, magic, 0, Color.Sell);
      if (sl + tp > 0)
         orderModifyReliable(ticket, 0, sl, tp, 0);
   }

   catch("sell()");
   return(ticket);
}


/**
 * place a buy stop order
 */
int buyStop(double lots, double price, double sl, double tp, int magic=42, string comment=""){
   return(orderSendReliable(Symbol(), OP_BUYSTOP, lots, price, 1, sl, tp, comment, magic, 0, CLR_NONE));
}


/**
 * place a sell stop order
 */
int sellStop(double lots, double price, double sl, double tp, int magic=42, string comment=""){
   int ticket = orderSendReliable(Symbol(), OP_SELLSTOP, lots, price, 1, sl, tp, comment, magic, 0, CLR_NONE);

   catch("sellStop()");
   return(ticket);
}


/**
 * calculate unrealized P&L, belonging to all open trades with this magic number
 */
double getProfit(int magic){
   int cnt;
   double profit = 0;
   int total=OrdersTotal();
   for(cnt=0; cnt<total; cnt++){
      OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES);
      if(OrderMagicNumber() == magic){
         profit += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }

   catch("getProfit()");
   return (profit);
}


/**
 * calculate realized P&L resulting from all closed trades with this magic number
 */
double getProfitRealized(int magic){
   int cnt;
   double profit = 0;
   int total=OrdersHistoryTotal();
   for(cnt=0; cnt<total; cnt++){
      OrderSelect(cnt, SELECT_BY_POS, MODE_HISTORY);
      if(OrderMagicNumber() == magic){
         profit += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }

   catch("getProfitRealized()");
   return(profit);
}


/**
 * get the number of currently open trades of specified type
 */
int getNumOpenOrders(int type, int magic) {
   int cnt;
   int num = 0;
   int total=OrdersTotal();
   for(cnt=0; cnt<total; cnt++){
      OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES);
      if((magic == -1 || OrderMagicNumber() == magic) && (type == -1 || OrderType() == type)){
         num++;
      }
   }

   catch("getNumOpenOrders()");
   return (num);
}


/**
 * Close all open orders or trades that match type and magic number.
 * This function won't return until all positions are closed
 * type = -1 means all types, magic = -1 means all magic numbers
 */
void closeOpenOrders(int type, int magic) {
   int total, cnt;
   double price;
   color clr;
   int order_type;

   Print ("closeOpenOrders(" + type + "," + magic + ")");

   while (getNumOpenOrders(type, magic) > 0){
      while (IsTradeContextBusy()){
         Print("closeOpenOrders(): waiting for trade context.");
         Sleep(MathRand()/10);
      }
      total=OrdersTotal();
      RefreshRates();
      if (type == OP_BUY) {
         price = Bid;
         clr = Color.Sell;
      }
      else {
         price = Ask;
         clr = Color.Buy;
      }
      for (cnt=0; cnt<total; cnt++) {
         OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES);
         if ((type==-1 || OrderType()==type) && (magic==-1 || OrderMagicNumber()==magic)) {
            if (IsTradeContextBusy())
               break; // something else is trading too, back to the while loop.

            order_type = OrderType();
            if (order_type == OP_BUYSTOP || order_type == OP_SELLSTOP || order_type == OP_BUYLIMIT || order_type == OP_SELLLIMIT) {
               orderDeleteReliable(OrderTicket());
            }
            else {
               orderCloseReliable(OrderTicket(), OrderLots(), price, 999, clr);
            }
            break; // restart the loop from 0 (hello FIFO!)
         }
      }
   }

   return(catch("closeOpenOrders()"));
}


/**
 * Get the number of (effective) lots that are curretly open.
 * This will return the effective exposure. Offsetting trades
 * will be subtracted. Positive means long, negative is short.
 * See also getLotsOnTable()
 */
double getLotsOnTableSigned(int magic){
   double total_lots = 0;
   int i;
   int total_orders = OrdersTotal();
   for (i=0; i<total_orders; i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if (OrderMagicNumber() == magic){
         if(OrderType() == OP_BUY){
            total_lots += OrderLots();
         }
         if(OrderType() == OP_SELL){
            total_lots -= OrderLots();
         }
      }
   }

   catch("getLotsOntableSigned()");
   return(total_lots);
}


/**
 * Plot the opening trade arrow.
 * This is part of a re-implementation of what metatrader does when dragging
 * a trade from the history to the chart. Metatrader won't do this automatically
 * for manual trading and for pending order fills so we have to do it ourselves.
 * See also plotNewOpenTrades() and plotNewClosedTrades() defined below.
 */
void plotOpenedTradeArrow(int ticket, bool remove=false) {
   string name, name_wrong;
   color clr;
   if (IsOptimization())
      return(catch("plotOpenedTradeArrow(1)"));

   OrderSelect(ticket, SELECT_BY_TICKET);

   name = "#" + ticket + " ";
   if (OrderType() == OP_BUY){
      name = name + "buy ";
      clr = Color.Buy;
   }
   if (OrderType() == OP_SELL){
      name = name + "sell ";
      clr = Color.Sell;
   }
   name = name + DoubleToStr(OrderLots(), 2) + " ";
   name = name + OrderSymbol() + " ";

   // sometimes mt4 will have created an arrow with open price = 0.
   // this is wrong, we will delete it.
   name_wrong = name + "at " + DoubleToStr(0, MarketInfo(OrderSymbol(), MODE_DIGITS));

   name = name + "at " + DoubleToStr(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS));

   ObjectDelete(name_wrong);
   int error = GetLastError(); if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST) catch("plotOpenedTradeArrow(2)", error);

   if (remove) {
      ObjectDelete(name);
      error = GetLastError(); if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST) catch("plotOpenedTradeArrow(3)", error);
   }
   else {
      ObjectCreate(name, OBJ_ARROW, 0, OrderOpenTime(), OrderOpenPrice());
      error = GetLastError(); if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_ALREADY_EXISTS) catch("plotOpenedTradeArrow(4)", error);
      ArrayPushString(objects, name);

      ObjectSet(name, OBJPROP_ARROWCODE, 1);
      ObjectSet(name, OBJPROP_COLOR, clr);
      ObjectSetText(name, formatOrderArrowInfo());
   }

   catch("plotOpenedTradeArrow(5)");
}


/**
 * Plot the closing trade arrow.
 * This is part of a re-implementation of what metatrader does when dragging
 * a trade from the history to the chart. Metatrader won't do this automatically
 * for manual trading and for pending order fills so we have to do it ourselves.
 * See also plotNewOpenTrades() and plotNewClosedTrades() defined below.
 */
void plotClosedTradeArrow(int ticket, bool remove=false) {
   string name;
   color clr;
   if (IsOptimization())
      return(catch("plotClosedTradeArrow(1)"));

   OrderSelect(ticket, SELECT_BY_TICKET);
   name = "#" + ticket + " ";
   if (OrderType() == OP_BUY){
      name = name + "buy ";
      clr = Color.Sell; // closing a buy is a sell, so make it red
   }
   if (OrderType() == OP_SELL){
      name = name + "sell ";
      clr = Color.Buy; // closing a sell is a buy, so make it blue
   }
   name = name + DoubleToStr(OrderLots(), 2) + " ";
   name = name + OrderSymbol() + " ";
   name = name + "at " + DoubleToStr(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   name = name + "close at " + DoubleToStr(OrderClosePrice(), MarketInfo(OrderSymbol(), MODE_DIGITS));

   if (remove) {
      ObjectDelete(name);
      int error = GetLastError();
      if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST)
         catch("plotClosedTradeLine(2)", error);
   }
   else {
      ObjectCreate(name, OBJ_ARROW, 0, OrderCloseTime(), OrderClosePrice());
      error = GetLastError();
      if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_ALREADY_EXISTS)
         catch("plotClosedTradeLine(3)", error);
      ArrayPushString(objects, name);

      ObjectSet(name, OBJPROP_ARROWCODE, 3);
      ObjectSet(name, OBJPROP_COLOR, clr);
      ObjectSetText(name, formatOrderArrowInfo());
   }

   catch("plotClosedTradeArrow(4)");
}


/**
 * Plot the line connecting open and close of a history trade.
 * This is part of a re-implementation of what metatrader does when dragging
 * a trade from the history to the chart. Metatrader won't do this automatically
 * for manual trading and for pending order fills so we have to do it ourselves.
 * See also plotNewOpenTrades() and plotNewClosedTrades() defined below.
 */
void plotClosedTradeLine(int ticket, bool remove=false) {
   string name;
   color clr;
   if (IsOptimization())
      return(catch("plotClosedTradeLine(1)"));

   OrderSelect(ticket, SELECT_BY_TICKET);
   name = "#" + ticket + " ";
   if (OrderType() == OP_BUY){
      clr = Color.Buy;
   }
   if (OrderType() == OP_SELL){
      clr = Color.Sell;
   }
   name = name + DoubleToStr(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS));
   name = name + " -> ";
   name = name + DoubleToStr(OrderClosePrice(), MarketInfo(OrderSymbol(), MODE_DIGITS));

   if (remove) {
      ObjectDelete(name);
      int error = GetLastError();
      if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST)
         catch("plotClosedTradeLine(2)", error);
   }
   else {
      ObjectCreate(name, OBJ_TREND, 0, OrderOpenTime(), OrderOpenPrice(), OrderCloseTime(), OrderClosePrice());
      error = GetLastError();
      if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_ALREADY_EXISTS)
         catch("plotClosedTradeLine(3)", error);
      ArrayPushString(objects, name);

      ObjectSet(name, OBJPROP_RAY, false);
      ObjectSet(name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSet(name, OBJPROP_COLOR, clr);
   }

   catch("plotClosedTradeLine(4)");
}


/**
 * Create the info-string for opened and closed order arrows.
 */
string formatOrderArrowInfo() {

   int    digits = MarketInfo(OrderSymbol(), MODE_DIGITS);
   double pip    = 1/MathPow(10, digits & (~1));

   // order is already selected
   string info = StringConcatenate(
                    OrderComment(),
                    " (",
                    OrderMagicNumber(),
                    ")\nP/L: ",
                    DoubleToStr(OrderProfit() + OrderSwap() + OrderCommission(), 2),
                    " ",
                    AccountCurrency(),
                    " (",
                    DoubleToStr(MathAbs(OrderOpenPrice() - OrderClosePrice()) / pip, 2),
                    " pips)"
                 );
   catch("formatOrderArrowInfo()");
   return(info);
}


/**
 * Plot all newly opened trades into the chart.
 * Check if the open trade list has changed and plot
 * arrows for opened trades into the chart.
 * Metatrader won't do this automatically for manual trading.
 * Use this function for scanning for new trades and plotting them.
 */
void plotNewOpenTrades(int magic=-1) {
   if (IsTesting())
      return(0);

   // FIXME! find something to detect changes as cheap as possible!

   int i, total = OrdersTotal();

   // order list has changed, so plot all arrows
   for (i=0; i<total; i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      catch("plotNewOpenTrades(1)   total="+ total +"    i="+ i);

      if ((magic==-1 || OrderMagicNumber()==magic) && OrderSymbol()==Symbol()) {
         if (OrderType()==OP_BUY || OrderType()==OP_SELL)
            plotOpenedTradeArrow(OrderTicket());
      }
   }

   catch("plotNewOpenTrades(2)");
}


/**
 * Plot all newly closed trades into the chart.
 * Check for changes in the trading history and plot the
 * trades into the chart with arrows and lines connectimg them.
 * Metatrader won't do this automatically for manual trading.
 * Use this function for scanning for closed trades and plotting them.
 */
void plotNewClosedTrades(int magic=-1) {
   if (IsTesting())
      return(0);

   static int last_change = 0;
   bool max_age_defined = GlobalVariableCheck("ARROW_MAX_AGE");
   int  max_age         = GlobalVariableGet  ("ARROW_MAX_AGE") * DAYS;

   int error = GetLastError();
   if (error!=ERR_NO_ERROR && error!=ERR_GLOBAL_VARIABLE_NOT_FOUND)
      catch("plotNewClosedTrades(1)", error);

   datetime tc = TimeCurrent();
   bool remove;

   int orders = OrdersHistoryTotal();

   if (orders == 0) {
      last_change = max_age + max_age_defined;
   }
   else {
      OrderSelect(orders-1, SELECT_BY_POS, MODE_HISTORY);
      if (OrderTicket() + max_age + max_age_defined != last_change){
         last_change = OrderTicket() + max_age + max_age_defined;

         // order list has changed, so plot all arrows
         for (int i=0; i < orders; i++){
            OrderSelect(i, SELECT_BY_POS, MODE_HISTORY);
            if((magic == -1 || OrderMagicNumber() == magic) && OrderSymbol() == Symbol()){
               if (OrderType() == OP_BUY || OrderType() == OP_SELL){
                  if (max_age_defined && tc - OrderCloseTime() > max_age){
                     remove = true;
                  }else{
                     remove = false;
                  }
                  plotOpenedTradeArrow(OrderTicket(), remove);
                  plotClosedTradeArrow(OrderTicket(), remove);
                  plotClosedTradeLine(OrderTicket(), remove);
               }
            }
         }
      }
   }
   catch("plotNewClosedTrades(2)");
}


/**
 * Create a horizontal line.
 */
string horizLine(string name, double price, color clr=Red, string label="") {
   if (IsOptimization())
      return(name);

   if (name=="")
      name = "line_" + Time[0];

   if (ObjectFind(name)==-1) {
      ObjectCreate(name, OBJ_HLINE, 0, 0, price);
      ArrayPushString(objects, name);
   }
   else{
      ObjectSet(name, OBJPROP_PRICE1, price);
   }
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSetText(name, label);

   int error = GetLastError();
   if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST && error!=ERR_OBJECT_ALREADY_EXISTS)
      catch("horizLine()", error);
   return(name);
}


/**
 * Create a text label.
 */
string label(string name, int x, int y, int corner, string text, color clr=Gray) {
   if (!IsOptimization()){
      if (name==""){
         name = "label_" + Time[0];
      }
      if (ObjectFind(name) == -1) {
         ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
         ArrayPushString(objects, name);
      }
      ObjectSet(name, OBJPROP_COLOR, clr);
      ObjectSet(name, OBJPROP_CORNER, corner);
      ObjectSet(name, OBJPROP_XDISTANCE, x);
      ObjectSet(name, OBJPROP_YDISTANCE, y);
      ObjectSetText(name, text);
   }

   int error = GetLastError();
   if (error!=ERR_NO_ERROR && error!=ERR_OBJECT_DOES_NOT_EXIST && error!=ERR_OBJECT_ALREADY_EXISTS)
      catch("label()", error);

   return(name);
}


/**
 * Show a button and check if it has been activated.
 * Emulate a button with a label that must be moved by the user.
 * Return true if the label has been moved and move it back.
 * create it if it does not already exist.
 */
bool labelButton(string name, int x, int y, int corner, string text, color clr=Gray) {
   if (IsOptimization())
      return(false);

   if (ObjectFind(name) != -1) {
      if (ObjectGet(name, OBJPROP_XDISTANCE) != x || ObjectGet(name, OBJPROP_YDISTANCE) != y){
         ObjectDelete(name);
         catch("labelButton()");
         return(true);
      }
   }
   label(name, x, y, corner, "[" + text + "]", clr);

   catch("labelButton()");
   return(false);
}


/**
 * Check if a line has been crossed, the line may contain a command string.
 *
 * return "1" or the the argument if price (Bid) just has crossed
 * a line with a decription starting with this command or "" otherwise.
 *
 * for example if a line has the description
 * buy 0.1
 * then it will return the string "0.1" when price has just crossed it
 * and it will return "" if this was not the case.
 *
 * If the parameter one_shot is true (default) it will add the word
 * "triggered: " to the command so it can't be triggered a second time,
 * the line description will then look like
 * triggered: buy 0.1
 * and it will not be active anymore.
 *
 * if there is bo argument behind the command then it will simply
 * return the string "1" if it is triggered.
 *
 * This function is intentionally returning strings and not doubles
 * to enable you to do such funny things like for example define a command
 * "delete" and then have lines like "delete buy" or "delete sell" and have
 * it delete other lines once price triggers this line or do even more
 * complex "visual programming" in the chart.
 */
string crossedLineS(string command, bool one_shot=true, color clr_active=CLR_NONE, color clr_triggered=CLR_NONE) {
   double last_bid; // see below!
   int i;
   double price;
   string name;
   string command_line;
   string command_argument;
   int type;

   if (clr_active    == CLR_NONE) clr_active    = Crossline.Color.Active;
   if (clr_triggered == CLR_NONE) clr_triggered = Crossline.Color.Triggered;

   for (i=0; i<ObjectsTotal(); i++){
      name = ObjectName(i);
      // is this an object without description (newly created by the user)?
      if (ObjectDescription(name) == "") {
         // Sometimes the user draws a new line and the default color is
         // accidentially the color and style of an active line. If we
         // simply reset all lines without decription but with the active
         // color and style we can almost completely eliminate this problem.
         // The color does not influence the functionality in any way but
         // we simply don't WANT to confuse the USER with lines that have
         // the active color and style that are not active lines.
         if (ObjectGet(name, OBJPROP_COLOR)==clr_active && ObjectGet(name, OBJPROP_WIDTH)==Crossline.Width.Active && ObjectGet(name, OBJPROP_STYLE)==Crossline.Style.Active) {
            ObjectSet(name, OBJPROP_COLOR, clr_triggered);
            ObjectSet(name, OBJPROP_STYLE, Crossline.Style.Triggered);
            ObjectSet(name, OBJPROP_WIDTH, Crossline.Width.Triggered);
            ObjectSet(name, OBJPROP_PRICE3, 0);
         }
      }

      // is this an object that contains our command?
      if (StringFind(ObjectDescription(name), command) == 0) {
         price = 0;
         type = ObjectType(name);

         // we only care about certain types of objects
         if (type == OBJ_HLINE) price = ObjectGet(name, OBJPROP_PRICE1);
         if (type == OBJ_TREND) price = ObjectGetValueByShift(name, 0);

         if (price > 0) { // we found a line
            // ATTENTION! DIRTY HACK! MAY BREAK IN FUTURE VERSIONS OF MT4
            // ==========================================================
            // We store the last bid price in the unused PRICE3 field
            // of every line, so we can call this function more than once
            // per tick for multiple lines. A static variable would not work here
            // since we could not call the function a second time during the same tick
            last_bid = ObjectGet(name, OBJPROP_PRICE3);

            // visually mark the line as an active line
            ObjectSet(name, OBJPROP_COLOR, clr_active);
            ObjectSet(name, OBJPROP_STYLE, Crossline.Style.Active);
            ObjectSet(name, OBJPROP_WIDTH, Crossline.Width.Active);

            // we have a last_bid value for this line
            if (last_bid > 0){

               // did price cross this line since the last time we checked this line?
               if ((Close[0] >= price && last_bid <= price) || (Close[0] <= price && last_bid >= price)) {

                  // extract the argument
                  command_line = ObjectDescription(name);
                  command_argument = StringSubstr(command_line, StringLen(command) + 1);
                  if (command_argument == ""){
                     command_argument = "1"; // default argument is "1"
                  }

                  // make the line triggered if it is a one shot command
                  if (one_shot) {
                     ObjectSetText(name, "triggered: " + command_line);
                     ObjectSet(name, OBJPROP_COLOR, clr_triggered);
                     ObjectSet(name, OBJPROP_STYLE, Crossline.Style.Triggered);
                     ObjectSet(name, OBJPROP_WIDTH, Crossline.Width.Triggered);
                     ObjectSet(name, OBJPROP_PRICE3, 0);
                  }
                  else {
                     ObjectSet(name, OBJPROP_PRICE3, Close[0]);
                  }

                  catch("crossedLineS()");
                  return(command_argument);
               }
            }

            // store current price in the line itself
            ObjectSet(name, OBJPROP_PRICE3, Close[0]);
         }
      }

   }

   catch("crossedLineS()");
   return(""); // command line not crossed, return empty string (false)
}


/**
 * Check if a line has been crossed.
 * Call crossedLineS() (see crossedLineS() for more documentation)
 * and cast it into a bool (true if crossed, otherwise false)
 */
bool crossedLine(string command, bool one_shot=true, color clr_active=CLR_NONE, color clr_triggered=CLR_NONE) {
   string arg  = crossedLineS(string command, one_shot, clr_active, clr_triggered);
   bool result = (arg != "");

   catch("crossedLine()");
   return(result);
}


/**
 * Drop-in replacement for OrderModify().
 * Try to handle all errors and locks and return only if successful
 * or if the error can not be handled or waited for.
 */
bool orderModifyReliable(int ticket, double price, double stoploss, double takeprofit, datetime expiration, color arrow_color=CLR_NONE) {
   int err;
   Print("OrderModifyReliable(" + ticket + "," + price + "," + stoploss + "," + takeprofit + "," + expiration + "," + arrow_color + ")");

   while (true) {
      while (IsTradeContextBusy()){
         Print("OrderModifyReliable(): Waiting for trade context.");
         Sleep(MathRand()/10);
      }
      if (OrderModify(ticket, NormalizeDouble(price, Digits), NormalizeDouble(stoploss, Digits), NormalizeDouble(takeprofit, Digits), expiration, arrow_color)) {
         catch("orderModifyReliable()");
         return(true);
      }

      err = GetLastError();
      if (isTemporaryError(err)) {
         log("orderModifyReliable()   temporary error, waiting", err);
      }
      else {
         log("orderModifyReliable()   permanent error, giving up", err);
         return(false);
      }
      Sleep(MathRand()/10);
   }

   catch("orderModifyReliable()", ERR_RUNTIME_ERROR);
   return(false);
}


/**
 * Drop-in replacement for OrderSend().
 * Try to handle all errors and locks and return only if successful
 * or if the error can not be handled or waited for.
 */
int orderSendReliable(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment="", int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   int ticket;
   int err;
   Print("orderSendReliable("+ symbol +","+ cmd +","+ volume +","+ price +","+ slippage +","+ stoploss +","+ takeprofit +","+ comment +","+ magic +","+ expiration +","+ arrow_color +")");

   while(true){
      if (IsStopped()){
         Print("orderSendReliable(): Trading is stopped!");
         catch("orderSendReliable()");
         return(-1);
      }
      RefreshRates();
      if (cmd == OP_BUY)  price = Ask;
      if (cmd == OP_SELL) price = Bid;

      if (!IsTradeContextBusy()) {
         ticket = OrderSend(symbol, cmd, volume, NormalizeDouble(price, MarketInfo(symbol, MODE_DIGITS)), slippage, NormalizeDouble(stoploss, MarketInfo(symbol, MODE_DIGITS)), NormalizeDouble(takeprofit, MarketInfo(symbol, MODE_DIGITS)), comment, magic, expiration, arrow_color);
         if (ticket > 0){
            catch("orderSendReliable()");
            return(ticket); // the normal exit
         }
         err = GetLastError();
         if (isTemporaryError(err)) {
            log("orderSendReliable()   temporary error, waiting", err);
         }
         else {
            log("orderSendReliable()   permanent error, giving up.", err);
            return(-1);
         }
      }
      else {
         Print("orderSendReliable(): Must wait for trade context");
      }
      Sleep(MathRand()/10);
   }

   catch("orderSendReliable()", ERR_RUNTIME_ERROR);
   return(-1);
}


/**
 * Drop-in replacement for OrderClose().
 * Try to handle all errors and locks and return only if successful
 * or if the error can not be handled or waited for.
 */
bool orderCloseReliable(int ticket, double lots, double price, int slippage, color arrow_color=CLR_NONE) {
   int err;
   Print("orderCloseReliable()");
   OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);

   while (true) {
      if (IsStopped()) {
         Print("orderCloseReliable(): Trading is stopped!");
         catch("orderCloseReliable()");
         return(false);
      }
      RefreshRates();
      if (OrderType() == OP_BUY){
         price = Bid;                        // close long at bid
      }
      if (OrderType() == OP_SELL){
         price = Ask;                        // close short at ask
      }
      if (!IsTradeContextBusy()) {
         if (OrderClose(ticket, lots, NormalizeDouble(price, MarketInfo(OrderSymbol(), MODE_DIGITS)), slippage, arrow_color)) {
            catch("orderCloseReliable()");
            return(true);                    // the normal exit
         }
         err = GetLastError();
         if (isTemporaryError(err)) {
            log("orderCloseReliable()   temporary error, waiting", err);
         }
         else {
            log("orderCloseReliable()   permanent error, giving up", err);
            return(false);
         }
      }
      else {
         Print("orderCloseReliable(): Must wait for trade context");
      }
      Sleep(MathRand()/10);
   }

   catch("orderCloseReliable()", ERR_RUNTIME_ERROR);
   return(false);
}


/**
 * Drop-in replacement for OrderDelete().
 * Try to handle all errors and locks and return only if successful
 * or if the error can not be handled or waited for.
 */
bool orderDeleteReliable(int ticket) {
   int err;
   Print("orderDeleteReliable(" + ticket + ")");

   while (true) {
      while (IsTradeContextBusy()) {
         Print("OrderDeleteReliable(): Waiting for trade context.");
         Sleep(MathRand()/10);
      }
      if (OrderDelete(ticket)){
         catch("orderDeleteReliable()");
         return(true);
      }

      err = GetLastError();
      if (isTemporaryError(err)) {
         log("orderDeleteReliable()   temporary error, waiting", err);
      }
      else {
         log("orderDeleteReliable()   permanent error, giving up", err);
         return(false);
      }
      Sleep(MathRand()/10);
   }

   catch("orderDeleteReliable()", ERR_RUNTIME_ERROR);
   return(false);
}


/**
 * Is the error temporary (does it make sense to wait).
 */
bool isTemporaryError(int error) {
   bool result = (error == ERR_NO_ERROR ||
                  error == ERR_COMMON_ERROR ||
                  error == ERR_SERVER_BUSY ||
                  error == ERR_NO_CONNECTION ||
                  error == ERR_MARKET_CLOSED ||
                  error == ERR_PRICE_CHANGED ||
                  error == ERR_INVALID_PRICE ||  //happens sometimes
                  error == ERR_OFF_QUOTES ||
                  error == ERR_BROKER_BUSY ||
                  error == ERR_REQUOTE ||
                  error == ERR_TRADE_TIMEOUT ||
                  error == ERR_TRADE_CONTEXT_BUSY);

   catch("isTemporaryError()");
   return(result);
}