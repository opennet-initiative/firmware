--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
]]--

module("luci.controller.opennet.on_captive_portal", package.seeall)
require("luci.model.opennet.funcs")


function index()
	luci.i18n.loadc("on-captive-portal")

	local page = entry({"opennet", "opennet_2", "captive_portal"},
		call("action_on_captive_portal"),
		luci.i18n.translate("Public Hotspot"), 7)
	page.i18n = "on_captive_portal"
	page.css = "opennet.css"
end


function action_on_captive_portal()
	local on_errors = {}
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
		on_function("captive_portal_apply")
	end
	-- Warne den Nutzer, falls dem 'free'-Netzwerk-Interface kein physisches Gerät zugeordnet ist.
	if not on_bool_function("captive_portal_has_devices") then
		table.insert(on_errors, luci.i18n.translate("You need to attach a physical network device to the 'free' interface in order to enable the Hotspot feature."))
	end
	luci.template.render("opennet/on_captive_portal", {
		portal_name=on_function("captive_portal_get_property", {"name"}),
		portal_url=on_function("captive_portal_get_property", {"url"}),
		on_errors=on_errors,
	})
end
