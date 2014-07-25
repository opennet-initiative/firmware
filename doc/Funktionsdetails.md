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


**TODO**:

* /etc/passwd darf nicht spontan ueberschrieben werden - dabei gehen Nutzeraccounts (z.B.: von anderen Paketen) verloren
  * stattdessen lediglich das root-Passwort setzen
* firewall: nicht selbst schreiben, sondern vorhandenes anpassen (unklar, inwieweit sich die Struktur bei openwrt verändert hat)
  * Hinzufügen der opennet-Zone sollte genügen
* olsrd-Konfiguration: es genügt wahrscheinlich, nameservice hinzuzufügen, anstelle die komplette Datei zu überschreiben
* rc.local unveraendert lassen; stattdessen policy-routing in separates init-Skript und local_user weglassen


Zeit synchroniseren
-------------------
Im Paket *on-core* befindet sich eine Datei *etc/init.d/ntpclient*. Beim Start sorgt sie dafür, dass alle konfigurierten NTP-Server (*ntpclient.@ntpserver[..]*) nacheinander im 3-Sekunden-Takt angefragt werden.
Sobald eine eine Verbindung hergestellt wurde, ist das Skript beendet.

Als NTP-Server sind derzeit (via */etc/config_presets/ntpclient*) folgende konfiguriert:

* 192.168.0.244
* 192.168.0.247
* 192.168.0.248
* 192.168.0.254

**TODO**:

* NTP-Server via ntpd konfigurieren (`uci show system.ntp.server`)
* NTP-Server aus Gateway-Liste (192.168.0.x) ermitteln?
* Funktion *update_ntp_from_gws* aus *on-openvpn/files/usr/bin/on_vpngateway_check* herausziehen


DNS-Server
----------

Im Paket *on-openvpn* wird mittels des Skripts *on-openvpn/files/usr/bin/on_vpngateway_check* mit der Funktion *update_dns_from_gws* die Liste der DNS-Server in */tmp/resolv.conf.auto* gepflegt.


**TODO**:

* Funktionalität von *on-openvpn* nach *on-core* verschieben


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


**TODO**:

* Datei *etc/firewall.opennet* in eine übliche uci-Firewall-Regel umwandeln



Nutzer-VPN
----------
Im Paket *on-openvpn* ist das config-preset *on-openvpn* enthalten, das die Suchmaske fuer gateway-IPs festlegt (192.168.0.x), sowie konfigurierbar festlegt, dass alle Gateways als ntp- und DNS-Server verwendet werden sollen.
Außerdem sind in diesem config_preset die Vorgaben für Nutzer-Zertifikate eingetragen.

Das config_preset *openvpn* überschreibt das Original des openvpn-Pakets.


Minütlich läuft ein cronjob (*on_vpngateway_check*), der folgendes tut:

* prüfen, ob ein anderer cronjob bereits läuft (falls ja, dann töten, kurz warten - notfalls abbrechen, falls er nicht stirbt)
  * Prüfung erfolgt über eine definierte PID-Datei
* olsrd-nameservice-Plugin aktivieren (via uci), falls es nicht aktiv ist
  * das ist fuer die automatische gateway-Suche noetig, da die Gateways einen nameservice-Eintrag verteilen



**TODO**:

* die Einstellung *gw_ntp* (Gateways als NTP-Server nutzen) sollte nicht Teil des on-openvpn-Pakets sein, sondern zu *on-core* verschoben werden
* prüfen, ob sich die Konfiguration "unseres" OpenVPN-Servers als separate Konfiguration hinzufügen lässt (anstatt die komplette openvpn-Konfiguration zu überschreiben)
* der Seiteneffekt der nameservice-Plugin-Aktivierung sollte explizit angewiesen werden
* Verbindungsaufbau wird mit allen vorhandenen Gateways versucht
  * jeweils nur kurze Verbindungen (via OpenVPN-Parameter 'inactive=10')



Usergateway
-----------
Im Paket *on-usergw* sind zwei VPN-Konfigurationen (opennet_ugw, opennet_vpntest) enthalten.
Außerdem ist ein Skript für den VPN-Aufbau, sowie für einen Geschwindigkeitstest und für das Kündigen einer alten IP vorhanden.


**TODO**:

* die genaue Funktionsweise des ugw-Skripts analysieren und beschreiben



Wifidog
-------
**TODO**

