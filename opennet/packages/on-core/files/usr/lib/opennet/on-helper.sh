#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# Copyright 2014 Lars Kruse <devel@sumpfralle.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	http://www.apache.org/licenses/LICENSE-2.0
#

# Abbruch bei:
#  u = undefinierten Variablen
#  e = Fehler
set -eu

# fuer Entwicklungszwecke: uebermaessig ausfuehrliche Ausgabe aktivieren
[ "${ON_DEBUG:-}" = "1" ] && set -x


GATEWAY_STATUS_FILE=/tmp/on-openvpn_gateways.status
ON_CORE_DEFAULTS_FILE=/usr/share/opennet/core.defaults
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
ON_WIFIDOG_DEFAULTS_FILE=/usr/share/opennet/wifidog.defaults
DNSMASQ_SERVERS_FILE_DEFAULT=/var/run/dnsmasq.servers
# leider, leider unterstuetzt die busybox-ash kein trap "ERR"
GUARD_TRAPS=EXIT
VPN_DIR_TEST=/etc/openvpn/opennet_vpntest
OPENVPN_CONFIG_BASEDIR=/var/etc/openvpn

DEBUG=${DEBUG:-}

# siehe Entwicklungsdokumentation (Entwicklungshinweise -> Shell-Skripte -> Fehlerbehandlung)
trap "error_trap __main__ '$*'" $GUARD_TRAPS


# Schreibe eine log-Nachricht bei fehlerhaftem Skript-Abbruch
# Uebliche Parameter sind der aktuelle Funktionsname, sowie Parameter der aufgerufenen Funktion.
# Jede nicht-triviale Funktion sollte zu Beginn folgende Zeile enthalten:
#    trap "error_trap FUNKTIONSNAME_HIER_EINTRAGEN '$*'" $GUARD_TRAPS
error_trap() {
	# dies ist der Exitcode des Skripts (im Falle der EXIT trap)
	local exitcode=$?
	local message="ERROR [trapped]: '$*'"
	[ "$exitcode" = 0 ] && exit 0
	msg_info "$message"
	echo >&2 "$message"
	exit "$exitcode"
}


# Module laden
for fname in core.sh network.sh olsr.sh routing.sh uci.sh services.sh openvpn.sh on-openvpn.sh on-usergw.sh; do
	fname=${IPKG_INSTROOT:-}/usr/lib/opennet/$fname
	[ -e "$fname" ] && . "$fname" || true
done

