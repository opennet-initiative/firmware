## @defgroup on-service-relay Dienst-Weiterleitungen
# Beginn der Doku-Gruppe
## @{

## eine beliebige Portnummer, auf der wir keinen udp-Dienst vermuten
SPEEDTEST_UPLOAD_PORT=29418
SPEEDTEST_SECONDS=20
UGW_FIREWALL_RULE_NAME=opennet_ugw
## für die Kompatibilität mit Firmware vor v0.5
UGW_LOCAL_SERVICE_PORT_LEGACY=1600
DEFAULT_MESH_OPENVPN_PORT=1602
## falls mehr als ein GW-Dienst weitergereicht wird, wird dieser Port und die folgenden verwendet
UGW_LOCAL_SERVICE_PORT_START=5100
# Markierung fuer firewall-Regeln, die zu Dienst-Weiterleitungen gehören
SERVICE_RELAY_CREATOR=on_service_relay


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
		[ "$creator" = "$SERVICE_RELAY_CREATOR" ] || continue
		# unbenutzte Eintraege entfernen
		_is_ugw_service_in_use "$service" || uci del_list "${uci_prefix}.service=$service"
	done
	return 0
}


# Pruefung ob ein lokaler Port bereits fuer einen ugw-Dienst weitergeleitet wird
_is_local_ugw_port_unused() {
	local port="$1"
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
get_local_service_relay_port() {
	local config_name="$1"
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
	local service_name=$1
	local main_ip=$(get_main_ip)
	local usergw_uci=$(find_first_uci_section on-usergw uplink "name=$service_name")
	local hostname
	local uci_prefix=$(uci_get "${usergw_uci}.firewall_rule")
	[ -z "$uci_prefix" ] && uci_prefix=firewall.$(uci add firewall redirect)
	# der Name ist wichtig fuer spaetere Aufraeumaktionen
	uci set "${uci_prefix}.name=$UGW_FIREWALL_RULE_NAME"
	uci set "${uci_prefix}.src=$ZONE_MESH"
	uci set "${uci_prefix}.proto=$(uci_get "${usergw_uci}.protocol")"
	uci set "${uci_prefix}.src_dport=$(get_local_service_relay_port "$service_name")"
	uci set "${uci_prefix}.target=DNAT"
	uci set "${uci_prefix}.src_dip=$main_ip"
	hostname=$(uci_get "${usergw_uci}.hostname")
	# wir verwenden nur die erste aufgeloeste IP, zu welcher wir eine Route haben.
	# z.B. faellt IPv6 aus, falls wir kein derartiges Uplink-Interface sehen
	uci set "${uci_prefix}.dest_ip=$(query_dns "$hostname" | filter_routable_addresses | head -n 1)"
	# olsr-nameservice-Announcement
	announce_olsr_service_ugw "$service_name"
	# VPN-Verbindung
	update_one_openvpn_ugw_setup "$service_name"
	uci set "openvpn.${service_name}.enable=1"
	apply_changes openvpn
	# unabhaengig von moeglichen Aenderungen: fehlende Dienste neu starten
	/etc/init.d/openvpn reload
	apply_changes on-usergw
	apply_changes firewall
	apply_changes olsrd
}


## @fn add_service_relay_forward_rule()
## @brief Erzeuge die Firewall-Weiterleitungsregel für einen durchgereichten Dienst.
## @param service_name der weiterzuleitende Dienst
## @attention Anschließend muss die firewall-uci-Sektion committed werden. 
add_service_relay_forward_rule() {
	local service_name="$1"
	local port=$(get_service_value "$port")
	local host=$(get_service_value "$host")
	local main_ip=$(get_main_ip)
	local target_ip=$(query_dns "$hostname" | filter_routable_addresses | head -n 1)
	# wir verwenden nur die erste aufgeloeste IP, zu welcher wir eine Route haben.
	# z.B. faellt IPv6 aus, falls wir kein derartiges Uplink-Interface sehen
	local uci_match=$(find_first_uci_section on-usergw redirect \
		"target=DNAT" "name=$service_name" "proto=$protocol" \
		"src=$ZONE_MESH" "src_dip=$main_ip" \
		"dest=$ZONE_WAN" "dest_port=$port" "dest_ip=$target_ip")
	# perfekt passende Regel gefunden? Fertig ...
	[ -n "$uci_match" ] && return 0
	local uci_match=$(find_first_uci_section on-usergw redirect "target=DNAT" "name=$service_name")
	# unvollstaendig passendes Ergebnis? Loesche es (der Ordnung halber) ...
	[ -n "$uci_match" ] && uci_delete "$uci_match"
	# neue Regel anlegen
	local uci_prefix=firewall.$(uci add firewall redirect)
	# der Name ist wichtig fuer spaetere Aufraeumaktionen
	uci set "${uci_prefix}.name=$service_name"
	uci set "${uci_prefix}.target=DNAT"
	uci set "${uci_prefix}.proto=$protocol"
	uci set "${uci_prefix}.src=$ZONE_MESH"
	uci set "${uci_prefix}.src_dip=$main_ip"
	uci set "${uci_prefix}.src_dport=$(get_local_service_relay_port "$service_name")"
	uci set "${uci_prefix}.dest=$ZONE_WAN"
	uci set "${uci_prefix}.dest_port=$port"
	uci set "${uci_prefix}.dest_ip=$target_ip"
	# die Abhängigkeit speichern
	service_add_uci_dependency "$service_name" "$uci_prefix"
}


## @fn announce_olsr_service_relay()
## @brief Verkuende das lokale Relay eines öffentlichen Dienstes inkl. Geschwindigkeitsdaten via olsr nameservice.
## @param service_name Name des zu veröffentlichenden Diensts
## @attention Anschließend muss die uci-Sektion 'olsrd' committed werden.
announce_olsr_service_relay() {
	trap "error_trap announce_ugw_service_ugw '$*'" $GUARD_TRAPS
	local service_name=$1
	local main_ip=$(get_main_ip)

	local download=$(get_service_detail "$service_name" download)
	local upload=$(get_service_detail "$service_name" upload)
	local ping=$(get_service_detail "$service_name" ping)

	local olsr_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	[ -z "$olsr_prefix" ] && msg_info "FATAL ERROR: failed to enforce olsr nameservice plugin" && trap "" $GUARD_TRAPS && return 1

	local port=$(get_local_service_relay_port "$service_name")
	local protocol=$(get_service_value "$service_name" "protocol")
	local service_type=$(get_service_value "$service_name" "scheme")

	# announce the service
	local service_description="${scheme}://${main_ip}:${port}|${protocol}|${service} upload:$upload download:$download ping:$ping creator:$SERVICE_RELAY_CREATOR"
	uci_add_list "${olsr_prefix}.service=$service_description"
	# TODO: da es sich um eine Liste mehrerer Elemente handelt, wollen wir keinesfalls die ganze Liste löschen
	service_add_uci_dependency "$service_name" "$uci_prefix"
}


# Pruefe regelmaessig, ob Weiterleitungen zu allen bekannten UGW-Servern existieren.
# Fehlende Weiterleitungen oder olsr-Announcements werden angelegt.
update_service_relay_status() {
	trap "error_trap ugw_update_service_status '$*'" $GUARD_TRAPS
	local name
	local uci_prefix
	TODO: neu!
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

# Ende der Doku-Gruppe
## @}
