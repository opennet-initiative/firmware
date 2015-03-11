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


## @fn update_mesh_openvpn_connection_state()
## @brief Prüfe, ob ein Verbindungsaufbau mit einem openvpn-Dienst möglich ist.
## @param Name eines Diensts
## @returns exitcode=0 falls der Test erfolgreich war
## @details Die UGW-Tests dürfen eher träger Natur sein, da die Nutzer-VPN-Tests für schnelle Wechsel im Fehlerfall
##   sorgen und jedes UGW typischerweise mehrere Gateway-Dienste via Portweiterleitung anbietet.
## @attention Seiteneffekt: die Zustandsinformationen des Diensts (Status und Test-Zeitstempel) werden verändert.
update_mesh_openvpn_connection_state() {
	trap "error_trap update_mesh_openvpn_connection_state '$*'" $GUARD_TRAPS
	local service_name="$1"
	# sicherstellen, dass alle vpn-relevanten Einstellungen gesetzt wurden
	prepare_openvpn_service "$service_name" "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
	local host=$(get_service_value "$service_name" "host")
	if verify_vpn_connection "$service_name" \
			"$VPN_DIR_TEST/on_aps.key" \
			"$VPN_DIR_TEST/on_aps.crt" \
			"$VPN_DIR_TEST/opennet-ca.crt"; then
		msg_debug "vpn-availability of gw $host successfully tested"
		set_service_value "$service_name" "vpn_status" "y"
	else
		set_service_value "$service_name" "vpn_status" "n"
		msg_debug "failed to test vpn-availability of gw $host"
	fi
	set_service_value "$service_name" "timestamp_connection_test" "$(get_time_minute)"
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
	local min_timestamp=$(($(get_time_minute) - $(get_on_core_default "service_expire_minutes")))
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
	set_service_value "$service_name" "wan_speed_timestamp" "$(get_time_minute)"
}


## @fn update_mesh_gateway_mtu()
## @brief Falls auf dem Weg zwischen Router und öffentlichem Gateway ein MTU-Problem existiert, dann werden die Daten nur bruchstückhaft fließen, auch wenn alle anderen Symptome (z.B. Ping) dies nicht festellten. Daher müssen wir auch den MTU-Pfad auswerten lassen.
## @param service_name der Name des Diensts
## @returns keine Ausgabe - als Seiteneffekt wird der MTU des Diensts verändert
update_mesh_gateway_mtu() {
	trap "error_trap update_update_mesh_gateway_mtu '$*'" $GUARD_TRAPS
	local service_name="$1"
	local host=$(get_service_value "$service_name" "host")
	local state

	msg_debug "starting update_mesh_gateway_mtu for '$host'"
	msg_debug "update_mesh_gateway_mtu will take around 5 minutes per gateway"

	# sicherstellen, dass die config-Datei existiert
	prepare_openvpn_service "$service_name" "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"

	local result=$(openvpn_get_mtu "$service_name")
	local out_wanted=$(echo "$result" | cut -f 1)
	local out_real=$(echo "$result" | cut -f 2)
	local in_wanted=$(echo "$result" | cut -f 3)
	local in_real=$(echo "$result" | cut -f 4)
	local status_output=$(echo "$result" | cut -f 5)

	if [ -n "$result" ] && [ "$out_wanted" -le "$out_real" ] && [ "$in_wanted" -le "$in_real" ]; then
		state="true"
	else
		state="false"
	fi

	set_service_value "$service_name" "mtu_msg" "$status_output"
	set_service_value "$service_name" "mtu_out_wanted" "$out_wanted"
	set_service_value "$service_name" "mtu_out_real" "$out_real"
	set_service_value "$service_name" "mtu_in_wanted" "$in_wanted"
	set_service_value "$service_name" "mtu_in_real" "$in_real"
	set_service_value "$service_name" "mtu_timestamp" "$(get_time_minute)"
	set_service_value "$service_name" "mtu_status" "$state"

	msg_debug "mtu [$state]: update_mesh_gateway_mtu for '$host' done"
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
