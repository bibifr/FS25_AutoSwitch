-- AutoSwitch : traces de pneus gardées avec la partie
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo = AS.vtpInfo

-------------------------------------------------------------------------------
-- v1.0.0.03 : le jeu ne sauvegarde pas les traces de pneus, elles disparaissent
--   au rechargement. Ce module note les points de trace dessinés pendant la
--   partie (TireTrackSystem:addTrackPoint), les écrit quand le jeu sauvegarde
--   (savegameX/autoSwitchTireTracks.xml) et les redessine au chargement.
--   Seuls les MAX_POINTS points les plus récents sont gardés, un point tous les
--   MIN_STEP mètres au plus. Partie solo ou hôte uniquement (les traces sont
--   dessinées sur la machine qui sauvegarde).
-------------------------------------------------------------------------------
AS_TireTracksSave = {}
AS_TireTracksSave.MAX_POINTS     = 20000
AS_TireTracksSave.MIN_STEP       = 0.5    -- m entre deux points gardés
AS_TireTracksSave.RESTORE_DELAY  = 3000   -- ms après le chargement
AS_TireTracksSave.RESTORE_BATCH  = 2000   -- points redessinés par image
AS_TireTracksSave.FILE_NAME      = "autoSwitchTireTracks.xml"

AS_TireTracksSave.segments = {}      -- liste de { w, atlas, pts = { {14 valeurs}, ... } }, du plus ancien au plus récent
AS_TireTracksSave.current = {}       -- [index de trace] = segment en cours
AS_TireTracksSave.trackInfo = {}     -- [index de trace] = { w, atlas }
AS_TireTracksSave.pointCount = 0
AS_TireTracksSave.hookedSystem = nil
AS_TireTracksSave.replaying = false
AS_TireTracksSave.restoreState = nil -- nil = à faire, "running", "done"
AS_TireTracksSave.timer = 0

local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_TireTracksSave.FILE_NAME
end

local function getSystem()
    return g_currentMission ~= nil and g_currentMission.tireTrackSystem or nil
end

-- Largeur et texture d'une trace créée avant nos crochets : on la retrouve sur les véhicules
function AS_TireTracksSave:findTrackInfo(index)
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then return nil end
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
        for _, spec in ipairs({ vehicle.spec_tireTracks or false, vehicle.spec_wheels or false }) do
            if spec and spec.tireTrackNodes ~= nil then
                for _, node in pairs(spec.tireTrackNodes) do
                    local w = node.width or node.tireTrackWidth
                    if node.tireTrackIndex == index and w ~= nil then
                        local info = { w = w, atlas = node.atlasIndex or node.tireTrackAtlasIndex or 0 }
                        self.trackInfo[index] = info
                        return info
                    end
                end
            end
        end
    end
    return nil
end

function AS_TireTracksSave:dropOldest()
    while self.pointCount > self.MAX_POINTS and #self.segments > 0 do
        local seg = self.segments[1]
        local excess = self.pointCount - self.MAX_POINTS
        if #seg.pts > excess + 1 then
            -- on raccourcit la plus ancienne trace par le début
            local kept = {}
            for k = excess + 1, #seg.pts do kept[#kept + 1] = seg.pts[k] end
            seg.pts = kept
            self.pointCount = self.pointCount - excess
        else
            table.remove(self.segments, 1)
            self.pointCount = self.pointCount - #seg.pts
            for index, cur in pairs(self.current) do
                if cur == seg then self.current[index] = nil end
            end
        end
    end
end

function AS_TireTracksSave:record(index, x, y, z, ux, uy, uz, r, g, b, dirt, depth, dir, isTerrain, blend)
    if index == nil or x == nil then return end
    local seg = self.current[index]
    if seg == nil then
        local info = self.trackInfo[index] or self:findTrackInfo(index)
        if info == nil then return end
        seg = { w = info.w, atlas = info.atlas, pts = {} }
        self.current[index] = seg
        table.insert(self.segments, seg)
    end
    local last = seg.pts[#seg.pts]
    if last ~= nil then
        local dx, dz = x - last[1], z - last[3]
        if dx * dx + dz * dz < self.MIN_STEP * self.MIN_STEP then return end
    end
    table.insert(seg.pts, { x, y, z, ux or 0, uy or 1, uz or 0, r or 0, g or 0, b or 0,
        dirt or 0, depth or 0, dir or 1, (isTerrain == false) and 0 or 1, blend or 0 })
    self.pointCount = self.pointCount + 1
    if self.pointCount > self.MAX_POINTS then
        self:dropOldest()
    end
end

-- Remplace les fonctions de traces sur la classe TireTrackSystem (dès le chargement du mod,
-- avant que les véhicules créent leurs traces) ou, à défaut, sur l'objet de la partie.
function AS_TireTracksSave:hook(sys)
    if self.hookedSystem == sys or self.classHooked then return end
    self.hookedSystem = sys
    local origCreate, origAdd, origCut, origDestroy = sys.createTrack, sys.addTrackPoint, sys.cutTrack, sys.destroyTrack
    if origAdd == nil or origCut == nil then return end
    local mod = self
    if origCreate ~= nil then
        sys.createTrack = function(s, width, atlasIndex, ...)
            local index = origCreate(s, width, atlasIndex, ...)
            if index ~= nil then
                mod.trackInfo[index] = { w = width, atlas = atlasIndex or 0 }
                mod.current[index] = nil
            end
            return index
        end
    end
    sys.addTrackPoint = function(s, index, ...)
        if not mod.replaying then
            pcall(mod.record, mod, index, ...)
        end
        return origAdd(s, index, ...)
    end
    sys.cutTrack = function(s, index, ...)
        if not mod.replaying then mod.current[index] = nil end
        return origCut(s, index, ...)
    end
    if origDestroy ~= nil then
        sys.destroyTrack = function(s, index, ...)
            if not mod.replaying then
                mod.current[index] = nil
                mod.trackInfo[index] = nil
            end
            return origDestroy(s, index, ...)
        end
    end
    vtpInfo("[AS_TireTracksSave] traces de pneus suivies")
end

if TireTrackSystem ~= nil and TireTrackSystem.addTrackPoint ~= nil and TireTrackSystem.cutTrack ~= nil then
    AS_TireTracksSave:hook(TireTrackSystem)
    AS_TireTracksSave.classHooked = true
end

-------------------------------------------------------------------------------
-- Sauvegarde / chargement
-------------------------------------------------------------------------------
local function fmt(v)
    return string.format("%.2f", v):gsub("%.?0+$", "")
end

function AS_TireTracksSave:save()
    if g_server == nil then return end
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asTireTracks", path, "tireTracks")
    if xml == nil or xml == 0 then return end
    setXMLInt(xml, "tireTracks#version", 1)
    local i = 0
    for _, seg in ipairs(self.segments) do
        if #seg.pts >= 2 then
            local key = string.format("tireTracks.segment(%d)", i)
            setXMLFloat(xml, key .. "#width", seg.w)
            setXMLInt(xml, key .. "#atlas", seg.atlas)
            local parts = {}
            for _, p in ipairs(seg.pts) do
                local vals = {}
                for k = 1, 14 do vals[k] = fmt(p[k]) end
                parts[#parts + 1] = table.concat(vals, ",")
            end
            setXMLString(xml, key .. "#points", table.concat(parts, ";"))
            i = i + 1
        end
    end
    saveXMLFile(xml)
    delete(xml)
    vtpInfo(string.format("[AS_TireTracksSave] %d points de traces sauvegardés", self.pointCount))
end

function AS_TireTracksSave:load()
    local path = savegamePath()
    if path == nil or not fileExists(path) then return {} end
    local xml = loadXMLFile("asTireTracks", path)
    if xml == nil or xml == 0 then return {} end
    local list, i = {}, 0
    while true do
        local key = string.format("tireTracks.segment(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local seg = { w = getXMLFloat(xml, key .. "#width") or 0.5, atlas = getXMLInt(xml, key .. "#atlas") or 0, pts = {} }
        for chunk in string.gmatch(getXMLString(xml, key .. "#points") or "", "[^;]+") do
            local p = {}
            for v in string.gmatch(chunk, "[^,]+") do p[#p + 1] = tonumber(v) or 0 end
            if #p == 14 then seg.pts[#seg.pts + 1] = p end
        end
        if #seg.pts >= 2 then list[#list + 1] = seg end
        i = i + 1
    end
    delete(xml)
    return list
end

-- Redessine les traces sauvegardées, quelques milliers de points par image
function AS_TireTracksSave:startRestore(sys)
    local list = self:load()
    self.restoreState = "running"
    self.restore = { list = list, segIdx = 1, ptIdx = 1, handles = {} }
    -- les traces redessinées repartent dans la mémoire, pour la prochaine sauvegarde
    for _, seg in ipairs(list) do
        table.insert(self.segments, seg)
        self.pointCount = self.pointCount + #seg.pts
    end
    self:dropOldest()
end

function AS_TireTracksSave:stepRestore(sys)
    local r = self.restore
    local budget = self.RESTORE_BATCH
    self.replaying = true
    while budget > 0 and r.segIdx <= #r.list do
        local seg = r.list[r.segIdx]
        local hk = string.format("%.3f_%d", seg.w, seg.atlas)
        local handle = r.handles[hk]
        if handle == nil then
            handle = sys:createTrack(seg.w, seg.atlas)
            r.handles[hk] = handle or false
        end
        if not handle then
            r.segIdx, r.ptIdx = r.segIdx + 1, 1
        else
            local p = seg.pts[r.ptIdx]
            sys:addTrackPoint(handle, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9],
                p[10], p[11], p[12], p[13] == 1, p[14])
            budget = budget - 1
            r.ptIdx = r.ptIdx + 1
            if r.ptIdx > #seg.pts then
                sys:cutTrack(handle)
                r.segIdx, r.ptIdx = r.segIdx + 1, 1
            end
        end
    end
    self.replaying = false
    if r.segIdx > #r.list then
        self.restoreState = "done"
        local n = 0
        for _, seg in ipairs(r.list) do n = n + #seg.pts end
        if n > 0 then
            vtpInfo(string.format("[AS_TireTracksSave] %d points de traces redessinés", n))
        end
    end
end

function AS_TireTracksSave:update(dt)
    local sys = getSystem()
    if sys == nil or sys.addTrackPoint == nil then return end
    self:hook(sys)
    if self.restoreState == "done" or g_server == nil then return end
    if self.restoreState == nil then
        self.timer = self.timer + (dt or 0)
        if self.timer < self.RESTORE_DELAY then return end
        local ok, err = pcall(self.startRestore, self, sys)
        if not ok then
            print("[AS_TireTracksSave] ERREUR chargement : " .. tostring(err))
            self.restoreState = "done"
            return
        end
    end
    local ok, err = pcall(self.stepRestore, self, sys)
    if not ok then
        self.replaying = false
        self.restoreState = "done"
        print("[AS_TireTracksSave] ERREUR redessin : " .. tostring(err))
    end
end

function AS_TireTracksSave:deleteMap()
    self.segments, self.current, self.trackInfo = {}, {}, {}
    self.pointCount, self.timer = 0, 0
    if not self.classHooked then self.hookedSystem = nil end
    self.restoreState, self.restore = nil, nil
    self.replaying = false
end

-- écriture au moment où le jeu sauvegarde la partie
if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_TireTracksSave.save, AS_TireTracksSave)
        if not ok then print("[AS_TireTracksSave] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

addModEventListener(AS_TireTracksSave)
