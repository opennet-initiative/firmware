#!/bin/sh
#
# nodogsplash muss eigene iptables-Regeln erstellen, um wirksam zu werden
# Damit diese bei einem firewall-Restart angewandt werden, muss dieses Skript
# in der firewall-Konfiguration als include aktivert sein.

is_on_module_installed_and_enabled "on-captive-portal" && on-function captive_portal_restart
true
