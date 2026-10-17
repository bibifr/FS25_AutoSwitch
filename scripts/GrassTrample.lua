-- AutoSwitch : herbe piétinée sous les roues
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getMudClass, getVehicles = AS.getMudClass, AS.getVehicles

-------------------------------------------------------------------------------
-- 1.0.0.46 : Mud System Physics fauchait l'herbe et la prairie sous chaque roue
--   dès 12 % d'humidité (FieldGroundMudPhysics:lowerGrassArea). AutoSwitch coupe ce
--   fauchage et le remplace par un recul de pousse :
--   - sol sec (< 12 %) : rien sous 11 km/h, puis chance de reculer d'un stade qui
--     monte avec la vitesse (10 % à 11, 15 % à 15, 30 % à 25, 50 % à 36 km/h) ;
--   - humide (12 à 30 %) : dès 7 km/h, chance x1,5, un stade ;
--   - très humide (> 30 %) ou pluie : dès 7 km/h, chance x1,5, un stade
--     (1.0.0.48 : deux stades et chance doublée étaient trop durs pour Fabien) ;
--   - au-delà de 30 km/h : coupée à ras, quel que soit le temps ;
--   - déjà au stade le plus bas : le passage suivant la coupe à ras.
--   Un passage = un véhicule (attelage compris) sur un carré de 0,5 m : ses autres
--   roues ne comptent pas tant qu'il n'est pas reparti depuis PASS_MS.
--   Les autres cultures restent gérées par Mud System Physics. Aucun fichier de
--   Mud System Physics n'est modifié.
-------------------------------------------------------------------------------
AS_GrassTrample = {}
AS_GrassTrample.ENABLED = true
AS_GrassTrample.mspHooked = false

AS_GrassTrample.CELL = 0.5               -- taille d'un carré (m)
AS_GrassTrample.PASS_MS = 20000          -- même véhicule sur le même carré = même passage
AS_GrassTrample.DRY_MIN_KPH = 11
AS_GrassTrample.WET_MIN_KPH = 7
AS_GrassTrample.CUT_KPH = 30
AS_GrassTrample.WET = 0.12
AS_GrassTrample.VERY_WET = 0.30
AS_GrassTrample.RAIN = 0.1
AS_GrassTrample.CURVE = { { 11, 10 }, { 15, 15 }, { 25, 30 }, { 36, 50 } }
AS_GrassTrample.WET_MUL = 1.5
AS_GrassTrample.VERY_WET_STAGES = 1
AS_GrassTrample.LOG_MAX = 15

AS_GrassTrample.cells = {}
AS_GrassTrample.cellCount = 0
AS_GrassTrample.logCount = 0

local function gtLog(fmt, ...)
    local self = AS_GrassTrample
    if self.logCount >= self.LOG_MAX then return end
    self.logCount = self.logCount + 1
    print(string.format("[AS_Grass] " .. fmt, ...))
end

-- Chance (%) de reculer d'un stade par temps sec
function AS_GrassTrample:dryChance(kph)
    local c = self.CURVE
    if kph < c[1][1] then return 0 end
    for i = 2, #c do
        if kph < c[i][1] then
            local a, b = c[i - 1], c[i]
            return a[2] + (b[2] - a[2]) * (kph - a[1]) / (b[1] - a[1])
        end
    end
    return 100
end

-------------------------------------------------------------------------------
-- Mud System Physics ne fauche plus l'herbe
-------------------------------------------------------------------------------
function AS_GrassTrample:hookMsp()
    if self.mspHooked then return end
    local ok, fg = pcall(getMudClass, "FieldGroundMudPhysics")
    if not ok or fg == nil or type(fg.lowerGrassArea) ~= "function" then return end
    fg.lowerGrassArea = function(...)
        if AS_GrassTrample.ENABLED then return end
    end
    self.mspHooked = true
    print("[AS_Grass] fauchage de l'herbe par Mud System Physics coupé")
end

-------------------------------------------------------------------------------
-- Herbe et prairie
-------------------------------------------------------------------------------
function AS_GrassTrample:loadGrassTypes()
    self.grassTypes = {}
    if g_fruitTypeManager == nil or FruitType == nil then return end
    local seen = {}
    for _, index in ipairs({ FruitType.GRASS, FruitType.MEADOW }) do
        if index ~= nil and not seen[index] then
            seen[index] = true
            local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
            if desc ~= nil and desc.terrainDataPlaneId ~= nil then
                local maxState = desc.maxHarvestingGrowthState or desc.numGrowthStates or 4
                if desc.numGrowthStates ~= nil then maxState = math.max(maxState, desc.numGrowthStates) end
                local floor = 1
                if desc.cutState ~= nil and desc.cutState > 0 and desc.cutState < maxState then
                    floor = desc.cutState
                end
                local modifier = DensityMapModifier.new(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels, g_terrainNode)
                local filter = DensityMapFilter.new(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels)
                table.insert(self.grassTypes, {
                    index = index, desc = desc, maxState = maxState, floor = floor,
                    modifier = modifier, filter = filter,
                })
                print(string.format("[AS_Grass] %s : stades %d à %d, coupé = %s",
                    tostring(desc.name), floor, maxState, tostring(desc.cutState)))
            end
        end
    end
end

-- Recule l'herbe de 'stages' stades dans le carré ; si elle est déjà au plus bas, la coupe
function AS_GrassTrample:regressCell(x0, z0, x1, z1, x2, z2, stages)
    local growth = g_currentMission ~= nil and g_currentMission.growthSystem or nil
    if growth ~= nil then growth:setIgnoreDensityChanges(true) end
    for _, g in ipairs(self.grassTypes) do
        g.modifier:setParallelogramWorldCoords(x0, z0, x1, z1, x2, z2, DensityCoordType.POINT_POINT_POINT)
        -- stade le plus bas : coupée à ras (stade « coupé » du jeu), avant le recul
        local cut = g.desc.cutState
        if cut ~= nil and cut > g.maxState then
            g.filter:setValueCompareParams(DensityValueCompareType.EQUAL, g.floor)
            g.modifier:executeSet(cut, g.filter)
        end
        -- dans l'ordre croissant, pour ne jamais reculer deux fois le même pixel
        for s = g.floor + 1, g.maxState do
            g.filter:setValueCompareParams(DensityValueCompareType.EQUAL, s)
            g.modifier:executeSet(math.max(g.floor, s - stages), g.filter)
        end
    end
    if growth ~= nil then growth:setIgnoreDensityChanges(false) end
end

function AS_GrassTrample:cutCell(x0, z0, x1, z1, x2, z2)
    if FSDensityMapUtil == nil or FSDensityMapUtil.updateMowerArea == nil then return end
    for _, g in ipairs(self.grassTypes) do
        FSDensityMapUtil.updateMowerArea(g.index, x0, z0, x1, z1, x2, z2, false)
    end
end

-------------------------------------------------------------------------------
-- Météo
-------------------------------------------------------------------------------
function AS_GrassTrample:getWetLevel(vehicle)
    local wet = 0
    if AS_TtdBridge ~= nil and AS_TtdBridge.getMspWetness ~= nil then
        local ok, w = pcall(AS_TtdBridge.getMspWetness, vehicle)
        if ok and type(w) == "number" then wet = w end
    end
    local rain = 0
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local weather = env ~= nil and env.weather or nil
    if weather ~= nil and weather.getRainFallScale ~= nil then
        local ok, r = pcall(weather.getRainFallScale, weather)
        if ok and type(r) == "number" then rain = r end
    end
    if wet > self.VERY_WET or rain > self.RAIN then return 2, wet end
    if wet >= self.WET then return 1, wet end
    return 0, wet
end

-------------------------------------------------------------------------------
-- Roues
-------------------------------------------------------------------------------
local function gtHasContact(wheel)
    local p = wheel.physics
    if p == nil then return false end
    return p.hasGroundContact == true or p.hasSoilContact == true
end

-- Coin et deux côtés du carré (pour les fonctions de densité)
function AS_GrassTrample:cellCoords(cx, cz)
    local s = self.CELL
    local x, z = cx * s, cz * s
    return x, z, x + s, z, x, z + s
end

function AS_GrassTrample:processCell(cx, cz, rootId, now, kph, wetLevel, wet)
    local key = cx * 100003 + cz
    local cell = self.cells[key]
    if cell ~= nil and cell.id == rootId and (now - cell.t) < self.PASS_MS then
        cell.t = now
        return
    end
    if cell == nil then self.cellCount = self.cellCount + 1 end
    self.cells[key] = { id = rootId, t = now }

    local x0, z0, x1, z1, x2, z2 = self:cellCoords(cx, cz)
    if kph >= self.CUT_KPH then
        self:cutCell(x0, z0, x1, z1, x2, z2)
        gtLog("coupée à ras : %.0f km/h", kph)
        return
    end

    local chance, stages
    if wetLevel == 0 then
        if kph < self.DRY_MIN_KPH then return end
        chance, stages = self:dryChance(kph), 1
    else
        if kph < self.WET_MIN_KPH then return end
        chance = math.min(100, self.WET_MUL * self:dryChance(math.max(kph, self.DRY_MIN_KPH)))
        stages = wetLevel == 2 and self.VERY_WET_STAGES or 1
    end
    if math.random() * 100 >= chance then return end
    self:regressCell(x0, z0, x1, z1, x2, z2, stages)
    gtLog("recul de %d stade(s) : %.0f km/h, humidité %.0f %%, chance %.0f %%", stages, kph, wet * 100, chance)
end

function AS_GrassTrample:processVehicle(vehicle, now)
    if vehicle.getWheels == nil then return end
    local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or vehicle
    if root == nil or root.getLastSpeed == nil then return end
    local kph = root:getLastSpeed()
    if kph == nil or kph < self.WET_MIN_KPH then return end

    local wheels = vehicle:getWheels()
    if wheels == nil or #wheels == 0 then return end

    local wetLevel, wet = nil, 0
    local s = self.CELL
    for _, wheel in ipairs(wheels) do
        if gtHasContact(wheel) and wheel.repr ~= nil and wheel.repr ~= 0 then
            local node = wheel.driveNode or wheel.repr
            local width = (wheel.physics ~= nil and type(wheel.physics.width) == "number") and wheel.physics.width or (wheel.width or 0.5)
            local half = math.max(0.1, width * 0.5)
            local lx, ly, lz = localToLocal(node, wheel.repr, 0, 0, 0)
            -- points répartis sur la largeur du pneu, tous les CELL mètres
            local n = math.max(1, math.ceil(width / s))
            for i = 0, n do
                local off = -half + (2 * half) * (i / n)
                local wx, _, wz = localToWorld(wheel.repr, lx + off, ly, lz)
                if wetLevel == nil then wetLevel, wet = self:getWetLevel(root) end
                self:processCell(math.floor(wx / s), math.floor(wz / s), root.rootNode or root, now, kph, wetLevel, wet)
            end
        end
    end
end

-- Oublie les carrés trop anciens pour ne pas grossir la mémoire
function AS_GrassTrample:cleanup(now)
    local removed = 0
    for key, cell in pairs(self.cells) do
        if now - cell.t > self.PASS_MS then
            self.cells[key] = nil
            removed = removed + 1
        end
    end
    self.cellCount = math.max(0, self.cellCount - removed)
end

-------------------------------------------------------------------------------
function AS_GrassTrample:loadMap()
    self:hookMsp()
end

function AS_GrassTrample:update(dt)
    if not self.ENABLED then return end
    if not self.mspHooked and (self.retries or 0) < 20 then
        self.retryTimer = (self.retryTimer or 0) + (dt or 0)
        if self.retryTimer >= 500 then
            self.retryTimer = 0
            self.retries = (self.retries or 0) + 1
            self:hookMsp()
        end
    end
    if g_server == nil or g_currentMission == nil or g_terrainNode == nil then return end
    if self.grassTypes == nil then
        local ok, err = pcall(self.loadGrassTypes, self)
        if not ok then
            print("[AS_Grass] ERREUR : " .. tostring(err))
            self.grassTypes = {}
        end
    end
    if #self.grassTypes == 0 then return end

    local now = g_time or 0
    for _, vehicle in pairs(getVehicles()) do
        local ok, err = pcall(self.processVehicle, self, vehicle, now)
        if not ok and not self.errShown then
            self.errShown = true
            print("[AS_Grass] ERREUR : " .. tostring(err))
        end
    end

    self.cleanTimer = (self.cleanTimer or 0) + (dt or 0)
    if self.cleanTimer >= 5000 or self.cellCount > 20000 then
        self.cleanTimer = 0
        self:cleanup(now)
    end
end

addModEventListener(AS_GrassTrample)
