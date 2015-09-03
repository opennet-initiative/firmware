--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--
module("luci.controller.opennet.opennet", package.seeall)


function index()
	local page
	local i18n = luci.i18n.translate
	require("luci.model.opennet.urls")
	luci.i18n.loadc("on-core")

	-- Umleitung der top-level Node (die Startseite) zur Node "opennet"
	local page = node()
	page.target = on_alias()
	page.sysauth = nil
	page.sysauth_authenticator = nil
	
	-- Definition der Opennet-Startseite
	page = on_entry_no_auth({}, nil, i18n("Opennet"), 35)
	page.target = on_alias("status")

	-- die Status-Seite (/status)
	on_entry_no_auth({"status"}, template("opennet/on_status"), i18n("Status"), 10)

	-- Quellen fuer die Inhalte der Status-Seite
	require ("luci.model.opennet.on_status")
	on_entry_no_auth({"status", "neighbors"}, call("status_neighbors")).leaf = true
	on_entry_no_auth({"status", "network"}, call("status_network")).leaf = true
	on_entry_no_auth({"status", "wireless"}, call("status_wireless")).leaf = true
	on_entry_no_auth({"status", "issues"}, call("status_issues")).leaf = true


	-- Grundlegende Einstellungen (/basis)
	require ("luci.model.opennet.base")
	page = on_entry({"basis"}, nil, i18n("Base"), 20)
	page.target = on_alias("basis", "funknetz")
	on_entry({"basis", "funknetz"}, template("opennet/on_network"), i18n("Network"), 20).leaf = true
	on_entry({"basis", "einstellungen"}, call("action_settings"), i18n("Settings"), 40).leaf = true
	on_entry({"basis", "portweiterleitung"}, call("action_portmapping"), i18n("Port-Mapping"), 60).leaf = true
	on_entry({"basis", "bericht"}, call("action_report"), i18n("Report"), 80)
	on_entry({"basis", "bericht", "zeitstempel"}, call("get_report_timestamp")).leaf = true
end
