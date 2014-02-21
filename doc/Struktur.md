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
    	src-link        opennet         ../../opennet
    	src-link        packages        ../../packages
    	src-link        routing         ../../routing
    	src-link        luci            ../../luci
	src-link	telephony	../../telephony
    EOF
    # den Patch entsprechend der Dateiveränderungen aktualisieren
    quilt refresh
    # Patch beschreiben
    quilt header -e
    # Patch committen
    git add patches
    git commit -m "ein erster Patch: Paket-Feeds einbinden"
