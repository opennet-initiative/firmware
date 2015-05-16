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


    -- Funktionen
    -- Einbindung in die Status-Seite mit dortigem Link
    entry({"opennet", "on_status", "on_status_ugw_connection"}, call("status_ugw_connection")).leaf = true

    -- importiere den file-upload-Handler
    require("luci.model.opennet.on_vpn_management")
end


function action_on_openvpn_mesh_keys()
    local result = process_openvpn_certificate_form("mesh")
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


function status_ugw_connection()
    luci.http.prepare_content("text/plain")

    local ugw_status = {}
    -- central gateway-IPs reachable over tap-devices
    ugw_status.connections = on_function("get_active_ugw_connections")
    local service_name
    local central_ips_table = {}
    for service_name in line_split(ugw_status.connections) do
        table.insert(central_ips_table, get_service_value(service_name, "host"))
    end
    ugw_status.centralips = string_join(central_ips_table, ", ")
    ugw_status.centralip_status = (ugw_status.centralips ~= "")
    -- tunnel active
    ugw_status.tunnel_active = to_bool(ugw_status.centralips)
    -- sharing possible
    ugw_status.usergateways_no = 0
    -- TODO: Struktur ab hier weiter umsetzen
    cursor:foreach ("on-usergw", "usergateway", function() ugw_status.usergateways_no = ugw_status.usergateways_no + 1 end)
    ugw_status.sharing_possible = false
    local count = 1
    while count <= ugw_status.usergateways_no do
        local onusergw = cursor:get_all("on-usergw", "opennet_ugw"..count)
        if uci_to_bool(onusergw.wan) and uci_to_bool(onusergw.mtu_status) then
            ugw_status.sharing_possible = true
            break
        end
        count = count + 1
    end
    -- sharing enabled
    ugw_status.sharing_enabled = uci_to_bool(cursor:get("on-usergw", "ugw_sharing", "shareInternet"))
    -- forwarding enabled
    local ugw_port_forward = tab_split(on_function("get_ugw_portforward"))
    ugw_status.forwarded_ip = ugw_port_forward[1]
    ugw_status.forwarded_gw = ugw_port_forward[2]


    local result = ""
    if ugw_status.sharing_enabled or ugw_status.sharing_possible then
        result = result .. [[<tr class='cbi-section-table-titles'><td class='cbi-section-table-cell'>]] ..
                luci.i18n.translate("Internet-Sharing:") .. [[</td><td class='cbi-section-table-cell'>]]
        if uci_to_bool(ugw_status.centralip_status) or (ugw_status.forwarded_gw ~= "") then
            result = result .. luci.i18n.translate("Internet shared")
            if ugw_status.centralips then
                result = result .. luci.i18n.translate("(no central Gateway-IPs connected trough tunnel)")
            else
                result = result .. luci.i18n.translatef("(central Gateway-IPs (%s) connected trough tunnel)", ugw_status.centralips)
            end
            if ugw_status.forwarded_gw ~= "" then
                result = result .. ", " .. luci.i18n.translatef("Gateway-Forward for %s (to %s) activated", ugw_status.forwarded_ip, ugw_status.forwarded_gw)
            end
        elseif ugw_status.tunnel_active then
            result = result .. luci.i18n.translate("Internet not shared")
                    .. " ( " .. luci.i18n.translate("Internet-Sharing enabled")
                    .. ", " .. luci.i18n.translate("Usergateway-Tunnel active") .. " )"
        elseif ugw_status.sharing_enabled then
            result = result .. luci.i18n.translate("Internet not shared")
                    .. " ( "..  luci.i18n.translate("Internet-Sharing enabled")
                    .. ", " .. luci.i18n.translate("Usergateway-Tunnel not running") .. " )"
        elseif ugw_status.sharing_possible then
            result = result .. luci.i18n.translate("Internet not shared")
                    .. ", " .. luci.i18n.translate("Internet-Sharing possible")
        else
            result = result .. luci.i18n.translate("Internet-Sharing possible")
        end
        result = result .. '</td></tr>'
        luci.http.write(result)
    end
end
