## @defgroup on-service-relay Dienst-Weiterleitungen
# Beginn der Doku-Gruppe
## @{

## für die Kompatibilität mit Firmware vor v0.5
## falls mehr als ein GW-Dienst weitergereicht wird, wird dieser Port und die folgenden verwendet
SERVICE_RELAY_LOCAL_RELAY_PORT_START=5100


# Pruefung ob ein lokaler Port bereits fuer einen ugw-Dienst weitergeleitet wird
_is_local_service_relay_port_unused() {
	local port="$1"
	local collisions
	collisions=$(get_services | filter_services_by_value "local_relay_port" "$port")
	[ -n "$collisions" ] && trap "" EXIT && return 1
	# keine Kollision entdeckt
	return 0
}


# Liefere den Port zurueck, der einer Dienst-Weiterleitung lokal zugewiesen wurde.
# Falls noch kein Port definiert ist, dann waehle einen neuen Port.
# Parameter: config_name
pick_local_service_relay_port() {
	trap 'error_trap pick_local_service_relay_port "$*"' EXIT
	local service_name="$1"
	local port
	port=$(get_service_value "$service_name" "local_relay_port")
	# falls unbelegt: suche einen unbenutzten lokalen Port
	if [ -z "$port" ]; then
		port="$SERVICE_RELAY_LOCAL_RELAY_PORT_START"
		until _is_local_service_relay_port_unused "$port"; do
			port=$((port + 1))
		done
	fi
	set_service_value "$service_name" "local_relay_port" "$port"
	echo "$port"
}


## @fn update_relay_firewall_rules
## @brief Erstelle die Liste aller Firewall-Regeln fuer Service-Relay-Weiterleitungen neu.
## @details Diese Funktion wird als Teil des Firewall-Reload-Prozess und nach Service-Relay-Aenderungen
##   aufgerufen.
update_relay_firewall_rules() {
	trap 'error_trap update_relay_firewall_rules "$*"' EXIT
	local host
	local port
	local protocol
	local target_ip
	local main_ip
	local table="on_usergw_table"
	local dnat_chain="on_service_relay_dnat"
	local new_rules
	main_ip=$(get_main_ip)
	# calculate the entries for the new rules
	# We need to do this in advance - otherwise it could happen, that DNS problems could cause
	# invalid (i.e. missing) firewall rules. Only if at least one valid rule is calculated,
	# the rules are updated.
	new_rules=$(for service in $(get_services | filter_relay_services); do
		is_service_relay_possible "$service" || continue
		host=$(get_service_value "$service" "host")
		port=$(get_service_value "$service" "port")
		protocol=$(get_service_value "$service" "protocol")
		local_port=$(get_service_value "$service" "local_relay_port")
		target_ip=$(query_dns "$host" | filter_routable_addresses | tail -n 1)
		# skip entries in case of broken DNS resolution
		[ -z "$target_ip" ] && continue
		echo "$host $port $protocol $local_port $target_ip"
	done)
	# do not apply changes, if there are no valid rules
	[ -z "$new_rules" ] && return 0
	
	# alte Regeln aus Chains löschen (siehe auch /usr/share/nftables.d/ fuer Definition der Chain)
	nft flush chain inet "$table" "$dnat_chain"
	
	# DNAT Chain fuellen
	echo "$new_rules" | while read -r host port protocol local_port target_ip; do
		if is_ipv4 "$main_ip"; then
			nft add rule inet "$table" "$dnat_chain" ip daddr "$main_ip" "$protocol" dport "$local_port" counter dnat to "${target_ip}:${port}"
		else
			nft add rule inet "$table" "$dnat_chain" ip6 daddr "$main_ip" "$protocol" dport "$local_port" counter dnat to "${target_ip}:${port}"
		fi
	done
	# Connection-Tracking-Tabelle flushen
	# Sonst werden Aenderungen fuer bestehende Verbindungen nicht wirksam.
	echo f >/proc/net/nf_conntrack
}


_get_service_relay_olsr_announcement_prefix() {
	trap 'error_trap _get_service_relay_olsr_announcement_prefix "$*"' EXIT
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
	service_type="${service_type#$RELAYABLE_SERVICE_PREFIX}"
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
	trap 'error_trap get_service_relay_olsr_announcement "$*"' EXIT
	local service_name="$1"
	local announce_unique
	local uci_prefix
	announce_unique=$(_get_service_relay_olsr_announcement_prefix "$service_name")
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	uci_get_list "${uci_prefix}.service" | awk '{ if ($1 == "'"$announce_unique"'") print $0; }'
}


## @fn announce_olsr_service_relay()
## @brief Verkuende das lokale Relay eines öffentlichen Dienstes inkl. Geschwindigkeitsdaten via olsr nameservice.
## @param service_name Name des zu veröffentlichenden Diensts
## @attention Anschließend muss die uci-Sektion 'olsrd' committed werden.
announce_olsr_service_relay() {
	trap 'error_trap announce_olsr_service_relay "$*"' EXIT
	local service_name="$1"
	local service_unique
	local service_details
	service_unique=$(_get_service_relay_olsr_announcement_prefix "$service_name")
	# das 'service_name'-Detail wird fuer die anschliessende Beraeumung (firewall-Regeln usw.) verwendet
	# nur nicht-leere Attribute werden geschrieben
	service_details=$(while read -r key value; do [ -z "$value" ] && continue; echo "$key:$value"; done <<EOF
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
	# shellcheck disable=SC2034
	get_service_relay_olsr_announcement "$service_name" | while read -r this_unique this_details; do
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


## @fn get_olsr_relay_service_name_from_description()
## @brief Ermittle den Dienstnamen, der zu einer olsr-Relay-Service-Definition gehoert.
get_olsr_relay_service_name_from_description() {
	trap 'error_trap get_olsr_relay_service_name_from_description "$*"' EXIT
	local service_description="$1"
	local fields
	local port
	local service_type
	fields=$(echo "$service_description" | parse_olsr_service_descriptions)
	port=$(echo "$fields" | cut -f 4)
	service_type=$(echo "$fields" | cut -f 1)
	get_services "${RELAYABLE_SERVICE_PREFIX}$service_type" | filter_services_by_value "local_relay_port" "$port"
}


# olsr-Nameservice-Beschreibungen entfernen falls der dazugehoerige Dienst nicht mehr relay-tauglich ist
deannounce_unused_olsr_service_relays() {
	# wir erwarten einen ausführbaren Testnamen
	local test_for_activity="$1"
	local service_description
	local service_name
	local uci_prefix
	uci_prefix=$(get_and_enable_olsrd_library_uci_prefix "nameservice")
	uci_get_list "${uci_prefix}.service" | while read -r service_description; do
		# unbenutzte Eintraege entfernen
		service_name=$(get_olsr_relay_service_name_from_description "$service_description")
		# falls es den Dienst noch gibt: ist er immer noch aktiv?
		[ -n "$service_name" ] && "$test_for_activity" "$service_name" && continue
		uci_delete_list "${uci_prefix}.service" "$service_description"
	done
	return 0
}


## @fn is_service_relay_possible()
## @brief Pruefe ob ein Relay-Dienst aktiviert (nicht "disabled") ist und ob das WAN-Routing korrekt ist.
is_service_relay_possible() {
	trap 'error_trap is_service_relay_possible "$*"' EXIT
	local service_name="$1"
	local disabled
	local wan_routing
	disabled=$(get_service_value "$service_name" "disabled" "false")
	uci_is_true "$disabled" && trap "" EXIT && return 1
	wan_routing=$(get_service_value "$service_name" "wan_status" "false")
	uci_is_false "$wan_routing" && trap "" EXIT && return 1
	return 0
}


## @fn update_service_relay_status()
## @brief Pruefe regelmaessig, ob Weiterleitungen für alle bekannten durchgereichten Diensten existieren.
## @details Fehlende Weiterleitungen oder olsr-Announcements werden angelegt.
update_service_relay_status() {
	trap 'error_trap update_service_relay_status "$*"' EXIT
	local service_name
	local wan_status
	if is_on_module_installed_and_enabled "on-usergw"; then
		for service_name in $(get_services | filter_relay_services); do
			# WAN-Routing pruefen und aktualisieren
			is_service_routed_via_wan "$service_name" && wan_status="true" || wan_status="false"
			set_service_value "$service_name" "wan_status" "$wan_status"
			is_service_relay_possible "$service_name" || continue
			announce_olsr_service_relay "$service_name"
		done
		update_relay_firewall_rules
		deannounce_unused_olsr_service_relays is_service_relay_possible
	else
		deannounce_unused_olsr_service_relays false
	fi
	apply_changes olsrd
}


## @fn filter_relay_services()
## @brief Filtere aus einer Reihe eingehender Dienste diejenigen heraus, die als Dienst-Relay fungieren.
## @details Die Dienst-Namen werden über die Standardeingabe gelesen und an die Standardausgabe
##   weitergeleitet, falls es sich um einen Relay-Dienst handelt.
filter_relay_services() {
	local service_name
	while read -r service_name; do
		[ -z "$(get_service_value "$service_name" "local_relay_port")" ] || echo "$service_name"
	done
}

# Ende der Doku-Gruppe
## @}
