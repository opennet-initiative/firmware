#permanent IPv6 Präfix (ULA)
IP6_PREFIX_PERM=fd32:d8d3:87da:0

IP6_PREFIX_LENGTH=64
NETWORK_LOOPBACK=on_loopback
ROUTING_TABLE_MESH_OLSR2=olsrd2
OLSR2_POLICY_DEFAULT_PRIORITY=20000
# interne Zahl fuer die "Domain" in olsr2
OLSR2_DOMAIN=0
OLSR2_UPDATE_LOCK_FILE=/var/run/on-update-olsr2-interfaces.lock
IPV6_NAME_MAP=/var/run/on-ipv6-name.map


## @fn get_mac_address()
## @brief Ermittle die erste nicht-Null MAC-Adresse eines echten Interfaces.
get_mac_address() {
	ip link | grep -A 1 '^[0-9]\+: \(eth\|wlan\)' | grep "link/ether" \
		| awk '{print $2}' | grep -v "^00:00:00:00:00:00$" | sort | head -1
}


## @fn shorten_ipv6_address()
## @brief Verkuerze eine IPv6-Adress-Repräsentation anhand der üblichen Regeln.
## Die Funktion ist kaum getestet - sie erzeugt sicherlich falsche Adressen (mehr als ein
## Doppel-Doppelpunkt, usw.).
shorten_ipv6_address() {
	# entferne alle führenden Nullen; ersetze die erste Gruppe von doppelten Nullen durch "::"
	sed -E 's/:0+([1-9a-f])/:\1/g; s/:0(:0)+:/::/'
}


## @fn convert_mac_to_eui64_address()
## @brief Wandle eine MAC-Adresse in ein IPv6-Suffix (64 bit) um.
convert_mac_to_eui64_address() {
	local prefix="$1"
	local mac="$2"
	# by default EUI64 conversion toggles the 7th most significant bit
	local mac_offset="${3:-0x020000000000}"
	local combined_mac
	combined_mac=$(echo "$mac" | cut -c 1-2,4-5,7-8,10-11,13-14,16-17)
	# MAC-Offset mit XOR verknüpfen
	combined_mac=$(printf "%012x" "$(( 0x$combined_mac ^ mac_offset ))")
	printf "%s:%s:%sff:fe%s:%s" "$prefix" "${combined_mac:0:4}" "${combined_mac:4:2}" \
		"${combined_mac:6:2}" "${combined_mac:8:4}" | shorten_ipv6_address
}


## @fn get_main_ipv6_address()
## @brief Ermittle die IPv6-Adresse des APs anhand des EUI64-Verfahrens.
get_main_ipv6_address() {
	printf "%s/%s" "$(convert_mac_to_eui64_address "$IP6_PREFIX_PERM" "$(get_mac_address)")" "$IP6_PREFIX_LENGTH"
}


## @fn configure_ipv6_address()
## @brief Konfiguriere die ermittelte IPv6-Adresse des AP auf dem loopback-Interface.
configure_ipv6_address() {
	local uci_prefix
	local main_ipv6
	uci_prefix="network.$NETWORK_LOOPBACK"
	main_ipv6=$(get_main_ipv6_address)
	[ "$main_ipv6" = "$(uci get "${uci_prefix}.ip6addr")" ] && return 0
	uci set "$uci_prefix=interface"
	uci set "${uci_prefix}.proto=static"
	uci set "${uci_prefix}.device=lo"
	echo "$main_ipv6" | uci_replace_list "${uci_prefix}.ip6addr"
	apply_changes network
}


## @fn update_olsr2_interfaces()
## @brief Mesh-Interfaces ermitteln und für olsrd2 konfigurieren
update_olsr2_interfaces() {
	local interfaces
	local uci_prefix
	local token
	local is_configured=0
	local pyh_if
	# auf IPv6 begrenzen (siehe http://www.olsr.org/mediawiki/index.php/OLSR_network_deployments)
	local ipv6_limit="-0.0.0.0/0 -::1/128 default_accept"
	interfaces="$NETWORK_LOOPBACK $(get_zone_interfaces "$ZONE_MESH")"
	# alle konfigurierten Interfaces durchgehen und überflüssige löschen
	for uci_prefix in $(find_all_uci_sections "olsrd2" "interface"); do
		# seit olsrd2 v0.12 benötigen wir "ifname" nicht mehr
		uci_delete "${uci_prefix}.ifname"
		# alle weiteren Interface-Sektionen loeschen, falls wir bereits fertig sind
		[ "$is_configured" = "1" ] && uci_delete "${uci_prefix}" && continue
		uci_delete "${uci_prefix}.ignore"
		# Interface auf IPv6 begrenzen
		[ -n "$(uci_get "${uci_prefix}.bindto")" ] || {
			for token in $ipv6_limit; do uci_add_list "${uci_prefix}.bindto" "$token"; done
		}
		# Die Liste der Netzwerkschnittstellen aktualisieren.
		# Alle veralteten Einträge entfernen.
		for token in $(uci_get_list "${uci_prefix}.name"); do
			echo "$interfaces" | grep -qwF "$token" && continue
			uci_delete_list "${uci_prefix}.name" "$token"
		done
		# Alle neuen hinzufügen.
		for token in $interfaces; do
			# olsrd2 benoetigt den physischen Interface-Namen (z.B. wlan0, tap0, eth4)
			# Wir versuche erst den physischen Interface-Namen zu ermitteln.
			phy_dev=$(uci_get network."$token".device)
			if [[ -n "$phy_dev" ]]; then
				# Wenn physicher Name nicht abgeleitet werden kann, dann gehen wir davon aus, 
				#  dass es bereits ein physischer Name ist.
				uci_add_list "${uci_prefix}.name" "$phy_dev"
			else
				uci_add_list "${uci_prefix}.name" "$token"
			fi
		done
		is_configured=1
	done
	if [ "$is_configured" = "0" ]; then
		uci_prefix="olsrd2.$(uci add "olsrd2" "interface")"
		for token in $ipv6_limit; do uci_add_list "${uci_prefix}.bindto" "$token"; done
		for token in $interfaces; do uci_add_list "${uci_prefix}.name" "$token"; done
	fi
	# Informationsversand auf IPv6 begrenzen
	uci_prefix=$(find_first_uci_section "olsrd2" "olsrv2")
	[ -z "$uci_prefix" ] && uci_prefix="olsrd2.$(uci add "olsrd2" "olsrv2")"
	[ -n "$(uci_get "${uci_prefix}.originator")" ] || {
		for token in $ipv6_limit; do
			uci_add_list "${uci_prefix}.originator" "$token"
		done
	}
	# prevent recursive trigger chaining
	if acquire_lock "$OLSR2_UPDATE_LOCK_FILE" 5 5; then
		# routing tables depend on the list of mesh interfaces
		init_policy_routing_ipv6
		apply_changes "olsrd2"
		rm -f "$OLSR2_UPDATE_LOCK_FILE"
	fi
}


## @update_olsr2_daemon_state()
## @brief Aktiviere oder deaktiviere den olsrd2-Dienst - je nach Modul-Aktiviertheit.
update_olsr2_daemon_state() {
	if is_on_module_installed_and_enabled "on-olsr2"; then
		/etc/init.d/olsrd2 enable || true
		if [ -z "$(pgrep olsrd2)" ]; then
			/etc/init.d/olsrd2 start
		else
			# "reload" does not seem to be sufficient after interface changes
			/etc/init.d/olsrd2 restart >/dev/null || true
		fi
	else
		/etc/init.d/olsrd2 disable || true
		[ -n "$(pgrep olsrd2)" ] && /etc/init.d/olsrd2 stop
		true
	fi
}


## @fn olsr2_sync_routing_tables()
## @brief Synchronisiere die olsrd-Routingtabellen-Konfiguration mit den iproute-Routingtabellennummern.
## @details Im Konfliktfall wird die olsrd-Konfiguration an die iproute-Konfiguration angepasst.
olsr2_sync_routing_tables() {
	trap 'error_trap olsr2_sync_routing_tables "$*"' EXIT
	local olsr2_id
	local iproute_id
	local uci_prefix
	uci_prefix=$(find_first_uci_section "olsrd2" "domain" "name=$OLSR2_DOMAIN")
	[ -z "$uci_prefix" ] && {
		uci_prefix="olsrd2.$(uci add "olsrd2" "domain")"
		uci set "${uci_prefix}.name=$OLSR2_DOMAIN"
	}
	olsr2_id=$(uci_get "${uci_prefix}.table")
	iproute_id=$(get_routing_table_id "$ROUTING_TABLE_MESH_OLSR2")
	# beide sind gesetzt und identisch? Alles ok ...
	[ -n "$olsr2_id" ] && [ "$olsr2_id" = "$iproute_id" ] && return 0
	# eventuell Tabelle erzeugen, falls sie noch nicht existiert
	[ -z "$iproute_id" ] && iproute_id=$(add_routing_table "$ROUTING_TABLE_MESH_OLSR2")
	# olsr passt sich im Zweifel der iproute-Nummer an
	[ "$olsr2_id" != "$iproute_id" ] && uci set "${uci_prefix}.table=$iproute_id"
	apply_changes "olsrd2"
}


# Konfiguriere das IPv6-Policy-Routing für unsere OLSR2-Routing-Tabellen.
# Falls das Modul "on-olsrd2" abgeschaltet ist, wird das Standard-Policy-Routing konfiguriert.
init_policy_routing_ipv6() {
	local iface
	local priority="$OLSR2_POLICY_DEFAULT_PRIORITY"
	olsr2_sync_routing_tables
	# die Uplink-Tabelle ist unabhaengig von olsr
	add_routing_table "$ROUTING_TABLE_ON_UPLINK" >/dev/null

	# alte Regel loeschen, falls vorhanden
	delete_policy_rule inet6 table "$ROUTING_TABLE_MESH_OLSR2"
	delete_policy_rule inet6 table "$ROUTING_TABLE_ON_UPLINK"
	delete_policy_rule inet6 table main

	if is_on_module_installed_and_enabled "on-olsr2"; then
		# free-Verkehr geht immer in den Tunnel (falls das Paket installiert ist)
		if [ -n "${ZONE_FREE:-}" ]; then
			add_zone_policy_rules_by_iif inet6 "$ZONE_FREE" table "$ROUTING_TABLE_ON_UPLINK" prio "$priority"
			priority=$((priority + 1))
		fi

		# sehr wichtig - also zuerst: keine vorbeifliegenden Mesh-Pakete umlenken
		add_zone_policy_rules_by_iif inet6 "$ZONE_MESH" table "$ROUTING_TABLE_MESH_OLSR2" prio "$priority"
		priority=$((priority + 1))

		# Pakete mit passendem Ziel orientieren sich an der main-Tabelle
		# Alle Ziele ausserhalb der mesh-Zone sind geeignet (z.B. local, free, ...).
		# Wir wollen dadurch explizit keine potentielle default-Route verwenden.
		get_all_network_interfaces | while read -r iface; do
			[ "$iface" = "$NETWORK_LOOPBACK" ] && continue
			is_interface_in_zone "$iface" "$ZONE_MESH" && continue
			add_network_policy_rule_by_destination inet6 "$iface" table main prio "$priority"
		done
		priority=$((priority + 1))

		# alle nicht-mesh-Quellen routen auch ins olsr-Netz
		ip -family inet6 rule add table "$ROUTING_TABLE_MESH_OLSR2" prio "$priority"
		priority=$((priority + 1))
		# Routen, die nicht den lokalen Netz-Interfaces entsprechen (z.B. default-Routen)
		ip -family inet6 rule add table main prio "$priority"
		priority=$((priority + 1))


		# die VPN-Tunnel fungieren fuer alle anderen Pakete als default-GW
		ip -family inet6 rule add table "$ROUTING_TABLE_ON_UPLINK" prio "$priority"
	else
		ip -family inet6 rule add table main prio "$priority"
	fi
}


request_olsrd2_txtinfo() {
	echo "/$*" | timeout 2 nc localhost 2009 2>/dev/null
}


## @fn get_olsr2_route_count_by_neighbour()
## @brief Liefere die Anzahl von olsr-Routen, die auf einen bestimmten Routing-Nachbarn verweisen.
get_olsr2_route_count_by_neighbour() {
	local neighbour_link_ipv6="$1"
	request_olsrd2_txtinfo "olsrv2info" "route" | awk '{ if ($2 == "'"$neighbour_link_ipv6"'") print $1; }' | wc -l
}


## @fn get_olsr2_neighbours()
## @brief Ermittle die direkten olsr2-Nachbarn und liefere ihre IPs und interessante Kennzahlen zurück.
## details Ergebnisformat: Neighbour_IPv4 Neighbour_IPv6 Interface IncomingRate OutgoingRate RouteCount
get_olsr2_neighbours() {
	local ipv6
	local ipv4
	local link_ipv6
	local mac
	local interface
	local incoming_rate
	local outgoing_rate
	local route_count
	request_olsrd2_txtinfo "nhdpinfo" "link" | awk '{ print $1,$2,$10,$14,$18,$20 }' \
			| while read -r interface link_ipv6 mac ipv6 incoming_rate outgoing_rate; do
		ipv4=$(get_ipv4_of_mac "$mac")
		[ -z "$ipv4" ] && ipv4="?"
		route_count=$(get_olsr2_route_count_by_neighbour "$link_ipv6")
		echo "$ipv4 $ipv6 $interface $outgoing_rate $incoming_rate $route_count"
	done
}


update_ipv6_name_map_if_outdated() {
	local name_map
	# keep the cache for a while
	[ -e "$IPV6_NAME_MAP" ] && ! is_file_timestamp_older_minutes "$IPV6_NAME_MAP" 360 && return
	# We need to use a pipe instead of "request_field_from_api", since the response is too big.
	name_map=$(wget -q -O - "$OPENNET_API_URL/accesspoint/" \
		| jsonfilter -e '@[*]["main_ip","main_ipv6"]' \
		| awk '{if ($1 ~ ":") { print(main_ip, $1) } else { main_ip=$1 }}' \
		| sed -E 's/^192\.168\.(\d+)\.(\d+) /AP\1-\2 /')
	if [ -n "$name_map" ]; then
		echo "$name_map" >"${IPV6_NAME_MAP}.new"
		mv "${IPV6_NAME_MAP}.new" "$IPV6_NAME_MAP"
	fi
}


debug_ping_all_olsr2_hosts() {
	local ipv6
	local status
	ip -6 route show table olsrd2 | awk '{print $1}' | while read -r ipv6; do
		local
		if ping6 -w 1 -c 1 "$ipv6" >/dev/null 2>&1; then
			status="OK"
		else
			status="FAIL"
		fi
		printf '%-8s%-48s%-48s\n' "$status" "--${ipv6}--" "__${ipv6}__"
	done | shorten_ipv6_address_in_stream | replace_ipv6_addresses_with_names "__" | sed 's/__//g; s/--//g'
}


# manuelle Host-Liste (bis wir richtiges Reverse-DNS haben)
# Falls der optionale Parameter "original_prefix" gesetzt ist, werden nur diejenigen IPv6-Adressen
# ersetzt, die direkt auf dieses Präfix folgen.
replace_ipv6_addresses_with_names() {
	local original_prefix="${1:-}"
	local token
	local mac
	local name
	update_ipv6_name_map_if_outdated
	sed -e "$(while read -r name ipv6; do
			printf 's|%s\\b|%s|g;\n' "${original_prefix:-\\b}$ipv6" "$original_prefix$name"
		done <"$IPV6_NAME_MAP")"
}
