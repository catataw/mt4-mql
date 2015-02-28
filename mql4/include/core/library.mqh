
int __TYPE__         = T_LIBRARY;
int __lpSuperContext = NULL;


/**
 * Initialisierung der Library.
 *
 * @return int - Fehlerstatus
 */
int init() {
   // Im Tester globale Arrays eines EA's zur�cksetzen.
   if (IsTesting()) {                                             // Zur Zeit kein besserer Workaround f�r die ansonsten im Speicher verbleibenden Variablen des vorherigen Tests.
      Tester.ResetGlobalArrays();                                 // K�nnte ein Feature f�r die Optimization sein, um Daten test�bergreifend verwalten zu k�nnen.
   }
   //Expander_init(__ExecutionContext);
   return(catch("init()"));
}


/**
 * Startfunktion f�r Libraries (Dummy).
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: F�r den Compiler v224 mu� ab einer unbestimmten Komplexit�t der Library eine start()-Funktion existieren,
 *       wenn die init()-Funktion aufgerufen werden soll.
 */
int start() {
   //Expander_start(__ExecutionContext);
   return(catch("start()", ERR_WRONG_JUMP));
}


/**
 * Deinitialisierung der Library.
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: 1) Bei VisualMode=Off und regul�rem Testende (Testperiode zu Ende) bricht das Terminal komplexere EA-deinit()-Funktionen verfr�ht und nicht
 *          erst nach 2.5 Sekunden ab. In diesem Fall wird diese deinit()-Funktion u.U. auch nicht mehr ausgef�hrt.
 *
 *       2) Bei Testende wird diese deinit()-Funktion u.U. zweimal aufgerufen. Beim zweiten Mal ist die Library zur�ckgesetzt, der Variablen-Status also
 *          undefiniert.
 */
int deinit() {
   //Expander_deinit(__ExecutionContext);
   return(catch("deinit()")); __DummyCalls();
}


/**
 * Gibt die ID des aktuellen oder letzten Init()-Szenarios zur�ck. Kann au�er in deinit() �berall aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int InitReason() {
   return(_NULL(catch("InitReason()", ERR_NOT_IMPLEMENTED)));
}


/**
 * Gibt die ID des aktuellen Deinit()-Szenarios zur�ck. Kann nur in deinit() aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int DeinitReason() {
   return(_NULL(catch("DeinitReason()", ERR_NOT_IMPLEMENTED)));
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Expert ist.
 *
 * @return bool
 */
bool IsExpert() {
   if (__TYPE__ == T_LIBRARY) return(!catch("IsExpert()  library not initialized", ERR_RUNTIME_ERROR));

   return(__TYPE__ & T_EXPERT != 0);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Script ist.
 *
 * @return bool
 */
bool IsScript() {
   if (__TYPE__ == T_LIBRARY) return(!catch("IsScript()  library not initialized", ERR_RUNTIME_ERROR));

   return(__TYPE__ & T_SCRIPT != 0);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Indikator ist.
 *
 * @return bool
 */
bool IsIndicator() {
   if (__TYPE__ == T_LIBRARY) return(!catch("IsIndicator()  library not initialized", ERR_RUNTIME_ERROR));

   return(__TYPE__ & T_INDICATOR != 0);
}


/**
 * Ob das aktuell ausgef�hrte Modul eine Library ist.
 *
 * @return bool
 */
bool IsLibrary() {
   return(true);
}


/**
 * Ob das aktuelle Programm durch ein anderes Programm ausgef�hrt wird.
 *
 * @return bool
 */
bool IsSuperContext() {
   if (__TYPE__ == T_LIBRARY) return(!catch("IsSuperContext()  library not initialized", ERR_RUNTIME_ERROR));

   return(__lpSuperContext != 0);
}


/**
 * Setzt den internen Fehlercode des Moduls.
 *
 * @param  int error - Fehlercode
 *
 * @return int - derselbe Fehlercode (for chaining)
 *
 *
 * NOTE: Akzeptiert einen weiteren beliebigen Parameter, der bei der Verarbeitung jedoch ignoriert wird.
 */
int SetLastError(int error, int param=NULL) {
   last_error = error;
   return(ec.setLastError(__ExecutionContext, last_error));
}


/**
 * �berpr�ft und aktualisiert den aktuellen Programmstatus. Darf in Libraries nicht verwendet werden, dort kann der Programmstatus aus dem
 * EXECUTION_CONTEXT ausgelesen, jedoch nicht modifiziert werden.
 *
 * @param  int value - der zur�ckzugebende Wert (default: NULL)
 *
 * @return int - der �bergebene Wert
 */
int UpdateProgramStatus(int value=NULL) {
   catch("UpdateProgramStatus()", ERR_FUNC_NOT_ALLOWED);
   return(value);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   int    GetTesterWindow();
   int    GetUIThreadId();
   string GetWindowText(int hWnd);
   bool   StringEndsWith(string object, string postfix);

#import "stdlib2.ex4"
   int    GetTerminalRuntime();

#import "kernel32.dll"
   int    GetCurrentThreadId();

#import "user32.dll"
   int    GetParent(int hWnd);

#import "struct.EXECUTION_CONTEXT.ex4"
   int    ec.setLastError(/*EXECUTION_CONTEXT*/int ec[], int lastError);
#import
