#!/bin/sh

set -eu

BASE_DIR=$(cd "$(dirname "$0")/.."; pwd)
CONTROL_BIN="$BASE_DIR/bin/te-control.sh"
VERSION_STABLE="0.4-5"
MGMT_NETWORK_PREFIX="172.16.137"


ACTION=help
test $# -gt 0 && ACTION=$1 && shift

# get random MAC address
# echo 'import random; print ":".join(["%02X" % random.randint(0, 255) for index in range(6)])' | python


case "$ACTION" in
	start)
		uplink="$(ip route get 1.1.1.1 | head -1 | sed 's/^.* dev \([^ ]\+\) .*/\1/')"
		if test -z "$uplink"; then
			echo >&2 "WARNUNG: es wurde keine default-Route gefunden - hoffen wir das Beste ..."
			uplink=eth0
		 fi
		echo "Ermitteltes Gateway-Interface: $uplink"
		echo "Initialisiere die Netzwerkschnittstellen ..."
		"$CONTROL_BIN" start-net olsr1 switch
		"$CONTROL_BIN" start-net olsr2 switch
		"$CONTROL_BIN" start-net net_user switch
		"$CONTROL_BIN" start-net net_wifidog switch
		"$CONTROL_BIN" start-net uplink switch
		"$CONTROL_BIN" start-net mgmt virtual "$MGMT_NETWORK_PREFIX.1" 255.255.255.0
		"$CONTROL_BIN" start-net uplink capture "$uplink"
		echo "Starte die Hosts ..."
		"$CONTROL_BIN" start-host ap1.201 "$VERSION_STABLE" x86 \
				olsr1 "DD:4B:E3:A7:98:F9" \
				uplink "46:98:2C:8A:46:50" \
				net_wifidog "DF:37:98:BC:AA:21" \
				mgmt "B6:78:93:BC:21:33"
		"$CONTROL_BIN" start-host ap1.202 "$VERSION_STABLE" x86 \
				olsr1 "5D:6E:A9:9E:AE:6F" \
				olsr2 "FC:EF:67:F8:62:B3" \
				mgmt "B6:78:93:BC:21:44"
		"$CONTROL_BIN" start-host ap1.203 "$VERSION_STABLE" x86 \
				olsr2 "23:55:74:4C:5B:C9" \
				net_user "55:16:90:6D:7A:83" \
				mgmt "B6:78:93:BC:21:55"
		"$CONTROL_BIN" start-host client_user "$VERSION_STABLE" x86 \
				net_user "DF:CB:6B:80:39:89" \
				mgmt "B6:78:93:BC:21:66"
		"$CONTROL_BIN" start-host client_wifidog "$VERSION_STABLE" x86 \
				net_wifidog "A1:D8:AC:59:91:8D" \
				mgmt "B6:78:93:BC:21:77"
		"$0" configure
		;;
	configure)
		# value determined by testing - increase in case of failures
		min_uptime=40
		echo "Konfiguriere die Verwaltungsschnittstelle der Hosts ..."
		"$CONTROL_BIN" wait-host-boot ap1.201 "$min_uptime"
		"$CONTROL_BIN" host-configure-management ap1.201 eth3 "$MGMT_NETWORK_PREFIX.11" 255.255.255.0
		"$CONTROL_BIN" wait-host-boot ap1.202 "$min_uptime"
		"$CONTROL_BIN" host-configure-management ap1.202 eth2 "$MGMT_NETWORK_PREFIX.12" 255.255.255.0
		"$CONTROL_BIN" wait-host-boot ap1.203 "$min_uptime"
		"$CONTROL_BIN" host-configure-management ap1.203 eth2 "$MGMT_NETWORK_PREFIX.13" 255.255.255.0
		"$CONTROL_BIN" wait-host-boot client_user "$min_uptime"
		"$CONTROL_BIN" host-configure-management client_user eth1 "$MGMT_NETWORK_PREFIX.14" 255.255.255.0
		"$CONTROL_BIN" wait-host-boot client_wifidog "$min_uptime"
		"$CONTROL_BIN" host-configure-management client_wifidog eth1 "$MGMT_NETWORK_PREFIX.15" 255.255.255.0
		# configure hosts
		#config_dir="$BASE_DIR/setup.d"
		#for name in ap1.201 ap1.202 ap1.203 client_user client_wifidog; do
		#	echo "Configuring $name ..."
		#	"$CONTROL_BIN" apply-config "$name" "$config_dir/_default"
		#	"$CONTROL_BIN" apply-config "$name" "$config_dir/$name"
		#	"$CONTROL_BIN" command "$name" reboot
		# done
		;;
	stop)
		echo "Stoppe die Hosts ..."
		for name in ap1.201 ap1.202 ap1.203 client_user client_wifidog; do
			"$CONTROL_BIN" stop-host "$name"
		 done
		echo "Entferne die Netzwerkschnittstellen ..."
		for net in olsr1 olsr2 net_user net_wifidog uplink mgmt; do
			"$CONTROL_BIN" stop-net "$net"
		 done
		;;
	status)
		"$CONTROL_BIN" status
		;;
	restart)
		"$0" stop
		"$0" start
		;;
	help|--help)
		echo "Syntax $(basename "$0") {start|stop|restart|help}"
		echo
		;;
	*)
		"$0" help >&2
		exit 1
		;;
 esac

exit 0

