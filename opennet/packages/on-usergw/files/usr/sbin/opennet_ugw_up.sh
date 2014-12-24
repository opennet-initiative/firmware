#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2010 Rene Ejury <opennet@absorb.it>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#

. "${IPKG_INSTROOT:-}/lib/functions.sh"

# die obige "lib/functions.sh" vertraegt keinen strikten Modus
set -eu
. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

# newline
N="
"
msg_debug "starting for iface ${dev}"

local batch
# add new network to configuration (to be recognized by olsrd)
append batch "set network.on_${dev}=interface${N}"
append batch "set network.on_${dev}.proto=static${N}"
append batch "set network.on_${dev}.ifname=${dev}${N}"
append batch "set network.on_${dev}.netmask=${ifconfig_netmask}${N}"
append batch "set network.on_${dev}.ipaddr=${ifconfig_local}${N}"
append batch "set network.on_${dev}.defaultroute=0${N}"
append batch "set network.on_${dev}.peerdns=0${N}"

msg_debug "adding new network config for ${dev}"

echo "$batch" | uci batch
apply_changes network

# Interface zur opennet-mesh-Zone hinzufuegen
add_interface_to_zone "$ZONE_MESH" "on_$dev"
apply_changes firewall

update_olsr_interfaces

filename=/tmp/opennet_ugw-$(get_safe_filename "${remote_1:-}${remote_2:-}${remote_3:-}${remote_4:-}").txt
echo "$dev" > "$filename" # a short message for the web frontend

msg_debug "finished for iface ${dev}"

exit 0

