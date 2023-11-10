[TOC]

Überblick {#ueberblick-entwicklung}
=========

Die Opennet-Firmware basiert auf den Komponenten *git*, *quilt* und der *OpenWrt*-Entwicklungsumgebung.
Links zur Dokumentation dieser Komponenten findest du am Ende dieses Dokuments.

Die grundlegende Struktur der Entwicklungsumgebung ist in der [Struktur-Dokumentation] (Struktur.md) beschrieben.


Vorbereitung der Entwicklungsumgebung {#prepare}
=====================================

Die Einrichtung der Entwicklungsumgebung dauert nur wenige Minuten und ist untenstehend beschrieben.
Der gesamte Prozess der Image-Erzeugung erfordert dagegen ca. 10 GB Festplattenplatz je Zielarchitektur und dauert - je nach Rechner - üblicherweise mindestens ein dutzend Stunden.


Abhängigkeiten installieren {#dependencies}
---------------------------

Debian / Ubuntu:

    apt install build-essential git flex gcc-multilib doxygen file gawk unzip python3 quilt \
      libncurses5-dev zlib1g-dev liblzo2-dev libssl-dev rsync qemu-utils \
      python3-distutils python3-lib2to3


Repository herunterladen {#repository}
------------------------

Quellcode Zugriff:

    git clone https://github.com/opennet-initiative/firmware.git 

Die lokale Arbeitsumgebung wird mit folgenden Kommandos abgeschlossen:

    cd firmware
    make init

Die obige Aktion wird eine Weile dauern, da die OpenWrt Repositories heruntergeladen werden.


quilt-Konfiguration {#quilt-setup}
-------------------

Für die komfortable Verwendung des Patch-Verwaltungsystems *quilt* sollten ein paar quilt-Einstellungen gesetzt werden.

Als dauerhafte Lösung ist folgendes möglich - dabei werden jedoch eventuell vorhandene quilt-Einstellungen gelöscht:

    cp quiltrc ~/.quiltrc

Alternativ können die Einstellungen auch zu Beginn jeder Shell-Sitzung importiert werden:

    source quiltrc

Falls die obigen Einstellungen nicht gesetzt werden, wird quilt unnötige Patch-Korrekturen vornehmen, sobald sich Zeitstempel ändern.

Dies ist nicht wünschenswert.


Build-Service {#build-service}
-------------

Auf einem Opennet Server ist ein automatischer Build-Dienst konfiguriert, der kurz nach einem push einen neuen Snapshot der Firmware erzeugt. Innerhalb von ca. 30 Minuten sind die ersten neuen Images dann verfügbar: http://downloads.opennet-initiative.de/openwrt/testing


Änderungen an der Firmware vornehmen {#developing}
====================================

Änderungen im Opennet-Repository auf den Server pushen {#git-push}
------------------------------------------------------

Nach dem Auschecken editiere die gewünschten Dateien. Wenn du .patch-Dateien editieren will, musst du weitere Dinge beachten (siehe andere Abschnitte). 

Um deine Änderungen einzuchecken, führe folgende Kommandos aus:

    # lokal einchecken
    git commit
    # (Versuch) Änderungen remote einzuchecken
    git push
    # Wenn es keinen Fehler gibt, bist du fertig. Glückwunsch!

Nun kann es sein, dass andere Personen zwischendurch Änderungen gemacht haben. Wenn dem so ist, bekommst du eine Fehlermeldung mit entsprechendem Hinweis. Dieses Problem kannst du folgendermaßen lösen: 

    # alle vorher eingespielten Patches zurückspielen
    make unpatch
    # hole alle Änderungen von remote und wende deine Änderungen darauf an
    git pull --rebase
    # deine Änderungen remote einchecken
    git push


Änderungen vom entfernten git-Repository lokal pullen {#git-pull}
-----------------------------------------------------

Prinzipiell ist die Arbeit mit dem opennet-Repository identisch mit dem üblichen Umgang mit git-Arbeitsumgebungen.
Lediglich die *quilt*-Patches führen unter besonderen Bedingungen zu einem leicht geänderten Verhalten.
Daher wird anstelle des üblichen `git pull` folgende Abfolge empfohlen:

    # lokale Patches zurücknehmen (vermeidet Konflikte, falls Patch-Dateien geändert werden)
    make unpatch
    # entfernte Änderungen 
    git pull --rebase


**Achtung**: `git pull --rebase` manipuliert deine lokale git-History. Falls du frische lokale Commits also bereits zu einem anderen Server übertragen haben solltest, dann führt dies zu unüberschaubaren Chaos. Verzichte in diesem Fall auf `--rebase`.


Eine Datei im OpenWrt Repository ändern {#patching}
---------------------------------------

Im OpenWrt Repository befindet sich das Basissystem und OpenWrt-spezifischer Code. Externe Pakete befinden sich (in Form von Makefiles, die auf upstream-Quellen verweisen) in den separaten Paket-Repositories.

    # alle Patches anwenden (falls der neue Patch am Ende angehängt werden soll)
    quilt push -a
    # einen neuen Patch beginnen
    quilt new IRGENDEIN_THEMA.patch
    # Hinweis: "quilt edit" ist identisch zu "quilt add", manuellen Änderungen und einem anschließenden "quilt refresh"
    quilt edit openwrt/IRGENDEINE_DATEI
    # Patch beschreiben
    quilt header -e
    # ausprobieren ...
    # falls weitere Änderungen vorgenommen wurden, dann nochmal die Patch-Datei aktualisieren
    quilt refresh
    # Patch committen
    git commit patches/IRGENDEIN_THEMA.patch


Eine Datei in einem Paket-Repository ändern {#patching-package}
-------------------------------------------

Im Gegensatz zum OpenWrt Repository befinden sich in den Paket-Repositories lediglich Makefiles (Rezepte für den Paketbau) und OpenWrt-spezifische Patches. Unsere Änderungen sind üblicherweise ebenfalls Patches, die zu den OpenWrt Patches hinzukommen.

1. einen neuen Patch anlegen:

        quilt new PATCH_NAME.patch

2. die noch nicht existente Patch-Datei im Paket-Repository zum Patch hinzufügen:

        quilt add packages/net/openssh/patches/042-FOO.patch

3. die OpenWrt-spezifische Dokumentation zum Erstellen von Patches lesen und anwenden:

        http://wiki.openwrt.org/doc/devel/patches

4. den Inhalt der neuen Patch-Datei erfassen:

        quilt refresh

5. dem Patch eine Beschreibung geben:

        quilt header -e

6. den Patch committen:

        git commit patches/PATCH_NAME.patch


Einen bestehenden Patch verändern {#patch-change}
---------------------------------

1. alle Patches zurücknehmen:

        quilt pop -a

2. alle Patches bis zum gewünschten anwenden:

        quilt push PATCH

3. gewünschte Datei(en) ändern:

        quilt edit DATEI

4. geänderte Dateien in Patch aufnehmen:

        quilt refresh

5. Patch-Beschreibung anpassen:

        quilt header -e


Paket-Repositories oder das OpenWrt Repository aktualisieren {#update-repo}
------------------------------------------------------------

Die verwendeten Basis-Repositories (OpenWrt), Pakete, Routing und Luci sind als git-submodules in das opennet-Firmware-Repository eingebunden. Somit sind sie auf spezifische Commits (mittels ihrer Hash-ID) festgelegt.
Neue Commits in dem zugrundeliegenden Branch werden von uns also nicht automatisch verwendet. Daher sollten wir gelegentlich zum aktuellen HEAD des Basis-Branch (z.B. "openwrt-19.07") wechseln.

    make pull-submodules
    # die geänderten Submodule-Commit-IDs für zukünftige Builds festlegen
    git commit -m "Update upstream sources" luci openwrt packages routing


Einen neuen Paket-Feed einbinden {#feed-add}
--------------------------------

Ziel: den Patch patches/oni-feeds.patch verändern (z.B. um einen weiteren Feed zu erweitern)

    # alle Patches zurücknehmen
    make unpatch
    # alle Patches auflisten
    quilt series
    # alles bis zu dem gewünschten Patch anwenden
    quilt push oni-feeds.patch
    # die neue Feeds-Quelle eintrage
    vi openwrt/feeds.conf
    # Patch-Datei aktualisieren
    quilt refresh
    # den neuen Patch in das Repository hochladen
    git commit patches/oni-feeds.patch -m "andere feeds-Dinge hinzugefügt"


Einzelnes Paket bauen {#build-single}
---------------------

Für die schnelle Lösung von Build-Problemen ist es oft sinnvoll, nur das eine problematische Paket erstellen zu lassen:

    make -C openwrt package/on-core/{clean,compile} V=s
 

Neue Pakete oder Paketoptionen einbinden {#config-change}
----------------------------------------

Die Liste vorhandener Pakete und ihrer Einstellungen wird mit dem *feeds*-Skript von OpenWrt verwaltet. Die Feeds werden mittels des meta-Makefile vor jedem Build und vor jedem Aufruf von `make menuconfig` aktualisiert. Du kannst dies jedoch auch manuell auslösen:

    make feeds


Fehler beim Build analysieren {#analyze-build-errors}
-----------------------------

Eine detaillierte Fehlerausgabe erhältst mit der make-Zugabe von `V=s`:

    make ath79 V=s

Dabei erleichtert es den Überblick deutlich, wenn du parallele Build-Prozess (z.B. `-j 3`) *nicht* verwendest. Andernfalls musst du eventuell ein paar Seiten in der Build-Ausgabe zurückblättern, um die Fehlermeldung zu finden.


Parallele Build-Prozesse für Mehr-Kern-Prozessoren {#parallel-build}
--------------------------------------------------

Wie üblich in make-Buildumgebung kannst du manuell mehrere parallele Prozesse für den Paketbau verwenden. Als Faustregel wird üblicherweise ein Wert von *Anzahl der Kerne + 1* empfohlen. Bei einem vier-Kern-Rechner wäre dies folgende Zeile:

    make -j 5

In den ersten 20 Zeilen der Build-Ausgabe wirst du ein paar Fehlermeldung bezüglich `-j1` finden - diese sind ein Indikator für eine openwert-spezifische Unfeinheit. Der finale Build-Prozess wird ungeachtet dieser Warnungen parallelisiert ablaufen.


Build-Konfiguration (menuconfig) {#menuconfig}
================================

Die opennet-Entwicklungsumgebung verwendet grundlegend die Abläufe der OpenWrt Buildumgebung. Es gibt jedoch ein paar Besonderheiten, bzw. Komfortfunktionen.


Zusammensetzung einer config-Datei {#config-assemble}
----------------------------------

Da die opennet-Firmware verschiedene Ziel-Plattformen (ath79, ixp44, x86, ...) unterstützt, müssen verschiedene Konfigurationen gepflegt werden. Zur Erleichterung der Pflege und zur Vermeidung von Doppelungen gibt es für jede Ziel-Plattform eine separate Datei (z.B. *opennet/config/ath79*), sowie eine Datei mit Einstellungen, die für alle Zielplattformen gelten (*opennet/config/common*). Letztere ist für den Entwicklungsprozess wohl die wichtigere.

Die plattform-spezifische config-Datei wird durch *opennet/config/Makefile* mit der allgemeinen config-Datei zusammengefügt. Anschließend werden folgende Ersetzungen vorgenommen:
* der Platzhalter ``__PKG_STATUS__`` wird durch *stable* oder *snapshots* ersetzt (je nachdem, ob der aktuelle git-commit ein Versions-Tag trägt)
* die Variable *CONFIG_VERSION_NUMBER* wird durch ein eventuell vorhandenes git-tag ersetzt (falls vorhanden) oder um das Suffix *-unstable-GIT_COMMIT_COUNT* erweitert


Konfiguration für eine Plattform erstellen {#platform-config}
------------------------------------------

Die finale OpenWrt Konfiguration wird aus der Ziel-Plattform-Konfiguration und der allgemeinen Konfiguration erstellt und anschließend mittels `make -C openwrt defconfig` durch OpenWrt auf Abhängigkeiten zu prüfen und mit den Standardwerten aufzufüllen.

Diese Konfiguration für eine Plattform kann beispielsweise mittels `make config-arx71xx` erstellt werden. Das Ergebnis ist anschließend als *openwrt/.config* verfügbar.


Konfigurationsänderungen betrachten {#diff-changes}
-----------------------------------

Zur verbesserten Überschaubarkeit von Einstellungsänderungen ist in dem meta-Makefile ein Target namens `diff-menuconfig` integriert. Es zeigt dir nach dem Ausführen des gewohnten `make -C openwrt menuconfig` den Unterschied zwischen der vorherigen und der gespeicherten Konfiguration in Form eines diffs an.


Entwicklungshinweise {#devel-hints}
====================

Shell-Skripte {#shell}
-------------

### Einbindung der Bibliotheken {#shell-include}


Unter ``/usr/lib/opennet/`` liegen mehrere Dateien, die Shell-Funktionen beinhalten.
Alle Funktionen werden durch die folgende Zeile im globalen Namensraum verfügbar gemacht:

    . "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


### Funktionen ausprobieren {#shell-run}

Alle Funktionen aus den shell-Bibliotheken lassen sich folgendermaßen prüfen:

    on-function get_zone_interfaces on_mesh

Dabei ist zu debug-Zwecken auch die ausführliche Ausführungsprotokollierung verfügbar:

    ON_DEBUG=1 on-function get_zone_interfaces on_mesh



### Fehlerbehandlung {#shell-error-handling}

Die optionale strikte Fehlerbehandlung durch die Shell erleichtert das Debugging.
Sie lässt sich global in der Datei ``/usr/lib/opennet/on-helper.sh`` mit folgender Zeile aktivieren:

    set -eu

In allen Skripten sollten Fehler-Traps aktiviert werden, um den Ort der Entstehung von Problemem leichter zu ermitteln.
Folgende Zeile ist im Kopf von nicht-trivialen Funktionen einzutragen, wobei der Funktionsname zu ersetzen ist:

    trap "error_trap NAME_DER_FUNKTION $*" EXIT

Leider ist es in der ash-Shell nicht möglich, reine Fehler (siehe ``set -e``) abzufangen (siehe ``echo 'trap "echo klappt" ERR' ash``).
Daher müssen wir die in der ash-Shell vorhandene allgemeinere ``EXIT``-trap verwenden.
Dies führt leider dazu, dass wir gewünschte Fehler (z.B.: ``return 1`` in einer Wahrheitswert-Funktion) von ungewünschten Fehlern (durch ``set -e`` abgefangen) explizit unterscheiden müssen.
In jeder Funktion, die explizit ein ``false``-Ergebnis zurückliefern möchte (und die traps verwendet), muss folgende Zeile anstelle von ``return 1`` (bzw. anderen Fehlercodes) eingesetzt werden:

    trap "" EXIT && return 1

Im System-Log (``logread``) lassen sich ausgelöste traps finden:

    logread | grep trapped


Folgende Stolperfallen sind sehr beliebt bei der Verwendung des strikten Fehlermodus:

* der letzte Befehl vor dem Ende einer Funktion, einer Schleife oder einer if/then/else-Konstruktion definiert den Rückgabewert
    * beispielsweise führt ``[ 1 -lt "$x" ] && echo "foo"`` als letzte Zeile einer Schleife zu einem Abbruch, da die Schleife mit dieser (nicht-Abbruch-auslösenden, jedoch gleichzeitig nicht-erfolgreichen Kette) nach ihrem letzten Durchlauf als "nicht erfolgreich" gilt und somit zu einem Abbruch führt
    * dieses Problem versteckt sich sehr gut, da es nur dann wirksam wird, wenn **der letzte Schleifendurchlauf** mit einem Fehlercode endet
    * ein ``return 0`` oder ``true`` oder ein angehängtes ``| true`` kann nie schaden


### uci-Funktionen {#shell-uci}

Da der typische uci-Aufruf ``uci -q get CONFIG_KEY`` bei nicht-existenten Schlüsseln einen Fehlercode zurückliefert, müsste hier jeder Aufruf von unübersichtlichem boilerplate-Code umgeben werden, um mit strikter Shell-Fehlerbehandlung zu funktionieren.
Alternativ steht diese Funktion zur Verfügung:

    uci_get CONFIG_KEY [DEFAULT_VALUE]

Das Ergebnis ist ein leerer String, falls der config-Wert nicht vorhanden oder leer ist. Andernfalls wird der Inhalt zurückgeliefert.

Außerdem ist eine verbesserte Version von ``uci add_list`` verfügbar, die - im Unterschied zum Original - bereits vorhandene Einträge nicht erneut hinzufügt:

    uci_add_list CONFIG_KEY=NEW_VALUE

Die Funktion ``uci_delete`` entspricht ihrem Äquivalent (``uci delete``) bis auf die fehlende Fehlermeldung und der Fehlercode im Falle der Löschung eines nicht vorhandenen Knotens:

    uci_delete CONFIG_KEY


### Zuordnung von git commits hash und ONI Versionsnummern generieren

Die Opennet Versionsnummern entsprechen dem Commit Zähler. Ab und zu ist es nötig zu wissen, welcher konkrete Commit zu welcher Versionsnummer gehört. Hier gibt es eine einfache Kommandozeile

    git log --oneline | sed -n '1!G;h;$p' | nl

Dies listet alle Commit mit entsprechender ONI Versionsnummer auf und einem Abstrakt der Commit Nachricht.


lua-Skripte {#lua}
-----------

Das OpenWrt Webinterface basiert auf lua-Skripten. Der grundlegende Code sollte in den shell-Bibliotheken untergebracht werden - lediglich die für die Darstellung notwendige Logik gehört in die lua-Skripte.


### Funktionen {#lua-functions}

Ein paar wenige Funktionen werden von mehreren lua-Skripten verwendet.
Diese liegen derzeit in der Datei ``on-core/files/usr/lib/lua/luci/model/opennet/funcs.lua``.

Die wichtigsten Funktionen sind folgende:

* on_function
* get_gateway_value
* set_gateway_value
* delete_gateway_value
* get_default_value

Hinzu kommen ein paar Funktionen für die Erleichterung alltäglicher Dinge:

* tab_split, line_split, space_split
* string_join
* map_table
* to_bool


luci-Webinterface {#luci-web}
-----------------

Zum Debuggen von Fehlern im Web-Interface sind folgende Kommandos sinnvoll:

    killall -9 uhttpd 2>/dev/null; sleep 1; rm -rf /var/luci-*; uhttpd -h /www -p 80 -f

Denselben Effekt erreichst du mit der Funktion *run_httpd_debug* (blockierend - inkl. Fehler-Ausgaben des Webservers), sowie *clean_luci_restart* (Webserver neustarten und im Hintergrund ausführen):

    on-function run_httpd_debug		# Debug
    on-function clean_luci_restart	# Daemon


Hotplug-System {#hotplug}
--------------

OpenWrt verwendet ``procd`` für die Behandlung von hotplug-Ereignissen.
Skripte liegen unter ``/etc/hotplug.d/``. Für unsere netzwerkbasierten Ereignisse (z.B. Hinzufügen neuer olsrd-Interfaces) verwenden wir den hotplug-Typ ``ifcace``.

Der Aufruf von hotplug-Skripten lässt sich folgendermaßen emulieren:

    ACTION=ifup INTERFACE=on_mesh hotplug-call iface


Hilfreiche Werkzeuge {#tools}
--------------------

### Unbenutzte Funktionen finden {#tools-unused}

Das Skript ``opennet/tools/check_for_obsolete_functions.sh`` gibt potentiell unbenutzte lua- und shell-Funktionen aus. Ein gelegentliches Prüfen der Ausgabe dieses Skripts hilft dabei, nicht mehr benötigte Funktionen zu beräumen.


### Lokale Änderungen auf einen AP übertragen {#tools-copy}

Das Skript ``opennet/tools/copy-package-files-to-AP.sh`` kopiert die Inhalte der lokalen Entwicklungsverzeichnisse direkt auf einen angebenen AP. Dies ist möglich, da in unseren Pakete lediglich Interpreter-Code (shell/lua) vorhanden ist und somit kein Build-Prozess erforderlich ist.

Falls auf dem Ziel-AP *rsync* installiert ist, wird die Übertragung deutlich beschleunigt.

  opennet/tools/copy-package-files-to-AP.sh 172.16.0.1


Tests {#tests}
--------------

Derzeit existieren lediglich Code-Stil-Prüfungen. Funktionale Tests sind nicht vorhanden.


Debugging {#debugging}
----------------------

Mehr Log-Ausgaben (debug) ins syslog (*logread*) schreiben:

  uci set on-core.settings.debug=true

Ein Skript mit detaillierter Ausführungsverfolgung starten:

  ON_DEBUG=1 on-function print_services

Fehlermeldungen des Web-Interface ausgeben:

  killall -9 uhttpd 2>/dev/null; sleep 1; rm -rf /var/luci-\*; uhttpd -h /www -p 80 -f


Profiling {#profiling}
---------

Für Performance-Optimierungen sind Daten zum Zeitbedarf der verschiedenen Funktionen sehr hilfreich.

Mit dem folgenden Kommando werden alle Shell-Skripte der opennet-Pakete derart manipuliert, dass fortan der Zeitbedarf jedes Funktionsaufrufs aufgezeichnet wird:

  on-function enable_profiling

Vor der Manipulation der Shell-Skripte prüft das obige Skript, ob die notwendigen Zusatzpakete (z.B. *bash*) intalliert sind.

Die obige Aktion ist irreversibel. Die einzige Möglichkeit, das Profiling wieder abzuschalten, ist die erneute Installation der Pakete.

Die Ergebnisse des Profiling werden unter `/var/run/on-profiling` abgelegt. Für jede Funktion wird eine Datei erzeugt. Jede Zeile in diesen Dateien entspricht dabei einem Funktionsdurchlauf. Die gemessene Zeit entspricht dem zeitlichen Abstand von Funktionseintritt und -ende. Die Verarbeitungszeit der aufgerufenen Funktionen geht also in den Zeitbedarf der sie aufrufenden Funktion ein.

Die Auswertung des Profiling ist folgendermaßen möglich:

  on-function summary_profiling

Mit fortlaufendem Profiling wird das tmp-Verzeichnis (bzw. der RAM) schrittweise gefüllt. Ein Host mit aktiviertem Profiling darf also nicht im produktiven Einsatz sein, da im Verlauf von Stunden eine Speichermangel-Situation droht.


Pakete erstellen {#packages}
================

Die verschiedenen Opennet-Pakete helfen bei der Modularisierung. Einige Pakete ermöglichen eine gewisse Nutzer-Funktion (z.B. on-openvpn: der Tunnel für den Internetzugang). Andere Pakete stellen Infrastruktur bereit, die von anderen Pakete benötigt wird (z.B. *on-certificates*).

Einige Pakete können über das Web-Interface installiert werden. Diese Pakete müssen an folgenden Orten aufgeführt werden:

* *on-core/files/usr/share/opennet/core.defaults*: zum Eintrag *on_modules* hinzufügen
* *on-core/files/usr/lib/lua/luci/view/opennet/on_modules.htm*: zum Dictionary *on_module_descriptions* hinzufügen
* *on-core/files/usr/lib/opennet/core.sh*: zur *case*-Verzweigung in *apply_changes* hinzufügen
* *config/common*: das Paket als Modul aktivieren (*CONFIG_PACKAGE_on-foobar=m*) und somit in den Build-Prozess aufnehmen
* falls das Paket übersetzungsfähige Texte enthalten kann: *touch opennet/po/de/on-foobar.po* (die Datei wird später durch "make translate" mit Inhalten gefüllt)

Das minimalste Paket ist *on-goodies* - es besteht lediglich aus einer Liste von Abhängigkeiten und ist daher gut als Vorlage geeignet. Zusätzlich sollten die meisten Pakete Initialisierungs- und Aufräumaktionen in *postinst*- und*prerm*-Skripten unterbringen.


Übersetzungen {#translations}
=============

Die Übersetzungen werden mittels des luci-Übersetzungskonzepts verwaltet. In den Templates verwenden wir englische Originaltexte.

Konzept {#translations-overview}
-------

* mittels luci-Werkzeugen wird aus den Code-Dateien eine pot-Datei erzeugt (ein Template, bzw. Katalog)
* die pot-Datei wird mit einer eventuell vorhandenen po-Datei verschmolzen (diese enthält die Übersetzungen für eine Zielsprache)
* die po-Dateien lassen sich mit einem Editor komfortabel bearbeiten (z.B. mit Virtaal)
* beim Build-Prozess wird mittels des *po2lmo*-Werkzeugs aus jeder po-Datei eine binäre lmo-Datei erzeugt - diese werden vom Makefile final unter */usr/lib/lua/luci/i18n* platziert (siehe *patches/makefile_include_opennet_packages.patch*)

Templates {#translations-templates}
---------

* im html-Teil: ``<%:This is an example.%>``
* im lua-Teil ohne Platzhalter: ``luci.i18n.translate("Interface")``
* im lua-Teil mit Platzhaltern: ``luci.i18n.translatef("Send an email to %s for further information.", email_address)``

Texte übersetzen {#translations-wording}
----------------

* po- und pot-Dateien übersetzen: ``make translate``
* po-Dateien (Übersetzungen) vervollständigen: ``virtaal opennet/po/de/on-core.po``


Versionsnummerierung {#version-numbers}
====================

Die Versionsnummer des kommenden Release ist in der ``opennet/config/common`` als ``CONFIG_VERSION_NUMBER`` eingetragen.

Im Laufe der Erzeugung der config-Datei wird eventuell die git-commit-Nummer hinzugefügt (siehe @ref config-assemble).

Die opennet-relevanten Pakete (*on-core* u.s.w) erhalten dieselbe Versionsnummer.
@sa ../../patches/makefile_include_opennet_packages.patch


Build-Server {#build-server}
=====================

Wir verwenden buildbot als Web-Interface und Baumumgebung: http://dev.opennet-initiative.de/.

Die buildbot Software wird durch einen git-commit ausgelöst und regt wenige Minuten nach einem *git push* einen Build-Prozess auf dem zuordneten Bau-Server an. Die Build-Schritte sind im Web-Interface sichtbar.

Innerhalb des Build-Prozess wird das export-Skript ausgeführt. Es kopiert das Build-Ergebnis für eine Plattform oder wahlweise die erstellte Dokumentation in das Export-Verzeichnis, welches via Webserver veröffentlicht wird (http://downloads.opennet-initiative.de/openwrt/). Das exakte Zielverzeichnis ergibt sich dabei aus der Versionsnummer (siehe @ref version-numbers).
@sa ../tools/buildbot-worker/export-build-builtbot.sh


Upgrade-Tests {#upgrade}
=============

Speichermangel {#upgrade-out-of-memory}
--------------

Bei RAM-Mangel (erkennbar am spontanen reboot ohne Änderungen nach dem Upload der neuen Firmware-Datei) kann folgende Kommandozeile wahrscheinlich genügend Platz schaffen:

    for a in collectd dnsmasq sysntpd cron; do /etc/init.d/$a stop; done

Alterantiv koennen diese Dienste via ``Administration -> System -> Systemstart`` gestoppt (nicht deaktiviert!) werden.


Release {#release}
=======

Für ein Release sind folgende Schritte durchzuführen:

* einen letzten commit (z.B. mit Doku) erstellen
* den Commit taggen: ``git tag -a v0.5.1``
* den Commit und das Tag zum Server pushen: ``git push --tags``
* das erzeugte Build-Verzeichnis nach "stable" verschieben: ``cd /var/www/downloads/openwrt && mv ../../downloads-buildbot/export/VERSION stable/VERSIONONLYNUMBER``
* Download-Link zu stable ``latest`` korrigieren (siehe ``ls -l /var/www/downloads.opennet-initiative.de/openwrt/stable``)
* die "CONFIG_VERSION_NUMBER" in ``opennet/config/common`` erhöhen
* Kommentare aus der ``opennet/changes.txt`` entfernen
* Wiki-Doku aktualisieren:
    * https://opennet-initiative.de/wiki/Opennet_Firmware_Versionen
    * https://opennet-initiative.de/wiki/Opennet_Firmware/Download
    * https://opennet-initiative.de/wiki/Firmware-Aktualisierung
* Anpassung des Download-Links in ``roles/virtualization-server/templates/vhost-admin.sh`` im ansible-Repository
* Informationsmail an die crew- oder die Mitgliederliste schicken


Externe Dokumentationen {#doc-external}
=======================

git {#doc-git}
---

Die git-Doku befindet sich hier: http://git-scm.com/documentation


quilt {#doc-quilt}
-----

Wir verwenden das Patch-Verwaltungssystem *quilt*. Dies erleichtert die Erstellung und Pflege von Patch-Serien gegenüber fremden Quellen.

Das Howto von *quilt* ist hier zu finden: http://repo.or.cz/w/guilt.git/blob/HEAD:/Documentation/HOWTO


OpenWrt {#doc-openwrt}
-------

Die Entwicklungsdokumentation von *OpenWrt* ist hier zu finden: http://wiki.openwrt.org/doc/devel/start

Die *OpenWrt* Build Umgebung ist in https://openwrt.org/docs/guide-developer/build-system/use-buildsystem beschrieben.
