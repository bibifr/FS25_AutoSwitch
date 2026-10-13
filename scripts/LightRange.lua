-- AutoSwitch : lumières des véhicules visibles de plus loin
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getVehicles = AS.getVehicles

-------------------------------------------------------------------------------
-- v1.0.0.37 : les halos des phares, feux, clignotants et gyros sont des
--   morceaux de la carrosserie (shapes avec le paramètre de shader des feux).
--   Chaque shape a une distance d'affichage (clipDistance) fixée dans l'i3d du
--   véhicule, souvent 75 à 150 m : au-delà, le phare d'un véhicule allumé
--   disparaît, même avec la distance de vue du jeu au maximum.
--   Ici, cette distance est multipliée par FACTOR (x5 par défaut, réglable),
--   seulement pour les shapes de feux. L'éclairage projeté au sol (vraies
--   lumières) n'est pas touché : presque aucun coût en FPS.
--   Effet seulement à l'affichage (chaque joueur pour lui-même).
-- v1.0.0.38 : luminosité des halos multipliée par GLOW (x2 par défaut, réglable).
--   Le jeu règle l'intensité d'un feu avec le paramètre de shader lightControl
--   (x = intensité, 0 = éteint) quand il l'allume ; à chaque image, une valeur
--   nouvelle posée par le jeu est reprise et multipliée. Le véhicule conduit et
--   ses outils ne sont pas touchés (tableau de bord, éblouissement en cabine).
-------------------------------------------------------------------------------
AS_LightRange = {}
AS_LightRange.FACTOR  = 5        -- 1 = jeu de base
AS_LightRange.SCAN_MS = 2000     -- recherche des nouveaux véhicules
AS_LightRange.timer   = AS_LightRange.SCAN_MS
AS_LightRange.nodes   = {}       -- node -> distance d'origine
AS_LightRange.groups  = {}       -- groupe parent -> distance d'origine
AS_LightRange.done    = {}       -- véhicule -> true quand ses feux sont trouvés
AS_LightRange.GLOW    = 2        -- luminosité des halos (1 = jeu de base)
AS_LightRange.lit     = {}       -- véhicule -> { { node, base, written } } (shapes avec lightControl)

-- Paramètres de shader portés par les shapes de feux (vehicleShader)
local LIGHT_PARAMS = { "lightControl", "lightIds0", "beaconLightControl", "lightTypeBitMask" }

local function isLightShape(node)
    if not getHasClassId(node, ClassIds.SHAPE) then return false end
    for _, p in ipairs(LIGHT_PARAMS) do
        if getHasShaderParameter(node, p) then return true end
    end
    return false
end

local function setScaled(store, node, factor)
    if store[node] == nil then
        store[node] = getClipDistance(node)
    end
    local orig = store[node]
    if orig ~= nil and orig > 0 then
        setClipDistance(node, orig * factor)
    end
end

-- Les groupes (non-shapes) au-dessus d'un feu peuvent aussi couper l'affichage
local function scaleParents(node, rootNode, factor)
    local p = getParent(node)
    while p ~= nil and p ~= 0 and p ~= rootNode do
        if not getHasClassId(p, ClassIds.SHAPE) then
            setScaled(AS_LightRange.groups, p, factor)
        end
        p = getParent(p)
    end
end

local function walk(node, rootNode, factor, found)
    if isLightShape(node) then
        setScaled(AS_LightRange.nodes, node, factor)
        scaleParents(node, rootNode, factor)
        if getHasShaderParameter(node, "lightControl") then
            found[#found + 1] = { node = node, base = 0, written = 0 }
        end
    end
    for i = 0, getNumOfChildren(node) - 1 do
        walk(getChildAt(node, i), rootNode, factor, found)
    end
end

function AS_LightRange:processVehicle(vehicle)
    if vehicle.spec_lights == nil or vehicle.components == nil then return end
    local found = {}
    for _, comp in ipairs(vehicle.components) do
        if comp.node ~= nil and comp.node ~= 0 then
            walk(comp.node, comp.node, self.FACTOR, found)
        end
    end
    if #found > 0 then self.lit[vehicle] = found end
    self.done[vehicle] = true
end

function AS_LightRange:scan()
    for vehicle in pairs(self.done) do
        if vehicle.isDeleted then
            self.done[vehicle] = nil
            self.lit[vehicle] = nil
        end
    end
    for _, vehicle in pairs(getVehicles()) do
        if not vehicle.isDeleted and self.done[vehicle] == nil then
            pcall(self.processVehicle, self, vehicle)
        end
    end
end

-- Nouveau facteur (menu) : réappliqué sur tout ce qui est déjà connu
function AS_LightRange:setFactor(factor)
    factor = math.max(1, factor or 1)
    if factor == self.FACTOR then return end
    self.FACTOR = factor
    for _, store in ipairs({ self.nodes, self.groups }) do
        for node, orig in pairs(store) do
            if entityExists(node) and orig > 0 then
                setClipDistance(node, orig * factor)
            else
                store[node] = nil
            end
        end
    end
end

-- Remet l'intensité du jeu (véhicule conduit, ou GLOW = 1)
local function restoreGlow(list)
    for _, l in ipairs(list) do
        if l.written ~= l.base and entityExists(l.node) then
            local x, y, z, w = getShaderParameter(l.node, "lightControl")
            if math.abs(x - l.written) < 0.0001 then
                setShaderParameter(l.node, "lightControl", l.base, y, z, w, false)
            end
        end
        l.written = l.base
    end
end

local function getRoot(vehicle)
    if vehicle ~= nil and vehicle.getRootVehicle ~= nil then
        local ok, r = pcall(vehicle.getRootVehicle, vehicle)
        if ok and r ~= nil then return r end
    end
    return vehicle
end

function AS_LightRange:updateGlow()
    local glow = self.GLOW
    local ownRoot = getRoot(AS.shGetControlledVehicle())
    for vehicle, list in pairs(self.lit) do
        if vehicle.isDeleted then
            self.lit[vehicle] = nil
        elseif glow <= 1 or (ownRoot ~= nil and getRoot(vehicle) == ownRoot) then
            restoreGlow(list)
        else
            for _, l in ipairs(list) do
                local x, y, z, w = getShaderParameter(l.node, "lightControl")
                if x ~= nil and math.abs(x - l.written) > 0.0001 then
                    -- valeur nouvelle posée par le jeu
                    l.base = x
                    l.written = x * glow
                    if x > 0 then
                        setShaderParameter(l.node, "lightControl", l.written, y, z, w, false)
                    end
                end
            end
        end
    end
end

-- Nouvelle luminosité (menu) : chaque feu allumé reprend son intensité du jeu x glow
function AS_LightRange:setGlow(glow)
    glow = math.max(1, glow or 1)
    if glow == self.GLOW then return end
    self.GLOW = glow
    for _, list in pairs(self.lit) do
        restoreGlow(list)
    end
end

function AS_LightRange:update(dt)
    if g_currentMission == nil or g_client == nil then return end
    pcall(self.updateGlow, self)
    self.timer = self.timer + (dt or 0)
    if self.timer < self.SCAN_MS then return end
    self.timer = 0
    pcall(self.scan, self)
end

function AS_LightRange:deleteMap()
    self.timer = self.SCAN_MS
    self.nodes, self.groups, self.done, self.lit = {}, {}, {}, {}
end

addModEventListener(AS_LightRange)
