--[[
Opennet Firmware

Copyright 2010 Rene Ejury <opennet@absorb.it>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: opennet.lua 5485 2009-11-01 14:24:04Z jow $
]]--

require("luci.sys")
local uci = require "luci.model.uci"
local cursor = uci.cursor()

function split(str)
    local t = { }
    str:gsub("%d+", function (w) table.insert(t, w) end)
    return t
end

-- aquire new random HNA
function newHNA()
  require("math")
  math.randomseed( os.time() )
  return cursor:get("on-usergw", "ugwng_hna_mask").."."..math.random(1,199)
end

-- aquire HNA from ID
function getHNAfromID()
  id = cursor:get("on-core", "settings", "on_id")
  if id then
    return cursor:get("on-usergw", "ugwng_hna_mask").."."..split(id)[2]
  else
    return nil
  end
end

-- aquire new HNA
-- try long as it's not the same than before and no collissions are detected
function getNewHNA(hna, orig_hna)
  while not hna or luci.sys.exec([[ip route show table olsrd | grep "^]]..hna..[[ "]]) ~= "" and hna ~= orig_hna do
    hna = newHNA()
  end
  return hna
end  

-- aquire new HNA, prefer HNA based on ID if there is no collision
function changeHNA()
  local orig_hna = cursor:get("on-usergw", "ugwng_hna")
  local hna = nil
  if orig_hna ~= getHNAfromID() then
    hna = getHNAfromID()
  end
  local result_hna = getNewHNA(hna, orig_hna)
  cursor:set("on-usergw", "ugwng_hna", result_hna)
  cursor:commit("on-usergw")
  return result_hna
end

-- returns new HNA if required (collission or something else)
-- return nil if current HNA is still ok.
function checkHNA()
  local orig_hna = cursor:get("on-usergw", "ugwng_hna")
  local hna = nil
  if orig_hna and luci.sys.exec([[ip route show table olsrd | grep "^]]..orig_hna..[[ "]]) == "" then
    hna = orig_hna
  end
  if not hna then
    hna = getHNAfromID()
  end
  hna = getNewHNA(hna, orig_hna)
  if hna ~= orig_hna then
    return hna
  end
  return nil
end

-- set new HNA if required (collission or something else)
-- do nothing if current HNA is still ok.
function replaceHNA()
  new_hna=checkHNA()
  if new_hna then
    cursor:set("on-usergw", "ugwng_hna", new_hna)
    cursor:commit("on-usergw")
    cursor:unload("on-usergw")
    io.write(new_hna)
  end
end

-- get current HNA, replace with working one if current
-- can't be used (anymore)
function getHNA()
  new_hna=checkHNA()
  if new_hna then
    cursor:set("on-usergw", "ugwng_hna", new_hna)
    cursor:commit("on-usergw")
    cursor:unload("on-usergw")
  end
	return cursor:get("on-usergw", "ugwng_hna")
end
