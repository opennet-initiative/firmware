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


# die PATH-Umgebungsvariable beim Ausfuehren des openvpn-Skripts beinhaltet leider nicht die sbin-Verzeichnisse
IP_BIN=$(PATH=$PATH:/sbin:/usr/sbin which ip)


# Allgemeine openvpn-Ereignisbehandlung
log_openvpn_events_and_disconnect_if_requested "mig-openvpn-connections"

# Sonder-Aktionen für mig-Verbindungen
case "$script_type" in
	up)
		"$IP_BIN" route add default via "$route_vpn_gateway" table "$ROUTING_TABLE_ON_UPLINK" || true
		;;
	down)
		# löse einen baldigen Verbindungsaufbau aus
		is_on_module_installed_and_enabled "on-openvpn" \
			&& has_mig_openvpn_credentials \
			&& { echo "on-function update_mig_connection_status" | schedule_task; }
		true
		;;
esac 2>&1 | logger -t mig-updown

exit 0

