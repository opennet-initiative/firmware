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
	local reset_connection_test_timestamps = luci.http.formvalue("reset_connection_test_timestamps")
	local on_errors = {}
	
	-- Neuen Dienst hinzufügen
	local service_result = process_add_service_form()
	if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end

	-- Dienst-Aktionen ausführen
	service_result = process_service_action_form("gw")
	if service_result == true then
		-- Irgendeine Änderung der Reihenfolge wurde vorgenommen.
		-- Forciere sofortigen Wechsel zum aktuell besten Gateway.
		-- Dies ist nicht immer notwendig - aber sofortige Änderungen
		-- entsprechen wahrscheinlich der Erwartungshaltung des Nutzenden.
		on_function("find_and_select_best_gateway", {"true"})
	elseif service_result ~= false then
		-- ungleich true und ungleich false: es ist eine Fehlermeldung
		table.insert(on_errors, service_result)
	end

	if reset_connection_test_timestamps then
		on_function("reset_all_mig_connection_test_timestamps")
	end

	luci.template.render("opennet/on_gateways", { on_errors=on_errors })
end


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/opennet_2/vpn_gateway_info/gw_openvpn_192_168_0_254_1600_udp
-- das Resultat ist ein json-formatierter Datensatz mit den Informationen eines Gateways
function gateway_info(service_name)
	-- wir lesen "status" als string ein, um die drei moeglichen Werte (y/n/leer) zu unterscheiden
	local info = parse_csv_service(service_name, {host="string|value|host", port="number|value|port",
			status="string|value|status", connection_state="string|function|get_openvpn_service_state",
			disabled="bool|value|disabled|false", distance="number|value|distance",
			hop_count="number|value|hop_count|0", offset="number|value|offset|0",
			wan_speed_download="number|detail|download", wan_speed_upload="number|detail|upload",
			age="number|function|get_mig_connection_test_age", source="string|value|source"})
	if info then
		luci.http.prepare_content("application/json")
		luci.http.write_json(info)
	else
		luci.http.status(404, "No such service")
	end
end


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/opennet_2/vpn_gateway_list
function gateway_list()
	local services = luci.sys.exec("on-function get_services gw | on-function sort_services_by_priority")
	local result = line_split(services)
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end
