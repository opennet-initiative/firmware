#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

# Ist OLSR zwischenzeitlich abgestuerzt?
if [ -z "$(pidof olsrd)" ]; then
    /etc/init.d/olsrd start >/dev/null || true 
    [ -z "$(pidof olsrd)" ] && msg_info "olsrd restart failed"; trap "" $GUARD_TRAPS && exit 1
    sleep 1
    [ -n "$(pidof olsrd)" ] && add_banner_event "olsrd restart"
fi

