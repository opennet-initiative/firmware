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
	local netname=$(echo "$ifname" | sed 's/[^0-9a-zA-Z]/_/g')
	uci set "network.${netname}=interface"
	uci set "network.${netname}.proto=none"
	uci set "network.${netname}.auto=0"
	# wir duerfen das Interface nicht via uci hinzufuegen - andernfalls verliert das Interface durch netifd seine Konfiguration
	# siehe https://lists.openwrt.org/pipermail/openwrt-devel/2015-June/033501.html
	#uci set "network.${netname}.ifname=$ifname"
	add_interface_to_zone "$ZONE_MESH" "$netname"
	update_olsr_interfaces
	apply_changes network firewall
	# indirekte Interface/Network-Zuordnung (siehe obigen Mailinglisten-Beitrag)
	# Auf diesem Weg bleibt die IP-Konfiguration des Device erhalten.
	ubus call network.interface.${netname} add_device '{ "name": "'$ifname'" }'
}


cleanup_mesh_interface() {
	local ifname="$1"
	local netname=$(echo "$ifname" | sed 's/[^0-9a-zA-Z]/_/g')
	uci_delete "network.${netname}"
	del_interface_from_zone "$ZONE_MESH" "$netname"
	apply_changes network firewall
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

