configure_onitest_node() {
	# read node configuration from a config file (e.g. /etc/onitest.conf) and configure all opennet interfaces
	local config=$1

	# enable ssh access (usually manual password change is required before)
	uci delete "dropbear.@dropbear[0].RootPasswordAuth"

	# the following setting contains a comma-separated list of interface configurations
	# INTERFACE_UCI IFNAME IPADDR
	local OLSR_INTERFACES=

	# the following setting may contain an interface configuration
	# IFNAME IPADDR NETMASK
	local LAN_INTERFACE=

	# the following setting may contain an interface configuration
	# INTERFACE
	local WAN_INTERFACE=

	# read config file
	. "$config"

	# disable wireless interfaces
	disable_interface on_wifi_0
	disable_interface on_wifi_1
	disable_wifi

	disable_interface lan
	test -n "$LAN_INTERFACE" && echo "$LAN_INTERFACE" | while read ifname ipaddr netmask; do
		uci set network.lan.proto=static
		uci set network.lan.ifname=$ifname
		uci set network.lan.ipaddr=$ipaddr
		uci set network.lan.netmask=$netmask
		# only one interface is allowed
		break
	 done

	if test -n "$WAN_INTERFACE"; then
	       uci set network.wan.proto=dhcp
	       uci set "network.wan.ifname=$WAN_INTERFACE"
	       uci set network.wan.defaultroute=1
	       uci set network.wan.peerdns=1
	 fi

	local main_ip=
	local olsr_zone=
	lines=$(echo "$OLSR_INTERFACES" | tr "," "\n")
	while read interface ifname ipaddr; do
		test -z "$interface" && continue
		test -z "$main_ip" && main_ip=$ipaddr
		configure_oni_interface "$interface" "$ifname" "$ipaddr"
		olsr_zone="$olsr_zone $interface"
         done << EOF
$lines
EOF

	# enable internet sharing
	test -e /etc/openvpn/opennet_ugw/on_ugws.crt && uci set on-usergw.ugw_sharing.shareInternet=on

	# set on-core opennet id
	local opennet_id=$(echo "$main_ip" | cut -f 3-4 -d .)
	uci_set_on_id "$opennet_id"

	# configure olsr
	uci_configure_opennet_zone "$main_ip" $olsr_zone

	uci_commit_all
}

uci_force_delete() {
	uci delete "$1" 2>/dev/null || true
}

onitest_is_configured() {
	uci show on-core | grep -q settings.on_id && return 0
	return 1
}

disable_interface() {
	local interface=$1
	uci_force_delete "network.${interface}"
	uci set network.${interface}=interface
	uci set network.${interface}.ifname=none
	uci set network.${interface}.proto=none
}

configure_oni_interface() {
	local interface=$1
	local ifname=$2
	local ipaddr=$3
	uci_force_delete "network.${interface}"
	uci set network.${interface}=interface
	uci set network.${interface}.ifname=$ifname
	uci set network.${interface}.proto=static
	uci set network.${interface}.ipaddr=$ipaddr
	uci set network.${interface}.netmask=255.255.0.0
}

uci_set_on_id() {
	local last_octets=$1
	local hostname=$(echo "$last_octets" | tr "." "-")
	uci set "on-core.settings.on_id=$last_octets"
	uci set "system.@system[0].hostname=AP-$hostname"
}

disable_wifi() {
	while uci delete "wireless.@wifi-iface[0]" 2>/dev/null; do true; done
}

uci_commit_all() {
	for setting in network wireless olsrd firewall on-core system; do
		uci commit "$setting"
	 done
}

uci_configure_opennet_zone() {
	local main_ip=$1
	shift
	local interfaces=$@
	uci set "olsrd.@olsrd[0].MainIp=$main_ip"
	uci set "olsrd.@Interface[0].interface=$interfaces"
	uci set "firewall.zone_opennet.network=$interfaces"
}

