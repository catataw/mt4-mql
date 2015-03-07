/**
 * Entfernt je nach Terminalversion Suchbox und/oder MQL4/5-Community-Button aus der Toolbar.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>
#include <win32api.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   int hWnd     = GetApplicationWindow();        if (!hWnd    ) return(last_error);
   int hToolbar = GetDlgItem(hWnd, IDC_TOOLBAR); if (!hToolbar) return(catch("onStart(1)  Toolbar not found", ERR_RUNTIME_ERROR));


   // (1) Suchbox-Control suchen und entfernen (enth�lt Community-Button)
   int hSearchCtrl = GetDlgItem(hToolbar, IDC_TOOLBAR_SEARCHBOX);
   if (hSearchCtrl != 0) {
      if (!PostMessageA(hSearchCtrl, WM_CLOSE, 0, 0))                    return(catch("onStart(2)->PostMessageA()  failed", ERR_WIN32_ERROR));
      while (IsWindow(hSearchCtrl)) Sleep(100);
      if (!RedrawWindow(hToolbar, NULL, NULL, RDW_ERASE|RDW_INVALIDATE)) return(catch("onStart(3)->RedrawWindow()  failed", ERR_WIN32_ERROR));
   }


   // (2) ohne Suchbox eigenst�ndigen Community-Button suchen und entfernen
   if (!hSearchCtrl) {
      int hBtnCtrl = GetDlgItem(hToolbar, IDC_TOOLBAR_COMMUNITY_BUTTON);
      if (hBtnCtrl != 0)
         if (!PostMessageA(hBtnCtrl, WM_CLOSE, 0, 0))                    return(catch("onStart(4)->PostMessageA()  failed", ERR_WIN32_ERROR));
   }

   return(catch("onStart(5)"));
}
