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


function index()
	require("luci.i18n")
	require("luci.model.opennet.funcs")
	require("luci.model.opennet.urls")
	local i18n = luci.i18n.translate
	luci.i18n.loadc("on-openvpn")

	local page = on_entry({"mig_openvpn"}, nil, i18n("VPN Tunnel"), 40, "on-openvpn")
	page.target = on_alias("mig_openvpn", "zertifikat")

	require("luci.model.opennet.on_mig_openvpn")
	on_entry({"mig_openvpn", "zertifikat"}, call("action_on_openvpn"), i18n("Certificate"), 20, "on-openvpn").leaf = true
	on_entry({"mig_openvpn", "gateways"}, call("action_vpn_gateways"), i18n("Gateways"), 40, "on-openvpn").leaf = true

	on_entry({"mig_openvpn", "vpn_status_label"}, call("on_vpn_status_label"), nil, nil, "on-openvpn").leaf = true
	on_entry({"mig_openvpn", "vpn_status_form"}, call("on_vpn_status_form"), nil, nil, "on-openvpn").leaf = true

	on_entry({"mig_openvpn", "status"})
	on_entry({"mig_openvpn", "status", "vpn_gateway_info"}, call("gateway_info"), nil, nil, "on-openvpn").leaf = true
	on_entry({"mig_openvpn", "status", "vpn_gateway_list"}, call("gateway_list"), nil, nil, "on-openvpn").leaf = true

	-- wir veröffentlichen unseren Status unterhalb der core-Seite, um die URL-Erstellung dort zu erleichtern
	on_entry_no_auth({"status", "mig_openvpn"}, call("status_mig_openvpn"), nil, nil, "on-openvpn").leaf = true

	-- importiere den file-upload-Handler
	require("luci.model.opennet.on_vpn_management")
end
