--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--

require "nixio"
local uci = require "luci.model.uci"
local cursor = uci.cursor()

function gw_name(str)
  if not str then return nil end
  local t = "opennet_ugw"
  str:gsub("%a+", function (w) t = t.."_"..w end)
  return t
end

function number_of_gateways()
  local count = 0
  cursor:foreach ("on-usergw", "usergateway", function() count = count + 1 end)
  return count
end

function searchUGW(name)
  local count = 1
  while count <= number_of_gateways() do
    if gw_name(cursor:get("on-usergw", "opennet_ugw"..count, "name")) == name then
      return true
    end
    count = count + 1
  end
  return nil
end

function reinitUGWs()
  nixio.syslog("info", "on_usergw_syncconfig: no usergateways found, adding default usergateways")
  local openvpn_preset = cursor:get_all("on-usergw", "opennet_ugw")
  for k, v in pairs(cursor:get_all("on-usergw")) do
    if v[".type"] == "usergw" then                         
      for index,name in pairs(cursor:get_list("on-usergw",k,"name")) do
        cursor:section("on-usergw", "usergateway", "opennet_ugw"..index)
        cursor:set("on-usergw", "opennet_ugw"..index, "name", name)
        local new_section = cursor:section("openvpn", "openvpn", gw_name(name), openvpn_preset)
        cursor:set("openvpn", new_section, "remote", name)
      end
    end
  end
  cursor:commit("on-usergw")
  cursor:unload("on-usergw")
end

function checkVPNConfig()
  local openvpn_preset = cursor:get_all("on-usergw", "opennet_ugw")

  for k, v in pairs(cursor:get_all("openvpn")) do
    if v[".type"] == "openvpn" and v.rport == openvpn_preset.rport then
      if not searchUGW(v[".name"]) then
        if v.enable ~= "1" then
          -- this shoudn't happen, anyway... Initscript won't shut down the gateway if it is not enabled
          cursor:set("openvpn", v[".name"], "enable", "1")
          cursor:commit("openvpn")
          cursor:unload("openvpn")
        end
        os.execute("/etc/init.d/openvpn down "..v[".name"])
        cursor:delete("openvpn", v[".name"])
      end
    end
  end

  local found_one = false
  for k, v in pairs(cursor:get_all("on-usergw")) do
    if v[".type"] == "usergateway" then
      found_one = true
      if not cursor:get("openvpn", gw_name(v.name)) then
        local new_section = cursor:section("openvpn", "openvpn", gw_name(v.name), openvpn_preset)
        cursor:set("openvpn", new_section, "remote", v.name)
      end
    end
  end
  
  if not found_one then
    reinitUGWs()
  end
  
  cursor:commit("openvpn")
  cursor:unload("openvpn")
end

