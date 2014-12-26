--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.opennet", package.seeall)

function index()
	luci.i18n.loadc("on-core")
	local i18n = luci.i18n.translate

	local page = node()
	page.target = alias("opennet")
	
	page = node("opennet")
	page.title = i18n("Opennet")
	page.target = alias("opennet", "on_status")

	-- die Status-Seite
	page = entry({"opennet", "on_status"}, template("opennet/on_status"))
	page.title = i18n("Status")
	page.order = 0
	page.css = "opennet.css"
	page.i18n = "on_status"

	-- Quellen fuer die Inhalte der Status-Seite
	require ("luci.model.opennet.on_status")
	page = entry({"opennet", "on_status", "on_status_neighbors"}, call("status_neighbors"))
	page.leaf = true

	page = entry({"opennet", "on_status", "on_status_network"}, call("status_network"))
	page.leaf = true

	page = entry({"opennet", "on_status", "on_status_wireless"}, call("status_wireless"))
	page.leaf = true

	-- separate top-level Auswahl fuer das olsr-Web-Interface
	page = node("olsr")
	page.title = i18n("OLSR-Status")
	page.target = template("opennet/on_olsr")
	page.css = "opennet.css"
	page.order = 100
end
