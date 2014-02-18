Entwicklungsumgebung einrichten
===============================

    git clone git@projects.farbdev.org:opennet/on-firmware.git
    cd on-firmware
    git submodule init
    git submodule update


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


Eine Datei in den Paket-Repositories ändern
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


openwrt-Repositories
--------------------

1. alle Patches zurücknehmen:

        quilt pop -a

2. in das Repository-Verzeichnis wechseln und zum gewünschten Commit wechseln:

        cd openwrt; git checkout FOO; cd ..

3. Patches wieder anwenden:

        quilt push -a

4. herumprobieren

5. falls der Commit als aktueller Repository-Zustand gespeichert werden soll, dann committen:

        git commit openwrt


Rückblick: Initialisierung der Entwicklungsumgebung
===================================================

Die folgende Beschreibung ist nicht relevant fuer die Weiterentwicklung der Firmware. Sie bietet jedoch einen schnellen Einstieg in die Struktur der Firmware-Entwicklungsumgebung.

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

