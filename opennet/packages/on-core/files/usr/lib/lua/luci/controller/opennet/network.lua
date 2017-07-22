--[[
Opennet Firmware

Copyright 2017 Martin Garbe <monomartin@on-i.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--
module("luci.controller.opennet.network", package.seeall)

function index()
	local uci = require("luci.model.uci").cursor()
	local page

	page = node("opennet", "network")
	page.target = firstchild()
	page.title  = _("Network")
	page.order  = 50
	page.index  = true

	page = entry({"opennet", "network", "wireless_set_ssid"}, post("wifi_set_oni_ssid"), nil)
	page.leaf = true
end


function wifi_set_oni_ssid()
	-- TODO allow other devices too
	local dev = "default_radio0"
	local ssid = luci.http.formvalue("ssid")

	luci.sys.exec("uci set wireless.default_radio0.mode=sta")
	luci.sys.exec("uci set wireless.default_radio0.ssid=" .. ssid )
	luci.sys.exec("uci commit wireless")
	luci.sys.exec("reload_config")
	
	luci.http.redirect(luci.dispatcher.build_url("opennet/basis/funknetz"))
end


