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

    local page = entry({"opennet", "opennet_2", "ugw_tunnel"},
        template("opennet/on_usergw"),
        luci.i18n.translate("Internet Sharing"), 3)
    page.css = "opennet.css"
    page.i18n = "on_usergw"

    -- Unterseiten
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
    local result = process_openvpn_certificate_form("ugw")
    luci.template.render("opennet/on_openvpn_mesh_keys", {
        certstatus=result.certstatus,
        openssl=result.openssl,
        force_show_uploadfields=result.force_show_uploadfields,
        force_show_generatefields=result.force_show_generatefields
    })
end


function action_on_mesh_connections()
    local on_errors = {}

    -- Dienst hinzufügen
    local service_result = process_add_service_form()
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end
    -- Dienst verschieben
    service_result = process_service_action_form("mesh")
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end

    luci.template.render("opennet/mesh_connections", { on_errors=on_errors })
end


function action_on_service_relay()
    local on_errors = {}

    -- Dienst hinzufügen
    local service_result = process_add_service_form()
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end
    -- Dienst verschieben
    service_result = process_service_action_form(nil)
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end

    luci.template.render("opennet/service_relay", { on_errors=on_errors })
end
