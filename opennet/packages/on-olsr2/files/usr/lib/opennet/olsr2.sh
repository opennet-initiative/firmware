IP6_PREFIX=2001:67c:1400:2432
IP6_PREFIX_LENGTH=64
NETWORK_LOOPBACK=on_loopback
ROUTING_TABLE_MESH_OLSR2=olsrd2
# interne Zahl fuer die "Domain" in olsr2
OLSR2_DOMAIN=0


## @fn get_mac_address()
## @brief Ermittle die erste nicht-Null MAC-Adresse eines echten Interfaces.
get_mac_address() {
	ip link | grep -A 1 "^[0-9]\+: \(eth\|wlan\)" | grep "link/ether" \
		| awk '{print $2}' | grep -v "^00:00:00:00:00:00$" | sort | head -1
}


## @fn get_ipv6_address()
## @brief Ermittle die IPv6-Adresse des APs anhand des EUI64-Verfahrens.
get_ipv6_address() {
	local combined_mac
	local ipv6_address
	combined_mac=$(get_mac_address | cut -c 1-2,4-8,10-14,16-17)
	echo "$(echo "$combined_mac" | cut -c 1-7)ff:fe$(echo "$combined_mac" | cut -c 8-14)"
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
	uci_add_list "${uci_prefix}.ip6addr" "${IP6_PREFIX}:$(get_ipv6_address)/$IP6_PREFIX_LENGTH"
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
	echo "$interfaces" | sed 's/[^a-zA-Z�0-9_]/\n/g' | while read ifname; do
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
