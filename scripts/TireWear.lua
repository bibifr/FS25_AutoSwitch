-- AutoSwitch : usure des pneus avec Reifenverschleiß (Real Physics - Tire Wear)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.45 : Reifenverschleiß remplace Use Your Tyres pour l'usure des pneus.
--   Après le calcul d'adhérence du jeu (WheelPhysics.updateFriction),
--   Reifenverschleiß écrit tireGroundFrictionCoeff = sa cible d'usure : la
--   différence route / champ / chemin / mouillé du jeu (et de TTD) disparaît.
--   AutoSwitch passe par-dessus sa fonction getWearAppliedTarget :
--     - l'adhérence du sol calculée juste avant est gardée ;
--     - au champ et sur chemin, la perte d'usure de Reifenverschleiß s'applique dessus ;
--     - sur route, un pneu usé gagne de l'adhérence (moins de crampons = slick),
--       même formule que Use Your Tyres : 1 + usure³ x 0,75.
--   Installé après le pont Reifenverschleiß de Mud System Physics, pour que son
--   multiplicateur reste appliqué une seule fois. Rien n'est modifié dans les
--   fichiers de Reifenverschleiß ni de MSP.
--   Affichage de TTD : sa case « usure des pneus » ne lisait que Use Your Tyres
--   (« NA UYT ») ; elle montre maintenant l'usure de Reifenverschleiß du
--   véhicule conduit. Seul l'affichage change : TTD n'applique pas cette usure
--   à son adhérence ni à son enfoncement (Reifenverschleiß le fait déjà).
-------------------------------------------------------------------------------

AS_TireWear = {}
AS_TireWear.installed = false
AS_TireWear.waitMs = 0
AS_TireWear.MSP_WAIT_MS = 15000   -- attente max du pont MSP avant de s'installer quand même
AS_TireWear.ROAD_GAIN = 0.75      -- gain sur route à 100 % d'usure (comme Use Your Tyres)
AS_TireWear.logLeft = 20          -- relevés dans log.txt pour le premier test
AS_TireWear.core = nil
AS_TireWear.hudMs = 0
AS_TireWear.HUD_INTERVAL_MS = 500

-- nom du mod Reifenverschleiß chargé (il change à chaque version)
function AS_TireWear:findModName()
    if g_modManager == nil or type(g_modManager.mods) ~= "table" then return nil end
    for _, mod in pairs(g_modManager.mods) do
        local name = type(mod) == "table" and mod.modName or nil
        if type(name) == "string" and string.find(name, "^FS25_Reifenverschleiss") ~= nil
            and (g_modIsLoaded == nil or g_modIsLoaded[name]) then
            return name
        end
    end
    return nil
end

local function wearPhysics(wheel)
    return wheel ~= nil and (wheel.physics or wheel.wheelPhysics) or nil
end

local function isRoad(physics)
    if WheelsUtil == nil or WheelsUtil.getGroundType == nil or FieldGroundType == nil or WheelContactType == nil then
        return false
    end
    local ok, gt = pcall(WheelsUtil.getGroundType, physics.densityType ~= FieldGroundType.NONE,
        physics.contact ~= WheelContactType.GROUND, physics.groundDepth)
    return ok and gt == WheelsUtil.GROUND_ROAD
end

function AS_TireWear:wrap(core)
    local original = core.getWearAppliedTarget
    local owner = self
    core.getWearAppliedTarget = function(vehicle, wheel)
        local target, pct = original(vehicle, wheel)
        local physics = wearPhysics(wheel)
        local scale = physics ~= nil and physics.frictionScale or nil
        if type(target) ~= "number" or type(scale) ~= "number" or scale <= 0 then
            return target, pct
        end
        local ok, newTarget = pcall(owner.adjust, owner, core, vehicle, wheel, physics, target, scale)
        if ok and type(newTarget) == "number" then
            return newTarget, pct
        end
        return target, pct
    end
end

function AS_TireWear:adjust(core, vehicle, wheel, physics, target, scale)
    -- adhérence du sol : celle du jeu, sauf si personne ne l'a recalculée depuis
    -- notre dernière écriture (on reprend alors la valeur gardée, sans la multiplier deux fois)
    local coeff = physics.tireGroundFrictionCoeff
    if type(coeff) ~= "number" then return nil end
    local ground
    if physics.__asRvWritten ~= nil and math.abs(coeff - physics.__asRvWritten) < 1e-6 then
        ground = physics.__asRvGround or 1
    else
        ground = coeff
        physics.__asRvGround = coeff
    end

    local ratio = target / scale   -- perte d'usure de Reifenverschleiß (1 = pneu neuf)
    local road = isRoad(physics)
    if road then
        local wear = core.getWheelWearValue ~= nil and core.getWheelWearValue(vehicle, wheel) or nil
        wear = math.max(0, math.min(1, tonumber(wear) or 0))
        ratio = 1 + wear * wear * wear * self.ROAD_GAIN
    end

    local final = ground * ratio
    physics.__asRvWritten = final

    if self.logLeft > 0 and vehicle ~= nil and vehicle.getIsControlled ~= nil and vehicle:getIsControlled() then
        self.logLeft = self.logLeft - 1
        print(string.format("[AS_TireWear] %s : sol %.3f, usure x%.3f (%s), adhérence %.3f au lieu de %.3f",
            tostring(vehicle.getName ~= nil and vehicle:getName() or "?"), ground, ratio,
            road and "route" or "hors route", final, target / scale))
    end
    return final * scale
end

local function controlledVehicle()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local ok, v = pcall(g_localPlayer.getCurrentVehicle, g_localPlayer)
        if ok and v ~= nil then return v end
    end
    return g_currentMission ~= nil and g_currentMission.controlledVehicle or nil
end

-- case « usure des pneus » de TTD : valeur de Reifenverschleiß
function AS_TireWear:updateTtdHud(dt)
    self.hudMs = self.hudMs + (dt or 0)
    if self.hudMs < self.HUD_INTERVAL_MS then return end
    self.hudMs = 0
    local v = controlledVehicle()
    local spec = v ~= nil and v.spec_tractorTerrainDynamics or nil
    if spec == nil or spec.groundData == nil or type(self.core.getHudWearState) ~= "function" then return end
    local ok, hud = pcall(self.core.getHudWearState, v)
    if not ok or type(hud) ~= "table" or hud.hasWearObjects ~= true then return end
    local pct = math.max(0, math.min(100, tonumber(hud.wearPercent) or 0))
    spec.groundData.tyreWear = math.floor(pct + 0.5)
    -- TTD n'affiche la case que pour un véhicule « Use Your Tyres » : sans ce mod
    -- chargé, personne d'autre ne lit ce drapeau pour appliquer une usure
    if self.uytLoaded ~= true then
        v.uytHasTyres = true
    end
end

function AS_TireWear:update(dt)
    if self.installed then
        if self.core ~= nil then self:updateTtdHud(dt) end
        return
    end
    local modName = self:findModName()
    if modName == nil then
        self.installed = true
        print("[AS_TireWear] Reifenverschleiß introuvable : module inactif")
        return
    end
    local core = AS.modGlobal(modName, "ReifenVerschleissCore")
    if type(core) ~= "table" or type(core.getWearAppliedTarget) ~= "function" then
        return
    end
    -- attendre le pont Reifenverschleiß de MSP : on se place par-dessus
    local rvc = AS.modGlobal("FS25_MudSystemPhysics", "ReifenverschleissCompatibility")
    self.waitMs = self.waitMs + (dt or 0)
    if type(rvc) == "table" and rvc.enabled == true and rvc._wearTargetInstalled ~= true
        and self.waitMs < self.MSP_WAIT_MS then
        return
    end
    self:wrap(core)
    self.core = core
    self.uytLoaded = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_useYourTyres"] == true
    self.installed = true
    print(string.format("[AS_TireWear] %s : adhérence du sol gardée, usure appliquée par-dessus, effet slick sur route (pont MSP %s)",
        modName, (type(rvc) == "table" and rvc._wearTargetInstalled == true) and "présent" or "absent"))
end

addModEventListener(AS_TireWear)
