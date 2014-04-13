Abhaengigkeiten
===============

* aptitude install qemu mtd-utils mkfs.jffs2 sudo socat kvm vde2
* aptitude install python-paramiko python-dnspython python-mechanize
* aptitude install python-zope.testbrowser python-ipcalc

Als VNC-Viewer ist ssvncviewer (Paket "ssvnc") empfehlenswert, da er Unix-Sockets (anstelle von Ports) unterstützt.

Leider gibt es ein Problem mit vde_pcapplug und libpcap0.8 (v1.5): https://sourceforge.net/p/vde/bugs/74/
Workaround: aptitude install libpcap0.8/wheezy

ONI-TESTER benötigt besondere Rechte. Daher ist es sinnvoll einen normalen Nutzer in sudoers hinzuzufügen mit der Berechtigung die folgenden Programme starten zu dürfen: 
 /usr/bin/vde_pcapplug
 /usr/bin/vde_plug2tap
 /sbin/ifconfig

Aufgaben
========

* web-basierte VNC-Verwendung mit novnc
* vncsnapshot

