Überblick
=========

Die Opennet-Firmware basiert auf den Komponenten *git*, *quilt* und der *openwrt*-Entwicklungsumgebung.
Links zur Dokumentation dieser Komponenten findest du am Ende dieses Dokuments.

Die grundlegende Struktur der Entwicklungsumgebung ist in der [Struktur-Dokumentation] (Struktur.md) beschrieben.
Ein Kurzeinstieg in den Bau von Firmware-Abbildern ist in der [Readme] (../Readme.md) zu finden.


Vorbereitung der Entwicklungsumgebung
=====================================

quilt-Konfiguration
-------------------

Für die komfortable Verwendung des Patch-Verwaltungsystems *quilt* sollten ein paar quilt-Einstellungen gesetzt werden.

Als dauerhafte Lösung ist folgendes möglich - dabei werden jedoch eventuell vorhandene quilt-Einstellungen gelöscht:

    cp quiltrc ~/.quiltrc

Alternativ können die Einstellungen auch zu Beginn jeder Shell-Sitzung importiert werden:

    source quiltrc

Falls die obigen Einstellungen nicht gesetzt werden, wird quilt unnötige Patch-Korrekturen vornehmen, sobald sich Zeitstempel ändern.

Dies ist nicht wünschenswert.


Umstellung der nur-lese git-URL
-------------------------------

Für das Einbringen von Änderungen in das öffentliche Firmware-Repository benötigst du einen git-Account.
Diesen kannst du auf der Opennet-Firmware-Mailingliste erfragen: https://list.opennet-initiative.de/mailman/listinfo/firmware

Sobald du einen git-Account zum pushen deiner Änderungen hast, solltest du den Upstream auf die schreibfähige URL umstellen:

    git remote set-url origin git@projects.farbdev.org:opennet/on-firmware.git


Irrelevante Dateien von git ignorieren lassen
---------------------------------------------

Füge die folgenden Zeilen in die Datei *.git/info/exclude

    \.pc


Änderungen an der Firmware vornehmen
====================================

Eine Datei im Opennet-Repository ändern
---------------------------------------
Nach dem Auschecken editiere die gewünschten Dateien. Wenn du .patch-Dateien editieren will, musst du weitere Dinge beachten (siehe andere Abschnitte). 

Um deine Änderungen einzuchecken, führe folgende Kommandos aus:

    # lokal einchecken
    git commit
    # (Versuch) Änderungen remote einzuchecken
    git push
    # Wenn es keinen Fehler gibt, bist du fertig. Glückwunsch!

    # Nun kann es sein, dass andere Personen zwischendurch Änderungen gemacht haben. Wenn dem so ist, bekommst du eine Fehlermeldung mit entsprechendem Hinweis. Dieses Problem kannst du folgendermaßen lösen. 
    # alle vorher eingespielten Patches zurückspielen
    make unpatch
    # hole alle Änderungen von remote und wende deine Änderungen darauf an
    git pull --rebase
    # deine Änderungen remote einchecken
    git push


Eine Datei im openwrt-Repository ändern
---------------------------------------

Im openwrt-Repository befindet sich das Basissystem und openwrt-spezifischer Code. Externe Pakete befinden sich (in Form von Makefiles, die auf upstream-Quellen verweisen) in den separaten Paket-Repositories.

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


Paket-Feeds oder das openwrt-Repository aktualisieren
-----------------------------------------------------

1. alle Patches zurücknehmen:

        make unpatch

2. in das Repository-Verzeichnis wechseln und zum gewünschten Commit wechseln (für spezifische commits: *git checkout*):

        cd openwrt; git pull; cd ..

3. Patches wieder anwenden:

        make patch

4. herumprobieren

5. falls der Commit als aktueller Repository-Zustand gespeichert werden soll, dann committen:

        git commit openwrt


Einen neuen Paket-Feed einbinden
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
    # Patch-Datei aktuasieren
    quilt refresh
    # den neuen Patch in das Repository hochladen
    git commit patches/oni-feeds.patch -m "andere feeds-Dinge hinzugefügt"


Einzelnes Paket bauen
---------------------

Für die schnelle Lösung von Build-Problemen ist es oft sinnvoll, nur das eine problematische Paket erstellen zu lassen:

    TOPDIR=$(pwd)/openwrt make -C opennet/packages/on-core V=99
 


Externe Dokumentationen
=======================

git
---

Die git-Doku befindet sich hier: http://git-scm.com/documentation


quilt
-----

Wir verwenden das Patch-Verwaltungssystem *quilt*. Dies erleichtert die Erstellung und Pflege von Patch-Serien gegenüber fremden Quellen.

Das Howto von *quilt* ist hier zu finden: http://repo.or.cz/w/guilt.git/blob/HEAD:/Documentation/HOWTO


openwrt
-------

Die Entwicklungsdokumentation von *openwrt* ist hier zu finden: http://wiki.openwrt.org/doc/devel/start

