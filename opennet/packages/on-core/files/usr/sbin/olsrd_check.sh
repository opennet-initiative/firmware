#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


START_DELAY=8


is_olsrd_running() {
	trap "error_trap is_olsrd_running '$*'" $GUARD_TRAPS
	local pid_file=$(grep "^PID=" /etc/init.d/olsrd | cut -f 2- -d =)
	if [ -z "$pid_file" ]; then
		# Falls wir keine gueltige PID-Datei finden, dann pruefen wir lediglich,
		# ob irgendein olsrd laeuft - dies ist natuerlich nicht sehr zuverlässig.
		msg_info "ERROR: failed to find PID file location for olsrd"
		pidof olsrd >/dev/null && return 0 || true
	else
		system_service_check /usr/sbin/olsrd "$pid_file" && return 0 || true
	fi
	trap "" $GUARD_TRAPS && return 1
}


# Ein seltsamer Bug fuehrt gelegentlich dazu, dass die Routen-Liste von olsrd
# leer ist (echo /routes | nc localhost 2006 | grep -q "^[0-9]").
# Ist OLSR zwischenzeitlich abgestuerzt?
check_for_empty_routing_table() {
	trap "error_trap check_for_empty_routing_table '$*'" $GUARD_TRAPS
	if is_olsrd_running; then
		# Pruefe, ob Routen in der richtigen Routing-Tabelle stehen
		# (es gibt einen Bug, bei dem olsrd vergisst, die Routen zu konfigurieren)
		# Wir duerfen sofort mit Erfolg beenden, da es nix weiter zu tun gibt.
		ip route show table "$ROUTING_TABLE_MESH" | grep -q "^[0-9]" && exit 0
		# Topologie ebenfalls leer? Dann ist es ok (wir haben kein Netz).
		echo /topology | nc localhost 2006 | grep -q "^[0-9]" || exit 0
		# es gibt also Topologie-Informationen, jedoch keine Routen -> ein Bug
		/etc/init.d/olsrd restart >/dev/null || true
	else
		/etc/init.d/olsrd start >/dev/null || true
	fi
	# warte auf vollstaendigen Start (inkl. bind)
	sleep "$START_DELAY"
}


# Sind andere olsrd-Prozesse aktiv, deren PID nicht in der PID-Datei stehen und somit unkontrolliert
# weiterlaufen und den Port blockieren?
check_for_stale_olsrd_process() {
	trap "error_trap check_for_stale_olsrd_process '$*'" $GUARD_TRAPS
	if pidof olsrd >/dev/null; then
		# Wir toeten mutigerweise alle olsrd-Prozesse und hoffen, dass die anderen olsrd-Prozesse
		# nicht zu einem anderen Netz gehörten.
		killall olsrd || true
		sleep 1
		/etc/init.d/olsrd start >/dev/null || true
	else
		# einfach nochmal versuchen
		/etc/init.d/olsrd restart >/dev/null || true
	fi
	sleep "$START_DELAY"
}


check_for_empty_routing_table
is_olsrd_running && add_banner_event "olsrd restart" && exit 0
msg_info "olsrd restart failed (attempt #1)"

check_for_stale_olsrd_process
is_olsrd_running && add_banner_event "olsrd restart" && exit 0
msg_info "olsrd restart failed (attempt #2)"

exit 1

