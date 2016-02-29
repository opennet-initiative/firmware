IP6_PREFIX=2001:67c:1400:2432
IP6_PREFIX_LENGTH=64
NETWORK_LOOPBACK=on_loopback


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
update_olsr2_interfaces() {
	local interfaces
	local finished_interfaces
	local ifname
	local uci_prefix
	interfaces=$(get_zone_interfaces "$ZONE_MESH")
	interfaces="loopback $interfaces"
	# alle konfigurierten Interfaces durchgehen und überflüssige löschen
	find_all_uci_sections "olsrd2" "interface" | while read uci_prefix; do
		ifname=$(uci_get "${uci_prefix}.ifname")
		if echo "$interfaces" | grep -q "^${ifname}$"; then
			# das Interface ist bereits eingetragen
			uci_delete "${uci_prefix}.ignore"
		else
			# fuer diesen Eintrag gibt es kein Interface
			uci_delete "${uci_prefix}"
		fi
	done
	# alle fehlenden Interfaces hinzufügen
	finished_interfaces=$(find_all_uci_sections "olsrd2" "interface" | while read uci_prefix; do uci_get "${uci_prefix}.ifname"; done)
	echo "$interfaces" | sed 's/[^a-zA-Z�0-9_]/\n/g' | while read ifname; do
		echo "$finished_interfaces" | grep -wq "$ifname" && continue
		uci_prefix="olsrd2.$(uci add "olsrd2" "interface")"
		uci set "${uci_prefix}.ifname=$ifname"
	done
	# TODO: die folgende Zeile vor dem naechsten Release durch "apply_changes on-olsr2" ersetzen
	[ -n "$(uci changes olsrd2)" ] && uci commit olsrd2 && /etc/init.d/olsrd2 reload >/dev/null
	true
}
