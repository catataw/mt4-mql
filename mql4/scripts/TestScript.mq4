/**
 * TestScript
 */
#include <stdlib.mqh>
#include <win32api.mqh>
#include <sampledll.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   int error = onInit(T_SCRIPT);



   int hProcess=GetCurrentProcess(), data[1], iNull[];
   data[0] = 107795257;

   string s1 = StringConcatenate("string ", "value");
   int addr  = GetIntValue(s1);
   string s2 = GetStringValue(addr);

   if (!WriteProcessMemory(hProcess, addr, data, 4, iNull)) return(0);
   debug("init()   s1->"+ s1 +"    s2->"+ s2);

   data[0] = data[0]+2000;
   if (!WriteProcessMemory(hProcess, addr, data, 4, iNull)) return(0);
   debug("init()   s1->"+ s1 +"    s2->"+ s2);



   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(catch("onStart()"));
}


