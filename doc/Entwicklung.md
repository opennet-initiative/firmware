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

    git remote set-url origin git@dev.opennet-initiative.de:on_firmware.git



Änderungen an der Firmware vornehmen
====================================

Änderungen im Opennet-Repository auf den Server pushen
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


Änderungen vom entfernten git-Repository lokal pullen
-----------------------------------------------------

Prinzipiell ist die Arbeit mit dem opennet-Repository identisch mit dem üblichen Umgang mit git-Arbeitsumgebungen.
Lediglich die *quilt*-Patches führen unter besonderen Bedingungen zu einem leicht geänderten Verhalten.
Daher wird anstelle des üblichen `git pull` folgende Abfolge empfohlen:

    # lokale Patches zurücknehmen (vermeidet Konflikte, falls Patch-Dateien geändert werden)
    make unpatch
    # entfernte Änderungen 
    git pull --rebase


**Achtung**: `git pull --rebase` manipuliert deine lokale git-History. Falls du frische lokale Commits also bereits zu einem anderen Server übertragen haben solltest, dann führt dies zu unüberschaubaren Chaos. Verzichte in diesem Fall auf `--rebase`.



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


Paket-Repositories oder das openwrt-Repository aktualisieren
------------------------------------------------------------

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
    # Patch-Datei aktualisieren
    quilt refresh
    # den neuen Patch in das Repository hochladen
    git commit patches/oni-feeds.patch -m "andere feeds-Dinge hinzugefügt"


Einzelnes Paket bauen
---------------------

Für die schnelle Lösung von Build-Problemen ist es oft sinnvoll, nur das eine problematische Paket erstellen zu lassen:

    make -C openwrt packages/feeds/opennet/on-core/{clean,compile} V=s
 

Neue Pakete oder Paketoptionen einbinden
----------------------------------------

Die Liste vorhandener Pakete und ihrer Einstellungen wird mit dem *feeds*-Skript von openwrt verwaltet. Die Feeds werden mittels des meta-Makefile vor jedem Build und vor jedem Aufruf von `make menuconfig` aktualisiert. Du kannst dies jedoch auch manuell auslösen:

    make feeds


Fehler beim Build analysieren
-----------------------------

Eine detaillierte Fehlerausgabe erhältst mit der make-Zugabe von `V=s`:

    make ar71xx V=s

Dabei erleichtert es den Überblick deutlich, wenn du parallele Build-Prozess (z.B. `-j 3`) *nicht* verwendest. Andernfalls musst du eventuell ein paar Seiten in der Build-Ausgabe zurückblättern, um die Fehlermeldung zu finden.


Parallele Build-Prozesse für Mehr-Kern-Prozessoren
--------------------------------------------------

Wie üblich in make-Buildumgebung kannst du manuell mehrere parallele Prozesse für den Paketbau verwenden. Als Faustregel wird üblicherweise ein Wert von *Anzahl der Kerne + 1* empfohlen. Bei einem vier-Kern-Rechner wäre dies folgende Zeile:

    make -j 5

In den ersten 20 Zeilen der Build-Ausgabe wirst du ein paar Fehlermeldung bezüglich `-j1` finden - diese sind ein Indikator für eine openwert-spezifische Unfeinheit. Der finale Build-Prozess wird ungeachtet dieser Warnungen parallelisiert ablaufen.


Build-Konfiguration (menuconfig)
================================

Die opennet-Entwicklungsumgebung verwendet grundlegend die Abläufe der openwrt-Buildumgebung. Es gibt jedoch ein paar Besonderheiten, bzw. Komfortfunktionen.

Da die opennet-Firmware verschiedene Ziel-Plattformen (ar71xx, ixp44, x86, ...) unterstützt, müssen verschiedene Konfigurationen gepflegt werden. Zur Erleichterung der Pflege und zur Vermeidung von Doppelungen gibt es für jede Ziel-Plattform eine separate Datei (z.B. *on-configs/ar71xx*), sowie eine Datei mit Einstellungen, die für alle Zielplattformen gelten (*on-configs/common*). Letztere sind für den Entwicklungsprozess wohl die interessanteren.


Konfiguration für eine Plattform erstellen
------------------------------------------

Die finale openwrt-Konfiguration wird aus der Ziel-Plattform-Konfiguration und der allgemeinen Konfiguration erstellt und anschließend mittels `make defconfig` durch openwrt auf Aufabhängigkeiten zu prüfen und mit den Standardwerten aufzufüllen.

Diese Konfiguration für eine Plattform kann beispielsweise mittels `make config-arx71xx` erstellt werden. Das Ergebnis ist anschließend als *openwrt/.config* verfügbar.


Konfigurationsänderungen betrachten
-----------------------------------

Zur verbesserten Überschaubarkeit von Einstellungsänderungen ist in dem meta-Makefile ein Target namens `diff-menuconfig` integriert. Es zeigt dir nach dem Ausführen des gewohnten `make -C openwrt menuconfig` den Unterschied zwischen der vorherigen und der gespeicherten Konfiguration in Form eines diffs an.



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

