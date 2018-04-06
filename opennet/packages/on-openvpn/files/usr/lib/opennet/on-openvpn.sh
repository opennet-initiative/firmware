## @defgroup on-openvpn Nutzer-Tunnel
## @brief Alles rund um die Nutzertunnel-Verbindung: Tests, Auswahl, Aufbau, Abbau, Portweiterleitungen und Logs.
# Beginn der Doku-Gruppe
## @{

MIG_OPENVPN_DIR=/etc/openvpn/opennet_user
MIG_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-mig.template
# shellcheck disable=SC2034
DEFAULT_MIG_PORT=1600
# Pakete mit dieser TOS-Markierung duerfen nicht in den Tunnel
# shellcheck disable=SC2034
TOS_NON_TUNNEL=8
## Quelldatei für Standardwerte des Nutzer-VPN-Pakets
ON_OPENVPN_DEFAULTS_FILE=/usr/share/opennet/openvpn.defaults
MIG_PREFERRED_SERVERS_FILE=/var/run/mig-tunnel-servers.list
# shellcheck disable=SC2034
ZONE_TUNNEL=on_vpn
# shellcheck disable=SC2034
NETWORK_TUNNEL=on_vpn
TRACEROUTE_FILENAME="traceroute_gw_cache"


## @fn get_on_openvpn_default()
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-openvpn).
## @param key Name des Schlüssels
## @sa get_on_core_default
get_on_openvpn_default() {
	local key="$1"
	_get_file_dict_value "$key" "$ON_OPENVPN_DEFAULTS_FILE"
}


## @fn has_mig_openvpn_credentials()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder
##   falls in irgendeiner Form Unklarheit besteht.
has_mig_openvpn_credentials() {
	has_openvpn_credentials_by_template "$MIG_OPENVPN_CONFIG_TEMPLATE_FILE" && return 0
	trap "" EXIT && return 1
}


## @fn verify_mig_gateways()
## @brief Durchlaufe die Liste aller Internet-Gateway-Dienste und aktualisieren deren Status.
## @see run_cyclic_service_tests
verify_mig_gateways() {
	local max_fail_attempts
	local test_period_minutes
	max_fail_attempts=$(get_on_openvpn_default "test_max_fail_attempts")
	test_period_minutes=$(get_on_openvpn_default "test_period_minutes")
	get_services "gw" | run_cyclic_service_tests "verify_vpn_connection" "$test_period_minutes" "$max_fail_attempts"
}


## @fn select_mig_connection()
## @brief Aktiviere den angegebenen VPN-Gateway
## @param wanted Name eines Diensts
## @attention Seiteneffekt: Beräumung aller herumliegenden Konfigurationen von alten Verbindungen.
select_mig_connection() {
	trap 'error_trap select_mig_connection "$*"' EXIT
	local wanted="$1"
	local found_service=0
	for one_service in $(get_services "gw"); do
		# loesche Flags fuer die Vorselektion
		set_service_value "$one_service" "switch_candidate_timestamp" ""
		# erst nach der Abschaltung der alten Dienste wollen wir den neuen Dienst anschalten
		[ "$one_service" = "$wanted" ] && found_service=1 && continue
		# alle unerwuenschten Dienste abschalten
		disable_openvpn_service "$one_service" || true
	done
	[ "$found_service" = "0" ] || enable_openvpn_service "$wanted" "host"
}


## @fn find_and_select_best_gateway()
## @brief Ermittle den besten Gateway und prüfe, ob ein Wechsel sinnvoll ist.
## @param force_switch_now [optional] erzwinge den Wechsel auf den besten Gateway unabhängig von Wartezeiten (true/false)
## @ref mig-switch
# shellcheck disable=SC2120
find_and_select_best_gateway() {
	trap 'error_trap find_and_select_best_gateway "$*"' EXIT
	local force_switch_now="${1:-false}"
	local service_name
	local host
	local best_gateway=
	local current_gateway=
	local current_priority
	local best_priority
	local switch_candidate_timestamp
	local now
	local bettergateway_timeout
	now=$(get_uptime_minutes)
	bettergateway_timeout=$(get_on_openvpn_default vpn_bettergateway_timeout)
	msg_debug "Trying to find a better gateway"
	# suche nach dem besten und dem bisher verwendeten Gateway
	# Ignoriere dabei alle nicht-verwendbaren Gateways.
	for service_name in $(get_services "gw" \
			| filter_reachable_services \
			| filter_enabled_services \
			| sort_services_by_priority); do
		host=$(get_service_value "$service_name" "host")
		uci_is_false "$(get_service_value "$service_name" "status" "false")" && \
			msg_debug "$host did not pass the last test" && \
			continue
		# dieser Gateway ist ein valider Kandidat
		[ -z "$best_gateway" ] && best_gateway="$service_name" && continue
		[ -n "$(get_openvpn_service_state "$service_name")" ] && current_gateway="$service_name" && break
	done
	if [ "$current_gateway" = "$best_gateway" ]; then
		if [ -z "$current_gateway" ]; then
			msg_debug "There is still no usable gateway around"
		else
			# gibt es eine gueltige default-Route?
			# Auf einem AP mit der v0.5.2 trat einmal eine Situation auf, in der zwei
			# OpenVPN-Prozesse gleichzeitig gestartet wurden und somit um den
			# Device-Namensraum (tun0/tun1) konkurrierten.
			# Am Ende ueberlebte der Prozess mit tun0 - allerdings hatte der tun1-Prozess
			# zuvor die default-Route ueberschrieben. Dieser Zustand ohne Internetzugang
			# war als Fehlerzustand nicht zu erkennen.
			if [ -z "$(get_target_route_interface 1.1.1.1)" ]; then
				# Durch aussergewoehnliche Umstaende (siehe oben) gibt es keine
				# default-Route. Um sicherzugehen, dass wir uns nicht gerade im
				# Verbindungsaufbau befinden, warten wir noch ein paar Sekunden und
				# starten anschliessend openvpn neu.
				sleep 20
				[ -n "$(get_target_route_interface 1.1.1.1)" ] || {
					# immer noch keine default-Route
					msg_info "Missing default route detected - restarting openvpn"
					/etc/init.d/openvpn restart || true
					return
				}
			fi
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
			if ! is_timestamp_older_minutes "$switch_candidate_timestamp" "$bettergateway_timeout"; then
				msg_debug "Counting down further until we reach $bettergateway_timeout minutes"
				return 0
			fi
		fi
	fi
	# eventuell kann hier auch ein leerer String uebergeben werden - dann wird kein Gateway aktiviert (korrekt)
	if [ -n "$best_gateway" ]; then
		msg_debug "Switching gateway from $current_gateway to $best_gateway"
	else
		msg_debug "Disabling $current_gateway without a viable alternative"
	fi
	select_mig_connection "$best_gateway"
}


## @fn get_active_mig_connections()
## @brief Liefere die aktiven VPN-Verbindungen (mit Mesh-Internet-Gateways) zurück.
## @returns Liste der Namen aller Dienste, die aktuell eine aktive VPN-Verbindung halten.
## @attention Diese Funktion braucht recht viel Zeit.
get_active_mig_connections() {
	trap 'error_trap get_active_mig_connections "$*"' EXIT
	local service_name
	for service_name in $(get_services "gw"); do
		[ "$(get_openvpn_service_state "$service_name")" != "active" ] || echo "$service_name"
	done
}


## @fn get_starting_mig_connections()
## @brief Liefere die im Aufbau befindlichen VPN-Verbindungen (mit Mesh-Internet-Gateways) zurück.
## @returns Liste der Namen aller Dienste, die aktuell beim Verbindungsaufbau sind.
## @attention Diese Funktion braucht recht viel Zeit.
get_starting_mig_connections() {
	trap 'error_trap get_starting_mig_connections "$*"' EXIT
	local service_name
	for service_name in $(get_services "gw"); do
		[ "$(get_openvpn_service_state "$service_name")" != "connecting" ] || echo "$service_name"
	done
}


## @fn reset_mig_connection_test_timestamp()
## @brief Löse eine erneute Prüfung dieses Gateways beim nächsten Prüflauf aus.
## @param service_name Name eines Diensts
## @details Das Löschen des *status_timestamp* Werts führt zu einer
##   erneuten Prüfung zum nächstmöglichen Zeitpunkt.
reset_mig_connection_test_timestamp() {
	local service_name="$1"
	set_service_value "$service_name" "status_timestamp" ""
}


## @fn reset_all_mig_connection_test_timestamps()
## @brief Löse eine erneute Prüfung aller Gateways zum nächstmöglichen Zeitpunkt aus.
## @sa reset_mig_connection_test_timestamp
reset_all_mig_connection_test_timestamps() {
	local service_name
	for service_name in $(get_services "gw"); do
		reset_mig_connection_test_timestamp "$service_name"
	done
}


## @fn get_mig_connection_test_age()
## @brief Ermittle das Test des letzten Verbindungstests in Minuten.
## @returns Das Alter des letzten Verbindungstests in Minuten oder nichts (falls noch kein Test durchgeführt wurde).
## @details Anhand des Test-Alters lässt sich der Zeitpunkt der nächsten Prüfung abschätzen.
get_mig_connection_test_age() {
	local service_name="$1"
	local timestamp
	timestamp=$(get_service_value "$service_name" "status_timestamp")
	# noch keine Tests durchgefuehrt?
	[ -z "$timestamp" ] && return 0
	echo "$timestamp" "$(get_uptime_minutes)" | awk '{ print $2 - $1 }'
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
## @param client_cn [optional] common name des Nutzer-Zertifikats
## @returns zwei Zahlen durch Tabulatoren getrennt / keine Ausgabe, falls keine Main-ID gefunden wurde
## @details Jeder AP bekommt einen Bereich von zehn Ports fuer die Port-Weiterleitung zugeteilt.
get_mig_port_forward_range() {
	trap 'error_trap get_mig_port_forward_range "$*"' EXIT
	local client_cn="${1:-}"
	[ -z "$client_cn" ] && client_cn=$(get_client_cn)
	local port_count=10
	local cn_address=
	local portbase
	local first_port

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
		# output first port and last port
		printf "%s\t%s\n" "$first_port" "$((first_port + port_count - 1))"
	fi
}


## @fn update_mig_connection_status()
## @brief Je nach Status des Moduls: prüfe die VPN-Verbindungen bis mindestens eine Verbindung
##   aufgebaut wurde bzw. trenne alle Verbindungen.
## @details Diese Funktion sollte regelmäßig als cronjob ausgeführt werden.
update_mig_connection_status() {
	if is_on_module_installed_and_enabled "on-openvpn"; then
		# die Gateway-Tests sind nur moeglich, falls ein Test-Schluessel vorhanden ist
		if has_mig_openvpn_credentials; then
			verify_mig_gateways
			# shellcheck disable=SC2119
			find_and_select_best_gateway
		fi
	else
		disable_on_openvpn
	fi
}


## @fn disable_on_openvpn()
## @brief Trenne alle laufenden oder im Aufbau befindlichen Verbindungen.
disable_on_openvpn() {
	local service_name
	local changed=0
	# möglicherweise vorhandene Verbindungen trennen und bei Bedarf openvpn neustarten
	for service_name in $(get_active_mig_connections; get_starting_mig_connections); do
		disable_openvpn_service "$service_name"
		changed=1
	done
	[ "$changed" = "0" ] || apply_changes "openvpn"
}


## @fn get_mig_tunnel_servers()
## @brief Ermittle die Server für den gewünschen Dienst, die via Tunnel erreichbar sind.
## @params stype Dienst-Typ (z.B. "DNS" oder "NTP") - entspricht den DHCP-Options, die vom OpenVPN-Server gepusht werden.
## @details Die Ausgabe ist leer, falls kein Tunnel aufgebaut ist.
get_mig_tunnel_servers() {
	trap 'error_trap get_mig_tunnel_server "$*"' EXIT
	local stype="$1"
	[ -z "$(get_active_mig_connections)" ] && return 0
	[ -f "$MIG_PREFERRED_SERVERS_FILE" ] || return 0
	awk <"$MIG_PREFERRED_SERVERS_FILE" '{ if ($1 == "'"$stype"'") print $2 }'
}


## @fn get_traceroute_csv()
## @brief Liefere den gecachten Traceroute zum Service zurück
## @param Service Name
## @returns CSV Liste von Hops
get_traceroute_csv() {
	local service_name="$1"
	local traceroute
	local host

	host=$(get_service_value "$service_name" "host")
	traceroute=$(get_service_value "$TRACEROUTE_FILENAME" "$host")

	# noch keine Tests durchgefuehrt?
	[ -z "$traceroute" ] && return 0
	echo "$traceroute"
}


## @fn update_traceroute_gw_cache()
## @brief Aktualisiere den traceroute zu allen Gateway Servern.
update_traceroute_gw_cache() {
	trap 'error_trap update_traceroute_gw_cache "$*"' EXIT
	local host
	local traceroute

	for host in $(get_services "gw" | pipe_service_attribute "host" | cut -f 2- | sort | uniq); do
		# do traceroute and get result as csv back
		traceroute=$(get_traceroute "$host")
		# update cache file
		set_service_value "$TRACEROUTE_FILENAME" "$host" "$traceroute"
	done
	# es gab eine Aenderung
	msg_info "updating traceroute to gateway servers"
}


# Ende der Doku-Gruppe
## @}
