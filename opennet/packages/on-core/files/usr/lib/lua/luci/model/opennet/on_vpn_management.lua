--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--

require("luci.model.opennet.funcs")


function replace_file(source, target)
	if file_exists(target) then
		nixio.fs.move(target, target .. "_bak")
	end
	nixio.fs.move(source, target)
	nixio.fs.remove(target .. "_bak")
	nixio.fs.chmod(target, 600)
end


-- cert_type is user or mesh
function upload_file(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	if not file_exists(upload_file_location) then return end
	if not file_exists(cert_info.cert_dir) then nixio.fs.mkdirr(cert_info.cert_dir) end
	local upload_filename = luci.http.formvalue("opensslfile")["file"]
	if string.find(upload_filename, ".key") then
		replace_file(upload_file_location, cert_info.filename_prefix .. ".key")
	elseif string.find(upload_filename, ".crt") then
		replace_file(upload_file_location, cert_info.filename_prefix .. ".crt")
	else
		-- unbekannter Datentyp? Wir muessen die Datei loeschen - sonst wird sie beim naechsten Upload wiederverwendet.
		nixio.fs.remove(upload_file_location)
		return
	end
	-- wollen wir vielleicht eine Aktion ausloesen, wenn Schluessel/Zertifikat nun vollstaendig sind
	if (cert_type == "user") and on_bool_function("has_mig_openvpn_credentials") then
		on_schedule_task("on-function update_mig_connection_status")
	elseif (cert_type == "mesh") and on_bool_function("has_mesh_openvpn_credentials") then
		on_schedule_task("on-function update_on_usergw_status")
	end
end


-- "type" is "user" or "mesh"
-- "download" is "key" or "cert"
function download_file(cert_type, download)
	local cert_info = get_ssl_cert_info(cert_type)
	local filename = cert_info.filename_prefix .. "." .. download
	local download_fpi = io.open(filename, "r")
	local on_id = on_function("uci_get", {"on-core.settings.on_id", "X.XX"})
	luci.http.header('Content-Disposition',
	    'attachment; filename="AP' .. on_id .. '_' .. cert_type .. '_' .. os.date("%Y-%m-%d") .. '.' .. download .. '"')
	-- crt is actually a application/x-x509-ca-cert, but can be ignored here
	luci.http.prepare_content("application/octet-stream")
	luci.ltn12.pump.all(luci.ltn12.source.file(download_fpi), luci.http.write)
end


function check_cert_status(cert_type)
	local cert_info = get_ssl_cert_info(cert_type)
	local csr_filename = cert_info.filename_prefix .. ".csr"
	local key_filename = cert_info.filename_prefix .. ".key"
	local crt_filename = cert_info.filename_prefix .. ".crt"
	local certstatus = {}
	certstatus.on_csr_exists = file_exists(csr_filename)
	if certstatus.on_csr_exists then
		certstatus.on_csr_date = nixio.fs.stat(csr_filename, "mtime")
		certstatus.on_csr_modulus = trim_string(on_function("get_ssl_object_hash", {csr_filename, "req"}))
	else
		certstatus.on_csr_date = ""
		certstatus.on_csr_modulus = ""
	end
	certstatus.on_key_exists = file_exists(key_filename)
	if certstatus.on_key_exists then
		certstatus.on_key_date = nixio.fs.stat(key_filename, "mtime")
		certstatus.on_key_modulus = trim_string(on_function("get_ssl_object_hash", {key_filename, "rsa"}))
	else
		certstatus.on_key_date = ""
		certstatus.on_key_modulus = ""
	end
	certstatus.on_crt_exists = file_exists(crt_filename)
	if certstatus.on_crt_exists then
		certstatus.on_crt_date = nixio.fs.stat(crt_filename, "mtime")
		certstatus.on_crt_modulus = trim_string(on_function("get_ssl_object_hash", {crt_filename, "x509"}))
	else
		certstatus.on_crt_date = ""
		certstatus.on_crt_modulus = ""
	end
	certstatus.on_keycrt_ok = certstatus.on_key_exists and certstatus.on_crt_exists and (certstatus.on_key_modulus == certstatus.on_crt_modulus)
	certstatus.on_keycsr_ok = certstatus.on_key_exists and certstatus.on_csr_exists and (certstatus.on_key_modulus == certstatus.on_csr_modulus)
	return certstatus
end



upload_file_location = SYSROOT .. "/tmp/key.file"
local file

-- installiere eine Upload-Handler
-- Diese Funktion muss in der index-Funktion eines controllers ausgefuehrt werden.
luci.http.setfilehandler(
	function(meta, chunk, eof)
		if not file_exists(upload_file_location) and not file and chunk and #chunk > 0 then
			file = io.open(upload_file_location, "w")
		end
		if file and chunk then file:write(chunk) end
		if file and eof then file:close() end
	end
)
