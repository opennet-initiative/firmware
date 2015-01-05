MIG_VPN_DIR=/etc/openvpn/opennet_user
MIG_VPN_CONNECTION_LOG=/var/log/mig_openvpn_connections.log


# Erzeuge oder aktualisiere einen mig-Service.
# Ignoriere doppelte Eintraege.
# Anschliessend muss "on-core" comitted werden.
update_mig_service() {
	local service_name="$1"
	local template_file=/usr/share/opennet/openvpn-mig.template
	local pid_file="/var/run/${service_name}.pid"
	local config_file="$OPENVPN_CONFIG_BASEDIR/${service_name}.conf"
	set_service_value "$service_name" "template_file" "$template_file"
	set_service_value "$service_name" "config_file" "$config_file"
	set_service_value "$service_name" "pid_file" "$pid_file"
}


# Pruefe, ob ein Verbindungsaufbau mit einem openvpn-Service moeglich ist.
# Parameter: Service-Name
# Resultat: exitcode=0 falls der Test erfolgreich war
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
		if verify_vpn_connection "$service_name" "true" \
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


# aktiviere den uebergebenen Gateway
# Seiteneffekt: Beraeumung aller herumliegenden Konfigurationen von alten Verbindungen
select_mig_connection() {
	local wanted="$1"
	local one_service
	get_sorted_services gw ugw | while read one_service; do
		# loesche Flags fuer die Vorselektion
		set_service_value "$one_service" "switch_candidate_timestamp" ""
		# erst nach der Abschaltung der alten Dienste wollen wir den/die neuen Dienste anschalten (also nur Ausgabe)
		[ "$one_service" = "$wanted" ] && echo "$one_service" && continue
		disable_openvpn_service "$one_service" || true
	done | while read one_service; do
		enable_openvpn_service "$wanted" "true"
	done
}


# Ermittle den besten Gateway und pruefe, ob ein Wechsel sinnvoll ist.
# Der erste (optionale) Parameter erlaubt den zwangsweisen Wechsel auf den besten Gateway (unabhaengig von Wartezeiten).
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


# Liefere die aktiven VPN-Verbindungen (mit Mesh-Internet-Gateways) zurueck.
# Diese Funktion braucht recht viel Zeit.
get_active_mig_connections() {
	local service_name
	get_sorted_services gw ugw | while read service_name; do
		is_openvpn_service_active "$service_name" && echo "$service_name" || true
	done
}


# Loesche den Zeitstempel des letztes VPN-Verbindungstests. Beim naechsten Durchlauf wird diese Verbindung
# erneut geprueft.
reset_mig_connection_test_timestamp() {
	service_name="$1"
	set_service_value "$service_name" "timestamp_connection_test" ""
}


reset_all_mig_connection_test_timestamps() {
	local service_name
	get_sorted_services gw ugw | while read service_name; do
		reset_mig_connection_test_timestamp "$service_name"
	done
}


get_mig_connection_test_age() {
	local service_name
	local timestamp=$(get_service_value "$service_name" "timestamp_connection_test")
	# noch keine Tests durchgefuehrt?
	[ -z "$timestamp" ] && return 0
	local now=$(get_time_minute)
	echo "$timestamp" "$now" | awk '{ print $2 - $1 }'
}


append_to_mig_connection_log() {
	local event="$1"
	local msg="$2"
	echo "$(date) openvpn [$event]: $msg" >>"$MIG_VPN_CONNECTION_LOG"
	# Datei kuerzen, falls sie zu gross sein sollte
	local filesize=$(get_filesize "$MIG_VPN_CONNECTION_LOG")
	[ "$filesize" -gt 10000 ] && sed -i "1,30d" "$MIG_VPN_CONNECTION_LOG"
	return 0
}


# Liefere den Inhalt des Nutzer-VPN-Verbindungsprotokolls (Aufbau + Trennung) zurueck
get_mig_connection_log() {
	[ -e "$MIG_VPN_CONNECTION_LOG" ] && cat "$MIG_VPN_CONNECTION_LOG" || true
}


# Gelegentlich bleiben nach einem reboot openvpn-Konfigurationen liegen, die durch schlechtes Timing nie geloescht werden.
# Der dazugehoerige Ablauf ist folgender:
#   1) eine VPN-Verbindung war beim Abschalten aktiv
#   2) nach dem Booten wird eine andere VPN-Verbindung ausgewaehlt
#    * zu diesem Zeitpunkt wurde die vorher aktive Verbindung noch nicht via olsrd-nameservice entdeckt
#    * somit wurde die Verbindung nicht via 'select_mig_connection' beraeumt
#   3) die unbrauchbare VPN-Verbindung bleibt liegen und fuehrt im Minutentakt zu einer Fehlermeldung des openvpn-Dienstes
cleanup_stale_openvpn_services() {
	local service_name
	local config_file
	(get_services "service=gw"; get_services "service=ugw") | while read service_name; do
		# existiert nicht?
		[ -z "$(uci_get "openvpn.$service_name")" ] && continue
		config_file=$(uci_get "openvpn.${service_name}.config")
		# falls die Datei nicht existiert, koennen wir die Konfiguration loeschen
		[ -e "$config_file" ] || uci_delete "openvpn.$service_name"
	done
	apply_changes openvpn
}

