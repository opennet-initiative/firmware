#permanent IPv6 Präfix (ULA)
IP6_PREFIX_PERM=fd32:d8d3:87da:0
#/60 Präfix von gai (IN-BERLIN)
IP6_PREFIX_OLD=2001:67c:1400:2432
#/48 Präfic von IN-BERLIN
IP6_PREFIX_TMP=2a0a:4580:1010:1

IP6_PREFIX_LENGTH=64
NETWORK_LOOPBACK=on_loopback
ROUTING_TABLE_MESH_OLSR2=olsrd2
# interne Zahl fuer die "Domain" in olsr2
OLSR2_DOMAIN=0

MAC_HOSTNAME_MAP="	50:54:00:a0:31:00 H-GAI
			24:a4:3c:0a:3d:44 AP1-54
			dc:9f:db:f4:34:a9 AP1-96
			00:27:22:44:c3:2f AP1-101
			00:27:22:44:c1:aa AP1-110
			68:72:51:0a:45:0c AP1-117
			00:15:6d:c5:c2:b2 AP1-120
			00:27:22:1a:78:65 AP1-187
			80:2a:a8:7a:19:0a AP1.189
			dc:9f:db:f4:36:d6 AP1-196
			c4:e9:84:7d:e4:48 AP2-1
			00:15:6d:80:08:f3 AP2-4
			24:a4:3c:86:3a:59 AP2-5
			00:15:6d:80:09:7b AP2-6
			00:15:6d:80:09:31 AP2-8
			24:a4:3c:44:c9:2a AP2-14
			c0:4a:00:40:ad:c2 AP2-30
			44:d9:e7:54:ee:d2 AP2-50
			24:a4:3c:fc:76:98 AP2-76
			14:cc:20:a8:ef:c6 AP2-166
			00:1e:62:1e:fa:37 AP2-189
			44:d9:e7:42:7f:76 AP3-17
			04:18:d6:ec:cd:ca AP3-18"
IPV6_HOSTNAME_MAP="fd00::245 HOST-GAI"


## @fn get_mac_address()
## @brief Ermittle die erste nicht-Null MAC-Adresse eines echten Interfaces.
get_mac_address() {
	ip link | grep -A 1 "^[0-9]\+: \(eth\|wlan\)" | grep "link/ether" \
		| awk '{print $2}' | grep -v "^00:00:00:00:00:00$" | sort | head -1
}


## @fn shorten_ipv6_address()
## @brief Verkuerze eine IPv6-Adress-Repräsentation anhand der üblichen Regeln.
## Die Funktion ist kaum getestet - sie erzeugt sicherlich falsche Adressen (mehr als ein
## Doppel-Doppelpunkt, usw.).
shorten_ipv6_address() {
	#use not the following     sed 's/:0\+/:/g; s/::\+/::/g'
	#but the below because in '/olsrv2info route' there are ':0:' in output
	sed 's/:00\+/:/g; s/::\+/::/g'
}


## @fn convert_mac_to_eui64_address()
## @brief Wandle eine MAC-Adresse in ein IPv6-Suffix (64 bit) um.
convert_mac_to_eui64_address() {
	local prefix="$1"
	local mac="$2"
	local mac_offset="${3:-0}"
	local combined_mac
	combined_mac=$(echo "$mac" | cut -c 1-2,4-5,7-8,10-11,13-14,16-17)
	# MAC-Offset hinzuaddieren
	combined_mac=$(printf "%012x" "$(( 0x$combined_mac + mac_offset ))")
	printf "%s:%s:%sff:fe%s:%s" "$prefix" "${combined_mac:0:4}" "${combined_mac:4:2}" \
		"${combined_mac:6:2}" "${combined_mac:8:4}"       | shorten_ipv6_address
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
	uci_prefix="network.$NETWORK_LOOPBACK"
	# schon konfiguriert?
	[ -n "$(uci_get "$uci_prefix")" ] && return
	uci set "$uci_prefix=interface"
	uci set "${uci_prefix}.proto=static"
	uci set "${uci_prefix}.ifname=lo"
	# Leider funktioniert dies noch nicht (Februar 2016) - wohl nur fuer "delegated networks".
	# Also wollen wir es erstmal nur manuell ermitteln.
	#uci set "${uci_prefix}.ip6ifaceid=eui64"
	#uci set "${uci_prefix}.ip6prefix=${IP6_PREFIX}::/$IP6_PREFIX_LENGTH"
	uci_add_list "${uci_prefix}.ip6addr" "$(get_main_ipv6_address)"
	apply_changes network
}


## @fn update_olsr2_interfaces()
## @brief Mesh-Interfaces ermitteln und für olsrd2 konfigurieren
update_olsr2_interfaces() {
	local interfaces
	local existing_interfaces
	local ifnames
	local uci_prefix
	local token
	local is_configured=0
	# auf IPv6 begrenzen (siehe http://www.olsr.org/mediawiki/index.php/OLSR_network_deployments)
	local ipv6_limit="-0.0.0.0/0 -::1/128 default_accept"
	interfaces="loopback $(get_zone_interfaces "$ZONE_MESH")"
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
		# alle Netzwerkschnittstellen eintragen
		for token in $interfaces; do uci_add_list "${uci_prefix}.name" "$token"; done
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
	apply_changes "olsrd2"
}


## @fn olsr2_sync_routing_tables()
## @brief Synchronisiere die olsrd-Routingtabellen-Konfiguration mit den iproute-Routingtabellennummern.
## @details Im Konfliktfall wird die olsrd-Konfiguration an die iproute-Konfiguration angepasst.
olsr2_sync_routing_tables() {
	trap "error_trap olsr2_sync_routing_tables '$*'" $GUARD_TRAPS
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
	[ -n "$olsr2_id" -a "$olsr2_id" = "$iproute_id" ] && continue
	# eventuell Tabelle erzeugen, falls sie noch nicht existiert
	[ -z "$iproute_id" ] && iproute_id=$(add_routing_table "$ROUTING_TABLE_MESH_OLSR2")
	# olsr passt sich im Zweifel der iproute-Nummer an
	[ "$olsr2_id" != "$iproute_id" ] && uci set "${uci_prefix}.table=$iproute_id" || true
	apply_changes "olsrd2"
}


init_policy_routing_ipv6() {
	olsr2_sync_routing_tables
	# die Uplink-Tabelle ist unabhaengig von olsr
	add_routing_table "$ROUTING_TABLE_ON_UPLINK" >/dev/null

	# alte Regel loeschen, falls vorhanden
	delete_policy_rule inet6 table "$ROUTING_TABLE_MESH_OLSR2"
	delete_policy_rule inet6 table main

	# free-Verkehr geht immer in den Tunnel (falls das Paket installiert ist)
	[ -n "${ZONE_FREE:-}" ] \
		&& add_zone_policy_rules_by_iif inet6 "$ZONE_FREE" table "$ROUTING_TABLE_ON_UPLINK"

	# sehr wichtig - also zuerst: keine vorbeifliegenden Mesh-Pakete umlenken
	add_zone_policy_rules_by_iif inet6 "$ZONE_MESH" table "$ROUTING_TABLE_MESH_OLSR2"

	# Pakete mit passendem Ziel orientieren sich an der main-Tabelle
	# Alle Ziele ausserhalb der mesh-Zone sind geeignet (z.B. local, free, ...).
	# Wir wollen dadurch explizit keine potentielle default-Route verwenden.
	get_all_network_interfaces | while read iface; do
		is_interface_in_zone "$iface" "$ZONE_MESH" && continue
		add_network_policy_rule_by_destination inet6 "$iface" table main
	done

	# alle nicht-mesh-Quellen routen auch ins olsr-Netz
	ip -family inet6 rule add table "$ROUTING_TABLE_MESH_OLSR2"
	# Routen, die nicht den lokalen Netz-Interfaces entsprechen (z.B. default-Routen)
	ip -family inet6 rule add table main


	# die VPN-Tunnel fungieren fuer alle anderen Pakete als default-GW
	ip -family inet6 rule add table "$ROUTING_TABLE_ON_UPLINK"
}


request_olsrd2_txtinfo() {
	echo /$@ | timeout 2 nc localhost 2009 2>/dev/null
}


## @fn get_olsr2_route_count_by_neighbour()
## @brief Liefere die Anzahl von olsr-Routen, die auf einen bestimmten Routing-Nachbarn verweisen.
get_olsr2_route_count_by_neighbour() {
	local neighbour_link_ipv6="$1"
	request_olsrd2_txtinfo "olsrv2info" "route" | awk '{ if ($2 == "'$neighbour_link_ipv6'") print $1; }' | wc -l
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
	request_olsrd2_txtinfo "nhdpinfo" "link" | awk '{ print $1,$2,$10,$11,$15,$17 }' \
			| while read interface link_ipv6 mac ipv6 incoming_rate outgoing_rate; do
		ipv4=$(get_ipv4_of_mac "$mac")
		[ -z "$ipv4" ] && ipv4="?"
		route_count=$(get_olsr2_route_count_by_neighbour "$link_ipv6")
		echo "$ipv4 $ipv6 $interface $incoming_rate $outgoing_rate $route_count"
	done
}


debug_ping_all_olsr2_hosts() {
	ip -6 route show table olsrd2 | awk '{print $1}' | while read a; do
		ping6 -w 1 -c 1 "$a" >/dev/null 2>&1 && printf "OK\t$a\n" || printf "FAIL\t$a\n"
	done
}


# manuelle Host-Liste (bis wir richtiges Reverse-DNS haben)
debug_translate_macs() {
	local token
	local mac
	local ip
	local name
	local sed_script_mac
	local sed_script_ip
	sed_script_mac=$(echo "$MAC_HOSTNAME_MAP" | while read mac name; do
			# Main-IP (loopback-Interface)
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "$IP6_PREFIX_PERM" "$mac")" "$name"
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "$IP6_PREFIX_OLD" "$mac")" "$name"
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "$IP6_PREFIX_TMP" "$mac")" "$name"
			# link-local-Adressen: das "local"-Bit setzen
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "fe80:" "$mac" "0x020000000000")" "$name"
			# für Nanostations: das 16. Bit hochzählen für die zweite MAC des Geräts
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "fe80:" "$mac" "0x020000010000")" "$name"
		done)
	sed_script_ip=$(echo "$IPV6_HOSTNAME_MAP" | while read ip name; do
			printf "s/%s/%s/g;\n" "$ip" "$name"
		done)
	sed -e "$sed_script_mac" -e "$sed_script_ip"
}
