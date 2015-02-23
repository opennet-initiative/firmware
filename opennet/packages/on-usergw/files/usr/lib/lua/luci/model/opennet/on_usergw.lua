--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--


local uci = require "luci.model.uci"
local cursor = uci.cursor()
require "luci.sys"
require("luci.i18n")
require("luci.model.opennet.funcs")


function get_ugw_status(ugw_status)
    ugw_status.usergateways_no = 0
    cursor:foreach ("on-usergw", "usergateway", function() ugw_status.usergateways_no = ugw_status.usergateways_no + 1 end)

    -- central gateway-IPs reachable over tap-devices
    ugw_status.centralips = luci.sys.exec("for gw in $(uci -q get on-usergw.@usergw[0].centralIP); do ip route get $gw | awk '/dev tap/ {print $1}' ; done")
    local words
    ugw_status.centralips_no = 0
    for words in string.gfind(ugw_status.centralips, "[^%s]+") do ugw_status.centralips_no=ugw_status.centralips_no+1 end
    ugw_status.centralip_status = "error"
    if ugw_status.centralips_no >= 1 then uci_to_bool(ugw_status.centralip_status) end
    -- tunnel active
    local iterator, number = nixio.fs.glob("/tmp/opennet_ugw-*.txt")
    ugw_status.tunnel_active = (number >= 1)

    -- if the forward is set, the sharing is active
    local port_forward = tab_split(on_function("get_ugw_portforward"))
    ugw_status.forwarded_ip = port_forward[1]
    ugw_status.forwarded_gw = port_forward[2]

    -- sharing possible
    ugw_status.sharing_wan_ok = false
    ugw_status.sharing_possible = false
    local count = 1
    while count <= ugw_status.usergateways_no do
        local onusergw = cursor:get_all("on-usergw", "opennet_ugw"..count)
        if (uci_to_bool(onusergw.wan)) then ugw_status.sharing_wan_ok = true end
        if (uci_to_bool(onusergw.wan) and uci_to_bool(onusergw.mtu_status)) then
            ugw_status.sharing_possible = true
        end
        if onusergw.ipaddr == ugw_status.forwarded_gw then
          ugw_status.forwarded_count = count
        end
        count = count + 1
    end
    -- sharing enabled
    ugw_status.sharing_enabled = uci_to_bool(cursor:get("on-usergw", "ugw_sharing", "shareInternet"))
    -- sharing blocked
    ugw_status.unblock_time = cursor:get("on-usergw", "ugw_sharing", "unblock_time")
    if ugw_status.unblock_time then
      ugw_status.sharing_blocked = math.ceil((ugw_status.unblock_time-os.time())/60)
    end
  -- checkMTU or checkWAN running
  local returnVal = luci.sys.exec("ps | grep on_usergateway_check")
  ugw_status.checkWANMTUrunning = (string.match(returnVal, "checkMtu") or string.match(returnVal, "checkWan"))
end


function check_ugw_status()
  local ugw_status = {}
  get_ugw_status(ugw_status)

  if not SYSROOT then SYSROOT = "" end        -- SYSROOT is only used for local testing (make runhttpd in luci tree)
  local autocheck_running = nixio.fs.access(SYSROOT.."/var/run/on_usergateway_check")

  luci.http.prepare_content("text/plain")

  luci.http.write([[<div class="cbi-map"><fieldset class="cbi-section"><fieldset class="cbi-section-node"><table class="usergw-status" id="ugw_status_table"><tr>]])
  luci.http.write([[<td rowspan="2" width="10%" ><div class="cbi-value-field"><div class="ugw-centralip" status="]]..ugw_status.centralip_status..[[">&#160;</div></div></td>]])
  luci.http.write([[<td><h4 class="on_sharing_status-title">]])
  if uci_to_bool(ugw_status.centralip_status) or (ugw_status.forwarded_gw ~= "") then
    luci.http.write(luci.i18n.translate("Internet shared") .. " (")
    if uci_to_bool(ugw_status.centralip_status) then
      luci.http.write(luci.i18n.translate("Central Gateways connected locally"))
    end
    if ugw_status.forwarded_gw ~= "" then
      luci.http.write(", " .. luci.i18n.translate("Gateway-Forward activated"))
    end
    luci.http.write(")")
  elseif ugw_status.tunnel_active then
    luci.http.write(luci.i18n.translate("Internet not shared") .. "( " .. luci.i18n.translate("Internet-Sharing enabled") ..
      ", " .. luci.i18n.translate("Usergateway-Tunnel active") .. ")")
  elseif ugw_status.sharing_enabled then
    luci.http.write(luci.i18n.translate("Internet not shared") .. "( " .. luci.i18n.translate("Internet-Sharing enabled") ..
      ", " .. luci.i18n.translate("Usergateway-Tunnel not running") .. ")")
  elseif ugw_status.sharing_possible then
    luci.http.write(luci.i18n.translate("Internet not shared") .. ", " .. luci.i18n.translate("Internet-Sharing possible"))
  else
    luci.http.write(luci.i18n.translate("Internet-Sharing impossible"))
  end
  luci.http.write([[</h4></td></tr>]])
  if ugw_status.tunnel_active then
    luci.http.write([[<tr class="cbi-section-table-titles"><td /><td colspan="1"><label class="cbi-value-ugwstatus">]])
    if ugw_status.centralips_no == 0 then
      luci.http.write(luci.i18n.translate("no central Gateway-IPs connected trough tunnel"))
    elseif ugw_status.centralips_no == 1 then
      luci.http.write(luci.i18n.translatef("central Gateway-IP %s connected trough tunnel", ugw_status.centralips))
    else
      luci.http.write(luci.i18n.translatef("central Gateway-IPs %s connected trough tunnel", ugw_status.centralips))
    end
    if ugw_status.forwarded_gw ~= "" then
      luci.http.write(", " .. luci.i18n.translatef("Gateway-Forward from %s to %s activated", ugw_status.forwarded_ip, ugw_status.forwarded_gw))
    end
    luci.http.write([[</label></td></tr>]])
  end
  luci.http.write([[</table></fieldset></fieldset></div>]])

  if ugw_status.sharing_possible or ugw_status.sharing_enabled then
    luci.http.write([[<h3>]] .. luci.i18n.translate("Manage Internet-Sharing")..
      [[</h3><div class="cbi-map"><fieldset class="cbi-section"><fieldset class="cbi-section-node">]])
    luci.http.write([[<h4 id="running_1" hidden="true"><div class="errorbox">]]..
      luci.i18n.translate("automated check is running, manual modifications are temporarily disabled") .. "</div><br /><br /></h4>")
    luci.http.write([[<form method="post"><div class="cbi-value">]])
    if ugw_status.sharing_enabled then
      luci.http.write('<label class="cbi-value-title">' .. luci.i18n.translate("Internet-Sharing enabled") .. "</label>")
      luci.http.write([[<div class="cbi-value-field"><input id="enable" type="submit" class="cbi-button" name="disable_sharing" value="]]..
        luci.i18n.translate("disable Sharing") .. '" ')
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[/></div>]])
    else
      luci.http.write('<label class="cbi-value-title">' .. luci.i18n.translate("Internet-Sharing disabled") .. "</label>")
      luci.http.write([[<div class="cbi-value-field"><input id="enable" type="submit" class="cbi-button" name="enable_sharing" value="]]..
        luci.i18n.translate("enable Sharing") .. '" ')
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[/></div>]])
    end
    luci.http.write([[</div>]])
    if (ugw_status.sharing_blocked and ugw_status.sharing_blocked > 0) then
      luci.http.write([[<div class="cbi-value"><label class="ugw_blocking_message">]]..
            luci.i18n.translatef("Internet-Sharing is currently disabled for %s Minutes. It will be automatically reenabled, but you can enable it manually if you like.", ugw_status.sharing_blocked) ..
            [[</label></div>]])
    elseif (ugw_status.unblock_time) then
      luci.http.write([[<div class="cbi-value"><label class="ugw_blocking_message">]]..
            luci.i18n.translatef("Internet-Sharing will be automatically reenabled in between the next 5 Minutes. You can enable it manually if you like.", ugw_status.sharing_blocked) ..
            [[</label></div>]])
    end
    if ugw_status.sharing_enabled then
      luci.http.write('<div class="cbi-value"><label class="cbi-value-title">' .. luci.i18n.translate("suspend Internet-Sharing for") ..
        [[</label><div class="cbi-value-field"><select class="cbi-input-select" name="suspend_time">]]..
        '<option value="10">10 ' .. luci.i18n.translate("minutes") .. "</option>" ..
        '<option value="30">30 ' .. luci.i18n.translate("minutes") .. "</option>" ..
        '<option value="60">1 ' .. luci.i18n.translate("hour") .. "</option>" ..
        '<option value="120">2 ' .. luci.i18n.translate("hours") .. "</option>" ..
        '<option value="180">3 ' .. luci.i18n.translate("hours") .. "</option>" ..
        '<option value="360">6 ' .. luci.i18n.translate("hours") .. "</option>" ..
        '<option value="720">12 ' .. luci.i18n.translate("hours") .. "</option>" ..
        '<option value="1440">1 ' .. luci.i18n.translate("day") .. "</option>" ..
        [[</select><input id="suspend" type="submit" class="cbi-button" name="suspend" title="suspend" value="]]..
          luci.i18n.translate("suspend now") .. '" ')
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[/></div></div>]])
    end
    luci.http.write([[</form></fieldset></fieldset></div>]])
  end
end


function get_wan()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  wan = cursor:get("on-usergw", "opennet_ugw"..count, "wan")
  if not wan then wan = "" end
  luci.http.prepare_content("text/plain")
  luci.http.write('<div class="ugw-wan-route" name="wan" status="' .. wan .. '" >&#x00A0;</div>')
  luci.http.write(get_html_loading_spinner("wan_spinner", "display:none;"));
end


function update_wan()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.sys.exec("/usr/sbin/on_usergateway_check checkWan "..count)
  get_wan()
end


function get_wan_ping()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  ping = cursor:get("on-usergw", "opennet_ugw"..count, "ping")
  if not ping then
    ping = ""
  else
    ping = ping.." ms"
  end
  luci.http.prepare_content("text/plain")
  luci.http.write([[<div name="wan" id="cbi-network-lan-ping" >]]..ping..[[</div>]])
  luci.http.write(get_html_loading_spinner("wan_ping_spinner", "display:none;"));
end


function get_speed()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.http.prepare_content("text/plain")
  upload = cursor:get("on-usergw", "opennet_ugw"..count, "wan_speed_upload")
  download = cursor:get("on-usergw", "opennet_ugw"..count, "wan_speed_download")
  if upload or download then
    speed_time = os.date("%c", cursor:get("on-usergw", "opennet_ugw"..count, "wan_speed_timestamp"))
    if not upload or upload == "0" then upload = "?" end
    if not download or download == "0" then download = "?" end
    local speed = upload.." kbps / "..download.." kbps"
    local abbr = speed_time..luci.i18n.translatef("upload to Gateway %s kbit/s; download from Gateway %s kbit/s", upload, download)
    luci.http.write([[<div class="ugw-wan-speed" name="speed" id="cbi-network-lan-speed" ><abbr title="]]
      ..abbr..[[">]]..speed..[[</abbr></div>]])
  end
  luci.http.write(get_html_loading_spinner("speed_spinner", "display:none;"));
end


function update_speed()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.sys.exec("/usr/sbin/on_usergateway_check checkSpeed "..count)
  get_speed()
end


function get_mtu()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  local mtu = parse_csv_service(service_name, {
      out_wanted="number|value|mtu_out_wanted",
      out_real="number|value|mtu_out_real",
      in_wanted="number|value|mtu_in_wanted",
      in_real="number|value|mtu_in_real",
      timestamp="number|value|0|mtu_timestamp",
      status="bool|value|disabled|mtu_status"})
  luci.http.prepare_content("text/plain")
  if mtu.status then
    local timestring = os.date("%c", mtu.timestamp)
    luci.http.write([[<div class="ugw-mtu" name="mtu" status="]] .. bool_to_yn(v.status) .. [["><abbr title="]] .. timestring .. [[: ]]
      .. luci.i18n.translatef("(tried/measured) to Gateway: %s/%s from Gateway: %s/%s", mtu.out_wanted, mtu.out_real, mtu.in_wanted, mtu.in_real)
      .. [[">&#x00A0;&#x00A0;&#x00A0;&#x00A0;</abbr></div>]])
  end
  luci.http.write(get_html_loading_spinner("mtu_spinner", "display:none;"));
end


function update_mtu()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.sys.exec("/usr/sbin/on_usergateway_check checkMtu "..count)
  get_mtu()
end


function get_vpn()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.http.prepare_content("text/plain")
  local v = cursor:get_all("on-usergw", "opennet_ugw"..count)
  local v_age = luci.sys.exe(". /usr/lib/opennet/on-helper.sh; get_ugw_value "..v.ipaddr.." age")
  local v_status = luci.sys.exe(". /usr/lib/opennet/on-helper.sh; get_ugw_value "..v.ipaddr.." status")
  if not v_age then v_age = "" end
  if v_status then
    luci.http.write([[<div id="cbi-network-lan-status" name="vpn" status="]]..v_status..[["><abbr title="]]
      ..luci.i18n.translatef("tested %s minutes ago", v_age)
      ..[[">&#x00A0;&#x00A0;&#x00A0;&#x00A0;</abbr></div>]])
  end
  luci.http.write(get_html_loading_spinner("vpn_spinner", "display:none;"));
end


function update_vpn()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  cursor:delete("on-usergw", "opennet_ugw"..count, "age")
  cursor:commit("on-usergw")
  cursor:unload("on-usergw")
  luci.sys.exec("/usr/sbin/on_usergateway_check checkVpn "..count)
  get_vpn()
end


function get_tunnel_active(count)
  local name = cursor:get("on-usergw", "opennet_ugw"..count, "name")
  if not name then return false end
  return nixio.fs.access("/tmp/opennet_ugw-"..name..".txt")
end


function get_forward_active(count)
  local ipaddr = cursor:get("on-usergw", "opennet_ugw"..count, "ipaddr")
  if not ipaddr then return false end
  local forwarded_gw = tab_split(on_function("get_ugw_portforward"))[2]
  return forwarded_gw == ipaddr
end


function get_name_button()
  local SYSROOT = os.getenv("LUCI_SYSROOT") or ""
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]
  luci.http.prepare_content("text/plain")
  local v = cursor:get_all("on-usergw", "opennet_ugw"..count)
  luci.http.write([[<h3 count="]] .. count
      .. [[" tunnel="]] .. (get_tunnel_active(count) and luci.i18n.translate("ok") or luci.i18n.translate("inactive"))
      .. [[" forward="]] .. (get_forward_active(count) and luci.i18n.translate("ok") or luci.i18n.translate("irrelevant"))
      .. [["><input class="cbi-button" type="submit" title="]])
  if v and v.ipaddr and v.ipaddr ~= "" and not nixio.fs.access(SYSROOT.."/var/run/on_usergateway_check") then
    luci.http.write(luci.i18n.translatef("Click in order to switch Forwarding to Gateway %s (IP: %s)", v.name, v.ipaddr)
        ..[[" name="select_gw" value="]]..v.name..[[" /></h3>]])
  else
    luci.http.write(luci.i18n.translate("No IP-Address found for Gateway-Name, Gateway cannot be used")
        ..[[" name="select_gw" value="]]..v.name..[[" disabled="true" /></h3>]])
  end
end


function check_running()
  local SYSROOT = os.getenv("LUCI_SYSROOT") or ""
  luci.http.prepare_content("text/plain")
  if nixio.fs.access(SYSROOT.."/var/run/on_usergateway_check") then
    luci.http.write("script running")
  else
    luci.http.write("")
  end
end
