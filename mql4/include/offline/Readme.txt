
=================================================================================================================================
 Allgemeine Offline-Chart-Infos  
=================================================================================================================================

 � Neue MetaTrader-Versionen setzen die Variablen Digits und Point in Offline-Charts permanent falsch, bei alten Versionen reicht 
   es, das Charttemplate neuzuladen.

 � EA's f�hren die start()-Funktion bei k�nstlichen Ticks in Offline- (und in regul�ren) Charts nur mit Serververbindung, 
   Indikatoren in jedem Fall auch ohne Serververbindung aus.

 � Charting synthetischer Instrumente:
   - Um die Chartperiode dynamisch umschalten zu k�nnen, mu� das Instrument in "symbols.raw" eingetragen und eine Verbindung zum 
     Tradeserver verhindert werden. F�r das Terminal sieht das synthetische Instrument dann wie ein regul�res Instrument aus.

   - Bei Verbindung zum Tradeserver wird eine modifizierte Datei "symbols.raw" �berschrieben und dort eingetragene synthetische
     Instrumente gehen verloren.

   - Ohne Serververbindung mu� eine modifizierte Datei "symbols.raw" nicht zus�tzlich gesch�tzt werden.

   - Dynamische Charts k�nnen wie Offline-Charts durch das Command ID_CHART_REFRESH aktualisiert werden, wenn der erste Chart 
     dieses Instruments dieser Periode w�hrend der gesamten Terminal-Laufzeit ein Offline-Chart war. Dies wird vom Offline-
     QuoteServer genutzt, um dynamische Charts synthetischer Instrumente wie regul�re Offline-Charts zu aktualisieren.


 TODO: Das Wechseln der SuperBar-Timeframes funktioniert in Offline-Charts noch nicht.



=================================================================================================================================
 Automatische Aktualisierung von Offline-Charts 
=================================================================================================================================

  Subscription-Proze�: Informationsflu� zwischen QuoteServer und QuoteClient (Subscribern)
  ----------------------------------------------------------------------------------------
  Beliebige Clients (z.B. Charts in beliebigen Terminals) k�nnen sich per Subscription-Modell beim QuoteServer anmelden. Auch ein 
  weiterer, parallel laufender QuoteServer kann sich als Subscriber anmelden, um benachrichtigt zu werden, wenn der momentan  
  laufende QuoteServer herunterf�hrt oder offline geht. In diesem Fall kann der zus�tzliche QuoteServer den Subscription-Channel 
  des herunterfahrenden QuoteServers inkl. dort auflaufender Messages nahtlos �bernehmen und die Subscriber k�nnen sich sofort und 
  ohne Unterbrechung erneut anmelden. Aus Sicht des Subscribers erfolgt ein Resubscribe, ohne den Wechsel der QuoteServer-Instanz 
  zu bemerken.
  
  Subscription-Channel: "MetaTrader::QuoteServer::{Symbol}"             - ein Channel f�r jedes vom QuoteServer angebotene Symbol 
  Backchannel:          "MetaTrader::QuoteClient::{Symbol}::{UniqueId}" - ein Channel f�r jeden Subscriber


  TODO: MQL kann in deinit() einen UninitReason noch nicht eindeutig erkennen, sondern erst im folgenden init(). Daher ist es nicht 
        m�glich, externe Resourcen (z.B. ein QuickChannel-Handle) abh�ngig vom UninitReason korrekt zu speichern oder freizugeben. 
        Dies kann erst mit einer UninitReason-Erkennung via DLL zuverl�ssig erreicht werden. Externe Resourcen m�ssen daher bei jedem 
        deinit() freigegeben und ein komplettes Unsubscribe-Subscribe durchgef�hrt werden. 
       
        Wegen dieses unn�tigen Mehraufwandes wurde vorl�ufig die Best�tigung jeder einzelnen Message entfernt. Dementsprechend ist der 
        Subscriber statuslos.       


(1) QuoteClient des Charts meldet sich beim QuoteServer an
    � Subscription-Ausgangsstatus des QuoteClients: "offline"
    � QuoteClient als Sender auf Subscription-Channel registrieren
    � QuoteClient als Receiver auf Backchannel registrieren

    � Subscribe-Message schicken: >> "Subscribe|{HWND_CHART}|{BackChannelName}|{ChannelMsgId}"
      - Subscriptionstatus des QuoteClients: "connecting"

    � Online-Status des QuoteServers pr�fen: Test mit QC_ChannelHasReceiver("{SubscriptionChannel}")
      - QuoteServer online:  fortfahren        
      - QuoteServer offline: Subscriptionstatus des QuoteClients: "offline"     
        
    � auf Best�tigung warten:     << "{ChannelMsgId}|OK"
    � regelm��ig Online-Status des QuoteServers pr�fen (nur in DLL m�glich) 



(2) QuoteClient des Charts l�uft
    � im Backchannel eingehende Messages verarbeiten:
      - Messagebest�tigungen:                    << "{ChannelMsgId}|OK"
      - vom QuoteServer initiiertes Unsubscribe: << "QuoteServer|{HWND_CHART}|Unsubscribed|Shutdown"



(3) QuoteClient des Charts meldet sich beim QuoteServer ab
    � QuoteClient mu� als Sender auf Subscription-Channel registriert sein

    � Unsubscription
      - Unsubscribe-Message schicken: >> "Unsubscribe|{HWND_CHART}|{ChannelMsgId}"
      - Serverbest�tigung:            << "{ChannelMsgId}|OK"
      - Die Serverbest�tigung kann, mu� aber nicht abgewartet werden. Der Backchannel mu� also nicht zwangsl�ufig offen sein. 
        Die Best�tigung bedeutet f�r den QuoteClient nur, da� der QuoteServer tats�chlich aufgeh�rt hat, Updates zu schicken.    


(4) QuoteServer startet oder geht online
    � QuoteServer als Receiver auf "MetaTrader::QuoteServer::{Symbol}" registrieren (jeweils ein Channel je angebotenem Symbol)



(5) QuoteServer ist online bzw. l�uft
    � Preis-Updates an die jeweiligen Subscriber schicken (Command ID_CHART_REFRESH)

    � in den Subscription-Channels eingehende Messages verarbeiten:
      - einhehende Subscribes verarbeiten
        � Subscribe-Message parsen:                                    << "Subscribe|{HWND}|{BackChannelName}|{ChannelMsgId}"
        � ChartHandle HWND_CHART validieren
        � pr�fen, ob auf "{BackChannelName}" ein Receiver online ist: QC_ChannelHasReceiver() ?
          - nein: Abbruch
          - ja:   fortfahren
        � QuoteServer als Sender auf "{BackChannelName}" registrieren
        � Subscribe-Best�tigung auf "{BackChannelName}" verschicken:   >> "{ChannelMsgId}|OK"
        � Subscriber speichern        
      
      - eingehende Unsubscribes verarbeiten
        � Unsubscribe-Message parsen:                                  << "Unsubscribe|{HWND}|{ChannelMsgId}"
        � entsprechenden Subscriber ermitteln        
        � Unsubscribe-Best�tigung auf "{BackChannelName}" verschicken: >> "{ChannelMsgId}|OK"
        � Backchannel schlie�en
        � Subscriber l�schen        

    � regelm��ig pr�fen, ob die Subscriber noch online sind (PostMessage(), Fensterhandle, Back-Channel)



(6) QuoteServer endet oder geht offline
    � QuoteServer mu� als Receiver auf "MetaTrader::QuoteServer::{Symbol}" registriert sein (jeweils ein Channel je Symbol)
    � QuoteServer mu� als Sender auf allen Backchannels der Subscriber registriert sein

    � f�r jedes angebotene Symbol:
      - Channel "MetaTrader::QuoteServer::{Symbol}" verlassen

    � f�r jeden registrierten Subscriber:
      - pr�fen, ob der Subscriber noch online ist (Fensterhandle und Back-Channel)
        � nein: Abbruch
        � ja:   fortfahren
      - auf "{BackChannelName}" Ende der Subscription signalisieren: >> "QuoteServer|{HWND}|Unsubscribed"
      - auf "{BackChannelName}" Shutdown-Benachrichtigung schicken:  >> "QuoteServer|Shutdown"
      - eine Best�tigung durch den Subscriber ist nicht notwendig



 
