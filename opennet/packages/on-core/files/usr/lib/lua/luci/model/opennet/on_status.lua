--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--


local uci = require "luci.model.uci"
local cursor = uci.cursor()
require("luci.sys")
require("luci.model.opennet.funcs")


function get_firmware_title()
	local on_version = on_function("get_on_firmware_version")
	local on_id = cursor:get("on-core", "settings", "on_id")
	local client_cn = nil
	if on_bool_function("is_function_available", {"get_client_cn"}) then
		client_cn = on_function("get_client_cn")
	end
	local result = luci.i18n.translatef("Opennet Firmware version %s", on_version)
	local suffix
	if on_id then
		suffix = luci.i18n.translatef("AP %s", on_id)
	end
	if not is_string_empty(client_cn) then
		suffix = luci.i18n.translatef("CN %s", client_cn)
	end
	if suffix then
		return result .. " -- " .. suffix
	else
		return result
	end
end


function status_network()
	luci.http.prepare_content("text/plain")
	print_zone_info("ZONE_LOCAL")
	print_zone_info("ZONE_MESH")
	print_zone_info("ZONE_WAN")
	if on_bool_function("is_function_available", {"captive_portal_get_or_create_config"}) then
		print_zone_info("ZONE_FREE")
	end
end


function print_zone_info(zone_variable_name)
	local zone_name = on_function("get_variable", {zone_variable_name})
	local network_interfaces = on_function("get_zone_interfaces", {zone_name})
	if not is_string_empty(network_interfaces) then
		local title
		local interface_name
		if zone_variable_name == "ZONE_LOCAL" then
			title = luci.i18n.translate("These addresses are used locally and usually protected by your firewall. Connections to the Internet are routed through your VPN-Tunnel if it is active.")
			interface_name = luci.i18n.translate("LOCAL")
		elseif zone_variable_name == "ZONE_MESH" then
			title = luci.i18n.translate("Opennet-Addresses are usually given to the Access-Point based on your Opennet-ID. These are the interfaces on which OLSR is running.")
			interface_name = luci.i18n.translate("OPENNET")
		elseif zone_variable_name == "ZONE_WAN" then
			title = luci.i18n.translate("The WAN Interface is used for your local Internet-Connection (for instance DSL). It will be used for your local traffic and to map Usergateways into Opennet = Share your Internet Connection if you choose to.")
			interface_name = luci.i18n.translate("WAN")
		elseif zone_variable_name == "ZONE_FREE" then
			title = luci.i18n.translate("The FREE Interface will be used to publicly share Opennet with Wifidog.")
			interface_name = luci.i18n.translate("FREE")
		end
		local zone_info = get_interfaces_info_table(network_interfaces, zone_name)
		if not is_string_empty(zone_info) then
			luci.http.write('<h3><abbr title="' .. title .. '">' .. interface_name .. '</abbr>&nbsp;'
				.. luci.i18n.translate('IP Address(es):') .. '</h3>')
			luci.http.write(zone_info)
		end
	end
end


function get_interfaces_info_table(networks, zoneName)
	local header = [[<table id="network_table_]] .. zoneName.. [[" class="status_page_table"><tr>]]
	        .. [[<th>]] ..  luci.i18n.translate("Interface") .. [[</th>]]
		.. [[<th>]] .. luci.i18n.translate("IP") .. [[</th>]]
		.. [[<th>]] .. luci.i18n.translate("IPv6") .. [[</th>]]
		.. [[<th>]] .. luci.i18n.translate("MAC") ..  [[</th>]]
	        .. [[</tr>]]
	local content = ""
	for network in networks:gmatch("%S+") do
		content = content .. (get_network_interface_table_row(network) or "")
	end
	if is_string_empty(content) then
		-- keine Tabelle im Fall von fehlenden Interfaces
		return ""
	else
		return header .. content .. [[</table>]]
	end
end


-- address_type: inet, inet6, link/ether (siehe "ip address")
function get_interface_addresses(network_interface, address_type)
	local output = luci.sys.exec([[ip address show label ']] .. network_interface .. [[']]
		.. [[ | awk '{ if ($1 == "]] .. address_type .. [[") print $2; }']])
	return line_split(trim_string(output))
end


function get_network_interface_table_row(network_interface)
	-- ignoriere abgeschaltete Interfaces
	if not on_bool_function("is_interface_up", {network_interface}) then return nil end
	local ifname = on_function("get_device_of_interface", {network_interface})
	local ip4_address = string_join(get_interface_addresses(ifname, "inet"), [[<br/>]])
	local ip6_address = string_join(get_interface_addresses(ifname, "inet6"), [[<br/>]])
	local mac_address = string_join(get_interface_addresses(ifname, "link/ether"), [[<br/>]])
	return [[<tr><td>]] .. ifname .. [[</td>]]
		.. [[<td>]] .. ip4_address .. [[</td>]]
		.. [[<td>]] .. ip6_address .. [[</td>]]
		.. [[<td>]] .. mac_address .. [[</td></tr>]]
end


function status_neighbors()
	luci.http.prepare_content("text/plain")
	local neighbour_info = on_function("get_olsr_neighbours")
	local response = ""
	if not is_string_empty(neighbour_info) then
		-- Tabelle in Tabelle (aussen: Details + Karte, innen: Details)
		response = response .. '<table border="0"><tr><td>'
		response = response .. '<table class="status_page_table"><tr>' ..
			'<th>' ..  luci.i18n.translate("IP Address") .. "</th>" ..
			'<th><abbr title="' .. luci.i18n.translate("Link-Quality: how many of your packets were received by your neighbor") .. '">LQ</abbr></th>' ..
			'<th><abbr title="' .. luci.i18n.translate("Neighbor-Link-Quality: how many of your test-packets did reach your neighbor") .. '">NLQ</abbr></th>' ..
			'<th><abbr title="' .. luci.i18n.translate("Expected Transmission Count: Quality of the Connection to the Gateway reagrding OLSR") .. '">ETX</abbr></th>' ..
			'<th><abbr title="' .. luci.i18n.translate("Number of routes via this neighbour") .. '">Routes</abbr></th>' ..
			'</tr>'
		for _, line in pairs(line_split(neighbour_info)) do
			local info = space_split(line)
			-- keine Ausgabe, falls nicht mindestens fuenf Felder geparst wurden
			-- (die Ursache fuer weniger als fuenf Felder ist unklar - aber es kam schon vor)
			if info[5] then
				response = response .. '<tr>' ..
					'<td><a href="http://' .. info[1] .. '/">' .. info[1] .. '</a></td>' ..
					'<td>' .. info[2] .. '</td>' ..
					'<td>' .. info[3] .. '</td>' ..
					'<td>' .. info[4] .. '</td>' ..
					'<td style="text-align:right">' .. info[5] .. '</td>' ..
					'</tr>'
			end
		end
		response = response .. '</table>'
		-- Karte einblenden
		response = response .. '</td><td>' ..
		                '<iframe scrolling="no" width="400px" height="250px" src="https://map.opennet-initiative.de/?ip=' ..
				on_function("get_main_ip") .. '"></iframe></td></tr></table>'
	else
		response = response .. '<div class="errorbox">' ..
			luci.i18n.translate("Currently there are no known routing neighbours.") .. " " ..
			luci.i18n.translatef('Maybe you want to connect to a local <a href="%s">wifi peer</a>.',
				luci.dispatcher.build_url("admin", "network", "wireless")) ..
			'</div>'
	end
	luci.http.write(response)
end


function status_issues()
	luci.http.prepare_content("text/plain")
	local result = ""
	local warnings = on_function("get_potential_error_messages", {"30"})
	if not is_string_empty(warnings) then
		result = result .. '<a title="' .. luci.util.pcdata(warnings) .. '">'
		    .. luci.i18n.translate("There are indications for possible technical issues.") .. "</a><br/>"
		local support_contact = get_default_value("on-core", "support_contact")
		result = result .. luci.i18n.translatef('You may want to send a <a href="%s">report</a> to the Opennet community (%s).', on_url("basis", 'bericht'), '<a href="mailto:' .. support_contact ..'">' .. support_contact .. '</a>')
	end
	if on_bool_function("has_flash_or_filesystem_error_indicators") then
		if result ~= "" then result = result .. "<br/>" end
		result = result .. luci.i18n.translate("There are indications for a possibly broken flash memory chip or a damaged filesystem.")
	end
	if result == "" then
		result = luci.i18n.translate("There seem to be no issues.")
	end
	luci.http.write(result)
end


--- @fn get_module_info()
--- @brief Liefere den aktuellen Zustand der installierten Module zurück
function status_modules()
	local enabled = {}
	local disabled = {}
	local missing = {}
	for _, modname in ipairs(line_split(on_function("get_on_modules"))) do
		if on_bool_function("is_on_module_installed_and_enabled", {modname}) then
			table.insert(enabled, modname)
		elseif on_bool_function("is_package_installed", {modname}) then
			table.insert(disabled, modname)
		elseif on_bool_function("was_on_module_installed_before", {modname}) then
			table.insert(missing, modname)
		end
	end
	luci.http.prepare_content("text/plain")
	result = ""
	if not table_is_empty(enabled) then
		result = result .. luci.i18n.translatef("Active: %s", string_join(enabled, ", ")) .. "<br/>"
	end
	if not table_is_empty(disabled) then
		result = result .. luci.i18n.translatef("Disabled: %s", string_join(disabled, ", ")) .. "<br/>"
	end
	if not table_is_empty(missing) then
		result = result .. '<div class="errorbox">'
			.. luci.i18n.translatef("Previously installed modules: %s", string_join(missing, ", ")) .. '<br/>'
			.. luci.i18n.translate("Recommended action") .. ': '
			.. '<a href="' .. on_url("basis", "module") .. '?install=' .. string_join(missing, ",") .. '">'
			.. luci.i18n.translate("Install missing modules")
			.. '</a></div>'
	end
	luci.http.write(result)
end
