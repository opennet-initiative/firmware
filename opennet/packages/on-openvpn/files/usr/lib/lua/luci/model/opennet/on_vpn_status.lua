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
require("luci.i18n")
require("nixio.fs")


-- eine Tunnel-VPN-Verbindung scheint aufgebaut zu sein
function is_tunnel_active()
	return on_function("get_active_mig_connections") ~= ""
end


-- ein Tunnel-VPN-Prozess laeuft (eventuell steht die Verbindung noch nicht)
function is_tunnel_starting()
	return on_function("get_starting_mig_connections") ~= ""
end


function on_vpn_status_label()
	local tunnel_active = is_tunnel_active()
	luci.http.prepare_content("text/plain")

	luci.http.write([[<tr>]])
	luci.http.write([[<td width="10%" ><div class="ugw-centralip" status="]])
	if tunnel_active then
		luci.http.write([[ok]])
	else
		luci.http.write([[false]])
	end
	luci.http.write([[">&#160;</div></td>]])
	luci.http.write([[<td><h4 class="on_sharing_status-title">]])
	if tunnel_active then
		luci.http.write(luci.i18n.translate("Tunnel active"))
	else
		if is_tunnel_starting() then
			luci.http.write(luci.i18n.translate("Tunnel starting"))
		else
			luci.http.write(luci.i18n.translate("Tunnel inactive"))
		end
	end
	luci.http.write([[</h4></td></tr>]])
end

function on_vpn_status_form()
	luci.http.prepare_content("text/plain")
	luci.http.write('<input class="cbi-button" type="submit" name="openvpn_restart" title="')
	if is_tunnel_active() or is_tunnel_starting() then
		luci.http.write(luci.i18n.translate("restart VPN Tunnel") .. '" value="' .. luci.i18n.translate("restart VPN Tunnel"))
	else
		luci.http.write(luci.i18n.translate("start VPN Tunnel") .. '" value="' .. luci.i18n.translate("start VPN Tunnel"))
	end
	luci.http.write('" />')
end


function status_mig_connection()
	luci.http.prepare_content("text/plain")
	local services = line_split(on_function("get_active_mig_connections"))
	local result
	function get_service_host(service_name)
		return get_service_value(service_name, "host")
	end
	local remotes = string_join(map_table(services, get_service_host), ", ")
	if remotes then
		result = luci.i18n.translatef('Active VPN-Tunnel: %s', remotes)
	else
		if on_bool_function("has_mig_openvpn_credentials") then
			-- Zertifikat vorhanden - syslog?
			result = luci.i18n.translatef('Check the <a href="%s">System Log</a> for details.',
					luci.dispatcher.build_url("admin", "status", "syslog"))
		else
			-- das Zertifikat fehlt
			result = luci.i18n.translatef('<a href="%s">A certificate is required</a>.',
					luci.dispatcher.build_url("opennet", "opennet_1", "vpn_tunnel"))
		end
		result = luci.i18n.translate('The VPN-Tunnel is not active,') .. " " .. result
	end
	luci.http.write(result)
end

