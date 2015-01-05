UGW_STATUS_FILE=/tmp/on-ugw_gateways.status
ON_USERGW_DEFAULTS_FILE=/usr/share/opennet/usergw.defaults
# eine beliebige Portnummer, auf der wir keinen Dienst vermuten
SPEEDTEST_UPLOAD_PORT=29418
SPEEDTEST_SECONDS=20
UGW_FIREWALL_RULE_NAME=opennet_ugw
UGW_LOCAL_SERVICE_PORT_START=5100
UGW_SERVICE_CREATOR=ugw_service


# hole einen der default-Werte der aktuellen Firmware
# Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
# Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfuegbar.
get_on_usergw_default() { _get_file_dict_value "$ON_USERGW_DEFAULTS_FILE" "$1"; }


#################################################################################
# Auslesen einer Gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
get_ugw_value() {
	_get_file_dict_value "$UGW_STATUS_FILE" "${1}_${2}"
}


#################################################################################
# Aendere eine gateway-Information
# Parameter ip: IP-Adresse des Gateways
# Parameter key: Informationsschluessel ("age", "status", ...)
# Parameter value: der neue Inhalt
set_ugw_value() {
	_set_file_dict_value "$UGW_STATUS_FILE" "${1}_${2}" "$3"
}


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


# Erzeuge einen neuen ugw-Service.
# Ignoriere doppelte Eintraege.
# Es wird _kein_ "uci commit" durchgefuehrt.
# TODO: nahezu identisch mit add_openvpn_mig_service
add_openvpn_ugw_service() {
	local hostname=$1
	local port=$2
	local protocol=$3
	local details=$4
	local uci_prefix
	local ipaddr
	local template
	local config_dir
	local config_file
	local config_name
	local safe_hostname
	local config_prefix
	if [ "$protocol" = "udp" ]; then
		template=/usr/share/opennet/openvpn-ugw-udp.template
		config_dir=$OPENVPN_CONFIG_BASEDIR
		config_prefix=on_ugw
	else
		msg_info "failed to add openvpn service for UGW due to invalid protocol ($protocol)"
		return 1
	fi
	[ "$protocol" != "tcp" -a "$protocol" != "udp" ] && \
		msg_info "failed to set up openvpn settings for invalid protocol ($protocol)" && return 1
	# config-Schluessel erstellen
	safe_hostname=$(echo "$hostname" | sed 's/[^a-zA-Z0-9]/_/g')
	config_name=openvpn_${config_prefix}_${safe_hostname}_${protocol}_${port}
	config_file=$config_dir/${config_name}.conf
	prepare_on_usergw_uci_settings
	uci_prefix=$(find_first_uci_section on-usergw uplink "name=$config_name")
	[ -z "$uci_prefix" ] && uci_prefix=on-usergw.$(uci add on-usergw uplink)
	# neuer Eintrag? Dann moege er aktiv sein.
	[ -z "$(uci_get "${uci_prefix}.enable")" ] && uci set "${uci_prefix}.enable=1"
	uci set "${uci_prefix}.name=$config_name"
	uci set "${uci_prefix}.type=openvpn"
	uci set "${uci_prefix}.hostname=$hostname"
	uci set "${uci_prefix}.template=$template"
	uci set "${uci_prefix}.config_file=$config_file"
	uci set "${uci_prefix}.port=$port"
	uci set "${uci_prefix}.protocol=$protocol"
	# Zeitstempel auffrischen
	set_ugw_value "$config_name" last_seen "$(date +%s)"
	# Details koennen sich haeufig aendern (z.B. Geschwindigkeiten)
	set_ugw_value "$config_name" details "$details"
}


# Parse die Liste der via olsrd-nameservice announcierten ugw-Dienste.
# Falls keine UGW-Dienste gefunden werden, bzw. vorher konfiguriert waren, werden die Standard-Opennet-Server eingetragen.
# Speichere diese Liste als on-userugw.@uplink-Liste.
# Anschliessend werden eventuell Dienste (z.B. openvpn) neu konfiguriert.
update_ugw_services() {
	trap "error_trap update_ugw_services '$*'" $GUARD_TRAPS
	local scheme
	local ipaddr
	local port
	local proto
	local details
	local hostname
	local service_description
	get_olsr_services mesh | cut -f 1,2,3,5,7 | while read scheme ipaddr port proto details; do
		service_description="$scheme://$ipaddr:$port ($proto) $details"
		if [ "$scheme" = "openvpn" ]; then
			hostname=$(echo "$details" | get_from_key_value_list hostname :)
			if [ -n "$hostname" ]; then
				add_openvpn_ugw_service "$hostname" "$port" "$proto" "$details"
			else
				msg_info "ignoring service due to missing hostname: $service_description"
			fi
		else
			msg_info "update_ugw_services: unbekannter ugw-Service: $service_description"
		fi
	done
	# pruefe ob keine UGWs konfiguriert sind - erstelle andernfalls die Standard-UGWs von Opennet
	prepare_on_usergw_uci_settings
	[ -z "$(find_all_uci_sections on-usergw uplink)" ] && add_default_openvpn_ugw_services
	# Portweiterleitungen aktivieren
	# kein "apply_changes" - andernfalls koennten Loops entstehen
	uci commit on-usergw
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
	find_all_uci_sections on-usergw uplink | while read uci_prefix; do
		[ "$port" = "$(uci_get "${uci_prefix}.local_port")" ] && return 1 || true
	done
	# keine Kollision entdeckt
	return 0
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

	local download=$(get_ugw_value "$config_name" download)
	local upload=$(get_ugw_value "$config_name" upload)
	local ping=$(get_ugw_value "$config_name" ping)

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
ugw_update_service_state () {
	trap "error_trap ugw_update_service_state '$*'" $GUARD_TRAPS
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
		mtu_test=$(get_ugw_value "$config_name" mtu)
		wan_test=$(get_ugw_value "$config_name" wan)
		openvpn_test=$(get_ugw_value "$config_name" status)
		cert_available=$(openvpn_has_certificate "$config_name" && echo y || echo n)

		# Ziel ist die Aktivierung der openvpn-Verbindung, sowie die Announcierung des Dienstes
		# und die Einrichtung der Port-Weiterleitungen
		if uci_is_false "$openvpn_enable"; then
			# openvpn-Setup ist abgeschaltet - soll es aktiviert werden?
			if [ "$mtu_test" = "ok" -a "$wan_test" = "ok" ] && \
					uci_is_true "$openvpn_test" && \
					uci_is_true "$sharing_enabled"; then
				enable_ugw_service "$config_name"
			fi
		else
			# openvpn-Setup ist aktiviert - muss es abgeschaltet werden?
			if [ "$mtu_test" != "ok" -o "$wan_test" != "ok" ] || \
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

