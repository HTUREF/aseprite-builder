-- Executed inside Aseprite batch mode. If Lua scripting is not compiled in,
-- Aseprite cannot interpret this file, so the report never appears and the
-- verification step fails deliberately.
local out = os.getenv("LUA_REPORT") or "lua-report.txt"
local f = assert(io.open(out, "w"))
f:write("scripts_enabled=1
")
f:write("lua_version=" .. tostring(_VERSION) .. "
")

local okv, ver = pcall(function() return app.version end)
if okv and ver ~= nil then
  f:write("app_version_type=" .. type(ver) .. "
")
  local oks, s = pcall(function() return tostring(ver) end)
  if oks then f:write("app_version=" .. tostring(s) .. "
") end
end

local oka, api = pcall(function() return app.apiVersion end)
if oka and api ~= nil then f:write("app_api_version=" .. tostring(api) .. "
") end

local okf, abs = pcall(function() return app.fs.isAbsolute("C:\") end)
if okf then f:write("app_fs_ok=" .. tostring(abs) .. "
") end

f:write("lua_script_executed=1
")
f:close()
print("LUA_CHECK_OK")
