## @defgroup on-openvpn Nutzer-Tunnel
## @brief Alles rund um die Nutzertunnel-Verbindung: Tests, Auswahl, Aufbau, Abbau, Portweiterleitungen und Logs.
# Beginn der Doku-Gruppe
## @{

MIG_VPN_DIR=/etc/openvpn/opennet_user
MIG_VPN_CONNECTION_LOG=/var/log/mig_openvpn_connections.log


## @fn get_on_openvpn_default()
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-openvpn).
## @param key Name des Schlüssels
## @sa get_on_core_default
get_on_openvpn_default() {
	_get_file_dict_value "$ON_OPENVPN_DEFAULTS_FILE" "$1"
}


## @fn update_mig_service()
## @param Name eines Diensts
## @brief Erzeuge oder aktualisiere einen Mesh-Internet-Gateway-Dienst Ignoriere doppelte Einträge.
## @attention Anschließend muss "on-core" comitted werden.
update_mig_service() {
	local service_name="$1"
	local template_file=/usr/share/opennet/openvpn-mig.template
	local pid_file="/var/run/${service_name}.pid"
	local config_file="$OPENVPN_CONFIG_BASEDIR/${service_name}.conf"
	set_service_value "$service_name" "template_file" "$template_file"
	set_service_value "$service_name" "config_file" "$config_file"
	set_service_value "$service_name" "pid_file" "$pid_file"
}


## @fn test_mig_connection()
## @brief Prüfe, ob ein Verbindungsaufbau mit einem openvpn-Dienst möglich ist.
## @param Name eines Diensts
## @returns exitcode=0 falls der Test erfolgreich war
## @attention Seiteneffekt: die Zustandsinformationen des Diensts (Status, Test-Zeitstempel) werden verändert.
test_mig_connection() {
	trap "error_trap test_mig_connection '$*'" $GUARD_TRAPS
	local service_name="$1"
	# sicherstellen, dass alle vpn-relevanten Einstellungen gesetzt wurden
	update_mig_service "$service_name"
	local host=$(get_service_value "$service_name" "host")
	local timestamp=$(get_service_value "$service_name" "timestamp_connection_test")
	local recheck_age=$(get_on_openvpn_default vpn_recheck_age)
	local now=$(get_time_minute)
	local nonworking_timeout=$(($recheck_age + $(get_on_openvpn_default vpn_nonworking_timeout)))
	local status=$(get_service_value "$service_name" "status")
	if [ -n "$timestamp" ] && is_timestamp_older_minutes "$timestamp" "$nonworking_timeout"; then
		# if there was no vpn-availability for a while (nonworking_timeout minutes), declare vpn-status as not working
		set_service_value "$service_name" "status" "n"
		# In den naechsten 'vpn_recheck_age' Minuten wollen wir keine Pruefungen durchfuehren.
		set_service_value "$service_name" "timestamp_connection_test" "$now"
		trap "" $GUARD_TRAPS && return 1
	elif [ -z "$timestamp" ] || [ -z "$status" ] || is_timestamp_older_minutes "$timestamp" "$recheck_age"; then
		# Neue Pruefung, falls:
		# 1) noch nie eine Pruefung stattfand
		# oder
		# 2) die "recheck"-Zeit abgelaufen ist
		# oder
		# 3) falls bisher noch kein definitives Ergebnis feststand (dies ist nur innerhalb
		#    der ersten "recheck" Minuten nach dem Booten moeglich).
		# In jedem Fall kann der Zeitstempel gesetzt werden - egal welches Ergebnis die Pruefung hat.
		if verify_vpn_connection "$service_name" "host" \
				"$VPN_DIR_TEST/on_aps.key" \
				"$VPN_DIR_TEST/on_aps.crt" \
				"$VPN_DIR_TEST/opennet-ca.crt"; then
			msg_debug "vpn-availability of gw $host successfully tested"
			set_service_value "$service_name" "status" "y"
			set_service_value "$service_name" "timestamp_connection_test" "$now"
			return 0
		else
			# kein Zeitstempel? Dann muessen wir beginnen zu zaehlen, damit der
			# Test irgendwann in den "broken"-Zustand uebergehen kann.
			[ -z "$timestamp" ] && set_service_value "$service_name" "timestamp_connection_test" "$now"
			# Solange wir keinen "status" setzen, wird der Test bei jedem Lauf wiederholt, bis "nonworking_timeout"
			# erreicht ist.
			msg_debug "vpn test of $host failed"
			trap "" $GUARD_TRAPS && return 1
		fi
	elif uci_is_true "$status"; then
		msg_debug "vpn-availability of gw $host still valid"
		return 0
	else
		# gateway is currently known to be broken
		trap "" $GUARD_TRAPS && return 1
	fi
}


## @fn select_mig_connection()
## @brief Aktiviere den angegebenen VPN-Gateway
## @param Name eines Diensts
## @attention Seiteneffekt: Beräumung aller herumliegenden Konfigurationen von alten Verbindungen.
select_mig_connection() {
	local wanted="$1"
	local one_service
	get_services "gw" "ugw" | while read one_service; do
		# loesche Flags fuer die Vorselektion
		set_service_value "$one_service" "switch_candidate_timestamp" ""
		# erst nach der Abschaltung der alten Dienste wollen wir den/die neuen Dienste anschalten (also nur Ausgabe)
		[ "$one_service" = "$wanted" ] && echo "$one_service" && continue
		disable_openvpn_service "$one_service" || true
	done | while read one_service; do
		enable_openvpn_service "$wanted" "host"
	done
}


## @fn find_and_select_best_gateway
## @brief Ermittle den besten Gateway und prüfe, ob ein Wechsel sinnvoll ist.
## @param force [optional] erzwinge den Wechsel auf den besten Gateway unabhängig von Wartezeiten (true/false)
## @ref mig-switch
find_and_select_best_gateway() {
	local force_switch_now=${1:-false}
	local service_name
	local host
	local best_gateway=
	local current_gateway=
	local result
	local current_priority
	local best_priority
	local switch_candidate_timestamp
	local now=$(get_time_minute)
	local bettergateway_timeout=$(get_on_openvpn_default vpn_bettergateway_timeout)
	msg_debug "Trying to find a better gateway"
	# suche nach dem besten und dem bisher verwendeten Gateway
	# Ignoriere dabei alle nicht-verwendbaren Gateways.
	result=$(get_sorted_services gw ugw | filter_enabled_services | while read service_name; do
		# Ist der beste und der aktive Gateway bereits gefunden? Dann einfach weiterspringen ...
		# (kein Abbruch der Schleife - siehe weiter unten - Stichwort SIGPIPE)
		[ -n "$current_gateway" ] && continue
		host=$(get_service_value "$service_name" "host")
		uci_is_false "$(get_service_value "$service_name" "status" "false")" && \
			msg_debug "$host did not pass the last test" && \
			continue
		# der Gateway ist ein valider Kandidat
		# Achtung: Variablen innerhalb einer "while"-Sub-Shell wirken sich nicht auf den Elternprozess aus
		# Daher wollen wir nur ein bis zwei Zeilen:
		#   den besten
		#   [den aktiven] (falls vorhanden)
		# Wir brechen die Ausgabe jedoch nicht nach den ersten beiden Zeilen ab. Andernfalls muessten wir
		# uns um das SIGPIPE-Signal kuemmern (vor allem in cron-Jobs).
		[ -z "$best_gateway" ] && best_gateway="$service_name" && echo "$best_gateway"
		is_openvpn_service_active "$service_name" && current_gateway="$service_name" && echo "$service_name" || true
	done)
	best_gateway=$(echo "$result" | sed -n 1p)
	current_gateway=$(echo "$result" | sed -n 2p)
	if [ "$current_gateway" = "$best_gateway" ]; then
		if [ -z "$current_gateway" ]; then
			msg_debug "There is still no usable gateway around"
		else
			msg_debug "Current gateway ($current_gateway) is still the best choice"
			# Wechselzaehler zuruecksetzen (falls er hochgezaehlt wurde)
			set_service_value "$current_gateway" "switch_candidate_timestamp" ""
		fi
		return 0
	fi
	msg_debug "Current ($current_gateway) / best ($best_gateway)"
	# eventuell wollen wir den aktuellen Host beibehalten (sofern er funktioniert und wir nicht zwangsweise wechseln)
	if [ -n "$current_gateway" ] \
			&& uci_is_false "$force_switch_now" \
			&& uci_is_true "$(get_service_value "$current_gateway" "status" "false")"; then
		# falls der beste und der aktive Gateway gleich weit entfernt sind, bleiben wir beim bisher aktiven
		current_priority=$(get_service_priority "$current_gateway")
		best_priority=$(get_service_priority "$best_gateway")
		[ "$current_priority" -eq "$best_priority" ] \
			&& msg_debug "Keeping current gateway since the best gateway has the same priority" \
			&& return 0
		# falls der beste und der aktive Gateway gleich weit entfernt sind, bleiben wir beim bisher aktiven
		# Haben wir einen besseren Kandidaten? Muessen wir den Wechselzaehler aktivieren?
		# Zaehle hoch bis der switch_candidate_timestamp alt genug ist
		switch_candidate_timestamp=$(get_service_value "$current_gateway" "switch_candidate_timestamp")
		if [ -z "$switch_candidate_timestamp" ]; then
			# wir bleiben beim aktuellen Gateway - wir merken uns allerdings den Switch-Zeitstempel
			set_service_value "$current_gateway" "switch_candidate_timestamp" "$now"
			msg_debug "Starting to count down until the switching timer reaches $bettergateway_timeout minutes"
			return 0
		else
			# noch nicht alt genug fuer den Wechsel?
			is_timestamp_older_minutes "$switch_candidate_timestamp" "$bettergateway_timeout" \
				|| { msg_debug "Counting down further until we reach $bettergateway_timeout minutes"; return 0; }
		fi
	fi
	# eventuell kann hier auch ein leerer String uebergeben werden - dann wird kein Gateway aktiviert (korrekt)
	[ -n "$best_gateway" ] \
		&& msg_debug "Switching gateway from $current_gateway to $best_gateway" \
		|| msg_debug "Disabling $current_gateway without a viable alternative"
	select_mig_connection "$best_gateway"
}


## @fn get_active_mig_connections()
## @brief Liefere die aktiven VPN-Verbindungen (mit Mesh-Internet-Gateways) zurück.
## @returns Liste der Namen aller Dienste, die aktuell eine aktive VPN-Verbindung halten.
## @attention Diese Funktion braucht recht viel Zeit.
get_active_mig_connections() {
	local service_name
	get_services "gw" "ugw" | while read service_name; do
		is_openvpn_service_active "$service_name" && echo "$service_name" || true
	done
}


## @fn reset_mig_connection_test_timestamp()
## @brief Löse eine erneute Prüfung dieses Gateways beim nächsten Prüflauf aus.
## @param Name eines Diensts
## @details Das Löschen des *timestamp_connection_test* Werts führt zu einer
##   erneuten Prüfung zum nächstmöglichen Zeitpunkt.
reset_mig_connection_test_timestamp() {
	local service_name="$1"
	set_service_value "$service_name" "timestamp_connection_test" ""
}


## @fn reset_all_mig_connection_test_timestamps()
## @brief Löse eine erneute Prüfung aller Gateways zum nächstmöglichen Zeitpunkt aus.
## @sa reset_mig_connection_test_timestamp
reset_all_mig_connection_test_timestamps() {
	local service_name
	get_services gw ugw | while read service_name; do
		reset_mig_connection_test_timestamp "$service_name"
	done
}


## @fn get_mig_connection_test_age()
## @brief Ermittle das Test des letzten Verbindungstests in Minuten.
## @returns Das Alter des letzten Verbindungstests in Minuten oder nichts (falls noch kein Test durchgeführt wurde).
## @details Anhand des Test-Alters lässt sich der Zeitpunkt der nächsten Prüfung abschätzen.
get_mig_connection_test_age() {
	local service_name="$1"
	local timestamp=$(get_service_value "$service_name" "timestamp_connection_test")
	# noch keine Tests durchgefuehrt?
	[ -z "$timestamp" ] && return 0
	local now=$(get_time_minute)
	echo "$timestamp" "$now" | awk '{ print $2 - $1 }'
}


## @fn append_to_mig_connection_log()
## @brief Hänge eine neue Nachricht an das Nutzer-VPN-Verbindungsprotokoll an.
## @param event die Kategorie der Meldung (up/down/other)
## @param msg die textuelle Beschreibung des Ereignis (z.B. "connection with ... closed")
## @details Die Meldungen werden von den konfigurierten openvpn-up/down-Skripten gesendet.
append_to_mig_connection_log() {
	local event="$1"
	local msg="$2"
	echo "$(date) openvpn [$event]: $msg" >>"$MIG_VPN_CONNECTION_LOG"
	# Datei kuerzen, falls sie zu gross sein sollte
	local filesize=$(get_filesize "$MIG_VPN_CONNECTION_LOG")
	[ "$filesize" -gt 10000 ] && sed -i "1,30d" "$MIG_VPN_CONNECTION_LOG"
	return 0
}


## @fn get_mig_connection_log()
## @brief Liefere den Inhalt des VPN-Verbindungsprotokolls.
# Liefere den Inhalt des Nutzer-VPN-Verbindungsprotokolls (Aufbau + Trennung) zurueck
get_mig_connection_log() {
	[ -e "$MIG_VPN_CONNECTION_LOG" ] && cat "$MIG_VPN_CONNECTION_LOG" || true
}


## @fn cleanup_stale_openvpn_services()
## @brief Beräumung liegengebliebener openvpn-Konfigurationen, sowie Deaktivierung funktionsunfähiger Verbindungen.
## @details Verwaiste openvpn-Konfigurationen können aus zwei Grunden auftreten:
##   1) nach einem reboot wurde nicht du zuletzt aktive openvpn-Verbindung ausgewählt - somit bleibt der vorher aktive uci-Konfigurationseintrag erhalten
##   2) ein VPN-Verbindungsaufbau scheitert und hinterlässt einen uci-Eintrag, eine PID-Datei, jedoch keinen laufenden Prozess
cleanup_stale_openvpn_services() {
	trap "error_trap cleanup_stale_openvpn_services '$*'" $GUARD_TRAPS
	local service_name
	local config_file
	local pid_file
	local uci_prefix
	find_all_uci_sections openvpn openvpn | while read uci_prefix; do
		config_file=$(uci_get "${uci_prefix}.config")
		# Keine config-Datei? Keine von uns verwaltete Konfiguration ...
		[ -z "$config_file" ] && continue
		service_name="${uci_prefix#openvpn.}"
		pid_file=$(get_service_value "$service_name" "pid_file")
		# Keine PID-Dateiangabe? Keine von uns verwaltete Konfiguration ...
		[ -z "$pid_file" ] && continue
		# Es scheint sich um eine von uns verwaltete Verbindung zu handeln.
		# Falls die config-Datei oder die pid-Datei fehlt, dann ist es ein reboot-Fragment. Wir löschen die Überreste.
		if [ ! -e "$config_file" -o ! -e "$pid_file" ]; then
			msg_info "Removing a reboot-fragment of a previously used openvpn connection: $service_name"
			disable_openvpn_service "$service_name"
		elif check_pid_file "$pid_file" "openvpn"; then
			# Prozess läuft - alles gut
			true
		else
			# Falls die PID-Datei existiert, jedoch veraltet ist (kein dazugehöriger Prozess läuft), dann
			# schlug der Verbindungsaufbau fehlt (siehe "tls-exit" und "single-session").
			# Wir markieren die Verbindung als kaputt.
			msg_info "Marking a possibly interrupted openvpn connection as broken: $service_name"
			set_service_value "$service_name" "status" "n"
			reset_mig_connection_test_timestamp "$service_name"
			disable_openvpn_service "$service_name"
		fi
	done
	apply_changes openvpn
}


## @fn get_client_cn()
## @brief Ermittle den Common-Name des Nutzer-Zertifikats.
## @details Liefere eine leere Zeichenkette zurück, falls kein Zertifikat vorhanden ist.
get_client_cn() {
	[ -e "$MIG_VPN_DIR/on_aps.crt" ] || return 0
	openssl x509 -in "$MIG_VPN_DIR/on_aps.crt" \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}


## @fn get_mig_port_forward_range()
## @brief Liefere den ersten und letzten Port der Nutzertunnel-Portweiterleitung zurück.
## @param [optional] common name des Nutzer-Zertifikats
## @returns zwei Zahlen durch Tabulatoren getrennt
## @details Jeder AP bekommt einen Bereich von zehn Ports fuer die Port-Weiterleitung zugeteilt.
get_mig_port_forward_range() {
	local client_cn=${1:-}
	[ -z "$client_cn" ] && client_cn=$(get_client_cn)
	local port_count=10
	local cn_address=
	local portbase
	local first_port
	local last_port

	[ -z "$client_cn" ] && msg_debug "$(basename "$0"): failed to get Common Name - maybe there is no certificate?" && return 0

	if echo "$client_cn" | grep -q '^\(\(1\.\)\?[0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=10000
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\([0-9][0-9]\?[0-9]\?\.mobile\.on\)$'; then
		portbase=12550
		cn_address=${client_cn%.mobile.on}
	elif echo "$client_cn" | grep -q '^\(2[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=15100
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\(3[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=20200
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	fi

	if [ -z "$cn_address" ] || [ "$cn_address" -lt 1 ] || [ "$cn_address" -gt 255 ]; then
		msg_info "$(basename "$0"): invalidate certificate Common Name ($client_cn)"
		trap "" $GUARD_TRAPS && return 1
	fi

	first_port=$((portbase + (cn_address-1) * port_count))
	last_port=$((first_port + port_count - 1))
	echo -e "$first_port\t$last_port"
}

# Ende der Doku-Gruppe
## @}
