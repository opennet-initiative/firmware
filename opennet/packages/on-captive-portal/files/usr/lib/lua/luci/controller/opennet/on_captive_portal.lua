--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
]]--

module("luci.controller.opennet.on_captive_portal", package.seeall)


function index()
	require("luci.i18n")
	require("luci.model.opennet.urls")
	local i18n = luci.i18n.translate
	luci.i18n.loadc("on-captive-portal")

	require("luci.model.opennet.on_captive_portal")
	on_entry({"zugangspunkt"}, call("action_on_captive_portal"), i18n("Public Hotspot"), 80, "on_captive_portal").leaf = 1

	-- Einbindung in die Status-Seite mit dortigem Link
	on_entry({"status", "zugangspunkt"}, call("action_captive_portal")).leaf = true
end
