--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>
Copyright 2014 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.on_gateways", package.seeall)
require ("luci.model.opennet.on_vpn_autosearch")
require("luci.model.opennet.funcs")

function index()
	luci.i18n.loadc("on_base")
	local i18n = luci.i18n.string
	
	local page = entry({"opennet", "opennet_2", "vpn_gateways"}, call("action_vpn_gateways"), i18n("VPN Gateways"), 1)
	page.i18n  = "on_gateways"
	page.css   = "opennet.css"
end

function action_vpn_gateways()

	local move_up = luci.http.formvalue("move_up")
	local move_down = luci.http.formvalue("move_down")
	local move_top = luci.http.formvalue("move_top")
	local delete_service = luci.http.formvalue("delete_service")
	local disable_service = luci.http.formvalue("disable_service")
	local enable_service = luci.http.formvalue("enable_service")
	local reset_offset = luci.http.formvalue("reset_offset")
	local reset_counter = luci.http.formvalue("reset_counter")
	
	if move_up then
		on_function("move_service_up", "'"..move_up.."' ug ugw")
	elseif move_down then
		on_function("move_service_down", "'"..move_down.."' ug ugw")
	elseif move_top then
		on_function("move_service_top", "'"..move_top.."' ug ugw")
		on_function("select_mig_connection", "'"..move_top.."'")
	elseif delete_service then
		on_function("delete_service", "'"..delete_service.."'")
	elseif disable_service then
		set_service_value(disable_service, "disabled", "1")
	elseif enable_service then
		delete_service_value(enable_service, "disabled")
	elseif reset_offset then
		delete_service_value(reset_offset, "offset")
	elseif reset_counter then
		on_function("reset_alL_mig_connection_test_timestamps")
	end


	-- optional koennten wir pruefen, ob ueberhaupt eine der Verbindungen einen Offset verwendet
	local offset_exists = true
	local show_more_info = luci.http.formvalue("show_more_info")

	luci.template.render("opennet/on_gateways", { show_more_info = show_more_info, offset_exists = offset_exists })
end

