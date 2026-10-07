-- AutoSwitch : adhérence en sol humide (MoreRealistic), bonus différentiels, usure Use Your Tyres
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.19 : perte d'adhérence en sol humide avec MoreRealistic.
--   MoreRealistic remplace entièrement le calcul d'adhérence des roues
--   (WheelPhysics.updateTireFriction) : l'adhérence réglée par Mud System Physics
--   et par Tractor Terrain Dynamics est écrasée, donc un champ humide ne fait
--   presque pas patiner. Ici, après le calcul de MoreRealistic, on réapplique son
--   adhérence multipliée par un facteur qui dépend :
--     - de l'humidité locale du sol (Mud System Physics),
--     - du type de sol sous la roue (profils fgpXX : sol meuble = plus de perte).
--   Rien n'est modifié dans MoreRealistic ni dans les autres mods.
-------------------------------------------------------------------------------
AS_WetGrip = {}
-- (v1.26) effet renforcé : début à 20 %, maximum à 70 % d'humidité, niveaux plus forts
AS_WetGrip.LEVEL = 0.45        -- perte maxi (0 = désactivé, 0.30 faible, 0.45 moyenne, 0.60 forte, 0.75 très forte)
AS_WetGrip.WET_START = 0.20    -- en dessous de cette humidité : aucune perte
AS_WetGrip.WET_FULL = 0.70     -- humidité où la perte est maximale
AS_WetGrip.MIN_MUL = 0.30
-- (v1.26) adhérence "champ mouillé" de la table MoreRealistic abaissée de 20 % (en mémoire seulement)
AS_WetGrip.MR_WET_FIELD_MUL = 0.80
AS_WetGrip.CHECK_MS = 500
AS_WetGrip.DIFF_BONUS = true          -- (v1.31) bonus d'adhérence quand les différentiels sont bloqués
AS_WetGrip.DIFF_BONUS_FRONT = 0.02     -- +2 % sur les roues avant (différentiel avant bloqué)
AS_WetGrip.DIFF_BONUS_REAR = 0.03      -- +3 % sur les roues arrière (différentiel arrière bloqué)
AS_WetGrip.MAX_MUL = 1.03
-- (v1.28) champ renommé __vtpasGripMul : __vtpGripMul est déjà utilisé par Variable Tire Pressure
-- (adhérence x2,5 en mode champ), ce qui écrasait notre réduction.
AS_WetGrip.timer = 0
AS_WetGrip.installed = false

function AS_WetGrip:computeWheelMul(wheel, fg, flw, baseWet)
    local ok, mud, _gt, prof = pcall(fg.getWheelGroundProfile, fg, wheel)
    if not ok or prof == nil then return 1.0 end
    local wet = baseWet
    if flw ~= nil and flw.enabled == true and flw.getEffectiveWetnessAt ~= nil and fg.getWheelContactPos ~= nil then
        local x, _, z = fg:getWheelContactPos(wheel)
        if x ~= nil then
            local ok2, w = pcall(flw.getEffectiveWetnessAt, flw, x, z, baseWet, 16, prof)
            if ok2 and type(w) == "number" then wet = w end
        end
    end
    local wet01 = shClamp((wet - self.WET_START) / math.max(0.05, self.WET_FULL - self.WET_START), 0, 1)
    if wet01 <= 0 then return 1.0 end
    local softness = shClamp((mud or prof.mud or 0) / 0.45, 0.1, 1.3)
    local loss = self.LEVEL * (wet01 ^ 0.9) * softness
    -- (v2.2) roues jumelées : surface au sol plus grande, perte d'adhérence réduite
    if AS_Duals ~= nil and AS_Duals.ENABLED and AS_Duals.getDualWidth(wheel.physics) ~= nil then
        loss = loss * (1 - AS_Duals.WET_LOSS_REDUCTION)
    end
    return shClamp(1 - loss, self.MIN_MUL, 1.0)
end

-- (v1.32) usure des pneus de Use Your Tyres (même formule que ce mod)
function AS_WetGrip:getWearMul(wp)
    local uyt = UseYourTyres
    if uyt == nil and type(FS25_useYourTyres) == "table" then uyt = FS25_useYourTyres.UseYourTyres end
    if uyt == nil or uyt.getWearAmount == nil or wp.wheel == nil or wp.wheel.vehicle == nil
        or wp.wheel.vehicle.uytHasTyres ~= true then
        return 1
    end
    local okW, wear = pcall(uyt.getWearAmount, wp.wheel)
    if not okW or type(wear) ~= "number" then return 1 end
    local w = math.pow(wear, 3) * 0.75
    local okG, gt = pcall(WheelsUtil.getGroundType, wp.densityType ~= FieldGroundType.NONE,
        wp.contact ~= WheelContactType.GROUND, wp.groundDepth)
    if okG and gt == WheelsUtil.GROUND_ROAD then
        return 1 + w
    end
    return math.max(0.1, math.min(1, 1 - w))
end

-- (v1.0.0.05) blocages ModMixer sur WheelPhysics.updateTireFriction : AutoSwitch respecte
-- le choix du joueur au lieu de réactiver ce qu'il a bloqué
AS_WetGrip.mrFrictionVetoed = false
AS_WetGrip.uytFrictionVetoed = false
function AS_WetGrip:readModMixerVetoes()
    local dir = g_modSettingsDirectory or (getUserProfileAppPath() .. "modSettings/")
    if string.sub(dir, -1) ~= "/" then dir = dir .. "/" end
    local path = dir .. "FS25_ModMixer/switchboard.xml"
    if not fileExists(path) then return end
    local xml = loadXMLFile("asModMixerSwitchboard", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("switchboard.vetoes.veto(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local mod, target = getXMLString(xml, key .. "#mod"), getXMLString(xml, key .. "#target")
        if target == "WheelPhysics.updateTireFriction" then
            if mod == "MoreRealistic" then self.mrFrictionVetoed = true end
            if mod == "FS25_useYourTyres" then self.uytFrictionVetoed = true end
        end
        i = i + 1
    end
    delete(xml)
    vtpInfo(string.format("[AS_WetGrip] ModMixer : MoreRealistic %s, Use Your Tyres %s sur l'adhérence",
        self.mrFrictionVetoed and "bloqué" or "actif", self.uytFrictionVetoed and "bloqué" or "actif"))
end

function AS_WetGrip:install()
    if self.installed then return end
    if WheelPhysics == nil or WheelPhysics.updateTireFriction == nil or WheelPhysics.mrUpdateTireFriction == nil then
        print("[AS_WetGrip] MoreRealistic non détecté : perte d'adhérence en sol humide inactive")
        self.installed = true
        self.inactive = true
        return
    end
    self:readModMixerVetoes()
    WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, function(wp, superFunc)
        local ready = wp.vehicle ~= nil and wp.vehicle.isServer and wp.vehicle.isAddedToPhysics
            and wp.wheelShape ~= nil and wp.wheel ~= nil and wp.wheel.node ~= nil
            and type(wp.tireGroundFrictionCoeff) == "number"
        if not ready then
            return superFunc(wp)
        end
        local mul = wp.__vtpasGripMul or 1

        if not AS_WetGrip.mrFrictionVetoed then
            -- MoreRealistic calcule l'adhérence sans tenir compte des autres mods :
            -- après lui, on réécrit son adhérence avec notre facteur (et l'usure Use Your Tyres)
            superFunc(wp)
            if math.abs(mul - 1) > 0.001 then
                local dyn = tonumber(wp.mrDynamicFrictionScale) or 1
                setWheelShapeTireFriction(wp.wheel.node, wp.wheelShape, wp.maxLongStiffness, wp.maxLatStiffness,
                    wp.maxLatStiffnessLoad, wp.tireGroundFrictionCoeff * dyn * mul * AS_WetGrip:getWearMul(wp))
            end
            return
        end

        -- (v1.0.0.05) MoreRealistic bloqué par ModMixer sur cette fonction : l'adhérence passe
        -- par frictionScale, que le jeu, Mud System Physics et Variable Tire Pressure
        -- multiplient chacun. On y ajoute notre facteur (et l'usure Use Your Tyres si ModMixer
        -- bloque aussi ce mod), sec ou humide : pas de saut quand le sol change.
        local extra = mul
        if AS_WetGrip.uytFrictionVetoed then
            extra = extra * AS_WetGrip:getWearMul(wp)
        end
        if math.abs(extra - 1) <= 0.001 then
            return superFunc(wp)
        end
        local old = wp.frictionScale
        wp.frictionScale = (old or 1) * extra
        local ok, err = pcall(superFunc, wp)
        wp.frictionScale = old
        if not ok then error(err) end
    end)
    self.installed = true
    -- table d'adhérence de MoreRealistic : pneus sur champ mouillé
    if WheelsUtil ~= nil and WheelsUtil.tireTypes ~= nil and WheelsUtil.GROUND_FIELD ~= nil and not self.mrTablePatched then
        local n = 0
        for _, tireType in pairs(WheelsUtil.tireTypes) do
            local wet = tireType.frictionCoeffsWet
            if type(wet) == "table" and type(wet[WheelsUtil.GROUND_FIELD]) == "number" then
                wet[WheelsUtil.GROUND_FIELD] = wet[WheelsUtil.GROUND_FIELD] * self.MR_WET_FIELD_MUL
                n = n + 1
            end
        end
        self.mrTablePatched = true
        vtpInfo(string.format("[AS_WetGrip] table MoreRealistic : adhérence champ mouillé x%.2f (%d types de pneus)", self.MR_WET_FIELD_MUL, n))
    end
    vtpInfo("[AS_WetGrip] perte d'adhérence en sol humide installée (MoreRealistic)")
end

function AS_WetGrip:loadMap()
    self:install()
end

-- (v1.27) DIAGNOSTIC TEMPORAIRE : toutes les 5 s, état de l'adhérence du véhicule conduit
AS_WetGrip.DIAG = false   -- (v1.29) diagnostic retiré : adhérence validée
function AS_WetGrip:diag(fg, flw, baseWet)
    local vehicle = shGetControlledVehicle()
    if vehicle == nil or vehicle.spec_wheels == nil then return end
    local parts = {}
    for i, wheel in ipairs(vehicle.spec_wheels.wheels) do
        local wp = wheel.physics
        if wp ~= nil and i <= 4 then
            local _, _, _, prof = pcall(fg.getWheelGroundProfile, fg, wheel)
            local wet = baseWet
            if flw ~= nil and flw.enabled == true and fg.getWheelContactPos ~= nil then
                local x, _, z = fg:getWheelContactPos(wheel)
                if x ~= nil then
                    local ok2, w = pcall(flw.getEffectiveWetnessAt, flw, x, z, baseWet, 16, prof)
                    if ok2 and type(w) == "number" then wet = w end
                end
            end
            table.insert(parts, string.format("r%d[sol=%s hum=%.2f mul=%.2f coefMR=%.3f dynMR=%.2f]", i,
                prof ~= nil and tostring(prof.name) or "-", wet, wp.__vtpasGripMul or 1,
                tonumber(wp.tireGroundFrictionCoeff) or -1, tonumber(wp.mrDynamicFrictionScale) or -1))
        end
    end
    local mrSlip = vehicle.spec_wheels.mrAvgDrivenWheelsSlip
    print(string.format("[AS_WetGrip][diag] %s humGlobale=%.2f patinageMR=%s %s", vehicle:getName(), baseWet,
        mrSlip ~= nil and string.format("%.1f%%", mrSlip * 100) or "-", table.concat(parts, " ")))
end

function AS_WetGrip:update(dt)
    if self.inactive or g_currentMission == nil or g_server == nil then return end
    if self.DIAG then
        self.diagTimer = (self.diagTimer or 0) + (dt or 0)
    end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.CHECK_MS then return end
    self.timer = 0

    local fg = getMudClass("FieldGroundMudPhysics")
    if fg == nil or fg.getWheelGroundProfile == nil then return end
    local flw = getMudClass("FieldLocalWetness")
    local baseWet = 0
    local env = g_currentMission.environment
    if env ~= nil and env.weather ~= nil and env.weather.getGroundWetness ~= nil then
        local ok, w = pcall(env.weather.getGroundWetness, env.weather)
        if ok and type(w) == "number" then baseWet = w end
    end
    local frozen = fg.isHardWinterFrozen ~= nil and select(2, pcall(fg.isHardWinterFrozen, fg)) == true
    if self.DIAG and (self.diagTimer or 0) >= 5000 then
        self.diagTimer = 0
        pcall(self.diag, self, fg, flw, baseWet)
    end

    for _, vehicle in pairs(getVehicles()) do
        local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
        -- (v1.31) différentiels bloqués (Enhanced Vehicle) : petit bonus d'adhérence
        local frontLocked, rearLocked, midZ = false, false, nil
        local vis = vehicle.vData ~= nil and vehicle.vData.is or nil
        if self.DIFF_BONUS and vis ~= nil and wheels ~= nil and vehicle.rootNode ~= nil then
            frontLocked = isLockedValue(vis[1])
            rearLocked = isLockedValue(vis[2])
            if frontLocked or rearLocked then
                local minZ, maxZ = math.huge, -math.huge
                for _, w in ipairs(wheels) do
                    local n = w.repr or w.driveNode or w.node
                    if n ~= nil and n ~= 0 then
                        local okz, _, _, z = pcall(localToLocal, n, vehicle.rootNode, 0, 0, 0)
                        if okz and type(z) == "number" then
                            w.__vtpasZ = z
                            if z < minZ then minZ = z end
                            if z > maxZ then maxZ = z end
                        end
                    end
                end
                if minZ ~= math.huge and maxZ - minZ >= 0.5 then midZ = (minZ + maxZ) * 0.5 end
            end
        end
        if wheels ~= nil and vehicle.isAddedToPhysics then
            for _, wheel in ipairs(wheels) do
                local wp = wheel.physics
                if wp ~= nil then
                    local mul = 1.0
                    if self.LEVEL > 0 and not frozen and not wp.hasSnowContact then
                        local ok, m = pcall(self.computeWheelMul, self, wheel, fg, flw, baseWet)
                        if ok and type(m) == "number" then mul = m end
                    end
                    if midZ ~= nil and wheel.__vtpasZ ~= nil and not wp.hasSnowContact then
                        local isFront = wheel.__vtpasZ >= midZ
                        local b = 0
                        if isFront and frontLocked then b = self.DIFF_BONUS_FRONT
                        elseif not isFront and rearLocked then b = self.DIFF_BONUS_REAR end
                        if b > 0 then mul = math.min(self.MAX_MUL, mul * (1 + b)) end
                    end
                    local prev = wp.__vtpasGripMul or 1.0
                    if math.abs(prev - mul) > 0.02 then
                        wp.__vtpasGripMul = mul
                        wp.isFrictionDirty = true
                    end
                end
            end
        end
    end
end

addModEventListener(AS_WetGrip)
