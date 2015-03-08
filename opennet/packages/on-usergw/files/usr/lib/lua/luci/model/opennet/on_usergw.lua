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

