## @defgroup devel Entwicklungswerkzeuge
## @brief Funktionen, die lediglich für die Firmware-Entwicklung, nicht jedoch zur Laufzeit nützlich sind.
# Beginn der Doku-Gruppe
## @{


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

# Ende der Doku-Gruppe
## @}
