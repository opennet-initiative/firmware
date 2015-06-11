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


set -eu

# die PATH-Umgebungsvariable beim Ausfuehren des openvpn-Skripts beinhaltet leider nicht die sbin-Verzeichnisse
IP_BIN=$(PATH=$PATH:/sbin:/usr/sbin which ip)


# Allgemeine openvpn-Ereignisbehandlung
on-function log_openvpn_events_and_disconnect_if_requested "mig-openvpn-connections"

# Sonder-Aktionen für mig-Verbindungen
case "$script_type" in
	up)
		uplink_table=$(on-function get_variable "ROUTING_TABLE_ON_UPLINK")
		"$IP_BIN" route add default via "$route_vpn_gateway" table "$uplink_table" || true
		;;
	down)
		;;
esac 2>&1 | logger -t mig-updown

exit 0

