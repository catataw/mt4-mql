/**
 * LFX.ExecuteTradeCmd
 *
 * Script, da� nur intern zur Ausf�hrung von zwischen den Terminals verschickten TradeCommands benutzt wird. Ein manueller Aufruf ist nicht m�glich.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <core/script.mqh>

#include <win32api.mqh>
#include <MT4iQuickChannel.mqh>
#include <core/script.ParameterProvider.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   // (1) Parameter einlesen
   string parameters = GetScriptParameters();
   if (parameters == "")
      return(last_error);

   debug("onStart()   script parameters=\""+ parameters +"\"");


   // (2) TradeCommands ausf�hren
   return(last_error);
}
