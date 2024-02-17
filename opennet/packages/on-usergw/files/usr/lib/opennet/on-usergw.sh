## @defgroup on-usergw UserGateway-Funktionen
# Beginn der Doku-Gruppe
## @{

# shellcheck disable=SC2034
UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
MESH_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-ugw.template
UGW_SERVICES_LIST_URL=https://services.opennet-initiative.de/ugw-services.csv
## auf den UGW-Servern ist via inetd der Dienst "discard" erreichbar
SPEEDTEST_UPLOAD_PORT=discard
SPEEDTEST_SECONDS=20
## dieser Wert muss mit der VPN-Konfigurationsvorlage synchron gehalten werden
# shellcheck disable=SC2034
MESH_OPENVPN_DEVICE_PREFIX=tap
# Die folgenden Attribute werden dauerhaft (im Flash) gespeichert. Häufige Änderungen sind also eher unerwünscht.
# Gruende fuer ausgefallene/unintuitive Attribute:
#   local_relay_port: der lokale Port, der für eine Dienst-Weiterleitung verwendet wird - er sollte über reboots hinweg stabil sein
#   *status: eine Mesh-Verbindung soll nach dem Booten schnell wieder aufgebaut werden (ohne lange MTU-Tests)
# Wir beachten den vorherigen Zustand der Variable, damit andere Module (z.B. on-usergw) diese
# ebenfalls beeinflussen können.
PERSISTENT_SERVICE_ATTRIBUTES="${PERSISTENT_SERVICE_ATTRIBUTES:-} local_relay_port status vpn_status wan_status mtu_status"

SERVICES_LIST_URLS="${SERVICES_LIST_URLS:-} $UGW_SERVICES_LIST_URL"


## @fn get_on_usergw_default()
## @param key Schlüssel des gewünschten default-Werts.
## @brief Hole default-Werte der UGW-Funktionalität der aktuellen Firmware.
## @details Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
##   Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_usergw_default() {
	_get_file_dict_value "$1" "$ON_USERGW_DEFAULTS_FILE"
}


## @fn has_mesh_openvpn_credentials()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder
##   falls in irgendeiner Form Unklarheit besteht.
has_mesh_openvpn_credentials() {
	has_openvpn_credentials_by_template "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE" && return 0
	trap "" EXIT && return 1
}


## @fn verify_mesh_gateways()
## @brief Durchlaufe die Liste aller Mesh-Gateway-Dienste und aktualisiere deren Status.
## @see run_cyclic_service_tests
verify_mesh_gateways() {
	local max_fail_attempts
	local test_period_minutes
	max_fail_attempts=$(get_on_usergw_default "test_max_fail_attempts")
	test_period_minutes=$(get_on_usergw_default "test_period_minutes")
	get_services "mesh" | run_cyclic_service_tests "is_mesh_gateway_usable" "$test_period_minutes" "$max_fail_attempts"
}


## @fn is_mesh_gateway_usable()
## @param service_name zu prüfender Dienst
## @brief Prüfe ob der Dienst alle notwendigen Tests besteht.
## @details Ein Test dauert bis zu 5 Minuten. Falls bereits eine VPN-Verbindung besteht, wird der MTU-Test übersprungen.
is_mesh_gateway_usable() {
	trap 'error_trap is_mesh_gateway_usable "$*"' EXIT
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
		if [ -z "$(get_openvpn_service_state "$service_name")" ]; then
			# es läuft aktuell keine Verbindung - wir können testen
			local mtu_result
			mtu_result=$(openvpn_get_mtu "$service_name")
			msg_debug "MTU test result ($service_name): $mtu_result"
			echo "$mtu_result" | update_mesh_gateway_mtu_state "$service_name"
			uci_is_true "$(get_service_value "$service_name" "mtu_status" "false")" || failed=1
		else
			# Aktuell läuft eine Verbindung: ein MTU-Test würde diese unterbrechen (was zu
			# wechselseitiger Trennung führen würde). Wir behalten daher das alte mtu-Ergebnis bei.
			# Ein Abbruch einer Verbindung erfolgt also lediglich, wenn die VPN-Verbindung komplett
			# nicht mehr nutzbar ist.
			true
		fi
	fi
	[ -z "$failed" ] && return 0
	trap "" EXIT && return 1
}


## @fn update_relayed_server_speed_estimation()
## @brief Schätze die Upload- und Download-Geschwindigkeit zu dem Dienstanbieter ab. Aktualisiere anschließend die Attribute des Diensts.
## @param service_name der Name des Diensts
## @details Auf der Gegenseite wird die Datei '.big' fuer den Download via http erwartet.
update_relayed_server_speed_estimation() {
	trap 'error_trap update_relayed_server_speed_estimation "$*"' EXIT
	local service_name="$1"
	local host
	local download_speed
	local upload_speed
	host=$(get_service_value "$service_name" "host")
	download_speed=$(measure_download_speed "$host")
	upload_speed=$(measure_upload_speed "$host")
	# keine Zahlen? Keine Aktualisierung ...
	[ -z "$download_speed" ] && [ -z "$upload_speed" ] && return
	# gleitende Mittelwerte: vorherigen Wert einfliessen lassen
	# Falls keine vorherigen Werte vorliegen, dann werden die aktuellen verwendet.
	local prev_download
	local prev_upload
	prev_download=$(get_service_value "$service_name" "wan_speed_download" "${download_speed:-0}")
	prev_upload=$(get_service_value "$service_name" "wan_speed_upload" "${upload_speed:-0}")
	set_service_value "$service_name" "wan_speed_download" "$(( (3 * download_speed + prev_download) / 4 ))"
	set_service_value "$service_name" "wan_speed_upload" "$(( (3 * upload_speed + prev_upload) / 4 ))"
	set_service_value "$service_name" "wan_speed_timestamp" "$(get_uptime_minutes)"
	announce_olsr_service_relay "$service_name"
}


## @fn update_mesh_gateway_mtu_state()
## @brief Falls auf dem Weg zwischen Router und öffentlichem Gateway ein MTU-Problem existiert, dann werden die Daten nur bruchstückhaft fließen, auch wenn alle anderen Symptome (z.B. Ping) dies nicht festellten. Daher müssen wir auch den MTU-Pfad auswerten lassen.
## @param service_name der Name des Diensts
## @returns Es erfolgt keine Ausgabe - als Seiteneffekt wird der MTU-Status des Diensts verändert.
## @details Als Eingabestrom wird die Ausgabe von 'openvpn_get_mtu' erwartet.
update_mesh_gateway_mtu_state() {
	trap 'error_trap update_mesh_gateway_mtu_state "$*"' EXIT
	local service_name="$1"
	local host
	local state
	local mtu_result
	local out_wanted
	local out_real
	local in_wanted
	local in_real
	local status_output

	host=$(get_service_value "$service_name" "host")

	msg_debug "starting update_mesh_gateway_mtu_state for '$host'"
	msg_debug "update_mesh_gateway_mtu_state will take around 5 minutes per gateway"

	mtu_result=$(cat -)
	out_wanted=$(echo "$mtu_result" | cut -f 1)
	out_real=$(echo "$mtu_result" | cut -f 2)
	in_wanted=$(echo "$mtu_result" | cut -f 3)
	in_real=$(echo "$mtu_result" | cut -f 4)
	status_output=$(echo "$mtu_result" | cut -f 5)

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


## @fn sync_mesh_openvpn_connection_processes()
## @brief Erzeuge openvpn-Konfigurationen für die als nutzbar markierten Dienste und entferne
##   die Konfigurationen von unbrauchbaren Dienste. Dabei wird auch die maximale Anzahl von
##   mesh-OpenVPN-Verbindungen beachtet.
sync_mesh_openvpn_connection_processes() {
	local service_name
	local conn_count=0
	local max_connections
	local service_state
	# diese Festlegung ist recht willkürlich: auf Geräten mit nur 32 MB scheinen wir jedenfalls nahe der Speichergrenze zu arbeiten
	[ "$(get_memory_size)" -gt 32 ] && max_connections=5 || max_connections=1
	for service_name in $(get_services "mesh" \
			| filter_services_by_value "scheme" "openvpn" \
			| sort_services_by_priority); do
		service_state=$(get_openvpn_service_state "$service_name")
		if [ "$conn_count" -lt "$max_connections" ] \
				&& uci_is_true "$(get_service_value "$service_name" "status" "false")" \
				&& uci_is_false "$(get_service_value "$service_name" "disabled" "false")"; then
			[ -z "$service_state" ] && enable_openvpn_service "$service_name"
			conn_count=$((conn_count + 1))
		else
			[ -z "$service_state" ] || disable_openvpn_service "$service_name"
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
_get_device_traffic() {
	local device="$1"
	local seconds="$2"
	local sys_path="/sys/class/net/$device"
	[ ! -d "$sys_path" ] && msg_error "Failed to find '$sys_path' for '_get_device_traffic'" && return 0
	# Ausgabe einer Zeile mit vier Zahlen: start_rx start_tx end_rx end_tx
	# Die sed-Filterung am Ende sorgt dafür, dass negative Zahlen (bei zwischenzeitlicher
	# Interface-Neukonfiguration) durch eine Null ersetzt werden.
	{
		cat "$sys_path/statistics/rx_bytes"
		cat "$sys_path/statistics/tx_bytes"
		sleep "$seconds"
		cat "$sys_path/statistics/rx_bytes"
		cat "$sys_path/statistics/tx_bytes"
	} | tr '\n' ' ' | awk '{ print int((8 * ($3-$1)) / 1024 / '"$seconds"' + 0.5) "\t" int((8 * ($4-$2)) / 1024 / '"$seconds"' + 0.5) }' \
		| sed 's/\(-[[:digit:]]\+\)/0/g'
}


## @fn measure_download_speed()
## @param host Gegenstelle für den Geschwindigkeitstest.
## @brief Pruefe Bandbreite durch kurzen Download-Datenverkehr
measure_download_speed() {
	local host="$1"
	local target_dev
	target_dev=$(get_target_route_interface "$host")
	wget -q -O /dev/null "http://$host/.big" &
	local pid="$!"
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	_get_device_traffic "$target_dev" "$SPEEDTEST_SECONDS" | cut -f 1
	kill "$pid" 2>/dev/null || true
}


## @fn measure_upload_speed()
## @param host Gegenstelle für den Geschwindigkeitstest.
## @brief Pruefe Bandbreite durch kurzen Upload-Datenverkehr
measure_upload_speed() {
	local host="$1"
	local target_dev
	target_dev=$(get_target_route_interface "$host")
	nc "$host" "$SPEEDTEST_UPLOAD_PORT" </dev/zero >/dev/null 2>&1 &
	local pid="$!"
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	_get_device_traffic "$target_dev" "$SPEEDTEST_SECONDS" | cut -f 2
	kill "$pid" 2>/dev/null || true
}


# Liefere die aktiven VPN-Verbindungen (mit Mesh-Hubs) zurueck.
# Diese Funktion bracht recht viel Zeit.
get_active_ugw_connections() {
	for one_service in $(get_services "mesh"); do
		[ "$(get_openvpn_service_state "$one_service")" != "active" ] || echo "$one_service"
	done
}


## @fn iptables_by_target_family()
## @brief Rufe "iptables" oder "ip6tables" (abhängig von einer Ziel-IP) mit den gegebenen Parametern aus.
## @param target die Ziel-IP anhand derer die Protokollfamilie (inet oder inet6) ermittelt wird
## @param ... alle weiteren Parameter werden direkt an ip(6)tables uebergeben
iptables_by_target_family() {
	local target="$1"
	shift
	local command
	is_ipv4 "$target" && command="iptables" || command="ip6tables"
	"$command" "$@"
}


## @fn update_mesh_gateway_firewall_rules()
## @brief markiere alle lokal erzeugten Pakete, die an einen mesh-Gateway-Dienst adressiert sind
## @details Diese Markierung ermöglicht die Filterung (throw) der Pakete für mesh-Gateways in der
##   Nutzer-Tunnel-Routingtabelle.
update_mesh_gateway_firewall_rules() {
	local host
	local port
	local protocol
	local target_ip
	local table="on_usergw_table"
	local chain="on_tos_mesh_vpn"
	# Chain leeren (siehe auch /usr/share/nftables.d/ fuer Definition der Chain)
    nft flush chain inet "$table" "$chain"

	# falls es keinen Tunnel-Anbieter gibt, ist nichts zu tun
	[ -z "${TOS_NON_TUNNEL:-}" ] && return 0
	# Regeln fuer jeden mesh-Gateway aufstellen
	for service in $(get_services "mesh"); do
		host=$(get_service_value "$service" "host")
		port=$(get_service_value "$service" "port")
		protocol=$(get_service_value "$service" "protocol")
		for target_ip in $(query_dns "$host" | filter_routable_addresses); do
			# unaufloesbare Hostnamen ignorieren
			[ -z "$target_ip" ] && continue
			# Setze TOS=8 (DSCP=0x02) wenn Ziel mesh-Gateway-Dienst
			if is_ipv4 "$target_ip"; then
				nft add rule inet "$table" "$chain" ip daddr "$target_ip" "$protocol" dport "$port" counter ip dscp set 0x02
			else
				nft add rule inet "$table" "$chain" ip6 daddr "$target_ip" "$protocol" dport "$port" counter ip6 dscp set 0x02
			fi
		done
	done
}


## @fn disable_on_usergw()
## @brief Alle mesh-Verbindungen trennen.
disable_on_usergw() {
	local service_name
	local changed=0
	for service_name in $(get_services "mesh" | filter_services_by_value "scheme" "openvpn"); do
		if [ -n "$(get_openvpn_service_state "$service_name")" ]; then
			disable_openvpn_service "$service_name"
			changed=1
		fi
	done
	[ "$changed" = "0" ] || apply_changes "openvpn"
}


## @fn fix_wan_route_if_missing()
## @brief Prüfe, ob die default-Route trotz aktivem WAN-Interface fehlt. In diesem Fall füge sie
##        mit "ifup wan" wieder hinzu.
## @details Die Ursache für die fehlende default-Route ist unklar.
fix_wan_route_if_missing() {
	trap 'error_trap fix_wan_route_if_missing "$*"' EXIT
	local wan_interface
	# default route exists? Nothing to fix ...
	ip route show | grep -q ^default && return 0
	(
		# tolerante Shell-Interpretation fuer OpenWrt-Code
		set +eu
		# shellcheck source=openwrt/package/base-files/files/lib/functions/network.sh
		. /lib/functions/network.sh
		wan_interface=
		network_find_wan wan_interface
		if [ -n "$wan_interface" ] && network_is_up "$wan_interface"; then
			add_banner_event "Missing default route - reinitialize '$wan_interface'"
			ifup "$wan_interface" || true
		fi
		set -eu
	)
}


## @fn update_on_usergw_status()
## @brief Baue Verbindungen auf oder trenne sie - je nach Modul-Status.
update_on_usergw_status() {
	trap 'error_trap update_on_usergw_status "$*"' EXIT
	if is_on_module_installed_and_enabled "on-usergw"; then
		fix_wan_route_if_missing
		update_mesh_gateway_firewall_rules
		# ohne Zertifikat ist nicht mehr zu tun
		if has_mesh_openvpn_credentials; then
			verify_mesh_gateways
			sync_mesh_openvpn_connection_processes
		fi
	else
		disable_on_usergw
	fi
}

# Ende der Doku-Gruppe
## @}
