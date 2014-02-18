--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.on_gateways", package.seeall)

function index()
	luci.i18n.loadc("on_base")
	local i18n = luci.i18n.string
	
	local page  = entry({"opennet", "opennet_2", "vpn_gateways"}, call("action_vpn_gateways"), i18n("VPN Gateways"), 1)
	page.i18n    = "on_gateways"
	page.css     = "opennet.css"
end

function action_vpn_gateways()
	local uci = require "luci.model.uci"
	local cursor = uci.cursor()
		
	function move_gateway_down (number)
		os.execute("logger move_gateway_down "..number)
		local t_below = cursor:get_all("on-openvpn", "gate_"..(number + 1))
		local t_current = cursor:get_all("on-openvpn", "gate_"..number)
        cursor:delete ("on-openvpn", "gate_"..(number + 1))
        cursor:delete ("on-openvpn", "gate_"..number)
		cursor:section ("on-openvpn", "gateway", "gate_"..(number + 1), t_current)
		cursor:section ("on-openvpn", "gateway", "gate_"..number, t_below)
	end

	function bring_gateway_etx_top(ipaddr)
		os.execute("logger bring_gateway_etx_top "..ipaddr)
		local number = 1
		local type = "etx"
		if cursor:get("on-openvpn", "gateways", "vpn_sort_criteria") == "metric" then type = "hop" end
		os.execute("logger bring_gateway_etx_top type "..type)
		-- search selected gw
		local target = cursor:get_all("on-openvpn", "gate_"..number)
		while target and (target.ipaddr ~= ipaddr) do
			number = number + 1
			target = cursor:get_all("on-openvpn", "gate_"..number)
		end
		os.execute("logger bring_gateway_etx_top number "..number)
		local selected_etx = cursor:get("on-openvpn", "gate_"..number, type)
		
		-- get minimal etx
		local minimal_etx = cursor:get("on-openvpn", "gate_1", type)
		local minimal_etx_offset = cursor:get("on-openvpn", "gate_1", "etx_offset")
		if minimal_etx_offset then minimal_etx = minimal_etx + minimal_etx_offset end
		
		-- set offset to get smallest etx
		cursor:set("on-openvpn", "gate_"..number, "etx_offset", math.floor(minimal_etx - selected_etx -1))
    cursor:commit("on-openvpn")
        cursor:unload("on-openvpn")
		require ("luci.model.opennet.on_vpn_autosearch")
	end
	
	function bring_gateway_top (ipaddr)
		os.execute("logger bring_gateway_top "..ipaddr)
		local number = 1
		local target = cursor:get_all("on-openvpn", "gate_"..number)
		while target and (target.ipaddr ~= ipaddr) do
			number = number + 1
			target = cursor:get_all("on-openvpn", "gate_"..number)
		end
		
		os.execute("logger bring_gateway_top found gateway at gate_"..number)
		
		while (number > 1) do
			number = number - 1
			move_gateway_down(number)
		end
	end
	
	local new_gateway = luci.http.formvalue("new_gateway")
	local new_gateway_name = luci.http.formvalue("new_gateway_name")
	local new_blacklist_gateway = luci.http.formvalue("new_blacklist_gateway")
	local new_blacklist_gateway_name = luci.http.formvalue("new_blacklist_gateway_name")
	local toggle_gateway_search = luci.http.formvalue("toggle_gateway_search")
	local toggle_sort_criteria = luci.http.formvalue("toggle_sort_criteria")
	local del_section = luci.http.formvalue("del_section")
	local del_blacklist_gw = luci.http.formvalue("del_blacklist_gw")
	local down_section = luci.http.formvalue("down_section")
	local reset_counter = luci.http.formvalue("reset_counter")
	local select_gw = luci.http.formvalue("select_gw")
    local up_etx = luci.http.formvalue("up_etx")
    local down_etx = luci.http.formvalue("down_etx")
	
	local number_of_gateways = 0
	cursor:foreach ("on-openvpn", "gateway", function() number_of_gateways = number_of_gateways + 1 end)
	
	if (new_gateway and new_gateway ~= "") or (new_gateway_name and new_gateway_name ~= "") then
		cursor:set ("on-openvpn", "gate_"..(number_of_gateways + 1), "gateway")
		cursor:tset ("on-openvpn", "gate_"..(number_of_gateways + 1), { ipaddr = new_gateway, name = new_gateway_name, age = '', status = '', route = ''})
	elseif (new_blacklist_gateway and new_blacklist_gateway ~= "") or (new_blacklist_gateway_name and new_blacklist_gateway_name ~= "") then
		cursor:section("on-openvpn", "blacklist_gateway", nil, { ipaddr = new_blacklist_gateway, name = new_blacklist_gateway_name })
	elseif up_etx then
        local etx_offset = cursor:get("on-openvpn", "gate_"..up_etx, "etx_offset")
        if etx_offset then
          etx_offset = etx_offset + 1
        else
          etx_offset = 1
        end
        if etx_offset ~= 0 then
          cursor:set ("on-openvpn", "gate_"..up_etx, "etx_offset", etx_offset)
        else
          cursor:delete ("on-openvpn", "gate_"..up_etx, "etx_offset")
        end
        cursor:commit("on-openvpn")
        cursor:unload("on-openvpn")
        require ("luci.model.opennet.on_vpn_autosearch")
    elseif down_etx then
        local etx_offset = cursor:get("on-openvpn", "gate_"..down_etx, "etx_offset")
        if etx_offset then
          etx_offset = etx_offset - 1
        else
          etx_offset = -1
        end
        if etx_offset ~= 0 then
          cursor:set ("on-openvpn", "gate_"..down_etx, "etx_offset", etx_offset)
        else
          cursor:delete ("on-openvpn", "gate_"..down_etx, "etx_offset")
        end
        cursor:commit("on-openvpn")
        cursor:unload("on-openvpn")
        require ("luci.model.opennet.on_vpn_autosearch")
    elseif down_section then
        down_section = down_section + 0
		move_gateway_down(down_section)
	elseif toggle_gateway_search then
		local search = cursor:get("on-openvpn", "gateways", "autosearch")
		if search == "on" then
          search = "off"
        else
          search = "on"
          require ("luci.model.opennet.on_vpn_autosearch")
        end
		cursor:set("on-openvpn", "gateways", "autosearch", search)
	elseif toggle_sort_criteria then
		local sort = cursor:get("on-openvpn", "gateways", "vpn_sort_criteria")
		if sort == "etx" then sort = "metric" else sort = "etx" end
		cursor:set("on-openvpn", "gateways", "vpn_sort_criteria", sort)
	elseif del_section then
		while ((del_section + 0) < number_of_gateways) do	-- comparising failed if del_section wasn't forced to be int
			move_gateway_down(del_section)
			del_section = del_section + 1
		end
		cursor:delete("on-openvpn", "gate_"..del_section)
	elseif del_blacklist_gw	then
		cursor:delete("on-openvpn", del_blacklist_gw)
	elseif reset_counter then
		for k, v in pairs(cursor:get_all("on-openvpn")) do
			if v[".type"] == "gateway" then cursor:set("on-openvpn", k, "age", "") end
		end
	elseif select_gw then
		if cursor:get("on-openvpn", "gateways", "autosearch") == "off" then
			bring_gateway_top(select_gw)
		else
			bring_gateway_etx_top(select_gw)
		end
		cursor:set("openvpn", "opennet_user", "remote", select_gw)
		cursor:set("on-openvpn", "gateways", "better_gw", 0)
		cursor:commit("openvpn")
		os.execute("/etc/init.d/openvpn down opennet_user")
		os.execute("/etc/init.d/openvpn up opennet_user")
	end
	if new_gateway or new_gateway_name or new_blacklist_gateway or new_blacklist_gateway_name or del_section or toggle_gateway_search or toggle_sort_criteria or reset_counter or select_gw then
		cursor:commit("on-openvpn")
		cursor:unload("on-openvpn")	-- just to get the real values for del-buttons
	end

	show_more_info = luci.http.formvalue("show_more_info")
    
    local offset_exists = false
    local number = 1
    local gws = cursor:get_all("on-openvpn", "gate_"..number)
    while gws do
      if gws.etx_offset then
        offset_exists = true
        break
      end
      number = number + 1
      gws = cursor:get_all("on-openvpn", "gate_"..number)
    end
	
	luci.template.render("opennet/on_gateways", { show_more_info = show_more_info, offset_exists = offset_exists })
end
