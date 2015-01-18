#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


START_DELAY=8


is_olsrd_running() {
	trap "" $GUARD_TRAPS
	system_service_check /usr/sbin/olsrd /var/run/olsrd.pid
}


# Ein seltsamer Bug fuehrt gelegentlich dazu, dass die Routen-Liste von olsrd
# leer ist (echo /routes | nc localhost 2006 | grep -q "^[0-9]").
# Ist OLSR zwischenzeitlich abgestuerzt?
check_for_empty_routing_table() {
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

