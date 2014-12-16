Firmware 0.5
============

Datenbank der Dienste
---------------------

Auf jedem AP wird eine Datenbank von Diensten gepflegt. Die typische Quelle fuer diese Datenbank ist der olsrd-Nameservice.

Die Dienste werden mittels eines olsrd-nameservice-Trigger-Skripts aktualisiert (``/etc/olsrd/nameservice.d/on_update_services``).

Die Aktion des Trigger-Skripts lässt sich manuell auslösen:

  on-function update_olsr_services

Die Ergebnisse der Dienst-Suche werden im Dateisystem gespeichert. Langfristig unveraenderliche Attribute eines Dienstes (z.B. der Host und der Port) werden persistent gespeichert - die übrigen Informationen (z.B. die Routing-Entfernung) liegen lediglich im tmpfs und werden bei jedem Neustart erneut gesammelt.

Die Details zur Datenablage sind unter ``Datenspeicherung`` zu finden.

Die menschenfreundliche Zusammenfassung aller Dienst-Informationen ist recht übersichtlich:

  on-function print_services

Dienste werden durch einen eindeutigen Namen (zusammengesetzt aus URL, Schema, Hostname, Port, usw.) referenziert. Dieser eindeutige Namen wird von allen Dienst-relevanten Funktionen verwendet.


DNS - Namensauflösung
---------------------

Alle DNS-Server verteilen via olsrd-nameservice-Plugin einen Eintrag ähnlich dem folgenden:

::

  dns://192.168.0.247:53|udp|dns


Konfiguration der DNS-Anbieter
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Die folgenden Voraussetzungen müssen von DNS-Servern im Opennet erfüllt werden:

1. der DNS-Port (üblicherweise UDP-Port 53) ist vom Opennet aus erreichbar
2. DNS-Abfragen werden nicht geloggt (Datensparsamkeit gegenüber den Nutzenden)
3. der lokale olsrd-Dienst verteilt via ``nameservice`` die URL des DNS-Servers


Der entsprechende ``nameservice``-Block in der ``olsrd.conf`` des DNS-Servers kann folgendermaßen aussehen:

::

  LoadPlugin "olsrd_nameservice.so.0.3"
  {
      PlParam "service" "dns://192.168.0.247:53|udp|dns" 
  }

**Wichtig**: Die angegebene IP muss unbedingt auf einem der von olsr verwalteten Netzwerk-Interfaces konfiguriert sein. Andernfalls wird das ``nameservice``-Plugin stillschweigend die Verteilung unterlassen. In der ``/var/run/services_olsr`` auf dem Host ist sofort zu erkennen, ob der Dienst-Eintrag verteilt wird.

Integration auf den APs
^^^^^^^^^^^^^^^^^^^^^^^

Das Skript ``/etc/olsrd/nameservice.d/on_update_services`` wird bei jeder Änderung der olsrd-Nameservice-Announcements aufgerufen und überträgt alle Dienst-Informationen in die lokale Datenbank. Im Anschluss wird ``apply_changes on-core`` aufgerufen. Dies löst die Aktualisierung der ``dnsmasq``-Nameserver-Datei (``/var/run/dnsmasq.servers``) basierend auf der Dienstliste aus.

In diesem Verlauf wird auch sichergestellt, dass die uci-Variable ``dhcp.@dnsmasq[0].serversfile`` gesetzt ist. Falls dies nicht der Fall ist, wird die Datei ``/var/run/dnsmasq.servers`` eingetragen.
Abschließend wird dem ``dnsmasq``-Prozess ein HUP-Signal gesendet, um ein erneutes Einlesen der Konfigurationsdateien auszulösen.

Folgende Voraussetzungen müssen gegeben sein:

* ``dnsmasq`` läuft
* das Plugin ``nameservice`` ist aktiviert
* das ``dnsmasq``-init-Skript ist gepatcht, um die ``servers-file``-Option zu beachten



NTP - Zeitsynchronisation
-------------------------

Alle NTP-Server verteilen via olsrd-nameservice-Plugin einen Eintrag ähnlich dem folgenden:

::

  ntp://192.168.0.247:123|udp|ntp

Konfiguration der NTP-Anbieter
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

//analog zur Konfiguration der DNS-Anbieter//

Integration auf den APs
^^^^^^^^^^^^^^^^^^^^^^^

Das Skript ``/etc/olsrd/nameservice.d/on_update_services`` wird bei jeder Änderung der olsrd-Nameservice-Announcements aufgerufen und überträgt alle Dienst-Informationen in die lokale Datenbank. Im Anschluss wird ``apply_changes on-core`` aufgerufen. Dies löst die Aktualisierung der NTP-Server-Liste in der uci-Konfiguration (``system.ntp.server``) aus.

Im Falle von Änderungen der Server-Liste wird diese in die uci-Variable ``system.ntp.server`` übertragen. Anschließend wird der ntp-Dienst neugestartet.


Gateway-Auswahl
---------------

Gateway-Liste
^^^^^^^^^^^^^

Das Skript ``/etc/olsrd/nameservice.d/on_update_services`` wird bei jeder Änderung der olsrd-Nameservice-Announcements aufgerufen und überträgt alle Dienst-Informationen in die lokale Datenbank.
Minütlich wird via cronjob die Datei ``/usr/sbin/on_vpngateway_check`` ausgeführt. Dieser führt folgende Aktionen aus:

* Test jedes einzelnen announcierten GW- oder UGW-Dienstes (falls die Wartezeit abgelaufen ist)
* Ermittlung des aktuell besten Gateways und seine Aktivierung, falls er seit mehreren Minuten besser ist oder falls aktuell kein Gateway konfiguriert ist


Gateway-Auswahl
^^^^^^^^^^^^^^^
 * Sortieren nach Entfernung, Hop-Count oder manuell

Gateway-Wechsel
^^^^^^^^^^^^^^^

Falls der minütliche cronjob feststellt, dass ein besserer Gateway als der aktuell verwendete vorhanden ist, dann schreibt er das Attribute ``switch_candidate_timestamp`` in diesen neuen Dienst. Sobald dieser Zeitstempel im Verlaufe nachfolgender cronjob-Läufe älter als fünf Minuten ist, wird der neue Gateway via ``select_mig_connection`` aktiviert und eine Verbindung aufgebaut.

Gateway-Verbindungsabbruch
^^^^^^^^^^^^^^^^^^^^^^^^^^

Sollte die Verbindung zum aktuellen Gateway abreissen, muss der Gateway als unbrauchbar markiert werden und ein Wechsel zu einem anderen Gateway ist sinnvoll. Dies wird folgendermaßen erreicht:

# Jeder Client erhält vom Server via ``keepalive`` die Regeln ``ping 10`` und ``pin-restart 120``. Somit wird nach ca. zwei Minuten Ausfall ein Neustart der Verbindung von Client-Seite ausgeführt.
# Der Verbindungsneustart führt aufgrund der fehlenden ``persist-tun``-Option zur Ausführung des ``down``-Skripts, In diesem Skript wird der Status der aktuellen OpenVPN-Verbindung als 'n' gesetzt. Somit wird bei der nächsten Prüfung eines Gateway-Wechsels ohne Verzögerung ein alternativer Gateway gewählt.
# Die Einstellung ``explicit-exit-notify`` muss abgeschaltet sein, da andernfalls der Grund des Endes der Verbindung im ``down``-Skript nicht erkennbar ist (die Status-Variable ``signal`` wird von ``explicit-exit-notify`` überschrieben).

Datenspeicherung
^^^^^^^^^^^^^^^^

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


Internet-Freigabe (Usergateways)
--------------------------------

Datenspeicherung
^^^^^^^^^^^^^^^^

Für jeden externen Gateway werden dauerhafte und wechselhafte Eigenschaften gespeichert.

Die dauerhaften Eigenschaften werden via uci unterhalb von ``on-usergw.@uplink[*]`` gespeichert. Folgende Attribute sind dauerhafter Natur:

* name - eindeutiger Name dieses UGW-Servers (wird beispielsweise als Name für die openvpn-Instanz verwendet)
* type - z.B. "openvpn"
* hostname - DNS-Name des UGW-Servers
* port - Portnummer des UGW-Servers
* protocol - "tcp" oder "udp"
* template - die zu verwendende Konfigurationsvorlage (z.B. /usr/share/opennet/ugw-openvpn-udp.template)

Die wechselhaften Eigenschaften werden im temporären Dateisystem (also im RAM) gespeichert. Dies reduziert Flash-Schreibzugriffe. Die wechselhaften Eigenschaften sind folgende:

* age - Alter des Eintrags (TODO: durch "last_seen" ersetzen)
* details - eventuelle Zusatzinformationen, die aus einem olsrd-nameservice-Announcement entnommen wurden (z.B. Bandbreite)
* download - letzte ermittelte Download-Bandbreite (kBytes/s)
* mtu - Status des MTU-Test ("ok" oder "error")
* mtu_msg - vollständige Status-Ausgabe von openvpn infolge des MTU-Tests
* mtu_toGW_tried - Startwert für die MTU-Prüfung (ausgehend)
* mtu_toGW_actual - Resultat der MTU-Prüfung (ausgehend)
* mtu_fromGW_tried - Startwert für die MTU-Prüfung (eingehend)
* mtu_fromGW_actual - Resultat der MTU-Prüfung (eingehend)
* mtu_time - Zeitstempel (epoch) des letzten MTU-Tests
* ping - Ping-Laufzeit zum UGW-Server
* speed_time - Zeitstempel (epoch) des letzten UGW-Tests
* speed_time_prev - Zeitstempel (epoch) der anzeigt, seit wann die aktuelle Geschwindigkeitsmessung grob konstant blieb
* status - Zusammenfassung: Gateway ist erreichbar ("ok" oder "error")
* upload - letzte ermittelte Upload-Bandbreite (kBytes/s)
* wan - Status des WAN-Tests ("ok" oder "error")

Geschwindigkeitstests
^^^^^^^^^^^^^^^^^^^^^

Zu allen UGWs wird in der UGW-Übersicht eine Abschätzung der Upload- und Download-Bandbreite angezeigt.
Diese wird durch den Download von der URL http://UGW_HOSTNAME/.big und den Upload via netcat zu Port 2222 auf dem UGW-Host ermittelt.

Die Geschwindigkeiten werden nach jeder Messung mit den vorherigen Werten gemittelt gespeichert. Änderungen setzen sich also nur langsam durch.

Diese Prüfung wird im Tagestakt innerhalb der ugw-Funktion ``ugw_doExtraChecks`` durchgeführt.

Konfiguration des UGW-Servers:

* Bereitstellung einer beliebigen Datei (> 100 MByte), die unter der URL http://UGW_HOST/.big erreichbar ist
* Betrieb eines netcat-Listeners:

 * iptables -I INPUT -p tcp --dport 22222 -j ACCEPT
 * (while true; do nc -l -n -p 22222 -q 0 2>&1 >/dev/null; sleep 2; done) &


Liste der Gegenstellen
^^^^^^^^^^^^^^^^^^^^^^

In der Firmware sind zwei öffentliche VPN-Server angegebene, die den Zugang zum Opennet-Mesh ermöglichen.
Diese sind in der Datei ``/usr/share/opennet/usergw.defaults`` zu finden (siehe ``openvpn_ugw_preset_X``).

Neben den vordefinierten Hosts werden Zugangsmöglichkeiten auch via olsrd-Nameservice veröffentlicht (Service-Typ: "mesh").
Bei jeder Änderung der lokalen Services-Liste (``/var/run/services_olsr``) wird somit das Skript ``/etc/olsrd/nameservice.d/on_update_usergw`` ausgeführt, welches eventuell neu announcierte Hosts parst und speichert.

Die bekannten Host-Einträge werden im uci-Namensraum ``on-usergw`` in der anonymen Liste ``uplink`` gespeichert. Hier sind alle für den Verbindungsaufbau notwendigen Daten abgelegt. Folgende Attribute sind dort beispielsweise zu finden:

  on-usergw.@uplink[0]=uplink
  on-usergw.@uplink[0].enable=1
  on-usergw.@uplink[0].name=openvpn_on_ugw_erina_opennet_initiative_de_udp_1602
  on-usergw.@uplink[0].type=openvpn
  on-usergw.@uplink[0].hostname=erina.opennet-initiative.de
  on-usergw.@uplink[0].template=/usr/share/opennet/ugw-openvpn-udp.template
  on-usergw.@uplink[0].config_file=/var/etc/openvpn/openvpn_on_ugw_erina_opennet_initiative_de_udp_1602.conf
  on-usergw.@uplink[0].port=1602
  on-usergw.@uplink[0].protocol=udp
  on-usergw.@uplink[0].local_port=5100
  on-usergw.@uplink[0].service=openvpn://192.168.1.203:5100|udp|ugw upload:4 download:4704 ping: creator:ugw_service

Nach jedem Booten wird einmal das via olsr-nameservice getriggerte Skript ausgeführt - dies führt implizit dazu, dass im Falle einer leeren Hostliste (nach der Erst-Installation) die zwei vorkonfigurierten Gegenstellene eingetragen werden.


Datensammlung: ondataservice
----------------------------

Das //ondataservice//-Plugin verteilt via //olsrd// detaillierte Informationen über den AP im Netz.

Konfiguration auf dem AP
^^^^^^^^^^^^^^^^^^^^^^^^
Das Initialisierungsskript /etc/uci-defaults/on-olsr-setup wird bei der Erstinstallation oder beim Firmware-Upgrade ausgeführt.
Es aktiviert da ondataservice-Plugin.


Erstkonfiguration
-----------------

Nach einer frischen Installation, sowie im Anschluss an ein Firmware-Upgrade wird eine Reihe von Skripten zur Initialisierung ausgeführt.
Openwrt stellt hierfür den //uci-defaults//-Mechanismus bereit:

  http://wiki.openwrt.org/doc/uci#defaults

Für alle Aktivitäten, die nach der Installation oder einem Upgrade notwendig sind, existieren in den Opennet-Paketen Dateien unterhalb von ``/usr/lib/opennet/init/``.
Diese Skripte werden als Symlink unter ``/etc/uci-defaults/`` bereitgestellt.
Nach dem Booten prüft ein openwrt-init-Skript, ob sich Dateien unterhalb von ``/etc/uci-defaults/`` befindet.
Jede aufgefundene Datei wird ausgeführt und bei Erfolg anschließend gelöscht.

Die Existenz einer Datei in diesem Verzeichnis deutet also auf ein Konfigurationsproblem hin, das gelöst werden sollte.

Standard-IP setzen
^^^^^^^^^^^^^^^^^^

Das Skript ``/etc/uci-defaults/on-configure-network`` prüft, ob der uci-Wert ``on-core.settings.default_ip_configured`` gesetzt ist.
Sollte dies nicht der Fall sein, dann wird die IP-Adresse aus der //on-core//-Defaults-Datei ausgelesen und konfiguriert.
Anschließend wird das obige uci-Flag gesetzt, um eine erneute Konfiguration anch einem Update zu verhindern.


Debugging
---------

Jedes Skript und jede Funktionalität lässt sich folgendermaßen im Detail debuggen:

  ON_DEBUG=1 on_usergateway_check


Firmware-NG
===========


Konfiguration initialisieren
----------------------------
Im Paket *on-core* befindet sich eine Datei *etc/init.d/on_config*. Beim Booten wird *check_firmware_upgrade* durchgeführt und anschließend die Opennet-Erstkonfiguration gesetzt, falls kein Netzwerkinterface mit dem Präfix "on_" existiert.


check_firmware_upgrade:

* die bisherige Version wird aus /etc/banner ausgelesen
  * folgend auf den String "opennet-firmware-ng" (viertes Token dieser Zeile)
* die aktuelle Version wird via `opkg status on-core` ausgelesen
* bei Unterschieden werden:
  * die Default-Einstellungen (*etc/etc_presets*) aus on-core werden kopiert
    * passwd wird überschrieben
    * etc/rc.local wird überschrieben; dadurch wird der Aufruf folgender Skripte sichergestellt:
      * rc.local_on-core: policy-Routing initialisieren
      * rc.local_user: kann vom Nutzer erstellt werden
    * init.d/watchdog wird überschrieben
  * /etc/banner (mit neuer Versionsnummer) geschrieben
  * auf APs mit aktiviertem UserGW wird folgendes aufgerufen: `require('luci.model.opennet.on_usergw') upgrade()`


Opennet-Erstkonfiguration:

* preset-Dateien (etc/config_presets/*) werden nach etc/ kopiert:
  * firewall: manuell erstellte Zonenkonfiguration
  * ntpclient: siehe "Zeitsychronisation"
  * olsrd: Basiskonfiguration inkl. nameservice
  * on-core: IP- und Netzwerkkonfiguration entsprechend den Opennet-Konventionen, sowie csr-Mailadresse, debug und on_id



Zeit synchroniseren
-------------------
Im Paket *on-core* befindet sich eine Datei *etc/init.d/ntpclient*. Beim Start sorgt sie dafür, dass alle konfigurierten NTP-Server (*ntpclient.@ntpserver[..]*) nacheinander im 3-Sekunden-Takt angefragt werden.
Sobald eine eine Verbindung hergestellt wurde, ist das Skript beendet.

Als NTP-Server sind derzeit (via */etc/config_presets/ntpclient*) folgende konfiguriert:

* 192.168.0.244
* 192.168.0.247
* 192.168.0.248
* 192.168.0.254


DNS-Server
----------

Im Paket *on-openvpn* wird mittels des Skripts *on-openvpn/files/usr/bin/on_vpngateway_check* mit der Funktion *update_dns_from_gws* die Liste der DNS-Server in */tmp/resolv.conf.auto* gepflegt.



ondataservice-Plugin
--------------------

Im Paket *on-core* ist die olsrd-Konfiguration enthalten, die zum Laden des ondataservice-Plugin führt. Außerdem ist ein täglicher cronjob (*usr/sbin/status_values.sh*) enthalten, der bei Bedarf die sqlite-Datenbank anlegt und die Datensatz-Datei aktualisiert.


olsrd
-----
Im Paket *on-core* ist ein minütlicher cron-job enthalten, der prüft, ob ein olsrd-Prozess läuft und ihn notfalls neu startet.

Beim Booten kann es dazu kommen, dass das oder die olsrd-Interfaces noch nicht aktiviert sind. In diesem Fall beendet sich olsrd mit der Fehlermeldung "Warning: Interface 'on_wifi_0' not found, skipped". Aufgrund des minütlichen cronjobs wird olsrd innerhalb von einer Minute trotzdem gestartet.


cronjobs
--------
Im Paket *on-core* ist eine Datei *etc/crontabs/root* enthalten, die im groben folgendem Patch folgt: https://dev.openwrt.org/ticket/1328


Firewall
--------
Die Zonen-Konfiguration von openwrt wird durch das Paket *on-core* von uns überschrieben.

Die Datei *etc/firewall.opennet* fügt anscheinend eine relevante Masquerade-Regel zu den üblichen Regeln hinzu, die mit den normalen uci-Regeln nicht nachgebildet werden kann.


Nutzer-VPN
----------
Im Paket *on-openvpn* ist das config-preset *on-openvpn* enthalten, das konfigurierbar festlegt, ob alle Gateways als ntp- und DNS-Server verwendet werden sollen.
Außerdem sind in diesem config_preset die Vorgaben für Nutzer-Zertifikate eingetragen.

Das config_preset *openvpn* überschreibt das Original des openvpn-Pakets.

Das lua-Skript `/usr/lib/lua/luci/model/opennet/on_vpn_autosearch.lua` wird via cron-Job im Minuten-Takt ausgeführt. Außerdem wird es beim Bearbeiten der Gateway-Einstellungen im Web-Interface gestartet. Seine Aufgabe ist die Neuberechnung der Wertigkeit aller erreichbaren Gateways, sowie die Sortierung der Gateway-Liste in den uci-Sektionen `on-openvpn.gate_*`.

Minütlich läuft ein cronjob (*on_vpngateway_check*), der folgendes tut:

* prüfen, ob ein anderer cronjob bereits läuft (falls ja, dann töten, kurz warten - notfalls abbrechen, falls er nicht stirbt)
  * Prüfung erfolgt über eine definierte PID-Datei
* olsrd-nameservice-Plugin aktivieren (via uci), falls es nicht aktiv ist
  * das ist fuer die automatische gateway-Suche noetig, da die Gateways einen nameservice-Eintrag verteilen


**TODO**:

* prüfen, ob sich die Konfiguration "unseres" OpenVPN-Servers als separate Konfiguration hinzufügen lässt (anstatt die komplette openvpn-Konfiguration zu überschreiben)
* der Seiteneffekt der nameservice-Plugin-Aktivierung sollte explizit angewiesen werden


Usergateway
-----------
Im Paket *on-usergw* sind zwei VPN-Konfigurationen (opennet_ugw, opennet_vpntest) enthalten.
Außerdem ist ein Skript für 
* VPN-Auf- und Abbau (opennet_ugw_up.sh, opennet_ugw_down.sh)
* Geschwindigkeitstest  (on_speed_check)
* lösche UGW-HNA in olsrd wenn es seit mehr als einer Woche nicht mehr genutzt wurde (clean_ugw_hna.sh)
* Skript, um alle UGW Voraussetzungen und Funktionalitäten zu testen (on_usergateway_check)
* Luci Script zur Webseitenausgabe (ugw_status)

Cronjob alle 5min:
* rufe Script on_usergateway_check auf mit folgenden Funktionen: (solange gleiches Script nicht bereits läuft) 
** ugw_syncVPNConfig - transfer UGW config from on-usergw to openvpn
** ugw_checkWANs - check if routes to UGW go through WAN-device, detect ping-time
** ugw_checkVPNs - check Vpn availability of gateway on port 1600
** ugw_doExtraChecks - do extra checks (speed, mtu)
** ugw_checkSharingBlocked - check if sharingInternet is temporarily blocked
** ugw_checkWorking - check if sharingInternet is possible for every gateway and store 'enabled'-value in openvpn config
** ugw_forwardGW - if there is a better gw then switch
** ugw_shareInternet - start UGW-tunnels if MTU and WAN ok and sharing is enabled
*** Starte (alle) UGWs, welche gestartet werden können. Überprüfe vorher, ob sie bereits laufen.
*** Stoppe alle UGWs, welche noch laufen, aber in der Zwischenzeit über die Nutzeroberfläche deaktiviert wurden.

Cronjob jeden Tag:
* rufe Script clean_ugw_hna.sh (siehe oben) auf

Konfiguration:
Die Datei /etc/config_presets/on-usergw enthält default Einstellungen für die SSL UGW Zertifkate, zwei Usergateway-Server (erina und subaru) sowie alle OpenVPN Einstellungen zum Verbinden zu den Servern.

Starten eines UGWs:


Wifidog
-------
Das allgemeine Wifidog-Konzept wird unter https://wiki.opennet-initiative.de/wiki/Projekt_Wifidog#DHCP-Ablauf_der_Wifidog-Implementierung
beschrieben. 
* Für Wifidog-Knoten ist der 10.3. / 16 Bereich reserviert (config_presets/on-wifidog).
* Als Authentifizierungsserver wird inez.opennet-initiative.de genutzt. Hier können Nutzer gemanaged/geblockt/... werden. (wifidog.conf.opennet_template).
* Alle DHCP Anfragen werden an die 10.1.0.1 und somit inez.on-i.de weitergeleitet (dhcp-fwd.conf.opennet_template).
 * die 10.1.0.1 ist die gateway-IP - auf dem jeweiligen Gateway muss also eine DNAT-Umleitung zu inez vorhanden sein
* Beim Start (init.d/on_wifidog_config) wird ein *free* Netzwerk erzeugt falls es nicht bereits vorhanden ist.

