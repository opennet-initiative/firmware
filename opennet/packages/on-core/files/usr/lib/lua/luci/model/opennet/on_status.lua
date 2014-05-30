--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--


local uci = require "luci.model.uci"
local cursor = uci.cursor()
require("luci.sys")

function split(str)
  local t = { }
  str:gsub("%S+", function (w) table.insert(t, w) end)
  return t
end

function printFirmwareTitle()
  local on_version = luci.sys.exec("opkg status on-core | awk '{if (/Version/) print $2;}'")
  local on_id = cursor:get("on-core", "settings", "on_id")
  local on_aps = ""
  if nixio.fs.access("/usr/sbin/on_portcalc.sh") then
    on_aps = split(luci.sys.exec("/usr/sbin/on_portcalc.sh"))[1]
  end
  luci.http.write(luci.i18n.stringf("Opennet Firmware (next generation) version %s", on_version))
  if on_id then
    luci.http.write(luci.i18n.stringf("-- AP %s", on_id))
  end
  if on_aps and on_aps ~= "" then
    luci.http.write(luci.i18n.stringf("-- CN %s", on_aps))
  end
end

function printOpenVPN()
  if nixio.fs.access("/tmp/openvpn_msg.txt") then
    remote = cursor:get("openvpn", "opennet_user", "remote")
    luci.http.write(luci.i18n.string([[VPN-Tunnel active.]])..[[ (]])
    if remote[1] then
      luci.http.write(remote[1])
    else
      luci.http.write(remote)
    end
    luci.http.write(")")
  else
    luci.http.write(luci.i18n.string([[VPN-Tunnel not active, for details check the System Log.]]))
  end
end

function printUserGW()
  local ugw_status = {}
  -- central gateway-IPs reachable over tap-devices
  ugw_status.centralips = luci.sys.exec("for gw in $(uci -q get on-usergw.@usergw[0].centralIP); do ip route get $gw | awk '/dev tap/ {print $1}'; done")
  local words
  ugw_status.centralips_no = 0
  for words in string.gfind(ugw_status.centralips, "[^%s]+") do
    ugw_status.centralips_no=ugw_status.centralips_no+1
  end
  ugw_status.centralip_status = "error"
  if ugw_status.centralips_no >= 1 then
    ugw_status.centralip_status = "ok"
  end
  -- tunnel active
  local iterator, number = nixio.fs.glob("/tmp/opennet_ugw*.txt")
  ugw_status.tunnel_active = (number >= 1)
  -- sharing possible
  ugw_status.usergateways_no = 0
  cursor:foreach ("on-usergw", "usergateway", function() ugw_status.usergateways_no = ugw_status.usergateways_no + 1 end)
  ugw_status.sharing_wan_ok = false
  ugw_status.sharing_possible = false
  local count = 1
  while count <= ugw_status.usergateways_no do
    local onusergw = cursor:get_all("on-usergw", "opennet_ugw"..count)
    if (onusergw.wan == "ok") then
      ugw_status.sharing_wan_ok = true
    end
    if (onusergw.wan == "ok" and onusergw.mtu == "ok") then
        ugw_status.sharing_possible = true
        break
    end
    count = count + 1
  end
  -- sharing enabled
  ugw_status.sharing_enabled = (cursor:get("on-usergw", "ugw_sharing", "shareInternet") == "on")
  -- forwarding enabled
  ugw_status.forwarded_ip = luci.sys.exec("iptables -L zone_opennet_prerouting -t nat -n | awk 'BEGIN{FS=\"[ :]+\"} /udp dpt:1600 to:/ {printf \$5; exit}'")
  ugw_status.forwarded_gw = luci.sys.exec("iptables -L zone_opennet_prerouting -t nat -n | awk 'BEGIN{FS=\"[ :]+\"} /udp dpt:1600 to:/ {printf \$10; exit}'")

  
  if ugw_status.sharing_enabled or ugw_status.sharing_possible then
    luci.http.write([[<tr class='cbi-section-table-titles'>
                <td class='cbi-section-table-cell'>]]..
                luci.i18n.string([[Internet-Sharing:]])..[[</td>
                <td class='cbi-section-table-cell'>]])
    if (ugw_status.centralip_status == "ok") or (ugw_status.forwarded_gw ~= "") then
      luci.http.write(luci.i18n.string([[Internet shared]]))
      if ugw_status.centralips_no == 0 then
        luci.http.write(luci.i18n.string([[(no central Gateway-IPs connected trough tunnel)]]))
      elseif ugw_status.centralips_no == 1 then 
        luci.http.write(luci.i18n.stringf([[(central Gateway-IP %s connected trough tunnel)]], ugw_status.centralips))
      else
        luci.http.write(luci.i18n.stringf([[(central Gateway-IPs %s connected trough tunnel)]], ugw_status.centralips))
      end
      if ugw_status.forwarded_gw ~= "" then
        print(", "..luci.i18n.stringf([[Gateway-Forward for %s (to %s) activated]], ugw_status.forwarded_ip, ugw_status.forwarded_gw))
      end
    elseif ugw_status.tunnel_active then
      luci.http.write(luci.i18n.string([[Internet not shared]]).." ( "..
        luci.i18n.string([[Internet-Sharing enabled]])..", "..luci.i18n.string([[Usergateway-Tunnel active]]).." )")
    elseif ugw_status.sharing_enabled then
      luci.http.write(luci.i18n.string([[Internet not shared]]).." ( "..
        luci.i18n.string([[Internet-Sharing enabled]])..", "..luci.i18n.string([[Usergateway-Tunnel not running]]).." )")
    elseif ugw_status.sharing_possible then
        luci.http.write(luci.i18n.string([[Internet not shared]])..", "..luci.i18n.string([[Internet-Sharing possible]]))
    else
        luci.http.write(luci.i18n.string([[Internet-Sharing possible]]))
    end
    luci.http.write([[</td></tr>]])
  end
end

-- ajaxified rest:

function status_network()
  luci.http.prepare_content("text/plain")
  printZoneLine("local")
  printZoneLine("opennet")
  printZoneLine("wan")
  printZoneLine("free")
end

function printZoneLine(zoneName)
  networks = cursor:get("firewall", "zone_"..zoneName, "network")
  if not networks then
    networks = cursor:get("firewall", "zone_"..zoneName, "name")
  end
  if networks and relevant(networks) then
--     luci.http.write([[<tr class='cbi-section-table-titles'><td class='cbi-section-table-cell'>]])
    luci.http.write([[<h3>]])
    if zoneName == "local" then
      luci.http.write(luci.i18n.string([[<abbr title='These addresses are used locally and usually protected by your firewall. Connections to the Internet are routed through your VPN-Tunnel if it is active.'>LOCAL</abbr> IP Address(es):]]))
    elseif zoneName == "opennet" then
      luci.http.write(luci.i18n.string([[<abbr title='Opennet-Addresses are usually given to the Access-Point based on your Opennet-ID. These are the interfaces on which OLSR is running.'>OPENNET</abbr> IP Address(es):]]))
    elseif zoneName == "wan" then
      luci.http.write(luci.i18n.string([[<abbr title='The WAN Interface is used for your local Internet-Connection (for instance DSL). It will be used for you local traffic and to map Usergateways into Opennet = Share your Internet Connection if you choose to.'>WAN</abbr> IP Address(es):]]))
    elseif zoneName == "free" then
      luci.http.write(luci.i18n.string([[<abbr title='The FREE Interface will be used to publicly share Opennet with Wifidog.'>FREE</abbr> IP Address(es):]]))
    end
    luci.http.write([[</h3>]])
--     luci.http.write([[</td><td class='cbi-section-table-cell'>]])
    printInterfaces(networks, zoneName)
--     luci.http.write([[</td></tr>]])
  end
end

function relevant(networks)
  for network in networks:gmatch("%S+") do
    local devices = luci.sys.exec(". $IPKG_INSTROOT/lib/functions.sh; include /lib/network; scan_interfaces; "..
      "[ -n \"$(config_get "..network.." ipaddr)\" ] && config_get "..network.." device")
    devices = devices.gsub(devices, "%c+", "")
    if devices ~= "" then
      for device in devices:gmatch("%S+") do 
        if luci.sys.exec("ip link show "..device.." 2>/dev/null | grep UP") ~= "" then
          return true
        end
      end
    end
  end
  return false
end

function printInterfaces(networks, zoneName)
  luci.http.write([[<table id='network_table_]]..zoneName..[[' class='status_page_table'><tr><th>]]..
    luci.i18n.string([[Interface]])..
    [[</th><th>]]..luci.i18n.string([[IP]])..
    [[</th><th>]]..luci.i18n.string([[IPv6]])..
    [[</th><th>]]..luci.i18n.string([[MAC]])..
    [[</th><th>]])
  luci.http.write(luci.i18n.string([[<abbr title='start / limit / leasetime'>DHCP</abbr>]]))
  luci.http.write([[</th></tr>]])
  for network in networks:gmatch("%S+") do
    printNetworkInterfaceValues(network)
  end
  luci.http.write([[</table>]])
end

function printNetworkInterfaceValues(network)
  -- get physical interface name
  ifname = luci.sys.exec(". $IPKG_INSTROOT/lib/functions.sh; include $IPKG_INSTROOT/lib/network; scan_interfaces; config_get "..network.." ifname")
  ifname = ifname.gsub(ifname, "%c+", "")
  if not ifname or ifname == "" then
    return
  end
  -- skip alias and disabled interfaces
  if luci.sys.exec("ip link show "..ifname.." 2>/dev/null | grep UP") == "" then
    return
  end
  output = luci.sys.exec([[ip address show label ]]..ifname..[[ | awk 'BEGIN{ mac="---";ip="---";ip6="---"; }  { if ($1 ~ /link/) mac=$2; if ($1 ~ /inet$/) ip=$2; if ($1 ~ /inet6/) ip6=$2; } END{ printf "<td>]]..ifname..[[</td><td>"ip"</td><td>"ip6"</td><td>"mac"</td>"}']])
  if output and output ~= "" then
    luci.http.write([[<tr>]]..output..[[<td>]])
    -- add DHCP information
    local dhcp = cursor:get_all("dhcp", network)
    if dhcp and dhcp.ignore ~= "1" then
      -- we provide DHCP for this network
      luci.http.write(dhcp.start.." / "..dhcp.limit.." / "..dhcp.leasetime)
    else 
      -- dnsmasq does not DHCP for this network _OR_ the network is used for opennet wifidog (FREE)
      local dhcpfwd
      if (luci.sys.exec("pidof dhcp-fwd") ~= "") then
        -- check for dhcp-fwd
        dhcpfwd = luci.sys.exec([[
          awk 'BEGIN{out=0} {if ($1 == "if" && $2 == "]]..ifname..[[" && $3 == "true") out=1;
            if (out == 1 && $1 == "server" && $2 == "ip") printf $3}' /etc/dhcp-fwd.conf
          ]])
        if dhcpfwd and dhcpfwd ~= "" then
          luci.http.write("active, forwarded to "..dhcpfwd)
        end
      end
      if not dhcpfwd or dhcpfwd == "" then
        luci.http.write("---")
      end
    end
    luci.http.write([[</td></tr>]])
  end
end

function status_wireless()
  luci.http.prepare_content("text/plain")

  local header = 0;
  local wireless = cursor:get_all("wireless")
  if wireless then
    for k, v in pairs(wireless) do
      if v[".type"] == "wifi-iface" then
        if header == 0 then
          luci.http.write([[<table id='wireless_table' class='status_page_table'><tr><th>]]..
                    luci.i18n.string([[Interface]])..[[</th><th>]]..
                    luci.i18n.string([[SSID]])..[[</th><th></th></tr>]])
          header = 1
        end
        ifname = v.ifname or "-"
        essid = luci.util.pcdata(v.ssid) or "-"
        if not ifname or ifname == "-" then
          ifname = luci.sys.exec([[
            find /var/run/ -name "hostapd*conf" -exec \
            awk 'BEGIN{FS="=";iface="";found=0} 
              {if ($1 == "ssid" && $2 == "]]..essid..[[") found=1; if ($1 == "interface") iface=$2;} 
              END{if (found) printf iface}' {} \;
              ]])
        end
        ifname = ifname.gsub(ifname, "%c+", "")
        iwinfo = luci.sys.wifi.getiwinfo(ifname)
        device = v.device or "-";
        if (not iwinfo.mode) then
          iwinfo = luci.sys.wifi.getiwinfo(device)
        end
        mode802 = wireless[v.device].hwmode
        mode802 = mode802 and "802."..mode802 or "-"
  --                  channel = wireless[v.device].channel or "-"
        
        local signal = iwinfo and iwinfo.signal or "-"
        local noise = iwinfo and iwinfo.noise or "-"
  --                  local q = iwinfo and iwinfo.quality or "0"
        local ssid = iwinfo and iwinfo.ssid or "N/A"
        local bssid = iwinfo and iwinfo.bssid or "N/A"
        local chan = iwinfo and iwinfo.channel or "N/A"
        local mode = iwinfo and iwinfo.mode or "N/A"
        local txpwr = iwinfo and iwinfo.txpower or "N/A"
  --                  local bitrate = iwinfo and iwinfo.bitrate or "N/A"

        luci.http.write(  "<tr><td>"..ifname.."/"..device.."</td>"..
                "<td>"..ssid.."</td>"..
                "<td>"..mode..
                " / Mode: "..mode802..
                " / Channel: "..chan..
                " / Cell: "..bssid..
                " / S/N: "..signal.."/"..noise..
--                          " / Bitrate: "..bitrate..
                " / Power: "..txpwr.."</td></tr>")
      end
    end
    if header == 1 then
      luci.http.write([[</table></td></tr>]])
    end
  end
end

function status_neighbors()
  luci.http.prepare_content("text/plain")
  output = luci.sys.exec("echo \"/links\" | nc localhost 2006 | awk 'BEGIN {out=0} { if (out == 1 \&\& \$0 != \"\") printf \"<tr><td><a href=\\\"http://\"$2\"\\\">\"\$2\"</a></td><td>\"\$4\"</td><td>\"\$5\"</td><td>\"\$6\"</td></tr>\"; if (\$1 == \"Local\") out = 1;}'")
  if output ~= "" then
    luci.http.write([[<tr><th>]]..
      luci.i18n.string([[IP Address]])..[[</th><th>]]..
              luci.i18n.string([[<abbr title='Link-Quality, how many test-packets you recevie from your neighbor'>LQ</abbr>]])..
              [[</th><th>]]..
              luci.i18n.string([[<abbr title='Neighbor-Link-Quality, how many of your test-packets are reaching your neighbor'>NLQ</abbr>]])..
              [[</th><th>]]..
              luci.i18n.string([[<abbr title='Expected Transmission Count - Quality of the Connection to the Gateway reagrding OLSR'>ETX</abbr>]])..
              [[</th></tr>]])
    luci.http.write(output)
  end
end
