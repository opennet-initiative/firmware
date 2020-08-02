--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
]]--

module("luci.model.opennet.on_captive_portal", package.seeall)

require("luci.model.opennet.funcs")


function action_on_captive_portal()
	local on_errors = {}
	check_and_warn_module_state("on-captive-portal", on_errors)
	-- Umgebungsprüfungen
	if not on_bool_function("captive_portal_has_devices") then
		-- Warne den Nutzer, falls dem 'free'-Netzwerk-Interface kein physisches Gerät zugeordnet ist.
		local netdev = on_function("get_variable", {"NETWORK_FREE"})
		table.insert(on_errors, luci.i18n.translatef('You need to <a href="%s">attach a physical network device</a> to the \'%s\' interface in order to enable the Hotspot feature.', luci.dispatcher.build_url("admin", "network", "network", netdev) .. "?tab.network." .. netdev .. "=physical", netdev))
	end
	luci.template.render("opennet/on_captive_portal", {on_errors=on_errors})
end


function status_captive_portal()
	luci.http.prepare_content("text/plain")
	local status
	local free_device = on_function("get_variable", {"NETWORK_FREE"})
	if on_bool_function("is_captive_portal_running") then
		-- die Funktion ist aktiv - melde Zustand
		status = luci.i18n.translatef("Connected clients: %s",
			on_function("get_captive_portal_client_count"))
	elseif on_bool_function("captive_portal_has_devices") then
		if is_string_empty(on_function("get_active_mig_connections")) then
			status = luci.i18n.translate("Disabled: the VPN tunnel is not running.")
		else
			status = luci.i18n.translatef("Disabled: failed to enable the '%s' network interface.", free_device)
		end
	else
		status = luci.i18n.translatef("Disabled: no network device is assigned to the '%s' zone.", free_device)
	end
	luci.http.write(status)
end
