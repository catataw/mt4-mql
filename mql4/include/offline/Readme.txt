
=================================================================================================================================
 Allgemein 
=================================================================================================================================

 � Neue MetaTrader-Versionen setzen die Variablen Digits und Point in Offline-Charts permanent falsch, bei alten Versionen reicht 
   es, das Charttemplate neuzuladen.

 � Charting synthetischer Instrumente:
   - Um die Chartperiode dynamisch umschalten zu k�nnen, mu� das Instrument in "symbols.raw" eingetragen und eine Verbindung zum 
     Trade-Server verhindert werden. F�r das Terminal sieht das synthetische Instrument dann wie ein regul�res Instrument aus.

   - Bei Verbindung zum Trade-Server wird eine modifizierte Datei "symbols.raw" �berschrieben und dort eingetragene synthetische
     Instrumente gehen verloren.

   - Ohne Serververbindung mu� eine modifizierte Datei "symbols.raw" nicht zus�tzlich gesch�tzt werden.

   - Dynamische Charts k�nnen wie Offline-Charts durch das Command ID_CHART_REFRESH aktualisiert werden, wenn der erste Chart 
     dieses Instruments und dieser Periode w�hrend der gesamten Terminal-Laufzeit ein Offline-Chart war. Dies wird vom Offline-
     QuotesProvider genutzt, um dynamische Charts synthetischer Instrumente wie regul�re Offline-Charts zu aktualisieren.


 TODO: Das Wechseln der SuperBar-Timeframes funktioniert in Offline-Charts noch nicht.



=================================================================================================================================
 Automatische Aktualisierung von Offline-Charts 
=================================================================================================================================

  Subscription-Proze�: Informationsflu� zwischen Quote-Provider und Subscribern
  -----------------------------------------------------------------------------
  Beliebige Clients (z.B. Charts in beliebigen Terminals) k�nnen sich per Subscription-Modell beim Quote-Provider anmelden.
  Auch ein weiterer, parallel laufender Quote-Provider kann sich als Subscriber anmelden, um benachrichtigt zu werden, wenn der 
  aktuelle Provider herunterf�hrt oder offline geht. In diesem Fall kann der zus�tzliche Provider den Subscription-Channel des 
  herunterfahrenden Providers inkl. dort auflaufender Messages nahtlos �bernehmen und die Subscriber k�nnen sich sofort und ohne 
  Unterbrechung erneut anmelden. Aus Sicht des Subscribers erfolgt ein Resubscribe, ohne den Wechsel der Quote-Provider-Instanz 
  zu bemerken.
  
  Subscription-Channel: "MetaTrader::QuoteServer::{Symbol}"             - ein Channel f�r jedes vom Provider angebotene Symbol 
  Back-Channel:         "MetaTrader::QuoteClient::{Symbol}::{UniqueId}" - ein Channel f�r jeden Subscriber


(1) Chart meldet sich beim Quote-Provider an
    � Subscription-Ausgangsstatus des Charts: "offline"
    � Chart als Sender auf Subscription-Channel registrieren
    � Chart als Receiver auf Back-Channel registrieren

    � Subscribe-Message schicken:       >> "Subscribe|{HWND_CHART}|{BackChannelName}"
      - Subscriptionstatus des Charts:  "connecting"

    � Online-Status des Providers pr�fen: Test mit QC_ChannelHasReceiver("{SubscriptionChannel}")
      - Provider online:  
        � auf Best�tigung warten:       << "Subscribe|{HWND_CHART}|{BackChannelName}|ACK" 

      - Provider offline:
        � Subscriptionstatus des Charts: "offline"     
        � auf Best�tigung warten 
        � regelm��ig Online-Status des Providers pr�fen (nur in DLL m�glich) 



(2) Chart meldet sich beim Quote-Provider ab
    � Unsubscription
      - ein aktiver Provider h�rt auf dem Channel "MetaTrader::QuoteServer::{Symbol}" (ist Receiver)
      - Test, ob Quote-Provider online ist: QC_ChannelHasReceiver() ?
        � nein: Abbruch (Quote-Provider offline, Abmeldung nicht notwendig)
        � ja:   fortfahren
      - Chart als Sender   auf "MetaTrader::QuoteServer::{Symbol}"             registrieren (Channel sollte bereits offen sein)
      - Chart als Receiver auf "MetaTrader::QuoteClient::{Symbol}::{UniqueId}" registrieren (Channel sollte bereits offen sein)
      - Unsubscribe-Message schicken:                   >> "Unsubscribe|{HWND_CHART}|{BackChannelName}"
      - Best�tigung braucht nicht abgewartet zu werden: << "Unsubscribe|{HWND_CHART}|ACK"



(3) Quote-Provider startet oder geht online
    � Provider als Receiver auf "MetaTrader::QuoteServer::{Symbol}" registrieren (jeweils ein Channel je Symbol)
    � pr�fen, ob in den Channels Subscribe-Messages von wartenden Clients existieren
      - nein: Abbruch
      - ja:   fortfahren
    � f�r jeden wartenden Client:
      - Subscribe-Message parsen:                              << "Subscribe|{HWND_CHART}|{BackChannelName}"
      - ChartHandle HWND_CHART validieren
      - pr�fen, ob auf "{BackChannelName}" ein Receiver online ist: QC_ChannelHasReceiver() ?
        � nein: Abbruch
        � ja:   fortfahren
      - Provider als Sender auf "{BackChannelName}" registrieren
      - Subscribe-Best�tigung auf "{BackChannelName}" schicken: >> "Subscribe|{HWND_CHART}|ACK"
    � bei neuem Tick Command ID_CHART_REFRESH an den jeweiligen Subscriber schicken
    � regelm��ig pr�fen, ob Subscriber noch online ist (PostMessage(), Fensterhandle oder Back-Channel)



(4) Quote-Provider endet oder geht offline
    � Provider mu� als Receiver auf "MetaTrader::QuoteServer::{Symbol}" registriert sein (jeweils ein Channel je Symbol)
    � Provider mu� als Sender auf allen BackChannels der Subscriber registriert sein

    � f�r jedes angebotene Symbol:
      - Messages im Channel "MetaTrader::QuoteServer::{Symbol}" verarbeiten

    � f�r jedes angebotene Symbol:
      - Channel "MetaTrader::QuoteServer::{Symbol}" verlassen

    � f�r jeden registrierten Subscriber:
      - pr�fen, ob der Subscriber noch online ist (Fensterhandle und Back-Channel)
        � nein: Abbruch
        � ja:   fortfahren
      - auf "{BackChannelName}" Ende der Subscription signalisieren: >> "QuoteServer|{Symbol}|SubscriptionCancelled"
      - auf "{BackChannelName}" Shutdown-Benachrichtigung schicken:  >> "QuoteServer|Shutdown"
      - es wird keine Best�tigung durch den Subscriber abgewartet



 