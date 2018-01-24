#!/bin/sh


OLSRD_READY_DELAY=5


# shellcheck disable=SC1090
. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"



olsr_service_action() {
	local action="$1"
	update_olsr_interfaces
	/etc/init.d/olsrd "$action" >/dev/null || true
	# Warte ein wenig, bis olsrd seinen internen Status aktualisiert hat.
	# Andernfalls schlagen vielleicht anschließende Prüfungen fehl.
	sleep "$OLSRD_READY_DELAY"
}


is_olsrd_running() {
	local pid_file
	pid_file=$(grep "^PID=" /etc/init.d/olsrd | cut -f 2- -d =)
	if [ -z "$pid_file" ]; then
		# Falls wir keine gueltige PID-Datei finden, dann pruefen wir lediglich,
		# ob irgendein olsrd laeuft - dies ist natuerlich nicht sehr zuverlässig.
		msg_error "Failed to find PID file location for olsrd"
		pgrep '/olsrd$' >/dev/null && return 0
		return 1
	else
		if system_service_check /usr/sbin/olsrd "$pid_file"; then
			return 0
		else
			# Falls die PID-Datei eine falsche PID enthält, dann wird
			# "/etc/init.d/olsrd restart" dauerhaft fehlschlagen, da es nie den alten
			# Prozess tötet. Der restart wird also immer nur in einem Fehler beim
			# Port-Bind enden.
			# Daher töten wir den Prozess manuell. Anschließend klappt der
			# Prozess-Start und eine valide PID wird geschrieben.
			killall olsrd || true
			return 1
		fi
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
	process_count=$(pgrep '/olsrd$' | wc -w)
	[ "$process_count" -gt 1 ] && return 0
	return 1
}


# Pruefe, ob der olsrd-Prozess lebt und Anfragen beantwortet.
is_olsrd_txtinfo_empty() {
	[ -n "$(request_olsrd_txtinfo con)" ] && return 1
	# Da es gelegentlich Fehlerkennungen von Ausfällen gab, prüfen wir im Fehlerfall zweimal.
	sleep 3
	[ -n "$(request_olsrd_txtinfo con)" ] && return 1
	return 0
}


# Warte ein wenig, um sicherzugehen, dass olsrd nicht gerade frisch gestartet wurde.
sleep "$OLSRD_READY_DELAY"

if ! is_olsrd_running; then
	# the service is not running
	olsr_service_action restart
	add_banner_event "olsrd restart (missing process)"
elif is_olsrd_txtinfo_empty; then
	# The process is alive, but does not respond to txtinfo requests.
	# These failures happened in 2017 with OLSR v0.9.5.
	olsr_service_action restart
	add_banner_event "olsrd restart (empty txtinfo)"
elif is_routing_table_out_of_sync; then
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
