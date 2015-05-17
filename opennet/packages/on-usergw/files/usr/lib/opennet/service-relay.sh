## @defgroup on-service-relay Dienst-Weiterleitungen
# Beginn der Doku-Gruppe
## @{

## eine beliebige Portnummer, auf der wir keinen udp-Dienst vermuten
SPEEDTEST_UPLOAD_PORT=29418
SPEEDTEST_SECONDS=20
## für die Kompatibilität mit Firmware vor v0.5
UGW_LOCAL_SERVICE_PORT_LEGACY=1600
DEFAULT_MESH_OPENVPN_PORT=1602
## falls mehr als ein GW-Dienst weitergereicht wird, wird dieser Port und die folgenden verwendet
SERVICE_RELAY_LOCAL_RELAY_PORT_START=5100
# Markierung fuer firewall-Regeln, die zu Dienst-Weiterleitungen gehören
SERVICE_RELAY_CREATOR=on_service_relay
SERVICE_RELAY_FIREWALL_RULE_PREFIX=on_service_relay_


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


# Pruefung ob ein lokaler Port bereits fuer einen ugw-Dienst weitergeleitet wird
_is_local_service_relay_port_unused() {
	local port="$1"
	local collisions=$(get_services | filter_services_by_value "local_relay_port" "$port")
	[ -n "$collisions" ] && trap "" $GUARD_TRAPS && return 1
	# keine Kollision entdeckt
	return 0
}


# Liefere den Port zurueck, der einer Dienst-Weiterleitung lokal zugewiesen wurde.
# Falls noch kein Port definiert ist, dann waehle einen neuen Port.
# Parameter: config_name
pick_local_service_relay_port() {
	local service_name="$1"
	local port=$(get_service_value "$service_name" "local_relay_port")
	# falls unbelegt: suche einen unbenutzten lokalen Port
	if [ -z "$port" ]; then
		# fuer IGW-Verbindungen: belege zuerst den alten Standard-Port (fuer alte Clients)
		if [ "$(get_service_value "$service_name" "service")" = "gw" ]; then
			_is_local_service_relay_port_unused "$UGW_LOCAL_SERVICE_PORT_LEGACY" \
				&& port="$UGW_LOCAL_SERVICE_PORT_LEGACY"
			true
		fi
	fi
	if [ -z "$port" ]; then
		port="$SERVICE_RELAY_LOCAL_RELAY_PORT_START"
		until _is_local_service_relay_port_unused "$port"; do
			: $((port++))
		done
	fi
	set_service_value "$service_name" "local_relay_port" "$port"
	echo "$port"
}


## @fn delete_unused_service_relay_forward_rules()
## @brief Lösche ungenutzte Firewall-Weiterleitungsregel für einen durchgereichten Dienst.
## @attention Anschließend muss die firewall-uci-Sektion committed werden. 
delete_unused_service_relay_forward_rules() {
	trap "error_trap delete_unused_service_relay_forward_rules '$*'" $GUARD_TRAPS
	local uci_prefix
	local fw_rule_name
	local service_name
	local prefix_length="${#SERVICE_RELAY_FIREWALL_RULE_PREFIX}"
	# es ist nicht leicht, herauszufinden, welche Regeln zu uns gehören - wir verwenden das Namenspräfix
	find_all_uci_sections firewall redirect "target=DNAT" "src=$ZONE_MESH" "dest=$ZONE_WAN" | while read uci_prefix; do
		fw_rule_name=$(uci_get "${uci_prefix}.name")
		# passt das Namenspräfix?
		[ "${fw_rule_name:0:$prefix_length}" != "$SERVICE_RELAY_FIREWALL_RULE_PREFIX" ] && continue
		# schneide das Präfix ab, um den Dienstnamen zu ermitteln
		service_name="${fw_rule_name:$prefix_length}"
		is_service_relay_possible "$service_name" && continue
		uci_delete "${uci_prefix}"
	done
}


## @fn add_service_relay_forward_rule()
## @brief Erzeuge die Firewall-Weiterleitungsregel für einen durchgereichten Dienst.
## @param service_name der weiterzuleitende Dienst
## @attention Anschließend muss die firewall-uci-Sektion committed werden. 
add_service_relay_forward_rule() {
	trap "error_trap add_service_relay_forward_rule '$*'" $GUARD_TRAPS
	local service_name="$1"
	local rule_name="${SERVICE_RELAY_FIREWALL_RULE_PREFIX}${service_name}"
	local port=$(get_service_value "$service_name" "port")
	local host=$(get_service_value "$service_name" "host")
	local protocol=$(get_service_value "$service_name" "protocol")
	local local_relay_port=$(get_service_value "$service_name" "local_relay_port")
	local main_ip=$(get_main_ip)
	local target_ip=$(query_dns "$host" | filter_routable_addresses | tail -n 1)
	# wir verwenden nur die erste aufgeloeste IP, zu welcher wir eine Route haben.
	# z.B. faellt IPv6 aus, falls wir kein derartiges Uplink-Interface sehen
	local uci_match=$(find_first_uci_section firewall redirect \
		"target=DNAT" "name=$rule_name" "proto=$protocol" \
		"src=$ZONE_MESH" "src_dip=$main_ip" \
		"dest=$ZONE_WAN" "dest_port=$port" "dest_ip=$target_ip")
	# perfekt passende Regel gefunden? Fertig ...
	[ -n "$uci_match" ] && return 0
	local uci_match=$(find_first_uci_section firewall redirect "target=DNAT" "name=$rule_name")
	# unvollstaendig passendes Ergebnis? Loesche es (der Ordnung halber) ...
	[ -n "$uci_match" ] && uci_delete "$uci_match"
	# neue Regel anlegen
	local uci_prefix=firewall.$(uci add firewall redirect)
	# der Name ist wichtig fuer spaetere Aufraeumaktionen
	uci set "${uci_prefix}.name=$rule_name"
	uci set "${uci_prefix}.target=DNAT"
	uci set "${uci_prefix}.proto=$protocol"
	uci set "${uci_prefix}.src=$ZONE_MESH"
	uci set "${uci_prefix}.src_dip=$main_ip"
	uci set "${uci_prefix}.src_dport=$local_relay_port"
	uci set "${uci_prefix}.dest=$ZONE_WAN"
	uci set "${uci_prefix}.dest_port=$port"
	uci set "${uci_prefix}.dest_ip=$target_ip"
	# die Abhängigkeit speichern
	service_add_uci_dependency "$service_name" "$uci_prefix"
}


## @fn enable_service_relay()
## @brief Aktiviere die Weiterleitung eines öffentlichen Diensts.
## @param service_name Name des durchzuleitenden Diensts
## @attention Anschließend müssen die uci-Sektion 'olsrd' und 'firewall' committed werden.
enable_service_relay() {
	trap "error_trap enable_service_relay '$*'" $GUARD_TRAPS
	local service_name="$1"
	add_service_relay_forward_rule "$service_name"
	announce_olsr_service_relay "$service_name"
}


## @fn announce_olsr_service_relay()
## @brief Verkuende das lokale Relay eines öffentlichen Dienstes inkl. Geschwindigkeitsdaten via olsr nameservice.
## @param service_name Name des zu veröffentlichenden Diensts
## @attention Anschließend muss die uci-Sektion 'olsrd' committed werden.
announce_olsr_service_relay() {
	trap "error_trap announce_olsr_service_relay '$*'" $GUARD_TRAPS
	local service_name="$1"
	local main_ip=$(get_main_ip)

	local download=$(get_service_detail "$service_name" download)
	local upload=$(get_service_detail "$service_name" upload)
	local ping=$(get_service_detail "$service_name" ping)

	local uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	[ -z "$uci_prefix" ] && msg_error "Failed to enforce olsr nameservice plugin" && trap "" $GUARD_TRAPS && return 1

	local service_type=$(get_service_value "$service_name" "service")
	local scheme=$(get_service_value "$service_name" "scheme")
	local host=$(get_service_value "$service_name" "host")
	local port=$(pick_local_service_relay_port "$service_name")
	local protocol=$(get_service_value "$service_name" "protocol")

	# announce the service
	local service_unique="${scheme}://${main_ip}:${port}|${protocol}|${service_type}"
	# das 'service_name'-Detail wird fuer die anschliessende Beraeumung (firewall-Regeln usw.) verwendet
	local service_details="upload:$upload download:$download ping:$ping creator:$SERVICE_RELAY_CREATOR public_host:$host service_name:$service_name"
	# loesche alte Dienst-Announcements mit demselben Prefix
	local this_unique
	local this_details
	uci_get_list "${uci_prefix}.service" \
			| awk "{ if (\$1 == \"$service_unique\") print \$0; }" \
			| cut -f 2- -d " " \
			| while read this_details; do
		# der Wert ist bereits korrekt - wir koennen abbrechen
		[ "$this_details" = "$service_details" ] && break
		# der Wert ist falsch: loeschen und am Ende neu hinzufuegen
		msg_debug "Deleting outdated service-relay announcement: $service_unique $this_details"
		uci_delete_list "${uci_prefix}.service" "$service_unique $this_details"
	done
	local matches=$(uci_get_list "${uci_prefix}.service" | awk "{ if (\$1 == \"$service_unique\") print \$0; }")
	# falls keine Treffer gibt, fuegen wir ein neues Announcement hinzu
	if [ -z "$matches" ]; then
		msg_debug "Adding new service-relay announcement: $service_unique $service_details"
		uci_add_list "${uci_prefix}.service" "$service_unique $service_details"
	fi
}


# olsr-Nameservice-Beschreibungen entfernen
deannounce_unused_olsr_service_relays() {
	local service_description
	local extra_info
	local creator
	local service_name
	local uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	uci_get_list "${uci_prefix}.service" | while read service_description; do
		extra_info=$(echo "$service_description" | parse_olsr_service_definitions | cut -f 7)
		creator=$(echo "$extra_info" | get_from_key_value_list "creator" :)
		# ausschließlich Eintrage mit unserem "creator"-Stempel beachten
		[ "$creator" = "$SERVICE_RELAY_CREATOR" ] || continue
		# unbenutzte Eintraege entfernen
		service_name=$(echo "$extra_info" | get_from_key_value_list "service_name" :)
		is_service_relay_possible "$service_name" && continue
		uci_delete_list "${uci_prefix}.service" "$service_description"
	done
	return 0
}


is_service_relay_possible() {
	trap "error_trap is_service_relay_possible '$*'" $GUARD_TRAPS
	local service_name="$1"
	local enabled
	local wan_routing
	enabled=$(get_service_value "$service_name" "true")
	uci_is_false "$enabled" && trap "" $GUARD_TRAPS && return 1
	wan_routing=$(get_service_value "$service_name" "wan_status" "false")
	uci_is_false "$wan_routing" && trap "" $GUARD_TRAPS && return 1
	return 0
}


# Pruefe regelmaessig, ob Weiterleitungen für alle bekannten durchgereichten Diensten existieren.
# Fehlende Weiterleitungen oder olsr-Announcements werden angelegt.
update_service_relay_status() {
	trap "error_trap update_service_relay_status '$*'" $GUARD_TRAPS
	local service_name
	get_services | filter_relay_services | while read service_name; do
		is_service_relay_possible "$service_name" && enable_service_relay "$service_name"
		true
	done
	delete_unused_service_relay_forward_rules
	deannounce_unused_olsr_service_relays
	apply_changes firewall
	apply_changes olsrd
}


## @fn filter_relay_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die als Dienst-Relay fungieren.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an die Standardausgabe
##   weitergeleitet, falls es sich um einen Relay-Dienst handelt.
filter_relay_services() {
	local service_name
	while read service_name; do
		[ -n "$(get_service_value "$service_name" "local_relay_port")" ] && echo "$service_name"
		true
	done
}

# Ende der Doku-Gruppe
## @}
