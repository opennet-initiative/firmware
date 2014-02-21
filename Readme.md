Entwicklungsumgebung einrichten
===============================

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

Dieser Prozess wird (insbesondere beim ersten Mal) viele Stunden dauern, da zuerst die Cross-Compile-Toolchain für die jeweilige Zielplattform erzeugt werden muss.

