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
	luci.i18n.loadc("on-openvpn")
	
	local page = entry({"opennet", "opennet_2", "vpn_gateways"}, call("action_vpn_gateways"), luci.i18n.translate("VPN Gateways"), 1)
	page.i18n = "on_gateways"
	page.css = "opennet.css"

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
	local reset_connection_test_timestamps = luci.http.formvalue("reset_connection_test_timestamps")
	local new_gateway = luci.http.formvalue("new_gateway")
	
	if move_up or move_down or move_top or delete_service or disable_service or enable_service then
		if move_up then
			on_function("move_service_up", {move_up, "gw", "ugw"})
		elseif move_down then
			on_function("move_service_down", {move_down, "gw", "ugw"})
		elseif move_top then
			on_function("move_service_top", {move_top, "gw", "ugw"})
		elseif delete_service then
			on_function("delete_service", {delete_service})
		elseif disable_service then
			set_service_value(disable_service, "disabled", "1")
		elseif enable_service then
			delete_service_value(enable_service, "disabled")
		elseif reset_offset then
			delete_service_value(reset_offset, "offset")
		end
		-- Forciere sofortigen Wechsel zum aktuell besten Gateway.
		-- Dies ist nicht immer notwendig - aber sofortige Änderungen
		-- entsprechen wahrscheinlich der Erwartungshaltung des Nutzenden.
		on_function("find_and_select_best_gateway", {"true"})
	elseif reset_connection_test_timestamps then
		on_function("reset_all_mig_connection_test_timestamps")
	elseif new_gateway then
		local new_gateway_ip = luci.http.formvalue("new_gateway_ip")
		local new_gateway_port = luci.http.formvalue("new_gateway_port") or "1600"
		on_function("notify_service", {"gw", "openvpn", new_gateway_ip, new_gateway_port, "udp", "/", "", "manual"})
	end

	local show_more_info = luci.http.formvalue("show_more_info")
	luci.template.render("opennet/on_gateways", { show_more_info=show_more_info })
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
			age="number|function|get_mig_connection_test_age", source="string|value|source"})
	if info then
		luci.http.prepare_content("application/json")
		luci.http.write_json(info)
	else
		luci.http.status(404, "No such device")
	end
end


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/opennet_2/vpn_gateway_list
function gateway_list()
	local services = luci.sys.exec("on-function get_services gw ugw | on-function sort_services_by_priority")
	local result = line_split(services)
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end
