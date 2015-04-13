#!/bin/sh


. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"


uci_prefix=$(nodogsplash_get_or_create_config)
if [ "$INTERFACE" = "$(uci_get "${uci_prefix}.network")" ]; then
	if [ "$ACTION" = "up" ]; then
		/etc/init.d/nodogsplash start
	elif [ "$ACTION" = "down" ]; then
		/etc/init.d/nodogsplash stop
	fi
fi

