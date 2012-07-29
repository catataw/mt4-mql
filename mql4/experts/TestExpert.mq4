/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {

      if (TimeCurrent() > D'2012-07-20 09:30') {
         //catch("onTick()", ERR_INVALID_STOP);
         done = true;
      }
   }


   if (IsTesting()) {
      debug("onTick()   hWndTester="+ GetTesterWindow());
   }
   return(catch("onTick()"));
}


/**
 * Pausiert den Tester. Der Aufruf ist nur im Tester möglich.
 *
 * @return int - Fehlerstatus
 */
int Tester.Pause() {
   if (!This.IsTesting()) return(catch("Tester.Pause()   Tester only function", ERR_FUNC_NOT_ALLOWED));

   if (!IsScript()) {
      if (IsStopped())                 return(NO_ERROR);             // skipping (nach Klick auf "Stop" war weder in start() noch in deinit() das IsStopped()-Flag gesetzt)
      if (__WHEREAMI__ == FUNC_DEINIT) return(NO_ERROR);             // skipping
   }
   if (!Tester.IsPaused())             return(NO_ERROR);             // skipping

   SendMessageA(GetApplicationWindow(), WM_COMMAND, ID_TESTER_PAUSERESUME, 0);
   return(NO_ERROR);
}


/**
 * Ob der Tester momentan pausiert. Der Aufruf ist nur im Tester möglich.
 *
 * @return bool
 */
bool Tester.IsPaused() {
   if (!This.IsTesting()) return(_false(catch("Tester.IsPaused()   Tester only function", ERR_FUNC_NOT_ALLOWED)));

   bool visualMode, testerStopped, testerOnPause;

   if (IsExpert()) {
      visualMode    = IsVisualMode();
      testerStopped = false;                                         // Code wird ausgeführt, also FALSE
      testerOnPause = GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_PAUSERESUME)) == ">>";
   }
   else if (IsIndicator()) {
      visualMode    = true;
      testerStopped = false;                                         // Code wird ausgeführt, also FALSE
      testerOnPause = GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_PAUSERESUME)) == ">>";
   }
   else /*_Script_*/ {
      visualMode    = true;
         int hWndSettings = GetDlgItem(GetTesterWindow(), ID_TESTER_SETTINGS);
      testerStopped = GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_STARTSTOP  )) == "Start";
      testerOnPause = GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_PAUSERESUME)) == ">>";
   }



   return(false);
}


/**
 * Schickt einen künstlichen Tick an den aktuellen Chart.
 *
 * @param  bool sound - ob der Tick akustisch bestätigt werden soll oder nicht (default: nein)
 *
 * @return int - Fehlerstatus
 */
int Chart.SendTick(bool sound=false) {
   bool testing, visualMode, testerStopped, testerPaused;

   if (IsExpert()) {
      testing       = IsTesting();
      visualMode    = IsVisualMode();
      testerStopped = false;                                         // Code wird ausgeführt, also beide FALSE
      testerPaused  = false;
   }
   else if (IsIndicator()) {
      testing       = IndicatorIsTesting();                          // TODO: IndicatorIsTesting() in init() und deinit() implementieren
      visualMode    = testing;
      testerStopped = false;                                         // Code wird ausgeführt, also beide FALSE
      testerPaused  = false;
   }
   else /*_Script_*/ {
      testing    = ScriptIsTesting();
      visualMode = testing;
      if (testing) {
         int hWndSettings  = GetDlgItem(GetTesterWindow(), ID_TESTER_SETTINGS);
         testerStopped = (                  GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_STARTSTOP  )) == "Start");
         testerPaused  = (!testerStopped && GetWindowText(GetDlgItem(hWndSettings, ID_TESTER_PAUSERESUME)) == ">>"   );
      }
      else {
         testerStopped = false;                                      // wir sind nicht im Tester
         testerPaused  = false;
      }
   }

   int hWnd = WindowHandle(Symbol(), NULL);
   if (hWnd == 0)
      return(catch("Chart.SendTick(1) ->WindowHandle() = "+ hWnd, ERR_RUNTIME_ERROR));

   if (!testing) {
      if (!PostMessageA(hWnd, WM_MT4(), MT4_TICK, 0))
         return(catch("Chart.SendTick(2) ->user32::PostMessageA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));
   }
   else if (visualMode && !testerStopped && testerPaused) {
      SendMessageA(hWnd, WM_COMMAND, ID_TESTER_TICK, 0);
   }

   if (sound)
      PlaySound("tick1.wav");

   return(NO_ERROR);
}


/**
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   return(catch("onDeinit()"));

   Tester.Pause();
   Tester.IsPaused();
   Chart.SendTick();
}
