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

function on_vpn_status_label()
	local SYSROOT = os.getenv("LUCI_SYSROOT")
	-- SYSROOT is only used for local testing (make runhttpd in luci tree)
	if not SYSROOT then SYSROOT = "" end
	local tunnel_active = nixio.fs.access(SYSROOT.."/tmp/openvpn_msg.txt")
	-- local tunnel_starting = nixio.fs.access(SYSROOT.."/tmp/run/openvpn-opennet_user.pid")

	local tunnel_starting = (luci.sys.exec("kill -0 $(cat /var/run/openvpn-opennet_user.pid 2>/dev/null) 2>/dev/null && echo -n ok") == "ok")

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
		luci.http.write(luci.i18n.string([[Tunnel active]]))
	elseif tunnel_starting then
		luci.http.write(luci.i18n.string([[Tunnel starting]]))
	else
		luci.http.write(luci.i18n.string([[Tunnel inactive]]))
	end
	luci.http.write([[</h4></td></tr>]])
end

function on_vpn_status_form()
	local SYSROOT = os.getenv("LUCI_SYSROOT")
	-- SYSROOT is only used for local testing (make runhttpd in luci tree)
	if not SYSROOT then SYSROOT = "" end
	local tunnel_active = nixio.fs.access(SYSROOT.."/tmp/openvpn_msg.txt")
	local tunnel_starting = nixio.fs.access(SYSROOT.."/tmp/run/openvpn-opennet_user.pid")
	luci.http.prepare_content("text/plain")
	luci.http.write([[<input class="cbi-button" type="submit" name="openvpn_restart" title="]])
	if tunnel_active or tunnel_starting then
		luci.http.write(luci.i18n.string([[restart VPN Tunnel]])..[[" value="]]..luci.i18n.string([[restart VPN Tunnel]]))
	else
		luci.http.write(luci.i18n.string([[start VPN Tunnnel]])..[[" value="]]..luci.i18n.string([[start VPN Tunnel]]))
	end
	luci.http.write([[" />]])
end

