-- Executed inside Aseprite batch mode. If Lua scripting were not compiled in,
-- Aseprite could not interpret this file and the report would never appear, so the
-- verification step would fail. A Lua syntax error also proves the interpreter runs.
local out = os.getenv("LUA_REPORT") or "lua-report.txt"
local f = assert(io.open(out, "w"))
f:write("scripts_enabled=1\n")
f:write("lua_version=" .. tostring(_VERSION) .. "\n")

local oka, api = pcall(function() return app.apiVersion end)
if oka and api ~= nil then
  f:write("app_api_version=" .. tostring(api) .. "\n")
end

local okv, ver = pcall(function() return app.version end)
if okv and ver ~= nil then
  local oks, s = pcall(function() return tostring(ver) end)
  if oks then
    f:write("app_version=" .. tostring(s) .. "\n")
  end
end

f:write("lua_script_executed=1\n")
f:close()
print("LUA_CHECK_OK")
