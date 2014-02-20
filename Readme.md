Entwicklungsumgebung einrichten
===============================

Erforderliche Pakete installieren
---------------------------------

Debian:

    apt-get update
    apt-get install build-essential git flex gcc-multilib subversion libncurses5-dev zlib1g-dev liblzo2-dev gawk unzip python


Lokale Build-Umgebung einrichten
--------------------------------

    git clone https://projects.farbdev.org/opennet/on-firmware.git
    cd on-firmware
    make init

Nun kannst du mit folgendem Kommando die aktuelle Firmware bauen:

    make all

Dieser Prozess wird (insbesondere beim ersten Mail) viele Stunden dauern, da zuerst die Cross-Compile-Toolchain für die jeweilige Zielplattform erzeugt werden muss.


quilt-Konfiguration
-------------------

Für die komfortable Verwendung von quilt sollten ein paar quilt-Einstellungen gesetzt werden.

Als dauerhafte Lösung ist folgendes möglich - dabei werden jedoch eventuell vorhandene quilt-Einstellungen gelöscht:

    cp quiltrc ~/.quiltrc

Alternativ können die Einstellungen auch zu Beginn jeder Shell-Sitzung importiert werden:

    source quiltrc

Falls die obigen Einstellungen nicht gesetzt werden, wird quilt unnötige Patch-Korrekturen vornehmen, sobald sich Zeitstempel ändern.
Dies ist nicht wünschenswert.


Die Firmware weiterentwickeln
=============================
Wir verwenden das Patch-Verwaltungssystem *quilt*. Dies erleichtert die Erstellung und Pflege von Patch-Serien gegenüber fremden Quellen.

Das Howto von *quilt* ist hier zu finden: http://repo.or.cz/w/guilt.git/blob/HEAD:/Documentation/HOWTO


Eine Datei im openwrt-Repository ändern
---------------------------------------

Im openwrt-Repository befindet sich das Basissystem und openwrt-spezifischer Code. Externe Pakete befinden sich (in Form von Makefiles, die auf upstream-Quellen verweisen) in den separaten Paket-Repositories.

    # alle Patches anwenden (falls der neue Patch am Ende angehängt werden soll)
    quilt push -a
    # einen neuen Patch beginnen
    quilt new IRGENDEIN_THEMA.patch
    quilt edit openwrt/IRGENDEINE_DATEI
    # Patch beschreiben
    quilt header -e
    # ausprobieren ...
    # Patch committen
    git commit patches/IRGENDEIN_THEMA.patch


Eine Datei in einem Paket-Repository ändern
-------------------------------------------

Im Gegensatz zum openwrt-Repository befinden sich in den Paket-Repositories lediglich Makefiles (Rezepte für den Paketbau) und openwrt-spezifische Patches. Unsere Änderungen sind üblicherweise ebenfalls Patches, die zu den openwrt-Patches hinzukommen.

1. einen neuen Patch anlegen:

        quilt new PATCH_NAME.patch

2. die noch nicht existente Patch-Datei im Paket-Repository zum Patch hinzufügen:

        quilt add packages/net/openssh/patches/042-FOO.patch

3. die openwrt-spezifische Dokumentation zum Erstellen von Patches lesen und anwenden:

        http://wiki.openwrt.org/doc/devel/patches

4. den Inhalt der neuen Patch-Datei erfassen:

        quilt refresh

5. dem Patch eine Beschreibung geben:

        quilt header -e

6. den Patch committen:

        git commit patches/PATCH_NAME.patch


Einen bestehenden Patch verändern
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


openwrt-Repositories aktualisieren
----------------------------------

1. alle Patches zurücknehmen:

        quilt pop -a

2. in das Repository-Verzeichnis wechseln und zum gewünschten Commit wechseln:

        cd openwrt; git checkout FOO; cd ..

3. Patches wieder anwenden:

        quilt push -a

4. herumprobieren

5. falls der Commit als aktueller Repository-Zustand gespeichert werden soll, dann committen:

        git commit openwrt


Senden von Änderungen in das Opennet-Repository
===============================================

Für das Einbringen von Änderungen in das öffentliche Firmware-Repository benötigst du einen git-Account.
Diesen kannst du auf der Opennet-Firmware-Mailingliste erfragen: https://list.opennet-initiative.de/mailman/listinfo/firmware

Sobald du einen git-Account zum pushen deiner Änderungen hast, solltest du den Upstream auf die schreibfähige URL umstellen:

    git remote set-url origin git@projects.farbdev.org:opennet/on-firmware.git


Historischer Rückblick: Erstellung der Entwicklungsumgebung im Jahr 2014
========================================================================

**Die folgende Beschreibung ist nicht relevant fuer die Weiterentwicklung der Firmware.**

Die Beschreibung soll lediglich die Struktur der Firmware-Entwicklungsumgebung verdeutlichen.


Repositories verknüpfen
-----------------------

    mkdir opennet
    git init
    git submodule add git://git.openwrt.org/openwrt.git openwrt
    git submodule add git://git.openwrt.org/packages.git packages
    git submodule add git://git.openwrt.org/project/luci.git luci
    git submodule add git://github.com/openwrt-routing/packages.git routing
    git commit -m "openwrt-Repositories als Submodule eingebunden"


Ein erster Patch: Paket-Feeds einbinden
---------------------------------------

    mkdir oni-packages
    mkdir patches
    # neuen Patch beginnen
    quilt new oni-feeds.patch
    # die (nicht existierende) Datei feeds.conf zur Beobachtung bei quilt anmelden
    quilt add openwrt/feeds.conf
    # die feeds-Datei mit Inhalten füllen
    cat - >openwrt/feeds.conf <<-EOF
    	src-link        opennet         ../opennet
    	src-link        packages        ../packages
    	src-link        routing         ../routing
    	src-link        luci            ../luci
    EOF
    # den Patch entsprechend der Dateiveränderungen aktualisieren
    quilt refresh
    # Patch beschreiben
    quilt header -e
    # Patch committen
    git add patches
    git commit -m "ein erster Patch: Paket-Feeds einbinden"

