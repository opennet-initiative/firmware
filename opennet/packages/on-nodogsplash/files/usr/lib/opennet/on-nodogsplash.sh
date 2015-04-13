## @defgroup nodogsplash NoDogSplash
## @brief Funktionen für den Umgang mit der Captive-Portal-Software für offene WLAN-Knoten
# Beginn der Doku-Gruppe
## @{


ZONE_FREE=free
NETWORK_FREE=free
NODOGSPLASH_CONFIG_NAME="on_portal"
## @var Quelldatei für Standardwerte des Hotspot-Pakets
ON_WIFIDOG_DEFAULTS_FILE=/usr/share/opennet/wifidog.defaults


nodogsplash_get_or_create_config() {
	local uci_prefix=$(find_first_uci_section "nodogsplash" "instance" "name=$NODOGSPLASH_CONFIG_NAME")
	# gefunden? Zurueckliefern ...
	if [ -z "$uci_prefix" ]; then
		# neu mit grundlegenden Einstellungen anlegen
		# Detail-Konfiguration findet via uci-defaults nur einmalig statt (damit der Nutzer sie überschreiben kann)
		uci_prefix="nodogsplash.$(uci add "nodogsplash" "instance")"
		# erstmal nicht aktivieren (enabled=0 ist der Standard)
		uci set "${uci_prefix}.network=$NETWORK_FREE"
		uci set "${uci_prefix}.gatewayname=$(get_on_nodogsplash_default "node_name")"
		uci set "${uci_prefix}.redirecturl=$(get_on_nodogsplash_default "portal_url")"
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
		# ssh (TODO: entfernen - nur fuer Debugging)
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 22"
		# DNS
		uci add_list "${uci_prefix}.users_to_router=allow tcp port 53"
		uci add_list "${uci_prefix}.users_to_router=allow udp port 53"
		# DHCP
		uci add_list "${uci_prefix}.users_to_router=allow udp port 67"
	fi
	echo -n "$uci_prefix"
}


## @fn get_on_nodogsplash_default()
## @brief Liefere einen der default-Werte der aktuellen Firmware zurück (Paket on-nodogsplash).
## @param key Name des Schlüssels
## @details Die default-Werte werden nicht von der Konfigurationsverwaltung uci verwaltet.
##   Somit sind nach jedem Upgrade imer die neuesten Standard-Werte verfügbar.
get_on_nodogsplash_default() {
	_get_file_dict_value "$1" "$ON_CORE_DEFAULTS_FILE"
}


# Ende der Doku-Gruppe
## @}
