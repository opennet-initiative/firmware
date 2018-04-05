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


DEBUG="${DEBUG:-}"

# siehe Entwicklungsdokumentation (Entwicklungshinweise -> Shell-Skripte -> Fehlerbehandlung)
trap "error_trap __main__ '$*'" EXIT


# Schreibe eine log-Nachricht bei fehlerhaftem Skript-Abbruch
# Uebliche Parameter sind der aktuelle Funktionsname, sowie Parameter der aufgerufenen Funktion.
# Jede nicht-triviale Funktion sollte zu Beginn folgende Zeile enthalten:
#    trap "error_trap FUNKTIONSNAME_HIER_EINTRAGEN '$*'" EXIT
error_trap() {
	# dies ist der Exitcode des Skripts (im Falle der EXIT trap)
	local exitcode="$?"
	local message="ERROR [trapped]: '$*'"
	[ "$exitcode" = 0 ] && exit 0
	msg_info "$message"
	echo >&2 "$message"
	exit "$exitcode"
}


# Minimieren aller Shell-Module durch Entfernen von Kommentar- und Leerzeilen
# Alle Modul-Dateien werden gelesen, minimiert und anschliessend in eine Cache-Datei
# geschrieben. Die Zeitstempel der Shell-Module werden bei jedem Start mit dem der
# Cache-Datei verglichen und letztere bei Bedarf erneuert.
# Diese Minimierung reduziert die Laufzeit bei einfachen Funktionsaufrufen um ca. 10%. 
ON_SHELL_MINIMIZED="${IPKG_INSTROOT:-}/tmp/on_shell_modules.cache"
ON_SHELL_MODULES_DIR="${IPKG_INSTROOT:-}/usr/lib/opennet"
ON_SHELL_MODULES=$(find "$ON_SHELL_MODULES_DIR" -maxdepth 1 -type f -name "*.sh")
ON_SHELL_MODULES_NEWEST=$( (ls -dtr "$ON_SHELL_MODULES_DIR" $ON_SHELL_MODULES "$ON_SHELL_MINIMIZED" 2>/dev/null || true) | tail -1)
[ "$ON_SHELL_MODULES_NEWEST" != "$ON_SHELL_MINIMIZED" ] && \
	grep -vh "^[[:space:]]*#" $(echo "$ON_SHELL_MODULES" \
		| grep -vF "on-helper.sh") \
		| sed 's/^[[:space:]]\+//' \
		| grep -v "^$" \
		>"${ON_SHELL_MINIMIZED}.$$" && mv "${ON_SHELL_MINIMIZED}.$$" "$ON_SHELL_MINIMIZED"
. "$ON_SHELL_MINIMIZED"


clear_caches() {
	rm -f "$ON_SHELL_MINIMIZED"
	clear_cache_opennet_opkg
}
