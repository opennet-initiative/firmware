MIG_VPN_DIR=/etc/openvpn/opennet_user
MIG_TEST_VPN_DIR=/etc/openvpn/opennet_vpntest


# Erzeuge oder aktualisiere einen mig-Service.
# Ignoriere doppelte Eintraege.
# Anschliessend muss "on-core" comitted werden.
update_mig_service() {
	local service_name="$1"
	local template_file=/usr/share/opennet/openvpn-mig.template
	local config_file="$OPENVPN_CONFIG_BASEDIR/${service_name}.conf"
	local pid_file="/var/run/${service_name}.pid"
	set_service_value "$service_name" "template_file" "$template_file"
	set_service_value "$service_name" "config_file" "$config_file"
	set_service_value "$service_name" "pid_file" "$pid_file"
}


# Pruefe, ob ein Verbindungsaufbau mit einem openvpn-Service moeglich ist.
# Parameter: Service-Name
# Resultat: exitcode=0 falls der Test erfolgreich war
test_mig_connection()
{
	trap "error_trap test_mig_connection $*" $GUARD_TRAPS
	local service_name="$1"
	# sicherstellen, dass alle vpn-relevanten Einstellungen gesetzt wurden
	update_mig_service "$service_name"
	local host=$(get_service_value "$service_name" "host")
	local config_file=$(get_service_value "$service_name" "config_file")
	local timestamp=$(get_service_value "$service_name" "timestamp_connection_test")
	local recheck_age=$(get_on_openvpn_default vpn_recheck_age)
	local now=$(get_time_minute)
	local nonworking_timeout=$(get_on_openvpn_default vpn_nonworking_timeout)
	if [ -n "$timestamp" ] && is_timestamp_older_minutes "$timestamp" "$nonworking_timeout"; then
		# if there was no vpn-availability for a while (nonworking_timeout minutes), declare vpn-status as not working
		set_service_value "$service_name" "timestamp_connection_test" "$now"
		set_service_value "$service_name" "status" "n"
		trap "" $GUARD_TRAPS && return 1
	elif [ -z "$timestamp" ] || is_timestamp_older_minutes "$timestamp" "$recheck_age"; then
		if verify_vpn_connection "$service_name" "true" \
				"$MIG_TEST_VPN_DIR/on_aps.key" \
				"$MIG_TEST_VPN_DIR/on_aps.crt" \
				"$MIG_TEST_VPN_DIR/opennet-ca.crt"; then
			set_service_value "$service_name" "timestamp_connection_test" "$now"
			set_service_value "$service_name" "status" "y"
			msg_debug "vpn-availability of gw $host successfully tested"
			return 0
		else
			# "age" will grow until it exceeds "recheck_age + nonworking_timeout" -> no need to do anything now
			msg_debug "vpn test of $host failed"
			trap "" $GUARD_TRAPS && return 1
		fi
	elif uci_is_true "$(get_service_value "$service_name" "status")"; then
		msg_debug "vpn-availability of gw $host still valid"
		return 0
	else
		# gateway is currently known to be broken
		trap "" $GUARD_TRAPS && return 1
	fi
}


# aktiviere den uebergebenen Gateway
# Seiteneffekt: Beraeumung aller herumliegenden Konfigurationen von alten Verbindungen
select_mig_connection() {
	local wanted="$1"
	local one_service
	get_sorted_services gw ugw | while read one_service; do
		# loesche Flags fuer die Vorselektion
		set_service_value "$one_service" "switch_candidate_timestamp" ""
		[ "$one_service" = "$wanted" ] && enable_openvpn_service "$wanted" && continue
		is_openvpn_service_active "$one_service" && disable_openvpn_service "$one_service"
	done
}


find_and_select_best_gateway() {
	local service_name
	local host
	local last_gateway=
	local best_gateway=
	local last_priority
	local best_priority
	local switch_candidate_timestamp
	local now=$(get_time_minute)
	local bettergateway_timeout=$(get_on_openvpn_default vpn_bettergateway_timeout)
	# suche nach dem besten und dem bisher verwendeten Gateway
	# Ignoriere dabei alle nicht-verwendbaren Gateways.
	get_sorted_services gw ugw | filter_enabled_services | while read service_name; do
		host=$(get_service_value "$service_name" "host")
		uci_is_false "$(get_service_value "$service_name" "status")" && \
			msg_debug "$host did not pass the last test" && \
			continue
		# der Gateway ist ein valider Kandidat
		[ -z "$best_gateway" ] && best_gateway="$service_name"
		[ -z "$last_gateway" ] && is_openvpn_service_active "$service_name" && last_gateway="$service_name"
		# sind wir fertig?
		[ -n "$best_gateway" ] && [ -n "$last_gateway" ] && break
	done
	# gibt es einen "letzten" (und somit auch immer einen "besten")?
	if [ -n "$last_gateway" ]; then
		# falls der beste und der aktive Gateway gleich weit entfernt sind, bleiben wir beim bisher aktiven
		if [ "$best_gateway" != "$last_gateway" ]; then
			last_priority=$(get_service_priority "$last_gateway")
			best_priority=$(get_service_priority "$best_gateway")
			[ "$last_priority" -eq "$best_priority" ] && best_gateway="$last_gateway"
		fi
		# Haben wir einen besseren Kandidaten? Muessen wir den Wechselzaehler aktivieren?
		if [ "$best_gateway" != "$last_gateway" ]; then
			# Zaehle hoch bis 
			switch_candidate_timestamp=$(get_service_value "$one_service" "switch_candidate_timestamp" "$now")
			# noch nicht alt genug fuer den Wechsel?
			is_timestamp_older_minutes "$switch_candidate_timestamp" "$bettergateway_timeout" || \
				best_gateway="$last_gateway"
		fi
	fi
	# eventuell kann hier auch ein leerer String uebergeben werden - dann wird kein Gateway aktiviert (korrekt)
	select_mig_connection "$best_gateway"
}


# Liefere die aktiven VPN-Verbindungen (mit Mesh-Internet-Gateways) zurueck.
# Diese Funktion bracht recht viel Zeit.
get_active_mig_connections() {
	get_sorted_services gw ugw | while read one_service; do
		is_openvpn_service_active "$one_service" && echo "$one_service"
	done
}

