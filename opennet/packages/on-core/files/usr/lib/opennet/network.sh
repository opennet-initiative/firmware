## @defgroup network Netzwerk
## @brie Umgang mit uci-Netzwerk-Interfaces und Firewall-Zonen
# Beginn der Doku-Gruppe
## @{

ZONE_LOCAL=lan
ZONE_WAN=wan
ZONE_MESH=on_mesh
ZONE_TUNNEL=on_vpn
ZONE_FREE=free
NETWORK_TUNNEL=on_vpn
NETWORK_FREE=free


# Liefere alle IPs fuer diesen Namen zurueck
query_dns() { nslookup "$1" | sed '1,/^Name:/d' | awk '{print $3}' | sort -n; }
query_dns_reverse() { nslookup "$1" 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'; }


## @fn query_srv_record()
## @brief Liefere die SRV Records zu einer Domain zurück.
## @param srv_domain Dienst-Domain (z.B. _mesh-openvpn._udp.opennet-initiative.de)
## @returns Zeilenweise Ausgabe von SRV Records: PRIORITY WEIGHT PORT HOSTNAME
## @details siehe RFC 2782
query_srv_records() {
	local srv_domain="$1"
	# entferne den abschliessenden Top-Level-Domain-Punkt ("on-i.de." statt "on-i.de")
	dig +short SRV "$srv_domain" | sed 's/\.$//'
}


# Lege eine Weiterleitungsregel fuer die firewall an (firewall.@forwarding[?]=...)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
add_zone_forward() {
	trap "error_trap add_zone_forward '$*'" $GUARD_TRAPS
	local source=$1
	local dest=$2
	local uci_prefix=$(find_first_uci_section firewall forwarding "src=$source" "dest=$dest")
	# die Weiterleitungsregel existiert bereits -> Ende
	[ -n "$uci_prefix" ] && return 0
	# neue Regel erstellen
	uci_prefix="firewall.$(uci add firewall forwarding)"
	uci set "${uci_prefix}.src=$source"
	uci set "${uci_prefix}.dest=$dest"
}


# Loesche eine Weiterleitungsregel fuer die firewall (Quelle -> Ziel)
# WICHTIG: anschliessend muss "uci commit firewall" ausgefuehrt werden
# Parameter: Quell-Zone und Ziel-Zone
delete_zone_forward() {
	trap "error_trap delete_zone_forward '$*'" $GUARD_TRAPS
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
	trap "error_trap update_opennet_zone_masquerading '$*'" $GUARD_TRAPS
	local network
	local networkprefix
	local uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_MESH")
	# Abbruch, falls die Zone fehlt
	[ -z "$uci_prefix" ] && msg_info "failed to find opennet mesh zone ($ZONE_MESH)" && return 0
	# alle masquerade-Netzwerke entfernen
	uci_delete "${uci_prefix}.masq_src"
	# aktuelle Netzwerke wieder hinzufuegen
	for network in $(get_zone_interfaces "$ZONE_LOCAL"); do
		networkprefix=$(get_address_of_network "$network")
		uci_add_list "${uci_prefix}.masq_src" "$networkprefix"
	done
	# leider ist masq_src im Zweifelfall nicht "leer", sondern enthaelt ein Leerzeichen
	if uci_get "${uci_prefix}.masq_src" | grep -q "[^ \t]"; then
		# masquerading aktiveren (nur fuer die obigen Quell-Adressen)
		uci set "${uci_prefix}.masq=1"
	else
		# Es gibt keine lokalen Interfaces - also duerfen wir kein Masquerading aktivieren.
		# Leider interpretiert openwrt ein leeres "masq_src" nicht als "masq fuer niemanden" :(
		uci set "${uci_prefix}.masq=0"
	fi
	apply_changes firewall
}


# Liefere die IP-Adresse eines logischen Interface inkl. Praefix-Laenge (z.B. 172.16.0.1/24).
# Parameter: logisches Netzwerk-Interface
get_address_of_network() {
	trap "error_trap get_address_of_network '$*'" $GUARD_TRAPS
	local network="$1"
	local ranges
	# Kurzzeitig den eventuellen strikten Modus abschalten.
	# (lib/functions.sh kommt mit dem strikten Modus nicht zurecht)
	(
		set +eu
		. "${IPKG_INSTROOT:-}/lib/functions/network.sh"
		__network_ifstatus "ranges" "$network" "['ipv4-address'][*]['address','mask']" "/"
		echo "$ranges"
		set -eu
	)
	return 0
}


# Liefere die logischen Netzwerk-Schnittstellen einer Zone zurueck.
get_zone_interfaces() {
	trap "error_trap get_zone_interfaces '$*'" $GUARD_TRAPS
	local zone="$1"
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	local interface
	# keine Zone -> keine Interfaces
	[ -z "$uci_prefix" ] && return 0
	interfaces=$(uci_get "${uci_prefix}.network")
	# falls 'network' und 'device' leer sind, dann enthaelt 'name' den Interface-Namen
	# siehe http://wiki.openwrt.org/doc/uci/firewall#zones
	[ -z "$interfaces" ] && [ -z "$(uci_get "${uci_prefix}.device")" ] && interfaces="$(uci_get "${uci_prefix}.name")"
	echo "$interfaces"
	return 0
}


# Liefere die physischen Netzwerk-Schnittstellen einer Zone zurueck.
get_zone_devices() {
	trap "error_trap get_zone_devices '$*'" $GUARD_TRAPS
	local zone="$1"
	local iface
	local result
	for iface in $(get_zone_interfaces "$zone"); do
		for result in $(uci_get "network.${iface}.ifname"); do
			echo "$result"
		done
	done
}


# Ist das gegebene physische Netzwer-Interface Teil einer Firewall-Zone?
is_device_in_zone() {
	trap "error_trap is_device_in_zone '$*'" $GUARD_TRAPS
	local device=$1
	local zone=$2
	local item
	for log_interface in $(get_zone_interfaces "$2"); do
		for item in $(uci_get "network.${log_interface}.ifname"); do
			# Entferne den Teil nach Doppelpunkten - fuer Alias-Interfaces
			[ "$device" = "$(echo "$item" | cut -f 1 -d :)" ] && return 0 || true
		done
	done
	trap "" $GUARD_TRAPS && return 1
}


# Ist das gegebene logische Netzwerk-Interface Teil einer Firewall-Zone?
is_interface_in_zone() {
	local interface=$1
	local zone=$2
	local item
	for item in $(get_zone_interfaces "$2"); do
		[ "$item" = "$interface" ] && return 0 || true
	done
	trap "" $GUARD_TRAPS && return 1
}


add_interface_to_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to add interface '$interface' to non-existing zone '$zone'" && trap "" $GUARD_TRAPS && return 1
	uci_add_list "${uci_prefix}.network" "$interface"
}


del_interface_from_zone() {
	local zone=$1
	local interface=$2
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "failed to remove interface '$interface' from non-existing zone '$zone'" && trap "" $GUARD_TRAPS && return 1
	uci del_list "${uci_prefix}.network=$interface"
}


## @fn get_zone_of_interface()
## @brief Ermittle die Zone eines physischen Interfaces.
## @param interface Name eines physischen Interface (z.B. eth0)
## @details Das Ergebnis ist ein leerer String, falls zu diesem Interface keine Zone existiert
##   oder falls es das Interface nicht gibt.
get_zone_of_interface() {
	trap "error_trap get_zone_of_interface '$*'" $GUARD_TRAPS
	local interface=$1
	local uci_prefix
	local interfaces
	local zone
	find_all_uci_sections firewall zone | while read uci_prefix; do
		zone=$(uci_get "${uci_prefix}.name")
		interfaces=$(get_zone_interfaces "$zone")
		is_in_list "$interface" "$interfaces" && echo -n "$zone" && return 0 || true
	done
	# ein leerer Rueckgabewert gilt als Fehler
	return 0
}


# Liefere die sortierte Liste der Opennet-Interfaces.
# Prioritaeten:
# 1. dem Netzwerk ist ein Geraet zugeordnet
# 2. Netzwerkname beginnend mit "on_wifi", "on_eth", ...
# 3. alphabetische Sortierung der Netzwerknamen
get_sorted_opennet_interfaces() {
	trap "error_trap get_sorted_opennet_interfaces '$*'" $GUARD_TRAPS
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


# Liefere alle vorhandenen logischen Netzwerk-Schnittstellen (lan, wan, ...) zurueck.
get_all_network_interfaces() {
	local interface
	uci show network | grep "^network\.[^.]\+=interface$" | cut -f 2 -d . | cut -f 1 -d = | while read interface; do
		# ignoriere loopback-Interface
		[ "$interface" = "loopback" ] && continue
		# alle uebrigen sind reale Interfaces
		echo "$interface"
	done
	return 0
}


rename_firewall_zone() {
	trap "error_trap rename_firewall_zone '$*'" $GUARD_TRAPS
	local old_zone="$1"
	local new_zone="$2"
	local setting
	local uci_prefix
	local key
	local old_uci_prefix=$(find_first_uci_section firewall zone "name=$old_zone")
	# die Zone existiert nicht (mehr)
	[ -z "$old_uci_prefix" ] && return 0
	local new_uci_prefix=$(find_first_uci_section firewall zone "name=$new_zone")
	[ -z "$new_uci_prefix" ] && new_uci_prefix="firewall.$(uci add firewall zone)"
	uci show "$old_uci_prefix" | cut -f 3- -d . | while read setting; do
		# die erste Zeile (der Zonen-Typ) ueberspringen
		[ -z "$setting" ] && continue
		uci set "${new_uci_prefix}.$setting"
	done
	# den Namen ueberschreiben (er wurde oben von der alten Zone uebernommen)
	uci set "${new_uci_prefix}.name=$new_zone"
	# aktualisiere alle Forwardings, Redirects und Regeln
	for section in "forwarding" "redirect" "rule"; do
		for key in "src" "dest"; do
			find_all_uci_sections firewall "$section" "${key}=$old_zone" | while read uci_prefix; do
				uci set "${uci_prefix}.${key}=$new_zone"
			done
		done
	done
	# fertig - wir loeschen die alte Zone
	uci_delete "$old_uci_prefix"
	apply_changes firewall
}

# Ende der Doku-Gruppe
## @}
