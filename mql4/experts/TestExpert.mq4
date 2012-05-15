/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__      T_EXPERT
int   __INIT_FLAGS__[] = {INIT_TIMEZONE, INIT_TICKVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitChartOpen() {
   debug("onInitChartOpen()");
   // neues Chartfenster (nach Terminal-Neustart oder File->New Chart), neuer EA
   // - nach Terminal->Exit->Neustart kein Input-Dialog, wenn der EA bereits geladen war
   // - nach File->New Chart Input-Dialog
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitChartClose() {
   debug("onInitChartClose()");
   // altes Chartfenster, dessen Template neugeladen wurde, neuer EA
   // Input-Dialog
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitRemove() {
   debug("onInitRemove()");
   // altes Chartfenster, von dem vorher der EA "removed" wurde, neuer EA
   // Input-Dialog
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitRecompile() {
   debug("onInitRecompile()");
   // altes Chartfenster, alter EA nach Recompile
   // kein Input-Dialog
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitParameterChange() {
   debug("onInitParameterChange()");
   // altes Chartfenster, alter EA nach Parameter-Change
   // Input-Dialog
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInitChartChange() {
   debug("onInitChartChange()");
   // altes Chartfenster, alter EA nach Symbol- oder Timeframe-Change
   // kein Input-Dialog
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartOpen() {
   debug("onDeinitChartOpen()");
   // kein UninitializeReason, Ausführungsende im Tester
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartClose() {
   debug("onDeinitChartClose()");
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   debug("onDeinitRemove()");
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   debug("onDeinitRecompile()");
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   debug("onDeinitParameterChange()");
   return(NO_ERROR);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   debug("onDeinitChartChange()");
   return(NO_ERROR);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   return(catch("onTick()"));
}
