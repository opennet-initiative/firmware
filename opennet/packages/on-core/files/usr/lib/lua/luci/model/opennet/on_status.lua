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
require("luci.model.opennet.funcs")


function get_firmware_title()
	local on_version = on_function("get_on_firmware_version")
	local on_id = cursor:get("on-core", "settings", "on_id")
	local client_cn = on_function("get_client_cn")
	local result
	result = luci.i18n.translatef("Opennet Firmware version %s", on_version)
	if on_id then
		result = result .. luci.i18n.translatef("-- AP %s", on_id)
	end
	if client_cn and client_cn ~= "" then
		result = result .. luci.i18n.translatef("-- CN %s", client_cn)
	end
	return result
end


function status_mig_connection()
	luci.http.prepare_content("text/plain")
	if not on_bool_function("is_function_available", {"get_active_mig_connections"}) then return end
	local services = line_split(on_function("get_active_mig_connections"))
	local result
	function get_service_host(service_name)
		return get_service_value(service_name, "host")
	end
	local remotes = string_join(map_table(services, get_service_host), ", ")
	if remotes then
		result = luci.i18n.translatef("VPN-Tunnel active (%s)", remotes)
	else
		result = luci.i18n.translate("VPN-Tunnel not active, for details check the System Log.")
	end
	luci.http.write(result)
end


function status_ugw_connection()
	-- check if package on-usergw is installed
	if not on_bool_function("is_function_available", {"get_active_ugw_connections"}) then return end

	luci.http.prepare_content("text/plain")

	local ugw_status = {}
	-- central gateway-IPs reachable over tap-devices
	ugw_status.connections = on_function("get_active_ugw_connections")
	local service_name
	local central_ips_table = {}
	for service_name in line_split(ugw_status.connections) do
		table.insert(central_ips_table, get_service_value(service_name, "host"))
	end
	ugw_status.centralips = string_join(central_ips_table, ", ")
	ugw_status.centralip_status = (ugw_status.centralips ~= "")
	-- tunnel active
	ugw_status.tunnel_active = to_bool(ugw_status.centralips)
	-- sharing possible
	ugw_status.usergateways_no = 0
	-- TODO: Struktur ab hier weiter umsetzen
	cursor:foreach ("on-usergw", "usergateway", function() ugw_status.usergateways_no = ugw_status.usergateways_no + 1 end)
	ugw_status.sharing_possible = false
	local count = 1
	while count <= ugw_status.usergateways_no do
		local onusergw = cursor:get_all("on-usergw", "opennet_ugw"..count)
		if uci_to_bool(onusergw.wan) and uci_to_bool(onusergw.mtu_status) then
			ugw_status.sharing_possible = true
			break
		end
		count = count + 1
	end
	-- sharing enabled
	ugw_status.sharing_enabled = uci_to_bool(cursor:get("on-usergw", "ugw_sharing", "shareInternet"))
	-- forwarding enabled
	local ugw_port_forward = tab_split(on_function("get_ugw_portforward"))
	ugw_status.forwarded_ip = ugw_port_forward[1]
	ugw_status.forwarded_gw = ugw_port_forward[2]


	local result = ""
	if ugw_status.sharing_enabled or ugw_status.sharing_possible then
		result = result .. [[<tr class='cbi-section-table-titles'><td class='cbi-section-table-cell'>]] ..
			luci.i18n.translate("Internet-Sharing:") .. [[</td><td class='cbi-section-table-cell'>]]
		if uci_to_bool(ugw_status.centralip_status) or (ugw_status.forwarded_gw ~= "") then
			result = result .. luci.i18n.translate("Internet shared")
			if ugw_status.centralips then
				result = result .. luci.i18n.translate("(no central Gateway-IPs connected trough tunnel)")
			else
				result = result .. luci.i18n.translatef("(central Gateway-IPs (%s) connected trough tunnel)", ugw_status.centralips)
			end
			if ugw_status.forwarded_gw ~= "" then
				result = result .. ", " .. luci.i18n.translatef("Gateway-Forward for %s (to %s) activated", ugw_status.forwarded_ip, ugw_status.forwarded_gw)
			end
		elseif ugw_status.tunnel_active then
			result = result .. luci.i18n.translate("Internet not shared")
			    .. " ( " .. luci.i18n.translate("Internet-Sharing enabled")
			    .. ", " .. luci.i18n.translate("Usergateway-Tunnel active") .. " )"
		elseif ugw_status.sharing_enabled then
			result = result .. luci.i18n.translate("Internet not shared")
			    .. " ( "..  luci.i18n.translate("Internet-Sharing enabled")
			    .. ", " .. luci.i18n.translate("Usergateway-Tunnel not running") .. " )"
		elseif ugw_status.sharing_possible then
			result = result .. luci.i18n.translate("Internet not shared")
			    .. ", " .. luci.i18n.translate("Internet-Sharing possible")
		else
			result = result .. luci.i18n.translate("Internet-Sharing possible")
		end
		result = result .. '</td></tr>'
		luci.http.write(result)
	end
end


function status_network()
	luci.http.prepare_content("text/plain")
	printZoneLine(on_function("get_variable", {"ZONE_LOCAL"}))
	printZoneLine(on_function("get_variable", {"ZONE_MESH"}))
	printZoneLine(on_function("get_variable", {"ZONE_WAN"}))
	printZoneLine(on_function("get_variable", {"ZONE_FREE"}))
end

function printZoneLine(zoneName)
	networks = on_function("get_zone_interfaces", {zoneName})
	if networks and relevant(networks) then
		luci.http.write([[<h3>]])
		if zoneName == "lan" then
			luci.http.write('<abbr title="' .. luci.i18n.translate("These addresses are used locally and usually protected by your firewall. Connections to the Internet are routed through your VPN-Tunnel if it is active.") .. '">' .. luci.i18n.translate("LOCAL") .. '</abbr> ' .. luci.i18n.translate('IP Address(es):'))
		elseif zoneName == "on_mesh" then
			luci.http.write('<abbr title="' .. luci.i18n.translate("Opennet-Addresses are usually given to the Access-Point based on your Opennet-ID. These are the interfaces on which OLSR is running.") .. '">' .. luci.i18n.translate("OPENNET") .. '</abbr> ' .. luci.i18n.translate("IP Address(es):"))
		elseif zoneName == "wan" then
			luci.http.write('<abbr title="' .. luci.i18n.translate("The WAN Interface is used for your local Internet-Connection (for instance DSL). It will be used for your local traffic and to map Usergateways into Opennet = Share your Internet Connection if you choose to.") .. '">' .. luci.i18n.translate("WAN") .. '</abbr> ' .. luci.i18n.translate("IP Address(es):"))
		elseif zoneName == "free" then
			luci.http.write('<abbr title="' .. luci.i18n.translate("The FREE Interface will be used to publicly share Opennet with Wifidog.") .. '">' .. luci.i18n.translate("FREE") .. '</abbr> ' .. luci.i18n.translate("IP Address(es):"))
		end
		luci.http.write([[</h3>]])
		printInterfaces(networks, zoneName)
	end
end

function relevant(networks)
	for network in networks:gmatch("%S+") do
		local devices = luci.sys.exec(". \"${IPKG_INSTROOT:-}/lib/functions.sh\"; include \"${IPKG_INSTROOT:-}/lib/network\"; scan_interfaces; "..
			"[ -n \"$(config_get "..network.." ipaddr)\" ] && config_get "..network.." device")
		devices = devices.gsub(devices, "%c+", "")
		if devices ~= "" then
			for device in devices:gmatch("%S+") do
				if luci.sys.exec("ip link show "..device.." 2>/dev/null | grep UP") ~= "" then return true end
			end
		end
	end
	return false
end

function printInterfaces(networks, zoneName)
	luci.http.write([[<table id='network_table_]]..zoneName..[[' class='status_page_table'><tr><th>]]..
		luci.i18n.translate("Interface") ..
		"</th><th>" .. luci.i18n.translate("IP") ..
		"</th><th>" .. luci.i18n.translate("IPv6") ..
		"</th><th>" .. luci.i18n.translate("MAC") ..
		"</th><th>")
	luci.http.write('<abbr title="' .. luci.i18n.translate("start / limit / leasetime") .. '">DHCP</abbr>')
	luci.http.write([[</th></tr>]])
	for network in networks:gmatch("%S+") do
		printNetworkInterfaceValues(network)
	end
	luci.http.write([[</table>]])
end

function printNetworkInterfaceValues(network)
	-- get physical interface name
	ifname = luci.sys.exec(". \"${IPKG_INSTROOT:-}/lib/functions.sh\"; include \"${IPKG_INSTROOT:-}/lib/network\"; scan_interfaces; config_get "..network.." ifname")
	ifname = ifname.gsub(ifname, "%c+", "")
	if not ifname or ifname == "" then return end
	-- skip alias and disabled interfaces
	if luci.sys.exec("ip link show "..ifname.." 2>/dev/null | grep UP") == "" then return end
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
						luci.i18n.translate("Interface") .. "</th><th>" ..
						luci.i18n.translate("SSID") .. "</th><th></th></tr>")
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
			luci.http.write([[</table>]])
		end
	end
end

function status_neighbors()
	luci.http.prepare_content("text/plain")
	-- TODO: Verschiebung der Ermittlung direkter Nachbarn in eine shell-Funktion
	output = luci.sys.exec("echo /links | on-function request_olsrd_txtinfo | awk 'BEGIN {out=0} { if (out == 1 \&\& \$0 != \"\") printf \"<tr><td><a href=\\\"http://\"$2\"\\\">\"\$2\"</a></td><td>\"\$4\"</td><td>\"\$5\"</td><td>\"\$6\"</td></tr>\"; if (\$1 == \"Local\") out = 1;}'")
	if output ~= "" then
		luci.http.write('<table class="status_page_table"><tr><th>' ..
			luci.i18n.translate("IP Address") .. "</th><th>" ..
			'<abbr title="' .. luci.i18n.translate("Link-Quality: how many of your packets were received by your neighbor") .. '">LQ</abbr>' ..
			'</th><th>' ..
			'<abbr title="' .. luci.i18n.translate("Neighbor-Link-Quality: how many of your test-packets did reach your neighbor") .. '">NLQ</abbr>' ..
			'</th><th>' ..
			'<abbr title="' .. luci.i18n.translate("Expected Transmission Count: Quality of the Connection to the Gateway reagrding OLSR") .. '">ETX</abbr>' ..
			"</th></tr></class>")
		luci.http.write(output)
	end
end


function status_issues()
	luci.http.prepare_content("text/plain")
	local warnings = on_function("get_potential_error_messages")
	local result = ""
	if warnings and (warnings ~= "") then
		result = result .. '<a title="' .. luci.util.pcdata(warnings) .. '">'
		    .. luci.i18n.translate("There are indications for possible technical issues.") .. "</a><br/>"
		local support_contact = get_default_value("on-core", "support_contact")
		result = result .. luci.i18n.translatef('You may want to send a <a href="%s">report</a> to the Opennet community (%s).', luci.dispatcher.build_url("opennet", "opennet_1", 'bericht'), '<a href="mailto:' .. support_contact ..'">' .. support_contact .. '</a>')
	else
		result = result .. luci.i18n.translate("There seem to be no issues.")
	end
	luci.http.write(result)
end

