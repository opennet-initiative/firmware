#!/bin/sh
#
# nodogsplash muss eigene iptables-Regeln erstellen, um wirksam zu werden
# Damit diese bei einem firewall-Restart angewandt werden, muss dieses Skript
# in der firewall-Konfiguration als include aktivert sein.

# reload genuegt nicht - nodogsplash scheint dabei keine Firewall-Regeln anzulegen
/etc/init.d/nodogsplash restart
