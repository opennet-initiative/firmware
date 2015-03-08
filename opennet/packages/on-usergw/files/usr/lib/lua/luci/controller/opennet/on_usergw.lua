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
    luci.i18n.loadc("on-usergw")

    local page = entry({"opennet", "opennet_2", "ugw_tunnel"}, call("action_on_usergw"), luci.i18n.translate("Internet Sharing"), 3)
    page.css = "opennet.css"
    page.i18n = "on_usergw"

    require ("luci.model.opennet.on_usergw")
    entry({"opennet", "opennet_2", "ugw_tunnel", "check_ugw_status"}, call("check_ugw_status"), nil).leaf = true

    -- sichtbare Unterseiten
    page = entry({"opennet", "opennet_2", "ugw_tunnel", "openvpn_mesh_keys"},
        call("action_on_openvpn_mesh_keys"),
        luci.i18n.translate("Key Management"), 1)
    page.css = "opennet.css"
    page.i18n = "on_usergw"
    page.leaf = true

    page = entry({"opennet", "opennet_2", "ugw_tunnel", "mesh_connections"},
        call("action_on_mesh_connections"),
        luci.i18n.translate("Mesh Connections"), 2)
    page.css = "opennet.css"
    page.i18n = "on_usergw"
    page.leaf = true

    entry({"opennet", "opennet_2", "ugw_tunnel", "service_relay"},
        call("action_on_service_relay"),
        luci.i18n.translate("Service Relay"), 3)
    page.css = "opennet.css"
    page.i18n = "on_usergw"
    page.leaf = true
end


function action_on_openvpn_mesh_keys()
    require("luci.model.opennet.on_vpn_management")

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

    luci.template.render("opennet/on_openvpn_mesh_keys", {
        certstatus=certstatus,
	openssl=openssl,
	force_show_uploadfields=force_show_uploadfields,
	force_show_generatefields=force_show_generatefields
    })
end


function action_on_mesh_connections()
    luci.template.render("opennet/on_mesh_connections")
end


function action_on_service_relay()
    luci.template.render("opennet/on_service_relay")
end


function action_on_usergwNG(ugw_status)
    local new_gateway_host = luci.http.formvalue("new_gateway_host")
    local new_gateway_port = luci.http.formvalue("new_gateway_port")
    local add_gateway_mesh = luci.http.formvalue("add_gateway_mesh")
    local add_gateway_igw = luci.http.formvalue("add_gateway_igw")

    local move_up = luci.http.formvalue("move_up")
    local move_down = luci.http.formvalue("move_down")
    local move_top = luci.http.formvalue("move_top")
    local delete_service = luci.http.formvalue("delete_service")
    local disable_service = luci.http.formvalue("disable_service")
    local enable_service = luci.http.formvalue("enable_service")
    local reset_offset = luci.http.formvalue("reset_offset")

    if new_gateway_host and new_gateway_port then
        new_gateway_port = parse_number_string(new_gateway_port) or on_function("get_variable", {"DEFAULT_MIG_PORT"})
        new_gateway_host = parse_hostname_string(new_gateway_host)
        if not new_gateway_host then
            -- Fehlerausgabe?
        elseif add_gateway_mesh then
            on_function("notify_service", {"mesh", "openvpn", new_gateway_host, new_gateway_port, "udp", "/", "", "manual"})
        elseif add_gateway_igw then
            on_function("notify_service", {"igw", "openvpn", new_gateway_host, new_gateway_port, "udp", "/", "", "manual"})
        end
    elseif move_up or move_down or move_top or delete_service or disable_service or enable_service or reset_offset then
        if move_up then
          on_function("move_service_up", {move_up, "mesh"})
        elseif move_down then
          on_function("move_service_down", {move_down, "mesh"})
        elseif move_top then
          on_function("move_service_top", {move_top, "mesh"})
        elseif delete_service then
          on_function("delete_service", {delete_service})
        elseif disable_service then
          set_service_value(disable_service, "disabled", "1")
        elseif enable_service then
          delete_service_value(enable_service, "disabled")
        elseif reset_offset then
          delete_service_value(reset_offset, "offset")
        end
    end
end


function action_on_usergw()
    require ("luci.model.opennet.on_vpn_management")
    require ("luci.model.opennet.on_usergw")

    local ugw_status = {}
    get_ugw_status(ugw_status)
    action_on_usergwNG(ugw_status)

    luci.template.render("opennet/on_usergw", { ugw_status=ugw_status })
end
