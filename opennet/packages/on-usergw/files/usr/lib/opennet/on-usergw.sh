## @defgroup on-usergw UserGateway-Funktionen
# Beginn der Doku-Gruppe
## @{

UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
MESH_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-ugw.template
TRUSTED_SERVICES_URL=https://service-discovery.opennet-initiative.de/ugw-services.csv
## eine beliebige Portnummer, auf der wir keinen udp-Dienst vermuten
SPEEDTEST_UPLOAD_PORT=29418
SPEEDTEST_SECONDS=20
## dieser Wert muss mit der VPN-Konfigurationsvorlage synchron gehalten werden
MESH_OPENVPN_DEVICE_PREFIX=tap


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


## @fn verify_mesh_gateways()
## @brief Durchlaufe die Liste aller Mesh-Gateway-Dienste und aktualisiere deren Status.
## @see run_cyclic_service_tests
verify_mesh_gateways() {
	local max_fail_attempts=$(get_on_usergw_default "test_max_fail_attempts")
	local test_period_minutes=$(get_on_usergw_default "test_period_minutes")
	get_services "mesh" | run_cyclic_service_tests "is_mesh_gateway_usable" "$test_period_minutes" "$max_fail_attempts"
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
	# Ping-Zeit aktualisieren
	local ping_time=
	[ -z "$failed" ] && ping_time=$(get_ping_time "$(get_service_value "$service_name" "host")")
	set_service_value "$service_name" "wan_ping" "$ping_time"
	# VPN-Verbindung
	if [ -n "$failed" ]; then
		set_service_value "$service_name" "vpn_status" ""
	else
		prepare_openvpn_service "$service_name" "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
		if verify_vpn_connection "$service_name"; then
			set_service_value "$service_name" "vpn_status" "true"
		else
			failed=1
			set_service_value "$service_name" "vpn_status" "false"
		fi
	fi
	# MTU-Pruefung
	if [ -n "$failed" ]; then
		for key in "mtu_msg" "mtu_out_wanted" "mtu_out_real" "mtu_in_wanted" "mtu_in_real" "mtu_timestamp" "mtu_status"; do
			set_service_value "$service_name" "$key" ""
		done
	else
		local mtu_result=$(openvpn_get_mtu "$service_name")
		msg_debug "MTU test result ($service_name): $mtu_result"
		echo "$mtu_result" | update_mesh_gateway_mtu_state "$service_name"
		uci_is_true "$(get_service_value "$service_name" "mtu_status")" || failed=1
	fi
	[ -z "$failed" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn update_trusted_service_list()
## @brief Hole die vertrauenswürdigen Dienste von signierten Opennet-Quellen.
## @details Diese Dienste führen beispielsweise auf UGW-APs zur Konfiguration von Portweiterleitungen
##   ins Internet. Daher sind sie nur aus vertrauenswürdiger Quelle zu aktzeptieren (oder manuell).
update_trusted_service_list() {
	local line
	local service_type
	local scheme
	local host
	local port
	local protocol
	local priority
	local details
	local service_name
	local is_proxy
	local url_list=$(run_curl "$TRUSTED_SERVICES_URL")
	# leeres Ergebnis? Noch keine Internet-Verbindung? Keine Aktualisierung, keine Beraeumung ...
	[ -z "$url_list" ] && return
	echo "$url_list" | grep -v "^#" | sed 's/\t\+/\t/g' | while read line; do
		service_type=$(echo "$line" | cut -f 1)
		# falls der Dienst-Typ mit "proxy-" beginnt, soll er weitergeleitet werden
		if [ "${service_type#proxy-}" = "$service_type" ]; then
			# kein Proxy-Dienst
			is_proxy=
		else
			# ein Proxy-Dienst
			is_proxy=1
			# entferne das Praefix
			service_type="${service_type#proxy-}"
		fi
		scheme=$(echo "$line" | cut -f 2)
		host=$(echo "$line" | cut -f 3)
		port=$(echo "$line" | cut -f 4)
		protocol=$(echo "$line" | cut -f 5)
		priority=$(echo "$line" | cut -f 6)
		details=$(echo "$line" | cut -f 7-)
		service_name=$(notify_service "$service_type" "$scheme" "$host" "$port" "$protocol" "/" "trusted" "$details")
		set_service_value "$service_name" "priority" "$priority"
		[ -n "$is_proxy" ] && pick_local_service_relay_port "$service_name" >/dev/null
		true
	done
	# veraltete Dienste entfernen
	local min_timestamp=$(($(get_uptime_minutes) - $(get_on_core_default "trusted_service_expire_minutes")))
	# falls die uptime kleiner ist als die Verfallszeit, dann ist ein Test sinnfrei
	if [ "$min_timestamp" -gt 0 ]; then
		get_services "mesh" \
				| filter_services_by_value "source" "trusted" \
				| while read service_name; do
			timestamp=$(get_service_value "$service_name" "timestamp" 0)
			# der Service ist zu lange nicht aktualisiert worden
			[ "$timestamp" -lt "$min_timestamp" ] && delete_service "$service_name"
			true
		done
	fi
	# aktualisiere DNS- und NTP-Dienste
	apply_changes on-core
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

	if [ -z "$mtu_result" ]; then
		state=""
		state_label="unknown"
	elif [ "$out_wanted" -le "$out_real" ] && [ "$in_wanted" -le "$in_real" ]; then
		state="true"
		state_label="OK"
	else
		state="false"
		state_label="failure"
	fi

	set_service_value "$service_name" "mtu_msg" "$status_output"
	set_service_value "$service_name" "mtu_out_wanted" "$out_wanted"
	set_service_value "$service_name" "mtu_out_real" "$out_real"
	set_service_value "$service_name" "mtu_in_wanted" "$in_wanted"
	set_service_value "$service_name" "mtu_in_real" "$in_real"
	set_service_value "$service_name" "mtu_status" "$state"

	msg_debug "mtu [$state_label]: update_mesh_gateway_mtu_state for '$host' done"
	[ -n "$status_output" ] && msg_debug "mtu [$state_label]: $status_output"
	true
}


## @fn sync_mesh_gateway_connection_processes()
## @brief Erzeuge openvpn-Konfigurationen für die als nutzbar markierten Dienste und entferne die Konfigurationen von unbrauchbaren Dienste. Dabei wird auch die maximale Anzahl von mesh-OpenVPN-Verbindungen beachtet.
sync_mesh_openvpn_connection_processes() {
	local service_name
	local max_connections=2
	local conn_count=0
	local service_state
	# diese Festlegung ist recht willkürlich: auf Geräten mit nur 32 MB scheinen wir jedenfalls nahe der Speichergrenze zu arbeiten
	[ "$(get_memory_size)" -gt 32 ] && max_connections=5
	get_services "mesh" \
			| filter_services_by_value "scheme" "openvpn" \
			| filter_enabled_services \
			| sort_services_by_priority \
			| while read service_name; do
		service_state=$(get_openvpn_service_state "$service_name")
		if [ "$conn_count" -lt "$max_connections" ] && uci_is_true "$(get_service_value "$service_name" "status" "false")"; then
			[ -z "$service_state" ] && enable_openvpn_service "$service_name"
			: $((conn_count++))
		else
			[ -n "$service_state" ] && disable_openvpn_service "$service_name"
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
# (empfangene|gesendete KBits/s)
get_device_traffic() {
	local device="$1"
	local seconds="$2"
	local sys_path="/sys/class/net/$device"
	[ ! -d "$sys_path" ] && msg_error "Failed to find '$sys_path' for 'get_device_traffic'" && return 0
	{
		cat "$sys_path/statistics/rx_bytes"
		cat "$sys_path/statistics/tx_bytes"
		sleep "$seconds"
		cat "$sys_path/statistics/rx_bytes"
		cat "$sys_path/statistics/tx_bytes"
	} | tr '\n' ' ' | awk '{ print int((8 * ($3-$1)) / 1024 / '$seconds' + 0.5) "\t" int((8 * ($4-$2)) / 1024 / '$seconds' + 0.5) }'
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
		[ "$(get_openvpn_service_state "$one_service")" = "active" ] && echo "$one_service" || true
	done
}

# Ende der Doku-Gruppe
## @}
