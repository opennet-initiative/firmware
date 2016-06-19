IP6_PREFIX=2001:67c:1400:2432
IP6_PREFIX_LENGTH=64
NETWORK_LOOPBACK=on_loopback
ROUTING_TABLE_MESH_OLSR2=olsrd2
# interne Zahl fuer die "Domain" in olsr2
OLSR2_DOMAIN=0

MAC_HOSTNAME_MAP="	50:54:00:a0:31:00 H-GAI
			dc:9f:db:f4:34:a9 AP1-96
			00:27:22:44:c3:2f AP1-101
			00:27:22:44:c1:aa AP1-110
			68:72:51:0a:45:0c AP1-117
			00:15:6d:c5:c2:b2 AP1-120
			00:27:22:1a:78:65 AP1-187
			dc:9f:db:f4:36:d6 AP1-196
			c4:e9:84:7d:e4:48 AP2-1
			00:15:6d:80:08:f3 AP2-4
			24:a4:3c:86:3a:59 AP2-5
			00:15:6d:80:09:7b AP2-6
			00:15:6d:80:09:31 AP2-8
			c0:4a:00:40:ad:c2 AP2-30
			24:a4:3c:fc:76:98 AP2-76
			14:cc:20:a8:ef:c6 AP2-166
			00:1e:62:1e:fa:37 AP2-189"
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
	sed 's/:0\+/:/g; s/::\+/::/g'
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
		"${combined_mac:6:2}" "${combined_mac:8:4}" | shorten_ipv6_address
}


## @fn get_main_ipv6_address()
## @brief Ermittle die IPv6-Adresse des APs anhand des EUI64-Verfahrens.
get_main_ipv6_address() {
	printf "%s/%s" "$(convert_mac_to_eui64_address "$IP6_PREFIX" "$(get_mac_address)")" "$IP6_PREFIX_LENGTH"
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
# TODO: olsrd2 ab Version 0.12 vereinfacht die uci-Konfiguration deutlich: http://www.olsr.org/mediawiki/index.php/UCI_Configuration_Plugin
update_olsr2_interfaces() {
	local interfaces
	local existing_interfaces
	local ifname
	local uci_prefix
	local token
	# auf IPv6 begrenzen (siehe http://www.olsr.org/mediawiki/index.php/OLSR_network_deployments)
	local ipv6_limit="-0.0.0.0/0 -::1/128 default_accept"
	interfaces="loopback $(get_zone_interfaces "$ZONE_MESH")"
	# alle konfigurierten Interfaces durchgehen und überflüssige löschen
	find_all_uci_sections "olsrd2" "interface" | while read uci_prefix; do
		ifname=$(uci_get "${uci_prefix}.ifname")
		[ -z "$ifname" ] && continue
		if echo "$interfaces" | grep -q "^${ifname}$"; then
			# das Interface ist bereits eingetragen
			uci_delete "${uci_prefix}.ignore"
			# Interface auf IPv6 begrenzen
			[ -n "$(uci_get "${uci_prefix}.bindto")" ] || {
				for token in $ipv6_limit; do uci_add_list "${uci_prefix}.bindto" "$token"; done
			}
		else
			# fuer diesen Eintrag gibt es kein Interface
			uci_delete "${uci_prefix}"
		fi
	done
	# alle fehlenden Interfaces hinzufügen
	existing_interfaces=$(find_all_uci_sections "olsrd2" "interface" \
		| while read uci_prefix; do uci_get "${uci_prefix}.ifname"; done)
	echo "$interfaces" | sed 's/[^a-zA-Z0-9\._]/\n/g' | while read ifname; do
		echo "$existing_interfaces" | grep -wq "$ifname" || {
			uci_prefix="olsrd2.$(uci add "olsrd2" "interface")"
			uci set "${uci_prefix}.ifname=$ifname"
			for token in $ipv6_limit; do uci_add_list "${uci_prefix}.bindto" "$token"; done
		}
	done
	# Informationsversand auf IPv6 begrenzen
	uci_prefix=$(find_first_uci_section "olsrd2" "olsrv2")
	[ -z "$uci_prefix" ] && uci_prefix="olsrd2.$(uci add "olsrd2" "olsrv2")"
	[ -n "$(uci_get "${uci_prefix}.originator")" ] || {
		for token in $ipv6_limit; do
			uci_add_list "${uci_prefix}.originator" "$token"
		done
	}
	# TODO: die folgende Zeile vor dem naechsten Release durch "apply_changes olsrd2" ersetzen
	apply_changes_olsrd2
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
	# TODO: die folgende Zeile vor dem naechsten Release durch "apply_changes olsrd2" ersetzen
	apply_changes_olsrd2
}


# TODO: diese Funktion vor dem naechsten Release durch "apply_changes olsrd2" ersetzen
apply_changes_olsrd2() {
	[ -n "$(uci changes olsrd2)" ] || return
	uci commit olsrd2
	# das init-Skript funktioniert nicht im strikten Modus
	set +eu
	/etc/init.d/olsrd2 reload >/dev/null
	true
}


init_policy_routing_ipv6() {
	# alte Regel loeschen, falls vorhanden
	ip -6 rule del lookup "$ROUTING_TABLE_MESH_OLSR2" 2>/dev/null || true
	ip -6 rule add lookup "$ROUTING_TABLE_MESH_OLSR2"
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
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "$IP6_PREFIX" "$mac")" "$name"
			# link-local-Adressen: das "local"-Bit setzen
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "fe80::" "$mac" "0x020000000000")" "$name"
			# für Nanostations: das 16. Bit hochzählen für die zweite MAC des Geräts
			printf "s/%s/%s/g;\n" "$(convert_mac_to_eui64_address "fe80::" "$mac" "0x020000010000")" "$name"
		done)
	sed_script_ip=$(echo "$IPV6_HOSTNAME_MAP" | while read ip name; do
			printf "s/%s/%s/g;\n" "$ip" "$name"
		done)
	sed -e "$sed_script_mac" -e "$sed_script_ip"
}
