-- AutoSwitch : flaques et mares selon le sol (Precision Farming + Mud System Physics)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getMudClass, shClamp, shSmootherstep = AS.getMudClass, AS.shClamp, AS.shSmootherstep

-------------------------------------------------------------------------------
-- Flaques (version de TEST, étapes A et B du plan)
--   A. Le type de sol de Precision Farming entre dans l'hydrologie de Mud System
--      Physics (FieldLocalWetnessLayer) : la rétention de chaque case est multipliée
--      par le coefficient du sol (sable : sèche vite, argile : reste mouillée).
--      Les creux du terrain (cuvettes MSP, micro-creux) deviennent des emplacements
--      de flaque : point le plus bas, nature du sol en surface (champ, chemin, pré ;
--      jamais sur le goudron, le béton ou dans l'eau), niveau de débordement.
--      Chaque emplacement reçoit de l'eau quand il pleut sur un sol saturé et la
--      perd par infiltration (selon le sol) et évaporation.
--   B. Affichage : un disque d'eau horizontal au niveau de l'eau, centré sur le point
--      le plus bas ; son bord est toujours sous le terrain, c'est le relief qui
--      dessine la forme de la flaque. Seulement autour de la caméra.
--   Relevés [AS_Puddles] dans le log. Aucun fichier de MSP ni de PF n'est modifié.
-------------------------------------------------------------------------------
AS_Puddles = {}
AS_Puddles.ENABLED = true

-- Sols Precision Farming : 1 sable glaiseux, 2 glaise sableuse, 3 glaise, 4 argile limoneuse
--   ret : rétention MSP ; inf : infiltration de la flaque ; dry : évaporation
AS_Puddles.SOIL = {
    [1] = { ret = 0.70, inf = 1.60, dry = 1.40 },
    [2] = { ret = 0.85, inf = 1.25, dry = 1.15 },
    [3] = { ret = 1.00, inf = 1.00, dry = 1.00 },
    [4] = { ret = 1.35, inf = 0.55, dry = 0.70 },
}
AS_Puddles.DEFAULT_SOIL = 3

AS_Puddles.RAIN_MM_PER_HOUR = 6      -- même estimation que la fenêtre Météo
AS_Puddles.SEEP_MM_PER_HOUR = 1.2    -- infiltration de la flaque, sol pas saturé, glaise
AS_Puddles.EVAP_MM_PER_HOUR = 0.12   -- évaporation, 15 °C, ciel moyen
AS_Puddles.MAX_DEPTH_MM = 300
AS_Puddles.MIN_SPILL_M = 0.015       -- creux de moins de 1,5 cm : pas de flaque
AS_Puddles.MIN_POCKET = 0.25         -- cuvette MSP
AS_Puddles.MIN_MICRO_M = 0.03        -- micro-creux MSP (m)
AS_Puddles.RINGS = { 0.75, 1.25, 1.75, 2.5, 3.25, 4, 5, 6, 7.5, 9, 11, 13, 16 }
AS_Puddles.RING_DIRS = 24
AS_Puddles.RUNOFF_RAIN = 0.35        -- part de la pluie de la case qui coule vers le creux
AS_Puddles.RUNOFF_FILL = 0.6         -- idem pour asPuddleFill (sol déjà mouillé)
AS_Puddles.MIN_RADIUS = 0.6          -- flaque d'au moins 1,2 m de large

AS_Puddles.UPDATE_MS = 2000          -- calcul de l'eau
AS_Puddles.VIEW_MS = 500             -- choix des flaques affichées
AS_Puddles.VIEW_DIST = 150
AS_Puddles.MAX_VISIBLE = 300
AS_Puddles.MIN_VISIBLE_MM = 3
AS_Puddles.BUDGET_MS = 2             -- temps de calcul maxi par image pendant la préparation
AS_Puddles.LOG_GAME_MINUTES = 60
AS_Puddles.FILE_NAME = "autoSwitchPuddles.xml"
AS_Puddles.I3D = "objects/puddle/flaque.i3d"   -- flaque faite par Fabien (GIANTS Editor)
AS_Puddles.LOOKS = { "eau (réglages de Dynamic Puddles)" }   -- ordre des formes dans puddle.i3d

AS_Puddles.modDir = g_currentModDirectory or ""

local SURFACE_NAMES = { field = "champ", path = "chemin", gravel = "gravier", grass = "pré", other = "autre" }

local function sprint(fmt, ...)
    print("[AS_Puddles] " .. string.format(fmt, ...))
end

local function terrainNode()
    local m = g_currentMission
    return (m ~= nil and (m.terrainRootNode or m.terrainRootNodeId)) or g_terrainNode
end

local function heightAt(x, z)
    return getTerrainHeightAtWorldPos(terrainNode(), x, 0, z)
end

local function gameHours()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return nil end
    return (env.currentMonotonicDay or env.currentDay or 0) * 24 + (env.dayTime or 0) / 3600000
end

function AS_Puddles:reset()
    self.layer = nil
    self.state = "wait"      -- wait -> soil -> scan -> run
    self.cursor = 1
    self.soilRaw = {}
    self.lowPoints = nil
    self.soilPasses = 0
    self.soilRedo = false
    self.puddles = {}        -- liste des emplacements
    self.byIndex = {}        -- [index de case MSP] = emplacement
    self.scanStats = {}
    self.lastHours = nil
    self.lastLogHours = nil
    self.timer = 0
    self.viewTimer = 0
    self.visible = {}
end

-------------------------------------------------------------------------------
-- Sol Precision Farming
-------------------------------------------------------------------------------
function AS_Puddles:getSoilMap()
    if self.soilMap ~= nil then return self.soilMap end
    local pf = AS.modGlobal("FS25_precisionFarming", "g_precisionFarming")
    if pf ~= nil and pf.soilMap ~= nil and pf.soilMap.getTypeIndexAtWorldPos ~= nil then
        self.soilMap = pf.soilMap
    end
    return self.soilMap
end

-- getTypeIndexAtWorldPos ne répond que là où un échantillon a été prélevé (3 % de la
-- carte chez Fabien) : on lit directement la carte des sols (bitVectorMap de PF,
-- canaux du type : typeFirstChannel / typeNumChannels de PrecisionFarming.xml).
function AS_Puddles:findSoilBitMap()
    if self.soilBitMap ~= nil then return self.soilBitMap or nil end
    self.soilBitMap = false
    local soil = self:getSoilMap()
    if soil == nil or getBitVectorMapSize == nil or getBitVectorMapPoint == nil then return nil end
    -- seulement le champ bitVectorMap (essayer les autres nombres provoquait des erreurs moteur)
    local id = soil.bitVectorMap
    if type(id) == "number" and id > 0 then
        local ok, sx, sy = pcall(getBitVectorMapSize, id)
        if ok and type(sx) == "number" and sx > 0 then
            self.soilBitMap = { id = id, sx = sx, sy = sy or sx }
        end
    end
    sprint("carte des sols PF : %s", self.soilBitMap and string.format("%dx%d", self.soilBitMap.sx, self.soilBitMap.sy) or "introuvable")
    local b = self.soilBitMap
    if b then
        b.first = tonumber(soil.typeFirstChannel) or 0
        b.num = tonumber(soil.typeNumChannels) or 2
        b.size = (g_currentMission ~= nil and tonumber(g_currentMission.terrainSize)) or 2048
    end
    return b or nil
end

function AS_Puddles:readSoilBitMap(x, z)
    local b = self:findSoilBitMap()
    if b == nil then return nil end
    local half = b.size * 0.5
    local px = math.floor((x + half) / b.size * b.sx)
    local pz = math.floor((z + half) / b.size * b.sy)
    if px < 0 or pz < 0 or px >= b.sx or pz >= b.sy then return nil end
    return getBitVectorMapPoint(b.id, px, pz, b.first, b.num)
end

function AS_Puddles:getSoilAt(x, z)
    local map = self:getSoilMap()
    if map == nil then return self.DEFAULT_SOIL end
    local ok, t = pcall(map.getTypeIndexAtWorldPos, map, x, z)
    if ok and type(t) == "number" and self.SOIL[t] ~= nil then return t, t end
    -- lecture directe : valeur 0 à 3 = types 1 à 4
    local okB, v = pcall(self.readSoilBitMap, self, x, z)
    if okB and type(v) == "number" and self.SOIL[v + 1] ~= nil then return v + 1, "b" .. v end
    return self.DEFAULT_SOIL, ok and t or nil
end

-------------------------------------------------------------------------------
-- Nature du sol en surface
-------------------------------------------------------------------------------
function AS_Puddles:loadLayers()
    self.layers = {}
    local node = terrainNode()
    if node == nil or getTerrainNumOfLayers == nil or getTerrainLayerAtWorldPos == nil then return end
    local count = getTerrainNumOfLayers(node) or 0
    local names = {}
    for id = 0, count - 1 do
        local raw = tostring(getTerrainLayerName(node, id) or "")
        local n = string.upper(raw)
        local kind = "other"
        local function has(s) return string.find(n, s, 1, true) ~= nil end
        if has("WATER") then kind = "water"
        elseif has("ASPHALT") or has("CONCRETE") or has("COBBLE") or has("STONE") or has("TILE")
            or has("PAVEMENT") or has("ROAD") or has("BRICK") or has("ROCK") then kind = "hard"
        elseif has("GRAVEL") then kind = "gravel"
        elseif has("DIRT") or has("MUD") or has("SAND") or has("PATH") or has("TRACK") or has("SOIL") then kind = "path"
        elseif has("GRASS") or has("MEADOW") or has("FOREST") or has("LEAF") or has("MOSS") then kind = "grass"
        end
        self.layers[#self.layers + 1] = { id = id, kind = kind }
        names[#names + 1] = raw .. "=" .. kind
    end
    sprint("%d couches de terrain : %s", count, table.concat(names, ", "))
end

function AS_Puddles:getSurfaceAt(x, z, y)
    local env = g_currentMission ~= nil and g_currentMission.environmentAreaSystem or nil
    if env ~= nil and env.getWaterYAtWorldPosition ~= nil then
        local ok, wy = pcall(env.getWaterYAtWorldPosition, env, x, y + 0.5, z)
        if ok and wy ~= nil and wy > y - 0.05 then return "water" end
    end
    if FSDensityMapUtil ~= nil and FSDensityMapUtil.getFieldDataAtWorldPosition ~= nil then
        local ok, onField = pcall(FSDensityMapUtil.getFieldDataAtWorldPosition, x, 0, z)
        if ok and onField == true then return "field" end
    end
    local node = terrainNode()
    local best, bestW = "other", 0
    for _, l in ipairs(self.layers or {}) do
        local w = getTerrainLayerAtWorldPos(node, l.id, x, 0, z) or 0
        if w > bestW then best, bestW = l.kind, w end
    end
    return best
end

-------------------------------------------------------------------------------
-- A1 : sol PF dans l'hydrologie MSP
-------------------------------------------------------------------------------
function AS_Puddles:hookLayer(layer)
    if self.hooked or type(layer.finalizeCell) ~= "function" then return end
    -- case recalculée par MSP : sa rétention repart de zéro, le sol sera réappliqué
    layer.finalizeCell = Utils.appendedFunction(layer.finalizeCell, function(l, index)
        local cell = l.cells ~= nil and l.cells[index] or nil
        if cell ~= nil then
            rawset(cell, "__asSoil", nil)
            if AS_Puddles.state == "run" then AS_Puddles.state = "soil"; AS_Puddles.cursor = 1 end
        end
    end)
    self.hooked = true
end

function AS_Puddles:stepSoil(deadline)
    local cells = self.layer.cells
    while self.cursor <= #cells do
        local cell = cells[self.cursor]
        if cell ~= nil and (rawget(cell, "__asSoil") == nil or self.soilRedo) then
            local soil, raw = self:getSoilAt(cell.x, cell.z)
            -- rétention d'origine de MSP gardée : un nouveau passage repart d'elle
            local base = rawget(cell, "__asBaseRet")
            if base == nil or rawget(cell, "__asSoil") == nil then
                base = cell.retention or 1
                rawset(cell, "__asBaseRet", base)
            end
            cell.retention = shClamp(base * self.SOIL[soil].ret, 0.42, 2.25)
            rawset(cell, "__asSoil", soil)
            local key = raw == nil and "nil" or tostring(raw)
            self.soilRaw[key] = (self.soilRaw[key] or 0) + 1
        end
        self.cursor = self.cursor + 1
        if self.cursor % 256 == 0 and getTimeSec() > deadline then return false end
    end
    return true
end

-- valeurs brutes lues dans la carte des sols (0 = pas de sol PF à cet endroit)
function AS_Puddles:logSoil()
    self.soilPasses = self.soilPasses + 1
    local r = self.soilRaw
    local parts = {}
    for k, v in pairs(r) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    sprint("sol PF passage %d : valeurs lues %s (1 à 4 : PF ; b0 à b3 : carte des sols lue directement = types 1 à 4 ; 0/nil = rien, compté glaise)",
        self.soilPasses, table.concat(parts, ", "))
    self.soilKnown = (r["1"] or 0) + (r["2"] or 0) + (r["3"] or 0) + (r["4"] or 0)
    self.soilRaw = {}
    self.soilRedo = false
    self.soilRedoTimer = 0
end

-- (test) la carte des sols peut se remplir après le premier passage : nouveau passage
-- toutes les 60 s tant que le nombre de cases avec un sol augmente (5 passages au plus)
function AS_Puddles:checkSoilRedo(dt)
    if self.soilPasses >= 5 or self.layer == nil then return end
    self.soilRedoTimer = (self.soilRedoTimer or 0) + (dt or 0)
    if self.soilRedoTimer < 60000 then return end
    self.soilRedoTimer = 0
    self.soilRedo = true
    self.cursor = 1
    local deadline = getTimeSec() + 0.5
    while not self:stepSoil(deadline) do deadline = getTimeSec() + 0.5 end
    local before = self.soilKnown
    self:logSoil()
    for _, p in ipairs(self.puddles) do p.soil = rawget(p.cell, "__asSoil") or p.soil end
    if self.soilKnown <= before then self.soilPasses = 5 end
end

-------------------------------------------------------------------------------
-- A2 : emplacements de flaque
-------------------------------------------------------------------------------
function AS_Puddles:isCandidate(cell)
    if (cell.pocket or 0) >= self.MIN_POCKET then return true end
    if (cell.microDepressionDepth or 0) >= self.MIN_MICRO_M then return true end
    return cell.downstream == nil and (cell.lowland or 0) > 0.03
end

-- point le plus bas de la case, puis descente vers le creux voisin
function AS_Puddles:findLowPoint(cell, size)
    local half = size * 0.5
    local bx, bz, bh = cell.x, cell.z, math.huge
    local step = math.max(1, size / 8)
    for dz = -half, half + 0.01, step do
        for dx = -half, half + 0.01, step do
            local h = heightAt(cell.x + dx, cell.z + dz)
            if h < bh then bx, bz, bh = cell.x + dx, cell.z + dz, h end
        end
    end
    for _ = 1, 8 do
        local nx, nz, nh = bx, bz, bh
        for dz = -0.5, 0.5, 0.5 do
            for dx = -0.5, 0.5, 0.5 do
                local h = heightAt(bx + dx, bz + dz)
                if h < nh - 0.001 then nx, nz, nh = bx + dx, bz + dz, h end
            end
        end
        if nx == bx and nz == bz then break end
        bx, bz, bh = nx, nz, nh
    end
    return bx, bz, bh
end

-- hauteur la plus basse du terrain sur chaque cercle autour du point bas
function AS_Puddles:measureRim(x, z)
    local rim, spill = {}, -math.huge
    local n = self.RING_DIRS
    for i, r in ipairs(self.RINGS) do
        local low = math.huge
        for k = 0, n - 1 do
            local a = 2 * math.pi * k / n
            local h = heightAt(x + math.cos(a) * r, z + math.sin(a) * r)
            if h < low then low = h end
        end
        rim[i] = low
        if low > spill then spill = low end
    end
    return rim, spill
end

-- deux cases voisines peuvent descendre au même point bas : une seule flaque
function AS_Puddles:hasPuddleAt(x, z)
    self.lowPoints = self.lowPoints or {}
    local key = math.floor(x * 2 + 0.5) .. ":" .. math.floor(z * 2 + 0.5)
    if self.lowPoints[key] then return true end
    self.lowPoints[key] = true
    return false
end

function AS_Puddles:stepScan(deadline)
    local cells = self.layer.cells
    local size = tonumber(self.layer.cellMeters) or 8
    local st = self.scanStats
    while self.cursor <= #cells do
        local index = self.cursor
        local cell = cells[index]
        self.cursor = self.cursor + 1
        if cell ~= nil and self:isCandidate(cell) then
            st.creux = (st.creux or 0) + 1
            local x, z, h = self:findLowPoint(cell, size)
            local surface = self:getSurfaceAt(x, z, h)
            if surface == "water" or surface == "hard" then
                st[surface] = (st[surface] or 0) + 1
            elseif self.byIndex[index] == nil and not self:hasPuddleAt(x, z) then
                local rim, spill = self:measureRim(x, z)
                local maxLevel = spill - 0.005
                if maxLevel - h < self.MIN_SPILL_M then
                    st.plat = (st.plat or 0) + 1
                else
                    local p = {
                        index = index, cell = cell, x = x, z = z, h = h,
                        rim = rim, maxDepthMm = math.min(self.MAX_DEPTH_MM, (maxLevel - h) * 1000),
                        soil = rawget(cell, "__asSoil") or self:getSoilAt(x, z),
                        surface = surface, depth = 0,
                    }
                    local saved = self.saved ~= nil and self.saved[index] or nil
                    if saved ~= nil then p.depth = math.min(saved, p.maxDepthMm) end
                    self.puddles[#self.puddles + 1] = p
                    self.byIndex[index] = p
                    st[surface] = (st[surface] or 0) + 1
                end
            end
        end
        if getTimeSec() > deadline then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- A3 : eau dans les flaques
-------------------------------------------------------------------------------
function AS_Puddles:getWeather()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local w = env ~= nil and env.weather or nil
    if w == nil then return 0, 15, 0.25 end
    local rain = w.getRainFallScale ~= nil and w:getRainFallScale() or 0
    local temp = w.getCurrentTemperature ~= nil and w:getCurrentTemperature() or 15
    local cloud = 0.25
    if w.cloudUpdater ~= nil and w.cloudUpdater.currentClouds ~= nil then
        local c = w.cloudUpdater.currentClouds
        cloud = math.max(tonumber(c.precipitation) or 0, shClamp((tonumber(c.densityScale) or 0) * 35, 0, 1))
    end
    return tonumber(rain) or 0, tonumber(temp) or 15, shClamp(cloud, 0, 1)
end

-- part de la pluie qui reste en surface et infiltration (mm/h) selon l'état du sol MSP
function AS_Puddles:soilState(p)
    local cell = p.cell
    local moisture = tonumber(cell.moisture) or 0
    local ret = shClamp(tonumber(cell.retention) or 1, 0.42, 2.25)
    local topo = (cell.lowland or 0) * 0.08 + (cell.pocket or 0) * 0.12 + (cell.catchment or 0) * 0.06
    local fc = shClamp(0.38 + ret * 0.13 + topo, 0.38, 0.82)
    local sat = shClamp(fc + 0.13 + topo, 0.54, 0.96)
    local e = shSmootherstep(fc, sat, moisture)
    return e, moisture
end

-- verse un volume d'eau (m³) dans le creux : le niveau monte selon la surface déjà mouillée
function AS_Puddles:addWater(p, m3)
    while m3 > 1e-6 and p.depth < p.maxDepthMm do
        local r = self:getRadius(p) or self.RINGS[#self.RINGS]
        local area = math.pi * math.max(r, self.MIN_RADIUS) ^ 2
        local dh = math.min(m3 / area, 0.005, (p.maxDepthMm - p.depth) / 1000)
        p.depth = p.depth + dh * 1000
        m3 = m3 - dh * area
    end
end

function AS_Puddles:cellArea()
    local size = self.layer ~= nil and tonumber(self.layer.cellMeters) or 8
    return size * size
end

function AS_Puddles:simulate(dtH)
    local rain, temp, cloud = self:getWeather()
    local rainMm = rain > 0.01 and rain * self.RAIN_MM_PER_HOUR or 0
    local tempMul = temp <= 0 and 0.15 or (temp >= 30 and 1.5 or 0.3 + 1.2 * temp / 30)
    local area = self:cellArea()
    local evap = self.EVAP_MM_PER_HOUR * tempMul * (1.2 - 0.7 * cloud) * (rainMm > 0 and 0.2 or 1)
    for _, p in ipairs(self.puddles) do
        local soil = self.SOIL[p.soil] or self.SOIL[self.DEFAULT_SOIL]
        local e = self:soilState(p)
        local cell = p.cell
        if rainMm > 0 then
            -- la pluie tombée sur la case (et l'amont) ruisselle vers le creux
            local collect = 1 + 2 * (cell.catchment or 0) + 1.5 * (cell.pocket or 0)
            local surface = shClamp(0.10 + 0.90 * e - (soil.inf - 1) * 0.50, 0, 1.3)
            self:addWater(p, rainMm * dtH / 1000 * area * self.RUNOFF_RAIN * collect * surface)
        end
        local seep = self.SEEP_MM_PER_HOUR * soil.inf * soil.inf * (1 - 0.75 * e)
        local loss = seep + evap * soil.dry
        p.depth = shClamp(p.depth - loss * dtH, 0, p.maxDepthMm)
    end
end

-------------------------------------------------------------------------------
-- Relevés
-------------------------------------------------------------------------------
function AS_Puddles:logState(reason)
    local n, sum, maxD = 0, 0, 0
    local bySoil, bySurf, ponds = { 0, 0, 0, 0 }, {}, 0
    for _, p in ipairs(self.puddles) do
        if p.depth >= self.MIN_VISIBLE_MM then
            n = n + 1
            sum = sum + p.depth
            if p.depth > maxD then maxD = p.depth end
            bySoil[p.soil] = (bySoil[p.soil] or 0) + 1
            bySurf[p.surface] = (bySurf[p.surface] or 0) + 1
            local r = self:getRadius(p)
            if r ~= nil and r >= 6 then ponds = ponds + 1 end
        end
    end
    local surf = {}
    for k, v in pairs(bySurf) do surf[#surf + 1] = (SURFACE_NAMES[k] or k) .. " " .. v end
    local rain, temp = self:getWeather()
    local hum = self.layer ~= nil and (self.layer._lastAverage or 0) * 100 or 0
    sprint("%s : %d flaques dont %d mares (%s) ; par sol : sable %d / glaise sableuse %d / glaise %d / argile %d ; eau moy. %.0f mm, maxi %.0f mm ; pluie %.2f, %.0f °C, humidité MSP moy. %.0f %%",
        reason, n, ponds, table.concat(surf, ", "), bySoil[1], bySoil[2], bySoil[3], bySoil[4],
        n > 0 and sum / n or 0, maxD, rain, temp, hum)
end

-------------------------------------------------------------------------------
-- B : affichage
-------------------------------------------------------------------------------
function AS_Puddles:onI3DLoaded(node, failedReason, args)
    if node == nil or node == 0 then
        sprint("ERREUR : modèle de flaque non chargé (%s)", tostring(failedReason))
        self.i3dFailed = true
        return
    end
    self.template = node
    -- comme Dynamic Puddles : modèle chargé avec la physique, posé caché dans la scène
    link(getRootNode(), node)
    setVisibility(node, false)
    -- le jeu renvoie une racine : on descend jusqu'au groupe qui porte les formes
    local group = node
    while getNumOfChildren(group) == 1 and getNumOfChildren(getChildAt(group, 0)) > 0 do group = getChildAt(group, 0) end
    self.templateGroup = group
    -- taille réelle du modèle : rayon de la plus grande forme, pour la mise à l'échelle
    self.modelRadius, self.modelCx, self.modelCz = 1, 0, 0
    for i = 0, getNumOfChildren(group) - 1 do
        local shape = getChildAt(group, i)
        setVisibility(shape, true)
        if getShapeBoundingSphere ~= nil then
            local ok, bx, _, bz, br = pcall(getShapeBoundingSphere, shape)
            if ok and type(br) == "number" and br > 0 and (i == 0 or br > self.modelRadius) then
                local lx, _, lz = getTranslation(shape)
                self.modelRadius, self.modelCx, self.modelCz = br, bx + lx, bz + lz
            end
        end
    end
    self.templateShapes = { group }
    sprint("modèle de flaque : %d formes, rayon %.2f m, centre %.2f / %.2f", getNumOfChildren(group), self.modelRadius, self.modelCx, self.modelCz)
    sprint("modèle de flaque chargé (aspect %d)", self.look or 1)
end

function AS_Puddles:loadI3D()
    if self.i3dRequested then return end
    self.i3dRequested = true
    self.look = self.look or 1
    local path = Utils.getFilename(self.I3D, self.modDir)
    self.i3dReq = g_i3DManager:loadSharedI3DFileAsync(path, false, true, self.onI3DLoaded, self, nil)
end

function AS_Puddles:newNode()
    local src = self.templateShapes[self.look] or self.templateShapes[1]
    if src == nil or src == 0 then return nil end
    local node = clone(src, true, false, true)
    if node == nil or node == 0 then return nil end
    link(getRootNode(), node)
    setVisibility(node, true)
    return node
end

-- Eau peu profonde du jeu (comme Dynamic Puddles) : la flaque devient un plan d'eau
-- connu du moteur, avec vagues et éclaboussures au passage des roues.
local function eachBody(node, fn)
    if getRigidBodyType ~= nil and getRigidBodyType(node) ~= RigidBodyType.NONE then fn(node) end
    for i = 0, getNumOfChildren(node) - 1 do eachBody(getChildAt(node, i), fn) end
end

function AS_Puddles:swsAdd(node)
    local sws = g_currentMission ~= nil and g_currentMission.shallowWaterSimulation or nil
    if sws == nil then return end
    eachBody(node, function(n) if sws:addWaterPlane(n) then sws:addAreaGeometry(n) end end)
end

function AS_Puddles:swsRemove(node)
    local sws = g_currentMission ~= nil and g_currentMission.shallowWaterSimulation or nil
    if sws == nil then return end
    eachBody(node, function(n)
        if sws.removeWaterPlane ~= nil then sws:removeWaterPlane(n) end
        if sws.removeAreaGeometry ~= nil then sws:removeAreaGeometry(n) end
    end)
end

function AS_Puddles:clearNodes()
    for p, node in pairs(self.visible) do
        pcall(self.swsRemove, self, node)
        delete(node)
        p.shown = nil
    end
    self.visible = {}
    for _, node in ipairs(self.pool or {}) do delete(node) end
    self.pool = {}
end

-- rayon du disque : premier cercle dont le terrain reste au-dessus de l'eau
function AS_Puddles:getRadius(p)
    local level = p.h + p.depth / 1000 + 0.005
    for i, r in ipairs(self.RINGS) do
        if p.rim[i] >= level then return r end
    end
    return nil
end

function AS_Puddles:updateView()
    if self.template == nil then return end
    local cam = getCamera ~= nil and getCamera() or nil
    if cam == nil or cam == 0 then return end
    local cx, _, cz = getWorldTranslation(cam)
    local d2max = self.VIEW_DIST * self.VIEW_DIST
    local list = {}
    for _, p in ipairs(self.puddles) do
        if p.depth >= self.MIN_VISIBLE_MM then
            local dx, dz = p.x - cx, p.z - cz
            local d2 = dx * dx + dz * dz
            if d2 <= d2max then list[#list + 1] = { p = p, d2 = d2 } end
        end
    end
    table.sort(list, function(a, b) return a.d2 < b.d2 end)
    local keep = {}
    for i = 1, math.min(#list, self.MAX_VISIBLE) do
        local p = list[i].p
        local r = self:getRadius(p)
        if r ~= nil then keep[p] = math.max(r, self.MIN_RADIUS) end
    end
    self.pool = self.pool or {}
    for p, node in pairs(self.visible) do
        if keep[p] == nil then
            self:swsRemove(node)
            setVisibility(node, false)
            self.pool[#self.pool + 1] = node
            self.visible[p] = nil
            p.shown = nil
        end
    end
    for p, r in pairs(keep) do
        local node = self.visible[p]
        if node == nil then
            node = table.remove(self.pool) or self:newNode()
            if node == nil then return end
            self.visible[p] = node
        end
        -- niveau arrondi au demi-centimètre : on ne touche au plan d'eau que s'il change
        local y = p.h + math.floor(p.depth / 5 + 0.5) * 0.005
        local sh = p.shown
        if sh == nil or sh.r ~= r or sh.y ~= y then
            if sh ~= nil then self:swsRemove(node) end
            -- modèle mis à la taille du creux, centré sur le point bas, tourné au hasard (fixe)
            local sc = r / self.modelRadius
            local rot = ((p.index * 7919) % 360) * math.pi / 180
            local cs, sn = math.cos(rot), math.sin(rot)
            local ox = (self.modelCx * cs + self.modelCz * sn) * sc
            local oz = (-self.modelCx * sn + self.modelCz * cs) * sc
            setWorldTranslation(node, p.x - ox, y, p.z - oz)
            setRotation(node, 0, rot, 0)
            setScale(node, sc, 1, sc)
            setVisibility(node, true)
            self:swsAdd(node)
            p.shown = { r = r, y = y }
        end
    end
end

-------------------------------------------------------------------------------
-- Sauvegarde
-------------------------------------------------------------------------------
local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_Puddles.FILE_NAME
end

function AS_Puddles:save()
    if self.state ~= "run" then return end
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asPuddles", path, "puddles")
    if xml == nil or xml == 0 then return end
    local i = 0
    for _, p in ipairs(self.puddles) do
        if p.depth > 0.5 then
            local key = string.format("puddles.p(%d)", i)
            setXMLInt(xml, key .. "#i", p.index)
            setXMLFloat(xml, key .. "#mm", p.depth)
            i = i + 1
        end
    end
    saveXMLFile(xml)
    delete(xml)
end

function AS_Puddles:load()
    self.saved = {}
    local path = savegamePath()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("asPuddles", path)
    if xml == nil or xml == 0 then return end
    local i, n = 0, 0
    while true do
        local key = string.format("puddles.p(%d)", i)
        local index = getXMLInt(xml, key .. "#i")
        if index == nil then break end
        self.saved[index] = getXMLFloat(xml, key .. "#mm") or 0
        i = i + 1
        n = n + 1
    end
    delete(xml)
    sprint("%d flaques reprises de la sauvegarde", n)
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_Puddles.save, AS_Puddles)
        if not ok then print("[AS_Puddles] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

-------------------------------------------------------------------------------
-- Commandes console (test)
-------------------------------------------------------------------------------
function AS_Puddles:consoleFill(mm)
    mm = tonumber(mm) or 20
    if self.state ~= "run" then
        self.pendingFill = (self.pendingFill or 0) + mm
        return string.format("flaques pas encore prêtes (%s) : +%d mm ajoutés dès qu'elles le seront", tostring(self.state), mm)
    end
    local m3 = mm / 1000 * self:cellArea() * self.RUNOFF_FILL
    for _, p in ipairs(self.puddles) do self:addWater(p, m3) end
    self.viewTimer = self.VIEW_MS
    return string.format("flaques : pluie de %d mm versée dans %d creux", mm, #self.puddles)
end

function AS_Puddles:consoleClear()
    for _, p in ipairs(self.puddles) do p.depth = 0 end
    self.viewTimer = self.VIEW_MS
    return "flaques vidées"
end

function AS_Puddles:consoleLook(look)
    look = tonumber(look) or 1
    if self.LOOKS[look] == nil then return "asPuddleLook 1 (eau)" end
    self.look = look
    self:clearNodes()
    self.viewTimer = self.VIEW_MS
    return "aspect des flaques : " .. self.LOOKS[look]
end

function AS_Puddles:consoleInfo()
    self:logState("relevé demandé")
    local cam = getCamera ~= nil and getCamera() or nil
    if cam == nil or cam == 0 then return "état : " .. tostring(self.state) end
    local cx, _, cz = getWorldTranslation(cam)
    local _, raw = self:getSoilAt(cx, cz)
    sprint("  sol PF sous la caméra (x %.0f, z %.0f) : %s", cx, cz, tostring(raw))
    local list = {}
    for _, p in ipairs(self.puddles) do
        local dx, dz = p.x - cx, p.z - cz
        list[#list + 1] = { p = p, d = math.sqrt(dx * dx + dz * dz), dx = dx, dz = dz }
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local soilNames = { "sable glaiseux", "glaise sableuse", "glaise", "argile limoneuse" }
    for i = 1, math.min(8, #list) do
        local e = list[i]
        local p = e.p
        local r = self:getRadius(p)
        sprint("  %.0f m (x %.0f, z %.0f) : %s, %s, eau %.0f mm / maxi %.0f mm, rayon %s m, humidité MSP %.0f %%",
            e.d, p.x, p.z, SURFACE_NAMES[p.surface] or p.surface, soilNames[p.soil] or "?", p.depth, p.maxDepthMm,
            r ~= nil and string.format("%.1f", r) or "-", (tonumber(p.cell.moisture) or 0) * 100)
    end
    return string.format("état %s, %d emplacements", tostring(self.state), #self.puddles)
end

-------------------------------------------------------------------------------
function AS_Puddles:loadMap()
    self:reset()
    local ok, err = pcall(self.load, self)
    if not ok then sprint("ERREUR chargement : %s", tostring(err)) end
    addConsoleCommand("asPuddleFill", "Flaques (test) : ajoute de l'eau (mm) dans tous les creux", "consoleFill", self)
    addConsoleCommand("asPuddleClear", "Flaques (test) : vide toutes les flaques", "consoleClear", self)
    addConsoleCommand("asPuddleInfo", "Flaques (test) : relevé et flaques les plus proches", "consoleInfo", self)
    addConsoleCommand("asPuddleLook", "Flaques (test) : aspect 1 = eau", "consoleLook", self)
    sprint("module chargé (version de test)")
end

function AS_Puddles:deleteMap()
    pcall(self.clearNodes, self)
    if self.template ~= nil then delete(self.template); self.template = nil end
    if self.i3dReq ~= nil then g_i3DManager:releaseSharedI3DFile(self.i3dReq); self.i3dReq = nil end
    self.i3dRequested = false
    removeConsoleCommand("asPuddleFill")
    removeConsoleCommand("asPuddleClear")
    removeConsoleCommand("asPuddleInfo")
    removeConsoleCommand("asPuddleLook")
    self:reset()
end

function AS_Puddles:prepare()
    local deadline = getTimeSec() + self.BUDGET_MS / 1000
    if self.state == "wait" then
        local layer = getMudClass("FieldLocalWetnessLayer")
        if type(layer) ~= "table" or layer.ready ~= true or type(layer.cells) ~= "table" or #layer.cells == 0 then return end
        self.layer = layer
        self:hookLayer(layer)
        self:loadLayers()
        sprint("hydrologie MSP prête : %d cases de %.1f m ; Precision Farming %s",
            #layer.cells, tonumber(layer.cellMeters) or 0, self:getSoilMap() ~= nil and "trouvé" or "ABSENT (sol glaise partout)")
        self.state, self.cursor = "soil", 1
        self.soilStart = getTimeSec()
    end
    if self.state == "soil" then
        if not self:stepSoil(deadline) then return end
        self:logSoil()
        if #self.puddles > 0 then
            self.state = "run"
            return
        end
        self.state, self.cursor = "scan", 1
        self.scanStart = getTimeSec()
        return
    end
    if self.state == "scan" then
        if not self:stepScan(deadline) then return end
        local st = self.scanStats
        sprint("emplacements de flaque : %d (champ %d, chemin %d, gravier %d, pré %d, autre %d) ; creux écartés : goudron/béton %d, eau %d, trop plats %d ; %d creux examinés en %.0f s",
            #self.puddles, st.field or 0, st.path or 0, st.gravel or 0, st.grass or 0, st.other or 0,
            st.hard or 0, st.water or 0, st.plat or 0, st.creux or 0, getTimeSec() - (self.scanStart or getTimeSec()))
        self.saved = nil
        self.state = "run"
        if (self.pendingFill or 0) > 0 then
            sprint("%s", self:consoleFill(self.pendingFill))
            self.pendingFill = nil
        end
        if g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil then
            pcall(g_currentMission.hud.addSideNotification, g_currentMission.hud, FSBaseMission.INGAME_NOTIFICATION_OK, "AutoSwitch : flaques prêtes")
        end
        self.lastHours = gameHours()
        self:logState("début")
    end
end

function AS_Puddles:update(dt)
    if not self.ENABLED or g_currentMission == nil or self.state == nil then return end
    if self.state ~= "run" then
        local ok, err = pcall(self.prepare, self)
        if not ok then
            sprint("ERREUR préparation : %s", tostring(err))
            self.ENABLED = false
        end
        return
    end
    self:loadI3D()
    local okS, errS = pcall(self.checkSoilRedo, self, dt)
    if not okS then sprint("ERREUR sol : %s", tostring(errS)); self.soilPasses = 5 end

    self.timer = self.timer + (dt or 0)
    if self.timer >= self.UPDATE_MS then
        self.timer = 0
        local now = gameHours()
        if now ~= nil and g_server ~= nil then
            local dtH = self.lastHours ~= nil and now - self.lastHours or 0
            self.lastHours = now
            if dtH > 0 then
                -- grands sauts (sommeil) découpés en pas de 15 min, 2 jours au plus
                local steps = math.min(192, math.max(1, math.ceil(dtH / 0.25)))
                local h = math.min(dtH, 48) / steps
                for _ = 1, steps do
                    local ok, err = pcall(self.simulate, self, h)
                    if not ok then sprint("ERREUR calcul : %s", tostring(err)); break end
                end
            end
            if self.lastLogHours == nil or now - self.lastLogHours >= self.LOG_GAME_MINUTES / 60 then
                self.lastLogHours = now
                self:logState("relevé")
            end
        end
    end

    self.viewTimer = self.viewTimer + (dt or 0)
    if self.viewTimer >= self.VIEW_MS then
        self.viewTimer = 0
        local ok, err = pcall(self.updateView, self)
        if not ok and not self.viewErr then
            self.viewErr = true
            sprint("ERREUR affichage : %s", tostring(err))
        end
    end
end

addModEventListener(AS_Puddles)
