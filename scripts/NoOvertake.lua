-- AutoSwitch : les voitures du trafic ne doublent plus les tracteurs
-- Fichier chargé par AutoSwitch.lua (après Common.lua, avant Settings.lua).

-------------------------------------------------------------------------------
-- v1.0.0.84 : le jeu sait arrêter ses voitures à un endroit d'une ligne du trafic
--   (setTrafficSystemBlockingPositionState, comme le mod No Overtake Splines de
--   Razak, qui ne le fait que sur les tronçons marqués par le mappeur).
--   Ici, sur toutes les routes du trafic : toutes les 0,5 s, chaque véhicule à
--   moteur qui roule sur une route reçoit une « barrière » BLOCK_GAP mètres derrière
--   son dernier outil, sur la ligne de sa voie (même sens que lui). Les voitures
--   restent derrière et ne doublent plus.
--   Pas de barrière s'il est arrêté depuis STOP_MS, s'il recule ou s'il a les
--   warnings allumés : les voitures peuvent alors passer.
--   Aussi sur les systèmes de trafic ajoutés par Traffic Density Control.
--   Serveur seulement (le trafic tourne sur le serveur).
-------------------------------------------------------------------------------
AS_NoOvertake = {}
AS_NoOvertake.ENABLED    = true
AS_NoOvertake.SCAN_MS    = 500
AS_NoOvertake.SAMPLE     = 3       -- m entre deux points d'une ligne du trafic
AS_NoOvertake.LANE_DIST  = 4       -- m max entre l'arrière du véhicule et la ligne
AS_NoOvertake.MIN_DOT    = 0.5     -- même sens que la ligne (cos 60°)
AS_NoOvertake.CELL       = 25
AS_NoOvertake.BLOCK_GAP  = 8       -- m derrière le dernier outil
AS_NoOvertake.STOP_KMH   = 2
AS_NoOvertake.STOP_MS    = 10000
AS_NoOvertake.RETRY_MS   = 10000   -- nouvel essai si aucune route trouvée
AS_NoOvertake.MAX_TRIES  = 6

AS_NoOvertake.timer    = 0
AS_NoOvertake.loaded   = false
AS_NoOvertake.tries    = 0
AS_NoOvertake.retry    = 0
AS_NoOvertake.splines  = {}
AS_NoOvertake.grid     = {}
AS_NoOvertake.active   = {}   -- barrières posées : { splineId, time }
AS_NoOvertake.stopped  = {}   -- véhicule -> ms à l'arrêt

-------------------------------------------------------------------------------
-- Lignes du trafic
-------------------------------------------------------------------------------

local function isSpline(node)
    if I3DUtil ~= nil and I3DUtil.getIsSpline ~= nil then
        return I3DUtil.getIsSpline(node)
    end
    local ok, length = pcall(getSplineLength, node)
    return ok and type(length) == "number" and length > 0
end

local function cellKey(x, z)
    local c = AS_NoOvertake.CELL
    return math.floor(x / c) * 100000 + math.floor(z / c)
end

function AS_NoOvertake:addSpline(splineId)
    local length = getSplineLength(splineId)
    if length == nil or length < 1 then return end
    local n = math.max(1, math.ceil(length / self.SAMPLE))
    local sp = { id = splineId, length = length }
    local px, _, pz = getSplinePosition(splineId, 0)
    for i = 1, n do
        local t = i / n
        local x, _, z = getSplinePosition(splineId, t)
        local dx, dz = x - px, z - pz
        local l2 = dx * dx + dz * dz
        if l2 > 0.0001 then
            local l = math.sqrt(l2)
            local seg = { sp = sp, x1 = px, z1 = pz, dx = dx, dz = dz, l2 = l2,
                          ux = dx / l, uz = dz / l, t1 = (i - 1) / n, t2 = t }
            -- dans toutes les cases touchées (marge de LANE_DIST)
            local m = self.LANE_DIST
            for cx = math.floor((math.min(px, x) - m) / self.CELL), math.floor((math.max(px, x) + m) / self.CELL) do
                for cz = math.floor((math.min(pz, z) - m) / self.CELL), math.floor((math.max(pz, z) + m) / self.CELL) do
                    local key = cx * 100000 + cz
                    local cell = self.grid[key]
                    if cell == nil then
                        cell = {}
                        self.grid[key] = cell
                    end
                    cell[#cell + 1] = seg
                end
            end
        end
        px, pz = x, z
    end
    self.splines[#self.splines + 1] = sp
end

function AS_NoOvertake:collect(node, depth)
    if node == nil or node == 0 or depth > 10 then return end
    if isSpline(node) then
        self:addSpline(node)
    end
    for i = 0, getNumOfChildren(node) - 1 do
        self:collect(getChildAt(node, i), depth + 1)
    end
end

function AS_NoOvertake:load()
    local ts = g_currentMission ~= nil and g_currentMission.trafficSystem or nil
    if ts == nil or ts.rootNodeId == nil or ts.rootNodeId == 0 then return false end
    self.splines, self.grid = {}, {}
    self:collect(ts.rootNodeId, 0)
    self.tries = self.tries + 1
    local total = 0
    for _, sp in ipairs(self.splines) do total = total + sp.length end
    print(string.format("[AutoSwitch] dépassement : %d lignes du trafic (%.1f km)", #self.splines, total / 1000))
    return #self.splines > 0
end

-- ligne de la voie sous (x, z), dans le sens (hx, hz) : spline, temps
function AS_NoOvertake:findLane(x, z, hx, hz)
    local cell = self.grid[cellKey(x, z)]
    if cell == nil then return nil end
    local best, bestT, bestD = nil, nil, self.LANE_DIST * self.LANE_DIST
    for _, s in ipairs(cell) do
        if s.ux * hx + s.uz * hz >= self.MIN_DOT then
            local f = ((x - s.x1) * s.dx + (z - s.z1) * s.dz) / s.l2
            f = math.max(0, math.min(1, f))
            local ex, ez = x - (s.x1 + f * s.dx), z - (s.z1 + f * s.dz)
            local d = ex * ex + ez * ez
            if d <= bestD then
                best, bestD = s.sp, d
                bestT = s.t1 + (s.t2 - s.t1) * f
            end
        end
    end
    return best, bestT
end

-------------------------------------------------------------------------------
-- Systèmes de trafic (jeu + Traffic Density Control)
-------------------------------------------------------------------------------

local function gameGlobals()
    local mt = getmetatable(_G)
    if mt ~= nil and type(mt.__index) == "table" then return mt.__index end
    return _G
end

local function getDensityControl()
    local G = gameGlobals()
    local tdc = rawget(G, "TrafficDensityControl") or rawget(G, "FS25_TrafficDensityControlInstance")
    if tdc == nil then
        local env = rawget(G, "FS25_TrafficDensityControl")
        if type(env) == "table" then tdc = env.TrafficDensityControl end
    end
    return tdc
end

function AS_NoOvertake:getSystemIds()
    local ids, seen = {}, {}
    local function add(id)
        if id ~= nil and id ~= 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local m = g_currentMission
    if m ~= nil and m.trafficSystem ~= nil then add(m.trafficSystem.trafficSystemId) end
    local tdc = getDensityControl()
    if type(tdc) == "table" and type(tdc.auxTrafficSystems) == "table" then
        for _, aux in ipairs(tdc.auxTrafficSystems) do
            if type(aux) == "table" then add(aux.trafficSystemId) end
        end
    end
    if m ~= nil and type(m.fs25TrafficDensityControlAuxTrafficSystems) == "table" then
        for _, aux in ipairs(m.fs25TrafficDensityControlAuxTrafficSystems) do
            if type(aux) == "table" then add(aux.trafficSystemId) end
        end
    end
    return ids
end

function AS_NoOvertake:setBlock(b, state)
    if setTrafficSystemBlockingPositionState == nil then return end
    for _, id in ipairs(self.systemIds or {}) do
        pcall(setTrafficSystemBlockingPositionState, id, b.splineId, b.time, state)
    end
end

function AS_NoOvertake:clear()
    for _, b in ipairs(self.active) do self:setBlock(b, false) end
    self.active = {}
end

-------------------------------------------------------------------------------
-- Véhicules
-------------------------------------------------------------------------------

-- le véhicule laisse-t-il passer les voitures ?
function AS_NoOvertake:letsPass(v, dt)
    local speed = v.getLastSpeed ~= nil and math.abs(v:getLastSpeed() or 0) or 0
    if speed < self.STOP_KMH then
        self.stopped[v] = (self.stopped[v] or 0) + dt
    else
        self.stopped[v] = nil
    end
    if (self.stopped[v] or 0) >= self.STOP_MS then return true end
    if v.movingDirection ~= nil and v.movingDirection < 0 and speed >= self.STOP_KMH then return true end
    if v.getTurnLightState ~= nil and Lights ~= nil and Lights.TURNLIGHT_HAZARD ~= nil
        and v:getTurnLightState() == Lights.TURNLIGHT_HAZARD then
        return true
    end
    return false
end

-- point arrière du convoi (dernier outil), sens de marche
local function rearPoint(v)
    local x, _, z = getWorldTranslation(v.rootNode)
    local hx, _, hz = localDirectionToWorld(v.rootNode, 0, 0, 1)
    local l = math.sqrt(hx * hx + hz * hz)
    if l < 0.01 then return nil end
    hx, hz = hx / l, hz / l
    local back = -((v.size ~= nil and v.size.length or 6) * 0.5)
    local children = v.childVehicles
    if children == nil and v.getChildVehicles ~= nil then children = v:getChildVehicles() end
    for _, c in ipairs(children or {}) do
        if c ~= v and c.rootNode ~= nil and c.rootNode ~= 0 then
            local cx, _, cz = getWorldTranslation(c.rootNode)
            local p = (cx - x) * hx + (cz - z) * hz - ((c.size ~= nil and c.size.length or 4) * 0.5)
            if p < back then back = p end
        end
    end
    return x + hx * back, z + hz * back, hx, hz
end

function AS_NoOvertake:update(dt)
    local m = g_currentMission
    if m == nil or (m.getIsServer ~= nil and not m:getIsServer()) then return end
    dt = dt or 0
    if not self.loaded then
        if self.tries >= self.MAX_TRIES then return end
        self.retry = self.retry - dt
        if self.retry > 0 then return end
        self.retry = self.RETRY_MS
        self.loaded = self:load()
        if not self.loaded then return end
    end
    self.timer = self.timer + dt
    if self.timer < self.SCAN_MS then return end
    local step = self.timer
    self.timer = 0

    self:clear()
    if not self.ENABLED then
        self.stopped = {}
        return
    end
    self.systemIds = self:getSystemIds()
    if #self.systemIds == 0 then return end

    local vehicles = m.vehicleSystem ~= nil and m.vehicleSystem.vehicles or m.vehicles or {}
    for _, v in pairs(vehicles) do
        if v ~= nil and not v.isDeleted and v.spec_motorized ~= nil and v.rootNode ~= nil and v.rootNode ~= 0
            and (v.rootVehicle == nil or v.rootVehicle == v) then
            if not self:letsPass(v, step) then
                local rx, rz, hx, hz = rearPoint(v)
                if rx ~= nil then
                    local sp, t = self:findLane(rx, rz, hx, hz)
                    if sp ~= nil then
                        local bt = t - self.BLOCK_GAP / sp.length
                        if bt > 0.001 then
                            local b = { splineId = sp.id, time = bt }
                            self:setBlock(b, true)
                            self.active[#self.active + 1] = b
                        end
                    end
                end
            end
        end
    end
end

function AS_NoOvertake:deleteMap()
    self:clear()
    self.loaded, self.tries, self.retry, self.timer = false, 0, 0, 0
    self.splines, self.grid, self.stopped = {}, {}, {}
end

function AS_NoOvertake:setEnabled(on)
    self.ENABLED = on == true
end

addModEventListener(AS_NoOvertake)
