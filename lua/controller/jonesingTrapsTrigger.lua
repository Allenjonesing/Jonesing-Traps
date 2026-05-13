-- lua/vehicle/controller/jonesingTrapsTrigger.lua

local M = {}

local function logSafe(level, msg)
  if log then pcall(log, level, "jonesingTrapsTrigger", tostring(msg)) end
end

local function ensureGE()
  if not obj or not obj.queueGameEngineLua then return end

  obj:queueGameEngineLua([[
    extensions.load("gameplay_vehicleTrap")

    if extensions.gameplay_vehicleTrap then
      extensions.gameplay_vehicleTrap.setEnabled(true)
    end
  ]])
end

local function init(jbeamData)
  logSafe("I", "loaded")
  ensureGE()
end

M.init = init

return M