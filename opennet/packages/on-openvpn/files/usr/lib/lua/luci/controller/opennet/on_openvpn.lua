--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--

module("luci.controller.opennet.on_openvpn", package.seeall)

require("luci.model.opennet.funcs")


function index()
	luci.i18n.loadc("on-openvpn")
	
	local page = entry({"opennet", "opennet_1", "vpn_tunnel"}, call("action_on_openvpn"))
	page.title = luci.i18n.translate("VPN Tunnel")
	page.order = 20
	page.i18n = "on_openvpn"
	page.css = "opennet.css"

	require ("luci.model.opennet.on_vpn_status")
	entry({"opennet", "opennet_1", "vpn_tunnel", "on_vpn_status_label"}, call("on_vpn_status_label"), nil).leaf = true
	entry({"opennet", "opennet_1", "vpn_tunnel", "on_vpn_status_form"}, call("on_vpn_status_form"), nil).leaf = true

	-- wir veröffentlichen unseren Status unterhalb der core-Seite, um die URL-Erstellung dort zu erleichtern
	entry({"opennet", "on_status", "on_status_mig_connection"}, call("status_mig_connection")).leaf = true

	-- importiere den file-upload-Handler
	require("luci.model.opennet.on_vpn_management")
end
