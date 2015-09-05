--[[
Opennet Firmware

Copyright 2015 Lars Kruse <devel@sumpfralle.de>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--

require("luci.dispatcher")


-- Die folgenden beiden Funktionen definieren global, an welcher Stelle im Luci-Dispatcher-Baum der Opennet-Zweig hängt.
-- Änderungen müssen an den beiden folgenden Funktionen synchron durchgeführt werden.

-- Definition der Basis-URL
-- synchron mit "_on_dispatcher_func_caller" halten
local function on_path(tokens)
	local path = {}
	table.insert(path, "opennet")
	for _, token in ipairs(tokens) do
		table.insert(path, token)
	end
	return path
end


-- synchron mit "on_path" halten
local function _on_dispatcher_func_caller(dispatcher_func, ...)
	return dispatcher_func("opennet", ...)
end


function on_alias(...) return _on_dispatcher_func_caller(luci.dispatcher.alias, ...) end
function on_url(...) return _on_dispatcher_func_caller(luci.dispatcher.build_url, ...) end


-- Erzeugung eines luci-Entry mit opennet-geeigneten Eigenschaften (Pfad, css, Sprache)
function on_entry(path_tokens, action, title, order, lang_domain)
	local path = on_path(path_tokens)
	local page = luci.dispatcher.entry(path, action, title, order)
	if lang_domain then
		page.i18n = lang_domain
	else
		page.i18n = "on-core"
	end
	page.css = "opennet.css"
	page.sysauth = "root"
	page.sysauth_authenticator = "htmlauth"
	return page
end


-- luci-Entry ohne Passwortschutz
function on_entry_no_auth(...)
	local page = on_entry(...)
	page.sysauth = nil
	page.sysauth_authenticator = nil
	return page
end
