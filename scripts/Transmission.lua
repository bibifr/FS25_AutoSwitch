-- AutoSwitch : transmission réelle de chaque machine (v1.0.0.56)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).
--
-- On suit les différentiels que le jeu utilise vraiment (après MoreRealistic, qui en retire
-- sur certaines machines : Lexion 6900 « 2WD in game ») : depuis le différentiel branché au
-- moteur (celui qu'aucun autre ne référence) jusqu'aux roues entraînées. La position des
-- roues entraînées donne le résultat : "4x4", "front" (pont avant seul) ou "rear".
-- Un différentiel qui en relie deux autres n'est pas forcément un central (jumelées avant
-- d'une moissonneuse), d'où le calcul par roues et non par forme.
--
-- Chaque machine est inscrite dans modSettings/FS25_AutoSwitch/transmissions.xml :
--   <vehicle xml="..." name="..." detected="front" forced=""/>
-- forced ("4x4", "front" ou "rear"), rempli à la main, l'emporte sur detected.

local getVehicles, vtpInfo = AS.getVehicles, AS.vtpInfo

AS_Trans = {}
AS_Trans.VALUES = { ["4x4"] = true, front = true, rear = true }
AS_Trans.SAVE_DELAY_MS = 2000
AS_Trans.SCAN_MS = 2000
AS_Trans.entries = {}      -- par fichier de machine
AS_Trans.order = {}        -- ordre d'inscription (fichier lisible)
AS_Trans.cache = setmetatable({}, { __mode = "k" })
AS_Trans.loaded = false
AS_Trans.dirty = false

local function filePath()
    local dir = (AS_Settings ~= nil and AS_Settings.MOD_DIR_NAME) or g_currentModName or "FS25_AutoSwitch"
    return getUserProfileAppPath() .. "modSettings/" .. dir .. "/", "transmissions.xml"
end

function AS_Trans:load()
    if self.loaded then return end
    self.loaded = true
    local dir, name = filePath()
    local path = dir .. name
    if not fileExists(path) then return end
    local xml = loadXMLFile("asTransmissions", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("transmissions.vehicle(%d)", i)
        local file = getXMLString(xml, key .. "#xml")
        if file == nil then break end
        if self.entries[file] == nil then
            local forced = getXMLString(xml, key .. "#forced") or ""
            if not self.VALUES[forced] then forced = "" end
            self.entries[file] = {
                xml = file,
                name = getXMLString(xml, key .. "#name") or "",
                detected = getXMLString(xml, key .. "#detected") or "",
                forced = forced,
            }
            table.insert(self.order, file)
        end
        i = i + 1
    end
    delete(xml)
end

function AS_Trans:save()
    local dir, name = filePath()
    local ok, err = pcall(function()
        createFolder(getUserProfileAppPath() .. "modSettings/")
        createFolder(dir)
        local xml = createXMLFile("asTransmissions", dir .. name, "transmissions")
        if xml == nil or xml == 0 then return end
        setXMLString(xml, "transmissions#info", "forced = 4x4 / front / rear pour corriger une machine")
        for i, file in ipairs(self.order) do
            local e = self.entries[file]
            local key = string.format("transmissions.vehicle(%d)", i - 1)
            setXMLString(xml, key .. "#name", e.name or "")
            setXMLString(xml, key .. "#xml", e.xml)
            setXMLString(xml, key .. "#detected", e.detected or "")
            setXMLString(xml, key .. "#forced", e.forced or "")
        end
        saveXMLFile(xml)
        delete(xml)
    end)
    if not ok then print("[AS_Trans] enregistrement impossible : " .. tostring(err)) end
    self.dirty = false
end

-- Roues entraînées depuis le différentiel moteur ; nil si la chaîne est illisible
local function drivenWheels(diffs)
    local referenced = {}
    for _, d in ipairs(diffs) do
        if d.diffIndex1IsWheel ~= true and type(d.diffIndex1) == "number" then referenced[d.diffIndex1 + 1] = true end
        if d.diffIndex2IsWheel ~= true and type(d.diffIndex2) == "number" then referenced[d.diffIndex2 + 1] = true end
    end
    local root
    for i = 1, #diffs do
        if not referenced[i] then
            if root ~= nil then return nil end   -- plusieurs racines : illisible
            root = i
        end
    end
    if root == nil then return nil end

    local wheels, visiting, valid = {}, {}, true
    local function walk(index, isWheel)
        if not valid then return end
        if isWheel then
            if type(index) ~= "number" then valid = false return end
            wheels[index] = true   -- index de roue Lua (1 = première roue)
            return
        end
        if type(index) ~= "number" then valid = false return end
        local i = index + 1
        local d = diffs[i]
        if d == nil or visiting[i] then valid = false return end
        visiting[i] = true
        walk(d.diffIndex1, d.diffIndex1IsWheel == true)
        walk(d.diffIndex2, d.diffIndex2IsWheel == true)
        visiting[i] = nil
    end
    walk(root - 1, false)
    if not valid then return nil end
    return wheels
end

-- "4x4", "front", "rear" ou nil (indéterminé)
function AS_Trans.detect(v)
    local sm = v.spec_motorized
    local diffs = sm ~= nil and sm.differentials or nil
    local ws = v.spec_wheels
    if type(diffs) ~= "table" or #diffs == 0 or ws == nil or ws.wheels == nil or v.rootNode == nil then
        return nil
    end
    local driven = drivenWheels(diffs)
    if driven == nil then return nil end

    local zs, minZ, maxZ = {}, math.huge, -math.huge
    for i, wheel in ipairs(ws.wheels) do
        local n = wheel.repr or wheel.driveNode or wheel.node
        if n ~= nil and n ~= 0 then
            local ok, _, _, z = pcall(localToLocal, n, v.rootNode, 0, 0, 0)
            if ok and type(z) == "number" then
                zs[i] = z
                if z < minZ then minZ = z end
                if z > maxZ then maxZ = z end
            end
        end
    end
    if minZ == math.huge or maxZ - minZ < 0.5 then return nil end
    local midZ = (minZ + maxZ) * 0.5

    local front, rear = false, false
    for i in pairs(driven) do
        local z = zs[i]
        if z == nil then return nil end
        if z >= midZ then front = true else rear = true end
    end
    if front and rear then return "4x4" end
    if front then return "front" end
    if rear then return "rear" end
    return nil
end

-- Transmission retenue (forcée dans le fichier, sinon détectée) ; "4x4" si indéterminée
function AS_Trans:get(v)
    local c = self.cache[v]
    if c ~= nil then return c end
    self:load()
    local detected = self.detect(v)
    local file = v.configFileName
    local result = detected or "4x4"
    if file ~= nil then
        local e = self.entries[file]
        if e == nil then
            local name = v.getFullName ~= nil and v:getFullName() or (v.getName ~= nil and v:getName()) or ""
            e = { xml = file, name = name, detected = detected or "", forced = "" }
            self.entries[file] = e
            table.insert(self.order, file)
            self.dirty = true
            vtpInfo(string.format("[AS_Trans] %s : transmission %s", name, detected or "indéterminée"))
        elseif detected ~= nil and e.detected ~= detected then
            e.detected = detected
            self.dirty = true
        end
        if self.VALUES[e.forced] then result = e.forced end
    end
    self.cache[v] = result
    return result
end

function AS_Trans:update(dt)
    if g_currentMission == nil then return end
    -- inscription des machines chargées ou achetées
    self.scanTimer = (self.scanTimer or 0) + (dt or 0)
    if self.scanTimer >= self.SCAN_MS then
        self.scanTimer = 0
        for _, v in pairs(getVehicles()) do
            if v.spec_motorized ~= nil and self.cache[v] == nil then
                self:get(v)
            end
        end
    end
    if self.dirty then
        self.saveTimer = (self.saveTimer or 0) + (dt or 0)
        if self.saveTimer >= self.SAVE_DELAY_MS then
            self.saveTimer = 0
            self:save()
        end
    end
end

function AS_Trans:deleteMap()
    if self.dirty then self:save() end
    self.cache = setmetatable({}, { __mode = "k" })
    self.entries, self.order, self.loaded = {}, {}, false
end

function AS.is4wd(v) return AS_Trans:get(v) == "4x4" end
-- pont moteur d'une machine sans 4x4 : "front" ou "rear"
function AS.drivenAxle(v) return AS_Trans:get(v) end

addModEventListener(AS_Trans)
