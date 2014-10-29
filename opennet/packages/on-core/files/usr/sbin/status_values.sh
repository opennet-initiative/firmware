#!/bin/sh
#
# Opennet Firmware
# 
# Copyright 2010 Rene Ejury <opennet@absorb.it>
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 

. "${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh"

DATABASE_VERSION="0.2"          # we start with 0.2 to have space for the old firmware database, which is 0.1
DATABASE_FILE="/tmp/database"   # ".json" will be added if it is exported as JSON
EXPORT_JSON="1"                 # export as JSON-file, does not require sqlite3/libsqlite
                                # if you change this, ensure that sqlite3 is installed

create_database() {
  [ -f "$DATABASE_FILE" ] && return
  [ "$EXPORT_JSON" = "1" ] && return
  
  SQL_STRING="$SQL_STRING 
    CREATE TABLE nodes
    (originator text, mainip text, sys_ver text, sys_board text, sys_cpu text, sys_mem int, sys_uptime text,
    sys_load text, sys_free int, sys_watchdog bool, sys_os_type text,
    sys_os_name text, sys_os_rel text, sys_os_ver text, sys_os_arc text,
    sys_os_insttime int, on_core_ver text, on_core_insttime int, on_packages text,
    on_id text, on_olsrd_status text, on_olsrd_mainip text,
    on_wifidog_status bool, on_wifidog_id text, on_vpn_cn text, on_vpn_status bool,
    on_vpn_gw text, on_vpn_autosearch bool, on_vpn_sort text, on_vpn_gws text, on_vpn_blist text,
    on_ugw_status bool, on_ugw_enabled bool, on_ugw_possible bool, on_ugw_tunnel bool,
    on_ugw_connected text, on_ugw_presetips text, on_ugw_presetnames text,
    on_old_autoadapttxpwr text, on_old_remoteconf text,
    db_time text, db_epoch int, db_ver text, db_update int, CONSTRAINT key_nodes PRIMARY KEY (mainip) ON CONFLICT REPLACE);
    
    CREATE TABLE ifaces
    (originator text, mainip text, if_name text, if_type_bridge text, if_type_bridgedif bool, if_hwaddr text,
    ip_label text, ip_addr text, ip_broadcast text,
    on_networks text, on_zones text, on_olsr bool,
    dhcp_start text, dhcp_limit text, dhcp_leasetime text, dhcp_fwd text,
    ifstat_collisions int, ifstat_rx_compressed int, ifstat_rx_errors int,
    ifstat_rx_length_errors int, ifstat_rx_packets int, ifstat_tx_carrier_errors int,
    ifstat_tx_errors int, ifstat_tx_packets int, ifstat_multicast int,
    ifstat_rx_crc_errors int, ifstat_rx_fifo_errors int, ifstat_rx_missed_errors int,
    ifstat_tx_aborted_errors int, ifstat_tx_compressed int, ifstat_tx_fifo_errors int,
    ifstat_tx_window_errors int, ifstat_rx_bytes int, ifstat_rx_dropped int,
    ifstat_rx_frame_errors int, ifstat_rx_over_errors int, ifstat_tx_bytes int,
    ifstat_tx_dropped int, ifstat_tx_heartbeat_errors int,
    wlan_essid text, wlan_apmac text, wlan_type text, wlan_hwmode text, wlan_mode text,
    wlan_channel text, wlan_freq text, wlan_txpower text, wlan_signal text, wlan_noise text,
    wlan_bitrate text, wlan_crypt text, wlan_vaps text,
    db_ver text, db_update int, CONSTRAINT key_ifaces PRIMARY KEY (mainip, if_name) ON CONFLICT REPLACE);"
}

print_interfaces_2_6() {
  olsr_interfaces=$(echo \"/int\" | nc localhost 2006 2>/dev/null)
  for if_name in $(ls /sys/class/net/ | awk '!/lo/ {print $0}'); do
    iface_up=$(cat /sys/class/net/${if_name}/operstate)
	# sometimes the up-state is not recognized by /sys, than check with 'ip link'
	if [ "$iface_up" = "unknown" ] && [ -n "$(ip link show $if_name | awk '{if ($2 == "'$if_name':" && $3 ~ "UP") print $0}')" ]; then
		iface_up="up"
	fi
#     if_type_bridge=$(ls /sys/class/net/${if_name}/brif 2>/dev/null)                      # is bridge interface, list bridged interfaces
    if_type_bridge="$(ls /sys/class/net/${if_name}/brif 2>/dev/null | awk '{printf $1" "}')"
    ip_addr=$(ip address show $if_name | awk 'BEGIN{ORS=" "} /inet/ {print $2}')  #   contains additional whitespace
    if_type_bridgedif=$([ "$(ls /sys/class/net/${if_name}/brport 2>/dev/null)" ] && echo "1")    # is bridged interface
      
    if [ "$iface_up" = "up" ] && ([ -n "$ip_addr" ] || [ -n "$if_type_bridgedif" ]) || [ -n "$if_type_bridge" ]; then
      wlan=$(ls /sys/class/net/${if_name}/wireless/ 2>/dev/null)
      if [ -n "$wlan" ]; then
        iwinfo=$(iwinfo $if_name info | awk '{print $0"{newline}"}')
        wlan_essid="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($2 == "ESSID:") {gsub("\"","");print $3;}}')"
        wlan_apmac="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Access" && $2 == "Point:") print $3;}')"
        wlan_type="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Type:") print $2;}')"
        wlan_hwmode="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($3 == "HW" && $4 == "Mode(s):") print $5;}')"
        wlan_mode="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Mode:") print $2;}')"
        wlan_channel="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($3 == "Channel:") print $4;}')"
        wlan_freq="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($3 == "Channel:") {gsub("(",""); print $5;}}')"
        wlan_txpower="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Tx-Power:") print $2;}')"
        wlan_signal="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Signal:") print $2;}')"
        wlan_noise="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($4 == "Noise:") print $5;}')"
        wlan_bitrate="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Bit" && $2 == "Rate:") print $3;}')"
        wlan_crypt="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Encryption:") {gsub(" Encryption: ","");print $0;}}')"
        wlan_vaps="$(echo $iwinfo | awk 'BEGIN{RS="\\\{newline\\\}"} {if ($1 == "Supports" && $2 == "VAPs:") print $3;}')"
      else
        wlan_essid=""; wlan_apmac=""; wlan_type=""; wlan_hwmode=""; wlan_mode=""; wlan_channel=""; wlan_freq=""; wlan_txpower=""; wlan_signal=""; wlan_noise="";
        wlan_bitrate=""; wlan_crypt=""; wlan_vaps=""
      fi

      ifstat_collisions=$(cat /sys/class/net/${if_name}/statistics/collisions 2>/dev/null)
      ifstat_rx_compressed=$(cat /sys/class/net/${if_name}/statistics/rx_compressed 2>/dev/null)
      ifstat_rx_errors=$(cat /sys/class/net/${if_name}/statistics/rx_errors 2>/dev/null)
      ifstat_rx_length_errors=$(cat /sys/class/net/${if_name}/statistics/rx_length_errors 2>/dev/null)
      ifstat_rx_packets=$(cat /sys/class/net/${if_name}/statistics/rx_packets 2>/dev/null)
      ifstat_tx_carrier_errors=$(cat /sys/class/net/${if_name}/statistics/tx_carrier_errors 2>/dev/null)
      ifstat_tx_errors=$(cat /sys/class/net/${if_name}/statistics/tx_errors 2>/dev/null)
      ifstat_tx_packets=$(cat /sys/class/net/${if_name}/statistics/tx_packets 2>/dev/null)
      ifstat_multicast=$(cat /sys/class/net/${if_name}/statistics/multicast 2>/dev/null)
      ifstat_rx_crc_errors=$(cat /sys/class/net/${if_name}/statistics/rx_crc_errors 2>/dev/null)
      ifstat_rx_fifo_errors=$(cat /sys/class/net/${if_name}/statistics/rx_fifo_errors 2>/dev/null)
      ifstat_rx_missed_errors=$(cat /sys/class/net/${if_name}/statistics/rx_missed_errors 2>/dev/null)
      ifstat_tx_aborted_errors=$(cat /sys/class/net/${if_name}/statistics/tx_aborted_errors 2>/dev/null)
      ifstat_tx_compressed=$(cat /sys/class/net/${if_name}/statistics/tx_compressed 2>/dev/null)
      ifstat_tx_fifo_errors=$(cat /sys/class/net/${if_name}/statistics/tx_fifo_errors 2>/dev/null)
      ifstat_tx_window_errors=$(cat /sys/class/net/${if_name}/statistics/tx_window_errors 2>/dev/null)
      ifstat_rx_bytes=$(cat /sys/class/net/${if_name}/statistics/rx_bytes 2>/dev/null)
      ifstat_rx_dropped=$(cat /sys/class/net/${if_name}/statistics/rx_dropped 2>/dev/null)
      ifstat_rx_frame_errors=$(cat /sys/class/net/${if_name}/statistics/rx_frame_errors 2>/dev/null)
      ifstat_rx_over_errors=$(cat /sys/class/net/${if_name}/statistics/rx_over_errors 2>/dev/null)
      ifstat_tx_bytes=$(cat /sys/class/net/${if_name}/statistics/tx_bytes 2>/dev/null)
      ifstat_tx_dropped=$(cat /sys/class/net/${if_name}/statistics/tx_dropped 2>/dev/null)
      ifstat_tx_heartbeat_errors=$(cat /sys/class/net/${if_name}/statistics/tx_heartbeat_errors 2>/dev/null)

      if_hwaddr=$(cat /sys/class/net/${if_name}/address 2>/dev/null)
      
      ip_broadcast=$(ip address show $if_name | awk 'BEGIN{ORS=" "} /inet/ {print $4}')  #   contains additional whitespace
      ip_label=$(ip address show $if_name | awk 'BEGIN{ORS=" "} /inet/ {print $NF}')  #   contains additional whitespace
      # opennet-firmware / openwrt values
      all_networks=$(uci -q show network | awk 'BEGIN{FS="="} /network\..*\.ifname/ {if ($2 == "'${if_name##br-}'") {gsub("network.",""); gsub(".ifname",""); print$1;}}')
      on_networks=""; on_zones=""; lastnetwork="";
      for network in $all_networks; do
        if [ -n "$network" ] && [ "$(uci_get network.$network.proto)" != "none" ]; then
          on_networks="$on_networks $network"
          lastnetwork="$network"
          zone=$(get_zone_of_interface "$network")
          on_zones="$on_zones $zone"
        fi
      done
      if [ -n "$if_type_bridge" ]; then
        zone=$(get_zone_of_interface "${if_name##br-}")
        on_zones="$on_zones $zone"
      fi
      dhcpignore="$(uci_get dhcp.${lastnetwork}.ignore)"
      dhcp_start="$([ "$dhcpignore" = "1" ] || uci_get dhcp.${lastnetwork}.start)"
      dhcp_limit="$([ "$dhcpignore" = "1" ] || uci_get dhcp.${lastnetwork}.limit)"
      dhcp_leasetime="$([ "$dhcpignore" = "1" ] || uci_get dhcp.${lastnetwork}.leasetime)"

      dhcp_fwd="$dhcpfwd $(awk 'BEGIN{out=0} {if ($1 == "if" && $2 == "'$if_name'" && $3 == "true") out=1;
                if (out == 1 && $1 == "server" && $2 == "ip") printf $3}' /etc/dhcp-fwd.conf)"
      on_olsr="$(echo "$olsr_interfaces" | awk 'BEGIN{out="0"} {if ($1 == "'$if_name'") {out="1"; end};} END{print out;}')"

      SQL_STRING="$SQL_STRING
        INSERT INTO ifaces VALUES
        ('', '$on_olsr_mainip', '$if_name', '${if_type_bridge% }', '$if_type_bridgedif', '$if_hwaddr',
        '${ip_label% }', '${ip_addr% }', '${ip_broadcast% }',
        '${on_networks# }', '${on_zones# }', '$on_olsr',
        '$dhcp_start', '$dhcp_limit', '$dhcp_leasetime', '${dhcp_fwd# }',
        '$ifstat_collisions', '$ifstat_rx_compressed', '$ifstat_rx_errors',
        '$ifstat_rx_length_errors', '$ifstat_rx_packets', '$ifstat_tx_carrier_errors',
        '$ifstat_tx_errors', '$ifstat_tx_packets', '$ifstat_multicast',
        '$ifstat_rx_crc_errors', '$ifstat_rx_fifo_errors', '$ifstat_rx_missed_errors',
        '$ifstat_tx_aborted_errors', '$ifstat_tx_compressed', '$ifstat_tx_fifo_errors',
        '$ifstat_tx_window_errors', '$ifstat_rx_bytes', '$ifstat_rx_dropped',
        '$ifstat_rx_frame_errors', '$ifstat_rx_over_errors', '$ifstat_tx_bytes',
        '$ifstat_tx_dropped', '$ifstat_tx_heartbeat_errors',
        '$wlan_essid', '$wlan_apmac', '$wlan_type', '$wlan_hwmode', '$wlan_mode',
        '$wlan_channel', '$wlan_freq', '$wlan_txpower', '$wlan_signal', '$wlan_noise',
        '$wlan_bitrate', '$wlan_crypt', '$wlan_vaps', '$DATABASE_VERSION', '$db_epoch');"
      printed_interfaces="$printed_interfaces $if_name";

      if [ "$EXPORT_JSON" = "1" ];then
        JSON=$(cat <<EOF
{"ifaces":{"originator":"%s","on_olsr_mainip":"%s","if_name":"%s","if_type_bridge":"%s","if_type_bridgedif":"%s","if_hwaddr":"%s",\
"ip_label":"%s","ip_addr":"%s","ip_broadcast":"%s","on_networks":"%s","on_zones":"%s","on_olsr":"%s","dhcp_start":"%s","dhcp_limit":"%s","dhcp_leasetime":"%s",\
"dhcp_fwd":"%s","ifstat_collisions":"%s","ifstat_rx_compressed":"%s","ifstat_rx_errors":"%s","ifstat_rx_length_errors":"%s","ifstat_rx_packets":"%s",\
"ifstat_tx_carrier_errors":"%s","ifstat_tx_errors":"%s","ifstat_tx_packets":"%s","ifstat_multicast":"%s","ifstat_rx_crc_errors":"%s","ifstat_rx_fifo_errors":"%s",\
"ifstat_rx_missed_errors":"%s","ifstat_tx_aborted_errors":"%s","ifstat_tx_compressed":"%s","ifstat_tx_fifo_errors":"%s","ifstat_tx_window_errors":"%s",\
"ifstat_rx_bytes":"%s","ifstat_rx_dropped":"%s","ifstat_rx_frame_errors":"%s","ifstat_rx_over_errors":"%s","ifstat_tx_bytes":"%s","ifstat_tx_dropped":"%s",\
"ifstat_tx_heartbeat_errors":"%s","wlan_essid":"%s","wlan_apmac":"%s","wlan_type":"%s","wlan_hwmode":"%s","wlan_mode":"%s","wlan_channel":"%s","wlan_freq":"%s",\
"wlan_txpower":"%s","wlan_signal":"%s","wlan_noise":"%s","wlan_bitrate":"%s","wlan_crypt":"%s","wlan_vaps":"%s","db_ver":"%s","db_update":"%s"}}\n
EOF
)
        printf $JSON "" "$on_olsr_mainip" "$if_name" "${if_type_bridge% }" "$if_type_bridgedif" "$if_hwaddr" "${ip_label% }" "${ip_addr% }" "${ip_broadcast% }" \
		"${on_networks# }" "${on_zones# }" "$on_olsr" "$dhcp_start" "$dhcp_limit" "$dhcp_leasetime" "${dhcp_fwd# }" "$ifstat_collisions" "$ifstat_rx_compressed" "$ifstat_rx_errors" \
		"$ifstat_rx_length_errors" "$ifstat_rx_packets" "$ifstat_tx_carrier_errors" "$ifstat_tx_errors" "$ifstat_tx_packets" "$ifstat_multicast" "$ifstat_rx_crc_errors" \
		"$ifstat_rx_fifo_errors" "$ifstat_rx_missed_errors" "$ifstat_tx_aborted_errors" "$ifstat_tx_compressed" "$ifstat_tx_fifo_errors" "$ifstat_tx_window_errors" \
		"$ifstat_rx_bytes" "$ifstat_rx_dropped" "$ifstat_rx_frame_errors" "$ifstat_rx_over_errors" "$ifstat_tx_bytes" "$ifstat_tx_dropped" "$ifstat_tx_heartbeat_errors" \
		"$wlan_essid" "$wlan_apmac" "$wlan_type" "$wlan_hwmode" "$wlan_mode" "$wlan_channel" "$wlan_freq" "$wlan_txpower" "$wlan_signal" "$wlan_noise" "$wlan_bitrate" \
		"$wlan_crypt" "$wlan_vaps" "$DATABASE_VERSION" "$db_epoch" | tr '\n' ' ' >>${DATABASE_FILE}.json.tmp
	    echo >>${DATABASE_FILE}.json.tmp	
      fi
    fi
  done
}

SQL_STRING=""
create_database

on_id="$(uci_get on-core.settings.on_id)"
on_olsr_mainip="$(echo \"/config\" | nc localhost 2006 2>/dev/null | awk '/MainIp/ {print $2}')"
db_epoch="$(date +%s)"

SQL_STRING="$SQL_STRING 
  BEGIN TRANSACTION;"

print_interfaces_2_6

sys_ver="$(uname -sr)"
sys_board="$(cat /proc/diag/model 2>/dev/null || awk 'BEGIN{FS="[ \t]+:[ \t]";ORS=" "} /machine|Model|system type|Hardware/ {print $2;}' /proc/cpuinfo)"
sys_cpu="$(awk 'BEGIN{FS="[ \t]+:[ \t]";ORS=" "} /Processor|cpu model|vendor_id/ {print $2;}' /proc/cpuinfo)"
sys_mem="$(awk '{if ($1 == "MemTotal:") {print $2}}' /proc/meminfo)"
sys_uptime="$(cat /proc/uptime | awk '{print $1}')"
sys_load="$(awk '{print $1" "$2" "$3}' /proc/loadavg)"
sys_free="$(awk '{if ($1 == "MemFree:") {print $2}}' /proc/meminfo)"
sys_watchdog="$(pidof watchdog >/dev/null && echo "1" || echo "0")"

. /etc/openwrt_release
sys_os_type="$DISTRIB_ID"
sys_os_name="$DISTRIB_CODENAME"
sys_os_rel="$DISTRIB_RELEASE"
sys_os_ver="$(opkg status base-files | awk '{if (/Version/) printf $2;}')"
sys_os_arc="$(opkg status base-files | awk '{if (/Architecture/) printf $2;}')"
sys_os_insttime="$(opkg status base-files | awk '{if (/Installed-Time/) printf $2;}')"

on_core_ver="$(opkg status on-core | awk '{if (/Version/) printf $2;}')"
on_core_insttime="$(opkg status on-core | awk '{if (/Installed-Time/) printf $2;}')"
on_packages="$(opkg status | awk '{if ($1 == "Package:" && $2 ~ "^on-" && $2 != "on-core") printf $2" "}')"

on_olsrd_status="$(pidof olsrd >/dev/null && echo "1" || echo "0")"
on_olsr_mainip="$(echo \"/config\" | nc localhost 2006 2>/dev/null | awk '/MainIp/ {print $2}')"

on_wifidog_status="$(pidof wifidog >/dev/null && echo "1" || echo "0")"
on_wifidog_id="$(awk '{if ($1 == "GatewayID") print $2}' /etc/wifidog.conf 2>/dev/null)"

on_vpn_status="$([ -e /tmp/openvpn_msg.txt ] && echo 1 || echo 0)"
on_vpn_cn="$(. \"${IPKG_INSTROOT:-}/usr/lib/opennet/on-helper.sh\"; get_client_cn)"
on_vpn_gw="$(uci_get openvpn.opennet_user.remote)"
on_vpn_autosearch="$([ "$(uci_get on-openvpn.gateways.autosearch)" = "on" ] && echo "1" || echo "0")"
on_vpn_sort="$(uci_get on-openvpn.gateways.vpn_sort_criteria)"

index=1; gw_addresses="";
while [ -n "$(uci_get on-openvpn.gate_$index)" ] ; do
  gw_ipaddr=$(uci_get on-openvpn.gate_$index.ipaddr);
  age=$(get_gateway_value "$gw_ipaddr" age)
  status=$(get_gateway_value "$gw_ipaddr" status)
  gw_addresses="$gw_addresses ${gw_ipaddr}:${status}:${age}"
  : $((index++))
done
on_vpn_gws="${gw_addresses## }"

index=0; gw_blacklist_addresses="";
while [ -n "$(uci_get on-openvpn.@blacklist_gateway[$index])" ] ; do
  ipaddr=$(uci_get on-openvpn.@blacklist_gateway[$index].ipaddr);
  name=$(uci_get on-openvpn.@blacklist_gateway[$index].name);
  gw_blacklist_addresses="$gw_blacklist_addresses ${ipaddr}:${name}"
  : $((index++))
done
on_vpn_blist="${gw_blacklist_addresses## }"

ugw_status_centralips=$(for gw in $(uci_get on-usergw.@usergw[0].centralIP); do ip route get $gw 2>/dev/null | awk '/dev tap/ {printf $1" "}'; done)
on_ugw_status="$([ "$(echo $ugw_status_centralips | wc -w)" -ge "1" ] && echo "1" || echo "0")"
on_ugw_enabled="$([ "$(uci_get on-usergw.ugw_sharing.shareInternet)" = "on" ] && echo "1" || echo "0")"

index=1; ugw_status_sharing_possible=0;
while [ -n "$(uci_get on-usergw.opennet_ugw${index})" ]; do
  wan=$(uci_get on-usergw.opennet_ugw${index}.wan)
  mtu=$(uci_get on-usergw.opennet_ugw${index}.mtu)
  [ "$wan" = "ok" ] && [ "$mtu" = "ok" ] && ugw_status_sharing_possible=1 && break
  : $((index++))
done
on_ugw_possible="$ugw_status_sharing_possible"
on_ugw_tunnel="$([ "$(ls /tmp/opennet_ugw*.txt 2>/dev/null)" ] && echo "1" || echo "0")"
on_ugw_connected="${ugw_status_centralips# }"
on_ugw_presetips="$(uci_get on-usergw.@usergw[0].centralIP)"
on_ugw_presetnames="$(uci_get on-usergw.@usergw[0].name)"

db_time="$(date)"

if [ "$EXPORT_JSON" = "1" ];then
	JSON=$(cat <<EOF
{"nodes":{"originator":"%s","on_olsr_mainip":"%s","sys_ver":"%s","sys_board":"%s","sys_cpu":"%s","sys_mem":"%s","sys_uptime":"%s","sys_load":"%s",\
"sys_free":"%s","sys_watchdog":"%s","sys_os_type":"%s","sys_os_name":"%s","sys_os_rel":"%s","sys_os_ver":"%s","sys_os_arc":"%s","sys_os_insttime":"%s",\
"on_core_ver":"%s","on_core_insttime":"%s","on_packages":"%s","on_id":"%s","on_olsrd_status":"%s","on_olsr_mainip":"%s","on_wifidog_status":"%s",\
"on_wifidog_id":"%s","on_vpn_cn":"%s","on_vpn_status":"%s","on_vpn_gw":"%s","on_vpn_autosearch":"%s","on_vpn_sort":"%s","on_vpn_gws":"%s","on_vpn_blist":"%s",\
"on_ugw_status":"%s","on_ugw_enabled":"%s","on_ugw_possible":"%s","on_ugw_tunnel":"%s","on_ugw_connected":"%s","on_ugw_presetips":"%s","on_ugw_presetnames":"%s",\
"on_old_autoadapttxpwr":"%s","on_old_remoteconf":"%s","db_time":"%s","db_epoch":"%s","db_ver":"%s","db_update":"%s"}}\n
EOF
)
    printf $JSON "" "$on_olsr_mainip" "$sys_ver" "${sys_board% }" "${sys_cpu% }" "$sys_mem" "$sys_uptime" "$sys_load" "$sys_free" "$sys_watchdog" "$sys_os_type" \
	"${sys_os_name% }" "$sys_os_rel" "$sys_os_ver" "$sys_os_arc" "$sys_os_insttime" "$on_core_ver" "$on_core_insttime" "${on_packages% }" "$on_id" "$on_olsrd_status" \
	"$on_olsr_mainip" "$on_wifidog_status" "$on_wifidog_id" "$on_vpn_cn" "$on_vpn_status" "$on_vpn_gw" "$on_vpn_autosearch" "$on_vpn_sort" "$on_vpn_gws" \
	"$on_vpn_blist" "$on_ugw_status" "$on_ugw_enabled" "$on_ugw_possible" "$on_ugw_tunnel" "$on_ugw_connected" "$on_ugw_presetips" "$on_ugw_presetnames" "" "" \
	"$db_time" "$db_epoch" "$DATABASE_VERSION" "$db_epoch" | tr '\n' ' ' >>${DATABASE_FILE}.json.tmp
    echo >>${DATABASE_FILE}.json.tmp
    mv -f ${DATABASE_FILE}.json.tmp ${DATABASE_FILE}.json
else
  SQL_STRING="$SQL_STRING
    INSERT INTO nodes VALUES
    ('', '$on_olsr_mainip', '$sys_ver', '${sys_board% }', '${sys_cpu% }',
    '$sys_mem', '$sys_uptime', '$sys_load', '$sys_free', '$sys_watchdog',
    '$sys_os_type', '${sys_os_name% }', '$sys_os_rel', '$sys_os_ver', '$sys_os_arc',
    '$sys_os_insttime', '$on_core_ver', '$on_core_insttime', '${on_packages% }',
    '$on_id', '$on_olsrd_status', '$on_olsr_mainip',
    '$on_wifidog_status', '$on_wifidog_id', '$on_vpn_cn', '$on_vpn_status',
    '$on_vpn_gw', '$on_vpn_autosearch', '$on_vpn_sort', '$on_vpn_gws', '$on_vpn_blist',
    '$on_ugw_status', '$on_ugw_enabled', '$on_ugw_possible', '$on_ugw_tunnel',
    '$on_ugw_connected', '$on_ugw_presetips', '$on_ugw_presetnames', '', '',
    '$db_time', '$db_epoch', '$DATABASE_VERSION', '$db_epoch');

    END TRANSACTION;"

  sqlite3 -batch $DATABASE_FILE "$SQL_STRING"
fi
