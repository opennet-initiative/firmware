--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.on_portmapping", package.seeall)

function index()
	luci.i18n.loadc("on_base")
	local i18n = luci.i18n.string
	local page = entry({"opennet", "opennet_2", "portmapping"}, call("action_portmapping"), i18n("Port-Mapping"), 2)
	page.i18n = "on_portmapping"
	page.css = "opennet.css"
end

function action_portmapping()
	local uci = require "luci.model.uci"
	local cursor = uci.cursor()
	
	zones = { "on_vpn", "opennet", "local", "wan" }
	
	local zone
	for index = 1, #zones do if  luci.http.formvalue(zones[index]) then zone = zones[index] end end

	local del_section
	for index = 1, #zones do del_section = luci.http.formvalue(zones[index].."_del_section") if del_section then break end end
	
	local new_src_dport = luci.http.formvalue("src_dport")
	local new_dest_ip = luci.http.formvalue("dest_ip")
	local new_dest_port = luci.http.formvalue("dest_port")
	
	
	if del_section then
		cursor:delete("firewall", del_section)
		cursor:commit("firewall")
	elseif zone then
		cursor:section("firewall", "redirect", nil, { src = zone, proto = 'tcpudp', src_dport = new_src_dport, dest_ip = new_dest_ip, dest_port = new_dest_port, target = 'DNAT' })
		cursor:commit("firewall")
		cursor:unload("firewall")
	end

	luci.template.render("opennet/on_portmapping", { show_more_info = show_more_info })
end
