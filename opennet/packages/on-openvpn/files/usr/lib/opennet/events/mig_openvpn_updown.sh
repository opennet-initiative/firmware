#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# Copyright 2014 Lars Kruse <devel@sumpfralle.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#


. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

MSG_FILE=/tmp/openvpn_msg.txt


disconnect_current() {
	# das Namensschema der Konfigurationsdatei enthaelt den Dienstnamen
	local broken_service=$(basename "${config%.conf}")
	[ -n "$broken_service" ] && on-function set_service_value "$broken_service" "status" "n"
	# PID-Datei loeschen
	rm -f "/var/run/${broken_service}.pid"
}


case "$script_type" in
	up)
		echo "vpn-tunnel active" >"$MSG_FILE"	# a short message for the web frontend
		append_to_mig_connection_log "up" "Connecting to ${remote_1}:${remote_port_1}"
		ip route add default via "$route_vpn_gateway" table "$ROUTING_TABLE_ON_UPLINK" || true
		;;
	down)
		rm -f "$MSG_FILE"
		# der openwrt-Build von openvpn setzt wohl leider nicht die "time_duration"-Umgebungsvariable
		[ -z "${time_duration:-}" ] && time_duration=$(($(date +%s) - $daemon_start_time))
		# Verbindungsverlust durch fehlende openvpn-Pings?
		if [ "${signal:-}" = "ping-restart" ]; then
			append_to_mig_connection_log "down" "Lost connection with ${remote_1}:${remote_port_1} after ${time_duration}s"
			# markiere die aktuelle Verbindung als kaputt
			disconnect_current
		else
			append_to_mig_connection_log "down" "Closing connection with ${remote_1}:${remote_port_1} after ${time_duration}s"
		fi
		;;
	*)
		append_to_mig_connection_log "other" "${remote_1}:${remote_port_1}"
		;;
esac

exit 0

