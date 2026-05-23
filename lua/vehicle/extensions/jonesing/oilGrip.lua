-- lua/ge/extensions/gameplay/vehicleTrap.lua
-- Add/merge into your existing file as needed.

local M = {}

local oilSlicks = {}
local oilHitVehicles = {}

local function now()
  return Engine.Platform.getRuntime()
end

local function groundPoint(pos)
  local origin = pos + vec3(0, 0, 2)
  local down = vec3(0, 0, -1)
  local maxDist = 20
  local hitDist = castRayStatic(origin, down, maxDist)

  if hitDist and hitDist < maxDist then
    return origin + (down * hitDist) + vec3(0, 0, 0.03)
  end

  return pos
end

local function applyOilToVehicle(obj)
  if not obj then return end

  local id = obj:getId()
  local t = now()

  -- avoid command spam
  if oilHitVehicles[id] and oilHitVehicles[id] > t then return end
  oilHitVehicles[id] = t + 0.35

  obj:queueLuaCommand([[
    jonesingOilEndTime = math.max(jonesingOilEndTime or 0, os.clock() + 5)

    if not jonesingOilOriginals then
      jonesingOilOriginals = {}
    end

    -- Attempt 1: brute force wheel fields. May log/work differently by vehicle/version.
    if wheels and wheels.wheels then
      for k, wd in pairs(wheels.wheels) do
        jonesingOilOriginals[k] = jonesingOilOriginals[k] or {}

        for key, val in pairs(wd) do
          if type(val) == "number" then
            local lower = tostring(key):lower()

            if lower:find("fric")
              or lower:find("grip")
              or lower:find("adhesion")
              or lower:find("traction")
              or lower:find("tread")
            then
              if jonesingOilOriginals[k][key] == nil then
                jonesingOilOriginals[k][key] = val
              end

              wd[key] = 0.03
            end
          end
        end

        if wd.frictionCoef ~= nil then wd.frictionCoef = 0.03 end
        if wd.frictionCoefMult ~= nil then wd.frictionCoefMult = 0.03 end
        if wd.gripCoef ~= nil then wd.gripCoef = 0.03 end
        if wd.treadCoef ~= nil then wd.treadCoef = 0.03 end
        if wd.adhesionCoef ~= nil then wd.adhesionCoef = 0.03 end
        if wd.tractionCoef ~= nil then wd.tractionCoef = 0.03 end
      end
    end

    -- Attempt 2: reduce driver control authority.
    -- This is fake oil, but less dumb than random shoving.
    if electrics and electrics.values then
      electrics.values.throttle = 0
      electrics.values.brake = 0
      electrics.values.parkingbrake = 0
    end

    -- Attempt 3: install temporary update hook once.
    if not jonesingOilHookInstalled then
      jonesingOilHookInstalled = true

      local oldUpdateGFX = updateGFX

      function updateGFX(dt)
        if oldUpdateGFX then oldUpdateGFX(dt) end

        if jonesingOilEndTime and jonesingOilEndTime > os.clock() then
          -- keep retrying wheel field nerf while oily
          if wheels and wheels.wheels then
            for _, wd in pairs(wheels.wheels) do
              if wd.frictionCoef ~= nil then wd.frictionCoef = 0.03 end
              if wd.frictionCoefMult ~= nil then wd.frictionCoefMult = 0.03 end
              if wd.gripCoef ~= nil then wd.gripCoef = 0.03 end
              if wd.treadCoef ~= nil then wd.treadCoef = 0.03 end
              if wd.adhesionCoef ~= nil then wd.adhesionCoef = 0.03 end
              if wd.tractionCoef ~= nil then wd.tractionCoef = 0.03 end
            end
          end

          if electrics and electrics.values then
            electrics.values.throttle = 0
            electrics.values.brake = 0
            electrics.values.parkingbrake = 0
          end
        elseif jonesingOilOriginals then
          -- restore any fields we changed
          if wheels and wheels.wheels then
            for k, fields in pairs(jonesingOilOriginals) do
              local wd = wheels.wheels[k]
              if wd then
                for key, val in pairs(fields) do
                  wd[key] = val
                end
              end
            end
          end

          jonesingOilOriginals = nil
          jonesingOilEndTime = 0
        end
      end
    end

    log("I", "JonesingOil", "Oil effect attempted")
  ]])
end

local function deployOilSlick()
  local veh = be:getPlayerVehicle(0)
  if not veh then return end

  local pos = veh:getPosition()
  local dir = veh:getDirectionVector()
  local right = dir:cross(vec3(0, 0, 1))

  -- many small pools trailing behind vehicle
  for i = 1, 14 do
    local backDist = 2.5 + (i * 1.55)
    local sideOffset = math.random(-190, 190) / 100
    local poolPos = pos - (dir * backDist) + (right * sideOffset)

    table.insert(oilSlicks, {
      pos = groundPoint(poolPos),
      radius = math.random(110, 240) / 100,
      life = 13
    })
  end

  log("I", "JonesingOil", "Oil slick trail deployed")
end

local function updateGFX(dt)
  for i = #oilSlicks, 1, -1 do
    local slick = oilSlicks[i]
    slick.life = slick.life - dt

    if slick.life <= 0 then
      table.remove(oilSlicks, i)
    else
      local alpha = math.min(0.75, slick.life / 13)
      local c = ColorF(0, 0, 0, alpha)

      -- visual pool
      debugDrawer:drawCylinder(
        slick.pos,
        slick.pos + vec3(0, 0, 0.01),
        slick.radius,
        c
      )

      -- optional smaller blob layered over it
      debugDrawer:drawCylinder(
        slick.pos + vec3(0.25, -0.15, 0.002),
        slick.pos + vec3(0.25, -0.15, 0.012),
        slick.radius * 0.55,
        ColorF(0, 0, 0, alpha * 0.9)
      )

      -- trigger vehicles
      for v = 0, be:getObjectCount() - 1 do
        local obj = be:getObject(v)

        if obj then
          local dist = obj:getPosition():distance(slick.pos)

          if dist < slick.radius + 1.8 then
            applyOilToVehicle(obj)
          end
        end
      end
    end
  end
end

M.deployOilSlick = deployOilSlick
M.updateGFX = updateGFX

return M