--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
require("luci.model.opennet.funcs")
module("luci.controller.opennet.on_portmapping", package.seeall)

function index()
	luci.i18n.loadc("on-core")
	local page = entry({"opennet", "opennet_2", "portmapping"}, call("action_portmapping"), luci.i18n.translate("Port-Mapping"), 2)
	page.i18n = "on_portmapping"
	page.css = "opennet.css"
end

function action_portmapping()
	local uci = require "luci.model.uci"
	local cursor = uci.cursor()
	
	zones = {}
	if on_bool_function("is_function_available", {"get_active_mig_connections"}) then
		table.insert(zones, on_function("get_variable", {"ZONE_TUNNEL"}))
	end
	table.insert(zones, on_function("get_variable", {"ZONE_MESH"}))
	table.insert(zones, on_function("get_variable", {"ZONE_LOCAL"}))
	table.insert(zones, on_function("get_variable", {"ZONE_WAN"}))
	
	local zone
	for index = 1, #zones do if luci.http.formvalue(zones[index]) then zone = zones[index] end end

	local del_section
	for index = 1, #zones do del_section = luci.http.formvalue(zones[index].."_del_section") if del_section then break end end
	
	local new_src_dport = luci.http.formvalue("src_dport")
	local new_dest_ip = luci.http.formvalue("dest_ip")
	local new_dest_port = luci.http.formvalue("dest_port")
	
	
	if del_section then
		cursor:delete("firewall", del_section)
	elseif zone then
		cursor:section("firewall", "redirect", nil, { src = zone, proto = 'tcpudp', src_dport = new_src_dport, dest_ip = new_dest_ip, dest_port = new_dest_port, target = 'DNAT' })
	end
	if del_section or zone then
		cursor:commit("firewall")
		cursor:unload("firewall")
		-- Neustart der firewall ausloesen
		luci.sys.exec("reload_config")
	end

	luci.template.render("opennet/on_portmapping", { show_more_info = show_more_info })
end
