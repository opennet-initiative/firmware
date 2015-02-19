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


# Allgemeine openvpn-Ereignisbehandlung
log_openvpn_events_and_disconnect_if_requested "mig-openvpn-connections"

# Sonder-Aktionen für mig-Verbindungen
case "$script_type" in
	up)
		echo "vpn-tunnel active" >"$MSG_FILE"	# a short message for the web frontend
		ip route add default via "$route_vpn_gateway" table "$ROUTING_TABLE_ON_UPLINK" || true
		;;
	down)
		rm -f "$MSG_FILE"
esac

exit 0

