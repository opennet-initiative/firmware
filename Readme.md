Entwicklungsumgebung einrichten
===============================

Die Einrichtung der Entwicklungsumgebung dauert nur wenige Minuten und ist untenstehend beschrieben.
Der gesamte Prozess der Image-Erzeugung erfordert dagegen ca. 10 GB Festplattenplatz je Zielarchitektur und dauert - je nach Rechner - üblicherweise mindestens ein dutzend Stunden.


Erforderliche Pakete installieren
---------------------------------

Debian:

    apt-get update
    apt-get install build-essential git flex gcc-multilib subversion libncurses5-dev zlib1g-dev liblzo2-dev gawk unzip python quilt


Lokale Build-Umgebung einrichten
--------------------------------

    git clone https://projects.farbdev.org/opennet/on-firmware.git
    cd on-firmware
    make init

Eine spezielle Architektur (z.B. ar71xx)  kannst du bauen mit:
    
    make ar71xx

Alternativ kannst du mit folgendem Kommando die Firmware für alle Architekturen bauen:

    make all

Die Ergebnisse (Flash-Images und nachinstallierbare Pakete) findest du anschließend unter *openwrt/bin/...*.


Detaildokumentation
===================

Hier findest du Informationen zu weiterführende Details:

1. *[Struktur der Build-Umgebung] (doc/Struktur.md)*
2. *[Enwicklungsleitfaden] (doc/Entwicklung.md)*

