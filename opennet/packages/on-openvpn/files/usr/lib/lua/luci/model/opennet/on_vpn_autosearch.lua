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


--[[
Parse eine olsr-service-Datei

Beispielhafte Eintraege:
  http://192.168.0.15:8080|tcp|ugw upload:3 download:490 ping:108         #192.168.2.15
  dns://192.168.10.4:53|udp|dns                                           #192.168.10.4

Das Ergebnis ist ein assoziatives Array der Form:
  array[IP-Adresse][Schluessel] = Wert
"Schluessel" ist dabei beispielsweise "upload"
]]--
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

function get_gateway_flag(ip, key)
  return luci.sys.exec("vpn_status get_gateway_flag '"..ip.."' '"..key.."'")
end

function set_gateway_flag(ip, key, value)
  luci.sys.exec("vpn_status set_gateway_flag '"..ip.."' '"..key.."' '"..value.."'")
end

function delete_gateway_flag(ip, key)
  set_gateway_flag(ip, key, "")
end

function gw_parse(gateways, gws_access, services_olsr, line)
  local tmp_elem = {}
  line:gsub("[^:]+", function (w) table.insert(tmp_elem, w) end)
  local ipaddr = tmp_elem[1]
  if not gws_access[ipaddr] then
    new_gw = {}
    gws_access[ipaddr] = new_gw
    gws_access[ipaddr].ipaddr = ipaddr
  end
  table.insert(gateways, gws_access[ipaddr])
  set_gateway_flag(ipaddr, "hop", tmp_elem[2])
  set_gateway_flag(ipaddr, "etx", tmp_elem[3])
  
  if services_olsr[ipaddr] then
    set_gateway_flag(ipaddr, "upload", services_olsr[ipaddr].upload)
    set_gateway_flag(ipaddr, "download", services_olsr[ipaddr].download)
    set_gateway_flag(ipaddr, "ping", services_olsr[ipaddr].ping)
  end

  if not get_gateway_flag(ipaddr, "etx_offset") then
    set_gateway_flag(ipaddr, "etx_offset", 0)
  end
end

function crazy_add(a, b)
  if a and b then
    return a+b
  else
    return 9999+1
  end
end

--[[
liefere wahr/falsch fuer die Sortierung zweier IP-Adressen
Das primaere Sortierkriterium ist die Routing-Entfernung (etx).
Bei Gleichheit (z.B. oft bei UGWs - da jeweils ein Hop zu erina/subaru vorliegt) wird
je nach Paritaet (gerade/ungerade) der eigenen AP-Nummer entschieden.
]]--
function gw_sort(a, b)
  local val_a
  local val_b
  local a_offset
  local b_offset
  if cursor:get("on-openvpn", "gateways", "vpn_sort_criteria") == "etx" then
    val_a = get_gateway_flag(a.ipaddr, "etx")
    val_b = get_gateway_flag(b.ipaddr, "etx")
  else
    val_a = get_gateway_flag(a.ipaddr, "hop")
    val_b = get_gateway_flag(b.ipaddr, "hop")
  end
  val_a = crazy_add(val_a, get_gateway_flag(a.ipaddr, "etx_offset"))
  val_b = crazy_add(val_b, get_gateway_flag(b.ipaddr, "etx_offset"))

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

--[[
Einlesen aktueller Gateway-Informationen (hops, etx, download, upload, ping).
Neue Werte werden in die Datenbank ('[sg]et_gateway_flag') geschrieben.
Abschliessend wird der uci-Namensraum "on-openvpn.gate*" mit der aktuellen Reihenfolge neu geschrieben.
Es gibt keinen Rueckgabewert.
]]--
function update_gateways()
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
    if (get_gateway_flag(gw.ipaddr, "hop")) then
      if get_gateway_flag(gw.ipaddr, "etx_offset") == "0" then
        delete_gateway_flag(gw.ipaddr, "etx_offset")
      end
      cursor:section("on-openvpn", "gateway", "gate_"..index, gw)
      index = index + 1
    end
--     print("k=" , k , "gw=", gw.ipaddr, " hop=", gw.hop, " etx=", gw.etx, " offset=", gw.etx_offset, " status=", gw.status, " age=", gw.age)
  end
  
  cursor:commit("on-openvpn")
end

