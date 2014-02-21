Offene Aufgaben
===============

ondataservice integrieren
-------------------------

Das ondataservice-Plugin ist noch nicht in den Feeds  sichtbar. Ein Teild des Patch muss auf das Makefile angewandt werden.


Konfigurationsdateien
---------------------

In den opennet-Paketen muessen die Konfigurationsdateien explizit genannt werden.


Unklarheiten
============

luci-initialization: cronloglevel=9
-----------------------------------

im luci-Root-Verzeichnis befand sich eine Datei 'initialization' mit folgendem Inhalt:

    uci set system.@system[0].cronloglevel=9

