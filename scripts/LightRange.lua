-- AutoSwitch : phares des véhicules plus puissants
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getVehicles = AS.getVehicles

-------------------------------------------------------------------------------
-- v1.0.0.75 : vrais faisceaux (sources de lumière des phares, phares de travail,
--   gyros) : portée multipliée par BEAM_RANGE et luminosité (couleur de la
--   lumière) par BEAM_GLOW, x2 par défaut, réglables. Tous les véhicules, le
--   véhicule conduit compris. Une couleur ou une portée nouvelle posée par le
--   jeu est reprise puis multipliée.
--   Les réglages de la 1.0.0.37 / 1.0.0.38 (distance et luminosité des halos)
--   sont retirés : sans effet visible en jeu.
-- v1.0.0.83 : option « Phares renforcés » (Oui / Non). Sur Non, les faisceaux
--   reprennent les valeurs du jeu et plus rien n'est lu à chaque image.
-------------------------------------------------------------------------------
-- v1.0.1.7 : un facteur par type de feu (portée et luminosité ensemble), x1,1 à x2,5.
--   Le type vient des listes du jeu (spec_lights) :
--     road      phares de route : lumières par défaut (types 0 croisement, 3 route),
--               feux de toit / bas
--     workFront phares de travail avant (type 2, et types propres au véhicule > 3)
--     workBack  phares de travail arrière (type 1)
--     beacon    gyrophares (spec_lights.beaconLights, realLightNode)
--     signal    clignotants, stop, recul
--     other     éclairage intérieur et lumières hors des listes du jeu
-------------------------------------------------------------------------------
AS_LightRange = {}
AS_LightRange.ENABLED    = true  -- (v1.0.0.83) phares renforcés
AS_LightRange.TYPES      = { "road", "workFront", "workBack", "beacon", "signal", "other" }
AS_LightRange.FACTORS    = { road = 2, workFront = 2, workBack = 2, beacon = 1.1, signal = 1.1, other = 1.1 }
AS_LightRange.SCAN_MS = 2000     -- recherche des nouveaux véhicules
AS_LightRange.timer   = AS_LightRange.SCAN_MS
AS_LightRange.done    = {}       -- véhicule -> true quand ses lumières sont trouvées
AS_LightRange.beams   = {}       -- véhicule -> { { node, kind, range, rangeW, r, g, b, rW, gW, bW } }

AS_LightRange.TEST = false   -- version TEST : relevé des types de feux toujours écrit dans log.txt
local function log(fmt, ...)
    local line = "[AS_Lights] " .. string.format(fmt, ...)
    if AS_LightRange.TEST and AS.rawPrint ~= nil then AS.rawPrint(line) else print(line) end
end

local function walk(node, beams)
    if getHasClassId(node, ClassIds.LIGHT_SOURCE) then
        beams[#beams + 1] = { node = node, kind = "other", range = 0, rangeW = -1, r = 0, g = 0, b = 0, rW = -1, gW = -1, bW = -1 }
    end
    for i = 0, getNumOfChildren(node) - 1 do
        walk(getChildAt(node, i), beams)
    end
end

-- note le type de node et de ses lumières enfants (sans écraser un type déjà donné)
local function mark(kinds, node, kind)
    if node == nil or node == 0 or not entityExists(node) then return end
    if kinds[node] == nil then kinds[node] = kind end
    for i = 0, getNumOfChildren(node) - 1 do
        mark(kinds, getChildAt(node, i), kind)
    end
end

local function has(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

-- type d'une lumière par défaut d'après ses types de feu (0 croisement, 1 travail AR,
-- 2 travail AV, 3 route, au-delà : propres au véhicule, en pratique des phares de travail)
local function defaultKind(lightTypes)
    if has(lightTypes, 0) or has(lightTypes, 3) then return "road" end
    if has(lightTypes, 2) then return "workFront" end
    if has(lightTypes, 1) then return "workBack" end
    for _, t in ipairs(lightTypes or {}) do
        if t > 3 then return "workFront" end
    end
    return "road"
end

local LIST_KIND = { topLights = "road", bottomLights = "road", brakeLights = "signal",
    reverseLights = "signal", turnLightsLeft = "signal", turnLightsRight = "signal",
    interiorLights = "other" }

local function vehicleKinds(vehicle)
    local spec = vehicle.spec_lights
    local kinds = {}
    for _, beacon in pairs(spec.beaconLights or {}) do
        if type(beacon) == "table" then mark(kinds, beacon.realLightNode, "beacon") end
    end
    for _, profile in pairs(spec.realLights or {}) do
        for listName, lights in pairs(profile) do
            for _, light in ipairs(lights) do
                local kind = LIST_KIND[listName]
                if listName == "defaultLights" then kind = defaultKind(light.lightTypes) end
                if kind ~= nil then
                    for _, n in ipairs(light.lightSources or { light.node }) do mark(kinds, n, kind) end
                end
            end
        end
    end
    return kinds
end

function AS_LightRange:processVehicle(vehicle)
    if vehicle.spec_lights == nil or vehicle.components == nil then return end
    local beams = {}
    for _, comp in ipairs(vehicle.components) do
        if comp.node ~= nil and comp.node ~= 0 then
            walk(comp.node, beams)
        end
    end
    local ok, kinds = pcall(vehicleKinds, vehicle)
    if not ok then
        log("ERREUR types de feux de %s : %s", tostring(vehicle.getName and vehicle:getName()), tostring(kinds))
        kinds = {}
    end
    -- gyrophares hors des composants (lumière chargée à part) : ajoutés aussi
    local seen = {}
    for _, l in ipairs(beams) do seen[l.node] = true end
    for node, kind in pairs(kinds) do
        if not seen[node] and entityExists(node) and getHasClassId(node, ClassIds.LIGHT_SOURCE) then
            beams[#beams + 1] = { node = node, kind = kind, range = 0, rangeW = -1, r = 0, g = 0, b = 0, rW = -1, gW = -1, bW = -1 }
        end
    end
    local count = {}
    for _, l in ipairs(beams) do
        l.kind = kinds[l.node] or l.kind
        count[l.kind] = (count[l.kind] or 0) + 1
    end
    if #beams > 0 then
        self.beams[vehicle] = beams
        log("%s : route %d, travail AV %d, travail AR %d, gyros %d, signalisation %d, autres %d",
            tostring(vehicle.getName and vehicle:getName() or "?"), count.road or 0, count.workFront or 0,
            count.workBack or 0, count.beacon or 0, count.signal or 0, count.other or 0)
    end
    self.done[vehicle] = true
end

function AS_LightRange:scan()
    for vehicle in pairs(self.done) do
        if vehicle.isDeleted then
            self.done[vehicle] = nil
            self.beams[vehicle] = nil
        end
    end
    for _, vehicle in pairs(getVehicles()) do
        if not vehicle.isDeleted and self.done[vehicle] == nil then
            pcall(self.processVehicle, self, vehicle)
        end
    end
end

local function differs(a, b)
    return math.abs(a - b) > 0.0001
end

-- Une valeur posée par le jeu (différente de la nôtre) devient la base,
-- puis on écrit base x facteur
function AS_LightRange:updateBeams()
    local F = self.FACTORS
    for vehicle, list in pairs(self.beams) do
        if vehicle.isDeleted then
            self.beams[vehicle] = nil
        else
            for _, l in ipairs(list) do
                local kr = F[l.kind] or 1
                local kg = kr
                local range = getLightRange(l.node)
                if range ~= nil and differs(range, l.rangeW) then
                    l.range = range
                    l.rangeW = range * kr
                    if kr ~= 1 then setLightRange(l.node, l.rangeW) end
                end
                local r, g, b = getLightColor(l.node)
                if r ~= nil and (differs(r, l.rW) or differs(g, l.gW) or differs(b, l.bW)) then
                    l.r, l.g, l.b = r, g, b
                    l.rW, l.gW, l.bW = r * kg, g * kg, b * kg
                    if kg ~= 1 then setLightColor(l.node, l.rW, l.gW, l.bW) end
                end
            end
        end
    end
end

-- Nouveaux facteurs (menu) : chaque faisceau reprend sa valeur du jeu x facteur de son type
function AS_LightRange:setFactors(factors)
    local changed = false
    for _, k in ipairs(self.TYPES) do
        local v = math.max(1, (factors or {})[k] or self.FACTORS[k] or 1)
        if math.abs(v - (self.FACTORS[k] or 1)) > 0.001 then changed = true end
        self.FACTORS[k] = v
    end
    if not changed then return end
    for _, list in pairs(self.beams) do
        for _, l in ipairs(list) do
            if entityExists(l.node) and l.rangeW >= 0 then
                local f = self.FACTORS[l.kind] or 1
                l.rangeW = l.range * f
                setLightRange(l.node, l.rangeW)
                l.rW, l.gW, l.bW = l.r * f, l.g * f, l.b * f
                setLightColor(l.node, l.rW, l.gW, l.bW)
            end
        end
    end
end

-- (v1.0.0.83) Oui / Non : sur Non, valeurs du jeu remises, plus aucune lecture
function AS_LightRange:setEnabled(on)
    on = on == true
    if on == self.ENABLED then return end
    self.ENABLED = on
    if not on then
        for _, list in pairs(self.beams) do
            for _, l in ipairs(list) do
                if entityExists(l.node) and l.rangeW >= 0 then
                    setLightRange(l.node, l.range)
                    setLightColor(l.node, l.r, l.g, l.b)
                end
            end
        end
    end
    -- nouvelle recherche des lumières au retour sur Oui
    self.done, self.beams = {}, {}
    self.timer = self.SCAN_MS
end

function AS_LightRange:update(dt)
    if not self.ENABLED or g_currentMission == nil or g_client == nil then return end
    pcall(self.updateBeams, self)
    self.timer = self.timer + (dt or 0)
    if self.timer < self.SCAN_MS then return end
    self.timer = 0
    pcall(self.scan, self)
end

function AS_LightRange:deleteMap()
    self.timer = self.SCAN_MS
    self.done, self.beams = {}, {}
end

addModEventListener(AS_LightRange)
