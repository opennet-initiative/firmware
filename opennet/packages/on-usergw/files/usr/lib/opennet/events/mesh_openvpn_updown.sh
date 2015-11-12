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


get_netname() {
	local ifname="$1"
	echo "$ifname" | sed 's/[^0-9a-zA-Z]/_/g'
}


setup_mesh_interface() {
	local ifname="$1"
	local netname
	netname=$(get_netname "$ifname")
	uci set "network.${netname}=interface"
	uci set "network.${netname}.proto=none"
	# wir duerfen das Interface nicht via uci hinzufuegen - andernfalls verliert das Interface durch netifd seine Konfiguration
	# siehe https://lists.openwrt.org/pipermail/openwrt-devel/2015-June/033501.html
	#uci set "network.${netname}.ifname=$ifname"
	ubus call network reload
	add_interface_to_zone "$ZONE_MESH" "$netname"
	apply_changes network firewall
	# indirekte Interface/Network-Zuordnung (siehe obigen Mailinglisten-Beitrag)
	# Auf diesem Weg bleibt die IP-Konfiguration des Device erhalten.
	local ubus_dev="network.interface.${netname}"
	ubus call "$ubus_dev" add_device '{ "name": "'$ifname'" }'
	# die obige ubus-Aktion wird nebenlaeufig abgearbeitet - wir muessen das Ergebnis abwarten
	ubus -t 10 wait_for "$ubus_dev"
	# expliziter olsrd-Neustart: eventuell sind noch Fragmente alter tap-Devices in
	# der olsrd-Konfiguration eingetragen. Diese verhindern einen olsrd-Neustart,
	# da es scheinbar keine Änderung gab.
	/etc/init.d/olsrd restart
	# ohne dieses explizite reload reagiert die firewall seltsamerweise nicht auf die neuen Interfaces
	/etc/init.d/firewall reload
	# iu Kuerze moege die olsr-Interface-Liste neu erstellt werden (inkl. des neuen Interface)
	echo "on-function update_olsr_interfaces" | schedule_task
}


cleanup_mesh_interface() {
	local ifname="$1"
	local netname
	netname=$(get_netname "$ifname")
	del_interface_from_zone "$ZONE_MESH" "$netname"
	uci_delete "network.${netname}"
	apply_changes network firewall
	update_olsr_interfaces
}


log_openvpn_events_and_disconnect_if_requested "mesh-openvpn-connections"


case "$script_type" in
	up)
		setup_mesh_interface "$dev"
		;;
	down)
		cleanup_mesh_interface "$dev"
		;;
esac 2>&1 | logger -t mesh-updown

exit 0
