/**
 * TestExpert
 */
#include <stdlib.mqh>
#include <win32api.mqh>


datetime startTime;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
      return(last_error);

   debug("init()   terminalVersion = "+ GetTerminalVersion());
   debug("init()   terminalBuild = "+ GetTerminalBuild());
   debug("init()   hWndTester = "+ GetTesterWindow());

   return(catch("init()"));
}


/**
 * Gibt das Fensterhandle des Strategy Testers zurück.
 *
 * @return int - Handle oder 0, falls ein Fehler auftrat
 */
int GetTesterWindow() {
   static int hWndTester;                                   // in Library überleben statische Variablen Timeframe-Wechsel, solange sie nicht per Initializer initialisiert werden
   if (hWndTester != 0)
      return(hWndTester);

   /*
   - Das Fenster kann im Terminalfensters oder in einem Toplevel-Window angedockt sein, das Handle dieses Child-Windows ist in beiden Fällen dasselbe.
   - Die Afx-Klassennamen sind dynamisch und müssen zur Laufzeit ermittelt werden (Fenstertexte dürfen wegen Internationalisierung nicht benutzt werden).
   - Klassennamen:
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | Build | Terminal                     | Tester Toplevel-Wrapper                   | Tester                                    | AfxControlBar    |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 225   | MetaQuotes::MetaTrader::4.00 | Afx:400000:8:10011:0:0                    | Afx:400000:b:10011:0:0                    | AfxControlBar42  |
     |       |                              | Afx:400000:8:10013:0:0                    | Afx:400000:b:10013:0:0                    |                  |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 402   | MetaQuotes::MetaTrader::4.00 | Afx:400000:8:10013:0:0                    | Afx:400000:b:10013:0:0                    | AfxControlBar42  |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 406   | MetaQuotes::MetaTrader::4.00 | Afx:400000:8:10013:0:0                    | Afx:400000:b:10013:0:0                    | AfxControlBar42s |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 409   | MetaQuotes::MetaTrader::4.00 | Afx:400000:8:10013:0:0                    | Afx:400000:b:10013:0:0                    | AfxControlBar42s |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 416   | MetaQuotes::MetaTrader::4.00 | Afx:00400000:8:00010013:00000000:00000000 | Afx:00400000:b:00010013:00000000:00000000 | AfxControlBar90s |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+
     | 419   | MetaQuotes::MetaTrader::4.00 | Afx:00400000:8:00010011:00000000:00000000 | Afx:00400000:b:00010011:00000000:00000000 | AfxControlBar90s |
     |       |                              | Afx:00400000:8:00010013:00000000:00000000 | Afx:00400000:b:00010013:00000000:00000000 |                  |
     +-------+------------------------------+-------------------------------------------+-------------------------------------------+------------------+

   - Afx-Namensschema (@see http://msdn.microsoft.com/en-us/library/btbxa0ad%28v=vs.90%29.aspx)

     Afx:%x:%x
     Afx:%x:%x:%x:%x:%x

     The hex digits that replace the %x characters are filled in from data from the WNDCLASS structure. The replaceable values for the %x characters
     shown above are as follows:

        WNDCLASS.hInstance
        WNDCLASS.style
        WNDCLASS.hCursor
        WNDCLASS.hbrBackground
        WNDCLASS.hIcon

     The first form (Afx:%x:%x) is used when hCursor, hbrBackground and hIcon are all NULL.
   */

   int    build = GetTerminalBuild();
   string class, classTopLevel, classTester, classAfxControlBar;

   // (1) Zunächst alle Child-Windows des Terminalfensters der Klasse "AfxControlBar42" durchlaufen und prüfen, ob Tester dort angedockt ist.
   int hChild = GetTopWindow(GetTerminalWindow());
   while (hChild != 0) {
      if (GetClassName(hChild) == "AfxControlBar42") {
         int hSubChild = GetTopWindow(hChild);
         while (hSubChild != 0) {
            class = GetClassName(hSubChild);
            if (class == "ToolbarWindow32")                          // Haupttoolbar => weiter mit dem nächsten AfxControlBar42-ChildWindow
               break;
                                                                     // "Afx:400000:b:10011:0:0"|"Afx:400000:b:10013:0:0"
            if (StringStartsWith(class, "Afx:400000:b:")) /*&&*/ if (StringStartsWith(GetWindowText(hSubChild), "Tester")) {
               hWndTester = hSubChild;                               // angedockt
               //debug("GetTesterWindow()    hWndTester=0x"+ IntToHexStr(hWndTester) +"   class=\""+ GetClassName(hWndTester) +"\"   title=\""+ GetWindowText(hWndTester) +"\" docked");
               break;
            }
            hSubChild = GetWindow(hSubChild, GW_HWNDNEXT);
         }
         if (hWndTester != 0)
            break;
      }
      hChild = GetWindow(hChild, GW_HWNDNEXT);
   }
   if (hWndTester != 0)
      return(hWndTester);


   // (2) Dann Toplevel-Windows durchlaufen und Testerfenster des eigenen Prozesses finden.
   int processId[1], hNext=GetTopWindow(NULL), me=GetCurrentProcessId();
   while (hNext != 0) {
      //debug("GetTesterWindow()    top-level hNext=0x"+ IntToHexStr(hNext) +"   class=\""+ GetClassName(hNext) +"\"   title=\""+ GetWindowText(hNext) +"\"");

      GetWindowThreadProcessId(hNext, processId);
      if (processId[0] == me) {
         //debug("GetTesterWindow()    top-level(me) hNext=0x"+ IntToHexStr(hNext) +"   class=\""+ GetClassName(hNext) +"\"   title=\""+ GetWindowText(hNext) +"\"");
         if (StringStartsWith(GetClassName(hNext), "Afx:400000:8:")) {           // "Afx:400000:8:10011:0:0"|"Afx:400000:8:10013:0:0"
            if (StringStartsWith(GetWindowText(hNext), "Tester")) {
               hChild = GetTopWindow(hNext);
               if (hChild == 0)                               return(_ZERO(catch("GetTesterWindow(1)   cannot find any children of floating top-level window 0x"+ IntToHexStr(hNext) +"  class=\""+ GetClassName(hNext) +"\"  title=\""+ GetWindowText(hNext) +"\"", ERR_RUNTIME_ERROR)));
               if (GetClassName(hChild) != "AfxControlBar42") return(_ZERO(catch("GetTesterWindow(2)   class of 1st child of floating top-level window 0x"+ IntToHexStr(hNext) +" is not \"AfxControlBar42\":  found \""+ GetClassName(hChild) +"\"", ERR_RUNTIME_ERROR)));

               hSubChild = GetTopWindow(hChild);
               if (hSubChild == 0)                            return(_ZERO(catch("GetTesterWindow(3)   cannot find any sub-children of floating top-level window 0x"+ IntToHexStr(hNext) +"  class=\""+ GetClassName(hNext) +"\"  title=\""+ GetWindowText(hNext) +"\"", ERR_RUNTIME_ERROR)));
               if (!StringStartsWith(GetClassName(hSubChild), "Afx:400000:b:"))  // "Afx:400000:b:10011:0:0"|"Afx:400000:b:10013:0:0"
                                                              return(_ZERO(catch("GetTesterWindow(4)   class of 1st sub-child of floating top-level window 0x"+ IntToHexStr(hNext) +" is not \"Afx:400000:b:10013:0:0\":  found \""+ GetClassName(hSubChild) +"\"", ERR_RUNTIME_ERROR)));

               hWndTester = hSubChild;                                           // im floatenden Toplevel-Fenster angedockt
               //debug("GetTesterWindow()    hWndTester=0x"+ IntToHexStr(hWndTester) +"   class=\""+ GetClassName(hWndTester) +"\"   title=\""+ GetWindowText(hWndTester) +"\" floating");
               break;
            }
         }
      }
      hNext = GetWindow(hNext, GW_HWNDNEXT);
   }

   if (hWndTester == 0)
      catch("GetTesterWindow(5)   cannot find tester window", ERR_RUNTIME_ERROR);
   return(hWndTester);
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

   return(NO_ERROR);



   if (startTime == 0)
      startTime = TimeCurrent();

   static bool done1, done2, done3, done4;
   static int ticket, ticket1, ticket2, partial;

   double execution[] = {NULL};

   if (!done1) {
      if (TimeCurrent() > startTime + 1*HOUR) {
         done1 = true;
         debug("onTick(1)          Ticket         Type   Lots   Symbol              OpenTime   OpenPrice             CloseTime   ClosePrice   Swap   Commission   Profit   MagicNumber   Comment");

         execution[EXEC_FLAGS] = NULL;
         ticket1 = OrderSendEx(Symbol(), OP_BUY, 0.7, NULL, NULL, NULL, NULL, "order comment", 111, NULL, Blue, execution);
         if (ticket1 == -1)
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick(1) ->open        #"+ ticket1 +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket1, "onTick(1)"))
            return(last_error);
         //debug("onTick(1) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done2) {
      if (TimeCurrent() > startTime + 2*HOURS) {
         done2 = true;

         execution[EXEC_FLAGS] = NULL;
         ticket2 = OrderSendEx(Symbol(), OP_SELL, 1, NULL, NULL, NULL, NULL, "order comment", 222, NULL, Red, execution);
         if (ticket2 == -1)
            return(SetLastError(stdlib_PeekLastError()));
         //debug("onTick(2) ->open        #"+ ticket2 +" = "+ ExecutionToStr(execution));

         if (!OrderSelectByTicket(ticket2, "onTick(2)"))
            return(last_error);
         //debug("onTick(2) open  "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
      }
   }

   if (!done3) {
      if (TimeCurrent() > startTime + 3*HOURS) {
         done3 = true;

         if (!OrderSelectByTicket(ticket1, "onTick(3)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         if (!OrderSelectByTicket(ticket2, "onTick(4)"))
            return(last_error);
         debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());

         int tickets[];
         ArrayPushInt(tickets, ticket1);
         ArrayPushInt(tickets, ticket2);

         execution[EXEC_FLAGS] = NULL;
         if (!OrderMultiClose(tickets, NULL, Orange, execution))
            return(SetLastError(stdlib_PeekLastError()));
         debug("onTick(3) ->OrderMultiClose = "+ ExecutionToStr(execution));

         int orders = OrdersHistoryTotal();
         for (int i=0; i < orders; i++) {
            OrderSelect(i, SELECT_BY_POS, MODE_HISTORY);
            debug("onTick(3)       "+ StringLeftPad("#"+ OrderTicket(), 9, " ") +"   "+ StringLeftPad(OperationTypeDescription(OrderType()), 10, " ") +"   "+ DoubleToStr(OrderLots(), 2) +"   "+ OrderSymbol() +"   "+ TimeToStr(OrderOpenTime(), TIME_FULL) +" "+ StringLeftPad(NumberToStr(OrderOpenPrice(), PriceFormat), 11, " ") +"   "+ ifString(OrderCloseTime()==0, "                   ", TimeToStr(OrderCloseTime(), TIME_FULL)) +" "+ StringLeftPad(NumberToStr(OrderClosePrice(), PriceFormat), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderSwap(), 2), 6, " ") +" "+ StringLeftPad(DoubleToStr(OrderCommission(), 2), 12, " ") +" "+ StringLeftPad(DoubleToStr(OrderProfit(), 2), 8, " ") +"   "+ StringLeftPad(OrderMagicNumber(), 11, " ") +"   "+ OrderComment());
         }
      }
   }

   return(catch("onTick(7)"));
}
