ZONE_TUNNEL_V6=on_vpn_v6
NETWORK_TUNNEL_V6=on_vpn_v6

#OPENVPN_CONFIG_BASEDIR=/var/etc/openvpn #Variable sollte aus on-openvpn bekannt sein
SERVICE_NAME=gw_openvpn_v6_fd32_d8d3_87da__245_1700_udp
SERVICE_TYPE=gw
REMOTE_ADDR_V6=fd32:d8d3:87da::245
REMOTE_ADDR_V4=192.168.0.245
REMOTE_PORT=1700

MIG_OPENVPN_V6_CONFIG_TEMPLATE_FILE=/usr/share/opennet/openvpn-v6-mig.template
PID_FILE=/var/run/${SERVICE_NAME}.pid
#wir legen die Datei direkt auf dem Flash Speicher ab damit sie nach dem Reboot weiter vorhanden ist
OPENVPN_V6_CONFIG_BASEDIR=/etc/openvpn


configure_tunnel_v6_network() {
	local uci_prefix=network.$NETWORK_TUNNEL_V6

	# Abbruch falls das Netzwerk schon vorhanden ist
	[ -n "$(uci_get "$uci_prefix")" ] && return

	# add new network to configuration (to be recognized by olsrd)
	uci set "${uci_prefix}=interface"
	uci set "${uci_prefix}.proto=dhcpv6"
	uci set "${uci_prefix}.ifname=tap-on-user-v6"
	uci set "${uci_prefix}.reqprefix=auto"
	uci set "${uci_prefix}.reqaddress=try"

	apply_changes network
}


delete_tunnel_v6_network() {
	local uci_prefix=network.$NETWORK_TUNNEL_V6
	uci delete "${uci_prefix}"
	apply_changes network
}


configure_tunnel_v6_firewall() {
	local was_changed=0
	local uci_prefix
	uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_TUNNEL_V6")

	# Zone erzeugen, falls sie noch nicht vorhanden ist
	if [ -z "$(uci_get "$uci_prefix")" ]; then
		# Zone fuer ausgehenden Verkehr definieren
		uci_prefix=firewall.$(uci add firewall zone)
		uci set "${uci_prefix}.name=$ZONE_TUNNEL_V6"
		uci add_list "${uci_prefix}.network=$NETWORK_TUNNEL_V6"
		uci set "${uci_prefix}.forward=REJECT"
		uci set "${uci_prefix}.input=REJECT"
		uci set "${uci_prefix}.output=ACCEPT"
		was_changed=1
	fi
	create_uci_section_if_missing firewall forwarding \
			"src=$ZONE_LOCAL" "dest=$ZONE_TUNNEL_V6" \
		&& was_changed=1
	create_uci_section_if_missing firewall rule \
			"src=$ZONE_TUNNEL_V6" "proto=udp" "family=ipv6" "dest_port=546" "target=ACCEPT" "name=on-user-dhcpv6" \
		&& was_changed=1
	create_uci_section_if_missing firewall rule \
			"src=$ZONE_TUNNEL_V6" "proto=icmp" "family=ipv6" "target=ACCEPT" "name=on-user-icmpv6" \
		&& was_changed=1
	[ "$was_changed" = "0" ] && return 0
	apply_changes firewall
}


delete_tunnel_v6_firewall() {
	uci_prefix=$(find_first_uci_section firewall zone "name=$ZONE_TUNNEL_V6")
	uci delete "${uci_prefix}"
	for uci_prefix in $(find_all_uci_sections "firewall" "rule" "src=$ZONE_TUNNEL_V6"); do
		uci_delete "$uci_prefix"
	done
	for uci_prefix in $(find_all_uci_sections "firewall" "forwarding" "dest=$ZONE_TUNNEL_V6"); do
		uci_delete "$uci_prefix"
	done

	apply_changes firewall
}


enable_openvpn_v6_service() {
	trap 'error_trap enable_openvpn_v6_service "$*"' EXIT
	local service_name=$SERVICE_NAME
	local config_file="$OPENVPN_V6_CONFIG_BASEDIR/${service_name}.conf"
	local uci_prefix="openvpn.$service_name"

	mkdir -p "$OPENVPN_V6_CONFIG_BASEDIR"
	
	# zuvor ankuendigen, dass zukuenftig diese uci-Konfiguration an dem Dienst haengt
	service_add_uci_dependency "$service_name" "$uci_prefix"
	# lege die uci-Konfiguration an und aktiviere sie
	uci set "${uci_prefix}=openvpn"
	uci set "${uci_prefix}.enabled=1"
	uci set "${uci_prefix}.config=$config_file"
	apply_changes openvpn
}

delete_openvpn_v6_service() {
	local service_name=$SERVICE_NAME
	local uci_prefix="openvpn.$service_name"
	local config_file="$OPENVPN_V6_CONFIG_BASEDIR/${service_name}.conf"
	uci delete "${uci_prefix}"
	apply_changes openvpn

	rm "$config_file"
	# loesche Verzeichnis wenn es leer ist
	rmdir --ignore-fail-on-non-empty "$OPENVPN_V6_CONFIG_BASEDIR"
}

disable_openvpn_v6_service() {
	trap 'error_trap disable_openvpn_v6_service "$*"' EXIT
	local service_name=$SERVICE_NAME
	disable_openvpn_service "$service_name"
}


## liefere openvpn-Konfiguration eines Dienstes zurück
## param: 'v6' oder 'v4' - abhängig davon wird der OpenVPN Server mit IPv6 oder IPv4 angesprochen
##        wird kein Wert angegeben, wird automatisch die IPv6 Adresse genommen
get_openvpn_v6_config() {
	trap 'error_trap get_openvpn_v6_config "$*"' EXIT
	local ip_version="$1"
	local service_name=$SERVICE_NAME
	local template_file=$MIG_OPENVPN_V6_CONFIG_TEMPLATE_FILE
	if [ -n "$ip_version" ] && [ "$ip_version" = "v4" ]; then
		echo "remote $REMOTE_ADDR_V4 $REMOTE_PORT"
		echo "proto udp"
	else
		echo "remote $REMOTE_ADDR_V6 $REMOTE_PORT"
		echo "proto udp6"
	fi
	cat "$template_file"
	# sicherstellen, dass die Konfigurationsdatei mit einem Zeilenumbruch endet (fuer "echo >> ...")
	echo
}


## Schreibe eine openvpn-Konfigurationsdatei.
update_vpn_v6_config() {
	trap 'error_trap update_vpn_v6_config "$*"' EXIT
	local service_name="$SERVICE_NAME"
	local config_file="$OPENVPN_V6_CONFIG_BASEDIR/${service_name}.conf"
	service_add_file_dependency "$service_name" "$config_file"
	# Konfigurationsdatei neu schreiben
	mkdir -p "$(dirname "$config_file")"
	get_openvpn_v6_config "v6" >"$config_file"
}


## wenn keine IPv6 Verbindung zum OpenVPN Server moeglich ist, muss sich per IPv4 verbunden werden
connect_vpn_v6_server_via_v4() {
	trap 'error_trap connect_vpn_v6_server_via_v4 "$*"' EXIT
	local service_name="$SERVICE_NAME"
	#TODO hier haben wir jetzt einen Dateinamen mit IPv6 Adressen im Namen aber IPv4 Adresse in der Datei. Verbessern.
	local config_file="$OPENVPN_V6_CONFIG_BASEDIR/${service_name}.conf"
	#ersetze remote addr in config Datei
	get_openvpn_v6_config "v4" >"$config_file"
}
