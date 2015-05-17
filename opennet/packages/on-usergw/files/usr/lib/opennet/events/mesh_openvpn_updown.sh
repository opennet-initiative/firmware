#!/bin/sh
#
# Opennet Firmware
#
# Copyright 2015 Lars Kruse <devel@sumpfralle.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#


. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


setup_mesh_interface() {
	local ifname="$1"
	add_raw_device_to_zone "$ZONE_MESH" "$ifname"
	apply_changes firewall
}


cleanup_mesh_interface() {
	local ifname="$1"
	del_raw_device_from_zone "$ZONE_MESH" "$ifname"
	apply_changes firewall
}


log_openvpn_events_and_disconnect_if_requested "mesh-openvpn-connections"


case "$script_type" in
	up)
		setup_mesh_interface "$dev"
		;;
	down)
		cleanup_mesh_interface "$dev"
		;;
esac

exit 0

