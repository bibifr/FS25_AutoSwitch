-- AutoSwitch : fenêtre Champs (Ctrl droit + C, ou clic sur l'icône à gauche de la mini-météo)
-- Fichier chargé par AutoSwitch.lua (après Weather.lua).

-------------------------------------------------------------------------------
-- v1.0.1.4 (TEST) : une ligne par champ possédé :
--   Champ      numéro du jeu ; champs réunis (un seul contour de sol de champ)
--              affichés sur une seule ligne « Champ 12 (+13) »
--   Culture    culture et stade (FieldState du jeu, lu au point central du champ)
--   Semis      date notée par AutoSwitch quand un semoir travaille sur le champ
--   Engrais    date du dernier passage (engrais, engrais liquide, fumier, lisier, digestat)
--   Herbicide  date du dernier passage d'herbicide
--   Récolte    « Prêt », « Idéal » ou mois estimé (calendrier de récolte de la culture dans le jeu)
-- Le jeu ne garde aucune date : elles sont notées à partir de l'installation et
-- sauvegardées avec la partie (AutoSwitch_fields.xml). Un passage n'est noté que
-- quand au moins 10 % du champ a été travaillé (passages de bordure ignorés).
-------------------------------------------------------------------------------
AS_Fields = {}
AS_Fields.FILE_NAME     = "AutoSwitch_fields.xml"
AS_Fields.MIN_SHARE     = 0.10    -- part du champ à travailler pour noter une date
AS_Fields.GAP_DAYS      = 2       -- passages séparés de plus de 2 jours = nouveau passage
AS_Fields.REFRESH_MS    = 2000    -- liste recalculée toutes les 2 s, fenêtre ouverte
AS_Fields.ROWS          = 14
AS_Fields.DEBUG         = false   -- true : logs [AS_Champs] dans log.txt

AS_Fields.records = {}            -- [fieldId] = { sow = {date, fruit}, fert = {date, n}, herb = {date} }
AS_Fields.acc = {}                -- cumuls en cours [fieldId .. kind] = { m2, day, done }
AS_Fields.isOpen = false
AS_Fields.scroll = 0
AS_Fields.rows = nil
AS_Fields.lastCompute = -100000
AS_Fields.overlays = {}
AS_Fields.actionEventId = nil

local function log(fmt, ...)
    if AS_Fields.DEBUG then print("[AS_Champs] " .. string.format(fmt, ...)) end
end

-------------------------------------------------------------------------------
-- Textes (même méthode que le registre)
-------------------------------------------------------------------------------
local frenchCache = nil
local function isFrench()
    if frenchCache ~= nil then return frenchCache end
    local french, known = false, false
    if getLanguage ~= nil and getLanguageCode ~= nil then
        local ok, code = pcall(function() return getLanguageCode(getLanguage()) end)
        if ok and type(code) == "string" then
            known = true
            french = code:lower():sub(1, 2) == "fr"
        end
    end
    if not french and g_languageShortName ~= nil then
        known = true
        french = g_languageShortName == "fr"
    end
    if known and g_currentMission ~= nil then frenchCache = french end
    return french
end
local function T(fr, en)
    if isFrench() then return fr end
    return en
end

local function periodName(period)
    if g_i18n ~= nil and g_i18n.formatPeriod ~= nil then
        local ok, s = pcall(g_i18n.formatPeriod, g_i18n, period, false)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return T("Mois ", "Month ") .. tostring(period)
end

-------------------------------------------------------------------------------
-- Date du jeu
-------------------------------------------------------------------------------
local function gameDate()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return { mday = 0, period = 0, year = 0, dayInPeriod = 0 } end
    return {
        mday = env.currentMonotonicDay or env.currentDay or 0,
        period = env.currentPeriod or 0,
        year = env.currentYear or 0,
        dayInPeriod = env.currentDayInPeriod or 0,
    }
end

local function fmtDate(d)
    if d == nil then return nil end
    local s = string.format("%s%d %s", T("Jour ", "Day "), d.dayInPeriod or 0, periodName(d.period or 0))
    local now = gameDate()
    if (d.year or 0) ~= now.year then s = s .. string.format(" %s%d", T("an ", "y"), d.year or 0) end
    return s
end

-------------------------------------------------------------------------------
-- Champs du jeu
-------------------------------------------------------------------------------
local function fieldId(field)
    if field == nil then return nil end
    if field.getId ~= nil then
        local ok, id = pcall(field.getId, field)
        if ok and type(id) == "number" then return id end
    end
    if field.farmland ~= nil and type(field.farmland.id) == "number" then return field.farmland.id end
    return field.fieldId
end

local function getFields()
    local fm = g_fieldManager
    if fm == nil then return {} end
    if fm.getFields ~= nil then
        local ok, list = pcall(fm.getFields, fm)
        if ok and type(list) == "table" then return list end
    end
    return fm.fields or {}
end

local function fieldAt(x, z)
    if g_fieldManager ~= nil and g_fieldManager.getFieldAtWorldPosition ~= nil then
        local ok, f = pcall(g_fieldManager.getFieldAtWorldPosition, g_fieldManager, x, z)
        if ok and f ~= nil then return f end
    end
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandAtWorldPosition ~= nil then
        local ok, fl = pcall(g_farmlandManager.getFarmlandAtWorldPosition, g_farmlandManager, x, z)
        if ok and fl ~= nil and fl.field ~= nil then return fl.field end
    end
    return nil
end

local function farmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local ok, id = pcall(g_currentMission.getFarmId, g_currentMission)
        if ok and id ~= nil then return id end
    end
    return 1
end

local function isOwned(field)
    local fl = field.farmland
    if fl == nil then return false end
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandOwner ~= nil and fl.id ~= nil then
        local ok, owner = pcall(g_farmlandManager.getFarmlandOwner, g_farmlandManager, fl.id)
        if ok and owner ~= nil then return owner == farmId() end
    end
    return fl.isOwned == true
end

local function fieldArea(field)
    return math.max(0.01, tonumber(field.areaHa) or 1) * 10000
end

-- état du sol à un point (FieldState du jeu)
local probe = nil
local function stateAt(x, z)
    if FieldState == nil or FieldState.new == nil then return nil end
    if probe == nil then probe = FieldState.new() end
    local ok = pcall(probe.update, probe, x, z)
    if not ok then return nil end
    return {
        isValid = probe.isValid, fruit = probe.fruitTypeIndex, growth = probe.growthState or 0,
        groundType = probe.groundType, spray = probe.sprayLevel or 0, weed = probe.weedState or 0,
    }
end

-------------------------------------------------------------------------------
-- Passages notés (semoir, épandeur, pulvérisateur)
-------------------------------------------------------------------------------
local FERT_NAMES = { FERTILIZER = true, LIQUIDFERTILIZER = true, MANURE = true,
    LIQUIDMANURE = true, DIGESTATE = true }

local function fillTypeName(index)
    if index == nil or g_fillTypeManager == nil then return nil end
    local ft = g_fillTypeManager:getFillTypeByIndex(index)
    return ft ~= nil and ft.name or nil
end

local function pixelsToM2(area)
    if area == nil or area <= 0 or g_currentMission == nil then return 0 end
    local ok, ha = pcall(MathUtil.areaToHa, area, g_currentMission:getFruitPixelsToSqm())
    if ok and type(ha) == "number" then return ha * 10000 end
    return 0
end

-- ajoute m2 travaillés pour un type de passage ; note la date quand 10 % du champ est atteint
function AS_Fields:addWork(vehicle, kind, m2, extra)
    if m2 <= 0 or vehicle == nil or vehicle.rootNode == nil then return end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local field = fieldAt(x, z)
    local id = fieldId(field)
    if id == nil then return end
    local now = gameDate()
    local key = id .. ":" .. kind
    local a = self.acc[key]
    if a == nil or now.mday - a.day > self.GAP_DAYS or (extra ~= nil and a.extra ~= extra) then
        a = { m2 = 0, day = now.mday, done = false, extra = extra }
        self.acc[key] = a
    end
    a.m2 = a.m2 + m2
    a.day = now.mday
    if a.done or a.m2 < fieldArea(field) * self.MIN_SHARE then return end
    a.done = true
    local rec = self.records[id]
    if rec == nil then rec = {}; self.records[id] = rec end
    if kind == "sow" then
        rec.sow = { date = now, fruit = extra }
        rec.fert, rec.herb = nil, nil    -- nouvelle culture : on repart de zéro
        self.groupsDirty = true          -- un semis peut avoir réuni des champs
    elseif kind == "fert" then
        local n = (rec.fert ~= nil and rec.fert.n or 0) + 1
        rec.fert = { date = now, n = n, fill = extra }
    elseif kind == "herb" then
        rec.herb = { date = now }
    end
    self.rows = nil
    log("champ %s : %s noté (%s, %.0f m² sur %.0f)", tostring(id), kind, tostring(extra), a.m2, fieldArea(field))
end

if Sprayer ~= nil and Sprayer.onEndWorkAreaProcessing ~= nil then
    Sprayer.onEndWorkAreaProcessing = Utils.appendedFunction(Sprayer.onEndWorkAreaProcessing, function(self, dt)
        if not self.isServer then return end
        local spec = self.spec_sprayer
        local wap = spec ~= nil and spec.workAreaParameters or nil
        if wap == nil or not wap.isActive then return end
        local name = fillTypeName(wap.sprayFillType)
        if name == nil then return end
        local kind = nil
        if name == "HERBICIDE" then kind = "herb" elseif FERT_NAMES[name] then kind = "fert" end
        if kind == nil then return end
        local ok, err = pcall(AS_Fields.addWork, AS_Fields, self, kind, pixelsToM2(wap.lastTotalArea), name)
        if not ok then log("ERREUR pulvérisateur : %s", tostring(err)) end
    end)
    log("crochet pulvérisateur / épandeur posé")
end

if SowingMachine ~= nil and SowingMachine.onEndWorkAreaProcessing ~= nil then
    SowingMachine.onEndWorkAreaProcessing = Utils.appendedFunction(SowingMachine.onEndWorkAreaProcessing, function(self, dt)
        if not self.isServer then return end
        local spec = self.spec_sowingMachine
        local wap = spec ~= nil and spec.workAreaParameters or nil
        if wap == nil or (wap.lastChangedArea or 0) <= 0 then return end
        local ok, err = pcall(AS_Fields.addWork, AS_Fields, self, "sow", pixelsToM2(wap.lastChangedArea), wap.seedsFruitType)
        if not ok then log("ERREUR semoir : %s", tostring(err)) end
    end)
    log("crochet semoir posé")
end

-------------------------------------------------------------------------------
-- Sauvegarde
-------------------------------------------------------------------------------
local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_Fields.FILE_NAME
end

local function writeDate(xml, key, d)
    setXMLInt(xml, key .. "#day", d.mday or 0)
    setXMLInt(xml, key .. "#period", d.period or 0)
    setXMLInt(xml, key .. "#dayInPeriod", d.dayInPeriod or 0)
    setXMLInt(xml, key .. "#year", d.year or 0)
end

local function readDate(xml, key)
    if not hasXMLProperty(xml, key .. "#period") then return nil end
    return { mday = getXMLInt(xml, key .. "#day") or 0, period = getXMLInt(xml, key .. "#period") or 0,
        dayInPeriod = getXMLInt(xml, key .. "#dayInPeriod") or 0, year = getXMLInt(xml, key .. "#year") or 0 }
end

local function fruitName(index)
    local f = index ~= nil and g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(index) or nil
    return f ~= nil and f.name or nil
end

function AS_Fields:save()
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asFields", path, "fields")
    if xml == nil or xml == 0 then return end
    local i = 0
    for id, rec in pairs(self.records) do
        local key = string.format("fields.field(%d)", i)
        setXMLInt(xml, key .. "#id", id)
        if rec.sow ~= nil then
            writeDate(xml, key .. ".sow", rec.sow.date)
            local fn = fruitName(rec.sow.fruit)
            if fn ~= nil then setXMLString(xml, key .. ".sow#fruit", fn) end
        end
        if rec.fert ~= nil then
            writeDate(xml, key .. ".fert", rec.fert.date)
            setXMLInt(xml, key .. ".fert#n", rec.fert.n or 1)
            if rec.fert.fill ~= nil then setXMLString(xml, key .. ".fert#fill", rec.fert.fill) end
        end
        if rec.herb ~= nil then writeDate(xml, key .. ".herb", rec.herb.date) end
        i = i + 1
    end
    -- (v1.0.1.4) champs réunis, pour ne pas les recalculer à chaque chargement
    if self.groups ~= nil and self.groupsOwned ~= nil then
        setXMLString(xml, "fields.groups#owned", self.groupsOwned)
        setXMLBool(xml, "fields.groups#dirty", self.groupsDirty == true)
        local chosen = {}
        for id in pairs(self.chosenMain) do chosen[#chosen + 1] = tostring(id) end
        if #chosen > 0 then setXMLString(xml, "fields.groups#main", table.concat(chosen, " ")) end
        local k = 0
        for id, root in pairs(self.groups) do
            if id ~= root then
                setXMLString(xml, string.format("fields.groups.join(%d)#ids", k), id .. " " .. root)
                k = k + 1
            end
        end
    end
    saveXMLFile(xml)
    delete(xml)
end

function AS_Fields:load()
    self.records = {}
    local path = savegamePath()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("asFields", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("fields.field(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local id = getXMLInt(xml, key .. "#id")
        if id ~= nil then
            local rec = {}
            local d = readDate(xml, key .. ".sow")
            if d ~= nil then
                local fn = getXMLString(xml, key .. ".sow#fruit")
                local f = fn ~= nil and g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByName(fn) or nil
                rec.sow = { date = d, fruit = f ~= nil and f.index or nil }
            end
            d = readDate(xml, key .. ".fert")
            if d ~= nil then
                rec.fert = { date = d, n = getXMLInt(xml, key .. ".fert#n") or 1, fill = getXMLString(xml, key .. ".fert#fill") }
            end
            d = readDate(xml, key .. ".herb")
            if d ~= nil then rec.herb = { date = d } end
            self.records[id] = rec
        end
        i = i + 1
    end
    self.groups, self.groupsOwned, self.groupsDirty = nil, nil, false
    local owned = getXMLString(xml, "fields.groups#owned")
    if owned ~= nil then
        local groups = {}
        for id in owned:gmatch("%d+") do groups[tonumber(id)] = tonumber(id) end
        local k = 0
        while true do
            local v = getXMLString(xml, string.format("fields.groups.join(%d)#ids", k))
            if v == nil then break end
            local a, b = v:match("(%d+)%s+(%d+)")
            if a ~= nil then groups[tonumber(a)] = tonumber(b) end
            k = k + 1
        end
        self.groups, self.groupsOwned = groups, owned
        self.groupsDirty = getXMLBool(xml, "fields.groups#dirty") == true
        self.chosenMain = {}
        for id in (getXMLString(xml, "fields.groups#main") or ""):gmatch("%d+") do self.chosenMain[tonumber(id)] = true end
    end
    delete(xml)
    log("dates chargées pour %d champ(s), champs réunis %s", i, owned ~= nil and "repris de la sauvegarde" or "à calculer")
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_Fields.save, AS_Fields)
        if not ok then print("[AS_Champs] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

function AS_Fields:loadMap()
    local ok, err = pcall(self.load, self)
    if not ok then print("[AS_Champs] ERREUR chargement : " .. tostring(err)) end
    print("[AS_Champs] module Champs accroché (Ctrl droit + C)")
end

function AS_Fields:deleteMap()
    self.records, self.acc, self.rows = {}, {}, nil
    self.groups, self.groupsOwned, self.groupsDirty, self.job = nil, nil, false, nil
    self.chosenMain, self.expanded = {}, {}
    self.isOpen = false
end

-------------------------------------------------------------------------------
-- Calcul des lignes
-------------------------------------------------------------------------------

-- texte du sol sans culture, d'après le type de sol du jeu
local function groundText(gt)
    if gt == nil or FieldGroundType == nil then return T("Sans culture", "No crop") end
    for name, v in pairs(FieldGroundType) do
        if v == gt and type(name) == "string" then
            local n = name:upper()
            if n:find("PLOW") then return T("Labouré", "Plowed") end
            if n:find("CULTIVAT") then return T("Déchaumé", "Cultivated") end
            if n:find("STUBBLE") then return T("Chaume", "Stubble") end
            if n:find("SEEDBED") or n:find("ROLL") then return T("Prêt à semer", "Seedbed") end
            if n:find("GRASS") then return T("Herbe", "Grass") end
        end
    end
    return T("Sans culture", "No crop")
end

local function growthMode()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return mi ~= nil and mi.growthMode or nil
end

-- (v1.0.1.5) premier et dernier stade récoltable d'une culture, calculés une fois par culture
local harvestRanges = {}
local function harvestRange(fruit, q)
    local key = fruit.index or fruit.name
    local r = harvestRanges[key]
    if r == nil then
        r = {}
        local top = fruit.maxHarvestingGrowthState or 0
        if fruit.cutState ~= nil and fruit.cutState > 1 then top = math.max(top, fruit.cutState - 1) end
        for s = 1, math.min(top, 15) do
            if q("getIsHarvestable", s) and not q("getIsWithered", s) and not q("getIsCut", s) then
                if r.first == nil then r.first = s end
                r.last = s
            end
        end
        harvestRanges[key] = r
    end
    return r.first, r.last
end

-- récolte : texte, couleur (« ready », « dead », « wait », « none »)
local function harvestInfo(fruit, gs)
    if fruit == nil or gs == nil or gs <= 0 then return "-", "none" end
    local function q(name, ...)
        if fruit[name] == nil then return nil end
        local ok, v = pcall(fruit[name], fruit, ...)
        if ok then return v end
        return nil
    end
    if q("getIsWithered", gs) then return T("Fanée", "Withered"), "dead" end
    if q("getIsCut", gs) then return T("Récolté", "Harvested"), "done" end
    if q("getIsHarvestable", gs) or (fruit.minHarvestingGrowthState ~= nil and gs >= fruit.minHarvestingGrowthState
        and gs <= (fruit.maxHarvestingGrowthState or gs)) then
        -- (v1.0.1.5) culture récoltable sur plusieurs stades (ex. maïs ensilage) : le dernier est l'idéal
        local first, last = harvestRange(fruit, q)
        if first ~= nil and last ~= nil and first < last then
            if gs >= last then return T("Idéal", "Best"), "ready" end
            return string.format(T("Prêt (idéal %d/%d)", "Ready (best %d/%d)"), last, last), "ready"
        end
        return T("Prêt", "Ready"), "ready"
    end
    -- (v1.0.1.4) au-delà des stades de récolte : chaume, broyé ou roulé après la récolte
    if fruit.maxHarvestingGrowthState ~= nil and fruit.maxHarvestingGrowthState > 0 and gs > fruit.maxHarvestingGrowthState then
        return T("Récolté", "Harvested"), "done"
    end
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local cur = env ~= nil and env.currentPeriod or nil
    local mode = growthMode()
    if cur ~= nil and fruit.getIsHarvestableInPeriod ~= nil then
        for k = 1, 12 do
            local p = ((cur - 1 + k) % 12) + 1
            if q("getIsHarvestableInPeriod", mode, p) then
                return T("vers ", "about ") .. periodName(p), "wait"
            end
        end
    end
    return "-", "none"
end

local function fruitTitle(fruit)
    if fruit == nil then return nil end
    if fruit.fillType ~= nil and fruit.fillType.title ~= nil then return fruit.fillType.title end
    return tostring(fruit.name)
end

-------------------------------------------------------------------------------
-- (v1.0.1.4) Champs réunis : contour du sol de champ suivi une fois par champ, comme
-- l'ancien scanner de Courseplay (sans regarder le numéro du champ, donc un champ
-- réuni donne un seul contour). Un champ dont le centre est dans le contour d'un
-- autre fait partie du même groupe. Calcul étalé sur plusieurs images (PROBES_PER_FRAME
-- tests de sol au plus), gardé avec la partie, refait seulement si les champs possédés
-- changent ou après un semis.
-------------------------------------------------------------------------------
AS_Fields.GRID             = 2      -- m : pas du suivi de bord
AS_Fields.PROBES_PER_FRAME = 200
AS_Fields.MAX_TRACE_STEPS  = 8000
AS_Fields.groups = nil              -- [fieldId] = numéro du champ principal du groupe
AS_Fields.groupsOwned = nil         -- liste des champs possédés au moment du calcul (texte)
AS_Fields.groupsDirty = false
AS_Fields.job = nil
AS_Fields.chosenMain = {}         -- [fieldId] = true : champ principal choisi par le joueur
AS_Fields.expanded = {}           -- [groupe] = true : liste des champs dépliée
AS_Fields.nextCheck = 0

local N8 = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function isFieldGround(x, z)
    if FSDensityMapUtil ~= nil and FSDensityMapUtil.getFieldDataAtWorldPosition ~= nil and g_currentMission ~= nil then
        local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
        local ok, onField = pcall(FSDensityMapUtil.getFieldDataAtWorldPosition, x, y, z)
        if ok then return onField == true end
    end
    local st = stateAt(x, z)
    return st ~= nil and st.isValid and st.groundType ~= nil and st.groundType ~= 0
end

local function ownedList()
    local list = {}
    for _, field in ipairs(getFields()) do
        local id = fieldId(field)
        if id ~= nil and isOwned(field) then list[#list + 1] = { id = id, field = field } end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function ownedKey(list)
    local t = {}
    for i, o in ipairs(list) do t[i] = tostring(o.id) end
    return table.concat(t, " ")
end

local function pointInPolygon(x, z, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, zi, xj, zj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if ((zi > z) ~= (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then inside = not inside end
        j = i
    end
    return inside
end

local function polygonArea(poly)
    local a, j = 0, #poly
    for i = 1, #poly do
        a = a + (poly[j][1] + poly[i][1]) * (poly[j][2] - poly[i][2])
        j = i
    end
    return math.abs(a) * 0.5
end

-- prépare le suivi d'un champ (départ au centre, direction d)
local function newTrace(o, d)
    return { o = o, d = d or 1, phase = "walk", i = 0, j = 0, steps = 0, cells = {}, pts = {},
        x0 = o.field.posX or 0, z0 = o.field.posZ or 0 }
end

-- avance le suivi ; renvoie true quand le champ est fini (contour ou échec), et le nombre de tests faits
local function stepTrace(tr, budget)
    local G = AS_Fields.GRID
    local used = 0
    local function isF(i, j)
        local k = i .. "," .. j
        local v = tr.cells[k]
        if v == nil then
            v = isFieldGround(tr.x0 + i * G, tr.z0 + j * G)
            tr.cells[k] = v
            used = used + 1
        end
        return v
    end
    while used < budget do
        if tr.phase == "walk" then
            if tr.steps == 0 and not isF(0, 0) then return true, used end
            local di, dj = DIRS[tr.d][1], DIRS[tr.d][2]
            if isF(tr.i + di, tr.j + dj) and tr.steps < 2000 then
                tr.i, tr.j, tr.steps = tr.i + di, tr.j + dj, tr.steps + 1
            else
                tr.pi, tr.pj = tr.i, tr.j
                tr.bi, tr.bj = tr.i + di, tr.j + dj
                tr.si, tr.sj, tr.sbi, tr.sbj = tr.pi, tr.pj, tr.bi, tr.bj
                tr.phase, tr.steps = "trace", 0
            end
        else
            -- voisin de p par lequel on est arrivé (b), puis tour des 8 voisins dans le sens horaire
            local k0 = 1
            for k = 1, 8 do
                if tr.pi + N8[k][1] == tr.bi and tr.pj + N8[k][2] == tr.bj then k0 = k break end
            end
            local found = false
            local prevI, prevJ = tr.bi, tr.bj
            for n = 1, 8 do
                local k = ((k0 - 1 + n) % 8) + 1
                local ci, cj = tr.pi + N8[k][1], tr.pj + N8[k][2]
                if isF(ci, cj) then
                    tr.bi, tr.bj = prevI, prevJ
                    tr.pi, tr.pj = ci, cj
                    found = true
                    break
                end
                prevI, prevJ = ci, cj
            end
            if not found then return true, used end   -- une seule case de champ
            tr.steps = tr.steps + 1
            if tr.steps % 2 == 0 then tr.pts[#tr.pts + 1] = { tr.x0 + tr.pi * G, tr.z0 + tr.pj * G } end
            if (tr.pi == tr.si and tr.pj == tr.sj and tr.bi == tr.sbi and tr.bj == tr.sbj) or tr.steps > AS_Fields.MAX_TRACE_STEPS then
                tr.done = true
                return true, used
            end
        end
    end
    return false, used
end

function AS_Fields:startGroupJob(list)
    self.job = { list = list, index = 1, trace = nil, contours = {}, probes = 0, started = g_time }
    log("calcul des champs réunis lancé (%d champs possédés)", #list)
end

function AS_Fields:finishGroupJob()
    local job = self.job
    local list = job.list
    local parent = {}
    for _, o in ipairs(list) do parent[o.id] = o.id end
    local function find(x)
        while parent[x] ~= x do x = parent[x] end
        return x
    end
    for _, a in ipairs(list) do
        local poly = job.contours[a.id]
        if poly ~= nil then
            for _, b in ipairs(list) do
                if b.id ~= a.id and pointInPolygon(b.field.posX or 0, b.field.posZ or 0, poly) then
                    local ra, rb = find(a.id), find(b.id)
                    if ra ~= rb then
                        if ra < rb then parent[rb] = ra else parent[ra] = rb end
                    end
                end
            end
        end
    end
    local groups = {}
    for _, o in ipairs(list) do groups[o.id] = find(o.id) end
    self.groups = groups
    self.groupsOwned = ownedKey(list)
    self.groupsDirty = false
    self.job = nil
    self.rows = nil
    local txt = {}
    for _, o in ipairs(list) do
        if groups[o.id] ~= o.id then txt[#txt + 1] = o.id .. "->" .. groups[o.id] end
    end
    log("champs réunis : %s (%d tests de sol, %.1f s)", #txt > 0 and table.concat(txt, ", ") or "aucun",
        job.probes, (g_time - job.started) / 1000)
end

function AS_Fields:update(dt)
    if g_currentMission == nil or g_currentMission.environment == nil then return end
    local job = self.job
    if job == nil then
        if g_time < self.nextCheck then return end
        self.nextCheck = g_time + 5000
        local list = ownedList()
        if #list > 0 and (self.groups == nil or self.groupsDirty or self.groupsOwned ~= ownedKey(list)) then
            self:startGroupJob(list)
        end
        return
    end
    local budget = self.PROBES_PER_FRAME
    while budget > 0 and self.job ~= nil do
        local o = job.list[job.index]
        if o == nil then
            local ok, err = pcall(self.finishGroupJob, self)
            if not ok then log("ERREUR réunion : %s", tostring(err)); self.job = nil end
            return
        end
        if job.trace == nil then job.trace = newTrace(o, 1) end
        local ok, done, used = pcall(stepTrace, job.trace, budget)
        if not ok then
            log("ERREUR contour champ %s : %s", tostring(o.id), tostring(done))
            done, used = true, budget
        end
        used = used or budget
        budget = budget - used
        job.probes = job.probes + used
        if done then
            local tr = job.trace
            local area = (tr.done and #tr.pts >= 3) and polygonArea(tr.pts) or 0
            if area >= fieldArea(o.field) * 0.5 then
                job.contours[o.id] = tr.pts
                job.trace, job.index = nil, job.index + 1
            elseif tr.d < 4 and tr.steps > 0 then
                -- contour trop petit (îlot ou arbre dans le champ) : autre direction
                job.trace = newTrace(o, tr.d + 1)
            else
                log("champ %s : contour introuvable", tostring(o.id))
                job.trace, job.index = nil, job.index + 1
            end
        end
    end
end

local function laterDate(a, b)
    if a == nil then return b end
    if b == nil then return a end
    if (b.date.mday or 0) > (a.date.mday or 0) then return b end
    return a
end

local loggedStates = {}
function AS_Fields:compute()
    local owned = {}
    for _, o in ipairs(ownedList()) do
        o.st = stateAt(o.field.posX or 0, o.field.posZ or 0) or {}
        owned[#owned + 1] = o
    end
    -- groupes calculés (champ principal = plus petit numéro du groupe)
    local byRoot, order = {}, {}
    for _, o in ipairs(owned) do
        local root = self.groups ~= nil and self.groups[o.id] or o.id
        if byRoot[root] == nil then
            byRoot[root] = {}
            order[#order + 1] = root
        end
        table.insert(byRoot[root], o)
    end

    local rows = {}
    for _, root in ipairs(order) do
        local g = byRoot[root]
        local main = g[1]
        for _, m in ipairs(g) do if m.id == root then main = m end end
        for _, m in ipairs(g) do if self.chosenMain[m.id] then main = m end end
        local others = {}
        local sow, fert, herb = nil, nil, nil
        local area = 0
        for _, m in ipairs(g) do
            if m ~= main then others[#others + 1] = tostring(m.id) end
            local rec = self.records[m.id] or {}
            sow, fert, herb = laterDate(sow, rec.sow), laterDate(fert, rec.fert), laterDate(herb, rec.herb)
            area = area + fieldArea(m.field)
        end
        local st = main.st
        local fruit = nil
        if st.fruit ~= nil and st.fruit ~= 0 and g_fruitTypeManager ~= nil then
            fruit = g_fruitTypeManager:getFruitTypeByIndex(st.fruit)
        end
        local name = string.format("%s %d", T("Champ", "Field"), main.id)
        if #g > 1 then name = name .. string.format(T(" (%d champs)", " (%d fields)"), #g) end
        local members = {}
        for _, m in ipairs(g) do members[#members + 1] = { id = m.id, area = fieldArea(m.field), main = m == main } end
        local hText, hKind = harvestInfo(fruit, st.growth)
        local crop, stage = nil, "-"
        if fruit ~= nil then
            if hKind == "done" then
                crop, stage = fruitTitle(fruit), T("chaume", "stubble")
            else
                local maxG = (fruit.minHarvestingGrowthState or 1)
                crop, stage = fruitTitle(fruit), string.format("%d/%d", math.min(st.growth, maxG), maxG)
            end
            local key = main.id .. ":" .. tostring(fruit.name) .. ":" .. tostring(st.growth)
            if not loggedStates[key] then
                loggedStates[key] = true
                log("champ %d : %s stade %s (récolte %s-%s, coupé %s, fané %s) -> %s", main.id, tostring(fruit.name),
                    tostring(st.growth), tostring(fruit.minHarvestingGrowthState), tostring(fruit.maxHarvestingGrowthState),
                    tostring(fruit.cutState), tostring(fruit.witheredState), hText)
            end
        else
            crop = groundText(st.groundType)
        end
        rows[#rows + 1] = { name = name, area = area, key = root, members = members, isGroup = #g > 1, crop = crop, stage = stage, hasFruit = fruit ~= nil and hKind ~= "done",
            sow = sow, fert = fert, herb = herb, spray = st.spray, harvest = hText, hKind = hKind }
    end
    return rows
end

-------------------------------------------------------------------------------
-- Dessin
-------------------------------------------------------------------------------
local C = {
    white = { 1, 1, 1, 1 },
    gray  = { 0.70, 0.73, 0.78, 1 },
    title = { 1.00, 0.80, 0.30, 1 },
    green = { 0.55, 0.90, 0.45, 1 },
    red   = { 1.00, 0.45, 0.40, 1 },
    blue  = { 0.45, 0.72, 1.00, 1 },
}

local function uiScale()
    local s = 1
    if g_gameSettings ~= nil and g_gameSettings.getValue ~= nil then
        local ok, v = pcall(g_gameSettings.getValue, g_gameSettings, "uiScale")
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    return s
end

function AS_Fields:getIcon()
    local ov = self.overlays.icon
    if ov == nil then
        local path = Utils.getFilename("hud/as_fields.dds", AS_MOD_DIR)
        local ok, o = pcall(createImageOverlay, path)
        if ok and o ~= nil and o ~= 0 then ov = o else
            ov = false
            print("[AS_Champs] icône introuvable : " .. tostring(path))
        end
        self.overlays.icon = ov
    end
    return ov or nil
end

local function hasPF()
    return g_modIsLoaded ~= nil and g_modIsLoaded["FS25_precisionFarming"] == true
end

function AS_Fields:draw()
    self.iconBox = nil
    if g_currentMission == nil then return end
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then return end
    if self.isOpen then
        if self.rows == nil or g_time - self.lastCompute >= self.REFRESH_MS then
            self.lastCompute = g_time
            local ok, r = pcall(self.compute, self)
            if ok then self.rows = r elseif not self.loggedError then
                self.loggedError = true
                print("[AS_Champs] erreur : " .. tostring(r))
            end
        end
        local ok, err = pcall(self.drawPanel, self)
        if not ok and not self.loggedDrawError then
            self.loggedDrawError = true
            print("[AS_Champs] erreur d'affichage : " .. tostring(err))
        end
        return
    end
    local hud = g_currentMission.hud
    if hud ~= nil and hud.getIsVisible ~= nil and not hud:getIsVisible() then return end
    if (AS_Weather ~= nil and AS_Weather.isOpen) or (AS_Register ~= nil and AS_Register.isOpen) then return end
    pcall(self.drawIcon, self)
end

-- icône à gauche de la mini-météo (ou en haut à droite si la mini-météo est coupée)
function AS_Fields:drawIcon()
    local ov = self:getIcon()
    if ov == nil then return end
    local sc = uiScale()
    local aspect = (g_screenWidth or 1920) / math.max(1, g_screenHeight or 1080)
    local function py(px) return px * sc / 1080 end
    local function pxw(px) return py(px) / aspect end
    local row3H = py(22)
    local h = py(48)
    local wb = AS_Weather ~= nil and AS_Weather.widgetBox or nil
    local x, ytop
    if wb ~= nil then
        h = math.min(py(64), math.max(py(36), wb.h - row3H))
        ytop = wb.y + wb.h
        x = wb.x - pxw(8)
    else
        ytop = 1 - py(20)
        x = 1 - pxw(560)
    end
    -- (v1.0.1.7) sous l'icône : flèche vers le haut et « Clique-moi », comme la mini-météo
    local hint = AS.L ~= nil and AS.L("vtpas_wx_clickMe") or "Click me"
    setTextBold(true)
    local tw = getTextWidth(py(12), hint)
    setTextBold(false)
    local iconW = h / aspect
    local w = math.max(iconW, pxw(6) + pxw(14) + pxw(4) + tw + pxw(6))
    x = math.max(0, x - w)
    local y = ytop - h
    self.iconBox = { x = x, y = y - row3H, w = w, h = h + row3H }
    setOverlayColor(ov, 1, 1, 1, self.iconHover and 1 or 0.92)
    renderOverlay(ov, x + (w - iconW) * 0.5, y, iconW, h)
    drawFilledRect(x, y - row3H, w, row3H, 0, 0, 0, 0.45)
    local arrow = AS_Weather ~= nil and AS_Weather.getOverlay ~= nil and AS_Weather:getOverlay("arrow") or nil
    local ax = x + pxw(6)
    if arrow ~= nil then
        setOverlayColor(arrow, 1, 1, 1, 1)
        if setOverlayRotation ~= nil then setOverlayRotation(arrow, 0, pxw(14) * 0.5, py(14) * 0.5) end
        renderOverlay(arrow, ax, y - row3H + py(4), pxw(14), py(14))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(1.00, 0.80, 0.30, 1)
    renderText(ax + pxw(18), y - row3H + py(6), py(12), hint)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

function AS_Fields:drawPanel()
    local sc = uiScale()
    local aspect = (g_screenWidth or 1920) / math.max(1, g_screenHeight or 1080)
    local function py(px) return px * sc / 1080 end
    local function pxw(px) return py(px) / aspect end
    local function text(x, y, size, s, col, align, bold)
        setTextAlignment(align or RenderText.ALIGN_LEFT)
        setTextBold(bold == true)
        local c = col or C.white
        setTextColor(c[1], c[2], c[3], c[4])
        renderText(x, y, py(size), tostring(s))
    end

    -- lignes affichées : un groupe déplié montre ses champs dessous (v1.0.1.6)
    local rows = {}
    for _, r in ipairs(self.rows or {}) do
        rows[#rows + 1] = r
        if r.isGroup and self.expanded[r.key] then
            for _, m in ipairs(r.members) do rows[#rows + 1] = { sub = true, parent = r, m = m } end
        end
    end
    local nShow = math.min(self.ROWS, #rows)
    local maxScroll = math.max(0, #rows - self.ROWS)
    self.scroll = math.max(0, math.min(self.scroll, maxScroll))
    local rowH, headH = 30, 30
    local Hpx = 44 + 14 + headH + math.max(1, nShow) * rowH + 40
    local W, H = pxw(1300), py(Hpx)
    local pad = pxw(18)
    local x0, y0 = 0.5 - W * 0.5, 0.5 - H * 0.5
    local top = y0 + H

    AS_drawPanelBg(x0, y0, W, H, py(44), py, pxw, 0.88)
    local ov = self:getIcon()
    if ov ~= nil then
        setOverlayColor(ov, 1, 1, 1, 1)
        renderOverlay(ov, x0 + pad, top - py(39), pxw(34), py(34))
    end
    text(x0 + pad + pxw(44), top - py(31), 20, T("Champs", "Fields"), C.title, nil, true)
    local now = gameDate()
    -- total des hectares possédés, en haut entre le titre et la date (v1.0.3.0)
    local total = 0
    for _, r in ipairs(self.rows or {}) do total = total + (r.area or 0) end
    text(x0 + W * 0.5, top - py(30), 15, string.format(T("%.1f ha possédés", "%.1f ha owned"), total / 10000), C.title, RenderText.ALIGN_CENTER, true)
    -- bouton X
    local bs, bw = py(30), pxw(30)
    local bx, by = x0 + W - pxw(8) - bw, top - py(7) - bs
    self.closeBox = { x = bx, y = by, w = bw, h = bs }
    drawFilledRect(bx, by, bw, bs, 0.75, 0.18, 0.15, self.closeHover and 1 or 0.85)
    text(bx + bw * 0.5, by + py(7), 18, "X", C.white, RenderText.ALIGN_CENTER, true)
    text(bx - pxw(12), top - py(30), 15, string.format("%s%d %s %s%d", T("Jour ", "Day "), now.dayInPeriod, periodName(now.period),
        T("an ", "y"), now.year), C.gray, RenderText.ALIGN_RIGHT)

    -- colonnes
    local cols = { 0, 290, 530, 630, 810, 1020, 1170 }
    local heads = { T("Champ", "Field"), T("Culture", "Crop"), T("Stade", "Stage"), T("Semis", "Sown"), T("Engrais", "Fertilizer"),
        T("Herbicide", "Herbicide"), T("Récolte", "Harvest") }
    local y = top - py(44) - py(14) - py(headH)
    for i, h in ipairs(heads) do text(x0 + pad + pxw(cols[i]), y + py(8), 15, h, C.title, nil, true) end
    drawFilledRect(x0 + pad, y + py(3), W - 2 * pad, py(1), 1, 1, 1, 0.15)

    if #rows == 0 then
        y = y - py(rowH)
        text(x0 + pad, y + py(8), 15, T("Aucun champ possédé.", "No owned field."), C.gray)
    end
    local before = T("avant suivi", "before tracking")
    local haX = x0 + pad + pxw(cols[2] - 20)
    local nameX = x0 + pad + pxw(26)
    self.toggleBoxes, self.pickBoxes = {}, {}
    for i = 1, nShow do
        local r = rows[i + self.scroll]
        y = y - py(rowH)
        if i % 2 == 0 then drawFilledRect(x0 + pad, y, W - 2 * pad, py(rowH), 1, 1, 1, 0.04) end
        local ty = y + py(9)
        if r.sub then
            -- champ d'un groupe : clic = champ principal
            local box = { x = x0 + pad, y = y, w = pxw(cols[2] - 10), h = py(rowH) }
            self.pickBoxes[#self.pickBoxes + 1] = { box = box, id = r.m.id, parent = r.parent }
            if self.pickHover == r.m.id then drawFilledRect(box.x, box.y, box.w, box.h, 0.45, 0.72, 1.00, 0.15) end
            local label = string.format("%s %d", T("Champ", "Field"), r.m.id) .. (r.m.main and "  *" or "")
            text(nameX + pxw(18), ty, 14, label, r.m.main and C.title or C.gray, nil, r.m.main)
            text(haX, ty, 13, string.format("%.1f ha", r.m.area / 10000), C.gray, RenderText.ALIGN_RIGHT)
            if i == 1 or rows[i + self.scroll - 1].sub ~= true then
                text(x0 + pad + pxw(cols[2]), ty, 13, T("clic sur un champ = champ principal", "click a field = main field"), C.gray)
            end
        else
        if r.isGroup then
            -- croix bleue : déplier / replier la liste des champs du groupe
            local s = py(20)
            local box = { x = x0 + pad, y = y + py(5), w = pxw(20), h = s }
            self.toggleBoxes[#self.toggleBoxes + 1] = { box = box, key = r.key }
            drawFilledRect(box.x, box.y, box.w, box.h, 0.20, 0.45, 0.85, self.toggleHover == r.key and 1 or 0.85)
            text(box.x + box.w * 0.5, box.y + py(3), 16, self.expanded[r.key] and "-" or "+", C.white, RenderText.ALIGN_CENTER, true)
        end
        text(nameX, ty, 15, r.name, C.white, nil, true)
        text(haX, ty, 13, string.format("%.1f ha", r.area / 10000), C.gray, RenderText.ALIGN_RIGHT)
        text(x0 + pad + pxw(cols[2]), ty, 15, r.crop, r.hasFruit and C.white or C.gray)
        text(x0 + pad + pxw(cols[3]), ty, 15, r.stage or "-", r.hasFruit and C.white or C.gray)
        -- semis
        text(x0 + pad + pxw(cols[4]), ty, 15, r.sow ~= nil and fmtDate(r.sow.date) or (r.hasFruit and before or "-"), r.sow ~= nil and C.white or C.gray)
        -- engrais
        local ft, fc
        if r.fert ~= nil then
            ft, fc = fmtDate(r.fert.date), C.white
            if (r.fert.n or 1) > 1 then ft = ft .. string.format(" (x%d)", r.fert.n) end
        elseif not hasPF() and (r.spray or 0) > 0 then
            ft, fc = before, C.gray
        else
            ft, fc = "-", C.gray
        end
        if not hasPF() and r.hasFruit then ft = ft .. string.format("  %d/2", r.spray or 0) end
        text(x0 + pad + pxw(cols[5]), ty, 15, ft, fc)
        -- herbicide
        text(x0 + pad + pxw(cols[6]), ty, 15, r.herb ~= nil and fmtDate(r.herb.date) or "-", r.herb ~= nil and C.white or C.gray)
        -- récolte
        local hc = C.gray
        if r.hKind == "ready" then hc = C.green elseif r.hKind == "dead" then hc = C.red elseif r.hKind == "wait" then hc = C.white end
        text(x0 + pad + pxw(cols[7]), ty, 15, r.harvest, hc, nil, r.hKind == "ready")
        end
    end
    local foot = T("Dates notées par AutoSwitch quand 10 % du champ est travaillé", "Dates recorded by AutoSwitch once 10 % of the field is worked")
    text(x0 + pad, y0 + py(12), 13, foot, C.gray)
    if maxScroll > 0 then
        text(x0 + W - pad, y0 + py(12), 13, T("molette pour défiler", "scroll with the mouse wheel"), C.gray, RenderText.ALIGN_RIGHT)
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-------------------------------------------------------------------------------
-- Ouverture, souris, touche
-------------------------------------------------------------------------------
function AS_Fields:setOpen(open)
    if open == self.isOpen then return end
    self.isOpen = open
    self.scroll = 0
    self.rows = nil
    self.expanded = {}
    self.closeBox, self.closeHover = nil, false
    if open then
        if AS_Weather ~= nil and AS_Weather.isOpen then AS_Weather:setOpen(false) end
        if AS_Register ~= nil and AS_Register.isOpen then AS_Register:setOpen(false) end
    end
    if g_inputBinding == nil or g_inputBinding.setShowMouseCursor == nil then return end
    if open then
        self.cursorBefore = g_inputBinding.getShowMouseCursor ~= nil and g_inputBinding:getShowMouseCursor() == true
        if not self.cursorBefore then pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true) end
    elseif self.cursorBefore == false then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
    end
end

function AS_Fields.onToggle()
    AS_Fields:setOpen(not AS_Fields.isOpen)
end

local function inBox(b, px, py_)
    return b ~= nil and px >= b.x and px <= b.x + b.w and py_ >= b.y and py_ <= b.y + b.h
end

function AS_Fields:mouseEvent(posX, posY, isDown, isUp, button)
    if self.isOpen then
        self.closeHover = inBox(self.closeBox, posX, posY)
        self.toggleHover, self.pickHover = nil, nil
        local pick = nil
        for _, t in ipairs(self.toggleBoxes or {}) do
            if inBox(t.box, posX, posY) then self.toggleHover = t.key end
        end
        for _, p in ipairs(self.pickBoxes or {}) do
            if inBox(p.box, posX, posY) then self.pickHover, pick = p.id, p end
        end
        if isDown and button == Input.MOUSE_BUTTON_LEFT and self.closeHover then
            self:setOpen(false)
        elseif isDown and button == Input.MOUSE_BUTTON_LEFT and self.toggleHover ~= nil then
            self.expanded[self.toggleHover] = not self.expanded[self.toggleHover] or nil
        elseif isDown and button == Input.MOUSE_BUTTON_LEFT and pick ~= nil then
            -- (v1.0.1.6) champ principal choisi par le joueur, gardé avec la partie
            for _, m in ipairs(pick.parent.members) do self.chosenMain[m.id] = nil end
            self.chosenMain[pick.id] = true
            self.rows, self.lastCompute = nil, -100000
            log("champ principal du groupe : %d", pick.id)
        elseif isDown and button == Input.MOUSE_BUTTON_WHEEL_UP then
            self.scroll = math.max(0, self.scroll - 3)
        elseif isDown and button == Input.MOUSE_BUTTON_WHEEL_DOWN then
            self.scroll = self.scroll + 3
        end
        return
    end
    -- icône : un clic ouvre la fenêtre (curseur de la souris affiché)
    if g_inputBinding == nil or g_inputBinding.getShowMouseCursor == nil or g_inputBinding:getShowMouseCursor() ~= true then
        self.iconHover = false
        return
    end
    self.iconHover = inBox(self.iconBox, posX, posY)
    if self.iconHover and isUp and button == Input.MOUSE_BUTTON_LEFT then
        self:setOpen(true)
    end
end

local function registerToggle()
    if InputAction == nil or InputAction.AS_FIELDS == nil then return nil end
    local _, id = g_inputBinding:registerActionEvent(InputAction.AS_FIELDS, AS_Fields, AS_Fields.onToggle, false, true, false, true)
    if id ~= nil then
        g_inputBinding:setActionEventText(id, AS.L("input_AS_FIELDS"))
        g_inputBinding:setActionEventTextVisibility(id, false)
    end
    return id
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents ~= nil then
    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, function(self)
        if self.player == nil or not self.player.isOwner then return end
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        if AS_Fields.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(AS_Fields.actionEventId)
            AS_Fields.actionEventId = nil
        end
        AS_Fields.actionEventId = registerToggle()
        g_inputBinding:endActionEventsModification()
    end)
end

if Drivable ~= nil and Drivable.onRegisterActionEvents ~= nil then
    Drivable.onRegisterActionEvents = Utils.appendedFunction(Drivable.onRegisterActionEvents, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        if not self.isClient or not isActiveForInputIgnoreSelection then return end
        registerToggle()
    end)
end

function AS_Fields:delete()
    self.isOpen = false
    self.actionEventId = nil
    for _, ov in pairs(self.overlays) do
        if ov then delete(ov) end
    end
    self.overlays = {}
end

addModEventListener(AS_Fields)
