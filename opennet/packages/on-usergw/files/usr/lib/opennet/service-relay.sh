## @defgroup on-service-relay Dienst-Weiterleitungen
# Beginn der Doku-Gruppe
## @{

## für die Kompatibilität mit Firmware vor v0.5
UGW_LOCAL_SERVICE_PORT_LEGACY=1600
DEFAULT_MESH_OPENVPN_PORT=1602
## falls mehr als ein GW-Dienst weitergereicht wird, wird dieser Port und die folgenden verwendet
SERVICE_RELAY_LOCAL_RELAY_PORT_START=5100
# Markierung fuer firewall-Regeln, die zu Dienst-Weiterleitungen gehören
SERVICE_RELAY_FIREWALL_RULE_PREFIX=on_service_relay_


# Pruefung ob ein lokaler Port bereits fuer einen ugw-Dienst weitergeleitet wird
_is_local_service_relay_port_unused() {
	local port="$1"
	local collisions
	collisions=$(get_services | filter_services_by_value "local_relay_port" "$port")
	[ -n "$collisions" ] && trap "" $GUARD_TRAPS && return 1
	# keine Kollision entdeckt
	return 0
}


# Liefere den Port zurueck, der einer Dienst-Weiterleitung lokal zugewiesen wurde.
# Falls noch kein Port definiert ist, dann waehle einen neuen Port.
# Parameter: config_name
pick_local_service_relay_port() {
	trap "error_trap pick_local_service_relay_port '$*'" $GUARD_TRAPS
	local service_name="$1"
	local port
	port=$(get_service_value "$service_name" "local_relay_port")
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
	# wir erwarten einen ausführbaren Testnamen
	local test_for_activity="$1"
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
		"$test_for_activity" "$service_name" && continue
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
	local host
	local uci_match
	local rule_name
	local uci_prefix
	uci_match=$(get_service_relay_port_forwarding "$service_name")
	# perfekt passende Regel gefunden? Fertig ...
	[ -n "$uci_match" ] && return 0
	host=$(get_service_value "$service_name" "host")
	rule_name="${SERVICE_RELAY_FIREWALL_RULE_PREFIX}${service_name}"
	uci_match=$(find_first_uci_section firewall redirect "target=DNAT" "name=$rule_name")
	# unvollstaendig passendes Ergebnis? Loesche es (der Ordnung halber) ...
	[ -n "$uci_match" ] && uci_delete "$uci_match"
	# neue Regel anlegen
	uci_prefix=firewall.$(uci add firewall redirect)
	# der Name ist wichtig fuer spaetere Aufraeumaktionen
	uci set "${uci_prefix}.name=${SERVICE_RELAY_FIREWALL_RULE_PREFIX}${service_name}"
	uci set "${uci_prefix}.target=DNAT"
	uci set "${uci_prefix}.proto=$(get_service_value "$service_name" "protocol")"
	uci set "${uci_prefix}.src=$ZONE_MESH"
	uci set "${uci_prefix}.src_dip=$(get_main_ip)"
	uci set "${uci_prefix}.src_dport=$(get_service_value "$service_name" "local_relay_port")"
	uci set "${uci_prefix}.dest=$ZONE_WAN"
	uci set "${uci_prefix}.dest_port=$(get_service_value "$service_name" "port")"
	uci set "${uci_prefix}.dest_ip=$(query_dns "$host" | filter_routable_addresses | tail -n 1)"
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


_get_service_relay_olsr_announcement_prefix() {
	trap "error_trap _get_service_relay_olsr_announcement_prefix '$*'" $GUARD_TRAPS
	local service_name="$1"
	local main_ip
	local service_type
	local scheme
	local host
	local port
	local protocol
	main_ip=$(get_main_ip)
	service_type=$(get_service_value "$service_name" "service")
	# remove prefix
	service_type="${service_type%$RELAYABLE_SERVICE_PREFIX}"
	scheme=$(get_service_value "$service_name" "scheme")
	host=$(get_service_value "$service_name" "host")
	port=$(pick_local_service_relay_port "$service_name")
	protocol=$(get_service_value "$service_name" "protocol")
	# announce the service
	echo "${scheme}://${main_ip}:${port}|${protocol}|${service_type}"
}


## @fn get_service_relay_olsr_announcement()
## @brief Ermittle den oder die OLSR-Nameservice-Announcements, die zu dem Dienst gehoeren.
get_service_relay_olsr_announcement() {
	trap "error_trap get_service_relay_olsr_announcement '$*'" $GUARD_TRAPS
	local service_name="$1"
	local announce_unique
	local uci_prefix
	announce_unique=$(_get_service_relay_olsr_announcement_prefix "$service_name")
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	uci_get_list "${uci_prefix}.service" | awk '{ if ($1 == "'$announce_unique'") print $0; }'
}


## @fn announce_olsr_service_relay()
## @brief Verkuende das lokale Relay eines öffentlichen Dienstes inkl. Geschwindigkeitsdaten via olsr nameservice.
## @param service_name Name des zu veröffentlichenden Diensts
## @attention Anschließend muss die uci-Sektion 'olsrd' committed werden.
announce_olsr_service_relay() {
	trap "error_trap announce_olsr_service_relay '$*'" $GUARD_TRAPS
	local service_name="$1"
	local service_unique
	local service_details
	service_unique=$(_get_service_relay_olsr_announcement_prefix "$service_name")
	# das 'service_name'-Detail wird fuer die anschliessende Beraeumung (firewall-Regeln usw.) verwendet
	# nur nicht-leere Attribute werden geschrieben
	service_details=$(while read key value; do [ -z "$value" ] && continue; echo "$key:$value"; done <<EOF
		public_host $(get_service_value "$service_name" "host")
		upload $(get_service_value "$service_name" "wan_speed_upload")
		download $(get_service_value "$service_name" "wan_speed_download")
		ping $(get_service_value "$service_name" "wan_ping")
EOF
)
	# Zeilenumbrueche durch Leerzeichen ersetzen, abschliessendes Leerzeichen entfernen
	service_details=$(echo "$service_details" | tr '\n' ' ' | sed 's/ $//')
	# loesche alte Dienst-Announcements mit demselben Prefix
	local this_unique
	local this_details
	local uci_prefix
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	get_service_relay_olsr_announcement "$service_name" | while read this_unique this_details; do
		# der Wert ist bereits korrekt - wir koennen abbrechen
		[ "$this_details" = "$service_details" ] && break
		# der Wert ist falsch: loeschen und am Ende neu hinzufuegen
		msg_debug "Deleting outdated service-relay announcement: $service_unique $this_details"
		uci_delete_list "${uci_prefix}.service" "$service_unique $this_details"
	done
	# falls keine Treffer gibt, fuegen wir ein neues Announcement hinzu
	if [ -z "$(get_service_relay_olsr_announcement "$service_name")" ]; then
		msg_debug "Adding new service-relay announcement: $service_unique $service_details"
		uci_add_list "${uci_prefix}.service" "$service_unique $service_details"
	fi
}


# olsr-Nameservice-Beschreibungen entfernen falls der dazugehoerige Dienst nicht mehr relay-tauglich ist
deannounce_unused_olsr_service_relays() {
	# wir erwarten einen ausführbaren Testnamen
	local test_for_activity="$1"
	local service_description
	local service_name
	local uci_prefix
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	uci_get_list "${uci_prefix}.service" | while read service_description; do
		# unbenutzte Eintraege entfernen
		service_name=$(get_olsr_service_name_from_description "$service_description")
		[ -z "$service_name" ] && msg_info "Failed to parse olsr service description: $service_description" && continue
		"$test_for_activity" "$service_name" && continue
		uci_delete_list "${uci_prefix}.service" "$service_description"
	done
	return 0
}


## @fn is_service_relay_possible()
## @brief Pruefe ob ein Relay-Dienst aktiviert (nicht "disabled") ist und ob das WAN-Routing korrekt ist.
is_service_relay_possible() {
	trap "error_trap is_service_relay_possible '$*'" $GUARD_TRAPS
	local service_name="$1"
	local enabled
	local wan_routing
	disabled=$(get_service_value "$service_name" "disabled" "false")
	uci_is_true "$disabled" && trap "" $GUARD_TRAPS && return 1
	wan_routing=$(get_service_value "$service_name" "wan_status" "false")
	uci_is_false "$wan_routing" && trap "" $GUARD_TRAPS && return 1
	return 0
}


## @fn update_service_relay_status()
## @brief Pruefe regelmaessig, ob Weiterleitungen für alle bekannten durchgereichten Diensten existieren.
## @details Fehlende Weiterleitungen oder olsr-Announcements werden angelegt.
update_service_relay_status() {
	trap "error_trap update_service_relay_status '$*'" $GUARD_TRAPS
	local service_name
	local wan_status
	if is_on_module_installed_and_enabled "on-usergw"; then
		get_services | filter_relay_services | while read service_name; do
			# WAN-Routing pruefen und aktualisieren
			is_service_routed_via_wan "$service_name" && wan_status="true" || wan_status="false"
			set_service_value "$service_name" "wan_status" "$wan_status"
			is_service_relay_possible "$service_name" || continue
			enable_service_relay "$service_name"
		done
		delete_unused_service_relay_forward_rules is_service_relay_possible
		deannounce_unused_olsr_service_relays is_service_relay_possible
		apply_changes firewall olsrd
	else
		disable_service_relay
	fi
}


## @fn disable_service_relay()
## @brief Schalte alle Weiterleitungen und Dienst-Announcierungen ab.
disable_service_relay() {
	trap "error_trap disable_service_relay '$*'" $GUARD_TRAPS
	local service_name
	get_services | filter_relay_services | while read service_name; do
		delete_unused_service_relay_forward_rules false
		deannounce_unused_olsr_service_relays false
	done
	apply_changes firewall olsrd
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


## @fn get_service_relay_port_forwarding()
## @brief Liefere den Namen der uci-Sektion des Relay-Service-Portforwarding zurueck.
## @param service_name Name des Relay-Service-Diensts.
## @returns Den uci-Namen oder nichts, falls keine Portweiterleitung existiert.
get_service_relay_port_forwarding() {
	trap "error_trap get_service_relay_port_forwarding '$*'" $GUARD_TRAPS
	local service_name="$1"
	local rule_name="${SERVICE_RELAY_FIREWALL_RULE_PREFIX}${service_name}"
	local port
	local host
	local protocol
	local main_ip
	local target_ip
	port=$(get_service_value "$service_name" "port")
	host=$(get_service_value "$service_name" "host")
	protocol=$(get_service_value "$service_name" "protocol")
	main_ip=$(get_main_ip)
	target_ip=$(query_dns "$host" | filter_routable_addresses | tail -n 1)
	# wir verwenden nur die erste aufgeloeste IP, zu welcher wir eine Route haben.
	# z.B. faellt IPv6 aus, falls wir kein derartiges Uplink-Interface sehen
	find_first_uci_section firewall redirect \
		"target=DNAT" "name=$rule_name" "proto=$protocol" \
		"src=$ZONE_MESH" "src_dip=$main_ip" \
		"dest=$ZONE_WAN" "dest_port=$port" "dest_ip=$target_ip"
}

# Ende der Doku-Gruppe
## @}
