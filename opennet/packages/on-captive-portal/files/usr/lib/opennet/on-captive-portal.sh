## @defgroup captive_portal Captive Portal
## @brief Funktionen für den Umgang mit der Captive-Portal-Software für offene WLAN-Knoten
# Beginn der Doku-Gruppe
## @{


ZONE_FREE=on_free
NETWORK_FREE=on_free
## @var Quelldatei für Standardwerte des Hotspot-Pakets
ON_CAPTIVE_PORTAL_DEFAULTS_FILE=/usr/share/opennet/captive-portal.defaults


## @fn captive_portal_get_or_create_config()
## @brief Liefere die uci-captive-Portal-Konfigurationssektion zurück.
## @details Typischerweise ist dies so etwas wie nodogsplash.cfgXXXX. Falls die uci-Sektion noch
##   nicht existieren sollte, dann wird sie erzeugt und zurückgeliefert.
captive_portal_get_or_create_config() {
	trap "error_trap captive_portal_get_or_create_config '$*'" $GUARD_TRAPS
	local uci_prefix
	uci_prefix=$(find_first_uci_section "nodogsplash" "instance" "network=$NETWORK_FREE")
	# gefunden? Zurueckliefern ...
	if [ -z "$uci_prefix" ]; then
		# neu mit grundlegenden Einstellungen anlegen
		# Detail-Konfiguration findet via uci-defaults nur einmalig statt (damit der Nutzer sie überschreiben kann)
		uci_prefix="nodogsplash.$(uci add "nodogsplash" "instance")"
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
		# ssh/web (TODO: entfernen - nur fuer Debugging)
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 22"
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 80"
		# DNS
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 53"
		uci add_list "${uci_prefix}.users_to_router=allow udp port 53"
		# DHCP
		uci add_list "${uci_prefix}.users_to_router=allow udp port 67"
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
		ndsctl auth "$ip"
	done
}


## @fn captive_portal_reload()
## @brief Neukonfiguration der Captive-Portal-Software, falls Änderungen aufgetreten sind.
## @details Bestehende Verbindungen bleiben erhalten.
captive_portal_reload() {
	/etc/init.d/nodogsplash reload >/dev/null
}


## @fn captive_portal_has_devices()
## @brief Prüfe, ob dem Captive Portal mindestens ein physisches Netzwerk-Gerät zugeordnet ist.
## @details Sobald ein Netzwerk-Gerät konfiguriert ist, gilt der Captive-Portal-Dienst als aktiv.
captive_portal_has_devices() {
	[ -n "$(get_subdevices_of_interface "$NETWORK_FREE")" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


update_captive_portal_status() {
	if is_on_module_installed_and_enabled "on-captive-portal"; then
		sync_captive_portal_state_with_mig_connections
	else
		disable_captive_portal
	fi
}


disable_captive_portal() {
	# free-Interface ist aktive - es gibt jedoch keinen Tunnel
	ifdown "$NETWORK_FREE"
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
	if [ -n "$device_active" -a -z "$mig_active" ]; then
		disable_captive_portal
	elif [ -z "$device_active" -a -n "$mig_active" ]; then
		# kein aktives free-Interface, aber ein aktiver Tunnel
		ifup "$NETWORK_FREE"
	fi
	# warte auf das Netzwerk-Interface
	sleep 3
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
		if [ -z "$key" -a -n "$ip_address" ]; then
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
