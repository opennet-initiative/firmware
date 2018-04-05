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
	ubus call "$ubus_dev" add_device '{ "name": "'"$ifname"'" }'
	# die obige ubus-Aktion wird nebenlaeufig abgearbeitet - wir muessen das Ergebnis abwarten
	ubus -t 10 wait_for "$ubus_dev"
	# expliziter olsrd-Neustart: eventuell sind noch Fragmente alter tap-Devices in
	# der olsrd-Konfiguration eingetragen. Diese verhindern einen olsrd-Neustart,
	# da es scheinbar keine Änderung gab.
	/etc/init.d/olsrd restart || true
	# ohne dieses explizite reload reagiert die firewall seltsamerweise nicht auf die neuen Interfaces
	/etc/init.d/firewall reload
	# iu Kuerze moege die olsr-Interface-Liste neu erstellt werden (inkl. des neuen Interface)
	echo "on-function update_olsr_interfaces" | schedule_task
}


# UGWs ohne lokale Mesh-Interfaces sollen auch über ihre Main-IP erreichbar sein
# Wir konfigurieren die Main-IP abseits von uci manuell als /32-Adresse. Es gibt also keine
# Beeinflussung des Routings. Die zusätliche Adresse wird nur konfiguriert, falls die Main-IP
# nicht bereits auf einem realen Interface aktiv ist (siehe "ip addr show").
# Jedes einzelne OpenVPN-Mesh-Interface erhält diese zusätzliche Adresse.
add_main_ip_if_missing() {
	local dev="$1"
	local main_ip
	main_ip=$(get_main_ip)
	# irgendwie kein Main-IP? Ignorieren ...
	[ -z "$main_ip" ] && return 0
	# Ist auf einem Interface bereits eine Adresse mit dem "global"-Scope (Standard) aktiv?
	# In diesem Fall müssen wir nichts tun.
	ip addr show scope global | grep -qwF "inet $main_ip" && return 0
	# Adresse mit dem scope "host" konfigurieren - das passt inhaltlich und erleichtert uns die
	# obige Unterscheidung zwischen realen und manuell hinzugefügten Adressen.
	ip addr add "$main_ip/32" dev "$dev" scope host
}


log_openvpn_events_and_disconnect_if_requested "mesh-openvpn-connections"


# "script_type" wird von openvpn als Umgebungsvariable definiert (up/down).
# shellcheck disable=SC2154
case "$script_type" in
	up)
		setup_mesh_interface "$dev"
		add_main_ip_if_missing "$dev"
		;;
	down)
		netname=$(get_netname "$dev")
		del_interface_from_zone "$ZONE_MESH" "$netname"
		uci_delete "network.${netname}"
		default_route=$(ip route show | grep ^default | head -1)
		# firewall-Reload erzeugt viele Status-Zeilen - wir wollen das Log nicht ueberfuellen
		apply_changes network firewall 2>/dev/null
		# Aus irgendeinem Grund kann die lokale default-Route verloren gehen, wenn
		# "apply_changes network" ausgeführt wird.
		# Reproduzierbarkeit:
		#  * manuelles Töten eines Mesh-VPN-Prozess
		#  * default-Route in der main-Table fehlt
		#  * "ifup wan" behebt das Problem
		# Wir prüfen also, ob die default-Route verlorenging und fügen sie notfalls erneut hinzu.
		ip route show | grep -q ^default || {
			if [ -n "$default_route" ]; then
				# Es gab eine vorherige Route, die wir wiederherstellen können.
				add_banner_event "Lost default route during 'down' event of mesh VPN. Adding it again."
				# shellcheck disable=SC2086
				ip route replace $default_route 2>/dev/null
			else
				# Schon vor dem "down"-Event gab es keine default-Route - wir
				# verwenden also die allgemeine Korrektur-Funktion.
				# Das "banner"-Event wird durch die "fix"-Funktion erzeugt - also nur "info".
				msg_info "Detected lost default route during 'down' event of mesh VPN. Adding it again."
				fix_wan_route_if_missing
			fi
			true
		}
		;;
esac 2>&1 | logger -t mesh-updown

exit 0
