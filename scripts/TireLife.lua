-- AutoSwitch : usure des pneus (module AutoSwitch, écrit de zéro)
-- Fichier chargé par AutoSwitch.lua (après Common.lua et WetGrip.lua).

local vtpInfo, L, showTimedNotification, getVehicles, shClamp, shGetControlledVehicle, modGlobal
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVehicles, AS.shClamp, AS.shGetControlledVehicle, AS.modGlobal

-------------------------------------------------------------------------------
-- v1.0.3.0 : usure des pneus gérée par AutoSwitch (remplace Use Your Tyres, qui reste
--   prioritaire s'il est activé : ce module se coupe alors tout seul).
--   Chaque pneu (et chaque chenille) a sa propre usure, de 0 (neuf) à 1 (lisse).
--   - Usure : distance roulée + distance glissée (patinage, roue bloquée au freinage),
--     multipliées par le sol (route > chemin > terre > champ), la charge réelle de la
--     roue, la pression (Mud System Physics ou Variable Tire Pressure), la vitesse sur
--     route, la température et l'humidité du sol.
--   - Adhérence : le pneu usé perd de l'adhérence au champ, sur la terre et la neige ;
--     sur route sèche il en gagne un peu (plus de gomme au sol, effet slick), sur route
--     mouillée il en perd. Appliquée dans le passage unique de WetGrip.lua.
--   - Rayon : le rayon physique diminue autant que la gomme rabotée (le pneu reste posé au
--     sol), par la voie de calcul du rayon de Mud System Physics (aucun fichier de MSP modifié).
--   - Chenilles : usure plus lente au champ, plus rapide sur route, pas de rayon.
--   - Aspect : crampons rabotés selon l'usure jusqu'au pneu lisse, boue du pneu comprise
--     (shaders/asTireShader.xml et asTireMudShader.xml : shaders de Giants + paramètre
--     asTireWear), gomme rayée (paramètre d'usure standard), toutes remorques comprises.
--   - Affichage : barres sur le tracteur du HUD d'AutoSwitch, ligne dans la boîte
--     d'info du véhicule, alertes à 75 % et 90 %.
--   - Atelier : bouton « Pneus neufs » (pneus usés à 25 % ou plus remplacés).
--   - Sauvegarde : autoswitch_tires.xml dans la partie, par véhicule et par jeu de
--     roues (changer de jeu de roues garde l'usure de chaque jeu).
-------------------------------------------------------------------------------
AS_TireLife = {}
AS_TireLife.ENABLED = true
AS_TireLife.LIFE_KM = 1500           -- durée de vie d'un pneu de 2 m sur route, charge normale (réglage)
AS_TireLife.FILE_NAME = "autoswitch_tires.xml"
AS_TireLife.UPDATE_MS = 500          -- calcul de l'usure
AS_TireLife.SLIDE_K = 4.0            -- 1 m glissé use comme 4 m roulés
AS_TireLife.REF_DIAMETER = 2.0       -- la durée de vie est donnée pour ce diamètre
AS_TireLife.LOAD_PER_M2 = 1.75       -- charge normale d'un pneu (t) = 1,75 x largeur x diamètre (moitié de sa charge maxi)
AS_TireLife.TRACK_LIFE_MUL = 2.0     -- chenilles : durée de vie x2
AS_TireLife.STEER_K = 2.0            -- roue braquée : usure x(1 + 2 x sin(angle) x sol), 30° sur goudron = x2
-- pneu lisse : part du rayon rabotée à 100 % (aspect et rayon physique), selon le type de pneu
AS_TireLife.LUG_DEPTH = { mud = 0.075, offroad = 0.045, street = 0.03, default = 0.06 }
AS_TireLife.NO_SHAVE_MAX = 0.02      -- pneu que notre shader ne sait pas raboter : rayon physique -2 % au plus
AS_TireLife.SHAVE_FROM = 0.03        -- aspect : crampons rabotés à partir de 3 % d'usure
AS_TireLife.SMOOTH_FROM = 0.90       -- aspect : pneu lisse, sans dessin, à partir de 90 %
AS_TireLife.MUD_GAP = 0.004          -- aspect : la boue du pneu reste 4 mm au-dessus de la gomme rabotée
AS_TireLife.EDGE_KEEP = 0.3          -- aspect : les bords de la bande s'usent moins que le milieu (0 = autant)
AS_TireLife.DEBUG_SHAVE = false
AS_TireLife.HOLDER_I3D = "objects/tireRackAR/asTireMaterial.i3d"   -- matériau du shader shaders/asTireShader.xml
AS_TireLife.REPLACE_FROM = 0.25      -- atelier : pneus remplacés à partir de 25 % d'usure
AS_TireLife.PRICE_K = 1500           -- prix d'un pneu = 1500 x diamètre^1,5 x largeur (710/70R42 : ~3000)
AS_TireLife.ALERTS = { 0.75, 0.90 }
AS_TireLife.SHAVE = true             -- crampons rabotés (shader)

-- sol : part de la distance qui use le pneu (route = 1)
AS_TireLife.SURFACE = {}
AS_TireLife.TRACK_SURFACE = {}

AS_TireLife.active = false           -- false si Use Your Tyres est activé
AS_TireLife.installed = false
AS_TireLife.timer = 0
AS_TireLife.pending = {}             -- [uniqueId] = { cfg, sets = { [cfg] = { usures } } } lus dans la partie
AS_TireLife.vehicles = {}            -- [vehicle] = état (faible)
setmetatable(AS_TireLife.vehicles, { __mode = "k" })

function AS_TireLife.logLine(msg)
    local line = "[AS_TireLife] " .. msg
    -- version TEST : toujours écrit (même si les logs d'AutoSwitch sont coupés)
    if AS_TireLife.DEBUG_SHAVE and AS.rawPrint ~= nil then return AS.rawPrint(line) end
    print(line)
end

local function sprint(fmt, ...)
    AS_TireLife.logLine(string.format(fmt, ...))
end

local function text(key, fallback)
    local t = L(key)
    if t == key then return fallback end
    return t
end

-------------------------------------------------------------------------------
-- Pneu ou chenille ?
-------------------------------------------------------------------------------
local function isTrack(wheel)
    local wp = wheel.physics
    if wp ~= nil and WheelsUtil ~= nil and WheelsUtil.getTireTypeName ~= nil and wp.tireType ~= nil then
        local ok, name = pcall(WheelsUtil.getTireTypeName, wp.tireType)
        if ok and type(name) == "string" and string.lower(name) == "crawler" then return true end
    end
    -- Mud System marque les roues des chenilles (spec_crawlers)
    if wheel.__mpIsCrawlerTrackWheel == true or (wp ~= nil and wp.__mpIsCrawlerTrackWheel == true) then return true end
    return wheel.__asIsTrack == true
end

-- roues des chenilles déclarées par le véhicule
local function markTracks(vehicle)
    local spec = vehicle.spec_crawlers
    if spec == nil or type(spec.crawlers) ~= "table" then return end
    for _, crawler in pairs(spec.crawlers) do
        if type(crawler) == "table" and type(crawler.wheels) == "table" then
            for _, w in ipairs(crawler.wheels) do
                local wheel = type(w) == "table" and (w.wheel or w) or nil
                if type(wheel) == "table" then wheel.__asIsTrack = true end
            end
        end
    end
end

local function wheelDims(wheel)
    local wp = wheel.physics
    local r = (wp ~= nil and (wp.radiusOriginal or wp.radius)) or wheel.radius or 0.5
    local w = (wp ~= nil and wp.width) or wheel.width or 0.4
    if type(r) ~= "number" or r <= 0.05 then r = 0.5 end
    if type(w) ~= "number" or w <= 0.02 then w = 0.4 end
    return r * 2, w
end

-------------------------------------------------------------------------------
-- État par véhicule
-------------------------------------------------------------------------------
local function wheelConfigId(vehicle)
    local c = vehicle.configurations
    return c ~= nil and tonumber(c.wheel) or 1
end

local function getWheels(vehicle)
    local ws = vehicle.spec_wheels
    return ws ~= nil and ws.wheels or nil
end

-- usures des roues -> liste
local function readWears(wheels)
    local t = {}
    -- chenille entaillée : usure + 10 (relu par applyWears)
    for i, wheel in ipairs(wheels) do t[i] = (wheel.__asWear or 0) + (wheel.__asCut and 10 or 0) end
    return t
end

local function applyWears(wheels, list)
    for i, wheel in ipairs(wheels) do
        local v = list ~= nil and list[i] or 0
        wheel.__asCut = v >= 10 or nil
        if v >= 10 then v = v - 10 end
        wheel.__asWear = shClamp(v, 0, 1)
    end
end

function AS_TireLife:getState(vehicle)
    local st = self.vehicles[vehicle]
    if st ~= nil then return st end
    local wheels = getWheels(vehicle)
    if wheels == nil or #wheels == 0 then return nil end
    if vehicle.spec_locomotive ~= nil then return nil end
    markTracks(vehicle)
    local id = vehicle.uniqueId
    local saved = id ~= nil and self.pending[id] or nil
    st = { sets = {}, alerted = {}, dist = 0, radiusSeen = {}, since = g_time or 0 }
    st.cfg = wheelConfigId(vehicle)
    if saved ~= nil then
        st.sets = saved.sets or {}
        -- usure reprise de Use Your Tyres
        if saved.uyt ~= nil then self:mergeUyt(vehicle, st.sets, st.cfg, saved.uyt) end
        self.pending[id] = nil
    end
    applyWears(wheels, st.sets[st.cfg])
    -- alertes déjà dépassées : pas répétées au chargement
    for i, wheel in ipairs(wheels) do
        for k, a in ipairs(self.ALERTS) do
            if (wheel.__asWear or 0) >= a then st.alerted[k] = true end
        end
    end
    self.vehicles[vehicle] = st
    pcall(self.applyVisualAll, self, vehicle)
    -- rayon d'un pneu déjà usé (partie chargée), après l'aspect (forme gérée ou non)
    for _, wheel in ipairs(wheels) do
        if (wheel.__asWear or 0) > 0 then pcall(self.updateRadius, self, wheel) end
    end
    return st
end

-- jeu de roues changé (atelier, magasin) : l'usure de chaque jeu est gardée
function AS_TireLife:checkConfig(vehicle, st)
    local cfg = wheelConfigId(vehicle)
    if cfg == st.cfg then return end
    local wheels = getWheels(vehicle)
    if wheels == nil then return end
    st.sets[st.cfg] = readWears(wheels)
    st.cfg = cfg
    applyWears(wheels, st.sets[cfg])
    st.alerted = {}
    for _, wheel in ipairs(wheels) do wheel.__asTireShapes, wheel.__asVisual, wheel.__asShaveW = nil, nil, nil end
    pcall(self.applyVisualAll, self, vehicle)
    for _, wheel in ipairs(wheels) do pcall(self.updateRadius, self, wheel) end
    sprint("%s : jeu de roues %d, usure reprise", tostring(vehicle:getName()), cfg)
end

-------------------------------------------------------------------------------
-- Facteurs d'usure
-------------------------------------------------------------------------------
local function groundTypeOf(wp)
    if WheelsUtil == nil or WheelsUtil.getGroundType == nil then return nil end
    local isField = wp.densityType ~= nil and FieldGroundType ~= nil and wp.densityType ~= FieldGroundType.NONE
    local isRoad = WheelContactType ~= nil and wp.contact ~= WheelContactType.GROUND
    local ok, gt = pcall(WheelsUtil.getGroundType, isField, isRoad, wp.groundDepth or 0)
    if ok then return gt end
    return nil
end

-- braquage : la gomme frotte plus sur un sol dur et rugueux (matériau du sol sous la roue,
-- celui des sons de roulement), sinon selon le type de sol du jeu
AS_TireLife.STEER_MATERIAL = { asphalt = 1.0, concrete = 1.0, cobblestone = 0.9, gravel = 0.8, rock = 0.8,
    dirt = 0.5, soil = 0.5, sand = 0.4, grass = 0.35, mud = 0.25, field = 0.3, snow = 0.15, ice = 0.1 }
AS_TireLife.STEER_GROUND = {}

-- nom du matériau du sol sous la roue (sons de roulement du jeu), nil si inconnu
local terrainNames, terrainLogged = nil, {}
local function terrainMaterial(wheel, wp)
    local t = wp.lastTerrainAttribute or wheel.lastTerrainAttribute
    if t == nil or g_currentMission == nil then return nil end
    if terrainNames == nil then
        terrainNames = {}
        for _, ss in pairs(type(g_currentMission.surfaceSounds) == "table" and g_currentMission.surfaceSounds or {}) do
            local name = type(ss) == "table" and (ss.materialName or ss.name) or nil
            if type(ss) == "table" and ss.terrainAttribute ~= nil and type(name) == "string" then
                terrainNames[ss.terrainAttribute] = string.lower(name)
            end
        end
    end
    local name = terrainNames[t]
    if name ~= nil and AS_TireLife.DEBUG_SHAVE and not terrainLogged[name] then
        terrainLogged[name] = true
        AS_TireLife.logLine(string.format("sol sous les roues : %s (%s)", name, tostring(t)))
    end
    return name
end

function AS_TireLife:steerSurface(wheel, wp, gt)
    local name = terrainMaterial(wheel, wp)
    if name ~= nil then
        for key, v in pairs(self.STEER_MATERIAL) do
            if name:find(key, 1, true) then return v end
        end
    end
    return self.STEER_GROUND[gt] or 0.5
end

function AS_TireLife:buildSurfaces()
    if WheelsUtil == nil or WheelsUtil.GROUND_ROAD == nil then return end
    local s, t = self.SURFACE, self.TRACK_SURFACE
    s[WheelsUtil.GROUND_ROAD] = 1.00
    s[WheelsUtil.GROUND_HARD_TERRAIN] = 0.60
    s[WheelsUtil.GROUND_SOFT_TERRAIN] = 0.35
    s[WheelsUtil.GROUND_FIELD] = 0.30
    -- chenilles en caoutchouc : la route les use vite, le champ très peu
    t[WheelsUtil.GROUND_ROAD] = 1.30
    t[WheelsUtil.GROUND_HARD_TERRAIN] = 0.55
    t[WheelsUtil.GROUND_SOFT_TERRAIN] = 0.25
    t[WheelsUtil.GROUND_FIELD] = 0.18
    local g = self.STEER_GROUND
    g[WheelsUtil.GROUND_ROAD] = 1.0
    g[WheelsUtil.GROUND_HARD_TERRAIN] = 0.7
    g[WheelsUtil.GROUND_SOFT_TERRAIN] = 0.4
    g[WheelsUtil.GROUND_FIELD] = 0.3
end

-- pression du pneu de 0 (basse, champ) à 1 (haute, route) ; nil si inconnue
local function pressure01(vehicle, wp)
    local tps = modGlobal("FS25_MudSystemPhysics", "TirePressureSystem")
    if type(tps) == "table" and tps.enabled == true and type(tps.getWheelPressure01) == "function" then
        local ok, p = pcall(tps.getWheelPressure01, tps, wp)
        if ok and type(p) == "number" then return shClamp(p, 0, 1) end
    end
    local root = vehicle.rootVehicle or vehicle
    for _, v in ipairs({ vehicle, root }) do
        local spec = v.spec_variableTirePressure
        if spec ~= nil and spec.isRoadMode ~= nil then
            return spec.isRoadMode == true and 1 or 0.3
        end
    end
    return nil
end

-- charge de la roue / charge normale du pneu
local function loadFactor(wheel)
    local wp = wheel.physics
    if wp == nil or wp.getTireLoad == nil then return 1 end
    local ok, load = pcall(wp.getTireLoad, wp)
    if not ok or type(load) ~= "number" or load <= 0.01 then return 1 end
    local d, w = wheelDims(wheel)
    local nominal = math.max(0.2, AS_TireLife.LOAD_PER_M2 * w * d)
    return shClamp((load / nominal) ^ 0.8, 0.4, 2.5)
end

function AS_TireLife:readWeather()
    local wet, temp = 0, 15
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local w = env ~= nil and env.weather or nil
    if w ~= nil then
        if w.getGroundWetness ~= nil then
            local ok, v = pcall(w.getGroundWetness, w)
            if ok and type(v) == "number" then wet = v end
        end
        if w.getCurrentTemperature ~= nil then
            local ok, v = pcall(w.getCurrentTemperature, w)
            if ok and type(v) == "number" then temp = v end
        end
    end
    self.wet, self.temp = shClamp(wet, 0, 1), temp
end

-- usure d'une roue pendant dtS secondes (moved = distance parcourue par le véhicule)
function AS_TireLife:wheelWear(vehicle, wheel, dtS, moved, vehSpeed)
    local wp = wheel.physics
    if wp == nil or wp.wheelShape == nil or wp.wheelShape == 0 or wp.hasGroundContact == false then return 0 end
    if WheelContactType ~= nil and wp.contact == WheelContactType.NONE then return 0 end
    local node = wheel.node or wp.node
    local radius = wp.radius or wheel.radius
    if node == nil or radius == nil then return 0 end

    -- distance roulée et glissée
    local rolled, slid = moved, 0
    local ok, axleSpeed = pcall(getWheelShapeAxleSpeed, node, wp.wheelShape)
    if ok and type(axleSpeed) == "number" then
        local wheelSpeed = math.abs(axleSpeed) * radius
        local ground = vehSpeed
        if AS.wheelGroundSpeed ~= nil then
            local okg, g = pcall(AS.wheelGroundSpeed, wheel, vehSpeed)
            if okg and type(g) == "number" then ground = g end
        end
        rolled = math.max(moved, wheelSpeed * dtS)
        -- patinage (roue plus rapide) ou glissade (roue bloquée au freinage)
        slid = math.abs(wheelSpeed - ground) * dtS
        -- en dessous de 3 % : déformation normale du pneu, pas de glissade
        if slid < 0.03 * rolled then slid = 0 end
    end
    if rolled <= 0.001 and slid <= 0.001 then return 0 end

    local track = isTrack(wheel)
    local gt = groundTypeOf(wp)
    local road = WheelsUtil ~= nil and gt == WheelsUtil.GROUND_ROAD
    local surf = (track and self.TRACK_SURFACE[gt] or self.SURFACE[gt]) or 0.5
    if wp.hasSnowContact then surf = 0.15 end

    local f = surf * loadFactor(wheel)
    -- pression : basse sur route = flancs qui travaillent, usure plus rapide ;
    -- basse au champ = moins de patinage, un peu moins d'usure
    if not track then
        local p = pressure01(vehicle, wp)
        if p ~= nil then
            if road then f = f * (1 + 0.5 * (1 - p)) else f = f * (1 - 0.15 * (1 - p)) end
        end
    end
    -- vitesse sur route au-delà de 40 km/h
    if road then
        local kph = vehSpeed * 3.6
        if kph > 40 then f = f * (1 + math.min(0.5, (kph - 40) / 60 * 0.5)) end
        -- route chaude : gomme plus tendre
        local t = self.temp or 15
        if t > 20 then f = f * (1 + math.min(0.2, (t - 20) * 0.01))
        elseif t < 0 then f = f * 0.9 end
    end
    -- braquage : la roue braquée frotte, selon le sol (goudron, béton, gravier, terre, herbe...)
    if not track then
        local steer = math.abs(wheel.steeringAngle or wp.steeringAngle or 0)
        if steer > 0.02 then
            f = f * (1 + self.STEER_K * math.sin(math.min(steer, 1.2)) * self:steerSurface(wheel, wp, gt))
        end
    end
    -- sol mouillé : l'eau limite l'abrasion
    f = f * (1 - 0.3 * (self.wet or 0))
    -- pneu crevé (Mud System) : rouler à plat détruit la gomme
    if not track and self:isPunctured(vehicle, wheel) then f = f * self.PUNCTURE_WEAR end
    -- chenille entaillée : la coupure s'agrandit
    if track and wheel.__asCut then f = f * self.CUT_WEAR end

    local d = wheelDims(wheel)
    local life = self.LIFE_KM * 1000 * shClamp(d / self.REF_DIAMETER, 0.35, 1.5)
    if track then life = life * self.TRACK_LIFE_MUL end
    return (rolled + self.SLIDE_K * slid) * f / math.max(1000, life)
end

-------------------------------------------------------------------------------
-- Adhérence (appelé par WetGrip.lua au calcul de l'adhérence de la roue)
-------------------------------------------------------------------------------
function AS_TireLife:getGripMul(wp)
    if not self.active or not self.ENABLED or wp == nil or wp.wheel == nil then return 1 end
    local wheel = wp.wheel
    local w = wheel.__asWear or 0
    local cutMul = wheel.__asCut and self.CUT_GRIP or 1
    if w < 0.02 then return cutMul end
    local k = isTrack(wheel) and 0.5 or 1
    local mul
    if wp.hasSnowContact then
        mul = 1 - 0.5 * (w ^ 1.3)
    else
        local gt = groundTypeOf(wp)
        if WheelsUtil ~= nil and gt == WheelsUtil.GROUND_ROAD then
            -- route : plus de gomme au sol (sec), aquaplaning (mouillé)
            local wet01 = shClamp(((self.wet or 0) - 0.2) / 0.5, 0, 1)
            mul = 1 + 0.10 * w - 0.35 * w * wet01
        else
            local loss = 0.45 * (w ^ 1.5)
            if w > 0.9 then loss = loss + 0.10 * (w - 0.9) / 0.1 end
            mul = 1 - loss
        end
    end
    mul = (1 + (mul - 1) * k) * cutMul
    return shClamp(mul, 0.45, 1.10)
end

-- WetGrip.lua absent (sans MoreRealistic) : notre propre passage sur l'adhérence
function AS_TireLife:installOwnFriction()
    if WheelPhysics == nil or WheelPhysics.updateTireFriction == nil then return end
    WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, function(wp, superFunc)
        local mul = AS_TireLife:getGripMul(wp)
        if math.abs(mul - 1) <= 0.001 then return superFunc(wp) end
        local old = wp.frictionScale
        wp.frictionScale = (old or 1) * mul
        local ok, err = pcall(superFunc, wp)
        wp.frictionScale = old
        if not ok then error(err) end
    end)
    sprint("adhérence : passage propre (WetGrip inactif)")
end

-------------------------------------------------------------------------------
-- Rayon : voie « rayon de base » du calcul de rayon de Mud System Physics
-- (les autres effets de MSP, enfoncement, pression, crevaison, partent de ce rayon)
-------------------------------------------------------------------------------
function AS_TireLife:updateRadius(wheel)
    local wp = wheel.physics
    if wp == nil or isTrack(wheel) then return end
    local comb = modGlobal("FS25_MudSystemPhysics", "__MudRadiusCombiner")
    if type(comb) ~= "table" or type(comb.apply) ~= "function" then return end
    local r0 = wp.radiusOriginal
    if type(r0) ~= "number" or r0 <= 0.05 then return end
    -- même profondeur que la gomme rabotée : le pneu reste posé au sol
    local frac = self:wearDepthFrac(wheel.__asWear or 0, wheel)
    if not self:shaveVisible(wheel) then frac = math.min(frac, self.NO_SHAVE_MAX) end
    local target = r0 * (1 - frac)
    local cur = wp.__rvDesiredRadius
    if type(cur) == "number" and math.abs(cur - target) < 0.002 then return end
    wp.__rvOrigRadius = r0
    wp.__rvDesiredRadius = target
    pcall(comb.apply, wp, 0.001)
end

-- TTD (Tractor Terrain Dynamics) lit l'usure dans les champs de Use Your Tyres :
--   vehicle.uytHasTyres / uytMultiplier, wheel.uytTravelledDist (son icône : usure =
--   distance / (240 km x multiplicateur)) et wheel.uytWearMultiplier (rayon = rayon d'origine
--   x coefficient, patinage, crevaisons). On les remplit avec notre usure (pas de chiffre
--   tant que Use Your Tyres est là : c'est lui qui les remplit). Chenilles : seulement le %.
AS_TireLife.TTD_UYT_DIST = 240000

function AS_TireLife:syncTtd(vehicle, wheels)
    if self:isUytActive() or g_modIsLoaded == nil or g_modIsLoaded["FS25_TractorTerrainDynamics"] ~= true then return end
    if not self.ENABLED then
        if vehicle.__asTtd then
            vehicle.__asTtd, vehicle.uytHasTyres, vehicle.uytMultiplier = nil, nil, nil
            for _, wheel in ipairs(wheels) do wheel.uytTravelledDist, wheel.uytWearMultiplier = nil, nil end
        end
        return
    end
    vehicle.__asTtd = true
    vehicle.uytHasTyres = true
    vehicle.uytMultiplier = 1
    for _, wheel in ipairs(wheels) do
        local w = shClamp(wheel.__asWear or 0, 0, 1)
        wheel.uytTravelledDist = w * self.TTD_UYT_DIST
        if wheel.physics ~= nil and not isTrack(wheel) then
            -- même rayon que la gomme rabotée (updateRadius)
            local frac = self:wearDepthFrac(w, wheel)
            if not self:shaveVisible(wheel) then frac = math.min(frac, self.NO_SHAVE_MAX) end
            wheel.uytWearMultiplier = shClamp(1 - frac, 0.8, 1)
        else
            wheel.uytWearMultiplier = nil
        end
    end
end

function AS_TireLife:clearRadius(wheel)
    local wp = wheel.physics
    if wp == nil or wp.__rvDesiredRadius == nil then return end
    wp.__rvDesiredRadius, wp.__rvOrigRadius = nil, nil
    local comb = modGlobal("FS25_MudSystemPhysics", "__MudRadiusCombiner")
    if type(comb) == "table" and type(comb.apply) == "function" then pcall(comb.apply, wp, 0.001) end
end

-------------------------------------------------------------------------------
-- Aspect du pneu usé
--   - gomme rayée : paramètre d'usure standard du jeu (scratches) ;
--   - crampons rabotés : notre shader shaders/asTireShader.xml (shader véhicule de Giants
--     + paramètre asTireWear) ramène la gomme sur une coupe qui suit l'arrondi du pneu
--     (super-ellipse calée sur le rayon, la largeur et la jante) : le milieu de la bande
--     s'use le plus, les épaules moins, les flancs pas ; la boue collée au pneu (tireMudShader
--     du jeu) est coupée pareil, quelques mm au-dessus (shaders/asTireMudShader.xml) ;
--   - pneu lisse (SMOOTH_FROM) : plus de relief ni de masque du dessin, seulement la gomme.
-- Le matériau de chaque forme du pneu (toutes les LOD) est remplacé par le nôtre, avec ses
-- textures, dès SHAVE_FROM. Le jeu efface un matériau que plus aucune forme n'utilise : les
-- noms des textures d'origine sont lus une fois (recette) et le nôtre est refait quand il
-- le faut. Le rayon physique baisse comme le milieu de la bande (updateRadius) : le pneu
-- raboté reste posé au sol.
-------------------------------------------------------------------------------
local SHADER_WEAR = "scratches_dirt_snow_wetness"
local TIRE_PARAMS = { "scratches_dirt_snow_wetness", "porosity", "morphPos", "prevMorphPos", "colorScale",
    "dirtColor", "smoothnessScale", "metalnessScale", "clearCoatIntensity", "clearCoatSmoothness" }
local MUD_PARAMS = { "mudAmount", "prevMudAmount", "morphPos", "prevMorphPos", "dirtColor", "snowDirtRatio",
    "wetness", "porosity" }

-- part du rayon enlevée à l'usure w : régulière jusqu'à 60 %, plus rapide ensuite ; à 100 %
-- les crampons ont disparu (LUG_DEPTH : crampons agricoles, pneus tout-terrain, pneus de
-- route). Même valeur pour l'aspect et pour le rayon physique.
function AS_TireLife:lugDepth(wheel)
    local d = self.LUG_DEPTH
    local wp = wheel ~= nil and wheel.physics or nil
    if wp ~= nil and wp.tireType ~= nil and WheelsUtil ~= nil and WheelsUtil.getTireTypeName ~= nil then
        local ok, name = pcall(WheelsUtil.getTireTypeName, wp.tireType)
        if ok and type(name) == "string" and d[string.lower(name)] ~= nil then return d[string.lower(name)] end
    end
    return d.default
end

function AS_TireLife:wearDepthFrac(w, wheel)
    w = shClamp(w or 0, 0, 1)
    local k = w * 0.75
    if w > 0.6 then k = 0.45 + (w - 0.6) / 0.4 * 0.55 end
    return self:lugDepth(wheel) * k
end

-- formes du pneu (toutes les LOD) : gomme (shader véhicule) et boue (tireMudShader), avec
-- leur roue visuelle (roues jumelées : chacune ses dimensions)
local function tireShapes(wheel)
    local list = wheel.__asTireShapes
    if list ~= nil then return list end
    list = {}
    if getHasShaderParameter ~= nil then
        for _, vw in ipairs(wheel.visualWheels or {}) do
            for _, part in ipairs(vw.visualParts or {}) do
                if type(part.tireNodes) == "table" then
                    for _, n in ipairs(part.tireNodes) do
                        if n ~= nil and n ~= 0 then
                            if getHasShaderParameter(n, "mudAmount") then
                                list[#list + 1] = { node = n, mud = true, vw = vw }
                            elseif getHasShaderParameter(n, SHADER_WEAR) then
                                list[#list + 1] = { node = n, mud = false, vw = vw }
                            end
                        end
                    end
                end
            end
        end
    end
    wheel.__asTireShapes = list
    return list
end

-- matériaux de base (gomme, boue) du fichier objects/tireRackAR/asTireMaterial.i3d
function AS_TireLife:getHolderMaterials()
    if self.holderMat ~= nil or self.holderFailed then return self.holderMat, self.holderMudMat end
    self.holderFailed = true
    if g_i3DManager == nil or getMaterial == nil then return nil end
    local path = Utils.getFilename(self.HOLDER_I3D, AS_MOD_DIR)
    local ok, node, req = pcall(g_i3DManager.loadSharedI3DFile, g_i3DManager, path, false, false)
    if not ok or node == nil or node == 0 then
        sprint("ERREUR matériaux des pneus usés introuvables : %s", tostring(path))
        return nil
    end
    self.holderNode, self.holderReq = node, req
    local function matOf(i)
        if getNumOfChildren(node) <= i then return nil end
        local okM, m = pcall(getMaterial, getChildAt(node, i), 0)
        if okM and m ~= nil and m ~= 0 then return m end
        return nil
    end
    self.holderMat, self.holderMudMat = matOf(0), matOf(1)
    if self.holderMat == nil then
        sprint("ERREUR matériau des pneus usés illisible")
        return nil
    end
    self.holderFailed = false
    self.wornMats = {}
    sprint("shaders des pneus usés chargés (gomme %s, boue %s)", tostring(self.holderMat), tostring(self.holderMudMat))
    return self.holderMat, self.holderMudMat
end

local function okFile(f)
    return type(f) == "string" and f ~= "" and (f:lower():find("%.dds$") or f:lower():find("%.png$")) ~= nil
end

-- recette du matériau d'origine d'une forme : variation et noms des textures, lus tant que
-- le matériau existe (le jeu l'efface quand plus aucune forme ne s'en sert)
local function readRecipe(m, mud)
    local r = { var = getMaterialCustomShaderVariation(m) }
    if type(r.var) ~= "string" then r.var = "" end
    local f = getMaterialDiffuseMapFilename(m)
    if okFile(f) then r.diffuse = f end
    f = getMaterialNormalMapFilename(m)
    if okFile(f) then r.normal = f end
    f = getMaterialGlossMapFilename(m)
    if okFile(f) then r.gloss = f end
    -- chenille caoutchouc : tracé de la bande (trackArray)
    r.custom = {}
    local maps = mud and { "trackArray" } or { "detailDiffuse", "detailNormal", "detailSpecular", "trackArray" }
    for _, cm in ipairs(maps) do
        local okC, cf = pcall(getMaterialCustomMapFilename, m, cm)
        if okC and okFile(cf) then r.custom[cm] = cf end
    end
    local c = r.custom
    r.key = table.concat({ mud and "m" or "t", r.var, r.diffuse or "", r.normal or "", r.gloss or "",
        c.detailDiffuse or "", c.detailNormal or "", c.detailSpecular or "", c.trackArray or "" }, "|")
    return r
end

-- matériau encore là et toujours le nôtre (le jeu réutilise les numéros des matériaux effacés)
local function isOurMaterial(m)
    if m == nil or m == 0 or entityExists == nil or not entityExists(m) then return false end
    if getMaterialCustomShaderFilename == nil then return true end
    local ok, f = pcall(getMaterialCustomShaderFilename, m)
    return ok and type(f) == "string" and f:find("asTire", 1, true) ~= nil
end

-- notre matériau avec les textures de la recette ; smooth : pneu lisse, sans la carte de
-- relief ni le masque du dessin. Réutilisé tant qu'une forme s'en sert, refait sinon.
function AS_TireLife:getWornMaterial(recipe, mud, smooth)
    local ck = recipe.key .. (smooth and "|s" or "")
    local cached = self.wornMats ~= nil and self.wornMats[ck] or nil
    if cached == false then return nil end
    if cached ~= nil and isOurMaterial(cached) and (recipe.diffuse == nil or getMaterialDiffuseMapFilename(cached) == recipe.diffuse)
        and (recipe.normal == nil or (getMaterialNormalMapFilename(cached) == recipe.normal) ~= smooth) then
        return cached
    end
    local base, baseMud = self:getHolderMaterials()
    if mud then base = baseMud end
    if base == nil then return nil end
    local m = base
    if mud then
        -- boue des pneus et des chenilles caoutchouc (motionPathRubber) seulement
        if recipe.var == "motionPathRubber" and recipe.custom.trackArray ~= nil then
            m = setMaterialCustomShaderVariation(m, recipe.var, false)
        elseif recipe.var ~= "" then
            self.wornMats[ck] = false
            return nil
        end
    elseif recipe.var ~= "" and recipe.var ~= "tirePressureDeformation" then
        m = setMaterialCustomShaderVariation(m, recipe.var, false)
    end
    if recipe.diffuse ~= nil then m = setMaterialDiffuseMapFromFile(m, recipe.diffuse, true, true, false) end
    if recipe.normal ~= nil and not smooth then m = setMaterialNormalMapFromFile(m, recipe.normal, true, false, false) end
    if recipe.gloss ~= nil and not smooth then m = setMaterialGlossMapFromFile(m, recipe.gloss, true, false, false) end
    for _, cm in ipairs({ { "detailDiffuse", true }, { "detailNormal", false }, { "detailSpecular", false }, { "trackArray", false } }) do
        local cf = recipe.custom ~= nil and recipe.custom[cm[1]] or nil
        -- chenille lisse : plus de relief de détail non plus
        if smooth and cm[1] == "detailNormal" and recipe.custom.trackArray ~= nil then cf = nil end
        if cf ~= nil then m = setMaterialCustomMapFromFile(m, cm[1], cf, true, cm[2], false) end
    end
    self.wornMats[ck] = m
    sprint("matériau %s %s (variation « %s »%s)", mud and "boue" or "gomme", cached ~= nil and "refait" or "créé",
        recipe.var, smooth and ", lisse" or "")
    return m
end

-- échelle de la forme (repère du maillage -> mètres)
local function shapeScale(node)
    if localToWorld == nil then return 1 end
    local x0, y0, z0 = localToWorld(node, 0, 0, 0)
    local x1, y1, z1 = localToWorld(node, 0, 1, 0)
    local s = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2 + (z1 - z0) ^ 2)
    if s < 0.01 or s > 100 then return 1 end
    return s
end

-- profil du pneu (mètres) : rayon, largeur, centre du profil (mi-flanc) et exposant de la
-- super-ellipse (pneu haut et étroit : rond ; pneu large et bas : plat)
function AS_TireLife:tireProfile(wheel, vw, node)
    local wp = wheel.physics
    local R = vw ~= nil and tonumber(vw.radius) or nil
    if R == nil or R <= 0.05 then R = wp ~= nil and wp.radiusOriginal or nil end
    local W = vw ~= nil and tonumber(vw.width) or nil
    if W == nil or W <= 0.02 then W = wp ~= nil and wp.width or 0.5 end
    if type(R) ~= "number" or R <= 0.05 then return nil end
    local rim = vw ~= nil and tonumber(vw.rimDiameter) or nil
    local rimR = (rim ~= nil and rim > 0) and rim * 0.0254 * 0.5 or nil
    if rimR == nil and getHasShaderParameter(node, "morphPos") then
        -- début de l'écrasement du pneu : un peu au-dessus de la jante
        local mx = getShaderParameter(node, "morphPos")
        if type(mx) == "number" and mx < 0 then rimR = -mx - 0.05 end
    end
    local H = (rimR ~= nil and rimR > 0) and (R - rimR) or (0.6 * W)
    H = math.min(math.max(H, 0.12 * R), 0.6 * R)
    return { R = R, W = W, rm = R - 0.5 * H, n = math.min(math.max(6 - 4 * H / W, 2.2), 5) }
end

-- nouveau matériau ; les paramètres de la forme sont gardés (un pneu du FS22 a encore
-- morphPosition : recopié dans morphPos)
local function swapMaterial(n, mat, params)
    local saved = {}
    for _, pname in ipairs(params) do
        if getHasShaderParameter(n, pname) then saved[pname] = { getShaderParameter(n, pname) } end
    end
    if saved.morphPos == nil and getHasShaderParameter(n, "morphPosition") then
        local x, y, z = getShaderParameter(n, "morphPosition")
        saved.morphPos, saved.prevMorphPos = { x, y, z, 0 }, { x, y, z, 0 }
    end
    setMaterial(n, mat, 0)
    for pname, v in pairs(saved) do
        if getHasShaderParameter(n, pname) then setShaderParameter(n, pname, v[1], v[2], v[3], v[4], false) end
    end
end

function AS_TireLife:applyShave(wheel, w)
    if not self.SHAVE or isTrack(wheel) then return end
    local frac = self:wearDepthFrac(w, wheel)
    for _, s in ipairs(tireShapes(wheel)) do
        local n = s.node
        if s.kind == nil and w >= self.SHAVE_FROM then
            -- premier passage : profil du pneu dans le repère de la forme et recette du
            -- matériau d'origine (gardée par forme : la liste des formes peut être refaite
            -- alors que la forme porte déjà un de nos matériaux)
            s.scale = shapeScale(n)
            s.profile = self:tireProfile(wheel, s.vw, n)
            self.nodeRecipe = self.nodeRecipe or {}
            s.recipe = self.nodeRecipe[n]
            if s.recipe == nil then
                s.recipe = readRecipe(getMaterial(n, 0), s.mud)
                self.nodeRecipe[n] = s.recipe
            end
            s.kind = "orig"
            if s.profile == nil then
                s.failed = true
                sprint("forme %s : dimensions du pneu introuvables", tostring(n))
            end
        end
        if s.kind ~= nil and not s.failed then
            local kind = (not s.mud and w >= self.SMOOTH_FROM) and "smooth" or "worn"
            if s.kind ~= kind or (s.mat ~= nil and not isOurMaterial(getMaterial(n, 0))) then
                local ok, mat = pcall(self.getWornMaterial, self, s.recipe, s.mud, kind == "smooth")
                if ok and mat ~= nil then
                    swapMaterial(n, mat, s.mud and MUD_PARAMS or TIRE_PARAMS)
                    s.kind, s.mat = kind, mat
                    local has = getHasShaderParameter(n, "asTireWear")
                    local p = s.profile
                    sprint("forme %s (%s) : matériau %s, pneu R %.3f L %.3f, centre %.3f, exposant %.1f, échelle %.3f, paramètre asTireWear %s",
                        tostring(n), s.mud and "boue" or "gomme", kind, p.R, p.W, p.rm, p.n, s.scale, tostring(has))
                    if not has then s.failed = true end
                else
                    s.failed = true
                    sprint("forme %s (%s) : pas de matériau usé (%s)", tostring(n), s.mud and "boue" or "gomme",
                        ok and "variation non gérée" or tostring(mat))
                end
            end
            if not s.failed and s.kind ~= "orig" then
                -- coupe : milieu de la bande à R - d ; la demi-largeur dépasse le pneu de
                -- EDGE_KEEP pour que les bords s'usent moins que le milieu
                local p, sc = s.profile, s.scale
                local depth = p.R * frac
                local gap = s.mud and self.MUD_GAP or 0
                if w >= self.SHAVE_FROM then
                    setShaderParameter(n, "asTireWear", (p.R - depth + gap) / sc, p.rm / sc,
                        (p.W * 0.5 * (1 + self.EDGE_KEEP) + gap) / sc, p.n, false)
                else
                    setShaderParameter(n, "asTireWear", 0, 0, 1, 2, false)
                end
                local step = math.floor(w * 10)
                if self.DEBUG_SHAVE and s.logStep ~= step then
                    s.logStep = step
                    local x = getShaderParameter(n, "asTireWear")
                    sprint("forme %s : usure %d %%, milieu de la bande à %.3f (-%.1f cm), relu %.3f", tostring(n),
                        math.floor(w * 100 + 0.5), (p.R - depth + gap) / sc, depth * 100, x or -1)
                end
            end
        end
    end
end

-- gomme rayée : la plus forte de l'usure générale du véhicule et de celle du pneu
local function scratchOf(base, w)
    return math.max(base or 0, math.min(1, (w or 0) * 1.1))
end

function AS_TireLife:applyVisual(vehicle, wheel)
    if setShaderParameter == nil then return end
    if isTrack(wheel) then
        local ok, err = pcall(self.applyTracks, self, vehicle)
        if not ok and not self.loggedTrack then
            self.loggedTrack = true
            sprint("ERREUR chenilles : %s", tostring(err))
        end
    end
    local shapes = tireShapes(wheel)
    if #shapes == 0 then return end
    local w = (self.active and self.ENABLED) and (wheel.__asWear or 0) or 0
    local base = 0
    if vehicle.getWearTotalAmount ~= nil then
        local ok, v = pcall(vehicle.getWearTotalAmount, vehicle)
        if ok and type(v) == "number" then base = v end
    end
    local x = scratchOf(base, w)
    if wheel.__asVisual == nil or math.abs(wheel.__asVisual - x) >= 0.01 then
        wheel.__asVisual = x
        for _, s in ipairs(shapes) do
            if not s.mud then pcall(setShaderParameter, s.node, SHADER_WEAR, x, nil, nil, nil, false) end
        end
    end
    if wheel.__asShaveW ~= nil and math.abs(wheel.__asShaveW - w) < 0.005 then return end
    wheel.__asShaveW = w
    local ok, err = pcall(self.applyShave, self, wheel, w)
    if not ok and not self.loggedShave then
        self.loggedShave = true
        sprint("ERREUR crampons : %s", tostring(err))
    end
end

-- la gomme de ce pneu est rabotée à l'écran (sinon le rayon physique baisse peu)
function AS_TireLife:shaveVisible(wheel)
    if not self.SHAVE then return false end
    for _, s in ipairs(tireShapes(wheel)) do
        if not s.mud and s.failed then return false end
    end
    return true
end

function AS_TireLife:applyVisualAll(vehicle)
    for _, wheel in ipairs(getWheels(vehicle) or {}) do
        wheel.__asVisual, wheel.__asShaveW = nil, nil
        self:applyVisual(vehicle, wheel)
    end
end

-------------------------------------------------------------------------------
-- Chenille caoutchouc usée. La bande (shader véhicule, variation motionPathRubber) est un
-- profil (x en travers, y) posé le long d'un tracé lu dans une texture (trackArray) : -y
-- vers l'extérieur (crampons), +y vers l'intérieur (guides), vérifié sur des tracés de
-- chenilles. Nos shaders (asTrackWear) gardent les crampons au-dessus d'un niveau : le sol
-- sous la chenille (bas des roues physiques, machine posée et arrêtée) moins la profondeur
-- rabotée. Crampons : 85 % de l'épaisseur entre le sol et le bas des galets, sinon
-- TRACK_LUG. La boue de la chenille est coupée pareil, MUD_GAP plus bas.
-------------------------------------------------------------------------------
AS_TireLife.TRACK_LUG = 0.04          -- crampons d'une chenille caoutchouc (m) si l'épaisseur est inconnue
AS_TireLife.TRACK_KEEP = 0            -- part des crampons qui reste à 100 % (Fabien : lisse à 100 %)
AS_TireLife.TRACK_SETTLE_MS = 3000    -- attente après le chargement (machine posée)

local BELT_PARAMS, BELT_MUD_PARAMS = {}, {}
for _, p in ipairs(TIRE_PARAMS) do BELT_PARAMS[#BELT_PARAMS + 1] = p end
for _, p in ipairs(MUD_PARAMS) do BELT_MUD_PARAMS[#BELT_MUD_PARAMS + 1] = p end
for _, p in ipairs({ "scrollPos", "prevScrollPos" }) do
    BELT_PARAMS[#BELT_PARAMS + 1] = p
    BELT_MUD_PARAMS[#BELT_MUD_PARAMS + 1] = p
end
BELT_MUD_PARAMS[#BELT_MUD_PARAMS + 1] = "crawlerRealLength"

local function isRubberBelt(n)
    -- seulement les formes : getMaterial sur un groupe écrit une erreur au journal (Jaguar Terra Trac)
    if getHasClassId ~= nil and ClassIds ~= nil and not getHasClassId(n, ClassIds.SHAPE) then return false end
    local ok, m = pcall(getMaterial, n, 0)
    if not ok or m == nil or m == 0 then return false end
    local okV, v = pcall(getMaterialCustomShaderVariation, m)
    return okV and type(v) == "string" and v:find("motionPathRubber", 1, true) ~= nil
end

-- bandes caoutchouc (et leur boue) de chaque chenille, avec les roues de la chenille
local function crawlerBelts(vehicle)
    local list = vehicle.__asBelts
    if list ~= nil then return list end
    list = {}
    local spec = vehicle.spec_crawlers
    if spec ~= nil and type(spec.crawlers) == "table" and getNumOfChildren ~= nil then
        local seen = {}
        local function scan(n, crawler, wheels, depth)
            if type(n) ~= "number" or n == 0 or seen[n] or depth > 8 then return end
            seen[n] = true
            if isRubberBelt(n) and getHasShaderParameter(n, "scrollPos") then
                list[#list + 1] = { node = n, mud = getHasShaderParameter(n, "mudAmount"), crawler = crawler, wheels = wheels }
            end
            for i = 0, getNumOfChildren(n) - 1 do scan(getChildAt(n, i), crawler, wheels, depth + 1) end
        end
        for _, crawler in pairs(spec.crawlers) do
            if type(crawler) == "table" then
                local wheels = {}
                for _, w in ipairs(type(crawler.wheels) == "table" and crawler.wheels or {}) do
                    local wheel = type(w) == "table" and (w.wheel or w) or nil
                    if type(wheel) == "table" then wheels[#wheels + 1] = wheel end
                end
                for _, sn in pairs(type(crawler.scrollerNodes) == "table" and crawler.scrollerNodes or {}) do
                    if type(sn) == "table" then scan(sn.node, crawler, wheels, 0) end
                end
                scan(crawler.loadedCrawler, crawler, wheels, 0)
            end
        end
    end
    vehicle.__asBelts = list
    return list
end

-- sol sous la chenille et bas des galets, dans le repère de la bande (y)
function AS_TireLife:prepareBelt(s)
    local n = s.node
    s.scale = shapeScale(n)
    if localDirectionToWorld ~= nil then
        local _, uy = localDirectionToWorld(n, 0, 1, 0)
        if type(uy) == "number" and uy < 0.9 * math.min(s.scale, 1) then
            s.failed = true
            sprint("chenille %s : bande pas à plat (%.2f), pas rabotée", tostring(n), uy)
            return
        end
    end
    local ground, inner
    for _, wheel in ipairs(s.wheels) do
        local wp = wheel.physics
        local wn = wheel.repr or wheel.driveNode
        local r = wp ~= nil and (wp.radiusOriginal or wp.radius) or nil
        if wn ~= nil and wn ~= 0 and type(r) == "number" then
            local ok, _, y = pcall(localToLocal, wn, n, 0, 0, 0)
            if ok and type(y) == "number" then
                y = y - r / s.scale
                if ground == nil or y < ground then ground = y end
            end
        end
    end
    for _, rp in pairs(type(s.crawler.rotatingParts) == "table" and s.crawler.rotatingParts or {}) do
        if type(rp) == "table" and rp.node ~= nil and type(rp.radius) == "number" then
            local ok, _, y = pcall(localToLocal, rp.node, n, 0, 0, 0)
            if ok and type(y) == "number" then
                y = y - rp.radius / s.scale
                if inner == nil or y < inner then inner = y end
            end
        end
    end
    if ground == nil then
        s.failed = true
        sprint("chenille %s : roues de la chenille introuvables, pas rabotée", tostring(n))
        return
    end
    local thick = inner ~= nil and (inner - ground) * s.scale or nil
    if thick ~= nil and thick < 0 then
        s.failed = true
        sprint("chenille %s : sol %.3f au-dessus des galets %.3f, pas rabotée", tostring(n), ground, inner)
        return
    end
    s.ground = ground
    s.lug = (thick ~= nil and thick > 0.02 and thick < 0.25) and math.min(math.max(thick * 0.85, 0.02), 0.09) or self.TRACK_LUG
    self.nodeRecipe = self.nodeRecipe or {}
    s.recipe = self.nodeRecipe[n]
    if s.recipe == nil then
        s.recipe = readRecipe(getMaterial(n, 0), s.mud)
        self.nodeRecipe[n] = s.recipe
    end
    sprint("chenille %s (%s) : sol %.3f, galets %s, épaisseur %s, crampons %.1f cm, échelle %.3f, variation %s, tracé %s",
        tostring(n), s.mud and "boue" or "bande", ground, inner ~= nil and string.format("%.3f", inner) or "?",
        thick ~= nil and string.format("%.1f cm", thick * 100) or "?", s.lug * 100, s.scale, s.recipe.var,
        tostring(s.recipe.custom.trackArray))
end

function AS_TireLife:applyTracks(vehicle)
    local st = self.vehicles[vehicle]
    if st == nil or not self.SHAVE then return end
    st.tracksWaiting = nil
    for _, s in ipairs(crawlerBelts(vehicle)) do
        local w = 0
        if self.active and self.ENABLED then
            for _, wheel in ipairs(s.wheels) do w = math.max(w, wheel.__asWear or 0) end
        end
        local step = math.floor(w * 200)
        local kind = (not s.mud and w >= self.SMOOTH_FROM) and "smooth" or "worn"
        if not s.failed and (s.step ~= step or s.kind ~= kind or (s.mat ~= nil and not isOurMaterial(getMaterial(s.node, 0)))) then
            if s.ground == nil and w >= self.SHAVE_FROM then
                local speed = math.abs(vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0)
                if vehicle.isAddedToPhysics == false or speed > 1 or (g_time or 0) < (st.since or 0) + self.TRACK_SETTLE_MS then
                    st.tracksWaiting = true
                else
                    self:prepareBelt(s)
                end
            end
            if s.ground ~= nil and not s.failed then
                if s.mat == nil or s.kind ~= kind or not isOurMaterial(getMaterial(s.node, 0)) then
                    local ok, mat = pcall(self.getWornMaterial, self, s.recipe, s.mud, kind == "smooth")
                    if ok and mat ~= nil then
                        swapMaterial(s.node, mat, s.mud and BELT_MUD_PARAMS or BELT_PARAMS)
                        s.mat, s.kind = mat, kind
                        if not getHasShaderParameter(s.node, "asTrackWear") then
                            s.failed = true
                            sprint("chenille %s : paramètre asTrackWear absent", tostring(s.node))
                        end
                    else
                        s.failed = true
                        sprint("chenille %s (%s) : pas de matériau usé (%s)", tostring(s.node), s.mud and "boue" or "bande",
                            ok and "variation non gérée" or tostring(mat))
                    end
                end
                if not s.failed then
                    local depth = 0
                    if w >= self.SHAVE_FROM then
                        depth = s.lug * (1 - self.TRACK_KEEP) * self:wearDepthFrac(w, nil) / self:lugDepth(nil)
                        if s.mud then depth = depth - self.MUD_GAP end
                    end
                    setShaderParameter(s.node, "asTrackWear", s.ground, math.max(depth, 0) / s.scale, 0, 0, false)
                    s.step = step
                    local logStep = math.floor(w * 10)
                    if self.DEBUG_SHAVE and s.logStep ~= logStep then
                        s.logStep = logStep
                        sprint("chenille %s (%s) : usure %d %%, crampons rabotés de %.1f cm", tostring(s.node),
                            s.mud and "boue" or "bande", math.floor(w * 100 + 0.5), math.max(depth, 0) * 100)
                    end
                end
            end
        end
    end
end

-- le jeu remet l'usure générale du véhicule (rayures) sur ses pièces, pneus compris : on
-- remet celle du pneu sur les formes de gomme touchées, seulement quand le jeu a écrit
if Wearable ~= nil and Wearable.setNodeWearAmount ~= nil then
    Wearable.setNodeWearAmount = Utils.overwrittenFunction(Wearable.setNodeWearAmount, function(vehicle, superFunc, nodeData, wearAmount, force, ...)
        local r = superFunc(vehicle, nodeData, wearAmount, force, ...)
        local st = AS_TireLife.active and AS_TireLife.vehicles[vehicle] or nil
        if st ~= nil and type(nodeData) == "table" and type(nodeData.nodes) == "table"
            and (force or nodeData.wearAmountSent == nodeData.wearAmount) then
            pcall(AS_TireLife.reapplyScratches, AS_TireLife, vehicle, nodeData)
        end
        return r
    end)
end

function AS_TireLife:reapplyScratches(vehicle, nodeData)
    local tires = nodeData.__asTires
    if tires == nil then
        -- formes de gomme de ce groupe d'usure, et leur roue
        local byNode = {}
        for _, wheel in ipairs(getWheels(vehicle) or {}) do
            for _, s in ipairs(tireShapes(wheel)) do
                if not s.mud then byNode[s.node] = wheel end
            end
        end
        tires = {}
        for _, node in pairs(nodeData.nodes) do
            if byNode[node] ~= nil then tires[#tires + 1] = { node = node, wheel = byNode[node] } end
        end
        nodeData.__asTires = tires
    end
    if #tires == 0 or not self.ENABLED then return end
    for _, t in ipairs(tires) do
        setShaderParameter(t.node, SHADER_WEAR, scratchOf(nodeData.wearAmount, t.wheel.__asWear), nil, nil, nil, false)
    end
end

-------------------------------------------------------------------------------
-- Calcul
-------------------------------------------------------------------------------
local function isPlayerFarm(vehicle)
    if g_currentMission == nil or vehicle.getOwnerFarmId == nil then return false end
    local ok, farmId = pcall(vehicle.getOwnerFarmId, vehicle)
    local mine = g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    return ok and farmId ~= nil and farmId == mine
end

function AS_TireLife:checkAlerts(vehicle, st, wheels)
    local maxW = 0
    for _, wheel in ipairs(wheels) do maxW = math.max(maxW, wheel.__asWear or 0) end
    for k, a in ipairs(self.ALERTS) do
        if maxW >= a and not st.alerted[k] then
            st.alerted[k] = true
            if isPlayerFarm(vehicle) then
                local key = k == #self.ALERTS and "vtpas_tl_alertCritical" or "vtpas_tl_alertWorn"
                local fallback = k == #self.ALERTS and "%s : pneus à remplacer (%d %%)" or "%s : pneus usés (%d %%)"
                local msg = string.format(text(key, fallback), tostring(vehicle:getName()), math.floor(maxW * 100))
                local nt = FSBaseMission ~= nil and (k == #self.ALERTS and FSBaseMission.INGAME_NOTIFICATION_CRITICAL
                    or FSBaseMission.INGAME_NOTIFICATION_INFO) or nil
                pcall(showTimedNotification, "alert", nt, msg)
            end
            sprint("%s : usure %d %%", tostring(vehicle:getName()), math.floor(maxW * 100))
        end
    end
end

function AS_TireLife:updateVehicle(vehicle, dtS)
    local st = self:getState(vehicle)
    if st == nil then return end
    self:checkConfig(vehicle, st)
    if st.tracksWaiting then pcall(self.applyTracks, self, vehicle) end
    pcall(self.syncTtd, self, vehicle, getWheels(vehicle))
    local moved = st.dist
    st.dist = 0
    if not vehicle.isAddedToPhysics then return end
    local wheels = getWheels(vehicle)
    local vehSpeed = math.abs(vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0) / 3.6
    if moved <= 0.001 and vehSpeed < 0.05 then
        -- à l'arrêt : seule une roue qui patine sur place s'use
        local spinning = false
        for _, wheel in ipairs(wheels) do
            local wp = wheel.physics
            if wp ~= nil and wp.wheelShape ~= nil and wp.wheelShape ~= 0 then
                local ok, s = pcall(getWheelShapeAxleSpeed, wheel.node or wp.node, wp.wheelShape)
                if ok and type(s) == "number" and math.abs(s) * (wp.radius or 0.5) > 0.5 then spinning = true break end
            end
        end
        if not spinning then return end
    end
    for i, wheel in ipairs(wheels) do
        wheel.__asIndex = i
        local ok, dw = pcall(self.wheelWear, self, vehicle, wheel, dtS, moved, vehSpeed)
        if ok and type(dw) == "number" and dw > 0 then
            wheel.__asWear = math.min(1, (wheel.__asWear or 0) + dw)
            -- adhérence à recalculer quand elle change d'un cran
            local wp = wheel.physics
            local g = math.floor(wheel.__asWear * 100)
            if wp ~= nil and wheel.__asGripStep ~= g then
                wheel.__asGripStep = g
                wp.isFrictionDirty = true
                self:applyVisual(vehicle, wheel)
            end
            self:updateRadius(wheel)
        elseif not ok and not self.loggedError then
            self.loggedError = true
            sprint("ERREUR calcul : %s", tostring(dw))
        end
    end
    self:checkAlerts(vehicle, st, wheels)
    pcall(self.rollTrackCut, self, vehicle, st, wheels, moved, vehSpeed)
end

function AS_TireLife:update(dt)
    if not self.active or not self.ENABLED or g_currentMission == nil or g_server == nil then return end
    local vehicles = getVehicles()
    -- distance parcourue à chaque image
    for _, vehicle in pairs(vehicles) do
        if vehicle.spec_wheels ~= nil then
            local st = self.vehicles[vehicle] or self:getState(vehicle)
            if st ~= nil then st.dist = st.dist + math.abs(vehicle.lastMovedDistance or 0) end
        end
    end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.UPDATE_MS then return end
    local dtS = self.timer / 1000
    self.timer = 0
    self:readWeather()
    for _, vehicle in pairs(vehicles) do
        if self.vehicles[vehicle] ~= nil then
            local ok, err = pcall(self.updateVehicle, self, vehicle, dtS)
            if not ok and not self.loggedError then
                self.loggedError = true
                sprint("ERREUR : %s", tostring(err))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Usure par coin (HUD) et texte (boîte d'info)
-------------------------------------------------------------------------------
-- { fl, fr, rl, rr } : usure la plus forte du coin ; nil si pas de roue
function AS_TireLife:getCornerWear(vehicle)
    local wheels = getWheels(vehicle)
    if wheels == nil or vehicle.rootNode == nil or self.vehicles[vehicle] == nil then return nil end
    local pos, minZ, maxZ = {}, math.huge, -math.huge
    for i, wheel in ipairs(wheels) do
        local n = wheel.repr or wheel.driveNode or wheel.node
        if n ~= nil and n ~= 0 then
            local ok, x, _, z = pcall(localToLocal, n, vehicle.rootNode, 0, 0, 0)
            if ok and type(z) == "number" then
                pos[i] = { x = x, z = z }
                minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
            end
        end
    end
    if minZ == math.huge then return nil end
    local midZ = (minZ + maxZ) * 0.5
    local single = maxZ - minZ < 0.5     -- un seul essieu (remorque) : roues comptées à l'arrière
    local res = {}
    for i, wheel in ipairs(wheels) do
        local p = pos[i]
        if p ~= nil then
            local key = ((not single and p.z >= midZ) and "f" or "r") .. (p.x >= 0 and "l" or "r")
            local w = wheel.__asWear or 0
            if res[key] == nil or w > res[key] then res[key] = w end
            if wheel.__asCut then res[key .. "Cut"] = true end
        end
    end
    return res
end

local function wearColor(w)
    if w >= 0.90 then return 1.00, 0.25, 0.20 end
    if w >= 0.75 then return 1.00, 0.55, 0.15 end
    if w >= 0.50 then return 1.00, 0.85, 0.30 end
    return 0.45, 0.90, 0.35
end

-- barres d'usure de chaque coin, de part et d'autre du tracteur du HUD (SpeedHint.lua)
-- axles = { { y = centre de l'essieu avant }, { y = arrière } } ; reste du pneu en couleur
function AS_TireLife:drawIconWear(vehicle, iconX, iconW, iconH, axleY, pxw, py, labelW, pctSize)
    if not self.active or not self.ENABLED or drawFilledRect == nil then return end
    local now = g_time or 0
    local c = self.hudCache
    if c == nil or c.vehicle ~= vehicle or now - c.t > 1000 or now < c.t then
        local ok, cw = pcall(self.getCornerWear, self, vehicle)
        c = { vehicle = vehicle, t = now, wear = ok and cw or nil }
        self.hudCache = c
    end
    local cw = c.wear
    if cw == nil then return end
    local bw, bh = pxw(4), iconH * 0.22
    local corners = { { "fl", axleY[1], -1 }, { "fr", axleY[1], 1 }, { "rl", axleY[2], -1 }, { "rr", axleY[2], 1 } }
    for _, k in ipairs(corners) do
        local w = cw[k[1]]
        if w ~= nil then
            local x = k[3] < 0 and (iconX - bw - pxw(1)) or (iconX + iconW + pxw(1))
            local y0 = k[2] - bh * 0.5
            drawFilledRect(x, y0, bw, bh, 0, 0, 0, 0.7)
            local left = shClamp(1 - w, 0, 1)
            local r, g, b = wearColor(w)
            if left > 0 then drawFilledRect(x, y0, bw, bh * left, r, g, b, 1) end
            -- pourcentage d'usure du pneu à côté de sa barre (« ! » rouge : chenille entaillée)
            -- sous le patinage de la roue, au milieu de la colonne de chiffres
            if renderText ~= nil and setTextAlignment ~= nil and RenderText ~= nil and labelW ~= nil then
                local size = (pctSize or iconH * 0.12) * 0.85
                local cut = cw[k[1] .. "Cut"] == true
                local label = string.format("%d%%", math.floor(w * 100 + 0.5)) .. (cut and " !" or "")
                if cut then r, g, b = 1, 0.2, 0.2 end
                setTextBold(true)
                setTextColor(r, g, b, 1)
                setTextAlignment(RenderText.ALIGN_CENTER)
                local tx = k[3] < 0 and (iconX - labelW * 0.5) or (iconX + iconW + labelW * 0.5)
                renderText(tx, k[2] - (pctSize or size) * 1.45, size, label)
                setTextAlignment(RenderText.ALIGN_LEFT)
                setTextColor(1, 1, 1, 1)
                setTextBold(false)
            end
        end
    end
end

-- outils et remorques attelés derrière (chaîne : remorque puis seconde remorque), avec roues
local function rearTools(vehicle, list, depth)
    if depth > 3 or vehicle.getAttachedImplements == nil or vehicle.rootNode == nil then return list end
    for _, impl in ipairs(vehicle:getAttachedImplements() or {}) do
        local obj = impl.object
        if obj ~= nil and obj.rootNode ~= nil then
            local ok, _, _, z = pcall(localToLocal, obj.rootNode, vehicle.rootNode, 0, 0, 0)
            if ok and type(z) == "number" and z < 0 then
                local wheels = getWheels(obj)
                if wheels ~= nil and #wheels > 0 then list[#list + 1] = obj end
                rearTools(obj, list, depth + 1)
            end
        end
    end
    return list
end

-- roue avec un vrai pneu : les rouleaux (Katrina F5...) sont des roues physiques sans pneu
local function hasTire(wheel)
    for _, vw in ipairs(wheel.visualWheels or {}) do
        for _, part in ipairs(vw.visualParts or {}) do
            if type(part.tireNodes) == "table" and #part.tireNodes > 0 then return true end
        end
    end
    return false
end

-- essieux d'un outil, de l'avant vers l'arrière : { l = usure, r = usure, lCut, rCut }
local function toolAxles(obj)
    local pts = {}
    for _, wheel in ipairs(getWheels(obj) or {}) do
        local n = wheel.repr or wheel.driveNode or wheel.node
        if n ~= nil and n ~= 0 and hasTire(wheel) then
            local ok, x, _, z = pcall(localToLocal, n, obj.rootNode, 0, 0, 0)
            if ok and type(z) == "number" then pts[#pts + 1] = { x = x, z = z, w = wheel.__asWear or 0, cut = wheel.__asCut } end
        end
    end
    table.sort(pts, function(a, b) return a.z > b.z end)
    local axles = {}
    for _, p in ipairs(pts) do
        local a = axles[#axles]
        if a == nil or a.z - p.z > 0.4 then
            a = { z = p.z }
            axles[#axles + 1] = a
        end
        local side = p.x >= 0 and "l" or "r"
        if a[side] == nil or p.w > a[side] then a[side] = p.w end
        if p.cut then a[side .. "Cut"] = true end
    end
    while #axles > 8 do table.remove(axles) end
    return axles
end

-- icônes des pneus des outils arrière, sous le bloc du tracteur (SpeedHint.lua) : le
-- tracteur monte de rearToolsHeight quand un outil est attelé, redescend quand il part
local TOOL_ROW, TOOL_PAD, TOOL_BAR, TOOL_GAP = 16, 5, 9, 4
-- images de Fabien pour 1 à 4 essieux (hud/as_toolN.dds, 256 x 512, dessin en haut sur h px) ;
-- ax : milieu de chaque essieu, de l'avant vers l'arrière, en part de h. Au-delà : dessin.
local TOOL_IMG_W = 54
local TOOL_IMAGES = {
    { h = 369, ax = { 0.78 } },
    { h = 369, ax = { 0.52, 0.78 } },
    { h = 382, ax = { 0.38, 0.59, 0.81 } },
    { h = 386, ax = { 0.35, 0.52, 0.69, 0.86 } },
}

local function toolImageH(n) return TOOL_IMG_W * TOOL_IMAGES[n].h / 256 end

function AS_TireLife:getToolOverlay(n)
    if TOOL_IMAGES[n] == nil or createImageOverlay == nil then return nil end
    self.toolOverlays = self.toolOverlays or {}
    local ov = self.toolOverlays[n]
    if ov == nil then
        local path = Utils.getFilename(string.format("hud/as_tool%d.dds", n), AS_MOD_DIR)
        local ok, o = pcall(createImageOverlay, path)
        ov = (ok and o ~= nil and o ~= 0) and o or false
        if not ov then sprint("icône d'outil introuvable : %s", tostring(path)) end
        self.toolOverlays[n] = ov
    end
    return ov or nil
end

local function toolBlockH(axles, py)
    if TOOL_IMAGES[#axles] ~= nil then return py(toolImageH(#axles) + TOOL_PAD * 2) end
    return py(TOOL_BAR) + py(TOOL_PAD) * 2 + py(TOOL_ROW) * #axles
end

function AS_TireLife:rearToolsList(vehicle)
    if not self.active or not self.ENABLED or drawFilledRect == nil or renderText == nil then return {} end
    local now = g_time or 0
    local c = self.toolCache
    if c == nil or c.vehicle ~= vehicle or now - c.t > 1000 or now < c.t then
        local tools = {}
        local ok = pcall(rearTools, vehicle, tools, 0)
        local list = {}
        if ok then
            for _, obj in ipairs(tools) do
                if self.vehicles[obj] ~= nil then
                    local okA, axles = pcall(toolAxles, obj)
                    if okA and #axles > 0 then list[#list + 1] = axles end
                end
            end
        end
        c = { vehicle = vehicle, t = now, list = list }
        self.toolCache = c
    end
    return c.list
end

function AS_TireLife:rearToolsHeight(vehicle, py)
    local h = 0
    for _, axles in ipairs(self:rearToolsList(vehicle)) do
        h = h + toolBlockH(axles, py) + py(TOOL_GAP)
    end
    return h
end

-- outil de 1 à 4 essieux : image de Fabien, barre d'usure contre chaque pneu, % sur les côtés
function AS_TireLife:drawToolImage(ov, axles, iconX, iconW, bx, labelW, topY, pxw, py, size)
    local img = TOOL_IMAGES[#axles]
    local w, imgH = pxw(TOOL_IMG_W), py(toolImageH(#axles))
    local x = iconX + (iconW - w) * 0.5
    setOverlayColor(ov, 1, 1, 1, 1)
    renderOverlay(ov, x, topY - py(TOOL_IMG_W * 2), w, py(TOOL_IMG_W * 2))
    local bw, bh = pxw(4), imgH * math.min(0.22, 0.7 / #axles)
    for i, a in ipairs(axles) do
        local cy = topY - imgH * img.ax[i]
        for _, side in ipairs({ "l", "r" }) do
            local wr = a[side]
            if wr ~= nil then
                local bxx = side == "l" and (x - bw - pxw(1)) or (x + w + pxw(1))
                drawFilledRect(bxx, cy - bh * 0.5, bw, bh, 0, 0, 0, 0.8)
                local r, g, b = wearColor(wr)
                local left = shClamp(1 - wr, 0, 1)
                if left > 0 then drawFilledRect(bxx, cy - bh * 0.5, bw, bh * left, r, g, b, 1) end
                local cut = a[side .. "Cut"] == true
                if cut then r, g, b = 1, 0.2, 0.2 end
                setTextBold(true)
                setTextColor(r, g, b, 1)
                setTextAlignment(RenderText.ALIGN_CENTER)
                local tx = side == "l" and (bx + labelW * 0.5) or (iconX + iconW + labelW * 0.5)
                renderText(tx, cy - size * 0.35, size, string.format("%d%%", math.floor(wr * 100 + 0.5)) .. (cut and " !" or ""))
            end
        end
    end
end

-- bottomY : bas de la place réservée (rearToolsHeight) ; l'outil le plus proche en haut
function AS_TireLife:drawRearTools(vehicle, bx, bottomY, blockW, labelW, iconW, pxw, py, pctSize)
    local c = { list = self:rearToolsList(vehicle) }
    if #c.list == 0 then return 0 end
    local rowH, pad, bar, gap = py(TOOL_ROW), py(TOOL_PAD), py(TOOL_BAR), py(TOOL_GAP)
    local iconX = bx + labelW
    local bodyW = iconW * 0.46
    local bodyX = iconX + (iconW - bodyW) * 0.5
    local wheelW, size = pxw(7), (pctSize or py(11)) * 0.85
    local y = bottomY + self:rearToolsHeight(vehicle, py)
    for _, axles in ipairs(c.list) do
        local h = toolBlockH(axles, py)
        y = y - gap - h
        drawFilledRect(bx, y, blockW, h, 0, 0, 0, 0.35)
        local ov = self:getToolOverlay(#axles)
        if ov ~= nil then
            self:drawToolImage(ov, axles, iconX, iconW, bx, labelW, y + h - pad, pxw, py, size)
        else
        local bodyH = h - bar - pad
        -- caisse de l'outil, avant en haut comme le tracteur, flèche d'attelage au-dessus
        drawFilledRect(bodyX, y + pad, bodyW, bodyH - pad, 0.55, 0.55, 0.55, 0.95)
        drawFilledRect(iconX + iconW * 0.5 - pxw(1.5), y + bodyH, pxw(3), bar + pad - py(1), 0.55, 0.55, 0.55, 0.95)
        -- essieux : avant en haut, arrière en bas
        for i, a in ipairs(axles) do
            local cy = y + pad + rowH * (#axles - i + 0.5)
            for _, side in ipairs({ "l", "r" }) do
                local w = a[side]
                if w ~= nil then
                    local wx = side == "l" and (bodyX - wheelW - pxw(1)) or (bodyX + bodyW + pxw(1))
                    local wh = rowH * 0.8
                    drawFilledRect(wx, cy - wh * 0.5, wheelW, wh, 0, 0, 0, 0.8)
                    local r, g, b = wearColor(w)
                    local left = shClamp(1 - w, 0, 1)
                    if left > 0 then drawFilledRect(wx, cy - wh * 0.5, wheelW, wh * left, r, g, b, 1) end
                    local cut = a[side .. "Cut"] == true
                    if cut then r, g, b = 1, 0.2, 0.2 end
                    setTextBold(true)
                    setTextColor(r, g, b, 1)
                    setTextAlignment(RenderText.ALIGN_CENTER)
                    local tx = side == "l" and (bx + labelW * 0.5) or (iconX + iconW + labelW * 0.5)
                    renderText(tx, cy - size * 0.35, size, string.format("%d%%", math.floor(w * 100 + 0.5)) .. (cut and " !" or ""))
                end
            end
        end
        end
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
end

-- texte « AV 12 % · AR 20 % » (ou « 20 % » pour un seul essieu)
function AS_TireLife:getWearText(vehicle)
    local cw = self:getCornerWear(vehicle)
    if cw == nil then return nil end
    local front = math.max(cw.fl or -1, cw.fr or -1)
    local rear = math.max(cw.rl or -1, cw.rr or -1)
    if front < 0 and rear < 0 then return nil end
    if front < 0 or rear < 0 then
        return string.format("%d %%", math.floor(math.max(front, rear) * 100 + 0.5))
    end
    return string.format("%s %d %% · %s %d %%", text("vtpas_tl_front", "AV"), math.floor(front * 100 + 0.5),
        text("vtpas_tl_rear", "AR"), math.floor(rear * 100 + 0.5))
end

-------------------------------------------------------------------------------
-- Atelier : pneus neufs
-------------------------------------------------------------------------------
local function tirePrice(wheel)
    local d, w = wheelDims(wheel)
    local p = AS_TireLife.PRICE_K * (d ^ 1.5) * w
    if isTrack(wheel) then p = p * 3 end
    return p
end

-- roues à remplacer (usées à 25 % ou plus ; sinon toutes celles qui ont roulé) et prix
function AS_TireLife:getReplacePlan(vehicle)
    local wheels = getWheels(vehicle)
    if wheels == nil or self.vehicles[vehicle] == nil then return nil end
    local list, price = {}, 0
    for i, wheel in ipairs(wheels) do
        if (wheel.__asWear or 0) >= self.REPLACE_FROM or wheel.__asCut then
            list[#list + 1] = i
            price = price + tirePrice(wheel)
        end
    end
    if #list == 0 then
        for i, wheel in ipairs(wheels) do
            if (wheel.__asWear or 0) > 0.01 then
                list[#list + 1] = i
                price = price + tirePrice(wheel)
            end
        end
    end
    if #list == 0 then return nil end
    return { wheels = list, price = math.floor(price + 0.5) }
end

function AS_TireLife:replaceTires(vehicle)
    local plan = self:getReplacePlan(vehicle)
    if plan == nil or g_currentMission == nil then return false end
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    if farmId ~= nil and g_currentMission.getMoney ~= nil then
        local ok, money = pcall(g_currentMission.getMoney, g_currentMission, farmId)
        if ok and type(money) == "number" and money < plan.price then
            if InfoDialog ~= nil and InfoDialog.show ~= nil then
                InfoDialog.show(text("shop_messageNotEnoughMoneyToBuy", "Pas assez d'argent"))
            end
            return false
        end
    end
    local wheels = getWheels(vehicle)
    for _, i in ipairs(plan.wheels) do
        local wheel = wheels[i]
        if wheel ~= nil then
            wheel.__asWear = 0
            wheel.__asCut = nil
            wheel.__asGripStep = nil
            if wheel.physics ~= nil then wheel.physics.isFrictionDirty = true end
        end
    end
    local st = self.vehicles[vehicle]
    if st ~= nil then st.alerted = {} end
    pcall(self.applyVisualAll, self, vehicle)
    for _, i in ipairs(plan.wheels) do
        if wheels[i] ~= nil then self:updateRadius(wheels[i]) end
    end
    pcall(self.clearPunctures, self, vehicle, plan.wheels)
    if farmId ~= nil and g_currentMission.addMoney ~= nil and MoneyType ~= nil then
        local mt = MoneyType.VEHICLE_REPAIR or MoneyType.OTHER
        pcall(g_currentMission.addMoney, g_currentMission, -plan.price, farmId, mt, true, true)
    end
    sprint("%s : %d pneus neufs, %d", tostring(vehicle:getName()), #plan.wheels, plan.price)
    return true
end

function AS_TireLife:buttonText(vehicle)
    local plan = vehicle ~= nil and self:getReplacePlan(vehicle) or nil
    local label = text("vtpas_tl_replace", "Pneus neufs")
    if plan == nil then return label, true end
    local money = g_i18n ~= nil and g_i18n.formatMoney ~= nil and g_i18n:formatMoney(plan.price, 0, true, true) or tostring(plan.price)
    return string.format("%s (%d : %s)", label, #plan.wheels, money), false
end

function AS_TireLife:refreshButton(screen)
    local btn = screen.__asTireButton
    if btn == nil then return end
    local vehicle = screen.vehicle
    local show = self.active and self.ENABLED and vehicle ~= nil and self.vehicles[vehicle] ~= nil
    btn:setVisible(show)
    if show then
        local label, disabled = self:buttonText(vehicle)
        btn:setText(label)
        btn:setDisabled(disabled)
    end
    if screen.buttonsBox ~= nil and screen.buttonsBox.invalidateLayout ~= nil then
        pcall(screen.buttonsBox.invalidateLayout, screen.buttonsBox)
    end
end

function AS_TireLife:onReplaceClick(screen)
    local vehicle = screen.vehicle
    local plan = vehicle ~= nil and self:getReplacePlan(vehicle) or nil
    if plan == nil or YesNoDialog == nil or YesNoDialog.show == nil then return end
    local money = g_i18n ~= nil and g_i18n:formatMoney(plan.price, 0, true, true) or tostring(plan.price)
    local msg = string.format(text("vtpas_tl_replaceAsk", "Monter %d pneus neufs pour %s ?"), #plan.wheels, money)
    -- avec une cible, le jeu rappelle callback(cible, oui)
    YesNoDialog.show(function(self, yes)
        if yes then
            self:replaceTires(vehicle)
            self:refreshButton(screen)
        end
    end, self, msg)
end

-- bouton ajouté dans la barre de boutons de l'atelier, à partir d'un bouton du jeu
function AS_TireLife:addButton(screen)
    if screen.__asTireButton ~= nil or screen.buttonsBox == nil then return end
    local template
    for _, el in ipairs(screen.buttonsBox.elements or {}) do
        if ButtonElement ~= nil and el.isa ~= nil and el:isa(ButtonElement) then template = el break end
    end
    if template == nil then return end
    local btn = template:clone(screen.buttonsBox)
    btn.inputActionName = nil
    btn.onClickCallback = function() AS_TireLife:onReplaceClick(screen) end
    screen.__asTireButton = btn
    sprint("bouton Pneus neufs ajouté à l'atelier")
end

function AS_TireLife:installWorkshop()
    if WorkshopScreen == nil or WorkshopScreen.setVehicle == nil then
        sprint("atelier introuvable : pas de bouton Pneus neufs")
        return
    end
    WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, function(screen, vehicle)
        if not AS_TireLife.active then return end
        local ok, err = pcall(function()
            AS_TireLife:addButton(screen)
            AS_TireLife:refreshButton(screen)
        end)
        if not ok and not AS_TireLife.loggedWorkshop then
            AS_TireLife.loggedWorkshop = true
            sprint("ERREUR atelier : %s", tostring(err))
        end
    end)
end

-------------------------------------------------------------------------------
-- Boîte d'info du véhicule (regard sur le véhicule)
-------------------------------------------------------------------------------
if Vehicle ~= nil and Vehicle.showInfo ~= nil then
    Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, function(vehicle, box)
        if not AS_TireLife.active or not AS_TireLife.ENABLED or box == nil or box.addLine == nil then return end
        if AS_TireLife.vehicles[vehicle] == nil then return end
        local ok, t = pcall(AS_TireLife.getWearText, AS_TireLife, vehicle)
        if ok and t ~= nil then box:addLine(text("vtpas_tl_info", "Usure des pneus"), t) end
    end)
end

-------------------------------------------------------------------------------
-- Sauvegarde
-------------------------------------------------------------------------------
local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_TireLife.FILE_NAME
end

local function joinWears(list)
    local t = {}
    for i, w in ipairs(list or {}) do t[i] = string.format("%.5f", w) end
    return table.concat(t, " ")
end

local function splitWears(s)
    local t = {}
    for v in tostring(s or ""):gmatch("[%d%.]+") do t[#t + 1] = tonumber(v) or 0 end
    return t
end

-- véhicule supprimé (réinitialisation, changement de configuration) : son usure est
-- gardée pour le véhicule rechargé sous le même identifiant
if Vehicle ~= nil and Vehicle.delete ~= nil then
    Vehicle.delete = Utils.prependedFunction(Vehicle.delete, function(vehicle)
        local st = AS_TireLife.vehicles[vehicle]
        if st == nil then return end
        local wheels = getWheels(vehicle)
        if wheels ~= nil then st.sets[st.cfg] = readWears(wheels) end
        if vehicle.uniqueId ~= nil then
            AS_TireLife.pending[vehicle.uniqueId] = { sets = st.sets }
        end
        AS_TireLife.vehicles[vehicle] = nil
    end)
end

function AS_TireLife:save()
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asTires", path, "tires")
    if xml == nil or xml == 0 then return end
    local i, existing = 0, {}
    local function writeEntry(id, sets)
        local key = string.format("tires.vehicle(%d)", i)
        setXMLString(xml, key .. "#id", id)
        local j = 0
        for cfg, list in pairs(sets) do
            local k = string.format("%s.set(%d)", key, j)
            setXMLInt(xml, k .. "#cfg", cfg)
            setXMLString(xml, k .. "#wear", joinWears(list))
            j = j + 1
        end
        i = i + 1
    end
    for vehicle, st in pairs(self.vehicles) do
        local id = vehicle.uniqueId
        local wheels = getWheels(vehicle)
        if id ~= nil and wheels ~= nil and not vehicle.isDeleted then
            st.sets[st.cfg] = readWears(wheels)
            existing[id] = true
            writeEntry(id, st.sets)
        end
    end
    -- véhicules pas encore vus depuis le chargement (gardés s'ils existent toujours)
    local ids = {}
    for _, vehicle in pairs(getVehicles()) do
        if vehicle.uniqueId ~= nil then ids[vehicle.uniqueId] = vehicle end
    end
    for id, p in pairs(self.pending) do
        if not existing[id] and ids[id] then
            p.sets = p.sets or {}
            if p.uyt ~= nil then
                self:mergeUyt(ids[id], p.sets, wheelConfigId(ids[id]), p.uyt)
                p.uyt = nil
            end
            writeEntry(id, p.sets)
        end
    end
    if self.uytDone then setXMLBool(xml, "tires#uytImported", true) end
    saveXMLFile(xml)
    delete(xml)
    sprint("%d véhicules sauvegardés", i)
end

function AS_TireLife:load()
    self.pending = {}
    self.uytDone = false
    local path = savegamePath()
    if path ~= nil and fileExists(path) then self:loadOwn(path) end
    if not self.uytDone then
        local ok, err = pcall(self.importUyt, self)
        if not ok then sprint("ERREUR reprise de Use Your Tyres : %s", tostring(err)) end
    end
end

-- reprise de l'usure de Use Your Tyres, une seule fois par partie (tires#uytImported) :
-- il enregistre dans vehicles.xml la distance roulée par chaque roue de chaque jeu de roues
-- (vehicle.configuration#id = saveId du jeu, .wheels.wheel#uytTravelledDist en m) et
-- affiche usure = distance / (240 km x vehicles#uytDistanceMultiplier). Une partie déjà
-- sauvegardée sans lui n'a plus ces distances : on les lit alors dans la copie de secours
-- la plus récente qui les a encore (savegameBackup/<partie>_backup<date>).
AS_TireLife.UYT_LIFE_M = 240000
AS_TireLife.UYT_MAX_BACKUPS = 8

-- copies de secours de la partie, de la plus récente à la plus ancienne
local function uytBackupDirs(dir)
    local parent, name = dir:match("^(.*)[/\\]([^/\\]+)[/\\]*$")
    if parent == nil then return {} end
    local root = parent .. "/savegameBackup/"
    local prefix, list = name .. "_backup", {}
    local function add(fname, isDir)
        if type(fname) == "string" and isDir ~= false and fname:sub(1, #prefix) == prefix
            and fname:sub(#prefix + 1):match("^%d") then
            list[#list + 1] = fname
        end
    end
    if Files ~= nil and Files.new ~= nil then
        local f = Files.new(root)
        for _, e in pairs(f ~= nil and f.files or {}) do add(e.filename, e.isDirectory) end
    elseif getFiles ~= nil then
        local cb = { found = function(_, fname, isDir) add(fname, isDir) end }
        getFiles(root, "found", cb)
    end
    table.sort(list, function(x, y) return x > y end)
    for k, v in ipairs(list) do list[k] = root .. v end
    return list
end

-- distances d'un vehicles.xml -> { [uniqueId] = { cfgs = { [saveId] = usures }, active = saveId } }
function AS_TireLife:readUyt(path)
    if not fileExists(path) then return nil, 0, 0 end
    local xml = loadXMLFile("asUytVehicles", path)
    if xml == nil or xml == 0 then return nil, 0, 0 end
    local life = self.UYT_LIFE_M * math.max(getXMLFloat(xml, "vehicles#uytDistanceMultiplier") or 1, 0.01)
    local out, i, n, worn = {}, 0, 0, 0
    while true do
        local key = string.format("vehicles.vehicle(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local id = getXMLString(xml, key .. "#uniqueId")
        if id ~= nil then
            local u, top, j = nil, 0, 0
            while true do
                local ck = string.format("%s.configuration(%d)", key, j)
                local name = getXMLString(xml, ck .. "#name")
                if name == nil then break end
                if name == "wheel" and getXMLFloat(xml, ck .. ".wheels.wheel(0)#uytTravelledDist") ~= nil then
                    local saveId = getXMLString(xml, ck .. "#id") or tostring(j)
                    local list, k = {}, 0
                    while true do
                        local d = getXMLFloat(xml, string.format("%s.wheels.wheel(%d)#uytTravelledDist", ck, k))
                        if d == nil then break end
                        k = k + 1
                        list[k] = shClamp(d / life, 0, 1)
                        top = math.max(top, list[k])
                    end
                    u = u or { cfgs = {} }
                    u.cfgs[saveId] = list
                    if getXMLBool(xml, ck .. "#isActive") == true or u.active == nil then u.active = saveId end
                end
                j = j + 1
            end
            if u ~= nil then
                out[id] = u
                n = n + 1
                if top > 0 then worn = worn + 1 end
                if self.DEBUG_SHAVE and top > 0 then
                    local t = {}
                    for k, v in ipairs(u.cfgs[u.active]) do t[k] = string.format("%.0f%%", v * 100) end
                    sprint("reprise Use Your Tyres %s (%s) : %s", id, u.active, table.concat(t, " "))
                end
            end
        end
        i = i + 1
    end
    delete(xml)
    return out, n, worn
end

function AS_TireLife:importUyt()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return end
    local sources = { dir .. "/vehicles.xml" }
    local backups = uytBackupDirs(dir)
    for k = 1, math.min(#backups, self.UYT_MAX_BACKUPS) do sources[#sources + 1] = backups[k] .. "/vehicles.xml" end
    for _, path in ipairs(sources) do
        local data, n, worn = self:readUyt(path)
        if data ~= nil and n > 0 then
            for id, u in pairs(data) do
                self.pending[id] = self.pending[id] or { sets = {} }
                self.pending[id].uyt = u
            end
            self.uytDone = true
            sprint("usure reprise de Use Your Tyres : %d véhicules (%d usés), depuis %s", n, worn, path)
            return
        end
    end
    -- rien trouvé alors que les copies de secours sont lisibles : jamais de Use Your Tyres
    if #backups > 0 then self.uytDone = true end
end

-- index du jeu de roues dont le saveId est donné (nil si inconnu)
local function wheelIndexBySaveId(vehicle, saveId)
    if g_storeManager == nil or vehicle.configFileName == nil then return nil end
    local ok, item = pcall(g_storeManager.getItemByXMLFilename, g_storeManager, vehicle.configFileName)
    local items = ok and item ~= nil and item.configurations ~= nil and item.configurations.wheel or nil
    if items == nil then return nil end
    for i, c in ipairs(items) do
        if c.saveId == saveId then return i end
    end
    return nil
end

-- usures Use Your Tyres dans nos jeux de roues (la plus forte des deux, roue par roue)
function AS_TireLife:mergeUyt(vehicle, sets, cfg, u)
    for saveId, list in pairs(u.cfgs) do
        local idx = wheelIndexBySaveId(vehicle, saveId)
        if idx == nil and saveId == u.active then idx = cfg end
        if idx ~= nil then
            local cur = sets[idx] or {}
            for k, v in ipairs(list) do cur[k] = math.max(cur[k] or 0, v) end
            sets[idx] = cur
        end
    end
end

function AS_TireLife:loadOwn(path)
    local xml = loadXMLFile("asTires", path)
    if xml == nil or xml == 0 then return end
    local i, n = 0, 0
    while true do
        local key = string.format("tires.vehicle(%d)", i)
        local id = getXMLString(xml, key .. "#id")
        if id == nil then break end
        local sets, j = {}, 0
        while true do
            local k = string.format("%s.set(%d)", key, j)
            local cfg = getXMLInt(xml, k .. "#cfg")
            if cfg == nil then break end
            sets[cfg] = splitWears(getXMLString(xml, k .. "#wear"))
            j = j + 1
        end
        self.pending[id] = { sets = sets }
        n = n + 1
        i = i + 1
    end
    self.uytDone = getXMLBool(xml, "tires#uytImported") == true
    delete(xml)
    sprint("%d véhicules chargés", n)
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        if not AS_TireLife.active then return end
        local ok, err = pcall(AS_TireLife.save, AS_TireLife)
        if not ok then print("[AS_TireLife] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

-------------------------------------------------------------------------------
-- Démarrage
-------------------------------------------------------------------------------
-- Use Your Tyres activé : il garde l'usure, ce module ne fait rien
function AS_TireLife:isUytActive()
    return g_modIsLoaded ~= nil and g_modIsLoaded["FS25_useYourTyres"] == true
end

-- (réglage) marche / arrêt : en arrêt, adhérence et rayon reviennent à la normale
function AS_TireLife:setEnabled(on)
    on = on == true
    if self.ENABLED == on then return end
    self.ENABLED = on
    if not self.active then return end
    for vehicle, _ in pairs(self.vehicles) do
        local wheels = getWheels(vehicle)
        pcall(self.syncTtd, self, vehicle, wheels)
        pcall(self.applyVisualAll, self, vehicle)
        for _, wheel in ipairs(wheels or {}) do
            if on then self:updateRadius(wheel) else self:clearRadius(wheel) end
            if wheel.physics ~= nil then wheel.physics.isFrictionDirty = true end
        end
    end
end

-- console : asTiresWear [pourcentage]  -> usure du véhicule conduit (essais)
-- le véhicule conduit et tout ce qui y est attelé (outils, remorques)
local function vehicleTree(vehicle, list, depth)
    list[#list + 1] = vehicle
    if depth < 6 and vehicle.getAttachedImplements ~= nil then
        for _, impl in ipairs(vehicle:getAttachedImplements() or {}) do
            if impl.object ~= nil then vehicleTree(impl.object, list, depth + 1) end
        end
    end
    return list
end

function AS_TireLife:consoleWear(arg)
    local driven = shGetControlledVehicle()
    if driven == nil then return "aucun véhicule" end
    local v = tonumber(arg)
    local out = {}
    for _, vehicle in ipairs(vehicleTree(driven, {}, 0)) do
        local st = self:getState(vehicle)
        local wheels = st ~= nil and getWheels(vehicle) or nil
        if wheels ~= nil then
            if arg == "cut" then
                local groups = AS_TireLife.crawlerGroups(vehicle, wheels)
                if #groups > 0 then self:cutTrack(vehicle, groups[1]) end
            end
            if v ~= nil then
                for _, wheel in ipairs(wheels) do
                    wheel.__asWear = shClamp(v / 100, 0, 1)
                    wheel.__asGripStep = nil
                    if wheel.physics ~= nil then wheel.physics.isFrictionDirty = true end
                end
                st.alerted = {}
                pcall(self.applyVisualAll, self, vehicle)
                for _, wheel in ipairs(wheels) do self:updateRadius(wheel) end
            end
            local parts = {}
            for i, wheel in ipairs(wheels) do
                parts[#parts + 1] = string.format("r%d %.1f %%%s", i, (wheel.__asWear or 0) * 100, isTrack(wheel) and " (chenille)" or "")
            end
            out[#out + 1] = tostring(vehicle:getName()) .. " : " .. table.concat(parts, ", ")
        end
    end
    if #out == 0 then return "véhicule sans roues" end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Chenille caoutchouc entaillée (pierre, souche, chaume dur) : fait rare. Mud System
-- ne touche jamais aux chenilles ; même règle que ses crevaisons (risque qui monte
-- avec l'usure), mais AutoSwitch gère tout : adhérence et usure de la chenille
-- touchée, réparation par une chenille neuve à l'atelier.
-------------------------------------------------------------------------------
AS_TireLife.CUT_KM = 4000            -- en moyenne une entaille tous les 4000 km (chenille neuve, champ)
AS_TireLife.CUT_GRIP = 0.85          -- adhérence de la chenille entaillée
AS_TireLife.CUT_WEAR = 4             -- usure ×4 tant qu'elle n'est pas remplacée
AS_TireLife.CUT_SURFACE = { road = 0.3, hard = 1.2, soft = 0.8, field = 1.0 }

-- les roues d'une même chenille (spec_crawlers), sinon la roue seule
local function crawlerGroups(vehicle, wheels)
    local groups, seen = {}, {}
    local spec = vehicle.spec_crawlers
    if spec ~= nil and type(spec.crawlers) == "table" then
        for _, crawler in pairs(spec.crawlers) do
            if type(crawler) == "table" and type(crawler.wheels) == "table" then
                local g = {}
                for _, w in ipairs(crawler.wheels) do
                    local wheel = type(w) == "table" and (w.wheel or w) or nil
                    if type(wheel) == "table" and not seen[wheel] then seen[wheel] = true g[#g + 1] = wheel end
                end
                if #g > 0 then groups[#groups + 1] = g end
            end
        end
    end
    for _, wheel in ipairs(wheels) do
        if isTrack(wheel) and not seen[wheel] then groups[#groups + 1] = { wheel } end
    end
    return groups
end

AS_TireLife.crawlerGroups = crawlerGroups

local function cutSurface(wp)
    local c = AS_TireLife.CUT_SURFACE
    local gt = wp ~= nil and groundTypeOf(wp) or nil
    if WheelsUtil == nil or gt == nil then return 1 end
    if gt == WheelsUtil.GROUND_ROAD then return c.road end
    if gt == WheelsUtil.GROUND_HARD_TERRAIN then return c.hard end
    if gt == WheelsUtil.GROUND_SOFT_TERRAIN then return c.soft end
    return c.field
end

function AS_TireLife:rollTrackCut(vehicle, st, wheels, moved, vehSpeed)
    if vehSpeed < 5 / 3.6 or moved <= 0 then return end
    st.cutDist = (st.cutDist or 0) + moved
    if st.cutDist < 100 then return end
    local dist = st.cutDist
    st.cutDist = 0
    local groups = st.cutGroups
    if groups == nil then
        groups = crawlerGroups(vehicle, wheels)
        st.cutGroups = groups
    end
    if #groups == 0 then return end
    -- sol sous la machine et usure moyenne des chenilles encore intactes
    local candidates, total = {}, 0
    for _, g in ipairs(groups) do
        if not g[1].__asCut then
            local w, sf = 0, 0
            for _, wheel in ipairs(g) do
                w = w + (wheel.__asWear or 0)
                sf = sf + cutSurface(wheel.physics)
            end
            w, sf = w / #g, sf / #g
            local risk = (1 + (self.PUNCTURE_MAX - 1) * math.max(0, (w - self.PUNCTURE_FROM) / (1 - self.PUNCTURE_FROM)) ^ 2) * sf
            candidates[#candidates + 1] = { g = g, risk = risk }
            total = total + risk
        end
    end
    if #candidates == 0 then return end
    local p = (dist / 1000) / self.CUT_KM * (total / #groups)
    if math.random() >= p then return end
    local r, pick = math.random() * total, candidates[#candidates]
    for _, c in ipairs(candidates) do
        r = r - c.risk
        if r <= 0 then pick = c break end
    end
    self:cutTrack(vehicle, pick.g)
end

function AS_TireLife:cutTrack(vehicle, group)
    for _, wheel in ipairs(group) do
        wheel.__asCut = true
        if wheel.physics ~= nil then wheel.physics.isFrictionDirty = true end
    end
    if isPlayerFarm(vehicle) then
        local msg = string.format(text("vtpas_tl_trackCut", "%s : chenille entaillée, à remplacer à l'atelier"), tostring(vehicle:getName()))
        pcall(showTimedNotification, "alert", FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or nil, msg)
    end
    sprint("%s : chenille entaillée (%d roues)", tostring(vehicle:getName()), #group)
end

-------------------------------------------------------------------------------
-- Crevaisons de Mud System Physics : un pneu usé crève plus souvent. MSP demande le
-- risque de chaque roue à PunctureSystem:getWheelPunctureRiskMultiplier (il ne
-- connaît que Use Your Tyres et Reifenverschleiß) ; on y ajoute notre usure, la plus
-- forte des deux l'emporte (jamais les deux multipliées).
-------------------------------------------------------------------------------
AS_TireLife.PUNCTURE_FROM = 0.30     -- risque normal jusqu'à 30 % d'usure
AS_TireLife.PUNCTURE_MAX = 8         -- risque ×8 sur un pneu lisse
AS_TireLife.PUNCTURE_WEAR = 8        -- usure ×8 en roulant crevé

local function punctureSystem()
    local ps = modGlobal("FS25_MudSystemPhysics", "PunctureSystem")
    if type(ps) == "table" then return ps end
    return nil
end

function AS_TireLife:isPunctured(vehicle, wheel)
    local ps = punctureSystem()
    if ps == nil or ps.isWheelPunctured == nil or wheel.__asIndex == nil then return false end
    local ok, r = pcall(ps.isWheelPunctured, ps, vehicle, wheel.__asIndex)
    return ok and r == true
end

-- pneus neufs à l'atelier : la crevaison Mud System de ces roues est réparée aussi
function AS_TireLife:clearPunctures(vehicle, indices)
    local ps = punctureSystem()
    local ev = modGlobal("FS25_MudSystemPhysics", "PunctureStateEvent")
    if ps == nil or ev == nil or ev.send == nil or ps.getWheelState == nil or g_server == nil then return end
    for _, i in ipairs(indices) do
        local ok, st = pcall(ps.getWheelState, ps, vehicle, i)
        if ok and st ~= nil then
            pcall(ev.send, vehicle, i, ps.STAGE_NONE or 0, true, 0, 0, 0, 0)
            sprint("%s : crevaison roue %d réparée (pneu neuf)", tostring(vehicle:getName()), i)
        end
    end
end

function AS_TireLife:getPunctureRisk(wheel)
    local w = wheel ~= nil and wheel.__asWear or nil
    if not (self.active and self.ENABLED) or type(w) ~= "number" or isTrack(wheel) then return 1, w end
    local t = math.max(0, (w - self.PUNCTURE_FROM) / (1 - self.PUNCTURE_FROM))
    return 1 + (self.PUNCTURE_MAX - 1) * t * t, w
end

function AS_TireLife:installPunctureRisk()
    local ps = punctureSystem()
    if ps == nil or type(ps.getWheelPunctureRiskMultiplier) ~= "function" then return end
    if ps.__asTireLifeRisk then return end
    ps.__asTireLifeRisk = true
    local owner = self
    ps.getWheelPunctureRiskMultiplier = Utils.overwrittenFunction(ps.getWheelPunctureRiskMultiplier,
        function(sys, superFunc, vehicle, wheel)
            local m, wear, provider = superFunc(sys, vehicle, wheel)
            local ok, mine, myWear = pcall(owner.getPunctureRisk, owner, wheel)
            if ok and type(mine) == "number" and mine > (tonumber(m) or 1) then
                return mine, myWear, "AutoSwitch"
            end
            return m, wear, provider
        end)
    sprint("crevaisons Mud System : risque selon l'usure (x%d sur pneu lisse)", self.PUNCTURE_MAX)
end

function AS_TireLife:loadMap()
    self:buildSurfaces()
    if self:isUytActive() then
        self.active = false
        sprint("Use Your Tyres activé : usure des pneus laissée à Use Your Tyres")
        return
    end
    self.active = true
    if not self.installed then
        self.installed = true
        if AS_WetGrip == nil or AS_WetGrip.inactive or AS_WetGrip.disabled then
            self:installOwnFriction()
        end
        self:installWorkshop()
        self:installPunctureRisk()
        if addConsoleCommand ~= nil then
            addConsoleCommand("asTiresWear", "AutoSwitch : usure des pneus du véhicule conduit [pourcentage | cut = entailler une chenille]", "consoleWear", self)
        end
    end
    local ok, err = pcall(self.load, self)
    if not ok then sprint("ERREUR chargement : %s", tostring(err)) end
    sprint("usure des pneus active (durée de vie %d km)", self.LIFE_KM)
end

function AS_TireLife:deleteMap()
    if self.holderReq ~= nil and g_i3DManager ~= nil and g_i3DManager.releaseSharedI3DFile ~= nil then
        pcall(g_i3DManager.releaseSharedI3DFile, g_i3DManager, self.holderReq)
    end
    if self.holderNode ~= nil and delete ~= nil then pcall(delete, self.holderNode) end
    self.holderNode, self.holderReq, self.holderMat, self.holderMudMat, self.holderFailed, self.wornMats = nil, nil, nil, nil, nil, nil
    self.nodeRecipe = nil
    self.vehicles = setmetatable({}, { __mode = "k" })
    self.pending = {}
    self.hudCache, self.toolCache = nil, nil
    for _, ov in pairs(self.toolOverlays or {}) do
        if ov and delete ~= nil then pcall(delete, ov) end
    end
    self.toolOverlays = nil
    self.timer = 0
end

addModEventListener(AS_TireLife)
