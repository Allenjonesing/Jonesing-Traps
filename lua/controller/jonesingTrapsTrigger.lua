-- lua/vehicle/controller/jonesingTrapsTrigger.lua

local M = {}

local function logSafe(level, msg)
  if log then pcall(log, level, "jonesingTrapsTrigger", tostring(msg)) end
end

local function num(v, fallback)
  v = tonumber(v)
  if v == nil then return fallback end
  return v
end

local function ensureGE(config)
  if not obj or not obj.queueGameEngineLua then return end

  config = config or {}

  obj:queueGameEngineLua(string.format([[
    extensions.load("gameplay_vehicleTrap")

    if extensions.gameplay_vehicleTrap then
      extensions.gameplay_vehicleTrap.configure({
        cooldown = %.6f,
        poolSize = %d,
        placeBehindDistance = %.6f,
        rockPilePoolSize = %d,
        rockPileHeightOffset = %.6f,
        rockPileRotationOffsetDeg = %.6f,
        spikeStripPoolSize = %d,
        spikeStripHeightOffset = %.6f,
        spikeStripRotationOffsetDeg = %.6f,
        steelCoilPoolSize = %d,
        steelCoilHeightOffset = %.6f,
        steelCoilRotationOffsetDeg = %.6f
      })
      extensions.gameplay_vehicleTrap.setEnabled(true)
    end
  ]],
    num(config.cooldown, 0.25),
    math.max(1, math.floor(num(config.poolSize, 5))),
    num(config.placeBehindDistance, 5.0),
    math.max(1, math.floor(num(config.rockPilePoolSize, 5))),
    num(config.rockPileHeightOffset, 0),
    num(config.rockPileRotationOffsetDeg, 0),
    math.max(1, math.floor(num(config.spikeStripPoolSize, 5))),
    num(config.spikeStripHeightOffset, 0),
    num(config.spikeStripRotationOffsetDeg, 0),
    math.max(1, math.floor(num(config.steelCoilPoolSize, 5))),
    num(config.steelCoilHeightOffset, 1.5),
    num(config.steelCoilRotationOffsetDeg, 0)
  ))
end

local function init(jbeamData)
  logSafe("I", "loaded")
  ensureGE(jbeamData)
end

M.init = init

return M