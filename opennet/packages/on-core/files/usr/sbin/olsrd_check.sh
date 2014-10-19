#!/bin/sh

. "${IPKG_INSTROOT:-}/usr/bin/on-helper.sh"

# Ist OLSR zwischenzeitlich abgestuerzt?
if [ -z "$(pidof olsrd)" ]; then
    /etc/init.d/olsrd start >/dev/null
    sleep 1
    [ -n "$(pidof olsrd)" ] && add_banner_event "olsrd restart"
fi

