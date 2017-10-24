--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

]]--

require("luci.model.opennet.funcs")


function action_on_openvpn_mesh_overview()
    local result = process_openvpn_certificate_form("mesh")
    luci.template.render("opennet/on_usergw", { certstatus=result.certstatus })
end


function action_on_openvpn_mesh_keys()
    local on_errors = {}
    -- sofortiges Ende, falls der Upload erfolgreich verlief
    if process_csr_submission("mesh", on_errors) then return end
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

    check_and_warn_module_state("on-usergw", on_errors)

    -- Dienst hinzufügen
    local service_result = process_add_service_form()
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end
    -- Dienst verschieben
    service_result = process_service_action_form("mesh")
    if (service_result == true) then
        -- enable or disable services
        on_function("sync_mesh_openvpn_connection_processes")
    elseif (service_result ~= false) then
        -- ungleich true und ungleich false: es ist eine Fehlermeldung
        table.insert(on_errors, service_result)
    end

    luci.template.render("opennet/mesh_connections", { on_errors=on_errors })
end


function action_on_service_relay()
    local on_errors = {}

    check_and_warn_module_state("on-usergw", on_errors)

    -- Dienst hinzufügen
    local service_result = process_add_service_form()
    if (service_result ~= true) and (service_result ~= false) then table.insert(on_errors, service_result) end
    -- Dienst verschieben
    service_result = process_service_action_form(nil)
    if (service_result == true) then
        -- enable or disable services
        on_function("update_service_relay_status")
    elseif (service_result ~= false) then
        -- ungleich true und ungleich false: es ist eine Fehlermeldung
        table.insert(on_errors, service_result)
    end

    -- Dienst-Liste ermitteln
    local relay_services = line_split(luci.sys.exec("on-function get_services | on-function filter_relay_services"))

    luci.template.render("opennet/service_relay", { on_errors=on_errors, relay_services=relay_services })
end


function status_ugw_connection()
    local status_lines = {}
    if on_bool_function("has_mesh_openvpn_credentials") then
        -- Zertifikat und Schluessel sind vorhanden
        local ugw_status = {}
        ugw_status.mesh_servers = {}
        for _, service_name in pairs(line_split(on_function("get_active_ugw_connections"))) do
            table.insert(ugw_status.mesh_servers, get_service_value(service_name, "host"))
        end
        ugw_status.mesh_servers_string = string_join(ugw_status.mesh_servers, ", ")
        if not is_string_empty(ugw_status.mesh_servers_string) then
            table.insert(status_lines, luci.i18n.translatef("Connected Mesh Gateways: %s", ugw_status.mesh_servers_string))
        else
            table.insert(status_lines, luci.i18n.translate("No Mesh Gateways connected"))
        end
    else
        -- kein Zertifikat vorhanden
	table.insert(status_lines, luci.i18n.translate("Certificate is missing")
            .. " (" ..  luci.i18n.translate("see")
            .. ' <a href="' .. on_url("mesh_tunnel", "zertifikat") .. '">'
            ..  luci.i18n.translate("Certificate management") .. "</a>).")
    end
    -- weitergeleitete Nutzerverbindungen koennen auch ohne Mesh-VPN existieren (nur service-relay)
    if file_exists("/usr/sbin/munin-node-plugin.d/on_usergw_connections") then
        -- wir missbrauchen das munin-Plugin fuer die Ermittlung der Verbindungsanzahl
        -- TODO: dies löst eine Abhängigkeit von micropython aus - können wir das anders lösen?
        ugw_users_connection_count = luci.sys.exec(
            "/usr/sbin/munin-node-plugin.d/on_usergw_connections | awk 'BEGIN {sum = 0} {sum += $2} END {print sum}'")
    else
        ugw_users_connection_count = luci.i18n.translate("unknown (the 'on-monitoring' module is required for this information)")
    end
    table.insert(status_lines, luci.i18n.translatef("Relayed user tunnel connections: %s", ugw_users_connection_count))
    luci.http.prepare_content("text/plain")
    luci.http.write(string_join(status_lines, [[<br/>]]))
end
