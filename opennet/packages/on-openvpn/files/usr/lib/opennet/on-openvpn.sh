## @defgroup on-openvpn Nutzer-Tunnel
## @brief Alles rund um die Nutzertunnel-Verbindung: Tests, Auswahl, Aufbau, Abbau, Portweiterleitungen und Logs.
# Beginn der Doku-Gruppe
## @{

MIG_OPENVPN_DIR=/etc/openvpn/opennet_user
MIG_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-mig.template
DEFAULT_MIG_PORT=1600


## @fn get_on_openvpn_default()
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-openvpn).
## @param key Name des Schlüssels
## @sa get_on_core_default
get_on_openvpn_default() {
	_get_file_dict_value "$1" "$ON_OPENVPN_DEFAULTS_FILE"
}


## @fn has_mig_openvpn_credentials()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder
##   falls in irgendeiner Form Unklarheit besteht.
has_mig_openvpn_credentials() {
	has_openvpn_credentials_by_template "$MIG_OPENVPN_CONFIG_TEMPLATE_FILE" && return 0
	trap "" $GUARD_TRAPS && return 1
}


_notify_mig_success() {
	local service_name="$1"
	set_service_value "$service_name" "status" "true"
	set_service_value "$service_name" "status_fail_counter" ""
	set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
}


_notify_mig_failure() {
	local service_name="$1"
	# erhoehe den Fehlerzaehler
	local fail_counter=$(( $(get_service_value "$service_name" "status_fail_counter" "0") + 1))
	set_service_value "$service_name" "status_fail_counter" "$fail_counter"
	# Pruefe, ob der Fehlerzaehler gross genug ist, um seinen Status auf "fail" zu setzen.
	if [ "$fail_counter" -ge "$(get_on_openvpn_default "test_max_fail_attempts")" ]; then
		# Die maximale Anzahl von aufeinanderfolgenden fehlgeschlagenen Tests wurde erreicht:
		# markiere ihn als kaputt.
		set_service_value "$service_name" "status" "false"
	elif uci_is_true "$(get_service_value "$service_name" "status")"; then
		# Bisher galt der Dienst als funktionsfaehig - wir setzen ihn auf "neutral" bis
		# die maximale Anzahl aufeinanderfolgender Fehler erreicht ist.
		set_service_value "$service_name" "status" ""
	else
		# er gilt wohl schon als fehlerhaft - das kann so bleiben
		true
	fi
	set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
}


## @fn verify_mig_gateways()
## @brief Durchlaufe die Liste der Gateways bis mindestens ein Test erfolgreich ist
## @details Die Gateways werden in der Reihenfolge ihrer Priorität geprüft.
##   Nach dem ersten Durchlauf dieser Funktion sollte also der nächstgelegene nutzbare Gateway als
##   funktionierend markiert sein.
##   Falls kein Gateway positiv getestet wurde (beispielsweise weil alle Zeitstempel zu frisch sind),
##   dann wird in jedem Fall der älteste nicht-funktionsfähige Gateway getestet. Dies minimiert die Ausfallzeit im
#    Falle einer globalen Nicht-Erreichbarkeit aller Gateways ohne auf den Ablauf der Test-Periode warten zu müssen.
## @attention Seiteneffekt: die Zustandsinformationen des getesteten Diensts (Status, Test-Zeitstempel) werden verändert.
verify_mig_gateways() {
	trap "error_trap verify_mig_gateways '$*'" $GUARD_TRAPS
	local service_name
	local timestamp
	local status
	local test_period_minutes=$(get_on_openvpn_default "test_period_minutes")
	get_services "gw" \
			| filter_reachable_services \
			| filter_enabled_services \
			| sort_services_by_priority \
			| while read service_name; do
		timestamp=$(get_service_value "$service_name" "status_timestamp" "0")
		status=$(get_service_value "$service_name" "status")
		if [ -z "$status" ] || is_timestamp_older_minutes "$timestamp" "$test_period_minutes"; then
			prepare_openvpn_service "$service_name" "$MIG_OPENVPN_CONFIG_TEMPLATE_FILE"
			if verify_vpn_connection "$service_name"; then
				msg_debug "vpn-availability of gw $(get_service_value "$service_name" "host") successfully tested"
				_notify_mig_success "$service_name"
				# wir sind fertig - keine weiteren Tests
				return
			else
				msg_debug "failed to verify vpn-availability for gw $(get_service_value "$service_name" "host")"
				_notify_mig_failure "$service_name"
			fi
			set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
		elif uci_is_false "$status"; then
			# Junge "kaputte" Gateways sind potentielle Kandidaten fuer einen vorzeitigen Test, falls
			# ansonsten kein Gateway positiv getestet wurde.
			echo "$timestamp $service_name"
		else
			# funktionsfaehige "alte" Dienste - es gibt nichts fuer sie zu tun
			true
		fi
	done | sort -n | while read timestamp service_name; do
		# Hier landen wir nur, falls alle defekten Gateways zu jung fuer einen Test waren und
		# gleichzeitig kein Gateway erfolgreich getestet wurde.
		# Dies stellt sicher, dass nach einer kurzen Nicht-Erreichbarkeit aller Gateways (z.B. olsr-Ausfall)
		# relativ schnell wieder ein funktionierender Gateway gefunden wird, obwohl alle Test-Zeitstempel noch recht
		# frisch sind.
		msg_debug "vpn-test: there is nothing to be done - thus we pick the gateway with the oldest test timestamp: $service_name"
		verify_vpn_connection "$service_name" && _notify_mig_success "$service_name" || _notify_mig_failure "$service_name"
		# wir wollen nur genau einen Test durchfuehren
		break
	done
}


## @fn select_mig_connection()
## @brief Aktiviere den angegebenen VPN-Gateway
## @param Name eines Diensts
## @attention Seiteneffekt: Beräumung aller herumliegenden Konfigurationen von alten Verbindungen.
select_mig_connection() {
	trap "error_trap select_mig_connection '$*'" $GUARD_TRAPS
	local wanted="$1"
	local one_service
	get_services "gw" | while read one_service; do
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
	trap "error_trap find_and_select_best_gateway '$*'" $GUARD_TRAPS
	local force_switch_now=${1:-false}
	local service_name
	local host
	local best_gateway=
	local current_gateway=
	local result
	local current_priority
	local best_priority
	local switch_candidate_timestamp
	local now=$(get_uptime_minutes)
	local bettergateway_timeout=$(get_on_openvpn_default vpn_bettergateway_timeout)
	msg_debug "Trying to find a better gateway"
	# suche nach dem besten und dem bisher verwendeten Gateway
	# Ignoriere dabei alle nicht-verwendbaren Gateways.
	result=$(get_services "gw" \
			| filter_reachable_services \
			| filter_enabled_services \
			| sort_services_by_priority \
			| while read service_name; do
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
	trap "error_trap get_active_mig_connections '$*'" $GUARD_TRAPS
	local service_name
	get_services "gw" | while read service_name; do
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
	get_services "gw" | while read service_name; do
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
	local now=$(get_uptime_minutes)
	echo "$timestamp" "$now" | awk '{ print $2 - $1 }'
}


## @fn get_client_cn()
## @brief Ermittle den Common-Name des Nutzer-Zertifikats.
## @details Liefere eine leere Zeichenkette zurück, falls kein Zertifikat vorhanden ist.
get_client_cn() {
	[ -e "$MIG_OPENVPN_DIR/on_aps.crt" ] || return 0
	openssl x509 -in "$MIG_OPENVPN_DIR/on_aps.crt" \
		-subject -nameopt multiline -noout 2>/dev/null | awk '/commonName/ {print $3}'
}


## @fn get_mig_port_forward_range()
## @brief Liefere den ersten und letzten Port der Nutzertunnel-Portweiterleitung zurück.
## @param [optional] common name des Nutzer-Zertifikats
## @returns zwei Zahlen durch Tabulatoren getrennt / keine Ausgabe, falls keine Main-ID gefunden wurde
## @details Jeder AP bekommt einen Bereich von zehn Ports fuer die Port-Weiterleitung zugeteilt.
get_mig_port_forward_range() {
	trap "error_trap get_mig_port_forward_range '$*'" $GUARD_TRAPS
	local client_cn=${1:-}
	[ -z "$client_cn" ] && client_cn=$(get_client_cn)
	local port_count=10
	local cn_address=
	local portbase
	local first_port
	local last_port

	[ -z "$client_cn" ] && msg_debug "get_mig_port_forward_range: failed to get Common Name - maybe there is no certificate?" && return 0

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
	else
		first_port=$((portbase + (cn_address-1) * port_count))
		last_port=$((first_port + port_count - 1))
		echo -e "$first_port\t$last_port"
	fi
}

# Ende der Doku-Gruppe
## @}
