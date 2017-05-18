## @defgroup captive_portal Captive Portal
## @brief Funktionen für den Umgang mit der Captive-Portal-Software für offene WLAN-Knoten
# Beginn der Doku-Gruppe
## @{


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


## @fn captive_portal_get_or_create_config()
## @brief Liefere die uci-captive-Portal-Konfigurationssektion zurück.
## @details Typischerweise ist dies so etwas wie nodogsplash.cfgXXXX. Falls die uci-Sektion noch
##   nicht existieren sollte, dann wird sie erzeugt und zurückgeliefert.
captive_portal_get_or_create_config() {
	trap "error_trap captive_portal_get_or_create_config '$*'" $GUARD_TRAPS
	local uci_prefix
	uci_prefix=$(find_first_uci_section "nodogsplash" "nodogsplash" "network=$NETWORK_FREE")
	# gefunden? Zurueckliefern ...
	if [ -z "$uci_prefix" ]; then
		# neu mit grundlegenden Einstellungen anlegen
		# Detail-Konfiguration findet via uci-defaults nur einmalig statt (damit der Nutzer sie überschreiben kann)
		uci_prefix="nodogsplash.$(uci add "nodogsplash" "nodogsplash")"
		# wir aktivieren den Dienst generell - der Nutzer muss dem Device aktiv ein Gerät hinzufügen, um es zu aktivieren
		uci set "${uci_prefix}.enabled=1"
		uci set "${uci_prefix}.network=$NETWORK_FREE"
		uci set "${uci_prefix}.gatewayname=$(get_on_captive_portal_default "node_name")"
		uci set "${uci_prefix}.redirecturl=$(get_on_captive_portal_default "portal_url")"
		uci set "${uci_prefix}.maxclients=250"
		# kein Zwischen-Klick, keine lokale Webseite
		uci set "${uci_prefix}.authenticateimmediately=1"
		# Wir definieren keine "authenticated"-Regeln: nodogsplash verwendet "RETURN", falls
		# diese Liste leer ist. Dies ist wünschenswert, auf dass wir mit unserer firewall-
		# Einstellung der free-Zone den gewünschten Verkehrsfluss regeln können. Typischerweise
		# ist hier lediglich eine free->on_openvpn-Zonenregel erforderlich.
		# Demgegenüber ist es für den "users-to-router"-Verkehr praktischer, die einfachen
		# nodogsplash-Einstellungen zu verwenden. Dadurch vermeiden wir die Verwaltung
		# separater firewall-Regeln.
		# ssh/web (nur fuer Debugging)
		#uci add_list "${uci_prefix}.users_to_router=allow tcp port 22"
		#uci add_list "${uci_prefix}.users_to_router=allow tcp port 443"
		# DNS
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 53"
		uci add_list "${uci_prefix}.users_to_router=allow udp port 53"
		# DHCP
		uci add_list "${uci_prefix}.users_to_router=allow udp port 67"
		# jeglichen Verkehr ohne Interaktion zulassen
		# (lediglich der erste Zugriff auf Port 80 wird auf die Portalseite umgelenkt)
		uci set "${uci_prefix}.policy_preauthenticated_users=passthrough"
		# erstmal nur speichern - um die Anwendung kuemmert sich jemand anders
		uci commit nodogsplash
	fi
	echo -n "$uci_prefix"
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


## @fn captive_portal_set_property()
## @brief Setze ein Attribut der Captive-Portal-Funktion
## @param key Eins der Captive-Portal-Attribute: name / url
## @param value Der gewünschte neue Inhalt des Attributs
## @attention Anschließend ist 'apply_changes on-captive-portal' aufzurufen, um die Änderungen wirksam werden zu lassen.
captive_portal_set_property() {
	local key="$1"
	local value="$2"
	local uci_attribute
	uci_attribute=$(_captive_portal_get_mapped_attribute "$key")
	# ein Fehler ist aufgetreten - die obige subshell verdeckt ihn jedoch
	[ -z "$uci_attribute" ] && return 1
	local uci_prefix
	uci_prefix=$(captive_portal_get_or_create_config)
	uci set "${uci_prefix}.${uci_attribute}=$value"
}


## @fn captive_portal_get_property()
## @brief Hole ein Attribut der Captive-Portal-Funktion
## @param key Eins der Captive-Portal-Attribute: name / url
captive_portal_get_property() {
	local key="$1"
	local uci_attribute
	uci_attribute=$(_captive_portal_get_mapped_attribute "$key")
	# ein Fehler ist aufgetreten - die obige subshell verdeckt ihn jedoch
	[ -z "$uci_attribute" ] && return 1
	local uci_prefix
	uci_prefix=$(captive_portal_get_or_create_config)
	uci_get "${uci_prefix}.${uci_attribute}"
}


## @fn _captive_portal_get_mapped_attribute()
## @brief Liefere den UCI-Attribut-Namen für eine Captive-Portal-Eigenschaft zurück.
## @param attribute Eins der Captive-Portal-Attribute: name / url
## @details Dies ist lediglich eine Abstraktionsschicht.
_captive_portal_get_mapped_attribute() {
	local attribute="$1"
	if [ "$attribute" = "name" ]; then
		echo -n "gatewayname"
	elif [ "$attribute" = "url" ]; then
		echo -n "redirecturl"
	else
		msg_error "unknown captive portal attribute mapping requested: $attribute"
		return 1
	fi
}


## @fn captive_portal_restart()
## @brief Führe einen Neustart der Captive-Portal-Software mit minimalen Seiteneffekten durch.
## @details Aktuelle Verbindungen bleiben nach Möglichkeit erhalten.
captive_portal_restart() {
	trap "error_trap captive_portal_restart '$*'" $GUARD_TRAPS
	# alte Clients-Liste sichern; keine Fehlerausgabe bei gestopptem Prozess
	local clients
	clients=$(ndsctl clients 2>/dev/null | grep "^ip=" | cut -f 2 -d =)
	# Prozess neustarten (reload legt wohl keine iptables-Regeln an)
	/etc/init.d/nodogsplash restart >/dev/null
	# kurz warten, damit der Dienst startet
	sleep 1
	# kein laufender Prozess? Keine Wiederherstellung von Clients ...
	[ -z "$(pidof nodogsplash)" ] && return 0
	# Client-Liste wiederherstellen
	local ip
	echo "$clients" | while read ip; do
		[ -z "$ip" ] && continue
		ndsctl auth "$ip"
	done
}


## @fn captive_portal_reload()
## @brief Neukonfiguration der Captive-Portal-Software, falls Änderungen aufgetreten sind.
## @details Bestehende Verbindungen bleiben erhalten.
captive_portal_reload() {
	/etc/init.d/nodogsplash reload >/dev/null || true
}


## @fn captive_portal_has_devices()
## @brief Prüfe, ob dem Captive Portal mindestens ein physisches Netzwerk-Gerät zugeordnet ist.
## @details Sobald ein Netzwerk-Gerät konfiguriert ist, gilt der Captive-Portal-Dienst als aktiv.
##    Es werden sowohl nicht-wifi-, als auch wifi-Interfaces geprueft.
captive_portal_has_devices() {
	[ -n "$(get_subdevices_of_interface "$NETWORK_FREE")" ] && return 0
	[ -n "$(find_all_uci_sections wireless wifi-iface "network=$NETWORK_FREE")" ] && return 0
	trap "" $GUARD_TRAPS && return 1
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
	trap "" $GUARD_TRAPS && return 1
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
	find_all_uci_sections wireless wifi-iface "network=$NETWORK_FREE" | while read uci_prefix; do
		uci set "${uci_prefix}.disabled=$state"
	done
	apply_changes wireless
}


disable_captive_portal() {
	trap "error_trap disable_captive_portal '$*'" $GUARD_TRAPS
	msg_info "on-captive-portal: wifi-Interfaces abschalten"
	# free-Interface ist aktiv - es gibt jedoch keinen Tunnel
	change_captive_portal_wireless_disabled_state "1"
	# reload fuehrt zum sanften Stoppen
	is_captive_portal_running && sleep 1 && captive_portal_reload
	true
}


## @fn sync_captive_portal_state_with_mig_connections()
## @brief Synchronisiere den Zustand (up/down) des free-Interface mit dem des VPN-Tunnel-Interface.
## @details Diese Funktion wird nach Statusänderungen des VPN-Interface, sowie innerhalb eines
##   regelmäßigen cronjobs ausgeführt.
sync_captive_portal_state_with_mig_connections() {
	trap "error_trap sync_captive_portal_state_with_mig_connections '$*'" $GUARD_TRAPS
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
		# warte auf das Netzwerk-Interface
		sleep 5
	fi
	# Portalsoftware neu laden, falls das Interface aktiv ist, jedoch kein Prozess laeuft
	[ -n "$mig_active" ] && ! is_captive_portal_running && captive_portal_reload
	true
}


## @fn is_captive_portal_running()
## @brief Prüfe ob der Captive-Portal-Dienst läuft.
is_captive_portal_running() {
	[ -n "$(pgrep "^/usr/bin/nodogsplash$")" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


## @fn get_captive_portal_client_count()
## @brief Ermittle die Anzahl der verbundenen Clients.
get_captive_portal_client_count() {
	local count=0
	is_captive_portal_running && count=$(ndsctl clients | head -1)
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
get_captive_portal_clients() {
	trap "error_trap get_captive_portal_clients '$*'" $GUARD_TRAPS
	local line
	local key
	local value
	local ip_address=
	local mac_address=
	local connection_timestamp=
	local activity_timestamp=
	local traffic_download=
	local traffic_upload=
	# erzwinge eine leere Zeile am Ende fuer die finale Ausgabe des letzten Clients
	(ndsctl clients; echo) | while read line; do
		key=$(echo "$line" | cut -f 1 -d =)
		value=$(echo "$line" | cut -f 2- -d =)
		[ "$key" = "ip" ] && ip_address="$value"
		[ "$key" = "mac" ] && mac_address="$value"
		[ "$key" = "added" ] && connection_timestamp="$value"
		[ "$key" = "active" ] && activity_timestamp="$value"
		[ "$key" = "downloaded" ] && traffic_download="$value"
		[ "$key" = "uploaded" ] && traffic_upload="$value"
		if [ -z "$key" ] && [ -n "$ip_address" ]; then
			# leere Eingabezeile trennt Clients: Ausgabe des vorherigen Clients
			printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
				"$ip_address" "$mac_address" "$connection_timestamp" \
				"$activity_timestamp" "$traffic_download" "$traffic_upload"
			ip_address=
			mac_address=
			connection_timestamp=
			activity_timestamp=
			traffic_download=
			traffic_upload=
		fi
	done
}

# Ende der Doku-Gruppe
## @}
