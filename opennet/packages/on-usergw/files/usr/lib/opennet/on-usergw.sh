## @defgroup on-usergw UserGateway-Funktionen
# Beginn der Doku-Gruppe
## @{

UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
MESH_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-ugw.template
## @todo vorerst unter einer fremden Domain, bis wir ueber das Konzept entschieden haben
MESH_OPENVPN_SRV_DNS_NAME=_mesh-openvpn._udp.systemausfall.org
#MESH_OPENVPN_SRV_DNS_NAME=_mesh-openvpn._udp.opennet-initiative.de


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_usergw_default() {
	_get_file_dict_value "$1" "$ON_USERGW_DEFAULTS_FILE"
}


## @fn has_mesh_openvpn_credentials()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder
##   falls in irgendeiner Form Unklarheit besteht.
has_mesh_openvpn_credentials() {
	has_openvpn_credentials_by_template "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE" && return 0
	trap "" $GUARD_TRAPS && return 1
}


_notify_mesh_success() {
	local service_name="$1"
	set_service_value "$service_name" "status" "true"
	set_service_value "$service_name" "status_fail_counter" ""
	set_service_value "$service_name" "status_timestamp" "$(get_uptime_minutes)"
}


_notify_mesh_failure() {
	local service_name="$1"
	# erhoehe den Fehlerzaehler
	local fail_counter=$(( $(get_service_value "$service_name" "status_fail_counter" "0") + 1))
	set_service_value "$service_name" "status_fail_counter" "$fail_counter"
	# Pruefe, ob der Fehlerzaehler gross genug ist, um seinen Status auf "fail" zu setzen.
	if [ "$fail_counter" -ge "$(get_on_usergw_default "test_max_fail_attempts")" ]; then
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


## @fn verify_mesh_gateways()
## @brief Durchlaufe die Liste der Gateways bis mindestens ein Test erfolgreich ist
## @details Die Gateways werden in der Reihenfolge ihrer Priorität geprüft.
##   Nach dem ersten Durchlauf dieser Funktion sollte also der nächstgelegene nutzbare Gateway als
##   funktionierend markiert sein.
##   Falls kein Gateway positiv getestet wurde (beispielsweise weil alle Zeitstempel zu frisch sind),
##   dann wird in jedem Fall der älteste nicht-funktionsfähige Gateway getestet. Dies minimiert die Ausfallzeit im
#    Falle einer globalen Nicht-Erreichbarkeit aller Gateways ohne auf den Ablauf der Test-Periode warten zu müssen.
## @attention Seiteneffekt: die Zustandsinformationen des getesteten Diensts (Status, Test-Zeitstempel) werden verändert.
verify_mesh_gateways() {
	trap "error_trap verify_mesh_gateways '$*'" $GUARD_TRAPS
	local service_name
	local timestamp
	local status
	local test_period_minutes=$(get_on_usergw_default "test_period_minutes")
	get_services "mesh" \
			| filter_reachable_services \
			| filter_enabled_services \
			| sort_services_by_priority \
			| while read service_name; do
		timestamp=$(get_service_value "$service_name" "status_timestamp" "0")
		status=$(get_service_value "$service_name" "status")
		if [ -z "$status" ] || is_timestamp_older_minutes "$timestamp" "$test_period_minutes"; then
			if is_mesh_gateway_usable "$service_name"; then
				msg_debug "usability of mesh gateway $(get_service_value "$service_name" "host") successfully tested"
				_notify_mesh_success "$service_name"
				# wir sind fertig - keine weiteren Tests
				return
			else
				msg_debug "failed to verify usability of mesh gw $(get_service_value "$service_name" "host")"
				_notify_mesh_failure "$service_name"
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
		is_mesh_gateway_usable "$service_name" && _notify_mesh_success "$service_name" || _notify_mesh_failure "$service_name"
		# wir wollen nur genau einen Test durchfuehren
		break
	done
}


is_mesh_gateway_usable() {
	trap "error_trap is_mesh_gateway_usable '$*'" $GUARD_TRAPS
	local service_name="$1"
	local failed=
	# WAN-Routing
	if is_service_routed_via_wan "$service_name"; then
		set_service_value "$service_name" "wan_status" "true"
	else
		failed=1
		set_service_value "$service_name" "wan_status" "false"
	fi
	# VPN-Verbindung
	if [ -n "$failed" ]; then
		set_service_value "$service_name" "vpn_status" ""
	else
		prepare_openvpn_service "$service_name" "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
		if verify_vpn_connection "$service_name"; then
			set_service_value "$service_name" "vpn_status" "true"
		else
			set_service_value "$service_name" "vpn_status" "false"
		fi
	fi
	# MTU-Pruefung
	if [ -n "$failed" ]; then
		for key in "mtu_msg" "mtu_out_wanted" "mtu_out_real" "mtu_in_wanted" "mtu_in_real" "mtu_timestamp" "mtu_status"; do
			set_service_value "$service_value" "$key" ""
		done
	else
		local mtu_result=$(openvpn_get_mtu "$service_name")
		echo "$mtu_result" | update_mesh_gateway_mtu_state "$service_name"
		uci_is_true "$(get_service_value "$service_name" "mtu_status")" || failed=1
	fi
	[ -z "$failed" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn update_mesh_services_via_dns()
## @brief Frage den Sammel-Domainnamen für alle Mesh-Gateways ab, erzeuge Dienste für alle angegebenen Namen und lösche veraltete Einträge der Liste.
## @details Diese Funktion sollte gelegentlich via cronjob ausgeführt werden.
update_mesh_services_via_dns() {
	local priority
	local weight
	local port
	local hostname
	local service_name
	local timestamp
	local min_timestamp=$(($(get_uptime_minutes) - $(get_on_core_default "service_expire_minutes")))
	query_srv_records "$MESH_OPENVPN_SRV_DNS_NAME" | while read priority weight port hostname; do
		notify_service "mesh" "openvpn" "$hostname" "$port" "udp" "/" "" "dns-srv"
		service_name=$(get_service_name "mesh" "openvpn" "$hostname" "$port" "udp" "/")
		# wir ignorieren das SRV-Attribut "weight" - nur "priority" ist fuer uns relevant
		set_service_value "$service_name" "priority" "$priority"
	done
	# veraltete Dienste entfernen
	get_services "mesh" \
			| filter_services_by_value "scheme" "openvpn" \
			| filter_services_by_value "source" "dns-srv" \
			| while read service_name; do
		timestamp=$(get_service_value "$service_name" "timestamp" 0)
		# der Service ist zu lange nicht aktualisiert worden
		[ "$timestamp" -lt "$min_timestamp" ] && delete_service "$service_name" || true
	done
}


## @fn update_public_gateway_speed_estimation()
## @brief Schätze die Upload- und Download-Geschwindigkeit zu dem Dienstanbieter ab. Aktualisiere anschließend die Attribute des Diensts.
## @param service_name der Name des Diensts
## @details Auf der Gegenseite wird die Datei '.10megabyte' fuer den Download via http erwartet.
update_public_gateway_speed_estimation() {
	trap "error_trap update_public_gateway_speed_estimation '$*'" $GUARD_TRAPS
	local service_name="$1"
	local host=$(get_service_value "$service_name" "host")
	local download_speed=$(measure_download_speed "$host")
	local upload_speed=$(measure_upload_speed "$host")
	# keine Zahlen? Keine Aktualisierung ...
	[ -z "$download_speed" ] && [ -z "$upload_speed" ] && return
	# gleitende Mittelwerte: vorherigen Wert einfliessen lassen
	# Falls keine vorherigen Werte vorliegen, dann werden die aktuellen verwendet.
	local prev_download=$(get_service_detail "$service_name" "wan_speed_download" "${download_speed:-0}")
	local prev_upload=$(get_service_detail "$service_name" "wan_speed_upload" "${upload_speed:-0}")
	set_service_detail "$service_name" "wan_speed_download" "$(((3 * download_speed + prev_download) / 4))"
	set_service_detail "$service_name" "wan_speed_upload" "$(((3 * download_speed + prev_upload) / 4))"
	set_service_value "$service_name" "wan_speed_timestamp" "$(get_uptime_minutes)"
}


## @fn update_mesh_gateway_mtu_state()
## @brief Falls auf dem Weg zwischen Router und öffentlichem Gateway ein MTU-Problem existiert, dann werden die Daten nur bruchstückhaft fließen, auch wenn alle anderen Symptome (z.B. Ping) dies nicht festellten. Daher müssen wir auch den MTU-Pfad auswerten lassen.
## @param service_name der Name des Diensts
## @returns Es erfolgt keine Ausgabe - als Seiteneffekt wird der MTU-Status des Diensts verändert.
## @details Als Eingabestrom wird die Ausgabe von 'openvpn_get_mtu' erwartet.
update_mesh_gateway_mtu_state() {
	trap "error_trap update_mesh_gateway_mtu_state '$*'" $GUARD_TRAPS
	local service_name="$1"
	local host=$(get_service_value "$service_name" "host")
	local state

	msg_debug "starting update_mesh_gateway_mtu_state for '$host'"
	msg_debug "update_mesh_gateway_mtu_state will take around 5 minutes per gateway"

	local mtu_result=$(cat -)
	local out_wanted=$(echo "$mtu_result" | cut -f 1)
	local out_real=$(echo "$mtu_result" | cut -f 2)
	local in_wanted=$(echo "$mtu_result" | cut -f 3)
	local in_real=$(echo "$mtu_result" | cut -f 4)
	local status_output=$(echo "$mtu_result" | cut -f 5)

	if [ -n "$mtu_result" ] && [ "$out_wanted" -le "$out_real" ] && [ "$in_wanted" -le "$in_real" ]; then
		state="true"
	else
		state="false"
	fi

	set_service_value "$service_name" "mtu_msg" "$status_output"
	set_service_value "$service_name" "mtu_out_wanted" "$out_wanted"
	set_service_value "$service_name" "mtu_out_real" "$out_real"
	set_service_value "$service_name" "mtu_in_wanted" "$in_wanted"
	set_service_value "$service_name" "mtu_in_real" "$in_real"
	set_service_value "$service_name" "mtu_status" "$state"

	msg_debug "mtu [$state]: update_mesh_gateway_mtu_state for '$host' done"
	msg_debug "mtu [$state]: $status_output"
}


## @fn sync_mesh_gateway_connection_processes()
## @brief Erzeuge openvpn-Konfigurationen für die als nutzbar markierten Dienste und entferne die Konfigurationen von unbrauchbaren Dienste. Dabei wird auch die maximale Anzahl von mesh-OpenVPN-Verbindungen beachtet.
sync_mesh_openvpn_connection_processes() {
	local service_name
	local max_connections=2
	local conn_count=0
	# diese Festlegung ist recht willkürlich: auf Geräten mit nur 32 MB scheinen wir jedenfalls nahe der Speichergrenze zu arbeiten
	[ "$(get_memory_size)" -gt 32 ] && max_connections=5
	get_services "mesh" \
			| filter_services_by_value "scheme" "openvpn" \
			| filter_enabled_services \
			| sort_services_by_priority \
			| while read service_name; do
		if [ "$conn_count" -lt "$max_connections" ] && uci_is_true "$(get_service_value "$service_name" "status" "false")"; then
			is_openvpn_service_active "$service_name" || enable_openvpn_service "$service_name"
			: $((conn_count++))
		else
			is_openvpn_service_active "$service_name" && disable_openvpn_service "$service_name"
			true
		fi
	done
	apply_changes openvpn
}


# Messung des durchschnittlichen Verkehrs ueber ein Netzwerkinterface innerhalb einer gewaehlten Zeitspanne.
# Parameter: physisches Netzwerkinterface (z.B. eth0)
# Parameter: Anzahl von Sekunden der Messung
# Ergebnis (tab-separiert):
#   RX TX
# (empfangene|gesendete KBytes/s)
get_device_traffic() {
	local device="$1"
	local seconds="$2"
	! which ifstat >/dev/null && msg_info "ERROR: Missing ifstat for 'get_device_traffic'" && return 0
	ifstat -q -b -i "$device" "$seconds" 1 | tail -n 1 | awk '{print int($1 + 0.5) "\t" int($2 + 0.5)}'
}


# Pruefe Bandbreite durch kurzen Download-Datenverkehr
measure_download_speed() {
	local host="$1"
	local target_dev=$(get_target_route_interface "$host")
	wget -q -O /dev/null "http://$host/.big" &
	local pid="$!"
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	get_device_traffic "$target_dev" "$SPEEDTEST_SECONDS" | cut -f 1
	kill "$pid" 2>/dev/null || true
}


# Pruefe Bandbreite durch kurzen Upload-Datenverkehr
measure_upload_speed() {
	local host="$1"
	local target_dev=$(get_target_route_interface "$host")
	# UDP-Verkehr laesst sich auch ohne einen laufenden Dienst auf der Gegenseite erzeugen
	"$NETCAT_BIN" -u "$host" "$SPEEDTEST_UPLOAD_PORT" </dev/zero >/dev/null 2>&1 &
	local pid="$!"
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	get_device_traffic "$target_dev" "$SPEEDTEST_SECONDS" | cut -f 2
	kill "$pid" 2>/dev/null || true
}


# Liefere die aktiven VPN-Verbindungen (mit Mesh-Hubs) zurueck.
# Diese Funktion bracht recht viel Zeit.
get_active_ugw_connections() {
	get_services "mesh" | while read one_service; do
		is_openvpn_service_active "$one_service" && echo "$one_service" || true
	done
}

# Ende der Doku-Gruppe
## @}
