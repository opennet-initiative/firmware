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

function index()
	luci.i18n.loadc("on_base")
	local i18n = luci.i18n.string
	
	local page = entry({"opennet", "opennet_1"}, template("opennet/opennet_1"), i18n("Base"), 1)
	page.i18n = "on_opennet_1"
	page.css = "opennet.css"
	page.index = true
	page.sysauth = "root"
	page.sysauth_authenticator = "htmlauth"
	
	local page = entry({"opennet", "opennet_1", "funknetz"}, template("opennet/on_network"), i18n("Network"), 1)
	page.i18n = "on_network"
	page.css = "opennet.css"

	local page = entry({"opennet", "opennet_1", "restart"}, template("opennet/on_reboot"), i18n("Reboot"), 5)
	page.i18n = "on_reboot"
	page.css = "opennet.css"

	local page = entry({"opennet", "opennet_1", "passwd"}, cbi("opennet/passwd"), i18n("Password"), 2)
    
    page.css = "opennet.css"
end
