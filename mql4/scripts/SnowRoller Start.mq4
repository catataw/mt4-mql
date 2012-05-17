/**
 * SnowRoller Resume
 */
#include <types.mqh>
#define     __TYPE__    T_SCRIPT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

#include <SnowRoller/define.mqh>
#include <SnowRoller/functions.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   string ids [];
   int  status[], sizeOfIds;

   // (1) aktive Sequenzen ermitteln
   if (GetActiveSequences(ids, status)) {
      sizeOfIds = ArraySize(ids);

      for (int i=sizeOfIds-1; i >= 0; i--) {
         switch (status[i]) {
            case STATUS_STOPPED:
               break;
            default:
               ArraySpliceString(ids, i, 1);                         // nicht zu startende entfernen
               ArraySpliceInt(status, i, 1);
               sizeOfIds--;
         }
      }

      // (2) Bestätigung einholen
      for (i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to resume sequence "+ ids[i] +"?", __NAME__, MB_ICONQUESTION | ifInt(sizeOfIds==1, MB_OKCANCEL, MB_YESNOCANCEL));
         if (button == IDCANCEL)
            break;
         if (button == IDNO)
            continue;

         // (3) Command setzen

         // (4) Tick senden
         return(catch("onStart(1)"));
      }
   }

   if (!IsLastError()) {
      if (sizeOfIds == 0) {
         ForceSound("chord.wav");
         ForceMessageBox("No sequence to resume found.", __NAME__, MB_ICONEXCLAMATION|MB_OK);
      }
      catch("onStart(2)");
   }
   return(last_error);
}
