/**
 * LFX.ExecuteTradeCmd
 *
 * Script, da� intern zur Ausf�hrung von zwischen den Terminals verschickten TradeCommands benutzt wird. Parameter werden per QuickChannel �bergeben.
 * Ein manueller Aufruf ist nicht m�glich.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <core/script.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   debug("onStart()   running");
   return(last_error);
}
