## @defgroup network Netzwerk
## @brief Umgang mit uci-Netzwerk-Interfaces und Firewall-Zonen
# Beginn der Doku-Gruppe
## @{

ZONE_LOCAL=lan
ZONE_WAN=wan
ZONE_MESH=on_mesh
# shellcheck disable=SC2034
NETWORK_LOCAL=lan
# diese Domain wird testweise abgefragt, um die Verfügbarkeit des on-DNS zu prüfen
DNS_SERVICE_REFERENCE="opennet-initiative.de"
# ein Timeout von einer Sekunde scheint zu kurz zu sein (langsame Geräte brauchen mindestens 0,5s - abhängig vom Load)
DNS_TIMEOUT=3


# Liefere alle IPs fuer diesen Namen zurueck
query_dns() {
	nslookup "$1" 2>/dev/null | sed '1,3d' | grep "^Address:" | awk '{print $2}' | sort -n
}


query_dns_reverse() {
	nslookup "$1" 2>/dev/null | tail -n 1 | awk '{ printf "%s", $4 }'
}


## @fn has_opennet_dns()
## @brief Prüfe, ob *.on-Domains aufgelöst werden.
## @returns Der Exitcode ist Null, falls on-DNS verfügbar ist.
## @details Die maximale Laufzeit dieser Funktion ist auf eine Sekunde begrenzt.
has_opennet_dns() {
	trap 'error_trap has_opennet_dns "'"$*"'"' EXIT
	# timeout ist kein shell-builtin - es benoetigt also ein global ausfuehrbares Kommando
	[ -n "$(timeout "$DNS_TIMEOUT" on-function query_dns "$DNS_SERVICE_REFERENCE")" ] && return 0
	trap "" EXIT && return 1
}


## @fn get_ping_time()
## @brief Ermittle die Latenz eines Ping-Pakets auf dem Weg zu einem Ziel.
## @param target IP oder DNS-Name des Zielhosts
## @param duration die Dauer der Ping-Kommunikation in Sekunden (falls ungesetzt: 5)
## @returns Ausgabe der mittleren Ping-Zeit in ganzen Sekunden; bei Nichterreichbarkit ist die Ausgabe leer
get_ping_time() {
	trap 'error_trap get_ping_time "'"$*"'"' EXIT
	local target="$1"
	local duration="${2:-5}"
	local ip
	ip=$(query_dns "$target" | filter_routable_addresses | tail -1)
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
	trap 'error_trap add_zone_forward "'"$*"'"' EXIT
	local source="$1"
	local dest="$2"
	create_uci_section_if_missing "firewall" "forwarding" "src=$source" "dest=$dest" || true
}


# Das Masquerading in die Opennet-Zone soll nur fuer bestimmte Quell-Netze erfolgen.
# Diese Funktion wird bei hotplug-Netzwerkaenderungen ausgefuehrt.
update_opennet_zone_masquerading() {
	trap 'error_trap update_opennet_zone_masquerading "'"$*"'"' EXIT
	local network
	local network_with_prefix
	local uci_prefix
	uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_MESH")
	# Abbruch, falls die Zone fehlt
	[ -z "$uci_prefix" ] && msg_info "failed to find opennet mesh zone ($ZONE_MESH)" && return 0
	# alle masquerade-Netzwerke entfernen
	uci_delete "${uci_prefix}.masq_src"
	# aktuelle Netzwerke wieder hinzufuegen
	for network in $(get_zone_interfaces "$ZONE_LOCAL"; get_zone_interfaces "$ZONE_WAN"); do
		for network_with_prefix in $(get_current_addresses_of_network "$network"); do
			echo "$network_with_prefix"
		done
	done | uci_replace_list "${uci_prefix}.masq_src"
	if [ -n "$(uci_get "${uci_prefix}.masq_src")" ]; then
		# masquerading aktiveren (nur fuer die obigen Quell-Adressen)
		uci set "${uci_prefix}.masq=1"
	else
		# Es gibt keine lokalen Interfaces - also duerfen wir kein Masquerading aktivieren.
		# Leider interpretiert openwrt ein leeres "masq_src" nicht als "masq fuer niemanden" :(
		uci set "${uci_prefix}.masq=0"
	fi
	# Seit April 2017 (commit e751cde8) verwirft fw3 "INVALID"-Pakete (also beispielsweise
	# asymmetrische Antworten), sofern Masquerading aktiv ist. Dies schalten wir ab.
	uci set "${uci_prefix}.masq_allow_invalid=1"
	apply_changes firewall
}


## @fn get_current_addresses_of_network()
## @brief Liefere die IP-Adressen eines logischen Interface inkl. Praefix-Laenge (z.B. 172.16.0.1/24).
## @param network logisches Netzwerk-Interface
## @details Es werden sowohl IPv4- als auch IPv6-Adressen zurückgeliefert.
get_current_addresses_of_network() {
	trap 'error_trap get_current_addresses_of_network "'"$*"'"' EXIT
	local network="$1"
	{
		_run_system_network_function "network_get_subnets" "$network"
		_run_system_network_function "network_get_subnets6" "$network"
	} | xargs -r -n 1 echo
}


# Liefere die logischen Netzwerk-Schnittstellen einer Zone zurueck.
get_zone_interfaces() {
	trap 'error_trap get_zone_interfaces "'"$*"'"' EXIT
	local zone="$1"
	local uci_prefix
	local interfaces
	uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	# keine Zone -> keine Interfaces
	[ -z "$uci_prefix" ] && return 0
	interfaces=$(uci_get_list "${uci_prefix}.network")
	# falls 'network' und 'device' leer sind, dann enthaelt 'name' den Interface-Namen
	# siehe http://wiki.openwrt.org/doc/uci/firewall#zones
	[ -z "$interfaces" ] && [ -z "$(uci_get "${uci_prefix}.device")" ] && interfaces="$(uci_get "${uci_prefix}.name")"
	echo "$interfaces"
}


## @fn get_zone_raw_devices()
## @brief Ermittle die physischen Netzwerkinterfaces, die direkt einer Firewall-Zone zugeordnet sind.
## @details Hier werden _nicht_ die logischen Interfaces in die physischen aufgeloest, sondern
##   es wird lediglich der Inhalt des 'devices'-Eintrags einer Firewall-Zone ausgelesen.
get_zone_raw_devices() {
	trap 'error_trap get_zone_raw_devices "'"$*"'"' EXIT
	local zone="$1"
	local uci_prefix
	uci_prefix=$(find_first_uci_section "firewall" "zone" "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "Failed to retrieve raw devices of non-existing zone '$zone'" && return 0
	uci_get_list "${uci_prefix}.device"
}


# Ist das gegebene physische Netzwerk-Interface Teil einer Firewall-Zone?
is_device_in_zone() {
	trap 'error_trap is_device_in_zone "'"$*"'"' EXIT
	local device="$1"
	local zone="$2"
	local log_interface
	local item
	for log_interface in $(get_zone_interfaces "$2"); do
		for item in $(get_subdevices_of_interface "$log_interface"); do
			[ "$device" = "$item" ] && return 0
			true
		done
	done
	trap "" EXIT && return 1
}


# Ist das gegebene logische Netzwerk-Interface Teil einer Firewall-Zone?
is_interface_in_zone() {
	local interface="$1"
	local zone="$2"
	local item
	for item in $(get_zone_interfaces "$zone"); do
		[ "$item" = "$interface" ] && return 0
		true
	done
	trap "" EXIT && return 1
}


## @fn get_device_of_interface()
## @brief Ermittle das physische Netzwerk-Gerät, das einem logischen Netzwerk entspricht.
## @details Ein Bridge-Interface wird als Gerät betrachtet und zurückgeliefert (nicht seine Einzelteile).
get_device_of_interface() {
	local interface="$1"
	local found_bridge=0

	# OpenWrt nutzt jetzt DSA anstatt swconfig. Daher sind fuer eine Uebergangszeit hier zwei Pruefungen notwendig.
	
	# Bereite DSA Check vor. Ermittle aktuelle Anzahl an Devices laut network.@device[].
	# (Alternative zur Schleife unten ist die Nutzung von config_foreach(), siehe https://openwrt.org/docs/guide-developer/config-scripting.)
	local i=0
	local max_dev_index=-1  # finde groessten Index
	local MAX_BRIDGES=10  # oberes Limit gegen Endlosschleife
	while [ $i -lt $MAX_BRIDGES ]; do
		local dev_exists="-1"
		dev_exists="$(uci_get "network.@device[$i].type" -1)"
		if [ "$dev_exists" != "-1" ]; then
			# Device existiert
			max_dev_index=$i
		elif [ "$dev_exists" == "-1" ]; then
			# abbrechen
			i=$MAX_BRIDGES
		fi
		i=$(($i+1))
	done

	# DSA: Ist Interface eine Bridge?
	local phy_dev="$(uci_get "network.${interface}.device")"
	local i=0
	while [ $i -le $max_dev_index ]; do
		if [ "$(uci_get "network.@device[$i].name")" = "${phy_dev}" ] && [ "$(uci_get "network.@device[$i].type")" = "bridge" ]; then
			found_bridge=1
			echo "${phy_dev}"
		fi
		i=$(($i+1))
	done

	# swconfig: Ist Interface eine Bridge?
	if [ "$(uci_get "network.${interface}.type")" = "bridge" ]; then
		found_bridge=1
		echo "br-$interface"
	fi

	if [ $found_bridge -ne 1 ]; then
		# Interface ist keine Bridge
		get_subdevices_of_interface "$interface"
	fi
}


# Ist das gegebene physische Netzwerk-Interface Teil einer Firewall-Zone?
is_device_in_zone() {
	trap 'error_trap is_device_in_zone "'"$*"'"' EXIT
	local device="$1"
	local zone="$2"
	local log_interface
	local item
	for log_interface in $(get_zone_interfaces "$2"); do
		for item in $(get_subdevices_of_interface "$log_interface"); do
			[ "$device" = "$item" ] && return 0
			true
		done
	done
	trap "" EXIT && return 1
}


## @fn _run_system_network_function()
## @brief Führe eine der in /lib/functions/network.sh definierten Funktionen aus.
## @params func: der Name der Funktion
## @params ...: alle anderen Parameter werden der Funktion nach der Zielvariable (also ab
##              Parameter #2) übergeben
## @returns: die Ausgabe der Funktion
_run_system_network_function() {
	local func="$1"
	local result
	shift
	(
		set +eu
		# shellcheck source=openwrt/package/base-files/files/lib/functions/network.sh
		. /lib/functions/network.sh
		"$func" result "$@"
		[ -n "$result" ] && echo "$result"
		set -eu
	)
}

## @fn get_subdevices_of_interface()
## @brief Ermittle die physischen Netzwerk-Geräte (bis auf wifi), die zu einem logischen Netzwerk-Interface gehören.
## @details Im Fall eines Bridge-Interface werden nur die beteiligten Komponenten zurückgeliefert.
##   Wifi-Geräte werden nur dann zurückgeliefert, wenn sie Teil einer Bridge sind. Andernfalls sind ihre Namen nicht
##   ermittelbar.
## @returns Der oder die Namen der physischen Netzwerk-Geräte oder nichts.
get_subdevices_of_interface() {
	trap 'error_trap get_subdevices_of_interface "'"$*"'"' EXIT
	local interface="$1"
	local device
	local uci_prefix
	{
		# kabelgebundene Geräte
		for device in $(uci_get "network.${interface}.device"); do
			# entferne Alias-Nummerierungen
			device=$(echo "$device" | cut -f 1 -d :)
			[ -z "$device" ] || [ "$device" = "none" ] && continue
			echo "$device"
		done
		# wir fügen das Ergebnis der ubus-Abfrage hinzu (unten werden Duplikate entfernt)
		_run_system_network_function "network_get_physdev" "$interface"
	} | tr ' ' '\n' | sort | uniq | while read -r device; do
		# Falls das Verzeichnis existiert, ist es wohl eine Bridge, deren Bestandteile wir ausgeben.
		# Ansonsten wird das Device ausgegeben.
		ls "/sys/devices/virtual/net/$device/brif/" 2>/dev/null || echo "$device"
	done | sort | uniq | grep -v "^none$" | grep -v "^$" || true
}


## @fn add_interface_to_zone()
## @brief Fuege ein logisches Netzwerk-Interface zu einer Firewall-Zone hinzu.
## @details Typischerweise ist diese Funktion nur fuer temporaere Netzwerkschnittstellen geeignet.
add_interface_to_zone() {
	local zone="$1"
	local interface="$2"
	local uci_prefix
	uci_prefix=$(find_first_uci_section "firewall" "zone" "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "Failed to add interface '$interface' to non-existing zone '$zone'" && return 0
	uci_add_list "${uci_prefix}.network" "$interface"
}


## @fn del_interface_from_zone()
## @brief Entferne ein logisches Interface aus einer Firewall-Zone.
del_interface_from_zone() {
	local zone="$1"
	local interface="$2"
	local uci_prefix
	uci_prefix=$(find_first_uci_section "firewall" "zone" "name=$zone")
	[ -z "$uci_prefix" ] && msg_debug "Failed to remove interface '$interface' from non-existing zone '$zone'" && trap "" EXIT && return 1
	uci -q del_list "${uci_prefix}.network=$interface"
}


## @fn get_zone_of_device()
## @brief Ermittle die Zone eines physischen Netzwerk-Interfaces.
## @param interface Name eines physischen Netzwerk-Interface (z.B. eth0)
## @details Das Ergebnis ist ein leerer String, falls zu diesem Interface keine Zone existiert
##   oder falls es das Interface nicht gibt.
get_zone_of_device() {
	trap 'error_trap get_zone_of_device "'"$*"'"' EXIT
	local device="$1"
	local uci_prefix
	local zone
	local interface
	local current_device
	find_all_uci_sections firewall zone | while read -r uci_prefix; do
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
	trap 'error_trap get_zone_of_interface "'"$*"'"' EXIT
	local interface="$1"
	local uci_prefix
	local interfaces
	local zone
	find_all_uci_sections firewall zone | while read -r uci_prefix; do
		zone=$(uci_get "${uci_prefix}.name")
		interfaces=$(get_zone_interfaces "$zone")
		is_in_list "$interface" "$interfaces" && echo -n "$zone" && return 0
		true
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
	trap 'error_trap get_sorted_opennet_interfaces "'"$*"'"' EXIT
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
	find_all_uci_sections "network" "interface" | cut -f 2 -d . | while read -r interface; do
		# ignoriere loopback-Interfaces und ungueltige
		[ -z "$interface" ] || [ "$interface" = "none" ] || [ "$interface" = "loopback" ] && continue
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
	local uci_prefix
	uci_prefix=$(find_first_uci_section firewall zone "name=$zone")
	uci_delete "$uci_prefix"
	for section in "forwarding" "redirect" "rule"; do
		for key in "src" "dest"; do
			find_all_uci_sections firewall "$section" "${key}=$zone" | while read -r uci_prefix; do
				uci_delete "$uci_prefix"
			done
		done
	done
}


## @fn is_interface_up()
## @brief Prüfe ob ein logisches Netzwerk-Interface aktiv ist.
## @param interface Zu prüfendes logisches Netzwerk-Interface
## @details Im Fall eines Bridge-Interface wird sowohl der Status der Bridge (muss aktiv sein), als
##   auch der Status der Bridge-Teilnehmer (mindestens einer muss aktiv sein) geprüft.
is_interface_up() {
	trap 'error_trap is_interface_up "'"$*"'"' EXIT
	local interface="$1"
	# falls es ein uebergeordnetes Bridge-Interface geben sollte, dann muss dies ebenfalls aktiv sein
	if [ "$(uci_get "network.${interface}.type")" = "bridge" ]; then
		# das Bridge-Interface existiert nicht (d.h. es ist down)
		[ -z "$(ip link show dev "br-${interface}" 2>/dev/null || true)" ] && trap "" EXIT && return 1
		# Bridge ist aus? Damit ist das befragte Interface ebenfalls aus ...
		ip link show dev "br-${interface}" | grep -q '[\t ]state DOWN[\ ]' && trap "" EXIT && return 1
	fi
	local device
	for device in $(get_subdevices_of_interface "$interface"); do
		ip link show dev "$device" | grep -q '[\t ]state UP[\ ]' && return 0
		true
	done
	trap "" EXIT && return 1
}


## @fn get_ipv4_of_mac()
## @brief Ermittle die IPv4-Adresse zu einer MAC-Adresse
## @param mac MAC-Adresse eines Nachbarn
get_ipv4_of_mac() {
	local ip="$1"
	awk '{ if ($4 == "'"$ip"'") print $1; }' /proc/net/arp | sort | head -1
}


is_current_wifi_interface_channel_with_dfs() {
	local wifi_interface="$1"
	local channel
	channel=$(iwinfo "$wifi_interface" info | awk '{ if ($3 == "Channel:") print $4 }')
	echo "$channel" | grep -q "^[0-9]\+$" || return 1
	[ "$channel" -gt 48 ]
}


run_iwinfo_scan() {
	trap 'error_trap run_iwinfo_scan "'"$*"'"' EXIT
	local phy_device="$1"
	local wifi_interface_uci
	local wifi_interface
	local original_channel
	local needs_auto_channel
	wifi_interface_uci=$(find_first_uci_section "wireless" "wifi-iface" "device=$phy_device")
	[ -z "$wifi_interface_uci" ] && return 0
	# the field "device" is not strictly specified - thus fall back to a sane default
	wifi_interface=$(uci_get "$wifi_interface_uci.device" "wlan0")
	# try whether it works without any changes and exit early in case of success
	iwinfo "$wifi_interface" scan 2>/dev/null && return 0
	# Possible reason for failure: "scan" does not seem to work for a master on a DFS channel:
	#   https://forum.openwrt.org/t/cannot-scan-on-5g-on-tl-wr902ac/42863/2
	# (but sometimes it indeed works - thus we tried it in advance before, anyway)
	# Try hard to prepare a situation where it is possible to scan the channels.
	# Sadly this may break the HTTP connection (e.g. when accessing the wireless scan via the
	# web interface) if the user accessed the IP of the wireless interface.
	if [ "$(uci_get "$wifi_interface_uci.mode")" = "ap" ] && is_current_wifi_interface_channel_with_dfs "$wifi_interface"; then
		original_channel=$(uci_get "wireless.$phy_device.channel")
		needs_auto_channel="true"
	else
		needs_auto_channel="false"
	fi
	if [ "$needs_auto_channel" = "true" ]; then
		# switch to a non-DFS channel
		uci set "wireless.$phy_device.channel=48"
		uci commit "wireless.$phy_device"
		reload_config
		sleep 5
	fi
	iwinfo "$wifi_interface" scan
	# revert to the original setup
	if [ "$needs_auto_channel" = "true" ]; then
		uci set "wireless.$phy_device.channel=$original_channel"
		uci commit "wireless.$phy_device"
		reload_config
	fi
}


get_potential_opennet_scan_results_for_device() {
	trap 'error_trap get_potential_opennet_scan_results_for_device "'"$*"'"' EXIT
	local phy_device="$1"
	run_iwinfo_scan "$phy_device" \
		| awk '{
			if ($1 == "ESSID:") { if ((name != "") && (encryption == "none")) print(signal"\t"channel"\t"quality"\t"name); split($0, tokens, /"/); name=tokens[2]; };
			if ($1 == "Signal:") signal=$2;
			if ($4 == "Quality:") quality=substr($5, 0, index($5, "/") - 1);
			if ($3 == "Channel:") channel=$4;
			if ($1 == "Encryption:") encryption=$2;
		}' \
		| sort -n \
		| grep -E "(opennet|\bon\b)" \
		| grep -vF "join.opennet-initiative.de" || true
}

# Ende der Doku-Gruppe
## @}
