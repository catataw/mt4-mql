/**
 * TestScript
 */
#include <stdlib.mqh>
#include <win32api.mqh>
//#include <sampledll.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   int error = onInit(T_SCRIPT);

   /*
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
   */

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

   ExpertProperties();

   return(catch("onStart()"));
}


/**
 * Ruft den Input-Dialog des EA's im aktuellen Chart auf.
 *
 * @return int - Fehlerstatus bzw. -1, wenn der Tester läuft und WindowHandle() nicht benutzt werden kann
 */
int ExpertProperties() {
   int hWnd = WindowHandle(Symbol(), Period());
   if (hWnd == 0)
      return(catch("ExpertProperties() ->WindowHandle() = "+ hWnd, ERR_RUNTIME_ERROR));

   PostMessageA(hWnd, WM_COMMAND, WM_MT4_EXPERT_PROPERTIES, 0);
   return(NO_ERROR);
}
