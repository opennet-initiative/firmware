#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


is_olsrd_running() {
	[ -n "$(pidof olsrd)" ] && return 0
	trap "" $GUARD_TRAPS && return 1
}


# Ein seltsamer Bug fuehrt gelegentlich dazu, dass die Routen-Liste von olsrd
# leer ist (echo /routes | nc localhost 2006 | grep -q "^[0-9]").



# Ist OLSR zwischenzeitlich abgestuerzt?
if is_olsrd_running; then
	echo /routes | nc localhost 2006 | grep -q "^[0-9]" && exit 0
	# Topologie ebenfalls leer -> das ist ok (kein Netz)
	echo /topology | nc localhost 2006 | grep -q "^[0-9]" || exit 0
	# es gibt also Topologie-Informationen, jedoch keine Routen -> ein Bug
	/etc/init.d/olsrd restart >/dev/null || true
else
	/etc/init.d/olsrd start >/dev/null || true
fi

# Effekt des Restarts pruefen und protokollieren
sleep 1
is_olsrd_running || { msg_info "olsrd restart failed"; trap "" $GUARD_TRAPS && exit 1; }
sleep 1
is_olsrd_running && add_banner_event "olsrd restart"
exit 0

