/**
 * Schlie�t die angegebenen LFX-Positionen.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <core/script.mqh>

#include <LFXBasket/define.mqh>
#include <LFXBasket/functions.mqh>

#property show_inputs


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern string LFX.Labels = "";                           // Label-1 [, Label-n [, ...]]      (Pr�fung per OrderComment().StringIStartsWith(value))

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string labels[];
int    sizeOfLabels;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // Parametervalidierung
   LFX.Labels = StringTrim(LFX.Labels);
   if (StringLen(LFX.Labels) == 0)
      return(catch("onInit(1)   Invalid input parameter LFX.Labels = \""+ LFX.Labels +"\"", ERR_INVALID_INPUT_PARAMVALUE));

   // Parameter splitten und die einzelnen Label trimmen
   sizeOfLabels = Explode(LFX.Labels, ",", labels, NULL);

   for (int i=0; i < sizeOfLabels; i++) {
      labels[i] = StringTrim(labels[i]);
   }
   return(catch("onInit(2)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   int    orders = OrdersTotal();
   string positions[]; ArrayResize(positions, 0);
   int    tickets  []; ArrayResize(tickets, 0);


   // (1) zu schlie�ende Positionen selektieren
   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))      // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;

      if (LFX.IsMyOrder()) {
         if (OrderType() > OP_SELL)
            continue;

         for (int n=0; n < sizeOfLabels; n++) {
            if (StringIStartsWith(OrderComment(), labels[n])) {
               string label = GetCurrency(LFX.GetCurrencyId(OrderMagicNumber())) +"."+ LFX.GetCounter(OrderMagicNumber());
               if (!StringInArray(positions, label))
                  ArrayPushString(positions, label);
               if (!IntInArray(tickets, OrderTicket()))
                  ArrayPushInt(tickets, OrderTicket());
               break;
            }
         }
      }
   }


   // (2) Positionen schlie�en
   int sizeOfPositions = ArraySize(positions);
   if (sizeOfPositions > 0) {
      PlaySound("notify.wav");
      int button = MessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to close the specified "+ ifString(sizeOfPositions==1, "", sizeOfPositions +" ") +"position"+ ifString(sizeOfPositions==1, "", "s") +"?", __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
      if (button == IDOK) {
         int oeFlags = NULL;
         /*ORDER_EXECUTION*/int oes[][ORDER_EXECUTION.intSize]; ArrayResize(oes, ArraySize(tickets)); InitializeByteBuffer(oes, ORDER_EXECUTION.size);
         if (!OrderMultiClose(tickets, 0.1, Orange, oeFlags, oes))
            return(SetLastError(stdlib_GetLastError()));
         ArrayResize(oes, 0);

         // TODO: erzielten ClosePrice() berechnen und ausgeben

         // (3) Positionen aus ".\experts\files\LiteForex\remote_positions.ini" l�schen
         string file    = TerminalPath() +"\\experts\\files\\LiteForex\\remote_positions.ini";
         string section = ShortAccountCompany() +"."+ AccountNumber();
         for (i=0; i < sizeOfPositions; i++) {
            int error = DeletePrivateProfileKey(file, section, positions[i]);
            if (IsError(error))
               return(SetLastError(error));
         }
      }
   }
   else {
      PlaySound("notify.wav");
      MessageBox("No matching positions found.", __NAME__, MB_ICONEXCLAMATION|MB_OK);
   }

   return(last_error);
}
