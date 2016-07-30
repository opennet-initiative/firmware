--[[
Opennet Firmware

Copyright 2016 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--
module("luci.controller.opennet.on_olsr2", package.seeall)


function index()
	local page
	local i18n = luci.i18n.translate
	require("luci.model.opennet.urls")
	luci.i18n.loadc("on-olsr2")

	require ("luci.model.opennet.on_olsr2")
	on_entry_no_auth({"status", "neighbors_olsr2"}, call("status_neighbors_olsr2")).leaf = true
end
