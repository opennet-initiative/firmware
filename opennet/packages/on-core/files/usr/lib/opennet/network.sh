## @defgroup network Netzwerk
## @brie Umgang mit uci-Netzwerk-Interfaces und Firewall-Zonen
# Beginn der Doku-Gruppe
## @{

ZONE_LOCAL=lan
ZONE_WAN=wan
ZONE_MESH=on_mesh
NETWORK_LOCAL=lan


# Liefere alle IPs fuer diesen Namen zurueck
query_dns() {
	nslookup "$1" | sed '1,/^Name:/d' | awk '{print $3}' | sort -n
}


query_dns_reverse() {
	nslookup "$1" 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'
}


## @fn query_srv_record()
## @brief Liefere die SRV Records zu einer Domain zurück.
## @param srv_domain Dienst-Domain (z.B. _mesh-openvpn._udp.opennet-initiative.de)
## @returns Zeilenweise Ausgabe von SRV Records: PRIORITY WEIGHT PORT HOSTNAME
## @details Siehe RFC 2782 für die SRV-Spezifikation. Die Abfrage erfordert dig drill oder unbound-host.
query_srv_records() {
	local domain="$1"
	# verschiedene DNS-Werkzeuge sind nutzbar: dig, drill oder unbound-host
	# "djbdns-tools" unterstützt leider nicht das Parsen von srv-Records (siehe "dnsq 33 DOMAIN localhost")
	# "drill" ist das kleinste Werkzeug
	if which dig >/dev/null; then
		dig +short SRV "$domain"
	elif which drill >/dev/null; then
		drill "$domain" SRV | grep -v "^;" \
			| grep "[[:space:]]IN[[:space:]]\+SRV[[:space:]]\+[[:digit:]]\+[[:space:]]\+[[:digit:]]" \
			| awk '{print $5, $6, $7, $8}'
	elif which unbound-host >/dev/null; then
		unbound-host -t SRV "$domain" \
			| awk '{print $5, $6, $7, $8}'
	else
		msg_info "ERROR: Missing advanced DNS resolver for mesh gateway discovery"
	fi | sed 's/\.$//'
	# (siehe oben) entferne den abschliessenden Top-Level-Domain-Punkt ("on-i.de." statt "on-i.de")
}


## @fn get_ping_time()
## @brief Ermittle die Latenz eines Ping-Pakets auf dem Weg zu einem Ziel.
## @param target IP oder DNS-Name des Zielhosts
## @param duration die Dauer der Ping-Kommunikation in Sekunden (falls ungesetzt: 5)
## @returns Ausgabe der mittleren Ping-Zeit in ganzen Sekunden; bei Nichterreichbarkit ist die Ausgabe leer
get_ping_time() {
	local target="$1"
	local duration="${2:-5}"
	local ip=$(query_dns "$target" | filter_routable_addresses | tail -1)
	[ -z "$ip" ] && return 0
	ping -w "$duration" -q "$ip" 2>/dev/null \
		| grep "min/avg/max" \
		| cut -f 2 -d = \
		| cut -f 2 -d / \
		| awk '{ print int($1 + 0.5); }'
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
	# keine Zone -> keine Interfaces
	[ -z "$uci_prefix" ] && return 0
	local interfaces=$(uci_get "${uci_prefix}.network")
	# falls 'network' und 'device' leer sind, dann enthaelt 'name' den Interface-Namen
	# siehe http://wiki.openwrt.org/doc/uci/firewall#zones
	[ -z "$interfaces" ] && [ -z "$(uci_get "${uci_prefix}.device")" ] && interfaces="$(uci_get "${uci_prefix}.name")"
	echo "$interfaces"
	return 0
}


## @fn get_zone_devices()
## @brief Liefere die physischen Netzwerk-Geräte einer Zone zurueck.
## @param zone Der Name einer Netzwerk-Zone.
## @details Es werden sowohl echte physische Netzwerk-Geräte, als auch Bridge-Interfaces zurückgegeben.
get_zone_devices() {
	trap "error_trap get_zone_devices '$*'" $GUARD_TRAPS
	local zone="$1"
	local iface
	local result
	for iface in $(get_zone_interfaces "$zone"); do
		get_devices_of_interface "$iface"
		# Namen von Bridge-Interfaces werden explizit vergeben
		[ "$(uci_get "network.${iface}.type")" = "bridge" ] && echo "br-$iface"
		true
	done
}


# Ist das gegebene physische Netzwer-Interface Teil einer Firewall-Zone?
is_device_in_zone() {
	trap "error_trap is_device_in_zone '$*'" $GUARD_TRAPS
	local device="$1"
	local zone="$2"
	local item
	for log_interface in $(get_zone_interfaces "$2"); do
		for item in $(get_subdevices_of_interface "$log_interface"); do
			[ "$device" != "$item" ] || continue
			return 0
		done
	done
	trap "" $GUARD_TRAPS && return 1
}


# Ist das gegebene logische Netzwerk-Interface Teil einer Firewall-Zone?
is_interface_in_zone() {
	local interface="$1"
	local zone="$2"
	local item
	for item in $(get_zone_interfaces "$zone"); do
		[ "$item" = "$interface" ] && return 0 || true
	done
	trap "" $GUARD_TRAPS && return 1
}


## @fn get_device_of_interface()
## @brief Ermittle das physische Netzwerk-Gerät, das einem logischen Netzwerk entspricht.
## @details Ein Bridge-Interface wird als Gerät betrachtet und zurückgeliefert (nicht seine Einzelteile).
get_device_of_interface() {
	local interface="$1"
	[ "$(uci_get "network.${interface}.type")" = "bridge" ] \
		&& echo "br-$interface" \
		|| get_subdevices_of_interface "$interface"
}


## @fn get_subdevices_of_interface()
## @brief Ermittle die physischen Netzwerk-Geräte, die zu einem logischen Netzwerk-Interface gehören.
## @details Im Fall eines Bridge-Interface werden nur die beteiligten Komponenten zurückgeliefert.
## @returns Der Name des physischen Netzwerk-Geräts oder nichts.
get_subdevices_of_interface() {
	local interface="$1"
	local device
	# kabelgebundene Geräte
	for device in $(uci_get "network.${interface}.ifname"); do
		# entferne Alias-Nummerierungen
		device=$(echo "$device" | cut -f 1 -d :)
		[ -z "$device" -o "$device" = "none" ] && continue
		echo "$device"
	done
	# wlan-Geräte
	# "uci show network" enthält aus irgendeinem Grund keine wlan-Geräte. Daher müssen
	# wir dort separat nachschauen.
	local uci_prefix
	local current_interface
	find_all_uci_sections "wireless" "wifi-iface" | while read uci_prefix; do
		for current_interface in $(uci_get "${uci_prefix}.network"); do
			[ "$current_interface" != "$interface" ] && continue
			uci_get "${uci_prefix}.ifname"
		done
	done
	# Der folgende Weg (via ubus) wirkt wohl nur bei aktiven Interfaces:
	#(local ifname; . /lib/functions/network.sh; network_get_device ifname on_free; echo "$ifname")
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


## @fn get_zone_of_device()
## @brief Ermittle die Zone eines physischen Netzwerk-Interfaces.
## @param interface Name eines physischen Netzwerk-Interface (z.B. eth0)
## @details Das Ergebnis ist ein leerer String, falls zu diesem Interface keine Zone existiert
##   oder falls es das Interface nicht gibt.
get_zone_of_device() {
	trap "error_trap get_zone_of_device '$*'" $GUARD_TRAPS
	local device="$1"
	local uci_prefix
	local devices
	local zone
	local interface
	local current_device
	find_all_uci_sections firewall zone | while read uci_prefix; do
		zone=$(uci_get "${uci_prefix}.name")
		for interface in $(get_zone_interfaces "$zone"); do
			for current_device in \
					$(get_device_of_interface "$interface") \
					$(get_subdevices_of_interface "$interface"); do
				[ "$current_device" = "$device" ] && echo "$device" && return 0
				true
			done
		done
	done
	# keine Zone gefunden
}


## @fn get_zone_of_interface()
## @brief Ermittle die Zone eines logischen Netzwerk-Interfaces.
## @param interface Name eines logischen Netzwerk-Interface (z.B. eth0)
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
	local order
	local network
	# wir vergeben einfach statische Ordnungsnummern:
	#   10 - konfigurierte Interfaces
	#   20 - nicht konfigurierte Interfaces
	# Offsets basierend auf dem Netzwerknamen:
	#   1 - on_wifi*
	#   2 - on_eth*
	#   3 - alle anderen
	for network in $(get_zone_interfaces "$ZONE_MESH"); do
		order=10
		[ -z "$(get_subdevices_of_interface "$network")" ] && order=20
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
	# Die uci-network-Spezifikation sieht keine anonymen uci-Sektionen fuer Netzwerk-Interfaces vor.
	# Somit ist es wohl korrekt, auf die Namen als Teil des uci-Pfads zu vertrauen.
	find_all_uci_sections "network" "interface" | cut -f 2 -d . | while read interface; do
		# ignoriere loopback-Interfaces und ungueltige
		[ -z "$interface" -o "$interface" = "none" -o "$interface" = "loopback" ] && continue
		# alle uebrigen sind reale Interfaces
		echo "$interface"
	done | sort | uniq
	return 0
}


## @fn delete_firewall_zone()
## @brief Lösche eine Firewall-Zone, sowie alle Regeln, die sich auf diese Zone beziehen.
## @param zone Name der Zone
## @attention Anschließend ist ein "apply_changes firewall" erforderlich.
delete_firewall_zone() {
	local zone="$1"
	local section
	local key
	local uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	uci_delete "$uci_prefix"
	for section in "forwarding" "redirect" "rule"; do
		for key in "src" "dest"; do
			find_all_uci_sections firewall "$section" "${key}=$zone" | while read uci_prefix; do
				uci_delete "$uci_prefix"
			done
		done
	done
}


## @fn rename_firewall_zone()
## @brief Ändere den Namen einer Firewall-Zone.
## @param old_zone Bisheriger Name der Firewall-Zone
## @param new_zone Zukünftiger Name der Firewall-Zone
## @details Alle abhängigen Firewall-Regeln (offene Ports, Weiterleitungen, Umleitungen) werden auf die neue Zone umgelenkt.
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


## @fn is_interface_up()
## @brief Prüfe ob ein logisches Netzwerk-Interface aktiv ist.
## @param interface Zu prüfendes logisches Netzwerk-Interface
## @details Im Fall eines Bridge-Interface wird sowohl der Status der Bridge (muss aktiv sein), als
##   auch der Status der Bridge-Teilnehmer (mindestens einer muss aktiv sein) geprüft.
is_interface_up() {
	trap "error_trap is_interface_up '$*'" $GUARD_TRAPS
	local interface="$1"
	# falls es ein uebergeordnetes Bridge-Interface geben sollte, dann muss dies ebenfalls aktiv sein
	if [ "$(uci_get "network.${interface}.type")" = "bridge" ]; then
		# das Bridge-Interface existiert nicht (d.h. es ist down)
		[ -z "$(ip link show dev "br-${interface}" 2>/dev/null)" ] && trap "" $GUARD_TRAPS && return 1
		# Bridge ist aus? Damit ist das befragte Interface ebenfalls aus ...
		ip link show dev "br-${interface}" | grep -q "[\t ]state DOWN[\ ]" && trap "" $GUARD_TRAPS && return 1
	fi
	local device
	for device in $(get_subdevices_of_interface "$interface"); do
		ip link show dev "$device" | grep -q "[\t ]state UP[\ ]" && return 0
		true
	done
	trap "" $GUARD_TRAPS && return 1
}

# Ende der Doku-Gruppe
## @}
