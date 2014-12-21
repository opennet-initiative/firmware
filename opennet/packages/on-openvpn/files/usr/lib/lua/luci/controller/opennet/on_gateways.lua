--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2014 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.on_gateways", package.seeall)
require("luci.model.opennet.funcs")

function index()
	luci.i18n.loadc("on_base")
	local i18n = luci.i18n.string
	
	local page = entry({"opennet", "opennet_2", "vpn_gateways"}, call("action_vpn_gateways"), i18n("VPN Gateways"), 1)
	page.i18n  = "on_gateways"
	page.css   = "opennet.css"

	entry({"opennet", "opennet_2", "vpn_gateway_info"}, call("gateway_info"), nil).leaf = true
	entry({"opennet", "opennet_2", "vpn_gateway_list"}, call("gateway_list")).leaf = true
end


function action_vpn_gateways()
	local move_up = luci.http.formvalue("move_up")
	local move_down = luci.http.formvalue("move_down")
	local move_top = luci.http.formvalue("move_top")
	local delete_service = luci.http.formvalue("delete_service")
	local disable_service = luci.http.formvalue("disable_service")
	local enable_service = luci.http.formvalue("enable_service")
	local reset_offset = luci.http.formvalue("reset_offset")
	local reset_counter = luci.http.formvalue("reset_counter")
	
	if move_up then
		on_function("move_service_up", {move_up, "gw", "ugw"})
	elseif move_down then
		on_function("move_service_down", {move_down, "gw", "ugw"})
	elseif move_top then
		on_function("move_service_top", {move_top, "gw", "ugw"})
		on_function("select_mig_connection", {move_top})
	elseif delete_service then
		on_function("delete_service", {delete_service})
	elseif disable_service then
		set_service_value(disable_service, "disabled", "1")
	elseif enable_service then
		delete_service_value(enable_service, "disabled")
	elseif reset_offset then
		delete_service_value(reset_offset, "offset")
	elseif reset_counter then
		on_function("reset_all_mig_connection_test_timestamps")
	end


	-- optional koennten wir pruefen, ob ueberhaupt eine der Verbindungen einen Offset verwendet
	local offset_exists = true
	local show_more_info = luci.http.formvalue("show_more_info")

	luci.template.render("opennet/on_gateways", { gateway_list = gateway_list, show_more_info = show_more_info, offset_exists = offset_exists })
end


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/opennet_2/vpn_gateway_info/gw_openvpn_192_168_0_254_1600_udp
-- das Resultat ist ein json-formatierter Datensatz mit den Informationen eines Gateways
function gateway_info(service_name)
	-- wir lesen "status" als string ein, um die drei moeglichen Werte (y/n/leer) zu unterscheiden
	local info = parse_csv_service(service_name, {host="string|value|host", port="number|value|port",
			status="string|value|status", active="bool|function|is_openvpn_service_active",
			disabled="bool|value|disabled|false", distance="number|value|distance",
			hop_count="number|value|hop_count|0", offset="number|value|offset|0",
			download="number|detail|download", upload="number|detail|upload",
			age="number|function|get_mig_connection_test_age"})
	if info then
	    luci.http.prepare_content("application/json")
	    luci.http.write_json(info)
	else
	    luci.http.status(404, "No such device")
	end
end

-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/opennet_2/vpn_gateway_list
function gateway_list(service_name)
	local services = on_function("get_sorted_services", {"gw", "ugw"})
	local line
	local result = {}
	for line in string.gmatch(services, "[^\n]+") do
		table.insert(result, line)
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end
