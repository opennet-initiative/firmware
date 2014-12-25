--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.on_usergw", package.seeall)
require("luci.model.opennet.funcs")

function index()
    luci.i18n.loadc("on_base")
    local i18n = luci.i18n.string

    local page = entry({"opennet", "opennet_2", "ugw_tunnel"}, call("action_on_usergw"), i18n("Internet Sharing"), 3)
    page.css = "opennet.css"
    page.i18n = "on_usergw"

    require ("luci.model.opennet.on_usergw")
    entry({"opennet", "opennet_2", "ugw_tunnel", "check_ugw_status"}, call("check_ugw_status"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "update_wan"}, call("update_wan"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_wan"}, call("get_wan"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_wan_ping"}, call("get_wan_ping"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "update_speed"}, call("update_speed"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_speed"}, call("get_speed"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "update_mtu"}, call("update_mtu"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_mtu"}, call("get_mtu"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "update_vpn"}, call("update_vpn"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_vpn"}, call("get_vpn"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "get_name_button"}, call("get_name_button"), nil).leaf = true
    entry({"opennet", "opennet_2", "ugw_tunnel", "check_running"}, call("check_running"), nil).leaf = true
end

function action_on_usergwNG(ugw_status)
    local uci = require "luci.model.uci"
    local cursor = uci.cursor()

    function move_gateway_down (number)
        local t_below = cursor:get_all("on-usergw", "opennet_ugw"..(number + 1))
        local t_current = cursor:get_all("on-usergw", "opennet_ugw"..number)
        cursor:delete ("on-usergw", "opennet_ugw"..(number + 1))
        cursor:delete ("on-usergw", "opennet_ugw"..number)
        cursor:section ("on-usergw", "usergateway", "opennet_ugw"..(number + 1), t_current)
        cursor:section ("on-usergw", "usergateway", "opennet_ugw"..number, t_below)
    end

    function bring_gateway_top (name)
        local number = 1
        local target = cursor:get_all("on-usergw", "opennet_ugw"..number)
        while target and (target.name ~= name) do
            number = number + 1
            target = cursor:get_all("on-usergw", "opennet_ugw"..number)
        end

        while (number > 1) do
            number = number - 1
            move_gateway_down(number)
        end
    end

    local new_gateway_name = luci.http.formvalue("new_gateway_name")
    local del_section = luci.http.formvalue("del_section")
    local down_section = luci.http.formvalue("down_section")
    local reset_counter = luci.http.formvalue("reset_counter")
    local select_gw = luci.http.formvalue("select_gw")

    if (new_gateway and new_gateway ~= "") or (new_gateway_name and new_gateway_name ~= "") then
        cursor:set ("on-usergw", "opennet_ugw"..(ugw_status.usergateways_no + 1), "usergateway")
        cursor:tset ("on-usergw", "opennet_ugw"..(ugw_status.usergateways_no + 1), { ipaddr = '', name = new_gateway_name, age = '', status = '', ping = ''})
        ugw_status.usergateways_no = ugw_status.usergateways_no + 1
    elseif down_section then
        down_section = down_section + 0
        move_gateway_down(down_section)
    elseif del_section then
        while ((del_section + 0) < ugw_status.usergateways_no) do   -- comparing failed if del_section wasn't forced to be int
            move_gateway_down(del_section)
            del_section = del_section + 1
        end
        cursor:delete("on-usergw", "opennet_ugw"..del_section)
        cursor:commit("on-usergw")
        cursor:unload("on-usergw")
        ugw_status.usergateways_no = ugw_status.usergateways_no - 1
	on_function("update_openvpn_ugw_settings")
    elseif reset_counter then
        for k, v in pairs(cursor:get_all("on-usergw")) do
            if v[".type"] == "usergateway" then cursor:set("on-usergw", k, "age", "") end
        end
    elseif select_gw then
        cursor:set("on-usergw", "gateways", "autosearch", "off")
        bring_gateway_top(select_gw)
        cursor:set("usergw", "opennet_user", "remote", select_gw)
        cursor:commit("usergw")
        os.execute("/etc/init.d/usergw down opennet_user")
        os.execute("/etc/init.d/usergw up opennet_user")
    end

    if new_gateway_name or down_section or reset_counter or select_gw then
        cursor:commit("on-usergw")
        cursor:unload("on-usergw") -- just to get the real values for del-buttons
    end

end

function action_on_usergw()
    require ("luci.model.opennet.on_vpn_management")
    require ("luci.model.opennet.on_usergw")

    local ugw_status = {}
    get_ugw_status(ugw_status)
    action_on_usergwNG(ugw_status)

    local uci = require "luci.model.uci"
    local cursor = uci.cursor()

    if luci.http.formvalue("disable_sharing") then
      cursor:set("on-usergw", "ugw_sharing", "shareInternet", "off")
    elseif luci.http.formvalue("enable_sharing") then
      cursor:set("on-usergw", "ugw_sharing", "shareInternet", "on")
      cursor:delete("on-usergw", "ugw_sharing", "unblock_time")
    elseif luci.http.formvalue("suspend") then
      cursor:set("on-usergw", "ugw_sharing", "unblock_time", os.time()+luci.http.formvalue("suspend_time")*60)
      cursor:set("on-usergw", "ugw_sharing", "shareInternet", "off")
    end
    if luci.http.formvalue("disable_sharing") or luci.http.formvalue("enable_sharing") or luci.http.formvalue("suspend") then
      cursor:commit("on-usergw")
      cursor:unload("on-usergw")
      os.execute("/usr/sbin/on_usergateway_check shareInternet &")
    end

    if luci.http.formvalue("upload") then upload_file("ugw") end

    local download = luci.http.formvalue("download")
    if download then download_file("ugw", download) end

    local openssl = {}
    fill_openssl("on-usergw", openssl)
    if luci.http.formvalue("generate") then generate_csr("ugw", openssl) end

    local certstatus = {}
    check_cert_status("ugw", certstatus)

    local force_show_uploadfields = luci.http.formvalue("force_show_uploadfields") or not certstatus.on_keycrt_ok
    local force_show_generatefields = luci.http.formvalue("force_show_generatefields") or (not certstatus.on_keycrt_ok and not certstatus.on_keycsr_ok)

    luci.template.render("opennet/on_usergw", {
        ugw_status=ugw_status, certstatus=certstatus, openssl=openssl, force_show_uploadfields=force_show_uploadfields, force_show_generatefields=force_show_generatefields
    })
end
