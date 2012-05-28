/**
 * SnowRoller Stop
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
            case STATUS_WAITING:
            case STATUS_PROGRESSING:
               if (StringGetChar(ids[i], 0)!='T' || ScriptIsTesting())  // solange es keine Testsequenz auﬂerhalb des Testers ist
                  break;
            default:
               ArraySpliceStrings(ids, i, 1);                           // nicht zu stoppende Sequenzen entfernen
               ArraySpliceInts(status, i, 1);
               sizeOfIds--;
         }
      }


      // (2) Best‰tigung einholen
      for (i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo() && !This.IsTesting(), "- Live Account -\n\n", "") +"Do you really want to stop sequence "+ ids[i] +"?", __NAME__, MB_ICONQUESTION|ifInt(sizeOfIds==1, MB_OKCANCEL, MB_YESNOCANCEL));
         if (button == IDCANCEL)
            break;
         if (button == IDNO)
            continue;


         // (3) Command setzen
         string label = StringConcatenate("SnowRoller.", ids[i], ".command");
         if (ObjectFind(label) != 0) {
            if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
               return(catch("onStart(1)"));
            ObjectSet(label, OBJPROP_TIMEFRAMES, EMPTY);                // hidden on all timeframes
         }
         ObjectSetText(label, "stop", 1);


         // (4) Tick senden
         SendTick(false);
         return(catch("onStart(2)"));                                   // regular exit
      }
   }

   if (!IsLastError()) {
      if (sizeOfIds == 0) {
         ForceSound("chord.wav");
         ForceMessageBox("No sequence to stop found.", __NAME__, MB_ICONEXCLAMATION|MB_OK);
      }
      catch("onStart(3)");
   }
   return(last_error);
}
