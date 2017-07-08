#!/bin/sh


# shellcheck disable=SC1090
. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"



olsr_service_action() {
	local action="$1"
	update_olsr_interfaces
	/etc/init.d/olsrd "$action" >/dev/null || true
}


is_olsrd_running() {
	local pid_file
	pid_file=$(grep "^PID=" /etc/init.d/olsrd | cut -f 2- -d =)
	if [ -z "$pid_file" ]; then
		# Falls wir keine gueltige PID-Datei finden, dann pruefen wir lediglich,
		# ob irgendein olsrd laeuft - dies ist natuerlich nicht sehr zuverlässig.
		msg_error "Failed to find PID file location for olsrd"
		pidof olsrd >/dev/null && return 0
		return 1
	else
		system_service_check /usr/sbin/olsrd "$pid_file" && return 0
		return 1
	fi
}


# Ein seltsamer Bug fuehrt gelegentlich dazu, dass die Routen-Liste von olsrd leer ist
# (echo /routes | nc localhost 2006 | grep -q "^[0-9]"), obwohl laut OLSR-Topology Routen bekannt
# sind.
is_routing_table_out_of_sync() {
	# Falls Routen vorhanden sind, ist der Fehler nicht aufgetreten.
	[ -n "$(ip route show table "$ROUTING_TABLE_MESH")" ] && return 1
	# Die Abwesenheit von Routen ist akzeptabel, sofern OLSR noch keine Topologie bekannt ist
	# (z.B. nach dem Booten oder wegen fehlendem Nachbarn).
	[ -z "$(request_olsrd_txtinfo top)" ] && return 1
	# es gibt also Topologie-Informationen, jedoch keine Routen -> ein Bug
	return 0
}


# Sind andere olsrd-Prozesse aktiv, deren PID nicht in der PID-Datei stehen und somit unkontrolliert
# weiterlaufen und den Port blockieren?
are_multiple_olsrd_processes_alive() {
	local process_count
	process_count=$(pidof olsrd | wc -w)
	[ "$process_count" -gt 1 ] && return 0
	return 1
}


is_olsrd_txtinfo_empty() {
	[ -z "$(request_olsrd_txtinfo all)" ] && return 0
	return 1
}


if ! is_olsrd_running; then
	# the service is not running
	olsr_service_action restart
	add_banner_event "olsrd restart (missing process)"
elif  is_olsrd_txtinfo_empty; then
	# The process is alive, but does not respond to txtinfo requests.
	# These failures happened in 2017 with OLSR v0.9.5.
	olsr_service_action restart
	add_banner_event "olsrd restart (empty txtinfo)"
elif  is_routing_table_out_of_sync; then
	# The routing table does not reflect the content of OLSRD's topology information.
	olsr_service_action restart
	add_banner_event "olsrd restart (routes out of sync)"
elif are_multiple_olsrd_processes_alive; then
	# Wir toeten mutigerweise alle olsrd-Prozesse und hoffen, dass die anderen olsrd-Prozesse
	# nicht zu einem anderen Netz gehörten.
	killall olsrd
	sleep 1
	olsr_service_action restart
	add_banner_event "olsrd restart (stale processes)"
else
	# no problems
	true
fi
exit 0
