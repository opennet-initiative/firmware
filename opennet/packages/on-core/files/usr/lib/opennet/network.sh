ROUTE_RULE_ON=on-tunnel
ZONE_LOCAL=lan
ZONE_MESH=on_mesh
ZONE_TUNNEL=on_vpn
ZONE_FREE=free
NETWORK_TUNNEL=on_vpn
NETWORK_FREE=free
ROUTING_TABLE_MESH=olsrd
ROUTING_TABLE_MESH_DEFAULT=olsrd-default
OLSR_POLICY_DEFAULT_PRIORITY=20000


# Liefere alle IPs fuer diesen Namen zurueck
query_dns() { nslookup "$1" | sed '1,/^Name:/d' | awk '{print $3}' | sort -n; }
query_dns_reverse() { nslookup "$1" 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'; }


# Lege eine Weiterleitungsregel fuer die firewall an (firewall.@forwarding[?]=...)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
add_zone_forward() {
	local source=$1
	local dest=$2
	local section
	local uci_prefix=$(find_first_uci_section firewall forwarding "src=$source" "dest=$dest")
	# die Weiterleitungsregel existiert bereits -> Ende
	[ -n "$uci_prefix" ] && return 0
	# neue Regel erstellen
	section=$(uci add firewall forwarding)
	uci set "firewall.${section}.src=$source"
	uci set "firewall.${section}.dest=$dest"
}


# Loesche eine Weiterleitungsregel fuer die firewall (Quelle -> Ziel)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
delete_zone_forward() {
	local source=$1
	local dest=$2
	local uci_prefix=$(find_first_uci_section firewall forwarding "src=$source" "dest=$dest")
	# die Weiterleitungsregel existiert nicht -> Ende
	[ -z "$uci_prefix" ] && return 0
	# Regel loeschen
	uci_delete "$uci_prefix"
}


# Das Masquerading in die Opennet-Zone soll nur fuer bestimmte Quell-Netze erfolgen.
# Diese Funktion wird bei hotplug-Netzwerkaenderungen ausgefuehrt.
update_opennet_zone_masquerading() {
	local network
	local networkprefix
	local uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_MESH")
	# Abbruch, falls die Zone fehlt
	[ -z "$uci_prefix" ] && msg_info "failed to find opennet mesh zone ($ZONE_MESH)" && return 0
	# masquerading aktiveren (nur fuer die obigen Quell-Adressen)
	uci set "${uci_prefix}.masq=1"
	# alle masquerade-Netzwerke entfernen
	uci_delete "${uci_prefix}.masq_src"
	# aktuelle Netzwerke wieder hinzufuegen
	for network in $(get_zone_interfaces "$ZONE_LOCAL"); do
		networkprefix=$(get_network "$network")
		uci_add_list "${uci_prefix}.masq_src" "$networkprefix"
	done
	apply_changes firewall
}


get_network() {
	trap "error_trap get_network $*" $GUARD_TRAPS
	local ifname=$(
		# Kurzzeitig den eventuellen strikten Modus abschalten.
		# (lib/functions.sh kommt mit dem strikten Modus nicht zurecht)
		set +eu
		. "${IPKG_INSTROOT:-}/lib/functions.sh"
		include "${IPKG_INSTROOT:-}/lib/network"
		scan_interfaces
		config_get "$1" ifname
		set +eu
	)
	if [ -n "$ifname" ] && [ "$ifname" != "none" ]; then
		# TODO: aktuell nur IPv4
		ipaddr="$(ip address show label "$ifname" | awk '/inet / {print $2; exit}')"
		[ -z "$ipaddr" ] || { eval $(ipcalc -p -n "$ipaddr"); echo $NETWORK/$PREFIX; }
	fi
}


# jeder AP bekommt einen Bereich von zehn Ports fuer die Port-Weiterleitung zugeteilt
# Parameter (optional): common name des Nutzer-Zertifikats
get_port_forwards() {
	local client_cn=${1:-}
	[ -z "$client_cn" ] && client_cn=$(get_client_cn)
	local port_count=10
	local cn_address=
	local portbase
	local targetports

	[ -z "$client_cn" ] && msg_debug "$(basename "$0"): failed to get Common Name - maybe there is no certificate?" && return 0

	if echo "$client_cn" | grep -q '^\(\(1\.\)\?[0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=10000
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\([0-9][0-9]\?[0-9]\?\.mobile\.on\)$'; then
		portbase=12550
		cn_address=${client_cn%.mobile.on}
	elif echo "$client_cn" | grep -q '^\(2[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=15100
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	elif echo "$client_cn" | grep -q '^\(3[\._-][0-9][0-9]\?[0-9]\?\.aps\.on\)$'; then
		portbase=20200
		cn_address=${client_cn%.aps.on}
		cn_address=${cn_address#*.}
	fi

	if [ -z "$cn_address" ] || [ "$cn_address" -lt 1 ] || [ "$cn_address" -gt 255 ]; then
		msg_info "$(basename "$0"): invalidate certificate Common Name ($client_cn)"
		return 1
	fi

	targetports=$((portbase + (cn_address-1)*port_count))
	echo "$client_cn $targetports $((targetports+9))"
}


get_zone_interfaces() {
	local zone=$1
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	# keine Zone -> keine Interfaces
	[ -z "$uci_prefix" ] && return 0
	uci_get "${uci_prefix}.network"
	return 0
}


is_interface_in_zone() {
	local in_interface=$1
	local zone=$2
	for log_interface in $(get_zone_interfaces "$2"); do
		for phys_interface in $(uci_get "network.${log_interface}.ifname"); do
			# Entferne den Teil nach Doppelpunkten - fuer Alias-Interfaces
			[ "$in_interface" = "$(echo "$phys_interface" | cut -f 1 -d :)" ] && return 0 || true
		done
	done
	return 1
}


add_interface_to_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to add interface '$interface' to non-existing zone '$zone'" && return 1
	uci_add_list "${uci_prefix}.network" "$interface"
}


del_interface_from_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to remove interface '$interface' from non-existing zone '$zone'" && return 1
	uci del_list "${uci_prefix}.network=$interface"
}


get_zone_of_interface() {
	local interface=$1
	local prefix
	local networks
	local zone
	uci show firewall | grep "^firewall\.@zone\[[0-9]\+\]\.network=" | sed 's/=/ /' | while read prefix networks; do
	zone=$(uci_get "${prefix%.network}.name")
		echo " $networks " | grep -q "[ \t]$interface[ \t]" && echo "$zone" && return 0 || true
	done
	return 1
}


# Liefere die sortierte Liste der Opennet-Interfaces.
# Prioritaeten:
# 1. dem Netzwerk ist ein Geraet zugeordnet
# 2. Netzwerkname beginnend mit "on_wifi", "on_eth", ...
# 3. alphabetische Sortierung der Netzwerknamen
get_sorted_opennet_interfaces() {
	local uci_prefix
	local order
	# wir vergeben einfach statische Ordnungsnummern:
	#   10 - konfigurierte Interfaces
	#   20 - nicht konfigurierte Interfaces
	# Offsets basierend auf dem Netzwerknamen:
	#   1 - on_wifi*
	#   2 - on_eth*
	#   3 - alle anderen
	for network in $(get_zone_interfaces "$ZONE_MESH"); do
		uci_prefix=network.$network
		order=10
		[ "$(uci_get "${uci_prefix}.ifname")" == "none" ] && order=20
		if [ "${network#on_wifi}" != "$network" ]; then
			order=$((order+1))
		elif [ "${network#on_eth}" != "$network" ]; then
			order=$((order+2))
		else
			order=$((order+3))
		fi
		echo "$order $network"
	done | sort -n | cut -f 2 -d " "
}


