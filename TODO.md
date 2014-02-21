Offene Aufgaben
===============

ondataservice integrieren
-------------------------

Das ondataservice-Plugin ist noch nicht in den Feeds  sichtbar. Ein Teild des Patch muss auf das Makefile angewandt werden.


Konfigurationsdateien
---------------------

In den opennet-Paketen muessen die Konfigurationsdateien explizit genannt werden.


Sonstiges
---------

ID-Setzen fuehrt zu:

    This page contains the following errors:
    error on line 119 at column 57: expected '>'
    Below is a rendering of the page up to the first error.

Falsche IP beim Start

DHCP laeuft erst nach Neustart


Unklarheiten
============

luci-initialization: cronloglevel=9
-----------------------------------

im luci-Root-Verzeichnis befand sich eine Datei 'initialization' mit folgendem Inhalt:

    uci set system.@system[0].cronloglevel=9

