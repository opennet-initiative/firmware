#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# Copyright 2015 Lars Kruse <devel@sumpfralle.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#


. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


# parse die foreign-Options, beispielsweise:
#   foreign_option_4='dhcp-option DNS 10.1.0.1'
# Ergebnis: zeilenweise Auflistung von DHCP-Options und zugehoerigem Wert
# Beispielsweise:
#   DNS 10.1.0.1
#   NTP 10.1.0.1
get_servers_from_dhcp_options() {
	local index=1
	local option
	while true; do
		# prüfe ob die "foreign_option_XXX"-Variable gesetzt ist
		option=$(eval echo "\${foreign_option_$index:-}")
		[ -z "$option" ] && break
		echo "$option"
		: $((index++))
	done | awk '{ if ($1 == "dhcp-option") print $2,$3 }'
}


# die PATH-Umgebungsvariable beim Ausfuehren des openvpn-Skripts beinhaltet leider nicht die sbin-Verzeichnisse
IP_BIN=$(PATH=$PATH:/sbin:/usr/sbin which ip)


# Allgemeine openvpn-Ereignisbehandlung
log_openvpn_events_and_disconnect_if_requested "mig-openvpn-connections"

# Sonder-Aktionen für mig-Verbindungen
case "$script_type" in
	up)
		"$IP_BIN" route add default via "$route_vpn_gateway" table "$ROUTING_TABLE_ON_UPLINK" || true
		# verhindere das Routing von explizit unerwuenschtem Verkehr ueber den Nutzer-Tunnel (falls die Regel noch nicht existiert)
		"$IP_BIN" route add throw default table "$ROUTING_TABLE_ON_UPLINK" tos "$TOS_NON_TUNNEL" 2>/dev/null || true
		get_servers_from_dhcp_options >"$MIG_PREFERRED_SERVERS_FILE"
		update_dns_servers
		update_ntp_servers
		;;
	down)
		# löse einen baldigen Verbindungsaufbau aus
		is_on_module_installed_and_enabled "on-openvpn" \
			&& has_mig_openvpn_credentials \
			&& { echo "on-function update_mig_connection_status" | schedule_task; }
		true
		rm -f "$MIG_PREFERRED_SERVERS_FILE"
		update_dns_servers
		update_ntp_servers
		;;
esac 2>&1 | logger -t mig-updown

exit 0
