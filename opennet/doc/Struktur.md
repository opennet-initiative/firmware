[TOC]

Überblick {#ueberblick-struktur}
=========

Diese Dokumentation beschäftigt sich mit der Struktur der Firmware-Buildumgebung. Die Verwendung der Umgebung ist dagegen in der [Entwicklungsdokumentation] (Entwicklung.md) beschrieben.

Die Opennet-Entwicklungsumgebung ist die Zusammenfassung der OpenWrt-Repositories und ein paar weniger Opennet-Pakete.

Zusätzlich enthält sie Patches gegenüber *OpenWrt*, die es bisher noch nicht in deren Repository geschafft haben oder die zu spezifisch für Opennet sind.

Die Verzeichnisse haben die folgenden Inhalte:

* *openwrt* -- das OpenWrt-Repository (Build-Umgebung, Kernel und Basispakete)
* openwrt-Paket-Feeds:
    * *packages* -- die meisten openwrt-Pakete
    * *routing* -- Routing-Pakete
    * *luci* -- luci-basierte Webinterface-Pakete
* *opennet* -- Opennet-Pakete und angepasste/neue Pakete
* *patches* -- Änderungen an openwrt oder den externen Paket-Feeds
* *doc* -- diese Dokumentation


Externe Respositories {#repositories}
---------------------

Die externen Repositories (openwrt, packages, routing) werden von uns nur in Form von Patches angepasst.

Deren Version (also die git-commit-ID) wird in unserem Repository versioniert - der aktuelle Stand bezüglich der Upstream-Repositories ist also Teil der Versionsverwaltung.


Patches {#patches}
-------

Unsere Patches (gegen die externen Repositories) werden im Verzeichnis *patches* mittels *quilt* gepflegt. Die meisten dieser Patches sind bei openwrt eingereicht und harren auf ihre Upstream-Integration.


Unser Paket-Feed *opennet* {#feed}
--------------------------

In diesem Paket-Feed liegen unsere selbsterstellten Pakete (*on-*), die für den VPN-Tunnelaufbau und die Datensammlung erforderlich sind. Zusätzlich können hier Pakete untergebracht werden, die (noch) nicht in openwrt enthalten sind.



Historischer Rückblick: Erstellung der Entwicklungsumgebung im Jahr 2014 {#history}
========================================================================

**Die folgende Beschreibung ist nicht relevant fuer die Weiterentwicklung der Firmware.**

Die Beschreibung soll lediglich die Struktur der Firmware-Entwicklungsumgebung verdeutlichen.


Repositories verknüpfen {#history-submodules}
-----------------------

    mkdir opennet
    git init
    git submodule add git://git.openwrt.org/openwrt.git openwrt
    git submodule add git://git.openwrt.org/packages.git packages
    git submodule add git://git.openwrt.org/project/luci.git luci
    git submodule add git://github.com/openwrt-routing/packages.git routing
    git submodule add http://feeds.openwrt.nanl.de/openwrt/telephony.git telephony
    git commit -m "openwrt-Repositories als Submodule eingebunden"


Ein erster Patch: Paket-Feeds einbinden {#history-feeds}
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
