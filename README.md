# Jonesing Guns – BeamNG.drive Weapon Prototype Mod

A first-person / third-person vehicle weapon prototype for BeamNG.drive.
Fire rays at other vehicles and apply layered damage: flat tyres, engine kill,
fire, and catastrophic chassis failure.

---

## Install

1. **Locate your BeamNG user folder.**  
   Default path on Windows:
   ```
   %USERPROFILE%\Documents\BeamNG.drive\
   ```
   Full example:
   ```
   C:\Users\YourName\Documents\BeamNG.drive\
   ```

2. **Copy the mod folder** into the `mods\unpacked\` directory so that the
   layout looks like this:

   ```
   BeamNG.drive\
   └── mods\
       └── unpacked\
           └── JonesingGuns\
               ├── README.md
               ├── settings\
               │   └── inputmaps\
               │       └── jonesingGuns.inputmap.json
               ├── lua\
               │   ├── ge\
               │   │   └── extensions\
               │   │       └── gameplay\
               │   │           └── vehicleGun.lua
               │   └── controller\
               │       └── jonesingGunsTrigger.lua
               ├── ui\
               │   └── modules\
               │       └── apps\
               │           └── JonesingGuns\
               │               ├── app.html
               │               ├── app.js
               │               └── app.css
               └── vehicles\
                   └── common\
                       └── guns\
                           └── guns.jbeam
   ```

3. **Enable the mod** in BeamNG's in-game Mod Manager
   (`Main Menu → Repository → Installed → JonesingGuns → Enable`).

4. **Spawn or add the `guns` part** to a vehicle via the Parts Selector.  
   The `guns.jbeam` slot type is `jonesing_slot`; you can also add it to any
   vehicle by editing its config and adding `"jonesing_slot": "agenty_universal_dummy"`.

5. **The weapon extension loads automatically** when a vehicle with the `guns` part is spawned.
   You can also load it manually from the Lua console (press `~` or `F7`):
   ```lua
   extensions.load("gameplay/vehicleGun")
   ```

6. **(Optional) Enable the HUD app** via the UI App configuration panel
   (`Apps → + → JonesingGuns`).  The weapon works without it.

---

## Keybinds

All bindings are defined in `settings/inputmaps/jonesingGuns.inputmap.json`
and can be rebound in **Options → Controls → Other → jonesingGuns**.

| Action              | Default Key       | Controller         | Description                                         |
|---------------------|-------------------|--------------------|-----------------------------------------------------|
| `weaponFire`        | **Numpad 0**      | **L1 / LB**        | Fire the weapon (raycast hit on vehicle in sight)   |
| `weaponToggleView`  | **Numpad 5**      | —                  | Toggle driver (1st-person) ↔ orbit (3rd-person) cam |
| `weaponAim`         | **Numpad 2**      | —                  | Hold to aim (reserved for FoV pass)                 |
| `weaponReload`      | **Numpad 1**      | —                  | Reload magazine (refills to max ammo)               |
| `weaponDebug`       | **Numpad 3**      | —                  | Toggle debug messages & visible tracers             |

---

## Damage Modes

Change modes at runtime from the Lua console:

```lua
-- Soft: deflate one tyre
extensions.gameplay_vehicleGun.setDamageMode("soft")

-- Hard: deflate front tyres + stall engine
extensions.gameplay_vehicleGun.setDamageMode("hard")

-- Destroy: deflate all tyres + engine off + fire + chassis break (default)
extensions.gameplay_vehicleGun.setDamageMode("destroy")
```

---

## Architecture

```
jonesingGunsTrigger (vehicle controller, lua/controller/)
 └─ init(): obj:queueGameEngineLua("extensions.load('gameplay/vehicleGun')")
         │
         ▼
GE Lua (lua/ge/extensions/gameplay/vehicleGun.lua)
 ├─ registers jonesingGuns action map
 ├─ handles camera switching (core_camera.setByName)
 ├─ performs raycast (be:castRay → fallback proximity scan)
 └─ sends damage via vehicle:queueLuaCommand
         │
         ▼
Vehicle Lua (controller.jonesingGunsTrigger.applyGunHit)
 ├─ SOFT   → beamstate.deflateTire(1)
 ├─ HARD   → deflateTire(0,1) + electrics off
 └─ DESTROY→ all tyres + engine off + fire + breakBeamGroup("chassis")

UI App (AngularJS, optional)
 └─ polls getState() via bngApi.engineLua every 100 ms
    → renders crosshair, ammo, cooldown bar, damage-mode badge
```

---

## Files

| File | Purpose |
|------|---------|
| `settings/inputmaps/jonesingGuns.inputmap.json` | Custom action map & default bindings |
| `lua/ge/extensions/gameplay/vehicleGun.lua` | GE Lua extension: weapon state, camera, raycast, dispatch |
| `lua/controller/jonesingGunsTrigger.lua` | Vehicle controller: bootstraps GE extension + damage adapter |
| `ui/modules/apps/JonesingGuns/app.html` | HUD template |
| `ui/modules/apps/JonesingGuns/app.js` | HUD AngularJS controller |
| `ui/modules/apps/JonesingGuns/app.css` | HUD styles |
| `vehicles/common/guns/guns.jbeam` | JBeam part that attaches the controller to a vehicle |

---

## Debugging

Enable debug mode (extra Lua console logs + hit markers):
```lua
extensions.gameplay_vehicleGun.setEnabled(true)  -- ensure weapon is on
-- then press F9 in-game, or:
-- (debug flag is toggled by the weaponDebug action)
```

Logs appear in BeamNG's Lua console and `beamng.log` under the tags
`vehicleGun` and `jonesingGunsTrigger`.

---

## Compatibility Notes

- Tested against BeamNG.drive stable release mod API.
- All risky or version-specific APIs are wrapped in `pcall` guards.
- The mod degrades gracefully: if `be:castRay` is unavailable it falls back
  to a proximity-scan hit detection; if `core_camera.setByName` is absent the
  weapon still fires without switching cameras.
- Does **not** edit any core game files.
