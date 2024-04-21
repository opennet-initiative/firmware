[TOC]

Firmware 0.5 {#firmware05}
============

Datenbank der Dienste {#services}
---------------------

Auf jedem AP wird eine Datenbank von Diensten gepflegt.

Die zwei typischen Quelle fuer diese Datenbank sind der olsrd-Nameservice (nur OLSR v1), sowie der http-basierte Download einer zentral gepflegten Liste.

Die Ergebnisse der Dienst-Suche werden im Dateisystem gespeichert. Langfristig unveraenderliche Attribute eines Dienstes (z.B. der Host und der Port) werden persistent gespeichert - die übrigen Informationen (z.B. die Routing-Entfernung) liegen lediglich im tmpfs und werden bei jedem Neustart erneut gesammelt.

Die Details zur Datenablage sind unter ``Datenspeicherung`` zu finden.

Die menschenfreundliche Zusammenfassung aller Dienst-Informationen ist recht übersichtlich:

    on-function print_services

Dienste werden durch einen eindeutigen Namen (zusammengesetzt aus URL, Schema, Hostname, Port, usw.) referenziert. Dieser eindeutige Namen wird von allen Dienst-relevanten Funktionen verwendet.


### Empfang von Dienst-Listen via olsr-Nameservice {#services-olsr-nameservices}

Die Dienste werden mittels eines olsrd-nameservice-Trigger-Skripts aktualisiert (`/etc/olsrd/nameservice.d/on_update_services`).
Dieses Trigger-Skript setzt eine Markierungsdatei, deren Existenz durch einen minütlichen cronjob geprüft wird. Sofern die Datei existiert, wird einmalig die Service-Aktualisierung durchgeführt.

Die Aktion des Trigger-Skripts lässt sich manuell auslösen:

    on-function update_olsr_services


### Abruf zentraler Dienst-Listen {#services-list-download}

Einige Dienste werden nicht via olsr-nameservice, sondern via HTTP-Request ermittelt.

Folgende URLs enthalten Dienste, die von APs verwendet werden:
* https://services.opennet-initiative.de/ugw-services.csv: Auflistung aller Gateway- und Mesh-Server
* https://services.opennet-initiative.de/user-services.csv: Auflistung von Nutzer-VPN-Tunnel-Server

Die Spalten werden durch Tabulatoren getrennt (keine Leerzeichen).

Die erste Spalte enthält den Dienst-Typ (z.B. "mesh", "dns" oder "gw"). Falls der Dienst-Type mit dem Präfix "proxy-" beginnt, gilt er als weiterleitungsfähig. Er soll also nicht direkt verwendet, sondern lediglich weitergeleitet werden.

Die zweite Spalte enthält das Dienst-Protokoll / die Anwendung (z.B. "openvpn").

Die dritte Spalte enthält den öffentlich erreichbaren DNS-Namen oder die IP des Hosts.

Die vierte Spalte enthält die Port-Nummer des Diensts.

Die fünfte Spalte enthält das Übertragungsprotokoll (udp/tcp - je nach Dienst).

Die sechste Spalte enthält die Priorität dieses Dienste-Anbieters (5 = üblich; kleinere Werte werden bevorzugt). Ungwöhnliche Dienste oder Dienste mit überraschenden Eigenschaften (z.B. Exit-Knoten im Ausland) sollten eine höhrere Zahl verwenden, damit sie nur durch bewusste Auswahl aktiviert werden können.

Die siebente und die folgenden Spalten können zusätliche Dienst-Informationen enthalten (z.B. "location").

Dabei wird die Priorität (1. Spalte des Ergebnis) für die Vorauswahl der automatisch zu nutzenden Anbietern beachtet.

Die ermittelten Dienst-Anbieter werden durch die Dienste-Verwaltung gespeichert. Darin werden alle für den Verbindungsaufbau notwendigen Daten abgelegt.


### Prioritisierung der Dienste {#service-priority}

Wenn mehrere Anbieter eines Dienstes zur Verfügung stehen, dann muss eine automatisierte Entscheidung getroffen werden, welcher davon zu verwenden ist. Derzeit stehen drei Methoden zur Verfügung, von denen eine über die Konfigurationseinstellung ``on-core.settings.service_sorting`` ausgewählt wird:

* etx: die Entfernung, so wie sie von ``olsrd`` als Routing-Metrik verwendet wird (dies ist die Standard-Sortierung)
* hop: die Anzahl der Routing-Hops
* manual: die Reihenfolge wird durch manuelle Anordnung festgelegt


DNS - Namensauflösung {#dns}
---------------------

Alle DNS-Server verteilen via olsrd-nameservice-Plugin einen Eintrag ähnlich dem folgenden:

    dns://192.168.0.247:53|udp|dns


### Konfiguration der DNS-Anbieter {#dns-server}

Die folgenden Voraussetzungen müssen von DNS-Servern im Opennet erfüllt werden:

1. der DNS-Port (üblicherweise UDP-Port 53) ist vom Opennet aus erreichbar
2. DNS-Abfragen werden nicht geloggt (Datensparsamkeit gegenüber den Nutzenden)
3. der lokale olsrd-Dienst verteilt via ``nameservice`` die URL des DNS-Servers


Der entsprechende ``nameservice``-Block in der ``olsrd.conf`` des DNS-Servers kann folgendermaßen aussehen:

    LoadPlugin "olsrd_nameservice.so.0.3"
    {
        PlParam "service" "dns://192.168.0.247:53|udp|dns"
    }

**Wichtig**: Die angegebene IP muss unbedingt auf einem der von olsr verwalteten Netzwerk-Interfaces konfiguriert sein. Andernfalls wird das ``nameservice``-Plugin stillschweigend die Verteilung unterlassen. In der ``/var/run/services_olsr`` auf dem Host ist sofort zu erkennen, ob der Dienst-Eintrag verteilt wird.


### Integration auf den APs {#dns-ap}

Bei jeder Änderung von empfangenen olsrd-Nameservice-Announcements wird das Skript ``/etc/olsrd/nameservice.d/on_update_services`` ausgeführt, welches die Ausführung der Funktion ``update_olsr_services`` für die nächste Minute vormerkt (``schedule_task``). Dies verhindert die mehrfach parallel Ausführung der olsr-Auswertung.

Die Funktion ``update_olsr_services`` überträgt alle Dienst-Informationen in die lokale Datenbank. Im Anschluss wird ``apply_changes on-core`` aufgerufen. Dies löst die eventuelle Aktualisierung der ``dnsmasq``-Nameserver-Datei (``/var/run/dnsmasq.servers``) basierend auf der Dienstliste aus. Im Fall von Änderungen wird ein Prozess-Signal an dnsmasq geschickt, um das erneute Lesen der DNS-Server-Liste auszulösen.

In diesem Verlauf wird auch sichergestellt, dass die uci-Variable ``dhcp.@dnsmasq[0].serversfile`` gesetzt ist. Falls dies nicht der Fall ist, wird die Datei ``/var/run/dnsmasq.servers`` eingetragen.
Abschließend wird dem ``dnsmasq``-Prozess ein HUP-Signal gesendet, um ein erneutes Einlesen der Konfigurationsdateien auszulösen.

Folgende Voraussetzungen müssen gegeben sein:

* ``dnsmasq`` läuft
* das Plugin ``nameservice`` ist aktiviert


### DNS für APs mit einem Nutzer-Tunnel

Um die Privatsphäre der Nutzenden hinter einem VPN-Nutzertunnel zu schützen, werden DNS-Anfragen ausschließlich an die vom OpenVPN-Server announcierten DNS-Server gerichtet. Typischerweise sollte der OpenVPN-Server also nur seine eigene Tunnel-IP angeben, um sicherzustellen, dass DNS-Anfragen immer durch den Tunnel gesandt werden.

Die Umsetzung dieser DNS-Ausnahmesituation (im Vergleich zur obigen Darstellung) ist folgende:

* beim Aufbau eines Nutzertunnels werden im "up"-Hook-Skript die Umgebungsvariablen "foreign_option_XXX" geprüft
* alle Vorkommen von "dhcp-option DNS ..." werden gelesen und die angegebenes IP zeilenweise getrennt in eine temporäre Datei geschrieben
* anschließend wird von dem Hook-Skript die Neu-Erstellung der dnsmasq-Servers-Datei ausgelöst
* bei dieser Neuerstellung wird geprüft, ob aktuell ein Tunnel aktiv ist - daraufhin werden die zwischengespeicherten IPs als Nameserver verwendet und alle anderweitig announcierten DNS-Server werden ignoriert
* beim Abbau eines Nutzertunnels wird ebenfalls die Neuerstellung der DNS-Servers-Datei ausgelöst


NTP - Zeitsynchronisation {#ntp}
-------------------------

Alle NTP-Server verteilen via olsrd-nameservice-Plugin einen Eintrag ähnlich dem folgenden:

    ntp://192.168.0.247:123|udp|ntp


### Konfiguration der NTP-Anbieter {#ntp-server}

//analog zur Konfiguration der DNS-Anbieter//


### Integration auf den APs {#ntp-ap}

Das Skript ``/etc/olsrd/nameservice.d/on_update_services`` wird bei jeder Änderung der olsrd-Nameservice-Announcements aufgerufen und überträgt alle Dienst-Informationen in die lokale Datenbank. Im Anschluss wird ``apply_changes on-core`` aufgerufen. Dies löst die Aktualisierung der NTP-Server-Liste in der uci-Konfiguration (``system.ntp.server``) aus.

Im Falle von Änderungen der Server-Liste wird diese in die uci-Variable ``system.ntp.server`` übertragen. Anschließend wird der ntp-Dienst neugestartet.


Gateway-Auswahl {#mig}
---------------

### Gateway-Liste {#mig-list}

Das Skript ``/etc/olsrd/nameservice.d/on_update_services`` wird bei jeder Änderung der olsrd-Nameservice-Announcements aufgerufen und überträgt alle Dienst-Informationen in die lokale Datenbank.
Im Fünf-Minuten-Takt (kurz nach dem Booten: sogar minütlich) wird via cronjob die Funktion ``update_mig_connection_status`` ausgeführt. Diese löst folgende Aktionen aus:

* Durchlaufen aller Gateways bis ein Test erfolgreich abgeschlossen wurde ("frische" Tests werden nicht wiederholt)
* Falls kein Test erfolgreich durchgeführt wurde (z.B. weil alle Zeitstempel recht frisch sind), dann wird der älteste als defekt markierte Gateway getestet. Dies minimiert die Ausfallzeit nach einer globalen Nicht-Erreichbarkeit aller Gateways.
* Ermittlung des aktuell besten Gateways und seine Aktivierung, falls er seit mehreren Minuten besser ist oder falls aktuell kein Gateway konfiguriert ist

Diese Funktion (``update_mig_connection_status``) kann außerdem durch das *down*-Ereignis des VPN-Nutzertunnels ausgelöst. Sollte also der 60-Sekunden-Pingtest von OpenVPN scheitern (und somit die Verbindung trennen), dann wird innerhalb der nächsten 60 Sekunden der nächste passende Gateway ausgewählt.


### Gateway-Auswahl {#mig-selection}

 * Sortieren nach Entfernung, Hop-Count oder manuell


### Gateway-Wechsel {#mig-switch}

Falls der cronjob feststellt, dass ein besserer Gateway als der aktuell verwendete vorhanden ist, dann schreibt er das Attribute ``switch_candidate_timestamp`` in diesen neuen Dienst. Sobald dieser Zeitstempel im Verlaufe nachfolgender cronjob-Läufe älter als 15 Minuten ist, wird der neue Gateway via ``select_mig_connection`` aktiviert und eine Verbindung aufgebaut.


### Gateway-Verbindungsabbruch {#mig-disconnect}

Sollte die Verbindung zum aktuellen Gateway abreissen, muss der Gateway als unbrauchbar markiert werden und ein Wechsel zu einem anderen Gateway ist sinnvoll. Dies wird folgendermaßen erreicht:

* Jeder Client erhält vom Server via ``keepalive`` die Regeln ``ping 10`` und ``pin-restart 120``. Somit wird nach ca. zwei Minuten Ausfall ein Neustart der Verbindung von Client-Seite ausgeführt.
* Der Verbindungsneustart führt aufgrund der fehlenden ``persist-tun``-Option zur Ausführung des ``down``-Skripts, In diesem Skript wird der Status der aktuellen OpenVPN-Verbindung als 'n' gesetzt. Somit wird bei der nächsten Prüfung eines Gateway-Wechsels ohne Verzögerung ein alternativer Gateway gewählt. Zusätzlich wird für den Beginn der nächsten Minuten die Ausführung der Funktion ``update_mig_connection_status`` (siehe oben) vorgemerkt. Innerhalb von einer Minute wird also ein alternative Gateway ausgewählt.
* Die Einstellung ``explicit-exit-notify`` muss abgeschaltet sein, da andernfalls der Grund des Endes der Verbindung im ``down``-Skript nicht erkennbar ist (die Status-Variable ``signal`` wird von ``explicit-exit-notify`` überschrieben).


### Datenspeicherung {#mig-storage}

Für jeden Gateway werden dauerhafte und wechselhafte Eigenschaften gespeichert.

Die folgenden Attribute sind persistent (siehe ``on-core/files/usr/lib/opennet/services.sh``):

* service
* scheme
* host
* port
* protocol
* path
* uci_dependency
* file_dependency
* rank
* offset

Alle übrigen Attribute unterliegen lediglich der volatilen Speicherung.

Die persistenten Informationen liegen unter ``/etc/on-services.d``.

Die volatilen Informationen liegen unter ``/tmp/on-services-volatile.d``.


### Debugging der initialen Erstellung von UGW VPN Tunnel

Wenn ein neues Gerät gebootet wird, möchte man eventuell den Prozess bis zum Aufbauen des ersten UGW VPN Tunnels beschleunigen, da es sonst bis zu 20min dauert. Hierfür können folgende Schritte vorgenommen werden.

Schritt 1: Für welche UGW Server liegen gerade Informationen zum Verbindung vor? Beispiel:

    $ on-function get_services "mesh"
    mesh_openvpn_erina_opennet_initiative_de_1602_udp
    mesh_openvpn_subaru_opennet_initiative_de_1602_udp
    mesh_openvpn_megumi_opennet_initiative_de_1602_udp

Schritt 2: Die Funktion `verify_mesh_gateways()` prüft regelmäßig, ob diese Server alle Voraussetzungen (`wan_status`,`mtu`, ...) erfüllen und ruft selbst `is_mesh_gateway_usable()` auf. Also können wir den Prozess beschleunigen, indem wir für die Server folgendes aufrufen:
```
$ on-function is_mesh_gateway_usable mesh_openvpn_erina_opennet_initiative_de_1602_udp
```
Das Ergebnis der Prüfung ist in `/etc/on-services.d/mesh_openvpn_SERVERNAME` zu finden. Dort muss bspw auch `mtu_status true` am Ende stehen.

Schritt 3: Die Funktion `sync_mesh_openvpn_connection_processes()` erstellt eine OpenVPN Konfigurationsdatei, z.B. `/tmp/etc/openvpn/mesh_openvpn_erina_opennet_initiative_de_1602_udp.conf` und setzt in uci bspw. den Wert:
    openvpn.mesh_openvpn_erina_opennet_initiative_de_1602_udp.enabled='1'
Diesen Schritt können wir durch das manuelle Aufrufen von `sync_mesh_openvpn_connection_processes()` beschleunigt starten.


Internet-Freigabe (Usergateways) {#ugw}
--------------------------------

Internet-Spender betreiben APs, die im Wesentlichen die beiden folgenden Aufgaben erfüllen:

* eine Routing-Verbindung der lokalen Wolke mit der mesh-Wolke herstellen
* relevante Dienste (z.B. VPN-Verbindungen zu Exit-Knoten) weiterleiten

Die mesh-Verbindung wird mittels einer oder mehrerer openvpn-Verbindungen zu verschiedenen Mesh-Gateways aufgebaut.
Die Dienst-Durchleitung erfolgt mittel Portweiterleitungen verbunden mit olsrd-nameservice-Announcements.


### Datenspeicherung {#ugw-storage}

Für jeden externen Gateway werden dauerhafte und wechselhafte Eigenschaften gespeichert.

Die Eigenschaften von Gateway-Diensten werden durch die Dienstverwaltung gespeichert. Neben den für alle Dienste persistenten Informationen werden die folgenden UGW-spezifischen Informationen gespeichert:

* template - die zu verwendende Konfigurationsvorlage (z.B. /usr/share/opennet/ugw-openvpn-udp.template)
* age - Alter des Eintrags (TODO: durch "last_seen" ersetzen)
* details - eventuelle Zusatzinformationen, die aus einem olsrd-nameservice-Announcement entnommen wurden (z.B. Bandbreite)
* download - letzte ermittelte Download-Bandbreite (kBytes/s)
* mtu - Status des MTU-Test ("ok" oder "error")
* mtu_msg - vollständige Status-Ausgabe von openvpn infolge des MTU-Tests
* mtu_out_wanted - Startwert für die MTU-Prüfung (ausgehend)
* mtu_out_real - Resultat der MTU-Prüfung (ausgehend)
* mtu_in_wanted - Startwert für die MTU-Prüfung (eingehend)
* mtu_in_real - Resultat der MTU-Prüfung (eingehend)
* mtu_time - Zeitstempel (epoch) des letzten MTU-Tests
* ping - Ping-Laufzeit zum UGW-Server
* speed_time - Zeitstempel (epoch) des letzten UGW-Tests
* speed_time_prev - Zeitstempel (epoch) der anzeigt, seit wann die aktuelle Geschwindigkeitsmessung grob konstant blieb
* status - Zusammenfassung: Gateway ist erreichbar ("ok" oder "error")
* upload - letzte ermittelte Upload-Bandbreite (kBytes/s)
* wan - Status des WAN-Tests ("ok" oder "error")


### Geschwindigkeitstests {#ugw-speed}

Zu allen UGWs wird in der UGW-Übersicht eine Abschätzung der Upload- und Download-Bandbreite angezeigt.
Diese wird durch den Download von der URL http://UGW_HOSTNAME/.big und den Upload via netcat zum Dienst "discard" (Port 9) auf dem UGW-Host ermittelt.

Die Geschwindigkeiten werden nach jeder Messung mit den vorherigen Werten gemittelt gespeichert. Änderungen setzen sich also nur langsam durch.

Diese Prüfung wird im Tagestakt innerhalb der ugw-Funktion ``update_public_gateway_speed_estimation`` durchgeführt.

Konfiguration des UGW-Servers:

* Download: Bereitstellung einer beliebigen Datei (> 100 MByte), die unter der URL http://UGW_HOST/.big erreichbar ist
* Upload: Aktivierung des ``discard``-Diensts via ``inetd``


### Liste der Gegenstellen {#ugw-server-list}

Die UGW-Server bieten üblicherweise zwei Dienste an:

* Zugang zum mesh-Netzwerk
* Zugang zum Internet aus dem mesh-Netzwerk heraus

Beide Dienste sind über ihre öffentlichen IPs erreichbar. Daher ist eine Announcierung via olsrd-nameservice nicht umsetzbar.
Diese werden daher von einer zentralen Stelle via http heruntergeladen (siehe @ref services-list-download).

### Dienst-Weiterleitung: Service-Relay {#service-relay}

Jeder weiterzuleitende Dienst stellt eine Belastung für die Internet-Spender dar. Daher dürften diese Announcierungen nicht via olsrd erfolgen, um eine unerwünschte Nutzung der Internetfreigabe durch triviale olsr-Announcements zu verhindern.

Stattdesen erfolgt die Announcierung mittels der unter administrativer Kontrolle stehenden Opennet-Domain in Form einer csv-Datei, die via HTTP von einem Opennet-Server bereitgestellt wird (@ref ugw-server-list).

Es werden nur diejenigen Dienste weitergereicht und announciert, die den folgenden Bedingungen genügen:

* die Route zum Ziel-Host verläuft über das WAN-Interface
* die Quelle (*source*) des Dienstes ist *manual* (selbstverwaltet) oder *zentrale-csv* (durch den Verein verwaltet)


### Kombinierter Betrieb mit Nutzer-Tunnel {#ugw-nutzer-kombi}

Es ist wünschenswert, dass auf einem Gerät, welches als Internet-Spender agiert, auch ein Nutzer-Tunnel aktiviert werden kann. Dieses Feature führt jedoch zu einer sehr komplexen Konfiguration um zu verhindern, dass Pakete nicht im "falschen" Tunnel weitergeleitet werden.

Allgemein wurde diese Funktion während der Umstellung von iptables auf nftables ausgebaut. Im einem speziellen Fall, wird dieses Feature jedoch noch benötigt. Hier handelt es sich um Szenarien, wo ein Standort einen Internetanschluss hat (hier wird UGW Funktion benötigt) und am gleichen Standort der Internetverkehr der Nutzenden über Opennet geleitet werden soll. In diesem Szenario gibt es aber explizit keine weiteren Opennet Geräte an diesem Standort.

Im obigen Szenarion kann das UGW+Nutzer-Tunnel Feature wie folgt aktiviert werden:
* zuerst das Modul für den Nutzer-Tunnel aktivieren (z.B. über Webinterface)
* jetzt das Modul für den UGW-Tunnel über die Konsole/SSH installieren: `opkg-oni install on-usergw`
* nun kann wie gewohnt über das Webinterface die Konfiguration der Zertifikate für beiden Tunnel vorgenommen werden

### Routing - Offene Zugangspunkte / Captive Portal {#captive}

Offene Zugangspunkte stellen ihrer Umgebung Zugang zum Internet zur Verfügung. Verkehr wird dabei erst nach dem ersten Aufbau einer http-Verbindung durchgelassen. Dies ermöglicht uns die einmalige Einblendung einer Portal-Webseite.

Jeder offene Zugangspunkt trägt ein VPN-Zertifikat, mittels dessen er eine Verbindung zum Internet aufbaut.

Verkehr aus dem offenen Interface wird ausschließlich in das VPN-Tunnel-Interface geroutet. Verkehr in das Opennet-Mesh wird blockiert.

Die Funktionalität wird mittels des Pakets *on-captive-portal* bereitgestellt.


### Konfiguration des AP

1. VPN-Nutzertunnel einrichten
2. ein physisches Interface der *on_free*-Zone zuordnen (typischerweise ein WLAN mit der SSID *join.opennet-initiative.de*)


### Ablauf

Der hotplug-Trigger */etc/hotplug.d/iface/on-captive-portal-hotplug.sh* reagiert auf die folgenden Ereignisse:

* Aktivierung oder Deaktivierung des VPN-Tunnel-Interface: die Funktion *sync_captive_portal_state_with_mig_connections* sorgt für eine entsprechende Statusänderung des *on_free*-Interface
* Aktivierung oder Deaktivierung des *on_free*-Interface: *nodogsplash* wird via *reload* zum Starten oder Stoppen veranlasst

Somit folgt die offene Netzwerk-Schnittstelle dem Status des VPN-Tunnels: bei abgeschaltetem Tunnel-Interface ist das offene Netzwerk-Interface nicht sichtbar.


### nodogsplash-Konfiguration

Die leichtgewichtige captive-portal-Software *nodogsplash* wird verwendet. Sie erfüllt folgende Aufgaben:

* Hinzufügen und Entfernen von mac-basierten Firewall-Forward-Regeln abhängig von der Authentifikation
* die Authentifikation besteht lediglich aus der einmaligen Auslieferung einer Portal-Webseite als Antwort auf die erste vom Client versandte http-Anfrage
* alle externen Dienste sind zugelassen - es findet keine Portfilterung o.ä. statt

### Firewall-Konfiguration

*nodogsplash* fügt eine Regel zu Beginn der folgenden iptables-Chains ein:

* filter: INPUT und FORWARD
* mangle: PREROUTING und POSTROUTING
* nat: PREROUTING

Diese Regel verweist jeweils auf die passende iptables-Chain, die von *nodogsplash* verwaltet wird. Damit die obigen Regeln bei jeder Neukonfiguration der openwrt-Firewall vorhanden sind, wird bei jedem Reload der Firewall-Konfiguration *nodogsplash* neugestartet (siehe */usr/lib/opennet/events/on-captive-portal-firewall-reload.sh*). Die Integration dieses Skripts in die openwrt-Firewall-Konfiguration erfolgt mit Hilfe der Funktion *configure_captive_portal_firewall_script* im Rahmen der uci-defaults-Initialisierung. Bei diesem Vorgang gehen bestehende Client-Authentifikationen verloren - da die Authentifikation aber sehr schmerzfrei ist, dürfte dieses seltene Ereignis kein Problem darstellen.

Falls die *nodogsplash*-Firewall-Regeln fehlen, dann ist ein direkter Zugang zum VPN-Tunnel möglich (ohne Anzeige der Portal-Seite). Dies ist unerwünscht, aber nicht kritisch.

Der Zugang ins Mesh-Netz ist für Clients aufgrund der Firewall-Policy (unabhängig von *nodogsplash*) nicht zulässig.

### Roaming

Im Unterschied zur wifidog-basierten Implementierung (bis v0.4-5) ist die nahtlose Übergabe eines Clients an einen anderen offenen Zugangspunkt nicht möglich, da die DHCP-Leases und die Authentifikationszustände nur lokal am AP der Anmeldung vorliegen. Bei einem Netzwechsel wird also erneut die Portal-Seite präsentiert.

### Monitoring

Das *on-captive-portal*-Paket hängt von *muninlite* ab. Aktuell sind die Installationen offener Zugangspunkte typischerweise keine privaten APs sondern werden vom Verein betrieben - daher dürfte sich aus der statistischen Erfassung (gesamter Netzwerkvehr und Anzahl der Clients am Zugangspunkt im Zeitverlauf) kein Datenschutzproblem ergeben. Der muninlite-Dienst kann bei Bedarf abgeschaltet werden.

Die Speicherung und Visualisierung der munin-Daten erfolgt auf einem separaten munin-Server (z.B. *yurika*).

### Debugging

Auf dem AP sind folgende Aktionen bei der Fehlersuche eventuell hilfreich:

* Verfügbarkeit des Internet-Tunnels auf dem AP prüfen (dieser wird von den Clients des Zugangspunkts verwendet)
* `ndsctl status`: Anzeige des *nodogsplash*-Status (Konfiguration, Clients, Statistik)
* `on-function get_devices_of_interface on_free`: Auflistung der Netzwerkschnittstellen, die der Zone *on_free* zugeordnet sind
* `sync_captive_portal_state_with_mig_connections`: zwangsweise Angleichung des Netzwerk-Interface-Zustands (up/down) für *on_free* an die VPN-Tunnel-Schnittstelle (anschließend sollten beide aktiv oder beide inaktiv sein)
* `iptables -L | grep nds`: Vorhandensein von *nodogsplash*-Firewall-Regeln prüfen (keine Regeln -> freier Zugang ohne Portalseite)


Datensammlung: ondataservice {#ondataservice}
----------------------------

Das //ondataservice//-Plugin verteilt via //olsrd// detaillierte Informationen über den AP im Netz.


### Konfiguration auf dem AP

Das Initialisierungsskript /etc/uci-defaults/on-olsr-setup wird bei der Erstinstallation oder beim Firmware-Upgrade ausgeführt.
Es aktiviert da ondataservice-Plugin.


### Debugging

Das Plugin versendet standardmäßig im 3-Stunden-Takt olsr-Message-Pakete (Message-ID=222). Diese lassen sich auf dem AP mit tcpdump beobachten:

  tcpdump -vvvlnpi wlan0 port 698 | grep -A 5 "(0xde)"

Zur detaillierten Beobachtung kann es hilfreich sein, den Versand-Intervall (kurzzeitig) zu reduzieren (siehe *interval* in der *ondataservice_light*-Konfiguration in */etc/config/olsrd*).

Im [https://wiki.opennet-initiative.de/wiki/Firmware_Status](Wiki) findest du im Verlauf des nächstes Tages deinen AP aufgeführt. Dort findest du auch APs mit alter Firmware, sofern sie von der Kompatibilitätsschnittstelle unseres Datensammlers *geronimo* erfasst werden.


Erstkonfiguration {#initial-installation}
-----------------

Nach einer frischen Installation, sowie im Anschluss an ein Firmware-Upgrade wird eine Reihe von Skripten zur Initialisierung ausgeführt.
Openwrt stellt hierfür den //uci-defaults//-Mechanismus bereit:

  http://wiki.openwrt.org/doc/uci#defaults

Für alle Aktivitäten, die nach der Installation oder einem Upgrade notwendig sind, existieren in den Opennet-Paketen Dateien unterhalb von ``/usr/lib/opennet/init/``.
Diese Skripte werden als Symlink unter ``/etc/uci-defaults/`` bereitgestellt.
Nach dem Booten prüft ein openwrt-init-Skript, ob sich Dateien unterhalb von ``/etc/uci-defaults/`` befindet.
Jede aufgefundene Datei wird ausgeführt und bei Erfolg anschließend gelöscht.

Die Existenz einer Datei in diesem Verzeichnis deutet also auf ein Konfigurationsproblem hin, das gelöst werden sollte.


### Standard-IP setzen {#initial-ip}

Das Skript ``/etc/uci-defaults/on-configure-network`` prüft, ob der uci-Wert ``on-core.settings.default_ip_configured`` gesetzt ist.
Sollte dies nicht der Fall sein, dann wird die IP-Adresse aus der //on-core//-Defaults-Datei ausgelesen und konfiguriert.
Anschließend wird das obige uci-Flag gesetzt, um eine erneute Konfiguration anch einem Update zu verhindern.


### Paket-Quellen (opkg) {#opkg-repositories}

Die Firmware wird mit einer Original-openwrt-Repository-Datei (*/etc/opkg.conf*) erstellt.
Opennet stellt ein eigenes Repository zur Verfügung. Packeten aus diesem Repository können auf folgende Arten installiert werden:

* *opkg-oni.sh* (kleines Wrapper Script; Nutzung analog zu opkg)
* *on-function install_from_opennet_repository $PACKET*

Details zu diesen Funktionen kann man in */usr/lib/opennet/modules.sh* finden.


Bootvorgang {#booting}
-----------

Am Ende des Boot-Vorgangs werden alle Skripte, die sich im Verzeichnis */usr/lib/opennet/boot/* befinden, für die Ausführung beim nächsten minütlichen cron-Job angemeldet (siehe *schedule_task*). Einige dieser Skripte sollen nicht direkt nach dem Booten, sondern etwas verzögert gestartet werden. Diese Skripte sorgen ebenfalls durch *schedule_task* dafür, dass sie erneut ausgeführt werden, solange ihre Zeit noch nicht gekommen ist.


Hook-Skripte für Konfigurationsänderungen {#hooks}
-----------------------------------------

Die verschiedenen on-Pakete legen ausführbare Skripte im Verzeichnis */usr/lib/opennet/hooks.d/* ab. Diese Skripte werden ausgeführt, wenn Opennet-Skripte Änderungen an der Konfiguration vornehmen. Diese Änderungen werden via *apply_changes FOO* signalisiert. Der *apply_changes*-Funktion wird ein Paramter übergeben. Dieser ist entweder der Name einer uci-Sektion (z.B. *network*, *dhcp*, ...) oder eines Opennet-Pakets (*on-core*, *on-openvpn*, *on-usergw*, *on-monitoring*, *on-captive-portal*). Dieser Paramter wird als einziger Parameter beim Aufruf jedes einzelnen Hook-Skripts übergeben.

Die Hook-Skripte bestehen typischerweise aus einer einfachen case-Struktur.


Dauerhaftes Ereignisprotokoll {#bootlog}
-----------------------------

Relevante Vorgänge (Booten, OLSR-Neustarts) werden im Ereignislog (/etc/banner) festgehalten.

Um den korrekten Zeitstempel für das Boot-Ereignis sicherzustellen prüft das Skript ../packages/on-core/files/etc/cron.minutely/on_log_restart_timestamp zuerst, ob es eine Verbindung mit NTP-Servern (siehe @ref ntp) aufbauen kann. Bei Erfolg wird eine Datei erzeugt (*/var/run/on_boot_time_logged*). Die Existenz dieser Datei sorgt bei allen weiteren Ausführungen für ein sofortiges Ende des Skripts.


SSL-Zertifikate {#ssl-certs}
---------------

### CA-Verwaltung {#ssl-ca}

Die Opennet-CA-Zertifikate liegen im Verzeichnis */etc/ssl/certs/opennet-initiative.de*. Dies ist ein Unterverzeichnis des allgemein üblichen */etc/ssl/certs*-Verzeichnis. Die Separierung ermöglicht es bestimmten Anwendungen, ausschließlich Opennet-betriebenen Gegenstellen zu vertrauen (also beispielsweise nicht von der Telekom oder anderen verbreiteten CAs signierten Zertifikaten).

Alle Opennet-CA-Zertifikate liegen als einzelne Datei mit selbsterklärendem Dateinamen in dem obigen Verzeichnis. Die Dateinamen entsprechen dem Muster des CA-Bundles (siehe https://ca.opennet-initiative.de/ca.html) zuzüglich einer angehängten Jahreszahl der Erstellung.

Beim Bauen der Opennet-Pakete werden zusätzlich zu den Zertifikatsdatein in demselben Verzeichnis Symlinks erzeugt, die die effiziente Verfolgung von Vertrauensketten ermöglichen:

  c_rehash /etc/ssl/certs/opennet-initiative.de

Somit entspricht das Verzeichnis den üblichen Konventionen, die von SSL-tauglichen Clients verwendet werden (typischerweise: *capath*-Parameter). OpenVPN ist bei Verwendung des *capath*-Parameters darauf angewiesen, dass aktuell gültige CRLs für alle notwendigen Zertifikate vorliegen. Andernfalls werden die dazugehörigen Zertifikate ignoriert und die Verbindung zur Gegenstelle abgelehnt.

### Verwendung {#ssl-usage}

#### OpenVPN-Verbindungen (Nutzer, UGW, Test)

Die OpenVPN-Clients auf den APs verwenden ein von der User-CA (bzw. von der UGW-CA) unterschriebenes Zertifikat. Die Clients nutzen die folgenden ssl-relevanten Optionen:

  ca /etc/ssl/certs/opennet-initiative.de/opennet-server_bundle.pem
  ns-cert-type server

Es werden also alle Opennet-Server-Zertifikate akzeptiert, die von der Server-CA (oder der älteren root-CA) unterschrieben wurden.

@todo: Kann dies eventuell zu Problemen führen, falls wir mit unserer CA Server-Zertifikate für Dienste ausstellen, die von Nutzern und nicht von uns betrieben werden?

#### CSR-Upload

Zur vereinfachten Übermittlung der Zertifikatsanfragen von Nutzern überträgt die AP-Firmware via curl das CSR zu https://ca.opennet-initiative.de/.

### Aktualisierung {#ssl-update}

Seit Version 0.5.2 sind alle CA-Zertifikate in dem separaten Paket *on-certificates* zusammengefasst. Teil dieses Pakets ist außerdem ein Skript, das für die tägliche Aktualisierung dieses Pakets sorgt. Diese häufige Aktualisierung ist erforderlich, da andernfalls die Widerrufslisten (CRL) veralten und die dazugehörigen CA-Zertifikate nicht mehr verwendbar sind (im Falle des *capath*-Modus).

Dieses Skript wird zu den folgenden Zeitpunkten ausgeführt:

* einmal täglich (daily cronjob)
* stündlich innerhalb der ersten 120 Minuten nach dem Booten

Der stündliche cronjob, der nur kurz nach dem Booten wirksam ist, stellt sicher, dass unregelmäßig angeschaltete (bzw. verbundene) APs eine gute Chance haben, auch innerhalb einer kurzen Laufzeit ihre Zertifikate zu aktualisieren. Sollte dies mehr als 30 Tage lang nicht gelingen, dann verzögert sich anschließend die VPN-Verbindung, bis eine Zertifikatsaktualisierung erfolgreich abgeschlossen wird.

Die Aktualisierung wird über den opennet-internen Domainnamen (*downloads.on*), sowie den öffentlich nutzbaren Namen (*downloads.opennet-initiative.de*) versucht. Dies ermöglicht sowohl den direkten Teilnehmern des Mesh-Netzes, als auch den UGW-Hosts die Durchführung der CA-Aktualisierung.

Bei der Installation neuer Versionen des Opennet-Zertifikat-Pakets werden von *opkg* leider keine Signaturen und auch keine https-Verbindungen unterstützt. Somit ist auf diesem Weg das Unterschieben eines manipulierten CA-Zertifikats durch einen Dritten möglich.


Firewall-Regeln {#firewall}
---------------

Das *on-core*-Paket fügt bei der Erstinitialisierung einen Eintrag zur Firewall-Konfiguration hinzu, der dafür sorgt, dass bei jedem Reload der Firewall-Konfiguration alle Skripte im Verzeichnis ``/etc/on-firewall.d/`` ausgeführt werden.

Skripte die sich in diesem Verzeichnis befinden, sollten auf eine idempotente Ausführung achten: sie dürfen also nicht die Löchung aller zuvor erzeugten Regeln voraussetzen, sondern müssen selbst dafür sorgen (falls erforderlich).

Ein typisches Ablauf-Schema solcher Skripte ist:

1. eine separate Chain anlegen (Fehler bei Vorhandensein ignorieren)
2. in der zu beeinflussenden Chain eine neue Regel hinzufügen (``-I``) falls nicht vorhanden, die auf diese separate Chain verweist
3. die separate Chain leeren (``-F``)
4. die separate Chain mit Regeln füllen


Debugging {#debug}
---------

@see debugging
