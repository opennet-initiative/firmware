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

Nun kannst du mit folgendem Kommando die aktuelle Firmware bauen:

    make all

Dieser Prozess wird (insbesondere beim ersten Mail) viele Stunden dauern, da zuerst die Cross-Compile-Toolchain für die jeweilige Zielplattform erzeugt werden muss.

