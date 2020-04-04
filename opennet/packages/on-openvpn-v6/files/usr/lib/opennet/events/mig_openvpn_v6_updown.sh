#!/bin/sh
#
# Opennet Firmware
#

# shellcheck source=opennet/packages/on-core/files/usr/lib/opennet/on-helper.sh
. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

# die folgenden Variablen stammen aus der OpenVPN-Umgebung
script_type=${script_type:-}
route_vpn_gateway=${route_vpn_gateway:-}
route_network_1=${route_network_1:-}
# use either IPv4 or IPv6 Address of peer/server
trusted_ip=${trusted_ip:-${trusted_ip6:-}}


# Sonder-Aktionen für mig-Verbindungen
case "$script_type" in
	up)
		#restart neighbor discovery proxy because now interface is available
		/etc/init.d/ndppd restart
		;;
	down)
		#stop ndp proxy because interface is down
		/etc/init.d/ndppd stop
		;;
esac 2>&1 | logger -t mig-v6-updown

exit 0
