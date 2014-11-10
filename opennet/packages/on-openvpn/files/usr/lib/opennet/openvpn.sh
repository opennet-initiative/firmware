# Parse die Liste der via olsrd-nameservice announcierten ugw-Dienste.
# Falls keine UGW-Dienste gefunden werden, bzw. vorher konfiguriert waren, werden die Standard-Opennet-Server eingetragen.
# Speichere diese Liste als on-openvpn@server-Liste.
# Anschliessend werden eventuell Dienste (z.B. openvpn) neu konfiguriert.
update_mig_services() {
	trap "error_trap update_mig_services $*" $GUARD_TRAPS
	local scheme
	local ipaddr
	local port
	local proto
	local details
	local hostname
	local service_description
	(get_olsr_services gw; get_olsr_services ugw) | cut -f 1,2,3,5,7 | while read scheme ipaddr port proto details; do
		# Firmware-Versionen bis v0.4-5 veroeffentlichten folgendes Format:
		#    http://192.168.0.40:8080|tcp|ugw upload:50 download:15300 ping:23
		[ "$scheme" = "http" -a "$port" = "8080" ] && scheme=openvpn && port=1600
		service_description="$scheme://$ipaddr:$port ($proto) $details"
		if [ "$scheme" = "openvpn" ]; then
			add_openvpn_mig_service "$ipaddr" "$port" "$proto" "$details"
		else
			msg_info "update_ugw_services: unbekannter uplink-Service: $service_description"
		fi
	done
	# Portweiterleitungen aktivieren
	# kein "apply_changes" - andernfalls koennten Loops entstehen
	uci commit on-openvpn
}


# Erzeuge einen neuen mig-Service.
# Ignoriere doppelte Eintraege.
# Es wird _kein_ "uci commit" durchgefuehrt.
# TODO: nahezu identisch mit add_openvpn_ugw_service
add_openvpn_mig_service() {
	local ipaddr=$1
	local port=$2
	local proto=$3
	local details=$4
	local uci_prefix
	local template
	local config_dir
	local config_file
	local config_name
	local safe_hostname
	local config_prefix
	if [ "$protocol" = "udp" ]; then
		template=/usr/share/opennet/openvpn-mig-udp.template
		config_dir=$OPENVPN_CONFIG_BASEDIR
		config_prefix=on_aps
	else
		msg_info "failed to add openvpn service for Mesh-Internet-Gateway due to invalid protocol ($protocol)"
		return 1
	fi
	[ "$protocol" != "tcp" -a "$protocol" != "udp" ] && \
		msg_info "failed to set up openvpn settings for invalid protocol ($protocol)" && return 1
	# config-Schluessel erstellen
	safe_hostname=$(echo "$hostname" | sed 's/[^a-zA-Z0-9]/_/g')
	config_name=openvpn_${config_prefix}_${safe_hostname}_${protocol}_${port}
	config_file=$config_dir/${config_name}.conf
	uci_prefix=$(find_first_uci_section on-usergw server "type=openvpn" "hostname=$ipaddr" "port=$port" "protocol=$proto")
	[ -z "$uci_prefix" ] && on-openvpn$(uci add on-openvpn server)
	uci set "${uci_prefix}.details="
	# neuer Eintrag? Dann moege er aktiv sein.
	[ -z "$(uci_get "${uci_prefix}.enable")" ] && uci set "${uci_prefix}.enable=1"
	uci set "${uci_prefix}.name=$config_name"
	uci set "${uci_prefix}.type=openvpn"
	uci set "${uci_prefix}.hostname=$ipaddr"
	uci set "${uci_prefix}.template=$template"
	uci set "${uci_prefix}.config_file=$config_file"
	uci set "${uci_prefix}.port=$port"
	uci set "${uci_prefix}.protocol=$protocol"
	# Zeitstempel auffrischen
	set_gateway_value "$config_name" last_seen "$(date +%s)"
	# Details koennen sich haeufig aendern (z.B. Geschwindigkeiten)
	set_gateway_value "$config_name" details "$details"
}

