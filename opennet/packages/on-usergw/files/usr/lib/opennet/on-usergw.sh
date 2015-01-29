## @defgroup on-usergw UserGateway-Funktionen
# Beginn der Doku-Gruppe
## @{

UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
MESH_OPENVPN_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-ugw.template
## @todo vorerst unter einer fremden Domain, bis wir ueber das Konzept entschieden haben
MESH_OPENVPN_SRV_DNS_NAME=_mesh-openvpn._udp.systemausfall.org
#MESH_OPENVPN_SRV_DNS_NAME=_mesh-openvpn._udp.opennet-initiative.de
## eine beliebige Portnummer, auf der wir keinen udp-Dienst vermuten
SPEEDTEST_UPLOAD_PORT=29418
SPEEDTEST_SECONDS=20
UGW_FIREWALL_RULE_NAME=opennet_ugw
## für die Kompatibilität mit Firmware vor v0.5
UGW_LOCAL_SERVICE_PORT_LEGACY=1600
## falls mehr als ein GW-Dienst weitergereicht wird, wird dieser Port und die folgenden verwendet
UGW_LOCAL_SERVICE_PORT_START=5100
UGW_SERVICE_CREATOR=ugw_service


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_usergw_default() { _get_file_dict_value "$ON_USERGW_DEFAULTS_FILE" "$1"; }


## @fn has_mesh_openvpn_credentials()
## @brief Prüft, ob der Nutzer bereits einen Schlüssel und ein Zertifikat angelegt hat.
## @returns Liefert "wahr", falls Schlüssel und Zertifikat vorhanden sind oder
##   falls in irgendeiner Form Unklarheit besteht.
has_mesh_openvpn_credentials() {
	has_openvpn_credentials_by_template "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE" && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn test_ugw_openvpn_connection()
## @brief Prüfe, ob ein Verbindungsaufbau mit einem openvpn-Dienst möglich ist.
## @param Name eines Diensts
## @returns exitcode=0 falls der Test erfolgreich war
## @details Die UGW-Tests dürfen eher träger Natur sein, da die Nutzer-VPN-Tests für schnelle Wechsel im Fehlerfall
##   sorgen und jedes UGW typischerweise mehrere Gateway-Dienste via Portweiterleitung anbietet.
## @attention Seiteneffekt: die Zustandsinformationen des Diensts (Status und Test-Zeitstempel) werden verändert.
test_ugw_openvpn_connection() {
	trap "error_trap test_ugw_openvpn_connection '$*'" $GUARD_TRAPS
	local service_name="$1"
	# sicherstellen, dass alle vpn-relevanten Einstellungen gesetzt wurden
	prepare_openvpn_service "$service_name" "$MESH_OPENVPN_CONFIG_TEMPLATE_FILE"
	local host=$(get_service_detail "$service_name" "hostname")
	local returncode=0
	if verify_vpn_connection "$service_name" \
			"$VPN_DIR_TEST/on_aps.key" \
			"$VPN_DIR_TEST/on_aps.crt" \
			"$VPN_DIR_TEST/opennet-ca.crt"; then
		msg_debug "vpn-availability of gw $host successfully tested"
		set_service_value "$service_name" "status" "y"
	else
		set_service_value "$service_name" "status" "n"
		msg_debug "failed to test vpn-availability of gw $host"
		returncode=1
	fi
	set_service_value "$service_name" "timestamp_connection_test" "$(get_time_minute)"
	trap "" $GUARD_TRAPS && return "$returncode"
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
	get_services | filter_services_by_value "service=mesh" "scheme=openvpn" "source=dns-srv" | while read service_name; do
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
	local host=$(get_service_value "$service_name" "$host")
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


## @fn update_service_wan_status()
## @brief Pruefe ob der Verkehr zum Anbieter des Diensts über ein WAN-Interface verlaufen würde. Das "wan_status"-Flag des Diensts wird daraufhin aktualisiert.
## @param service_name der Name des Diensts
## @details Diese Operation dauert ca. 5s, da zusätzlich die Ping-Zeit des Zielhosts ermittelt wird.
update_service_wan_status() {
	trap "error_trap ugw_update_wan_status '$*'" $GUARD_TRAPS
	local service_name="$1"
	local host=$(get_service_value "$service_name" "host")
	local outgoing_interface=$(get_target_route_interface "$hostname")
	if is_device_in_zone "$outgoing_interface" "$ZONE_WAN"; then
		set_server_value "$service_name" "wan_status" "true"
		local ping_time=$(get_ping_time "$host")
		set_server_value "$service_name" "wan_ping" "$ping_time"
		msg_debug "target '$host' routing through wan device: $outgoing_interface"
		msg_debug "average ping time for $host: ${ping_time}s"
	else
		local outgoing_zone=$(get_zone_of_interface "$outgoing_interface")
		# ausfuehrliche Erklaerung, falls das Routing zuvor noch akzeptabel war
		uci_is_true "$(get_service_value "$service_name" "wan_status")" \
			&& msg_info "Routing switched away from WAN interface to '$outgoing_interface'"
		msg_debug "warning: target '$host' is routed via interface '$outgoing_interface' (zone '$outgoing_zone') instead of the expected WAN zone ($ZONE_WAN)"
		set_server_value "$service_name" "wan_status" "false"
		set_server_value "$service_name" "wan_ping" ""
	fi
}


## @fn update_public_gateway_mtu()
## @brief Falls auf dem Weg zwischen Router und öffentlichem Gateway ein MTU-Problem existiert, dann werden die Daten nur bruchstückhaft fließen, auch wenn alle anderen Symptome (z.B. Ping) dies nicht festellten. Daher müssen wir auch den MTU-Pfad auswerten lassen.
## @param service_name der Name des Diensts
## @returns keine Ausgabe - als Seiteneffekt wird der MTU des Diensts verändert
update_public_gateway_mtu() {
	trap "error_trap update_public_gateway_mtu '$*'" $GUARD_TRAPS
	local service_name="$1"
	local host=$(get_service_value "$service_name" "host")
	local state

	msg_debug "starting update_public_gateway_mtu for '$host'"
	msg_debug "update_public_gateway_mtu will take around 5 minutes per gateway"

	local result=$(openvpn_get_mtu "$service_name")

	if [ -n "$result" ]; then
		local out_wanted=$(echo "$result" | cut -f 1 -d ,)
		local out_real=$(echo "$result" | cut -f 2 -d ,)
		local in_wanted=$(echo "$result" | cut -f 3 -d ,)
		local in_real=$(echo "$result" | cut -f 4 -d ,)
		local status_output=$(echo "$result" | cut -f 5- -d ,)

		if [ "$out_wanted" -le "$out_real" ] && [ "$in_wanted" -le "$in_real" ]; then
			state="true"
		else
			state="false"
		fi

	else
		out_wanted=
		out_real=
		in_wanted=
		in_real=
		status_output=
		state="false"
	fi
	set_service_value "$service_name" "mtu_msg" "$status_output"
	set_service_value "$service_name" "mtu_out_wanted" "$out_wanted"
	set_service_value "$service_name" "mtu_out_real" "$out_real"
	set_service_value "$service_name" "mtu_in_wanted" "$in_wanted"
	set_service_value "$service_name" "mtu_in_real" "$in_real"
	set_service_value "$service_name" "mtu_timestamp" "$(get_time_minute)"
	set_service_value "$service_name" "mtu_status" "$state"

	local mtu_status=$(get_service_value "$service_name" "mtu_status")
	local mtu_msg=$(get_service_value "$service_name" "mtu_msg")
	msg_debug "mtu [$mtu_status]: update_public_gateway_mtu for '$host' done"
	msg_debug "mtu [$mtu_status]: $mtu_msg"
}


# try to establish openvpn tunnel
# return a string, if it works (else return nothing)
# parameter is index to test
update_public_gateway_vpn_status() {
	trap "error_trap ugw_update_vpn_status '$*'" $GUARD_TRAPS
	local service_name=$1
	local host=$(get_server_value "$service_name" "host")
	local status
	if verify_vpn_connection "$service_name" \
			"$VPN_DIR_TEST/on_aps.key" \
			"$VPN_DIR_TEST/on_aps.crt" \
			"$VPN_DIR_TEST/opennet-ca.crt"; then
		status="true"
		msg_debug "vpn-availability of gw '$host' successfully tested"
	else
		status="false"
	fi
	set_service_value "$service_name" "vpn_status" "false"
	set_service_value "$service_name" "vpn_timestamp" "$(get_time_minute)"
	msg_debug "finished vpn test of '$host'"
}


#----------

# Ermittle den aktuell definierten UGW-Portforward.
# Ergebnis (tab-separiert fuer leichte 'cut'-Behandlung des Output):
#   lokale IP-Adresse fuer UGW-Forward
#   externer Gateway
# TODO: siehe auch http://dev.on-i.de/ticket/49 - wir duerfen uns nicht auf die iptables-Ausgabe verlassen
get_ugw_portforward() {
	local chain=zone_${ZONE_MESH}_prerouting
	# TODO: vielleicht lieber den uci-Portforward mit einem Namen versehen?
	iptables -L "$chain" -t nat -n | awk 'BEGIN{FS="[ :]+"} /udp dpt:1600 to:/ {printf $3 "\t" $5 "\t" $10; exit}'
}


# Lies die vorkonfigurierten Opennet-UGW-Server ein und uebertrage sie in die on-usergw-Konfiguration.
# Diese Aktion sollte nur ausgefuehrt werden, wenn keine UGWs eintragen sind (z.B. weil der Nutzende sie versehentlich geloescht hat).
add_default_openvpn_ugw_services() {
	local index=1
	local hostname
	local port
	local proto
	local details
	while [ -n "$(get_on_usergw_default "openvpn_ugw_preset_$index")" ]; do
		# stelle sicher, dass ein Newline vorliegt - sonst liest "read" nix
		(get_on_usergw_default "openvpn_ugw_preset_$index"; echo) | while read hostname port proto details; do
			[ -z "$hostname" ] && break
			add_openvpn_ugw_service "$hostname" "$port" "$proto" "$details"
		done
		: $((index++))
	done
}


get_wan_device() {
	uci_get network.wan.ifname | cut -f 1 -d :
}


# Messung des durchschnittlichen Verkehrs ueber ein Netzwerkinterface innerhalb einer gewaehlten Zeitspanne.
# Parameter: physisches Netzwerkinterface (z.B. eth0)
# Parameter: Anzahl von Sekunden der Messung
# Ergebnis (tab-separiert):
#   RX TX
# (empfangene|gesendete KBytes/s)
get_device_traffic() {
	local device=$1
	local seconds=$2
	ifstat -q -b -i "$device" "$seconds" 1 | tail -n 1 | awk '{print int($1 + 0.5) "\t" int($2 + 0.5)}'
}


# Pruefe Bandbreite durch kurzen Download-Datenverkehr
measure_download_speed() {
	local host=$1
	wget -q -O /dev/null "http://$host/.big" &
	local pid=$!
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	get_device_traffic "$(get_wan_device)" "$SPEEDTEST_SECONDS" | cut -f 1
	kill "$pid" 2>/dev/null || true
}


# Pruefe Bandbreite durch kurzen Upload-Datenverkehr
measure_upload_speed() {
	local host=$1
	# UDP-Verkehr laesst sich auch ohne einen laufenden Dienst auf der Gegenseite erzeugen
	nc -u "$host" "$SPEEDTEST_UPLOAD_PORT" </dev/zero >/dev/null 2>&1 &
	local pid=$!
	sleep 3
	[ ! -d "/proc/$pid" ] && return
	get_device_traffic "$(get_wan_device)" "$SPEEDTEST_SECONDS" | cut -f 2
	kill "$pid" 2>/dev/null || true
}


# Abschalten eines UGW-Dienstes
# Die Firewall-Regel, die von der ugw-Weiterleitung stammt, wird geloescht.
# olsrd-nameservice-Ankuendigungen werden entfernt.
# Es wird kein "uci commit" oder "apply_changes olsrd" durchgefuehrt.
disable_ugw_service() {
	local config_name=$1
	local uci_prefix
	local service
	# Portweiterleitung loeschen
	uci_prefix=$(uci_get "$(find_first_uci_section on-usergw uplink "name=$config_name").firewall_rule")
	[ -n "$uci_prefix" ] && uci_delete "$uci_prefix"
	service=$(uci_get "${uci_prefix}.olsr_service")
	[ -n "$service" ] && uci del_list "$(get_and_enable_olsrd_library_uci_prefix nameservice).service=$service"
	update_one_openvpn_setup "$config_name" "on-usergw" "uplink"
	uci set "openvpn.${config_name}.enable=0"
	apply_changes openvpn
	# unabhaengig von moeglichen Aenderungen: laufende Dienste stoppen
	/etc/init.d/openvpn reload
	apply_changes on-usergw
	apply_changes firewall
	apply_changes olsrd
}


# Pruefe ob eine olsr-Nameservice-Beschreibung zu einem aktiven ugw-Service gehoert.
# Diese Pruefung ist nuetzlich fuer die Entscheidung, ob ein nameservice-Announcement entfernt
# werden kann.
_is_ugw_service_in_use() {
	local wanted_service=$1
	local uci_prefix
	find_all_uci_sections on-usergw uplink | while read uci_prefix; do
		[ "${uci_prefix}.service" = "$wanted_service" ] && return 0 || true
	done
	return 1
}

# Abschaltung aller Portweiterleitungen, die keinen UGW-Diensten zugeordnet sind.
# Die ugw-Portweiterleitungen werden an ihrem Namen erkannt.
# Es wird kein "uci commit" durchgefuehrt.
disable_stale_ugw_services () {
	trap "error_trap ugw_disable_forwards '$*'" $GUARD_TRAPS
	local uci_prefix
	local ugw_config
	local service
	local creator
	prepare_on_usergw_uci_settings
	# Portweiterleitungen entfernen
	find_all_uci_sections firewall redirect "name=$UGW_FIREWALL_RULE_NAME" | while read uci_prefix; do
		ugw_config=$(find_first_uci_section on-usergw uplink "firewall_rule=$uci_prefix")
		[ -n "$ugw_config" ] && [ -n "$(uci_get "$ugw_config")" ] && continue
		uci_delete "$uci_prefix"
	done
	# olsr-Nameservice-Beschreibungen entfernen
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix nameservice)
	uci_get_list olsrd service | while read service; do
		creator=$(echo "$service" | parse_olsr_service_definitions | cut -f 7 | get_from_key_value_list "creator" :)
		# ausschliesslich Eintrage mit unserem "creator"-Stempel beachten
		[ "$creator" = "$UGW_SERVICE_CREATOR" ] || continue
		# unbenutzte Eintraege entfernen
		_is_ugw_service_in_use "$service" || uci del_list "${uci_prefix}.service=$service"
	done
	return 0
}


# Pruefung ob ein lokaler Port bereits fuer einen ugw-Dienst weitergeleitet wird
_is_local_ugw_port_unused() {
	local port=$1
	local uci_prefix
	prepare_on_usergw_uci_settings
	# Suche nach einer Kollision
	[ -z "$(find_all_uci_sections on-usergw uplink "local_port=$port")" ] && return 0
	# mindestens eine Kollision entdeckt
	trap "" $GUARD_TRAPS && return 1
}


# Liefere den Port zurueck, der einer Dienst-Weiterleitung lokal zugewiesen wurde.
# Falls noch kein Port definiert ist, dann waehle einen neuen Port.
# Parameter: config_name
# commit findet nicht statt
get_local_ugw_service_port() {
	local config_name=$1
	local usergw_uci=$(find_first_uci_section on-usergw uplink "name=$config_name")
	local port=$(uci_get "${usergw_uci}.local_port")
	if [ -z "$port" ]; then
		# suche einen unbenutzten lokalen Port
		port=$UGW_LOCAL_SERVICE_PORT_START
		until _is_local_ugw_port_unused "$port"; do
			: $((port++))
		done
		uci set "${usergw_uci}.local_port=$port"
		apply_changes on-usergw
	fi
	echo "$port"
}


#################################################################################
# enable ugw forwarding, add rules from current firewall settings and set service string
# Parameter: config_name
# commit findet nicht statt
enable_ugw_service () {
	trap "error_trap enable_ugw_service '$*'" $GUARD_TRAPS
	local config_name=$1
	local main_ip=$(get_main_ip)
	local usergw_uci=$(find_first_uci_section on-usergw uplink "name=$config_name")
	local hostname
	local uci_prefix=$(uci_get "${usergw_uci}.firewall_rule")
	[ -z "$uci_prefix" ] && uci_prefix=firewall.$(uci add firewall redirect)
	# der Name ist wichtig fuer spaetere Aufraeumaktionen
	uci set "${uci_prefix}.name=$UGW_FIREWALL_RULE_NAME"
	uci set "${uci_prefix}.src=$ZONE_MESH"
	uci set "${uci_prefix}.proto=$(uci_get "${usergw_uci}.protocol")"
	uci set "${uci_prefix}.src_dport=$(get_local_ugw_service_port "$config_name")"
	uci set "${uci_prefix}.target=DNAT"
	uci set "${uci_prefix}.src_dip=$main_ip"
	hostname=$(uci_get "${usergw_uci}.hostname")
	# wir verwenden nur die erste aufgeloeste IP, zu welcher wir eine Route haben.
	# z.B. faellt IPv6 aus, falls wir kein derartiges Uplink-Interface sehen
	uci set "${uci_prefix}.dest_ip=$(query_dns "$hostname" | filter_routable_addresses | head -n 1)"
	# olsr-nameservice-Announcement
	announce_olsr_service_ugw "$config_name"
	# VPN-Verbindung
	update_one_openvpn_ugw_setup "$config_name"
	uci set "openvpn.${config_name}.enable=1"
	apply_changes openvpn
	# unabhaengig von moeglichen Aenderungen: fehlende Dienste neu starten
	/etc/init.d/openvpn reload
	apply_changes on-usergw
	apply_changes firewall
	apply_changes olsrd
}


# Verkuende den lokalen UGW-Dienst inkl. Geschwindigkeitsdaten via olsr nameservice
# Parameter: config_name
# kein commit
announce_olsr_service_ugw() {
	trap "error_trap announce_ugw_service_ugw '$*'" $GUARD_TRAPS
	local config_name=$1
	local main_ip=$(get_main_ip)
	local port
	local ugw_prefix
	local olsr_prefix
	local service_description
	prepare_on_usergw_uci_settings
	ugw_prefix=$(find_first_uci_section on-usergw uplink "name=$config_name")

	local download=$(get_service_detail "$config_name" download)
	local upload=$(get_service_detail "$config_name" upload)
	local ping=$(get_service_detail "$config_name" ping)

	local olsr_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	[ -z "$olsr_prefix" ] && msg_info "FATAL ERROR: failed to enforce olsr nameservice plugin" && trap "" $GUARD_TRAPS && return 1

	port=$(get_local_ugw_service_port "$config_name")

	# announce our ugw service
	# TODO: Anpassung an verschiedene Dienste
	if [ "$(uci_get "${ugw_prefix}.type")" = "openvpn" ]; then
		service_description="openvpn://${main_ip}:$port|udp|ugw upload:$upload download:$download ping:$ping creator:$UGW_SERVICE_CREATOR"
	else
		service_description=
	fi
	uci set "${ugw_prefix}.service=$service_description"
	# vorsorglich loeschen (Vermeidung doppelter Eintraege)
	uci -q del_list "${olsr_prefix}.service=$service_description" || true
	uci add_list "${olsr_prefix}.service=$service_description"
}


# Pruefe regelmaessig, ob Weiterleitungen zu allen bekannten UGW-Servern existieren.
# Fehlende Weiterleitungen oder olsr-Announcements werden angelegt.
ugw_update_service_status() {
	trap "error_trap ugw_update_service_status '$*'" $GUARD_TRAPS
	local name
	local ugw_name
	local ugw_enabled
	local uci_prefix
	local mtu_test
	local wan_test
	local openvpn_test
	local cert_available
	local sharing_enabled=$(uci_get on-usergw.ugw_sharing.shareInternet)
	[ -z "$sharing_enabled" ] && sharing_enabled=0
	prepare_on_usergw_uci_settings
	find_all_uci_sections on-usergw uplink | while read uci_prefix; do
		config_name=$(uci_get "${uci_prefix}.name")
		ugw_enabled=$(uci_get "${uci_prefix}.enable")
		openvpn_enable=$(uci_get "openvpn.${config_name}.enable")
		[ -z "$openvpn_enable" ] && openvpn_enable=1
		mtu_test=$(get_service_value "$config_name" "mtu_status")
		wan_test=$(get_service_value "$config_name" "wan_status")
		openvpn_test=$(get_service_value "$config_name" "status")
		cert_available=$(openvpn_service_has_certificate_and_key "$config_name" && echo y || echo n)

		# Ziel ist die Aktivierung der openvpn-Verbindung, sowie die Announcierung des Dienstes
		# und die Einrichtung der Port-Weiterleitungen
		if uci_is_false "$openvpn_enable"; then
			# openvpn-Setup ist abgeschaltet - soll es aktiviert werden?
			if uci_is_true "$mtu_test" && uci_is_true "$wan_test" && \
					uci_is_true "$openvpn_test" && \
					uci_is_true "$sharing_enabled"; then
				enable_ugw_service "$config_name"
			fi
		else
			# openvpn-Setup ist aktiviert - muss es abgeschaltet werden?
			if uci_is_false "$mtu_test" || uci_is_false "$wan_test" || \
					uci_is_false "$openvpn_test" || \
					uci_is_false "$sharing_enabled"; then
				disable_ugw_service "$config_name"
			fi
		fi
	done
	disable_stale_ugw_services
	apply_changes openvpn
	apply_changes on-usergw
	apply_changes firewall
	apply_changes olsrd
}


# Anlegen der on-usergw-Konfiguration, sowie Erzeugung ueblicher Sektionen.
# Diese Funktion sollte vor Scheibzugriffen in diesem Bereich aufgerufen werden.
prepare_on_usergw_uci_settings() {
	local section
	# on-usergw-Konfiguration erzeugen, falls noetig
	[ -e /etc/config/on-usergw ] || touch /etc/config/on-usergw
	for section in ugw_sharing; do
		uci show | grep -q "^on-usergw\.${section}\." || uci set "on-usergw.${section}=$section"
	done
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
