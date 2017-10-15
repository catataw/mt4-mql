/**
 *
 */
#property library

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/library.mqh>
#include <stdfunctions.mqh>
#include <functions/JoinStrings.mqh>
#include <structs/xtrade/OrderExecution.mqh>


/**
 * Wird von Expert::Library::init() bei Init-Cycle im Tester aufgerufen, um die verwendeten globalen Variablen vor dem
 * n�chsten Test zur�ckzusetzen.
 */
void Tester.ResetGlobalLibraryVars() {
}
