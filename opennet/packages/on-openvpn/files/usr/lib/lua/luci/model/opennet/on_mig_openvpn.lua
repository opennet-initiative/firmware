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
require("luci.i18n")
require("luci.model.opennet.urls")


function action_on_openvpn()
	if luci.http.formvalue("restartvpn") then os.execute("vpn_status restart opennet_user") end
	
	local on_errors = {}

	-- sofortiges Ende, falls der Upload erfolgreich verlief
	if process_csr_submission("user", on_errors) then return end

	-- Zertifikatverwaltung
	local cert_result = process_openvpn_certificate_form("user")

	check_and_warn_module_state("on-openvpn", on_errors)

	luci.template.render("opennet/on_openvpn", {
		on_errors=on_errors,
		certstatus=cert_result.certstatus,
		openssl=cert_result.openssl,
		force_show_uploadfields=cert_result.force_show_uploadfields,
		force_show_generatefields=cert_result.force_show_generatefields
	})
end


function action_vpn_gateways()
	local reset_connection_test_timestamps = luci.http.formvalue("reset_connection_test_timestamps")
	local on_errors = {}
	
	check_and_warn_module_state("on-openvpn", on_errors)

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


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/mig_openvpn/status/vpn_gateway_info/gw_openvpn_192_168_0_254_1600_udp
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


-- URL zum Testen: http://172.16.0.1/cgi-bin/luci/opennet/mig_openvpn/status/vpn_gateway_list
function gateway_list()
	sys = require("luci.sys")
	local services = sys.exec("on-function get_services gw | on-function sort_services_by_priority")
	local result = line_split(services)
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end


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

	luci.http.write([[<table><tr><td width="50%"><div class="opennet-bool" status="]] .. bool_to_yn(tunnel_active) .. [[" /></td><td>]])
	if tunnel_active then
		luci.http.write(luci.i18n.translate("Tunnel active"))
	else
		if is_tunnel_starting() then
			luci.http.write(luci.i18n.translate("Tunnel starting"))
		else
			luci.http.write(luci.i18n.translate("Tunnel inactive"))
		end
	end
	luci.http.write([[</td></tr></table>]])
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


function status_mig_openvpn()
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
					on_url("mig_openvpn", "zertifikat"))
		end
		result = luci.i18n.translate('The VPN-Tunnel is not active,') .. " " .. result
	end
	luci.http.write(result)
end
