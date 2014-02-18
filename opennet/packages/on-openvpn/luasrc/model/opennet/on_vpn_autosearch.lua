--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--
require "luci.sys"
local uci = require "luci.model.uci"
local cursor = uci.cursor()


function read_services()
  f = io.open("/var/run/services_olsr", "r")
  services_elem = {}
  if f then
    for line in f:lines() do
      line:gsub("^http://.*", function (w)
        ipaddr = nil
        w:gsub("[%d\.]+", function(z) ipaddr = z end, 1)
        if not services_elem[ipaddr] then
          services_elem[ipaddr] = {}
          w:gsub("[%a]+:[%d]+", function(z)
            temp_table = {}
            z:gsub("[^:]+", function(b)
                table.insert(temp_table, b)
            end
            )
            if temp_table then
              services_elem[ipaddr][temp_table[1]] = temp_table[2]
            end
          end
          )
        end
      end
      )
    end  
    f:close()
  end
  return services_elem
end

function gw_parse(gateways, gws_access, services_olsr, line)
  local tmp_elem = {}
  line:gsub("[^:]+", function (w) table.insert(tmp_elem, w) end)

  if not gws_access[tmp_elem[1]] then
    new_gw = {}
    gws_access[tmp_elem[1]] = new_gw
    gws_access[tmp_elem[1]].ipaddr = tmp_elem[1]
  end
  table.insert(gateways, gws_access[tmp_elem[1]])
  gws_access[tmp_elem[1]].hop = tmp_elem[2]
  gws_access[tmp_elem[1]].etx = tmp_elem[3]
  
  if services_olsr[tmp_elem[1]] then
    gws_access[tmp_elem[1]].upload = services_olsr[tmp_elem[1]].upload
    gws_access[tmp_elem[1]].download = services_olsr[tmp_elem[1]].download
    gws_access[tmp_elem[1]].ping = services_olsr[tmp_elem[1]].ping
  end

  if not gws_access[tmp_elem[1]].etx_offset then
    gws_access[tmp_elem[1]].etx_offset = 0
  end
end

function crazy_add(a, b)
  if a and b then
    return a+b
  else
    return 9999+1
  end
end

function gw_sort(a, b)
  local val_a
  local val_b
  if cursor:get("on-openvpn", "gateways", "vpn_sort_criteria") == "etx" then
    val_a = crazy_add(a.etx, a.etx_offset)
    val_b = crazy_add(b.etx, b.etx_offset)
  else
    val_a = crazy_add(a.hop, a.etx_offset)
    val_b = crazy_add(b.hop, b.etx_offset)
  end

  if (val_a == val_b) then
    local order = cursor:get("on-core", "settings", "on_id")
    if order and (order:sub(-1)%2 == 0) then
      return a.ipaddr < b.ipaddr
    else
      return a.ipaddr > b.ipaddr
    end
  end
  
  return (val_a < val_b)
end

function search_gateways()
  local number = 1
  local old_gws = cursor:get_all("on-openvpn", "gate_"..number)
  -- create two tables, one numeric and one associative to access elements by ip-address
  local gateways = {}
  local gws_access = {}
  
  -- build table of all gateways indexed by ip-address
  while old_gws do
--     table.insert(gateways, old_gws)
    gws_access[old_gws.ipaddr] = old_gws
    number = number + 1
    old_gws = cursor:get_all("on-openvpn", "gate_"..number)
  end
  
  gw_filter = cursor:get("on-openvpn", "gateways", "searchmask")
  cmd = "echo \"/route\" | nc localhost 2006 | awk 'BEGIN {FS=\"[/\\x09]+\"} "..gw_filter.." {print $1\":\"$4\":\"$5}'"
  local new_gws = luci.sys.exec(cmd)
  
  local services_olsr = read_services()
  
  -- add found gateways to table
  new_gws:gsub("%S+", function (w) gw_parse(gateways, gws_access, services_olsr, w) end)
  
  table.sort(gateways, function(a,b) return gw_sort(a, b, criteria,order) end)
  
  -- remove all gateways
  cursor:delete_all("on-openvpn", "gateway")
  -- add them with new order
  local index = 1
  for k,gw in pairs(gateways) do
    if (gw.hop) then
      if gw.etx_offset == 0 then
        gw.etx_offset = nil
      end
      cursor:section("on-openvpn", "gateway", "gate_"..index, gw)
      index = index + 1
    end
--     print("k=" , k , "gw=", gw.ipaddr, " hop=", gw.hop, " etx=", gw.etx, " offset=", gw.etx_offset, " status=", gw.status, " age=", gw.age)
  end
  
  cursor:commit("on-openvpn")
end

search_gateways()