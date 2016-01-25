/**
 * Schlie�t die angegebenen LFX-Positionen.
 *
 *
 * FEHLER !!!: Werden mehrere Positionen angegeben, wird nur die letzte geschlossen.
 *
 *
 * NOTE: Zur Zeit k�nnen die Positionen nur einzeln und nicht gleichzeitig geschlossen werden. Beim gleichzeitigen Schlie�en
 *       kann der ClosePrice der Gesamtposition noch nicht korrekt berechnet werden. Beim einzelnen Schlie�en mehrerer Positionen
 *       werden dadurch Commission und Spread mehrfach berechnet.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

#property show_inputs
////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern string LFX.Labels = "";                           // Label_1 [, Label_n [, ...]]: Pr�fung per OrderComment().StringStartsWithI(value)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/script.mqh>
#include <stdfunctions.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinStrings.mqh>
#include <stdlib.mqh>

#include <MT4iQuickChannel.mqh>
#include <lfx.mqh>
#include <structs/myfx/LFX_ORDER.mqh>


string inputLabels[];


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // TradeAccount initialisieren
   if (!InitTradeAccount())
      return(last_error);

   // Parametervalidierung
   LFX.Labels = StringTrim(LFX.Labels);
   if (!StringLen(LFX.Labels))
      return(HandleScriptError("onInit(1)", "Invalid input parameter LFX.Labels = \""+ LFX.Labels +"\"", ERR_INVALID_INPUT_PARAMETER));

   // Labels splitten und trimmen
   int size = Explode(LFX.Labels, ",", inputLabels, NULL);

   for (int i=0; i < size; i++) {
      inputLabels[i] = StringTrim(inputLabels[i]);
   }
   return(catch("onInit(2)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   QC.StopChannels();
   return(last_error);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   int magics       []; ArrayResize(magics,        0);      // alle zu schlie�enden LFX-'Tickets'
   int tickets      []; ArrayResize(tickets,       0);      // alle zu schlie�enden MT4-Tickets
   int tickets.magic[]; ArrayResize(tickets.magic, 0);      // MagicNumbers der zu schlie�enden MT4-Tickets: size(tickets) == size(tickets.magic)

   int inputSize=ArraySize(inputLabels), orders=OrdersTotal();


   // (1) zu schlie�ende Positionen selektieren
   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))      // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;
      if (LFX.IsMyOrder()) {
         if (OrderType() > OP_SELL)
            continue;
         for (int n=0; n < inputSize; n++) {
            if (StringStartsWithI(OrderComment(), inputLabels[n])) {
               if (!IntInArray(magics, OrderMagicNumber())) {
                  ArrayPushInt(magics, OrderMagicNumber());
               }
               if (!IntInArray(tickets, OrderTicket())) {
                  ArrayPushInt(tickets,       OrderTicket()     );
                  ArrayPushInt(tickets.magic, OrderMagicNumber());
               }
               break;
            }
         }
      }
   }
   int magicsSize = ArraySize(magics);
   if (!magicsSize) {
      PlaySoundEx("Windows Notify.wav");
      MessageBox("No matching LFX positions found.", __NAME__, MB_ICONEXCLAMATION|MB_OK);
      return(catch("onStart(1)"));
   }


   // (2) Sicherheitsabfrage
   PlaySoundEx("Windows Notify.wav");
   int button = MessageBox(ifString(!IsDemo(), "- Real Account -\n\n", "") +"Do you really want to close the specified "+ ifString(magicsSize==1, "", magicsSize +" ") +"LFX position"+ ifString(magicsSize==1, "", "s") +"?", __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
   if (button != IDOK)
      return(catch("onStart(2)"));


   // (3) Alle selektierten LFX-Orders sperren, damit andere Indikatoren/Charts keine tempor�ren Teilpositionen verarbeiten.
   for (i=0; i < magicsSize; i++) {
      // TODO: Deadlocks verhindern, falls einer der Mutexe bereits gesperrt ist.
      //if (!AquireLock("mutex.LFX.#"+ magics[i], true))
      //   return(SetLastError(stdlib.GetLastError()));
   }


   // (4) Positionen nacheinander schlie�en
   int ticketsSize = ArraySize(tickets);

   for (i=0; i < magicsSize; i++) {
      int positionSize, position[]; ArrayResize(position, 0);                          // Subset der in (1) gefundenen Tickets, Tickets jeweils einer LFX-Position
      for (n=0; n < ticketsSize; n++) {
         if (magics[i] == tickets.magic[n])
            positionSize = ArrayPushInt(position, tickets[n]);
      }


      // (5) Orderausf�hrung
      double slippage    = 0.1;
      color  markerColor = CLR_NONE;
      int    oeFlags     = NULL;

      if (IsError(stdlib.GetLastError())) return(SetLastError(stdlib.GetLastError())); // vor Trade-Request alle evt. aufgetretenen Fehler abfangen
      if (IsError(catch("onStart(3)")))   return(last_error);

      /*ORDER_EXECUTION*/int oes[][ORDER_EXECUTION.intSize]; ArrayResize(oes, ArraySize(position)); InitializeByteBuffer(oes, ORDER_EXECUTION.size);
      if (!OrderMultiClose(position, slippage, markerColor, oeFlags, oes))
         return(SetLastError(stdlib.GetLastError()));


      // (6) Gesamt-ClosePrice und -Profit berechnen
      string currency = GetCurrency(LFX.CurrencyId(magics[i]));
      double closePrice=1.0, profit=0;
      for (n=0; n < positionSize; n++) {
         if (StringStartsWith(oes.Symbol(oes, n), currency)) closePrice *= oes.ClosePrice(oes, n);
         else                                                closePrice /= oes.ClosePrice(oes, n);
         profit += oes.Swap(oes, n) + oes.Commission(oes, n) + oes.Profit(oes, n);
      }
      closePrice = MathPow(closePrice, 1/7.);
      if (currency == "JPY")
         closePrice *= 100;                                          // JPY wird normalisiert


      // (7) LFX-Order aktualisieren und speichern
      /*LFX_ORDER*/int lo[];
      int result = LFX.GetOrder(magics[i], lo);
      if (result < 1) { if (!result) return(last_error); return(catch("onStart(5)  LFX order "+ magics[i] +" not found", ERR_RUNTIME_ERROR)); }
         datetime now.fxt = TimeFXT(); if (!now.fxt) return(last_error);
         lo.setCloseTime (lo, now.fxt   );
         lo.setClosePrice(lo, closePrice);
         lo.setProfit    (lo, profit    );
            string comment = lo.Comment(lo);
               if (StringStartsWith(comment, lo.Currency(lo))) comment = StringSubstr(comment, 3);
               if (StringStartsWith(comment, "."            )) comment = StringSubstr(comment, 1);
               if (StringStartsWith(comment, "#"            )) comment = StringSubstr(comment, 1);
               int counter = StrToInteger(comment);
            string sCounter = ifString(!counter, "", "."+ counter);  // letzten Counter ermitteln
         lo.setComment   (lo, ""        );
      if (!LFX.SaveOrder(lo))
         return(last_error);


      // (8) Logmessage ausgeben
      if (__LOG) log("onStart(4)  "+ currency + sCounter +" closed at "+ NumberToStr(lo.ClosePrice(lo), ".4'") +", profit: "+ DoubleToStr(lo.Profit(lo), 2));


      // (9) LFX-Terminal benachrichtigen
      if (!QC.SendOrderNotification(lo.CurrencyId(lo), "LFX:"+ lo.Ticket(lo) +":close=1"))
         return(false);
   }


   // (9) Orders wieder freigeben
   for (i=0; i < magicsSize; i++) {
      //if (!ReleaseLock("mutex.LFX.#"+ magics[i]))
      //   return(SetLastError(stdlib.GetLastError()));
   }
   return(catch("onStart(6)"));
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


/*abstract*/bool QC.StopScriptParameterSender()  { return(!catch("QC.StopScriptParameterSender(1)", ERR_WRONG_JUMP)); }


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "struct.ORDER_EXECUTION.ex4"
   string oes.Symbol    (/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.ClosePrice(/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Swap      (/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Commission(/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Profit    (/*ORDER_EXECUTION*/int oe[][], int i);
#import
