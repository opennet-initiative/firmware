--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--
module("luci.controller.opennet.on_core", package.seeall)


function index()
	local i18n = luci.i18n.translate
	require("luci.model.opennet.urls")

	-- Umleitung der top-level Node (die Startseite) zur Node "opennet"
	local page = node()
	page.target = on_alias()

	-- Definition der Opennet-Startseite
	page = on_entry_no_auth({}, nil, i18n("Opennet"), 35)
	page.target = on_alias("status")

	-- die Status-Seite (/status)
	on_entry_no_auth({"status"}, template("opennet/on_status"), i18n("Status"), 10)

	-- Quellen fuer die Inhalte der Status-Seite
	require ("luci.model.opennet.on_status")
	on_entry_no_auth({"status", "neighbors"}, call("status_neighbors")).leaf = true
	on_entry_no_auth({"status", "network"}, call("status_network")).leaf = true
	on_entry_no_auth({"status", "modules"}, call("status_modules")).leaf = true
	on_entry_no_auth({"status", "issues"}, call("status_issues")).leaf = true
	on_entry_no_auth({"status", "firmware_update_info"}, call("status_firmware_update_info")).leaf = true


	-- Grundlegende Einstellungen (/basis)
	require "luci.model.opennet.base"
	require "luci.model.opennet.funcs"
	page = on_entry({"basis"}, nil, i18n("Base"), 20)
	page.target = on_alias("basis", "network")

	page = on_entry({"basis", "network"}, nil, i18n("Network"), 20)
	page.target = on_alias("basis", "network", "opennet_id")
	on_entry({"basis", "network", "opennet_id"}, call("action_network"), i18n("Opennet ID"))
	for device_name, wifi_device in pairs(get_wifi_devices()) do
		on_entry({"basis", "network", device_name},
			call("action_wifi_device", device_name),
			i18n("Wireless Interface") .. ' "' .. device_name .. '"').leaf = true
	end

	on_entry({"basis", "module"}, call("action_modules"), i18n("Modules"), 30).leaf = true
	on_entry({"basis", "einstellungen"}, call("action_settings"), i18n("Settings"), 40).leaf = true
	on_entry({"basis", "portweiterleitung"}, call("action_portmapping"), i18n("Port-Mapping"), 60).leaf = true
	on_entry({"basis", "bericht"}, call("action_report"), i18n("Report"), 80)
	on_entry({"basis", "bericht", "zeitstempel"}, call("get_report_timestamp")).leaf = true
end
