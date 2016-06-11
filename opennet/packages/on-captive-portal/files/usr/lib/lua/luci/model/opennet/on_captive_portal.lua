--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
]]--


require("luci.model.opennet.funcs")


function action_on_captive_portal()
	local on_errors = {}
	check_and_warn_module_state("on-captive-portal", on_errors)
	if luci.http.formvalue("save") then
		local captive_portal_node_name = parse_string_pattern(luci.http.formvalue("captive_portal_node_name"), "a-zA-Z0-9:./ %-_")
		if captive_portal_node_name then
			on_function("captive_portal_set_property", {"name", captive_portal_node_name})
		else
			table.insert(on_errors, luci.i18n.translate("Ignoring the node name due to invalid characters."))
		end
		local captive_portal_url = parse_string_pattern(luci.http.formvalue("captive_portal_url"), "%a%d:./%%_%-")
		if captive_portal_url then
			on_function("captive_portal_set_property", {"url", captive_portal_url})
		else
			table.insert(on_errors, luci.i18n.translate("Ignoring the URL due to invalid characters."))
		end
		on_function("apply_changes", {"on-captive-portal"})
	end
	-- Umgebungsprüfungen
	if not on_bool_function("captive_portal_has_devices") then
		-- Warne den Nutzer, falls dem 'free'-Netzwerk-Interface kein physisches Gerät zugeordnet ist.
		local netdev = on_function("get_variable", {"NETWORK_FREE"})
		table.insert(on_errors, luci.i18n.translatef('You need to <a href="%s">attach a physical network device</a> to the \'%s\' interface in order to enable the Hotspot feature.', luci.dispatcher.build_url("admin", "network", "network", netdev) .. "?tab.network." .. netdev .. "=physical", netdev))
	end
	if on_bool_function("captive_portal_uses_wifi_only_bridge") then
		-- Warne den Nutzer, falls das 'free'-Netzwerk-Interface als Bridge ausschließlich aus Wifi-Interfaces besteht
		local netdev = on_function("get_variable", {"NETWORK_FREE"})
		table.insert(on_errors, luci.i18n.translatef('You may want to <a href="%s">reconfigure</a> the \'%s\' interface. Currently a bridge consisting of multiple wifi interfaces (and nothing else) is configured. This setup is known to cause problems with openwrt. Please add a non-wifi interface or disable bridging.', luci.dispatcher.build_url("admin", "network", "network", netdev) .. "?tab.network." .. netdev .. "=physical", netdev))
	end
	luci.template.render("opennet/on_captive_portal", {
		portal_name=on_function("captive_portal_get_property", {"name"}),
		portal_url=on_function("captive_portal_get_property", {"url"}),
		on_errors=on_errors,
	})
end


function action_captive_portal()
	luci.http.prepare_content("text/plain")
	local status
	local free_device = on_function("get_variable", {"NETWORK_FREE"})
	if on_bool_function("is_captive_portal_running") then
		-- die Funktion ist aktiv - melde Zustand
		status = luci.i18n.translatef("Connected clients: %d | Hotspot name: %s",
				on_function("get_captive_portal_client_count"),
				on_function("captive_portal_get_property", {"name"}))
	elseif on_bool_function("captive_portal_uses_wifi_only_bridge") then
		status = luci.i18n.translatef("Warning: the Captive Portal interface (%s) seems to be a bridge containing only wifi devices. This setup is known to cause problems: you should add a non-wifi device or disable bridging.", free_device)
	elseif on_bool_function("captive_portal_has_devices") then
		if on_function("get_active_mig_connections") ~= "" then
			if on_bool_function("is_interface_up", {free_device}) then
				status = luci.i18n.translate("Disabled: failed to start the 'nodogsplash' service.")
			else
				status = luci.i18n.translatef("Disabled: failed to enable the '%s' network interface.", free_device)
			end
		else
			status = luci.i18n.translate("Disabled: the VPN tunnel is not running.")
		end
	else
		status = luci.i18n.translatef("Disabled: no network device is assigned to the '%s' zone.", free_device)
	end
	luci.http.write(status)
end
