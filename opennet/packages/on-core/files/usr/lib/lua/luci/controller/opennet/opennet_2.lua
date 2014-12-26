--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
module("luci.controller.opennet.opennet_2", package.seeall)

function index()
	luci.i18n.loadc("on-core")
	
	local page = entry({"opennet", "opennet_2"}, template("opennet/opennet_2"), luci.i18n.translate("ON Extended"), 2)
	page.i18n = "on_opennet_2"
	page.css = "opennet.css"
	page.index = true
	page.sysauth = "root"
	page.sysauth_authenticator = "htmlauth"
end
