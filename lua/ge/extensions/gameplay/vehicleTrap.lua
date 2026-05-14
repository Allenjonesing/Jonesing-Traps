-- lua/ge/extensions/gameplay/vehicleTrap.lua
-- Jonesing Destruction Mod - Vehicle Trap Spawner

local M = {}

local enabled = true
local cooldown = 0.25
local triggerTimer = 0

local poolSize = 5
local pool = {}
local poolReady = false
local poolLoading = false
local spawnedCount = 0

local hiddenZ = -1000
local hiddenSpacing = 8

local placeBehindDistance = 5.0
local groundRayStartHeight = 50
local groundRayLength = 250

local landMineModel = "mineJ"
local landMineConfig = "vehicles/mineJ/Normal.pc"

local hudText = "Jonesing Land Mine LOADING"
local lastMsg = {}
local lastLog = {}

local function V(x, y, z)
  return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
end

local function vf(o)
  if not o then return nil end
  return V(o.x, o.y, o.z)
end

local function add(a, b) return V(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return V(a.x - b.x, a.y - b.y, a.z - b.z) end
local function mul(a, s) return V(a.x * s, a.y * s, a.z * s) end
local function len(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

local function norm(a, fallback)
  local l = len(a)
  if l < 0.0001 then return fallback or V(0, 1, 0) end
  return V(a.x / l, a.y / l, a.z / l)
end

local function point(v)
  if Point3F then return Point3F(v.x, v.y, v.z) end
  return v
end

local function now()
  return os.clock and os.clock() or 0
end

local function logSafe(level, tag, text)
  if log then pcall(log, level, tag, tostring(text)) end
end

local function shouldLog(key, interval)
  local t = now()
  if t - (lastLog[key] or -1e9) >= interval then
    lastLog[key] = t
    return true
  end
  return false
end

local function msg(text, ttl, key, interval)
  key = key or text
  interval = interval or 0.5

  local t = now()
  if t - (lastMsg[key] or -1e9) < interval then return end
  lastMsg[key] = t

  if ui_message then
    pcall(ui_message, tostring(text), ttl or 1.5, "jonesingLandMine")
  elseif guihooks and guihooks.trigger then
    pcall(guihooks.trigger, "Message", {
      ttl = ttl or 1.5,
      msg = tostring(text),
      category = "jonesingLandMine",
      icon = "warning"
    })
  end
end

local function centerLoader(text)
  hudText = tostring(text or "Loading land mines...")

  if guihooks and guihooks.trigger then
    pcall(guihooks.trigger, "Message", {
      ttl = 1.0,
      msg = hudText,
      category = "jonesingLandMineLoader",
      icon = "warning"
    })
  else
    msg(hudText, 1.0, "loader", 0.25)
  end
end

local function getPlayerVehicle()
  if be and be.getPlayerVehicle then
    local ok, veh = pcall(be.getPlayerVehicle, be, 0)
    if ok then return veh end
  end
  return nil
end

local function safePos(obj)
  if obj and obj.getPosition then
    local ok, p = pcall(obj.getPosition, obj)
    if ok and p then return vf(p) end
  end
  return nil
end

local function vehicleForward(veh)
  for _, name in ipairs({ "getDirectionVector", "getForwardVector", "getFrontVector", "getForward" }) do
    if veh and veh[name] then
      local ok, d = pcall(veh[name], veh)
      if ok and d then return norm(vf(d), V(0, 1, 0)) end
    end
  end
  return V(0, 1, 0)
end

local function objId(o)
  if not o then return nil end

  if o.getID then
    local ok, id = pcall(o.getID, o)
    if ok then return id end
  end

  if o.getId then
    local ok, id = pcall(o.getId, o)
    if ok then return id end
  end

  return tostring(o)
end

local function tryGroundHeightApi(pos)
  local apiChecks = {
    function()
      if core_environment and core_environment.getTerrainHeight then
        return core_environment.getTerrainHeight(pos.x, pos.y)
      end
    end,
    function()
      if be and be.getTerrainHeight then
        return be:getTerrainHeight(pos.x, pos.y)
      end
    end,
    function()
      if be and be.getSurfaceHeightBelow then
        return be:getSurfaceHeightBelow(point(V(pos.x, pos.y, pos.z + groundRayStartHeight)))
      end
    end
  }

  for _, fn in ipairs(apiChecks) do
    local ok, z = pcall(fn)
    z = tonumber(z)
    if ok and z then return z end
  end

  return nil
end

local function tryStaticRaycastGround(pos)
  local from = V(pos.x, pos.y, pos.z + groundRayStartHeight)
  local dir = V(0, 0, -1)

  local rayChecks = {
    function()
      if Engine and Engine.castRayStatic then
        return Engine.castRayStatic(point(from), point(dir), groundRayLength)
      end
    end,
    function()
      if be and be.castRayStatic then
        return be:castRayStatic(point(from), point(dir), groundRayLength)
      end
    end,
    function()
      if castRayStatic then
        return castRayStatic(point(from), point(dir), groundRayLength)
      end
    end
  }

  for _, fn in ipairs(rayChecks) do
    local ok, hit = pcall(fn)

    if ok and hit then
      if type(hit) == "table" then
        if hit.pt then
          local p = vf(hit.pt)
          if p then return p.z end
        end

        if hit.pos then
          local p = vf(hit.pos)
          if p then return p.z end
        end

        if hit.point then
          local p = vf(hit.point)
          if p then return p.z end
        end

        if hit.z then
          return tonumber(hit.z)
        end
      end

      local n = tonumber(hit)
      if n and n > 0 and n < groundRayLength then
        return from.z - n
      end
    end
  end

  return nil
end

local function snapToGround(pos)
  if not pos then return nil, "no_position" end

  local z = tryStaticRaycastGround(pos) or tryGroundHeightApi(pos)

  if not z then
    return nil, "no_ground_hit"
  end

  -- EXACT surface placement. No hardcoded vertical offset.
  return V(pos.x, pos.y, z), "ok"
end

local function stabilizeVehicle(veh)
  if not veh or not veh.queueLuaCommand then return end

  veh:queueLuaCommand([[
    pcall(function()
      if obj then
        if obj.setVelocity then obj:setVelocity(0, 0, 0) end
        if obj.setAngularVelocity then obj:setAngularVelocity(0, 0, 0) end
      end
    end)

    pcall(function()
      if electrics and electrics.values then
        electrics.values.parkingbrake = 1
        electrics.values.brake = 1
        electrics.values.throttle = 0
      end
    end)

    pcall(function()
      if ai then ai.setMode("disabled") end
    end)
  ]])
end

local function freezeVehicle(veh)
  if not veh then return end

  pcall(function()
    if veh.queueLuaCommand then
      veh:queueLuaCommand([[
        pcall(function()
          if obj then
            if obj.setVelocity then obj:setVelocity(0, 0, 0) end
            if obj.setAngularVelocity then obj:setAngularVelocity(0, 0, 0) end
          end
        end)

        pcall(function()
          if electrics and electrics.values then
            electrics.values.parkingbrake = 1
            electrics.values.brake = 1
            electrics.values.throttle = 0
          end
        end)

        pcall(function()
          if controller and controller.mainController and controller.mainController.setEngineIgnition then
            controller.mainController.setEngineIgnition(false)
          end
        end)

        pcall(function()
          if ai then ai.setMode("disabled") end
        end)
      ]])
    end
  end)
end

local function wakeVehicle(veh)
  stabilizeVehicle(veh)
end

local function safeDeleteVehicle(veh)
  if not veh then return end

  local ok, err = pcall(function()
    if veh.delete then
      veh:delete()
    end
  end)

  if not ok then
    logSafe("W", "landMine", "failed to delete pooled mine: " .. tostring(err))
  end
end

local function setVehiclePosition(veh, pos, rot)
  if not veh or not pos then return false end

  local ok = false

  stabilizeVehicle(veh)

  pcall(function()
    if veh.setPositionRotation and rot then
      veh:setPositionRotation(pos.x, pos.y, pos.z, rot.x or 0, rot.y or 0, rot.z or 0, rot.w or 1)
      ok = true
    end
  end)

  if ok then
    stabilizeVehicle(veh)
    return true
  end

  pcall(function()
    if veh.setPosition then
      veh:setPosition(point(pos))
      ok = true
    end
  end)

  if ok then
    stabilizeVehicle(veh)
    return true
  end

  pcall(function()
    if veh.queueLuaCommand then
      veh:queueLuaCommand(string.format([[
        pcall(function()
          if obj and obj.setPosition then
            obj:setPosition(%0.6f, %0.6f, %0.6f)
          end

          if obj then
            if obj.setVelocity then obj:setVelocity(0, 0, 0) end
            if obj.setAngularVelocity then obj:setAngularVelocity(0, 0, 0) end
          end
        end)
      ]], pos.x, pos.y, pos.z))
      ok = true
    end
  end)

  stabilizeVehicle(veh)
  return ok
end

local function hiddenPoolPosition(index)
  return V(10000 + ((index or 1) * hiddenSpacing), 10000, hiddenZ)
end

local function spawnLandMine(index)
  if not core_vehicles or not core_vehicles.spawnNewVehicle then
    logSafe("E", "landMine", "core_vehicles.spawnNewVehicle unavailable")
    return nil
  end

  local pos = hiddenPoolPosition(index)

  local options = {
    pos = point(pos),
    config = landMineConfig,
    autoEnterVehicle = false,
    licenseText = "MINE"
  }

  local ok, veh = pcall(core_vehicles.spawnNewVehicle, landMineModel, options)

  if not ok then
    logSafe("E", "landMine", "spawnNewVehicle failed: " .. tostring(veh))
    return nil
  end

  freezeVehicle(veh)
  return veh
end

local function refreshEntryMine(entry)
  if not entry then return false end

  safeDeleteVehicle(entry.veh)

  local index = tonumber(entry.slotIndex) or 1
  local newVeh = spawnLandMine(index)

  if not newVeh then
    entry.veh = nil
    return false
  end

  entry.veh = newVeh
  entry.id = objId(newVeh)
  entry.active = false
  entry.lastPlaced = -1e9
  entry.pos = hiddenPoolPosition(index)

  return true
end

local function preloadPool()
  if poolReady or poolLoading then return end

  poolLoading = true
  hudText = "Jonesing Land Mine LOADING"
  centerLoader("Loading land mines 0/" .. tostring(poolSize))

  for i = 1, poolSize do
    local veh = spawnLandMine(i)

    if veh then
      table.insert(pool, {
        veh = veh,
        id = objId(veh),
        slotIndex = i,
        active = false,
        lastPlaced = -1e9,
        pos = hiddenPoolPosition(i)
      })

      spawnedCount = spawnedCount + 1
      centerLoader("Loading land mines " .. tostring(spawnedCount) .. "/" .. tostring(poolSize))
    else
      logSafe("W", "landMine", "failed to spawn pooled landmine index=" .. tostring(i))
    end
  end

  poolReady = #pool > 0
  poolLoading = false

  if poolReady then
    hudText = "Jonesing Land Mine READY"
    msg("Jonesing Land Mine READY", 2, "ready", 2)
    logSafe("I", "landMine", "pool ready count=" .. tostring(#pool))
  else
    hudText = "Jonesing Land Mine FAILED"
    msg("Land mine pool failed to load", 3, "failed", 2)
    logSafe("E", "landMine", "pool failed")
  end
end

local function getReusableMine(playerPos)
  if #pool == 0 then return nil end

  for _, entry in ipairs(pool) do
    if entry and entry.veh and not entry.active then
      return entry
    end
  end

  local farthest = nil
  local farthestDist = -1

  for _, entry in ipairs(pool) do
    if entry and entry.veh then
      local p = safePos(entry.veh) or entry.pos or V(0, 0, hiddenZ)
      local d = len(sub(p, playerPos))

      if d > farthestDist then
        farthestDist = d
        farthest = entry
      end
    end
  end

  return farthest
end

local function getLandMineDropPosition(playerVeh)
  local playerPos = safePos(playerVeh)
  if not playerPos then return nil, "no_player_position" end

  local forward = vehicleForward(playerVeh)
  local behind = mul(forward, -placeBehindDistance)

  local rawDrop = add(playerPos, behind)
  local groundDrop, reason = snapToGround(rawDrop)

  if not groundDrop then
    return nil, reason
  end

  return groundDrop, "ok"
end

local function placeLandMine()
  if not enabled or triggerTimer > 0 then return false end

  triggerTimer = cooldown

  if not poolReady then
    preloadPool()

    if not poolReady then
      msg("Land mines are still loading", 1, "loading", 0.25)
      return false
    end
  end

  local playerVeh = getPlayerVehicle()

  if not playerVeh then
    hudText = "NO PLAYER VEHICLE"
    msg(hudText, 1.5, "noVehicle", 0.5)
    return false
  end

  local playerPos = safePos(playerVeh)

  if not playerPos then
    hudText = "NO PLAYER POSITION"
    msg(hudText, 1.5, "noPlayerPos", 0.5)
    return false
  end

  local dropPos, reason = getLandMineDropPosition(playerVeh)

  if not dropPos then
    hudText = "LAND MINE FAILED: " .. tostring(reason)
    msg(hudText, 1.5, "dropFailed", 0.5)
    return false
  end

  local entry = getReusableMine(playerPos)

  if not entry or not entry.veh then
    hudText = "NO LAND MINE AVAILABLE"
    msg(hudText, 1.5, "noMine", 0.5)
    return false
  end

  if entry.active and not refreshEntryMine(entry) then
    hudText = "LAND MINE REFRESH FAILED: SPAWN"
    msg(hudText, 1.5, "refreshFailed", 0.5)
    return false
  end

  freezeVehicle(entry.veh)

  local moved = setVehiclePosition(entry.veh, dropPos)

  entry.active = true
  entry.lastPlaced = now()
  entry.pos = dropPos

  wakeVehicle(entry.veh)

  if moved then
    hudText = "LAND MINE DEPLOYED"
    msg("Land mine deployed", 0.8, "deployed", 0.15)
    logSafe(
      "I",
      "landMine",
      "deployed id=" .. tostring(entry.id)
        .. " groundPos=(" .. tostring(dropPos.x) .. "," .. tostring(dropPos.y) .. "," .. tostring(dropPos.z) .. ")"
    )
    return true
  end

  hudText = "LAND MINE MOVE FAILED"
  msg(hudText, 1.5, "moveFailed", 0.5)
  return false
end

local function onExtensionLoaded()
  for _, entry in ipairs(pool or {}) do
    if entry and entry.veh then
      safeDeleteVehicle(entry.veh)
    end
  end

  enabled = true
  triggerTimer = 0
  pool = {}
  poolReady = false
  poolLoading = false
  spawnedCount = 0

  hudText = "Jonesing Land Mine LOADING"
  logSafe("I", "landMine", "loaded land mine spawner")

  preloadPool()
end

local function onExtensionUnloaded()
  for _, entry in ipairs(pool or {}) do
    if entry and entry.veh then
      safeDeleteVehicle(entry.veh)
    end
  end

  pool = {}
  poolReady = false
  poolLoading = false
  spawnedCount = 0
  enabled = false
end

local function onUpdate(dtReal, dtSim, dtRaw)
  dtReal = tonumber(dtReal) or tonumber(dtSim) or 0

  if triggerTimer > 0 then
    triggerTimer = math.max(0, triggerTimer - dtReal)
  end

  if poolLoading then
    centerLoader("Loading land mines " .. tostring(spawnedCount) .. "/" .. tostring(poolSize))
  end

  if shouldLog("heartbeat", 5.0) then
    logSafe(
      "I",
      "landMine",
      "ready=" .. tostring(poolReady)
        .. " pool=" .. tostring(#pool)
        .. " enabled=" .. tostring(enabled)
    )
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onUpdate = onUpdate

M.fireWeapon = placeLandMine
M.placeLandMine = placeLandMine
M.spawnLandMineBehindPlayer = placeLandMine
M.preloadPool = preloadPool

M.setEnabled = function(v)
  enabled = v == true
  return enabled
end

M.setCooldown = function(v)
  cooldown = tonumber(v) or cooldown
  return cooldown
end

M.setPoolSize = function(v)
  poolSize = math.max(1, tonumber(v) or poolSize)
  return poolSize
end

M.setBehindDistance = function(v)
  placeBehindDistance = tonumber(v) or placeBehindDistance
  return placeBehindDistance
end

M.setLandMineVehicle = function(model, config)
  landMineModel = tostring(model or landMineModel)
  landMineConfig = tostring(config or landMineConfig)
  return landMineModel, landMineConfig
end

M.getState = function()
  return {
    enabled = enabled,
    cooldown = cooldown,
    triggerTimer = triggerTimer,
    poolSize = poolSize,
    poolReady = poolReady,
    poolLoading = poolLoading,
    spawnedCount = spawnedCount,
    activePoolCount = #pool,
    landMineModel = landMineModel,
    landMineConfig = landMineConfig,
    placeBehindDistance = placeBehindDistance,
    hiddenZ = hiddenZ,
    hudText = hudText
  }
end

M.getHudText = function()
  return hudText
end

return M
