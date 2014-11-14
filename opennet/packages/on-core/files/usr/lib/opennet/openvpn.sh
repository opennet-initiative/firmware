# liefere das UCI-Praefix fuer eine OpenVPN-Instanz zurueck, die zu dem angegebenen Service gehoert.
get_openvpn_service_uci_prefix() {
	local service_name="$1"
	shift
	find_first_uci_section on-core services "name=$name" "$@"
}


# Schreibe eine openvpn-Konfigurationsdatei.
# Parameter: der Service-Name
# Parameter: true|false
#   true: falls der Service-"Host" (typischerweise der Sender der olsr-nameservice-Information) verwendet werden soll
#   false: falls die "hostname"-Information aus den Service-Details verwendet werden soll
#          (z.B. fuer UserGateway-Server mit oeffentlichen IPs)
enable_openvpn_service() {
	local service_name="$1"
	local use_sender="$2"
	local uci_prefix
	local config_file=$(get_service_value "$service_name" "config_file")
	# Konfigurationsdatei neu schreiben
	mkdir -p "$(dirname "$config_file")"
	service_add_file_dependency "$service_name" "$config_file"
	get_openvpn_config "$service_name" "$use_sender" >"$config_file"
	# uci-Konfiguration setzen
	uci_prefix="openvpn.$service_name"
	# zuvor ankuendigen, dass zukuenftig diese uci-Konfiguration an dem Dienst haengt
	service_add_uci_dependency "$service_name" "$uci_prefix"
	# lege die uci-Konfiguration an und aktiviere sie
	uci set "${uci_prefix}=openvpn"
	uci set "${uci_prefix}.enabled=1"
	uci set "${uci_prefix}.config=$config_file"
	apply_changes openvpn
	apply_changes on-core
}


disable_openvpn_service() {
	local service_name="$1"
	local config_file=$(get_service_value "$service_name" "config_file")
	rm -f "$config_file"
	uci_delete "openvpn.$service_name"
	cleanup_service_dependencies "$service_name"
	apply_changes openvpn
}


is_openvpn_service_active() {
	local service_name="$1"
	# wir pruefen lediglich, ob ein VPN-Eintrag existiert
	[ -n "$(uci_get "openvpn.$service_name")" ] && return 0
	return 1
}


get_openvpn_config() {
	local service_name="$1"
	local use_sender="$2"
	local remote
	if uci_is_true "$use_sender"; then
		remote=$(get_service_value "$service_name" "host")
	else
		remote=$(get_service_value "$service_name" "details" | get_from_key_value_list "hostname")
	fi
	local port=$(get_service_value "$service_name" "port")
	local protocol=$(get_service_value "$service_name" "protocol")
	[ "$protocol" = "tcp" ] && protocol=tcp-client
	local template_file=$(get_service_value "$service_name" "template_file")
	local pid_file=$(get_service_value "$service_name" "pid_file")
	# schreibe die Konfigurationsdatei
	echo "# automatically generated by $0"
	echo "remote $remote $port"
	echo "proto $protocol"
	echo "writepid $pid_file"
	cat "$template_file"
}


# pruefe einen VPN-Verbindungsaufbau
# Parameter:
#   Service-Name
# optionale zusaetzliche Parameter:
#   Schluesseldatei: z.B. $VPN_DIR/on_aps.key
#   Zertifikatsdatei: z.B. $VPN_DIR/on_aps.crt
#   CA-Zertifikatsdatei: z.B. $VPN_DIR/opennet-ca.crt
# Ergebnis: Exitcode=0 bei Erfolg
verify_vpn_connection() {
	trap "error_trap verify_vpn_connection $*" $GUARD_TRAPS
	local service_name="$1"
	local use_sender="$2"
	local key_file=${3:-}
	local cert_file=${4:-}
	local ca_file=${5:-}
	local temp_config_file="/tmp/vpn_test_${service_name}-$$.conf"
	local wan_dev
	local openvpn_opts
	local hostname
	local status_output

	get_openvpn_config "$service_name" "$use_sender" >"$temp_config_file"
	msg_debug "start vpn test of <$temp_config_file>"

	# check if it is possible to open tunnel to the gateway (10 sec. maximum)
	# Assembling openvpn parameters ...
	openvpn_opts="--dev null"
	
	# some openvpn options:
	#   ifconfig-noexec: we do not want to configure a device (and mess up routing tables)
	#   route-nopull: ignore any advertised routes - we do not want to redirect traffic
	openvpn_opts="$openvpn_opts --ifconfig-noexec --route-nopull"

	# some timing options:
	#   inactive: close connection after 15s without traffic
	#   ping-exit: close connection after 15s without a ping from the other side (which is probably disabled)
	openvpn_opts="$openvpn_opts --inactive 15 1000000 --ping-exit 15"

	# other options:
	#   verb: verbose level 3 is required for the TLS messages
	#   nice: testing is not too important
	#   resolv-retry: fuer ipv4/ipv6-Tests sollten wir mehrere Versuche zulassen
	openvpn_opts="$openvpn_opts --verb 3 --nice 3 --resolv-retry 3"

	# wohl nur fuer tcp-Verbindungen
	#   connect-retry: Sekunden Wartezeit zwischen Versuchen
	#   connect-timeout: Dauer eines Versuchs
	#   connect-retry-max: Anzahl moeglicher Wiederholungen
	openvpn_opts="$openvpn_opts connect-retry=1 connect-timeout=15 connect-retry-max=1"

	# prevent a real connection (otherwise we may break our current vpn tunnel):
	#   tls-verify: force a tls handshake failure
	#   tls-exit: stop immediately after tls handshake failure
	#   ns-cert-type: enforce a connection against a server certificate (instead of peer-to-peer)
	openvpn_opts="$openvpn_opts --tls-verify /bin/false --tls-exit --ns-cert-type server"

	# nie die echte PID-Datei ueberschreiben (falls ein Prozess laeuft)
	sed -i "/^writepid/d" "$temp_config_file"

	[ -n "$key_file" ] && \
		openvpn_opts="$openvpn_opts --key $key_file" && \
		sed -i "/^key/d" "$temp_config_file"
	[ -n "$cert_file" ] && \
		openvpn_opts="$openvpn_opts --cert $cert_file" && \
		sed -i "/^cert/d" "$temp_config_file"
	[ -n "$ca_file" ] && \
		openvpn_opts="$openvpn_opts --ca $ca_file" && \
		sed -i "/^ca/d" "$temp_config_file"

	# check if the output contains a magic line
	status_output=$(openvpn --config "$temp_config_file" $openvpn_opts || true)
	rm -f "$temp_config_file"
	echo "$status_output" | grep -q "Initial packet" && return 0
	trap "" $GUARD_TRAPS && return 1
}

