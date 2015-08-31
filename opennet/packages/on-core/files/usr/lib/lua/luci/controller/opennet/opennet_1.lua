--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.opennet_1", package.seeall)

local report_filename = "/tmp/on_report.tar.gz"
require("luci.model.opennet.funcs")
require("luci.sys")
local uci = require "luci.model.uci"
local cursor = uci.cursor()


function index()
	luci.i18n.loadc("on-core")
	local i18n = luci.i18n.translate
	local page
	
	page = entry({"opennet", "opennet_1"}, template("opennet/opennet_1"))
	page.title = i18n("Base")
	page.order = 1
	page.i18n = "on_opennet_1"
	page.css = "opennet.css"
	page.index = true
	page.sysauth = "root"
	page.sysauth_authenticator = "htmlauth"
	
	page = entry({"opennet", "opennet_1", "funknetz"}, template("opennet/on_network"))
	page.title = i18n("Network")
	page.order = 10
	page.i18n = "on_network"
	page.css = "opennet.css"

	page = entry({"opennet", "opennet_1", "einstellungen"}, call("settings"))
	page.title = i18n("Settings")
	page.order = 40
	page.i18n = "on_settings"
	page.css = "opennet.css"

	page = entry({"opennet", "opennet_1", "bericht"}, call("report"))
	page.title = i18n("Report")
	page.order = 50
	page.i18n = "on_report"
	page.css = "opennet.css"

	page = entry({"opennet", "opennet_1", "bericht", "timestamp"}, call("get_report_timestamp"))
end


function report()
	if luci.http.formvalue("download") and nixio.fs.access(report_filename) then
		local timestamp = nixio.fs.stat(report_filename, "mtime")
		local fhandle = io.open(report_filename, "r")
		luci.http.header('Content-Disposition', 'attachment; filename="AP-report-%s-%s.tar.gz"' % {
			luci.sys.hostname(), os.date("%Y-%m-%d_%H%M", timestamp)})
		luci.http.prepare_content("application/x-targz")
		luci.ltn12.pump.all(luci.ltn12.source.file(fhandle), luci.http.write)
	else
		if luci.http.formvalue("delete") and nixio.fs.access(report_filename) then
			nixio.fs.remove(report_filename)
		elseif luci.http.formvalue("generate") then
			on_function("run_delayed_in_background", {"0", "generate_report"})
		end
		luci.template.render("opennet/on_report")
	end
end


function settings()
	on_errors = {}
	local remove_package = parse_string_pattern(luci.http.formvalue("remove"), "a-z-")
	if remove_package then
		-- stderr sollte nach stdout gehen, damit wir es als Fehlertext einblenden koennen
		error_message = luci.sys.exec("opkg --verbosity=0 --autoremove remove '" .. remove_package .. "' 2>&1")
		table.insert(on_errors, error_message)
	end
	local install_package = parse_string_pattern(luci.http.formvalue("install"), "a-z-")
	if install_package then
		error_message = on_function("install_from_opennet_repository", {install_package})
		table.insert(on_errors, error_message)
	end
	-- Module an- und abschalten oder umkonfigurieren
	if luci.http.formvalue("save") then
		-- Module
		for _, module in ipairs(line_split(on_function("get_on_modules"))) do
			if on_bool_function("is_package_installed", {module}) then
				local enabled = on_bool_function("is_on_module_installed_and_enabled", {module})
				if luci.http.formvalue(module .. "_enabled") then
					if not enabled then on_function("enable_on_module", {module}) end
				else
					if enabled then on_function("disable_on_module", {module}) end
				end
			end
		end
		-- Dienst-Sortierung
		for _, key in ipairs({"use_olsrd_dns", "use_olsrd_ntp"}) do
			if luci.http.formvalue(key) then
				cursor:set("on-core", "settings", key, "1")
			else
				cursor:set("on-core", "settings", key, "0")
			end
		end
		local services_sorting = luci.http.formvalue("services_sorting")
		if services_sorting then
			on_function("set_service_sorting", {services_sorting})
		end
		cursor:commit("on-core")
	end
	luci.template.render("opennet/on_settings", { on_errors=on_errors })
end


function get_report_timestamp()
	local info
	if nixio.fs.access(report_filename) then
		info = nixio.fs.stat(report_filename, "mtime")
	else
		info = nil
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json(info)
end

