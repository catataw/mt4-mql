/**
 *
 */
#property library

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/library.mqh>
#include <stdfunctions.mqh>
#include <structs/pewa/ORDER_EXECUTION.mqh>


/**
 * Wird nur im Tester in library::init() aufgerufen, um alle verwendeten globalen Arrays zur�cksetzen zu k�nnen (EA-Bugfix).
 */
void Tester.ResetGlobalArrays() {
   ArrayResize(stack.orderSelections, 0);
}
