## @defgroup captive_portal Captive Portal
## @brief Funktionen für den Umgang mit der Captive-Portal-Software für offene WLAN-Knoten
# Beginn der Doku-Gruppe
## @{


# shellcheck disable=SC2034
ZONE_FREE=on_free
NETWORK_FREE=on_free
## @var Quelldatei für Standardwerte des Hotspot-Pakets
ON_CAPTIVE_PORTAL_DEFAULTS_FILE=/usr/share/opennet/captive-portal.defaults


## @fn configure_free_network()
## @brief Erzeuge das free-Netzwerk-Interface, falls es noch nicht existiert.
configure_free_network() {
	local uci_prefix="network.$NETWORK_FREE"
	# es wurde bereits einmalig konfiguriert
	if [ -z "$(uci_get "$uci_prefix")" ]; then
		uci set "${uci_prefix}=interface"
		uci set "${uci_prefix}.ifname=none"
		uci set "${uci_prefix}.proto=static"
		uci set "${uci_prefix}.ipaddr=$(get_on_captive_portal_default free_ipaddress)"
		uci set "${uci_prefix}.netmask=$(get_on_captive_portal_default free_netmask)"
		uci set "${uci_prefix}.auto=1"
		apply_changes network
	fi
	# konfiguriere DHCP
	uci_prefix=$(find_first_uci_section "dhcp" "dhcp" "interface=$NETWORK_FREE")
	# beenden, falls vorhanden
	if [ -z "$uci_prefix" ]; then
		# DHCP-Einstellungen fuer dieses Interface festlegen
		uci_prefix="dhcp.$(uci add "dhcp" "dhcp")"
		uci set "${uci_prefix}.interface=$NETWORK_FREE"
		uci set "${uci_prefix}.start=10"
		uci set "${uci_prefix}.limit=240"
		uci set "${uci_prefix}.leasetime=30m"
		apply_changes dhcp
	fi
}


## @fn get_on_captive_portal_default()
## @param key Name des Schlüssels
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-captive-portal).
## @details Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
##   Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfügbar.
get_on_captive_portal_default() {
	local key="$1"
	_get_file_dict_value "$key" "$ON_CAPTIVE_PORTAL_DEFAULTS_FILE"
}


## @fn captive_portal_has_devices()
## @brief Prüfe, ob dem Captive Portal mindestens ein physisches Netzwerk-Gerät zugeordnet ist.
## @details Sobald ein Netzwerk-Gerät konfiguriert ist, gilt der Captive-Portal-Dienst als aktiv.
##    Es werden sowohl nicht-wifi-, als auch wifi-Interfaces geprueft.
captive_portal_has_devices() {
	[ -n "$(get_subdevices_of_interface "$NETWORK_FREE")" ] && return 0
	[ -n "$(find_all_uci_sections wireless wifi-iface "network=$NETWORK_FREE")" ] && return 0
	trap "" EXIT && return 1
}


## @fn captive_portal_repair_empty_network_bridge()
## @brief Reduziere Konstruktionen wie beispielsweise "bridge(None, wlan0)" zu "wlan0".
## @details Brücken mit "none"-Elementen verwirren das nodogsplash-Start-Skript.
captive_portal_repair_empty_network_bridge() {
	local uci_prefix="network.${NETWORK_FREE}"
	local sub_device_count
	if [ "$(uci_get "${uci_prefix}.type")" = "bridge" ] && [ "$(uci_get "${uci_prefix}.ifname")" = "none" ]; then
		# verdaechtig: Bruecke mit "none"-Device
		sub_device_count=$(get_subdevices_of_interface "$NETWORK_FREE" | wc -w)
		if [ "$sub_device_count" -eq "1" ]; then
			# wifi-Device is konfiguriert - Bruecke und "none" kann entfernt werden
			uci_delete "${uci_prefix}.type"
			uci_delete "${uci_prefix}.ifname"
		else
			# nichts ist konfiguriert - erstmal nur die Bruecke entfernen
			uci_delete "${uci_prefix}.type"
		fi
		apply_changes network
	fi
}


## @fn captive_portal_uses_wifi_only_bridge()
## @brief Prüfe ob eine fehleranfällige Brige-Konstruktion vorliegt.
## @details Reine wifi-Bridges scheinen mit openwrt nicht nutzbar zu sein.
captive_portal_uses_wifi_only_bridge() {
	local uci_prefix="network.${NETWORK_FREE}"
	local ifname
	if [ "$(uci_get "${uci_prefix}.type")" = "bridge" ]; then
		ifname=$(uci_get "${uci_prefix}.ifname")
		if [ -z "$ifname" ] || [ "$ifname" = "none" ]; then
			if [ -n "$(get_subdevices_of_interface "$NETWORK_FREE")" ]; then
				# anscheinend handelt es sich um eine reine wifi-Bridge
				return 0
			fi
		fi
	fi
	trap "" EXIT && return 1
}


update_captive_portal_status() {
	if is_on_module_installed_and_enabled "on-captive-portal"; then
		sync_captive_portal_state_with_mig_connections
	else
		disable_captive_portal
	fi
}


change_captive_portal_wireless_disabled_state() {
	local state="$1"
	local uci_prefix
	find_all_uci_sections wireless wifi-iface "network=$NETWORK_FREE" | while read -r uci_prefix; do
		uci set "${uci_prefix}.disabled=$state"
	done
	apply_changes wireless
}


disable_captive_portal() {
	trap "error_trap disable_captive_portal" EXIT
	msg_info "on-captive-portal: wifi-Interfaces abschalten"
	# free-Interface ist aktiv - es gibt jedoch keinen Tunnel
	change_captive_portal_wireless_disabled_state "1"
}


## @fn sync_captive_portal_state_with_mig_connections()
## @brief Synchronisiere den Zustand (up/down) des free-Interface mit dem des VPN-Tunnel-Interface.
## @details Diese Funktion wird nach Statusänderungen des VPN-Interface, sowie innerhalb eines
##   regelmäßigen cronjobs ausgeführt.
sync_captive_portal_state_with_mig_connections() {
	trap "error_trap sync_captive_portal_state_with_mig_connections" EXIT
	# eventuelle defekte/verwirrende Netzwerk-Konfiguration korrigieren
	captive_portal_repair_empty_network_bridge
	# Abbruch, falls keine Netzwerk-Interfaces zugeordnet wurden
	captive_portal_has_devices || return 0
	local mig_active
	local address
	local device_active=
	mig_active=$(get_active_mig_connections)
	if is_interface_up "$NETWORK_FREE"; then
		# Pruefe ob mindestens eine IPv4-Adresse konfiguriert ist.
		# (aus unbekannten Gruenden kann es vorkommen, dass die IPv4-Adresse spontan wegfaellt)
		for address in $(get_current_addresses_of_network "$NETWORK_FREE"); do
			is_ipv4 "$address" && device_active=1 && break
			true
		done
	fi
	if [ -n "$device_active" ] && [ -z "$mig_active" ]; then
		disable_captive_portal
	elif [ -n "$mig_active" ]; then
		[ -z "$device_active" ] && ifup "$NETWORK_FREE"
		change_captive_portal_wireless_disabled_state "0"
	fi
}


## @fn is_captive_portal_running()
## @brief Prüfe ob das Netzwerk-Interface des Captive-Portal aktiv ist.
is_captive_portal_running() {
	is_interface_up "$NETWORK_FREE" && return 0
	trap "" EXIT && return 1
}


## @fn get_captive_portal_client_count()
## @brief Ermittle die Anzahl der verbundenen Clients. Leere Ausgabe, falls keine aktiven
##        Interfaces vorhanden sind.
get_captive_portal_client_count() {
	local count=
	local this_count
	local assoclist
	local device
	if is_captive_portal_running; then
		count=0
		for device in $(get_subdevices_of_interface "$NETWORK_FREE"); do
			if assoclist=$(iwinfo "$device" assoclist 2>/dev/null); then
				this_count=$(echo "$assoclist" | awk '{ if (($1 == "TX:") && ($(NF-1) >= 100)) count++; } END { print count; }')
			else
				# determine the number of valid arp cache items for this interface
				this_count=$(ip neighbor list dev "$device" | grep -c 'REACHABLE$' || true)
			fi
			count=$((count + this_count))
		done
	fi
	# Liefere keine Ausgabe (leer), falls wir gar nichts zum Zaehlen gefunden haben.
	# Dadurch kann das munin-Plugin (und andere Aufrufer) erkennen, dass das Portal nicht
	# laeuft.
	[ -z "$count" ] && return 0
	echo -n "$count"
}


## @fn get_captive_portal_clients()
## @brief Zeilenweise aller aktuellen Clients inklusive ihrer relevanten Kenngrößen.
## @details In jeder Zeile wird ein Client beschrieben, wobei die folgenden Detailinformationen durch Tabulatoren getrennt sind:
##   * IP-Adresse
##   * MAC-Adresse
##   * Zeitpunkt des Verbindungsaufbaus (seit epoch)
##   * Zeitpunkt der letzten Aktivität (seit epoch)
##   * Download-Verkehrsvolumen (kByte)
##   * Upload-Verkehrsvolumen (kByte)
## Der Einfachheit halber nehmen wir an, dass alle DHCP-Clients auch Captive-Portal-Clients sind.
get_captive_portal_clients() {
	trap 'error_trap get_captive_portal_clients "'"$*"'"' EXIT
	local ip_address
	local mac_address
	local timestamp
	local packets_rxtx
	# Die "iwinfo assoclist" ist wahrscheinlich der einzige brauchbare Weg, um
	# Verkehrsstatistiken zu beliebigen Peers zu erhalten. Wir müssen es also gar nicht erst
	# mit anderen (nicht-wifi) Interfaces versuchen.
	local assoclist
	assoclist=$(for device in $(get_subdevices_of_interface "$NETWORK_FREE"); do \
		iwinfo wlan0 assoclist 2>/dev/null || true; done)
	# erzwinge eine leere Zeile am Ende fuer die finale Ausgabe des letzten Clients
	# shellcheck disable=SC2034
	while read -r timestamp mac_address ip_address hostname misc; do
		# eine assoclist-Zeile sieht etwa folgendermassen aus:
		#    TX: 6.5 MBit/s, MCS 0, 20MHz                     217 Pkts.
		packets_rxtx=$(echo "$assoclist" | awk '
			BEGIN { my_mac = tolower("'"$mac_address"'"); }
			{
				if ($1 ~ /^(..:){5}..$/) current_mac = tolower($1);
				if (($1 == "RX:") && (my_mac == current_mac)) my_rx=$(NF-1);
				if (($1 == "TX:") && (my_mac == current_mac)) my_tx=$(NF-1);
			}
			END { OFS="\t"; print(my_rx, my_tx); }')
		printf '%s\t%s\t%s\t%s\n' "$ip_address" "$mac_address" "$timestamp" "$packets_rxtx"
	done </var/dhcp.leases
}

# Ende der Doku-Gruppe
## @}
