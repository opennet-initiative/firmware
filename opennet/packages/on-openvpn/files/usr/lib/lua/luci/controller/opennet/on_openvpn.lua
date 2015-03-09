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
	
	local page = entry({"opennet", "opennet_1", "vpn_tunnel"}, call("action_on_openvpn"), luci.i18n.translate("VPN Tunnel"), 2)
	page.i18n = "on_openvpn"
	page.css = "opennet.css"

	require ("luci.model.opennet.on_vpn_status")
	entry({"opennet", "opennet_1", "vpn_tunnel", "on_vpn_status_label"}, call("on_vpn_status_label"), nil).leaf = true
	entry({"opennet", "opennet_1", "vpn_tunnel", "on_vpn_status_form"}, call("on_vpn_status_form"), nil).leaf = true
end

function action_on_openvpn()
	if luci.http.formvalue("restartvpn") then os.execute("vpn_status restart opennet_user") end
	
	local on_errors = {}

	local submit_url = luci.http.formvalue("submit")
	if submit_url then
		-- zeige lediglich die Ausgabe von curl an
		local result = on_function("submit_csr_via_http", {submit_url, "/etc/openvpn/opennet_user/on_aps.csr"})
		if not result or (result == "") then
			table.insert(on_errors, luci.i18n.translate("Failed to send Certificate Signing Request. You may want to use a manual approach instead. Sorry!"))
		end
		return
	end

	local cert_result = process_openvpn_certificate_form("user")
	
	luci.template.render("opennet/on_openvpn", {
		on_errors=on_errors,
		certstatus=cert_result.certstatus,
		openssl=cert_result.openssl,
		force_show_uploadfields=cert_result.force_show_uploadfields,
		force_show_generatefields=cert_result.force_show_generatefields
	})
end
