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
require "luci.config"
resource = luci.config.main.resourcebase
require("luci.i18n")

function get_ugw_status(ugw_status)
    ugw_status.usergateways_no = 0
    cursor:foreach ("on-usergw", "usergateway", function() ugw_status.usergateways_no = ugw_status.usergateways_no + 1 end)
  
    -- central gateway-IPs reachable over tap-devices
    ugw_status.centralips = luci.sys.exec("for gw in $(uci -q get on-usergw.@usergw[0].centralIP); do ip route get $gw | awk '/dev tap/ {print $1}' ; done")
    local words
    ugw_status.centralips_no = 0
    for words in string.gfind(ugw_status.centralips, "[^%s]+") do ugw_status.centralips_no=ugw_status.centralips_no+1 end
    ugw_status.centralip_status = "error"
    if ugw_status.centralips_no >= 1 then ugw_status.centralip_status = "ok" end
    -- tunnel active
    local iterator, number = nixio.fs.glob("/tmp/opennet_ugw-*.txt")
    ugw_status.tunnel_active = (number >= 1)
    
    -- if the forward is set, the sharing is active
    ugw_status.forwarded_ip = luci.sys.exec("iptables -L zone_opennet_prerouting -t nat -n | awk 'BEGIN{FS=\"[ :]+\"} /udp dpt:1600 to:/ {printf \$5; exit}'")
    ugw_status.forwarded_gw = luci.sys.exec("iptables -L zone_opennet_prerouting -t nat -n | awk 'BEGIN{FS=\"[ :]+\"} /udp dpt:1600 to:/ {printf \$10; exit}'")
    
    -- sharing possible
    ugw_status.sharing_wan_ok = false
    ugw_status.sharing_possible = false
    local count = 1
    while count <= ugw_status.usergateways_no do
        local onusergw = cursor:get_all("on-usergw", "opennet_ugw"..count)
        if (onusergw.wan == "ok") then ugw_status.sharing_wan_ok = true end
        if (onusergw.wan == "ok" and onusergw.mtu == "ok") then
            ugw_status.sharing_possible = true
        end
        if onusergw.ipaddr == ugw_status.forwarded_gw then
          ugw_status.forwarded_count = count
        end
        count = count + 1
    end
    -- sharing enabled
    ugw_status.sharing_enabled = (cursor:get("on-usergw", "ugw_sharing", "shareInternet") == "on")
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
  if (ugw_status.centralip_status == "ok") or (ugw_status.forwarded_gw ~= "") then
    luci.http.write(luci.i18n.string([[Internet shared]]).." (")
    if (ugw_status.centralip_status == "ok") then
      luci.http.write(luci.i18n.string([[Central Gateways connected locally]]))
    end
    if ugw_status.forwarded_gw ~= "" then
      luci.http.write(", "..luci.i18n.string([[Gateway-Forward activated]]))
    end
    luci.http.write(")")
  elseif ugw_status.tunnel_active then
    luci.http.write(luci.i18n.string([[Internet not shared]]).."( "..luci.i18n.string([[Internet-Sharing enabled]])..
      ", "..luci.i18n.string([[Usergateway-Tunnel active]])..")")
  elseif ugw_status.sharing_enabled then
    luci.http.write(luci.i18n.string([[Internet not shared]]).."( "..luci.i18n.string([[Internet-Sharing enabled]])..
      ", "..luci.i18n.string([[Usergateway-Tunnel not running]])..")")
  elseif ugw_status.sharing_possible then
    luci.http.write(luci.i18n.string([[Internet not shared]])..", "..luci.i18n.string([[Internet-Sharing possible]]))
  else
    luci.http.write(luci.i18n.string([[Internet-Sharing impossible]]))
  end
  luci.http.write([[</h4></td></tr>]])
  if cursor:get("on-usergw", "ugwng_hna") then
    luci.http.write([[<tr><td><h4 class="on_ugw-ugws-status">]])
    luci.http.write(luci.i18n.string([[<abbr title='Annouced Address, which stands for the local Gateway. This address might be changed automatically if it is announced by some other Gateway in the network'>Usergateway-Address</abbr>:]]))
    luci.http.write(" <span id='hna'>"..cursor:get("on-usergw", "ugwng_hna").."</span> ")
    if not ugw_status.sharing_enabled then
      luci.http.write([[<input id="update_hna_address" class="cbi-button" type="submit" title="]]..luci.i18n.string([[Change announced HNA Address]])..
        [[" value="]]..luci.i18n.string([[change Address]])..[[" onclick="return change_hna();" ]])
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[  />]])
    end
    luci.http.write([[</h4></td></tr>]])
  end
  if ugw_status.tunnel_active then
    luci.http.write([[<tr class="cbi-section-table-titles"><td /><td colspan="1"><label class="cbi-value-ugwstatus">]])
    if ugw_status.centralips_no == 0 then
      luci.http.write(luci.i18n.string([[no central Gateway-IPs connected trough tunnel]]))
    elseif ugw_status.centralips_no == 1 then 
      luci.http.write(luci.i18n.stringf([[central Gateway-IP %s connected trough tunnel]], ugw_status.centralips))
    else
      luci.http.write(luci.i18n.stringf([[central Gateway-IPs %s connected trough tunnel]], ugw_status.centralips))
    end
    if ugw_status.forwarded_gw ~= "" then
      luci.http.write(", "..luci.i18n.stringf([[Gateway-Forward from %s to %s activated]], ugw_status.forwarded_ip, ugw_status.forwarded_gw))
    end
    luci.http.write([[</label></td></tr>]])
  end
  luci.http.write([[</table></fieldset></fieldset></div>]])
  
  if ugw_status.sharing_possible or ugw_status.sharing_enabled then
    luci.http.write([[<h3>]]..luci.i18n.string([[Manage Internet-Sharing]])..
      [[</h3><div class="cbi-map"><fieldset class="cbi-section"><fieldset class="cbi-section-node">]])
    luci.http.write([[<h4 id="running_1" hidden="true"><div class="errorbox">]]..
      luci.i18n.string([[automated check is running, manual modifications are temporarily disabled]])..[[</div><br /><br /></h4>]])
    luci.http.write([[<form method="post"><div class="cbi-value">]])
    if ugw_status.sharing_enabled then
      luci.http.write([[<label class="cbi-value-title">]]..luci.i18n.string([[Internet-Sharing enabled]])..[[</label>]])
      luci.http.write([[<div class="cbi-value-field"><input id="enable" type="submit" class="cbi-button" name="disable_sharing" value="]]..
        luci.i18n.string([[disable Sharing]])..[[" ]])
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[/></div>]])
    else
      luci.http.write([[<label class="cbi-value-title">]]..luci.i18n.string([[Internet-Sharing disabled]])..[[</label>]])
      luci.http.write([[<div class="cbi-value-field"><input id="enable" type="submit" class="cbi-button" name="enable_sharing" value="]]..
        luci.i18n.string([[enable Sharing]])..[[" ]])
      if autocheck_running then luci.http.write([[disabled="true"]]) end
      luci.http.write([[/></div>]])
    end
    luci.http.write([[</div>]])
    if (ugw_status.sharing_blocked and ugw_status.sharing_blocked > 0) then
      luci.http.write([[<div class="cbi-value"><label class="ugw_blocking_message">]]..
            luci.i18n.stringf([[Internet-Sharing is currently disabled for %s Minutes. It will be automatically reenabled, but you can enable it manually if you like.]], ugw_status.sharing_blocked)..
            [[</label></div>]])
    elseif (ugw_status.unblock_time) then
      luci.http.write([[<div class="cbi-value"><label class="ugw_blocking_message">]]..
            luci.i18n.stringf([[Internet-Sharing will be automatically reenabled in between the next 5 Minutes. You can enable it manually if you like.]], ugw_status.sharing_blocked)..
            [[</label></div>]])
    end
    if ugw_status.sharing_enabled then
      luci.http.write([[<div class="cbi-value"><label class="cbi-value-title">]]..luci.i18n.string([[suspend Internet-Sharing for]])..
        [[</label><div class="cbi-value-field"><select class="cbi-input-select" name="suspend_time">]]..
        [[<option value="10">10 ]]..luci.i18n.string([[minutes]])..[[</option>]]..
        [[<option value="30">30 ]]..luci.i18n.string([[minutes]])..[[</option>]]..
        [[<option value="60">1 ]]..luci.i18n.string([[hour]])..[[</option>]]..
        [[<option value="120">2 ]]..luci.i18n.string([[hours]])..[[</option>]]..
        [[<option value="180">3 ]]..luci.i18n.string([[hours]])..[[</option>]]..
        [[<option value="360">6 ]]..luci.i18n.string([[hours]])..[[</option>]]..
        [[<option value="720">12 ]]..luci.i18n.string([[hours]])..[[</option>]]..
        [[<option value="1440">1 ]]..luci.i18n.string([[day]])..[[</option>]]..
        [[</select><input id="suspend" type="submit" class="cbi-button" name="suspend" title="suspend" value="]]..
          luci.i18n.string([[suspend now]])..[[" ]])
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
  luci.http.write([[<div class="ugw-wan-route" name="wan" status="]]..wan..[[" >&#x00A0;</div>]])
  luci.http.write([[<img class='loading_img_small' name="wan_spinner" src=']]..resource..[[/icons/loading.gif' alt=']]..
    luci.i18n.string([[Loading]])..[[' style="display:none;" />]])
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
  luci.http.write([[<img class='loading_img_small' name="wan_spinner" src=']]..resource..[[/icons/loading.gif' alt=']]..
    luci.i18n.string([[Loading]])..[[' style="display:none;" />]])
end

function get_speed()
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]  
  luci.http.prepare_content("text/plain")
  upload = cursor:get("on-usergw", "opennet_ugw"..count, "upload")
  download = cursor:get("on-usergw", "opennet_ugw"..count, "download")
  if upload or download then
    speed_time = os.date("%c", cursor:get("on-usergw", "opennet_ugw"..count, "speed_time"))
    if not upload or upload == "0" then upload = "?" end
    if not download or download == "0" then download = "?" end
    local speed = upload.." kbps / "..download.." kbps"
    local abbr = speed_time..luci.i18n.stringf([[: upload to Gateway %s kbit/s; download from Gateway %s kbit/s]], upload, download)
    luci.http.write([[<div class="ugw-wan-speed" name="speed" id="cbi-network-lan-speed" ><abbr title="]]
      ..abbr..[[">]]..speed..[[</abbr></div>]])
  end
  luci.http.write([[<img class='loading_img_small' name="speed_spinner" src=']]..resource..[[/icons/loading.gif' alt=']]..
    luci.i18n.string([[Loading]])..[[' style="display:none;" />]])
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
  luci.http.prepare_content("text/plain")
  local v = cursor:get_all("on-usergw", "opennet_ugw"..count)
  if v.mtu then
    mtu_time = os.date("%c", cursor:get("on-usergw", "opennet_ugw"..count, "mtu_time"))
    luci.http.write([[<div class="ugw-mtu" name="mtu" status="]]..v.mtu..[["><abbr title="]]..mtu_time..[[: ]]
      ..luci.i18n.stringf([[(tried/measured) to Gateway: %s/%s from Gateway: %s/%s]], v.mtu_toGW_tried, v.mtu_toGW_actual, v.mtu_fromGW_tried, v.mtu_fromGW_actual)
      ..[[">&#x00A0;&#x00A0;&#x00A0;&#x00A0;</abbr></div>]])
  end
  luci.http.write([[<img class='loading_img_small' name="mtu_spinner" src=']]..resource..[[/icons/loading.gif' alt=']]..
    luci.i18n.string([[Loading]])..[[' style="display:none;" />]])
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
  if not v.age then v.age = "" end
  if v.status then
    luci.http.write([[<div id="cbi-network-lan-status" name="vpn" status="]]..v.status..[["><abbr title="]]
      ..luci.i18n.stringf([[tested %s minutes ago]], v.age)
      ..[[">&#x00A0;&#x00A0;&#x00A0;&#x00A0;</abbr></div>]])
  end
  luci.http.write([[<img class='loading_img_small' name="vpn_spinner" src=']]..resource..[[/icons/loading.gif' alt=']]..
    luci.i18n.string([[Loading]])..[[' style="display:none;" />]])
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
  if not name then name = "" end
  local returnValue = "inactive"
  if nixio.fs.access("/tmp/opennet_ugw-"..name..".txt") then returnValue = "ok" end
  return returnValue
end

function get_forward_active(count)
  local ipaddr = cursor:get("on-usergw", "opennet_ugw"..count, "ipaddr")
  local returnValue = "irrelevant"
  if ipaddr then
    local forwarded_gw = luci.sys.exec("iptables -L zone_opennet_prerouting -t nat -n | awk 'BEGIN{FS=\"[ :]+\"} /udp dpt:1600 to:/ {printf \$10; exit}'")
    if forwarded_gw == ipaddr then returnValue = "ok" end
  end
  return returnValue
end
  
function get_name_button()
  local SYSROOT = os.getenv("LUCI_SYSROOT")
  if not SYSROOT then SYSROOT = "" end        -- SYSROOT is only used for local testing (make runhttpd in luci tree)
  local path = luci.dispatcher.context.requestpath
  local count = path[#path]  
  luci.http.prepare_content("text/plain")
  local v = cursor:get_all("on-usergw", "opennet_ugw"..count)
  if v and v.ipaddr and v.ipaddr ~= "" and not nixio.fs.access(SYSROOT.."/var/run/on_usergateway_check") then
    luci.http.write([[<h3 count="]]..count..[[" tunnel="]]..get_tunnel_active(count)..[[" forward="]]..get_forward_active(count)..[["><input class="cbi-button" type="submit" title="]]
      ..luci.i18n.stringf([[Click to switch Forwarding to Gateway %s (IP: %s)]], v.name, v.ipaddr)
      ..[[" name="select_gw" value="]]..v.name..[[" /></h3>]])
  else
    luci.http.write([[<h3 count="]]..count..[[" tunnel="]]..get_tunnel_active(count)..[[" forward="]]..get_forward_active(count)..[["><input class="cbi-button" type="submit" title="]]
      ..luci.i18n.string([[No IP-Address found for Gateway-Name, Gateway cannot be used]])
      ..[[" name="select_gw" value="]]..v.name..[[" disabled="true" /></h3>]])
  end
end

function check_running()
  local SYSROOT = os.getenv("LUCI_SYSROOT")
  if not SYSROOT then SYSROOT = "" end        -- SYSROOT is only used for local testing (make runhttpd in luci tree)
  luci.http.prepare_content("text/plain")
  if nixio.fs.access(SYSROOT.."/var/run/on_usergateway_check") then
    luci.http.write("script running")
  else
    luci.http.write("")
  end
end

function change_hna()
  require('luci.model.opennet.on_hna_check')
  luci.http.prepare_content("text/plain")
  luci.http.write(changeHNA())
end


function upgrade()
  -- set hna_mask if not yet set to preset
  if not cursor:get("on-usergw", "ugwng_hna_mask") then
    local preset_cursor = uci.cursor()
    preset_cursor:set_confdir("/etc/config_presets")
    cursor:set("on-usergw", "ugwng_hna_mask", preset_cursor:get("on-usergw", "ugwng_hna_mask"))
  end

  -- transfer all openvpn-remote-names back to on-usergw and remove openvpn entries
  local count = 1
  local number_of_gateways = 0
  cursor:foreach ("on-usergw", "usergateway", function() number_of_gateways = number_of_gateways + 1 end)
  while count <= number_of_gateways do
    local name = cursor:get("on-usergw", "opennet_ugw"..count, "name")
    if not name or name == "" then
      remote = cursor:get("openvpn", "opennet_ugw"..count, "remote")
      if remote then
        cursor:set("on-usergw", "opennet_ugw"..count, "name", remote)
      end
      cursor:delete("openvpn", "opennet_ugw"..count)
    end
    count = count + 1
  end

  cursor:commit("openvpn")
  cursor:commit("on-usergw")
end