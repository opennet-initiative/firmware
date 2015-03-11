## @defgroup devel Entwicklungswerkzeuge
## @brief Funktionen, die lediglich für die Firmware-Entwicklung, nicht jedoch zur Laufzeit nützlich sind.
# Beginn der Doku-Gruppe
## @{


# Ablage fuer profiling-Ergebnisse
PROFILING_DIR=/var/run/on-profiling


## @fn list_installed_packages_by_size()
## @brief Zeige alle installierten Pakete und ihren Größenbedarf an.
## @details Dies erlaubt die Analyse des Flash-Bedarfs.
list_installed_packages_by_size() {
	local fname
	find /usr/lib/opkg/info/ -type f -name "*.control" | while read fname; do
		grep "Installed-Size:" "$fname" \
			| awk '{print $2, "\t", "'$(basename "${fname%.control}")'" }'
	done | sort -n | awk 'BEGIN { summe=0 } { summe+=$1; print $0 } END { print summe }'
}


## @fn clean_luci_restart()
## @brief Starte den Webserver neu und lösche alle luci-Cache-Dateien und Kompilate.
## @details Diese Funktion sollte nach Änderungen von luci-Templates oder -Code ausgeführt werden.
clean_luci_restart() {
	/etc/init.d/uhttpd stop
	rm -rf /var/luci-*
	/etc/init.d/uhttpd start
}


## @fn run_httpd_debug()
## @brief Starte den Webserver im Debug-Modus zur Beobachtung von lua/luci-Ausgaben.
## @details
run_httpd_debug() {
	/etc/init.d/uhttpd stop 2>/dev/null || true
	rm -rf /var/luci-*
	# ignoriere CTRL-C (wir ueberlassen das INT-Signal dem uhttpd-Prozess)
	trap "" INT
	uhttpd -h /www -p 80 -f
	/etc/init.d/uhttpd start
}


## @fn enable_profiling()
## @brief Manipuliere die Funktionsheader in allen shell-Skripten der opennet-Pakete für das Sammeln von profiling-Informationen.
## @details Diese Operation ist irreversibel - eine erneute Installation der Pakete ist der einzige saubere Weg zurück.
##   Die Ergebnisse sind anschließend im PROFILING_DIR verfügbar.
## @see summary_profiling
enable_profiling() {
	local message=
	which bash >/dev/null || message="Failed to enable profiling - due to missing bash"
	[ -e /usr/bin/date ] || message="Failed to enable profiling - due to missing coreutils-date"
	if [ -z "$message" ]; then
		# ersetze das shebang in allen Opennet-Skripten
		cat /usr/lib/opkg/info/on-*.list | grep -E "(bin/|\.sh$|etc/cron\.|/etc/hotplug\.d/|lib/opennet)" \
			| xargs -n 200 -r sed -i -f "${IPKG_INSTROOT:-}/usr/lib/opennet/profiling.sed"
	else
		logger -t "on-profile" "$message"
		echo >&2 "$message"
		return 1
	fi
}


## @fn summary_profiling()
## @brief Werte gesammelte profiling-Informationen aus.
## @returns Jede Zeile beschreibt das kumulative Profiling einer Funktion:
##   Gesamtzeit, Anzahl der Aufrufe, durchschnittliche Verarbeitungszeit, Funktionsname
##   Die Zeiten sind jeweils in Millisekunden angegeben.
## @details Als Verarbeitungszeit einer Funktion gilt dabei der gesamte Zeitunterschied zwischen Funktionseintritt und -ende.
## @see enable_profiling
summary_profiling() {
	local fname
	local lines
	local sum
	find "$PROFILING_DIR" -type f | while read fname; do
		awk <"$fname" '
			BEGIN { summe=0; counter=0 }
			{ summe+=($1/1000); counter+=1 }
			END { printf "%16d %16d %16d %s\n", summe, counter, int(summe/counter), "'$fname'"}'
	done | sort -n
}

# Ende der Doku-Gruppe
## @}
