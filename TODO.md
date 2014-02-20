Offene Aufgaben
===============

Übersetzungen
-------------

siehe luci/Makefile:
 
    i18nbuild:
            mkdir -p host/lua-po
            ./build/i18n-po2lua.pl ./po host/lua-po

Wahrscheinlich muss in jedem uebersetzungsfaehigen Paket die obige Zeile in der Build-Anweisung eingetragen werden.


ondataservice integrieren
-------------------------


Unklarheiten
============

luci-initialization: cronloglevel=9
-----------------------------------

im luci-Root-Verzeichnis befand sich eine Datei 'initialization' mit folgendem Inhalt:

    uci set system.@system[0].cronloglevel=9

