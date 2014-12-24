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

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

msg_debug "starting for iface ${dev}"
msg_debug "removing network config for ${dev}"

uci delete "network.on_${dev}"
apply_changes network

msg_debug "removing interface ${dev} from config of firewall zone opennet"
del_interface_from_zone "$ZONE_MESH" "on_$dev"
apply_changes firewall

msg_debug "removing interface ${dev} from config of olsrd, restarting olsrd"
update_olsr_interfaces

filename=/tmp/opennet_ugw-${remote_1}.txt
rm -f "$filename"    # removing running message

msg_debug "finished for iface ${dev}"

exit 0

