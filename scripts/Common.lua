-- AutoSwitch : fonctions communes à tous les modules.
-- Chargé en premier par AutoSwitch.lua.

AS = AS or {}

AS_MOD_DIR = g_currentModDirectory or ""   -- dossier du mod (pour l'icône de patinage)

AS_VERBOSE = false

-- (v1.25) Journal : seules les erreurs sont écrites dans log.txt. Mettre true pour le diagnostic.

local function vtpInfo(...)
    if AS_VERBOSE then print(...) end
end

-- Textes traduits (fichiers l10n/l10n_xx.xml) ; renvoie la clé elle-même si le texte est introuvable.
local function L(key)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return key
end

-- Affiche une notification latérale avec une durée choisie ; repli sur les fonctions standard du jeu.
local function showTimedNotification(kind, notifType, text)
    if g_currentMission == nil then return end
    local duration = AS_NotifyDuration[kind] or 4000
    local hud = g_currentMission.hud
    if hud ~= nil and hud.addSideNotification ~= nil and notifType ~= nil then
        if pcall(hud.addSideNotification, hud, notifType, text, duration) then return end
    end
    if g_currentMission.addIngameNotification ~= nil and notifType ~= nil then
        if pcall(g_currentMission.addIngameNotification, g_currentMission, notifType, text) then return end
    end
    if g_currentMission.showBlinkingWarning ~= nil then
        g_currentMission:showBlinkingWarning(text, duration)
    end
end

local function getVtpClass()
    if FS25_VariableTirePressure ~= nil and FS25_VariableTirePressure.VariableTirePressure ~= nil then
        return FS25_VariableTirePressure.VariableTirePressure
    end
    if _G.FS25_VariableTirePressure ~= nil and _G.FS25_VariableTirePressure.VariableTirePressure ~= nil then
        return _G.FS25_VariableTirePressure.VariableTirePressure
    end
    if VariableTirePressure ~= nil then
        return VariableTirePressure
    end
    return nil
end

local function isAutoDriveActive(v)
    return v.ad ~= nil and v.ad.stateModule ~= nil
        and v.ad.stateModule.isActive ~= nil and v.ad.stateModule:isActive() == true
end

local function isCourseplayActive(v)
    return v.getIsCpActive ~= nil and v:getIsCpActive() == true
end

-- (v1.0.0.54) moissonneuse ou ensileuse (spécialisation Combine du jeu)
local function isHarvester(v)
    return v.spec_combine ~= nil
end

-- (v1.0.0.53) vrai 4x4 : un différentiel central relie les deux ponts (ses deux entrées sont
-- des différentiels, pas des roues). Moissonneuses et 4x2 n'en ont pas. Sans information
-- (pas de liste de différentiels), on garde l'ancien comportement (4x4).
local is4wdCache = setmetatable({}, { __mode = "k" })
local function is4wd(v)
    local c = is4wdCache[v]
    if c ~= nil then return c end
    -- (v1.0.0.55) moissonneuses et ensileuses : pont avant seul, même avec un différentiel
    -- central dans le mod (Lexion 6900 : arrière à 0 % quand l'avant patine à 100 % en 4x4)
    if isHarvester(v) then
        is4wdCache[v] = false
        return false
    end
    local sm = v.spec_motorized
    local diffs = sm ~= nil and sm.differentials or nil
    if type(diffs) ~= "table" or #diffs == 0 then return true end
    local r = false
    for _, d in ipairs(diffs) do
        if d.diffIndex1IsWheel ~= true and d.diffIndex2IsWheel ~= true then
            r = true
            break
        end
    end
    is4wdCache[v] = r
    return r
end

-- Retourne true si le véhicule est dans un champ, false sinon, nil si indéterminable.
local function isVehicleInField(vehicle)
    local x, _, z = getWorldTranslation(vehicle.rootNode)

    -- Méthode 1 : fonction native du véhicule, si elle existe
    if vehicle.getIsOnField ~= nil then
        local ok, res = pcall(vehicle.getIsOnField, vehicle)
        if ok and res ~= nil then
            if not AS_Tires.loggedMethod then
                AS_Tires.loggedMethod = true
                vtpInfo("[AS_Tires] détection de champ : vehicle:getIsOnField()")
            end
            return res == true
        end
    end

    -- Méthode 2 : polygones de champs de la carte
    if g_fieldManager ~= nil and g_fieldManager.getFieldAtWorldPosition ~= nil then
        local ok, field = pcall(g_fieldManager.getFieldAtWorldPosition, g_fieldManager, x, z)
        if ok then
            if not AS_Tires.loggedMethod then
                AS_Tires.loggedMethod = true
                vtpInfo("[AS_Tires] détection de champ : g_fieldManager:getFieldAtWorldPosition()")
            end
            return field ~= nil
        end
    end

    return nil
end

local function getVehicles()
    local m = g_currentMission
    if m == nil then return {} end
    if m.vehicleSystem ~= nil and m.vehicleSystem.vehicles ~= nil then
        return m.vehicleSystem.vehicles
    end
    return m.vehicles or {}
end

local function getEvClass()
    if FS25_EnhancedVehicle ~= nil and FS25_EnhancedVehicle.FS25_EnhancedVehicle ~= nil then
        return FS25_EnhancedVehicle.FS25_EnhancedVehicle
    end
    if _G.FS25_EnhancedVehicle ~= nil and _G.FS25_EnhancedVehicle.FS25_EnhancedVehicle ~= nil then
        return _G.FS25_EnhancedVehicle.FS25_EnhancedVehicle
    end
    return nil
end

-- (v1.0.0.42) Vitesse au sol (m/s) à l'endroit de la roue, dans le sens où elle roule :
-- vitesse du châssis + rotation (virage) au point de la roue, projetée sur l'axe avant de la
-- roue braquée. En virage, chaque roue suit son propre cercle (avant et extérieur plus vite) ;
-- comparer à la vitesse du tracteur comptait cet écart comme du patinage (jusqu'à 40 %).
-- Renvoie nil si le moteur physique ne donne pas les vitesses (on garde alors la vitesse du tracteur).
local function wheelGroundSpeed(wheel, fallback)
    local p = wheel.physics or wheel
    local body = wheel.node or p.node
    local ref = wheel.repr or wheel.driveNode or body
    if body == nil or body == 0 or ref == nil or ref == 0
       or g_server == nil or getLinearVelocity == nil or getAngularVelocity == nil then   -- client : pas de physique locale
        return fallback
    end
    local ok, vx, vy, vz = pcall(getLinearVelocity, body)
    local ok2, wx, wy, wz = pcall(getAngularVelocity, body)
    if not ok or not ok2 or vx == nil or wx == nil then return fallback end
    -- centre de masse du corps (getLinearVelocity est la vitesse du centre de masse)
    local cx, cy, cz
    local okc, lx, ly, lz = pcall(getCenterOfMass, body)
    if okc and lx ~= nil then
        cx, cy, cz = localToWorld(body, lx, ly, lz)
    else
        cx, cy, cz = getWorldTranslation(body)
    end
    local px, py, pz = getWorldTranslation(ref)
    local rx, ry, rz = px - cx, py - cy, pz - cz
    -- v_point = v + w x r
    local ux = vx + (wy * rz - wz * ry)
    local uy = vy + (wz * rx - wx * rz)
    local uz = vz + (wx * ry - wy * rx)
    local dx, dy, dz = localDirectionToWorld(ref, 0, 0, 1)
    return math.abs(ux * dx + uy * dy + uz * dz)
end

-- Patinage maximal (en %) parmi les roues au sol : roue plus rapide que le véhicule.
local function getMaxSlipPercent(vehicle)
    local ws = vehicle.spec_wheels
    if ws == nil or ws.wheels == nil then return nil end

    local vehSpeed = math.abs(vehicle:getLastSpeed() or 0) / 3.6   -- m/s
    local maxSlip = 0

    for _, wheel in ipairs(ws.wheels) do
        local p = wheel.physics or wheel
        local node   = wheel.node or p.node
        local shape  = p.wheelShape or wheel.wheelShape
        local radius = p.radius or wheel.radius
        local contact = p.hasGroundContact
        if contact == nil then contact = wheel.hasGroundContact end

        if node ~= nil and shape ~= nil and radius ~= nil and contact ~= false then
            local ok, axleSpeed = pcall(getWheelShapeAxleSpeed, node, shape)
            if ok and axleSpeed ~= nil then
                local wheelSpeed = math.abs(axleSpeed) * radius
                if wheelSpeed >= AS_Diff.MIN_WHEEL_SPEED then
                    local ground = wheelGroundSpeed(wheel, vehSpeed)
                    local slip = (wheelSpeed - ground) / wheelSpeed * 100
                    if slip > maxSlip then maxSlip = slip end
                end
            end
        end
    end
    return maxSlip
end

-- (v1.30) Patinage (%) des roues de l'essieu ARRIÈRE uniquement.
-- Les roues arrière sont celles dont la position (repère du véhicule, z = avant) est
-- en arrière du milieu de l'empattement.
local function getRearSlipPercent(vehicle)
    local ws = vehicle.spec_wheels
    if ws == nil or ws.wheels == nil or vehicle.rootNode == nil then return nil end
    local positions, minZ, maxZ = {}, math.huge, -math.huge
    for i, wheel in ipairs(ws.wheels) do
        local n = wheel.repr or wheel.driveNode or wheel.node
        if n ~= nil and n ~= 0 then
            local ok, _, _, z = pcall(localToLocal, n, vehicle.rootNode, 0, 0, 0)
            if ok and type(z) == "number" then
                positions[i] = z
                if z < minZ then minZ = z end
                if z > maxZ then maxZ = z end
            end
        end
    end
    if minZ == math.huge or maxZ - minZ < 0.5 then return nil end
    local midZ = (minZ + maxZ) * 0.5

    local vehSpeed = math.abs(vehicle:getLastSpeed() or 0) / 3.6
    local maxSlip = 0
    for i, wheel in ipairs(ws.wheels) do
        local z = positions[i]
        if z ~= nil and z < midZ then
            local p = wheel.physics or wheel
            local node   = wheel.node or p.node
            local shape  = p.wheelShape or wheel.wheelShape
            local radius = p.radius or wheel.radius
            local contact = p.hasGroundContact
            if contact == nil then contact = wheel.hasGroundContact end
            if node ~= nil and shape ~= nil and radius ~= nil and contact ~= false then
                local ok, axleSpeed = pcall(getWheelShapeAxleSpeed, node, shape)
                if ok and axleSpeed ~= nil then
                    local wheelSpeed = math.abs(axleSpeed) * radius
                    if wheelSpeed >= AS_Diff.MIN_WHEEL_SPEED then
                        local slip = (wheelSpeed - wheelGroundSpeed(wheel, vehSpeed)) / wheelSpeed * 100
                        if slip > maxSlip then maxSlip = slip end
                    end
                end
            end
        end
    end
    return maxSlip
end

-- (v1.0.0.35) Patinage (%) par coin du véhicule : { fl, fr, rl, rr } (avant/arrière, gauche/droite),
-- le plus fort des pneus du coin (jumelées comprises) ; nil pour un coin sans roue mesurée.
local function getWheelSlips(vehicle)
    local ws = vehicle.spec_wheels
    if ws == nil or ws.wheels == nil or vehicle.rootNode == nil then return nil end
    local pos, minZ, maxZ = {}, math.huge, -math.huge
    for i, wheel in ipairs(ws.wheels) do
        local n = wheel.repr or wheel.driveNode or wheel.node
        if n ~= nil and n ~= 0 then
            local ok, x, _, z = pcall(localToLocal, n, vehicle.rootNode, 0, 0, 0)
            if ok and type(z) == "number" then
                pos[i] = { x = x, z = z }
                if z < minZ then minZ = z end
                if z > maxZ then maxZ = z end
            end
        end
    end
    if minZ == math.huge or maxZ - minZ < 0.5 then return nil end
    local midZ = (minZ + maxZ) * 0.5

    local vehSpeed = math.abs(vehicle:getLastSpeed() or 0) / 3.6
    local res = {}
    for i, wheel in ipairs(ws.wheels) do
        local ps = pos[i]
        if ps ~= nil then
            local key = (ps.z >= midZ and "f" or "r") .. (ps.x >= 0 and "l" or "r")
            local p = wheel.physics or wheel
            local node   = wheel.node or p.node
            local shape  = p.wheelShape or wheel.wheelShape
            local radius = p.radius or wheel.radius
            local slip = 0
            if node ~= nil and shape ~= nil and radius ~= nil and p.hasGroundContact ~= false then
                local ok, axleSpeed = pcall(getWheelShapeAxleSpeed, node, shape)
                if ok and axleSpeed ~= nil then
                    local wheelSpeed = math.abs(axleSpeed) * radius
                    if wheelSpeed >= AS_Diff.MIN_WHEEL_SPEED then
                        slip = math.max(0, (wheelSpeed - wheelGroundSpeed(wheel, vehSpeed)) / wheelSpeed * 100)
                    end
                end
            end
            if res[key] == nil or slip > res[key] then res[key] = slip end
        end
    end
    return res
end

local function asState(sample, locked)
    if type(sample) == "number" then return locked and 1 or 0 end
    return locked
end

local function isLockedValue(x)
    return x == true or (type(x) == "number" and x ~= 0)
end

local function shClamp(v, a, b)
    v = tonumber(v) or 0
    if v < a then return a end
    if v > b then return b end
    return v
end

local function shSmootherstep(e0, e1, x)
    if e0 == e1 then return (x >= e1) and 1 or 0 end
    x = shClamp((x - e0) / (e1 - e0), 0, 1)
    return x * x * x * (x * (x * 6 - 15) + 10)
end

-- Classes du mod MudSystemPhysics (chaque mod a son propre environnement Lua)
-- (v1.11) accès normal, pas rawget : chaque mod a son propre environnement et rawget
-- ne voit pas les globales du jeu ni celles des autres mods.
local function getMudClass(name)
    local env = FS25_MudSystemPhysics
    if type(env) == "table" and env[name] ~= nil then return env[name] end
    return _G[name]
end

-- (v1.0.0.09) globale publiée par un autre mod : d'abord dans l'environnement du mod,
-- puis dans les globales du jeu (jamais rawget, voir getMudClass)
local function modGlobal(modName, name)
    local ok, v = pcall(function()
        local env = _G[modName]
        if type(env) == "table" and env[name] ~= nil then return env[name] end
        return _G[name]
    end)
    if ok then return v end
    return nil
end

local function shGetControlledVehicle()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local ok, v = pcall(g_localPlayer.getCurrentVehicle, g_localPlayer)
        if ok and v ~= nil then return v end
    end
    if g_currentMission ~= nil then
        return g_currentMission.controlledVehicle
    end
    return nil
end

-- v1.9 : durée d'affichage réglable de chaque notification (ms) : pneus, différentiels, alerte de patinage
AS_NotifyDuration = { tires = 4000, diffs = 4000, alert = 5000 }

-- Partage avec les autres fichiers
AS.vtpInfo = vtpInfo
AS.L = L
AS.showTimedNotification = showTimedNotification
AS.getVtpClass = getVtpClass
AS.isAutoDriveActive = isAutoDriveActive
AS.isCourseplayActive = isCourseplayActive
AS.is4wd = is4wd
AS.isHarvester = isHarvester
AS.isVehicleInField = isVehicleInField
AS.getVehicles = getVehicles
AS.getEvClass = getEvClass
AS.getMaxSlipPercent = getMaxSlipPercent
AS.getRearSlipPercent = getRearSlipPercent
AS.getWheelSlips = getWheelSlips
AS.asState = asState
AS.isLockedValue = isLockedValue
AS.shClamp = shClamp
AS.shSmootherstep = shSmootherstep
AS.getMudClass = getMudClass
AS.modGlobal = modGlobal
AS.shGetControlledVehicle = shGetControlledVehicle
