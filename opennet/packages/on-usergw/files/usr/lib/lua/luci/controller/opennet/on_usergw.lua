--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

]]--

module("luci.controller.opennet.on_usergw", package.seeall)
require("luci.model.opennet.urls")


function index()
	require("luci.i18n")
	require("luci.model.opennet.funcs")
	require("luci.model.opennet.urls")
	local i18n = luci.i18n.translate
	luci.i18n.loadc("on-usergw")

	require("luci.model.opennet.on_usergw")
	on_entry({"mesh_tunnel"}, call("action_on_openvpn_mesh_overview"), i18n("Internet Sharing"), 60, "on_usergw")

	on_entry({"mesh_tunnel", "zertifikat"}, call("action_on_openvpn_mesh_keys"),
			i18n("Key Management"), 20, "on_usergw").leaf = true
	on_entry({"mesh_tunnel", "verbindungen"}, call("action_on_mesh_connections"),
			i18n("Mesh Connections"), 30, "on_usergw").leaf = true
	on_entry({"mesh_tunnel", "dienst_weiterleitung"}, call("action_on_service_relay"),
			i18n("Service Relay"), 40, "on_usergw").leaf = true

	-- Einbindung in die Status-Seite mit dortigem Link
	on_entry({"status", "mesh_verbindungen"}, call("status_ugw_connection")).leaf = true

	-- importiere den file-upload-Handler
	require("luci.model.opennet.on_vpn_management")
end
