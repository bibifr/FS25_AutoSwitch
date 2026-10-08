-- AutoSwitch : palette de pneus (grange) : passage simple <-> jumelées avec Ctrl droit + I
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v2.4 : objet "palette de pneus" (boutique, catégorie palettes) à poser dans la grange.
-- À pied à côté de la palette, tracteur arrêté à moins de RANGE m d'elle + Ctrl droit + I :
--   pneus simples -> configuration jumelées correspondante (même marque / même taille si possible)
--   jumelées      -> retour à la configuration d'origine (mémorisée)
-- (v2.8) 15 min de jeu par pneu (4 pneus = 1 h, 2 pneus = 30 min) : le joueur peut partir, le tracteur ne doit pas bouger.
-- Le changement utilise le même mécanisme que le rechargement de véhicule du jeu :
-- le tracteur (et ses outils attelés) est sauvegardé avec la nouvelle configuration
-- de roues puis rechargé à la même place. Montage gratuit : seul l'achat de la palette est payant.
-------------------------------------------------------------------------------
AS_DualRack = {}
AS_DualRack.RANGE = 10           -- distance maxi tracteur <-> palette (m)
AS_DualRack.PLAYER_RANGE = 3     -- distance maxi joueur à pied <-> palette (m)
-- (v3.1) zone de montage au sol, à côté de la palette (côté +Z de la palette)
AS_DualRack.ZONE_OFFSET = 3.8    -- distance palette -> centre de la zone (m)
AS_DualRack.ZONE_LENGTH = 8.0    -- longueur de la zone (sens du tracteur, le long de la palette)
AS_DualRack.ZONE_WIDTH = 4.5     -- largeur de la zone
AS_DualRack.ZONE_SHOW_DIST = 20  -- zone affichée à moins de 20 m (à pied ou au volant)
AS_DualRack.MIN_PER_TIRE = 15    -- (v2.8) minutes de jeu par pneu : 4 pneus = 1 h, 2 pneus = 30 min
AS_DualRack.MAX_SPEED = 1        -- km/h : tracteur arrêté
-- (v2.7) types de palettes : universelle (4 pneus), arrière (2 pneus), avant (2 pneus)
AS_DualRack.RACK_KINDS = { ["tireRack.xml"] = "ALL", ["tireRackAR.xml"] = "AR", ["tireRackAV.xml"] = "AV",
    -- (v2.8) versions "menu construction" (objets fixes)
    ["tireRackAR_placeable.xml"] = "AR", ["tireRackAV_placeable.xml"] = "AV" }
AS_DualRack.jobs = {}            -- (v2.6) [uniqueId] = chantier en cours
AS_DualRack.rackTires = {}       -- (v2.6) [uniqueId palette] = nombre de pneus posés
AS_DualRack.memory = {}          -- [uniqueId] = saveId de la configuration simple d'origine
AS_DualRack.memoryLoaded = false

local function notify(kind, text)
    local t = FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_INFO or nil
    if kind == "ok" and FSBaseMission ~= nil then t = FSBaseMission.INGAME_NOTIFICATION_OK end
    if kind == "err" and FSBaseMission ~= nil then t = FSBaseMission.INGAME_NOTIFICATION_CRITICAL end
    showTimedNotification("tires", t, text)
end

-- (v3.2) fenêtre à valider (explication claire quand le changement est impossible)
local function popup(text)
    if InfoDialog ~= nil and InfoDialog.show ~= nil then
        local ok = pcall(InfoDialog.show, text, nil, nil, DialogElement ~= nil and DialogElement.TYPE_WARNING or nil)
        if ok then return end
    end
    notify("err", text)
end

-- temps de jeu en minutes (jours monotones)
local function gameMinutes()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return 0 end
    return (env.currentMonotonicDay or 0) * 1440 + (env.dayTime or 0) / 60000
end
local function clockText(min)
    local m = math.floor(min) % 1440
    return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

-- (v2.7) jumelées reconnues par l'identifiant (TWIN...) OU par le nom de la configuration
-- (certains tracteurs n'ont que "Roues jumelées arrière" comme nom)
local twinTexts, backTexts = nil, nil
local function loadTwinTexts()
    twinTexts, backTexts = {}, {}
    local function add(list, key)
        if g_i18n ~= nil and g_i18n:hasText(key) then
            local t = string.lower(g_i18n:getText(key))
            if t ~= "" then table.insert(list, t) end
        end
    end
    for _, k in ipairs({"configuration_valueTwinWheels", "configuration_valueTwinWheelsAll", "configuration_valueTwinWheelsBack",
                        "configuration_valueTwinWheelsFront", "configuration_valueTwinWheelsNarrow"}) do add(twinTexts, k) end
    add(backTexts, "configuration_valueTwinWheelsBack")
end
local function containsAny(s, list)
    for _, t in ipairs(list) do
        if string.find(s, t, 1, true) ~= nil then return true end
    end
    return false
end
local function jobTotal(j)
    local t = 0
    for _, r in ipairs(j.racks or {}) do t = t + r.cap end
    return math.max(1, t)
end

local function isTwinItem(it)
    if it == nil then return false end
    local sid = string.upper(it.saveId or "")
    if string.find(sid, "TWIN", 1, true) ~= nil then return true end
    if twinTexts == nil then loadTwinTexts() end
    local nm = string.lower(tostring(it.name or ""))
    return containsAny(nm, twinTexts) or string.find(nm, "twin", 1, true) ~= nil
        or string.find(nm, "jumel", 1, true) ~= nil or string.find(nm, "zwilling", 1, true) ~= nil
end
local function isBackItem(it)
    if it == nil then return false end
    local sid = string.upper(it.saveId or "")
    if string.find(sid, "BACK", 1, true) ~= nil or string.find(sid, "REAR", 1, true) ~= nil then return true end
    if twinTexts == nil then loadTwinTexts() end
    local nm = string.lower(tostring(it.name or ""))
    return containsAny(nm, backTexts) or string.find(nm, "arrière", 1, true) ~= nil
        or string.find(nm, "rear", 1, true) ~= nil or string.find(nm, "back", 1, true) ~= nil
        or string.find(nm, "hinten", 1, true) ~= nil
end

local function tokens(s)
    local t = {}
    for w in string.gmatch(string.upper(s or ""), "[^_]+") do
        if string.find(w, "TWIN", 1, true) == nil and w ~= "ALL" and w ~= "BACK" then t[w] = true end
    end
    return t
end

-------------------------------------------------------------------------------
-- (v2.6.3) mémoire (pneus d'origine, état des palettes, chantiers en cours) :
-- gardée en mémoire pendant la partie et écrite UNIQUEMENT quand le jeu sauvegarde,
-- dans le dossier de la partie (savegameX/autoSwitchDuals.xml). Quitter sans
-- sauvegarder = tout revient à l'état de la dernière sauvegarde, tracteurs compris.
-------------------------------------------------------------------------------
local function legacyPath()
    return getUserProfileAppPath() .. "modSettings/FS25_AutoSwitch/duals.xml"
end
local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/autoSwitchDuals.xml"
end
local function savegameKey()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return "sg" .. tostring(mi ~= nil and mi.savegameIndex or 0)
end

-- liste des palettes d'un chantier : "id:capacité,id:capacité"
function AS_DualRack.parseRacks(str, legacyId)
    local list = {}
    if str ~= nil and str ~= "" then
        for part in string.gmatch(str, "[^,]+") do
            local id, cap = string.match(part, "^(.-):(%d+)$")
            if id ~= nil then table.insert(list, { id = id, cap = tonumber(cap) }) end
        end
    elseif legacyId ~= nil and legacyId ~= "" then
        table.insert(list, { id = legacyId, cap = 4 })
    end
    return list
end
function AS_DualRack.formatRacks(list)
    local t = {}
    for _, r in ipairs(list or {}) do table.insert(t, r.id .. ":" .. tostring(r.cap)) end
    return table.concat(t, ",")
end

function AS_DualRack:loadMemory()
    self.memoryLoaded = true
    self.memory = {}
    self.rackTires = {}
    self.jobs = {}
    local path, base = savegamePath(), "duals"
    if path == nil or not fileExists(path) then
        -- ancienne version : fichier commun dans modSettings
        path, base = legacyPath(), "duals." .. savegameKey()
        if not fileExists(path) then return end
    end
    local xml = loadXMLFile("asDualsMem", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("%s.vehicle(%d)", base, i)
        if not hasXMLProperty(xml, key) then break end
        local id = getXMLString(xml, key .. "#uniqueId")
        local sid = getXMLString(xml, key .. "#wheel")
        if id ~= nil and sid ~= nil then self.memory[id] = sid end
        i = i + 1
    end
    self.rackTires = {}
    i = 0
    while true do
        local key = string.format("%s.rack(%d)", base, i)
        if not hasXMLProperty(xml, key) then break end
        local id = getXMLString(xml, key .. "#uniqueId")
        local n = getXMLInt(xml, key .. "#tires")
        if id ~= nil and n ~= nil then self.rackTires[id] = n end
        i = i + 1
    end
    self.jobs = {}
    i = 0
    while true do
        local key = string.format("%s.job(%d)", base, i)
        if not hasXMLProperty(xml, key) then break end
        local id = getXMLString(xml, key .. "#uniqueId")
        if id ~= nil then
            self.jobs[id] = {
                uniqueId = id,
                origSid = getXMLString(xml, key .. "#from"),
                toSid = getXMLString(xml, key .. "#to"),
                curSid = getXMLString(xml, key .. "#cur"),
                endMin = getXMLFloat(xml, key .. "#endMin") or 0,
                price = 0, -- montage gratuit
                farmId = getXMLInt(xml, key .. "#farmId") or 1,
                toDual = getXMLBool(xml, key .. "#toDual") == true,
                racks = AS_DualRack.parseRacks(getXMLString(xml, key .. "#racks"), getXMLString(xml, key .. "#rack")),
                startMin = getXMLFloat(xml, key .. "#startMin") or 0,
            }
        end
        i = i + 1
    end
    delete(xml)
end

function AS_DualRack:saveMemory()
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asDualsMem", path, "duals")
    if xml == nil or xml == 0 then return end
    local base = "duals"
    local i = 0
    for id, sid in pairs(self.memory) do
        local key = string.format("%s.vehicle(%d)", base, i)
        setXMLString(xml, key .. "#uniqueId", id)
        setXMLString(xml, key .. "#wheel", sid)
        i = i + 1
    end
    i = 0
    for id, j in pairs(self.jobs) do
        local key = string.format("%s.job(%d)", base, i)
        setXMLString(xml, key .. "#uniqueId", id)
        setXMLString(xml, key .. "#from", j.origSid or "")
        setXMLString(xml, key .. "#cur", j.curSid or "")
        setXMLString(xml, key .. "#to", j.toSid or "")
        setXMLFloat(xml, key .. "#endMin", j.endMin)
        setXMLInt(xml, key .. "#price", j.price or 0)
        setXMLInt(xml, key .. "#farmId", j.farmId or 1)
        setXMLBool(xml, key .. "#toDual", j.toDual == true)
        setXMLString(xml, key .. "#racks", AS_DualRack.formatRacks(j.racks))
        setXMLFloat(xml, key .. "#startMin", j.startMin or 0)
        i = i + 1
    end
    i = 0
    for id, n in pairs(self.rackTires) do
        local key = string.format("%s.rack(%d)", base, i)
        setXMLString(xml, key .. "#uniqueId", id)
        setXMLInt(xml, key .. "#tires", n)
        i = i + 1
    end
    saveXMLFile(xml)
    delete(xml)
end

-------------------------------------------------------------------------------
-- recherche de la configuration cible
-------------------------------------------------------------------------------
function AS_DualRack.getWheelItems(vehicle)
    local si = g_storeManager ~= nil and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    local items = si ~= nil and si.configurations ~= nil and si.configurations.wheel or nil
    return items
end

-- (v2.7) mode : "ALL" = jumelées avant + arrière, "BACK" = arrière seulement, "ANY" = au choix (ALL en priorité)
-- renvoie indexCible, versJumelees, itemActuel, raison
function AS_DualRack:findTarget(vehicle, mode)
    local items = AS_DualRack.getWheelItems(vehicle)
    local idx = vehicle.configurations ~= nil and vehicle.configurations.wheel or nil
    if items == nil or idx == nil or items[idx] == nil then return nil, true, nil end
    local cur = items[idx]
    local toDual = not isTwinItem(cur)

    -- retour : uniquement si les jumelées ont été montées avec une palette
    -- (configuration d'origine mémorisée). Tracteur arrivé déjà en jumelées : refusé.
    if not toDual then
        local prev = self.memory[vehicle:getUniqueId()]
        if prev ~= nil then
            for i, it in ipairs(items) do
                if it.saveId == prev then return i, false, cur end
            end
        end
        return nil, false, cur, "alreadyTwin"
    end

    -- (v2.9) jumelées obligatoirement dans la marque des pneus actuels du tracteur
    local curBrand = AS_DualRack.getTireBrand(cur)
    local curModel = cur.tireCombination ~= nil and cur.tireCombination.wheelSaveId or nil
    local otherBrands, seen = {}, {}
    local curTok = tokens(cur.saveId)
    local best, bestScore = nil, -math.huge
    for i, it in ipairs(items) do
        if i ~= idx and it.isSelectable ~= false and isTwinItem(it) then
            local back = isBackItem(it)
            local ok = mode == "ANY" or (mode == "BACK" and back) or (mode == "ALL" and not back)
            local b = AS_DualRack.getTireBrand(it)
            if ok and curBrand ~= nil and b ~= nil and b ~= curBrand then
                ok = false
                if not seen[b] then seen[b] = true; table.insert(otherBrands, b) end
            end
            if ok then
                local score = 0
                local t = tokens(it.saveId)
                for w in pairs(t) do
                    if curTok[w] then score = score + 10 else score = score - 1 end
                end
                for w in pairs(curTok) do
                    if not t[w] then score = score - 1 end
                end
                if mode == "ANY" and not back then score = score + 5 end
                -- même modèle de pneu (ex. Michelin AxioBib 2) en priorité
                if curModel ~= nil and it.tireCombination ~= nil and it.tireCombination.wheelSaveId == curModel then score = score + 20 end
                if score > bestScore then best, bestScore = i, score end
            end
        end
    end
    if best == nil and #otherBrands > 0 then
        return nil, toDual, cur, "brand", otherBrands
    end
    return best, toDual, cur
end

-- marque des pneus d'une configuration de roues (nil si inconnue)
function AS_DualRack.getTireBrand(it)
    if it == nil then return nil end
    local b = it.wheelBrandName
    if b == nil and it.tireCombination ~= nil and it.tireCombination.wheelBrand ~= nil then b = it.tireCombination.wheelBrand.name end
    if type(b) ~= "string" or b == "" then return nil end
    return string.upper(b)
end
function AS_DualRack.getBrandTitle(name)
    if name == nil then return "?" end
    local br = g_brandManager ~= nil and g_brandManager:getBrandByName(name) or nil
    return br ~= nil and br.title or name
end

-------------------------------------------------------------------------------
-- (v2.6) pneus visibles sur la palette : retirés un par un (du haut vers le bas)
-------------------------------------------------------------------------------
local function rackKind(v)
    local f = v ~= nil and v.configFileName or nil
    if f == nil then return nil end
    local base = string.match(f, "([^/\\]+)$") or f
    return AS_DualRack.RACK_KINDS[base]
end
local function isRack(v)
    return rackKind(v) ~= nil
end
AS_DualRack.rackKind = rackKind

function AS_DualRack:getRackTireNodes(rack)
    if rack.__asTireNodes ~= nil then return rack.__asTireNodes end
    local nodes = {}
    local function scan(node, depth)
        for i = 0, getNumOfChildren(node) - 1 do
            local c = getChildAt(node, i)
            local nm = getName(c)
            if string.sub(nm, 1, 4) == "_IF_" or string.lower(string.sub(nm, 1, 4)) == "pneu" then
                -- (v2.6.2) hauteur réelle du pneu : centre de la première forme 3D (lod0),
                -- le point d'origine du groupe ne correspond pas toujours au pneu
                local function firstShape(n, d)
                    for k = 0, getNumOfChildren(n) - 1 do
                        local ch = getChildAt(n, k)
                        if getHasClassId(ch, ClassIds.SHAPE) then return ch end
                        if d < 4 then
                            local r = firstShape(ch, d + 1)
                            if r ~= nil then return r end
                        end
                    end
                    return nil
                end
                local ref = firstShape(c, 0) or c
                local _, y, _ = localToLocal(ref, rack.rootNode, 0, 0, 0)
                table.insert(nodes, { node = c, y = y })
            elseif depth < 3 then
                scan(c, depth + 1)
            end
        end
    end
    scan(rack.rootNode, 0)
    table.sort(nodes, function(a, b) return a.y < b.y end) -- du bas vers le haut
    rack.__asTireNodes = nodes
    return nodes
end

function AS_DualRack:getRackCapacity(rack)
    local n = #self:getRackTireNodes(rack)
    if n > 0 then return n end
    return rackKind(rack) == "ALL" and 4 or 2
end

function AS_DualRack:getRackCount(rack)
    local n = self.rackTires[rack:getUniqueId()]
    if n == nil then return self:getRackCapacity(rack) end -- palette neuve : pleine
    return n
end

function AS_DualRack:setRackCount(rack, n)
    n = math.max(0, math.min(self:getRackCapacity(rack), n))
    self.rackTires[rack:getUniqueId()] = n
    local nodes = self:getRackTireNodes(rack)
    for i, e in ipairs(nodes) do
        setVisibility(e.node, i <= n)
    end
    rack.__asShown = n
end

-- (v2.8) toutes les palettes : palettes de la boutique (véhicules) + objets du menu construction
function AS_DualRack:allRacks()
    local list = {}
    local vs = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if vs ~= nil then
        for _, v in pairs(vs.vehicles) do
            if isRack(v) and not v.isDeleted and v.rootNode ~= nil then table.insert(list, v) end
        end
    end
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps ~= nil and ps.placeables ~= nil then
        for _, p in ipairs(ps.placeables) do
            if isRack(p) and not p.isDeleted and p.rootNode ~= nil then table.insert(list, p) end
        end
    end
    return list
end

function AS_DualRack:findRackById(id)
    for _, r in ipairs(self:allRacks()) do
        if r:getUniqueId() == id then return r end
    end
    return nil
end

function AS_DualRack:rackBusy(rack)
    local id = rack:getUniqueId()
    for _, j in pairs(self.jobs) do
        for _, r in ipairs(j.racks or {}) do
            if r.id == id then return true end
        end
    end
    return false
end

-- palette libre d'un type donné près du tracteur, pleine (full=true) ou vide (full=false)
function AS_DualRack:findRackNearVehicle(vehicle, kind, full, prefer)
    local function okRack(r)
        return r ~= nil and not r.isDeleted and rackKind(r) == kind and not self:rackBusy(r)
            and ((full and self:getRackCount(r) >= self:getRackCapacity(r)) or (not full and self:getRackCount(r) == 0))
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local function near(r)
        local rx, _, rz = getWorldTranslation(r.rootNode)
        return MathUtil.vector2Length(rx - x, rz - z) <= self.RANGE
    end
    if okRack(prefer) and near(prefer) then return prefer end
    for _, v in ipairs(self:allRacks()) do
        if okRack(v) and near(v) then return v end
    end
    return nil
end

-- joueur à pied à côté d'une palette ? renvoie la palette
function AS_DualRack:getPlayerRack()
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil or g_localPlayer:getCurrentVehicle() ~= nil then return nil end
    local ok, px, _, pz = pcall(g_localPlayer.getPosition, g_localPlayer)
    if not ok or px == nil then return nil end
    for _, v in ipairs(self:allRacks()) do
        local rx, _, rz = getWorldTranslation(v.rootNode)
        local mx, _, mz = self:getMarkerPos(v)
        if MathUtil.vector2Length(rx - px, rz - pz) <= self.PLAYER_RANGE
            or MathUtil.vector2Length(mx - px, mz - pz) <= 1.0 then
            local _, primary = self:getGroup(v)
            return primary or v
        end
    end
    return nil
end

-- tracteur (avec configurations de roues) le plus proche de la palette
-- (v3.1) zone de montage : centre + axes (monde, plan horizontal) d'une palette
-- (v3.3) palettes posées côte à côte (moins de GROUP_DIST m) = un seul poste de montage :
-- une seule zone tracteur et un seul repère joueur. Palette de référence : AR si présente.
AS_DualRack.GROUP_DIST = 4.5
function AS_DualRack:getGroup(rack)
    local all = self:allRacks()
    local group, inGroup = { rack }, { [rack] = true }
    local i = 1
    while i <= #group do
        local gx, _, gz = getWorldTranslation(group[i].rootNode)
        for _, r in ipairs(all) do
            if not inGroup[r] then
                local x, _, z = getWorldTranslation(r.rootNode)
                if MathUtil.vector2Length(x - gx, z - gz) <= self.GROUP_DIST then
                    inGroup[r] = true
                    table.insert(group, r)
                end
            end
        end
        i = i + 1
    end
    local primary = nil
    for _, r in ipairs(group) do
        if rackKind(r) == "AR" and (primary == nil or r:getUniqueId() < primary:getUniqueId()) then primary = r end
    end
    if primary == nil then
        for _, r in ipairs(group) do
            if primary == nil or r:getUniqueId() < primary:getUniqueId() then primary = r end
        end
    end
    return group, primary
end

function AS_DualRack:getZone(rack)
    local group, primary = self:getGroup(rack)
    local x, y, z = 0, 0, 0
    for _, r in ipairs(group) do
        local gx, gy, gz = getWorldTranslation(r.rootNode)
        x, y, z = x + gx, y + gy, z + gz
    end
    x, y, z = x / #group, y / #group, z / #group
    rack = primary
    local ax, _, az = localDirectionToWorld(rack.rootNode, 1, 0, 0)
    local n = math.sqrt(ax * ax + az * az)
    if n < 0.001 then ax, az, n = 1, 0, 1 end
    ax, az = ax / n, az / n
    local bx, bz = -az, ax     -- axe perpendiculaire (côté +Z de la palette)
    local zx, _, zz = localDirectionToWorld(rack.rootNode, 0, 0, 1)
    if zx * bx + zz * bz < 0 then bx, bz = -bx, -bz end
    -- demi-longueur du groupe le long de la palette (pour placer le repère au bout)
    local span = 0
    for _, r in ipairs(group) do
        local gx, _, gz = getWorldTranslation(r.rootNode)
        span = math.max(span, math.abs((gx - x) * ax + (gz - z) * az))
    end
    return {
        cx = x + bx * self.ZONE_OFFSET, cz = z + bz * self.ZONE_OFFSET, y = y,
        ax = ax, az = az, bx = bx, bz = bz,
        hl = self.ZONE_LENGTH / 2, hw = self.ZONE_WIDTH / 2,
        gx = x, gz = z, span = span, primary = primary,
    }
end

function AS_DualRack:isInZone(zone, vehicle)
    if vehicle == nil or vehicle.rootNode == nil then return false end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local dx, dz = x - zone.cx, z - zone.cz
    local a = dx * zone.ax + dz * zone.az
    local b = dx * zone.bx + dz * zone.bz
    return math.abs(a) <= zone.hl and math.abs(b) <= zone.hw
end

-- tracteur garé dans la zone de montage de la palette
function AS_DualRack:findTractorInZone(rack)
    local zone = self:getZone(rack)
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v ~= rack and v == v.rootVehicle and v.spec_motorized ~= nil and v.spec_wheels ~= nil and v.rootNode ~= nil
            and v.configurations ~= nil and v.configurations.wheel ~= nil and self:isInZone(zone, v) then
            return v
        end
    end
    return nil
end

-- dessin de la zone au sol : rouge = vide, vert = tracteur bien placé / chantier en cours
function AS_DualRack:drawZone(rack, active)
    local zn = self:getZone(rack)
    local occupied = active or self:findTractorInZone(rack) ~= nil
    local r, g, b = 0.9, 0.15, 0.1
    if occupied then r, g, b = 0.1, 0.85, 0.2 end
    local function corner(sa, sb)
        local x = zn.cx + zn.ax * zn.hl * sa + zn.bx * zn.hw * sb
        local z = zn.cz + zn.az * zn.hl * sa + zn.bz * zn.hw * sb
        return x, zn.y + 0.06, z
    end
    -- (v3.3) contour épais : plusieurs rectangles concentriques (bande d'environ 15 cm), sans flèche
    local function cornerIn(sa, sb, inset)
        local x = zn.cx + zn.ax * (zn.hl - inset) * sa + zn.bx * (zn.hw - inset) * sb
        local z = zn.cz + zn.az * (zn.hl - inset) * sa + zn.bz * (zn.hw - inset) * sb
        return x, zn.y + 0.06, z
    end
    for _, inset in ipairs({0, 0.03, 0.06, 0.09, 0.12, 0.15}) do
        for _, dy in ipairs({0, 0.02}) do
            local x1, y1, z1 = cornerIn(-1, -1, inset)
            local x2, y2, z2 = cornerIn(1, -1, inset)
            local x3, y3, z3 = cornerIn(1, 1, inset)
            local x4, y4, z4 = cornerIn(-1, 1, inset)
            drawDebugLine(x1, y1 + dy, z1, r, g, b, x2, y2 + dy, z2, r, g, b)
            drawDebugLine(x2, y2 + dy, z2, r, g, b, x3, y3 + dy, z3, r, g, b)
            drawDebugLine(x3, y3 + dy, z3, r, g, b, x4, y4 + dy, z4, r, g, b)
            drawDebugLine(x4, y4 + dy, z4, r, g, b, x1, y1 + dy, z1, r, g, b)
        end
    end
    if drawDebugTriangle ~= nil then
        local x1, y1, z1 = corner(-1, -1)
        local x2, y2, z2 = corner(1, -1)
        local x3, y3, z3 = corner(1, 1)
        local x4, y4, z4 = corner(-1, 1)
        drawDebugTriangle(x1, y1, z1, x3, y3, z3, x2, y2, z2, r, g, b, 0.15, false)
        drawDebugTriangle(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, 0.15, false)
    end
end

-- (v3.2.1) repère "placez-vous ici" pour le joueur à pied : cercle au sol + poteau + flèche
AS_DualRack.MARKER_DIST = 1.7    -- distance palette -> repère (bout de la palette, côté opposé à la flèche)
function AS_DualRack:getMarkerPos(rack)
    local zn = self:getZone(rack)
    local d = zn.span + self.MARKER_DIST
    return zn.gx - zn.ax * d, zn.y, zn.gz - zn.az * d
end

function AS_DualRack:drawMarker(rack, px, pz)
    local mx, my, mz = self:getMarkerPos(rack)
    local onSpot = px ~= nil and MathUtil.vector2Length(mx - px, mz - pz) <= 0.8
    local r, g, b = 1.0, 0.75, 0.0
    if onSpot then r, g, b = 0.1, 0.85, 0.2 end
    local y = my + 0.05
    local steps, rad = 20, 0.55
    for i = 0, steps - 1 do
        local a1, a2 = i / steps * 2 * math.pi, (i + 1) / steps * 2 * math.pi
        drawDebugLine(mx + math.cos(a1) * rad, y, mz + math.sin(a1) * rad, r, g, b, mx + math.cos(a2) * rad, y, mz + math.sin(a2) * rad, r, g, b)
        drawDebugLine(mx + math.cos(a1) * rad * 0.6, y, mz + math.sin(a1) * rad * 0.6, r, g, b, mx + math.cos(a2) * rad * 0.6, y, mz + math.sin(a2) * rad * 0.6, r, g, b)
    end
    -- (v3.4) le poteau et la flèche sont remplacés par le marqueur jaune du jeu (voir updateMarkers)
    local top = y + 2.2
    -- texte "Ctrl droit + I" au-dessus du repère
    if project3DTo2D ~= nil and renderText ~= nil then
        local sx, sy, sz = project3DTo2D(mx, top + 0.25, mz)
        if sx ~= nil and sz ~= nil and sz <= 1 and sx > 0 and sx < 1 and sy > 0 and sy < 1 then
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(r, g, b, 1)
            renderText(sx, sy, 0.016, onSpot and L("as_dual_marker_on") or L("as_dual_marker"))
            setTextBold(false)
            setTextColor(1, 1, 1, 1)
            setTextAlignment(RenderText.ALIGN_LEFT)
        end
    end
end

-- (v3.3) minuteur à droite, au milieu de l'écran : temps restant de chaque changement de roues
function AS_DualRack:drawTimers()
    if next(self.jobs) == nil or renderText == nil then return end
    local now = gameMinutes()
    local x, y = 0.985, 0.56
    local size = 0.0125
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextBold(true)
    local function line(txt, r, g, b)
        setTextColor(0, 0, 0, 0.75)
        renderText(x + 0.0008, y - 0.0012, size, txt)
        setTextColor(r, g, b, 1)
        renderText(x, y, size, txt)
        y = y - size * 1.35
    end
    line(L("as_dual_timer_title"), 1, 0.75, 0)
    setTextBold(false)
    for _, j in pairs(self.jobs) do
        local v = j.vehicle
        local name = (v ~= nil and not v.isDeleted and v.getName ~= nil) and v:getName() or "?"
        local left = math.max(0, math.ceil((j.endMin or now) - now))
        local total = jobTotal(j)
        local step = math.max(0, math.min(total, math.floor((now - (j.startMin or now)) / self.MIN_PER_TIRE)))
        local txt = string.format(L(j.toDual and "as_dual_timer_on" or "as_dual_timer_off"),
            name, left, clockText(j.endMin or now), step, total)
        line(txt, 1, 1, 1)
    end
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- (v3.4) marqueur jaune du jeu (icône d'atelier, comme aux points d'interaction) sur le repère joueur
AS_DualRack.MARKER_I3D = "$data/shared/assets/marker/markerIconWrench.i3d"
AS_DualRack.markers = {}   -- [palette de référence] = { node, reqId }

function AS_DualRack:onMarkerLoaded(node, failedReason, args)
    local m = self.markers[args.rack]
    if m == nil or m.reqId == nil then
        -- palette disparue entre-temps
        if node ~= nil and node ~= 0 then delete(node) end
        return
    end
    if node == nil or node == 0 then
        m.failed = true
        return
    end
    link(getRootNode(), node)
    setVisibility(node, false)
    m.node = node
end

function AS_DualRack:removeMarker(rack)
    local m = self.markers[rack]
    if m == nil then return end
    if m.node ~= nil and m.node ~= 0 then delete(m.node) end
    if m.reqId ~= nil then g_i3DManager:releaseSharedI3DFile(m.reqId) end
    self.markers[rack] = nil
end

function AS_DualRack:updateMarkers()
    local show = {}
    local ok, px, _, pz = false, nil, nil, nil
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() == nil then
        ok, px, _, pz = pcall(g_localPlayer.getPosition, g_localPlayer)
    end
    local busy = {}
    for _, j in pairs(self.jobs) do
        for _, r in ipairs(j.racks or {}) do busy[r.id] = true end
    end
    local exists = {}
    for _, rack in ipairs(self:allRacks()) do
        local okG, group, primary = pcall(self.getGroup, self, rack)
        if okG and primary ~= nil then
            exists[primary] = true
            local rx, _, rz = getWorldTranslation(primary.rootNode)
            local near = ok and px ~= nil and MathUtil.vector2Length(rx - px, rz - pz) <= self.ZONE_SHOW_DIST
            local isBusy = false
            for _, r in ipairs(group) do
                if busy[r:getUniqueId()] then isBusy = true end
            end
            if near and not isBusy then show[primary] = true end
        end
    end
    -- marqueurs de palettes disparues ou qui ne sont plus palette de référence
    for rack, _ in pairs(self.markers) do
        if not exists[rack] or rack.isDeleted then self:removeMarker(rack) end
    end
    for rack, _ in pairs(show) do
        local m = self.markers[rack]
        if m == nil then
            m = {}
            self.markers[rack] = m
            local args = { rack = rack }
            m.reqId = g_i3DManager:loadSharedI3DFileAsync(Utils.getFilename(self.MARKER_I3D, nil), false, false, self.onMarkerLoaded, self, args)
            args.reqId = m.reqId
        end
    end
    for rack, m in pairs(self.markers) do
        if m.node ~= nil and m.node ~= 0 then
            if show[rack] then
                local mx, my, mz = self:getMarkerPos(rack)
                setWorldTranslation(m.node, mx, my + 0.03, mz)
                setVisibility(m.node, true)
            else
                setVisibility(m.node, false)
            end
        end
    end
end

function AS_DualRack:draw()
    if g_currentMission == nil or g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then return end
    -- (v3.1.1) zone visible à pied ET au volant (position du joueur ou du véhicule conduit)
    local px, pz
    local cv = g_localPlayer:getCurrentVehicle()
    if cv ~= nil then
        local root = cv.rootVehicle or cv
        if root.rootNode == nil then return end
        local x, _, z = getWorldTranslation(root.rootNode)
        px, pz = x, z
    else
        local ok, x, _, z = pcall(g_localPlayer.getPosition, g_localPlayer)
        if not ok or x == nil then return end
        px, pz = x, z
    end
    local busy = {}
    for _, j in pairs(self.jobs) do
        for _, r in ipairs(j.racks or {}) do busy[r.id] = true end
    end
    local drawn = {}
    for _, rack in ipairs(self:allRacks()) do
        local rx, _, rz = getWorldTranslation(rack.rootNode)
        if MathUtil.vector2Length(rx - px, rz - pz) <= self.ZONE_SHOW_DIST then
            local ok, group, primary = pcall(self.getGroup, self, rack)
            if ok and primary ~= nil and not drawn[primary] then
                drawn[primary] = true
                local isBusy = false
                for _, r in ipairs(group) do
                    if busy[r:getUniqueId()] then isBusy = true end
                end
                pcall(self.drawZone, self, primary, isBusy)
                if cv == nil and not isBusy then
                    pcall(self.drawMarker, self, primary, px, pz)
                end
            end
        end
    end
    pcall(self.drawTimers, self)
end

function AS_DualRack:findTractorNear(rack)
    local vs = g_currentMission.vehicleSystem
    local rx, _, rz = getWorldTranslation(rack.rootNode)
    local best, bestD = nil, self.RANGE
    for _, v in pairs(vs.vehicles) do
        if v ~= rack and v == v.rootVehicle and v.spec_motorized ~= nil and v.spec_wheels ~= nil and v.rootNode ~= nil
            and v.configurations ~= nil and v.configurations.wheel ~= nil then
            local x, _, z = getWorldTranslation(v.rootNode)
            local d = MathUtil.vector2Length(x - rx, z - rz)
            if d <= bestD then best, bestD = v, d end
        end
    end
    return best
end

function AS_DualRack:onAction(actionName, inputValue)
    if g_currentMission == nil or not g_currentMission:getIsServer() or g_currentMission.missionDynamicInfo.isMultiplayer then
        popup( L("as_dual_mp"))
        return
    end
    local rack = self:getPlayerRack()
    if rack == nil then
        popup( L("as_dual_norack"))
        return
    end
    local vehicle = self:findTractorInZone(rack)
    if vehicle == nil and self:findTractorNear(rack) ~= nil then
        popup( L("as_dual_zone"))
        return
    end
    if vehicle == nil then
        popup( L("as_dual_notractor"))
        return
    end
    if not self.memoryLoaded then self:loadMemory() end
    local running = self.jobs[vehicle:getUniqueId()]
    if running ~= nil then
        popup(string.format(L("as_dual_running"), clockText(running.endMin)))
        return
    end
    if vehicle:getLastSpeed() > self.MAX_SPEED then
        popup( L("as_dual_stop"))
        return
    end
    local kind = rackKind(rack)
    local _, toDual, cur, reason = self:findTarget(vehicle, "ANY")
    if cur == nil then
        popup( L("as_dual_none"))
        return
    end
    local newIdx, racks = nil, nil
    local brandFail = nil
    local function pick(mode)
        local i, _, _, why, brands = self:findTarget(vehicle, mode)
        if why == "brand" and brandFail == nil then brandFail = brands end
        return i
    end
    if toDual then
        if kind == "ALL" then
            -- palette universelle : 4 pneus, elle doit être pleine
            if self:rackBusy(rack) then popup( L("as_dual_rackbusy")) return end
            if self:getRackCount(rack) < self:getRackCapacity(rack) then popup( L("as_dual_rackempty")) return end
            newIdx = pick("ANY")
            racks = { rack }
        else
            -- palettes AR / AV : AR obligatoire, AV en plus pour l'avant
            local ar = self:findRackNearVehicle(vehicle, "AR", true, rack)
            local av = self:findRackNearVehicle(vehicle, "AV", true, rack)
            if ar == nil then popup( L("as_dual_needar")) return end
            if av ~= nil then
                newIdx = pick("ALL")
                if newIdx ~= nil then racks = { av, ar } end
            end
            if newIdx == nil then
                newIdx = pick("BACK")
                racks = { ar }
                if newIdx == nil and av == nil and self:findTarget(vehicle, "ALL") ~= nil then
                    popup( L("as_dual_needav"))
                    return
                end
            end
        end
        if newIdx == nil then
            if brandFail ~= nil then
                local list = {}
                for _, b in ipairs(brandFail) do table.insert(list, AS_DualRack.getBrandTitle(b)) end
                popup( string.format(L("as_dual_brand"), AS_DualRack.getBrandTitle(AS_DualRack.getTireBrand(cur)), table.concat(list, ", ")))
            else
                popup( L("as_dual_none"))
            end
            return
        end
    else
        newIdx = self:findTarget(vehicle, "ANY")
        if newIdx == nil then
            popup( L(reason == "alreadyTwin" and "as_dual_alreadytwin" or "as_dual_nosingle"))
            return
        end
        if kind == "ALL" then
            if self:rackBusy(rack) then popup( L("as_dual_rackbusy")) return end
            if self:getRackCount(rack) > 0 then popup( L("as_dual_rackfull")) return end
            racks = { rack }
        else
            local ar = self:findRackNearVehicle(vehicle, "AR", false, rack)
            if ar == nil then popup( L("as_dual_needar_empty")) return end
            racks = { ar }
            if not isBackItem(cur) then
                local av = self:findRackNearVehicle(vehicle, "AV", false, rack)
                if av == nil then popup( L("as_dual_needav_empty")) return end
                racks = { av, ar }
            end
        end
    end
    -- (v2.9) confirmation avant de commencer : durée + avertissement
    local nTires = 0
    for _, r in ipairs(racks) do nTires = nTires + self:getRackCapacity(r) end
    local minutes = nTires * self.MIN_PER_TIRE
    local text = string.format(L(toDual and "as_dual_confirm_on" or "as_dual_confirm_off"), nTires, minutes, clockText(gameMinutes() + minutes))
    local function onAnswer(yes)
        if yes == true then self:startJob(vehicle, newIdx, toDual, racks) end
    end
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(onAnswer, nil, text, L("as_dual_confirm_title"))
    elseif g_gui ~= nil and g_gui.showYesNoDialog ~= nil then
        g_gui:showYesNoDialog({ title = L("as_dual_confirm_title"), text = text, callback = function(_, yes) onAnswer(yes) end })
    else
        onAnswer(true)
    end
end

-------------------------------------------------------------------------------
-- (v3.0) jumelées visibles pneu par pneu sur le tracteur + tracteur verrouillé
--   montage   : le tracteur passe tout de suite en jumelées (roues jumelées cachées),
--               puis elles apparaissent une par une pendant que la palette se vide.
--   démontage : les jumelées disparaissent une par une pendant que la palette se remplit,
--               puis le tracteur repasse en roues simples à la fin.
--   Pendant le chantier : impossible de monter dans le tracteur ou de lancer un ouvrier.
-------------------------------------------------------------------------------

-- roues jumelées visibles du tracteur (roues additionnelles), avant d'abord
function AS_DualRack:getTwinNodes(vehicle)
    if vehicle.__asTwinNodes ~= nil then return vehicle.__asTwinNodes end
    local list = {}
    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if wheels == nil or vehicle.rootNode == nil then return list end
    for _, w in ipairs(wheels) do
        if w.visualWheels ~= nil and #w.visualWheels >= 2 then
            local ref = w.repr or w.driveNode or w.node or w.linkNode
            local x, z = 0, 0
            if ref ~= nil and ref ~= 0 then
                local ok, lx, _, lz = pcall(localToLocal, ref, vehicle.rootNode, 0, 0, 0)
                if ok and type(lz) == "number" then x, z = lx, lz end
            end
            for k = 2, #w.visualWheels do
                local n = w.visualWheels[k].node
                if n ~= nil and n ~= 0 then table.insert(list, { node = n, z = z, x = x }) end
            end
        end
    end
    -- (v3.2.1) ordre fixe : essieu avant d'abord (comme la palette AV), puis gauche avant droite
    table.sort(list, function(a, b)
        if math.abs(a.z - b.z) > 0.3 then return a.z > b.z end
        return a.x > b.x
    end)
    if #list > 0 then vehicle.__asTwinNodes = list end
    return list
end

-- n jumelées visibles (les autres cachées) ; n = nil : toutes visibles
function AS_DualRack:setTwinVisible(vehicle, n)
    local nodes = self:getTwinNodes(vehicle)
    for i, e in ipairs(nodes) do
        setVisibility(e.node, n == nil or i <= n)
    end
    return #nodes
end

-- démontage : les k premières jumelées (avant d'abord) cachées, les autres visibles
function AS_DualRack:setTwinHiddenFirst(vehicle, k)
    local nodes = self:getTwinNodes(vehicle)
    for i, e in ipairs(nodes) do
        setVisibility(e.node, i > k)
    end
    return #nodes
end

-- (v3.2.1) état visuel imposé à chaque image (d'autres mods peuvent réafficher les roues)
function AS_DualRack:applyTwinState(j, v)
    if j.visMode == nil or v == nil or v.isDeleted then return end
    if j.visMode == "show" then
        self:setTwinVisible(v, j.visCount)
    elseif j.visMode == "hide" then
        self:setTwinHiddenFirst(v, j.visCount)
    end
end

function AS_DualRack:isLocked(vehicle)
    return vehicle ~= nil and vehicle.getUniqueId ~= nil and self.jobs[vehicle:getUniqueId()] ~= nil
end

-- verrou posé sur l'instance du tracteur (montée interdite, ouvrier interdit)
function AS_DualRack:installLock(vehicle)
    if vehicle == nil or vehicle.__asLock then return end
    vehicle.__asLock = true
    local function wrap(name, lockedValue)
        local orig = vehicle[name]
        if type(orig) ~= "function" then return end
        vehicle[name] = function(self, ...)
            if AS_DualRack:isLocked(self) then return lockedValue end
            return orig(self, ...)
        end
    end
    wrap("getIsEnterable", false)
    wrap("getIsTabbable", false)
    wrap("getCanStartAIVehicle", false)
end


-- lancement du chantier (après confirmation)
function AS_DualRack:startJob(vehicle, newIdx, toDual, racks)
    if vehicle == nil or vehicle.isDeleted or self.jobs[vehicle:getUniqueId()] ~= nil then return end
    for _, r in ipairs(racks) do
        if r.isDeleted or self:rackBusy(r) then notify("err", L("as_dual_rackbusy")) return end
    end
    if vehicle:getLastSpeed() > self.MAX_SPEED then notify("err", L("as_dual_stop")) return end
    local vs = g_currentMission.vehicleSystem
    if vs == nil or vs.isReloadRunning then notify("err", L("as_dual_failed")) return end
    local items = AS_DualRack.getWheelItems(vehicle)
    local curSid = items[vehicle.configurations.wheel].saveId
    local job = {
        uniqueId = vehicle:getUniqueId(), vehicle = vehicle,
        origSid = curSid, toSid = items[newIdx].saveId,
        curSid = toDual and items[newIdx].saveId or curSid,  -- configuration attendue pendant le chantier
        toDual = toDual, racks = {}, price = 0, farmId = vehicle:getOwnerFarmId(),
    }
    for _, r in ipairs(racks) do table.insert(job.racks, { id = r:getUniqueId(), cap = self:getRackCapacity(r) }) end
    job.startMin = gameMinutes()
    job.endMin = job.startMin + jobTotal(job) * self.MIN_PER_TIRE
    self.jobs[job.uniqueId] = job
    self:setJobRacks(job.racks, toDual, "start")
    if toDual then
        -- passage immédiat en jumelées, roues jumelées cachées
        local ok, res = pcall(self.doSwap, self, { vehicle = vehicle, newIdx = newIdx, mode = "mountStart", job = job })
        if not ok or not res then
            if not ok then print("[AS_DualRack] ERREUR : " .. tostring(res)) end
            self.jobs[job.uniqueId] = nil
            notify("err", L("as_dual_failed"))
            return
        end
    else
        job.visMode, job.visCount = "hide", 0
        self:installLock(vehicle)
    end
    notify("info", string.format(L(toDual and "as_dual_mounting" or "as_dual_unmounting"), clockText(job.endMin)))
end

-------------------------------------------------------------------------------
-- remplacement du tracteur par la même machine avec une autre configuration de roues
-- p.mode : "mountStart" (début du montage), "unmountEnd" (fin du démontage), "cancelMount" (annulation)
-------------------------------------------------------------------------------
function AS_DualRack:doSwap(p)
    local vehicle = p.vehicle
    local vs = g_currentMission.vehicleSystem
    if vs == nil or vs.isReloadRunning or vehicle == nil or vehicle.isDeleted then return false end

    local affected, used = {}, {}
    local function add(v)
        if v == nil or used[v] then return end
        if v.isVehicleSaved then
            v.isReconfigurating = true
            table.insert(affected, v)
            used[v] = true
            if v.getAttachedImplements ~= nil then
                for _, impl in pairs(v:getAttachedImplements()) do add(impl.object) end
            end
        end
    end
    add(vehicle)
    if #affected == 0 then return false end

    local xmlFile = XMLFile.create("asDualsReloadXML", "", "vehicles", Vehicle.xmlSchemaSavegame)
    if xmlFile == nil then return false end

    local oldIdx = vehicle.configurations.wheel
    vehicle.configurations.wheel = p.newIdx
    if vehicle.boughtConfigurations ~= nil and ConfigurationUtil ~= nil and ConfigurationUtil.addBoughtConfiguration ~= nil then
        pcall(ConfigurationUtil.addBoughtConfiguration, g_vehicleConfigurationManager, vehicle, "wheel", p.newIdx)
    end
    for _, v in ipairs(affected) do vs.vehicleByUniqueId[v:getUniqueId()] = nil end
    vs:saveToXML(affected, xmlFile, {})
    vehicle.configurations.wheel = oldIdx

    for _, v in ipairs(affected) do v.__asSwapping = true; v:removeFromPhysics() end
    local steerableId = nil
    local cur = shGetControlledVehicle()
    if cur ~= nil and used[cur.rootVehicle or cur] then steerableId = vehicle:getUniqueId() end
    local uniqueId = vehicle:getUniqueId()
    local job = p.job

    simulatePhysics(false)
    vs.isReloadRunning = true
    if p.mode == "mountStart" then AS_DualRack.hideTwinsFor = vehicle.configFileName end

    local function onLoaded(_, vehicles, state)
        AS_DualRack.hideTwinsFor = nil
        local success = state == VehicleLoadingState.OK and vehicles ~= nil and #vehicles == #affected
        local newVehicle = nil
        if success then
            for _, old in pairs(affected) do old:delete() end
            for _, nv in pairs(vehicles) do
                if nv:getUniqueId() == uniqueId then newVehicle = nv end
                if steerableId ~= nil and nv:getUniqueId() == steerableId and p.mode ~= "mountStart" then
                    g_localPlayer:requestToEnterVehicle(nv)
                end
            end
        else
            print("[AS_DualRack] ERREUR : changement de roues impossible, tracteur remis à l'identique")
            if vehicles ~= nil then for _, nv in pairs(vehicles) do nv:delete() end end
            for _, old in ipairs(affected) do
                old.isReconfigurating = false
                old.__asSwapping = nil
                old:addToPhysics()
                vs.vehicleByUniqueId[old:getUniqueId()] = old
            end
        end
        xmlFile:delete()
        vs.isReloadRunning = false
        simulatePhysics(true)

        if p.mode == "mountStart" then
            if success then
                if job ~= nil and job.origSid ~= nil then self.memory[uniqueId] = job.origSid end
                if job ~= nil then job.vehicle = newVehicle end
                if job ~= nil then job.visMode, job.visCount = "show", 0 end
                if newVehicle ~= nil then
                    self:installLock(newVehicle)
                    pcall(self.setTwinVisible, self, newVehicle, 0)
                end
            else
                if job ~= nil then
                    self.jobs[uniqueId] = nil
                    self:setJobRacks(job.racks, job.toDual, "start")
                end
                notify("err", L("as_dual_failed"))
            end
        elseif p.mode == "unmountEnd" then
            if success then
                self.memory[uniqueId] = nil
                if job ~= nil then self:setJobRacks(job.racks, false, "end") end
                notify("ok", L("as_dual_done_off"))
            else
                if job ~= nil then self:setJobRacks(job.racks, false, "start") end
                pcall(self.setTwinVisible, self, vehicle, nil)
                notify("err", L("as_dual_failed"))
            end
        elseif p.mode == "cancelMount" then
            if success then self.memory[uniqueId] = nil end
            if job ~= nil then self:setJobRacks(job.racks, true, "start") end
            notify("err", L(success and "as_dual_cancel" or "as_dual_failed"))
        end
    end

    g_asyncTaskManager:addTask(function()
        vs:loadFromXMLFile(xmlFile, onLoaded, nil, nil, false, true)
    end)
    return true
end

-- état des palettes d'un chantier : "start", "end" ou n° d'étape (pneus déjà déplacés)
function AS_DualRack:setJobRacks(list, toDual, state)
    local moved
    if state == "start" then moved = 0 elseif state == "end" then moved = math.huge else moved = state end
    for _, r in ipairs(list or {}) do
        local rack = self:findRackById(r.id)
        local m = math.min(r.cap, moved)
        moved = moved - m
        local n = toDual and (r.cap - m) or m
        if rack ~= nil then
            if self:getRackCount(rack) ~= n or rack.__asShown ~= n then pcall(self.setRackCount, self, rack, n) end
        else
            self.rackTires[r.id] = n
        end
    end
end

-- annulation d'un chantier (tracteur déplacé, palette disparue...)
function AS_DualRack:cancelJob(j, v, items)
    self.jobs[j.uniqueId] = nil
    if j.toDual then
        -- montage annulé : retour aux roues d'origine
        local idx = nil
        for i, it in ipairs(items or {}) do if it.saveId == j.origSid then idx = i break end end
        if idx ~= nil and v ~= nil then
            local ok, res = pcall(self.doSwap, self, { vehicle = v, newIdx = idx, mode = "cancelMount", job = j })
            if ok and res then return end
        end
        self:setJobRacks(j.racks, true, "start")
    else
        if v ~= nil then pcall(self.setTwinVisible, self, v, nil) end
        self:setJobRacks(j.racks, false, "start")
    end
    notify("err", L("as_dual_cancel"))
end

function AS_DualRack:update(dt)
    if self.actionEventId ~= nil then
        self.helpTimer = (self.helpTimer or 0) + (dt or 0)
        if self.helpTimer >= 300 then
            self.helpTimer = 0
            local near = self:getPlayerRack() ~= nil
            if near ~= self.helpVisible then
                self.helpVisible = near
                g_inputBinding:setActionEventTextVisibility(self.actionEventId, near)
            end
        end
    end
    for _, j in pairs(self.jobs) do
        if j.visMode ~= nil and j.vehicle ~= nil and not j.vehicle.isDeleted then
            pcall(self.applyTwinState, self, j, j.vehicle)
        end
    end
    local okM, errM = pcall(self.updateMarkers, self)
    if not okM and not self.markerErrPrinted then
        self.markerErrPrinted = true
        print("[AS_DualRack] ERREUR marqueur : " .. tostring(errM))
    end
    self.jobTimer = (self.jobTimer or 0) + (dt or 0)
    if self.jobTimer < 500 then return end
    self.jobTimer = 0
    local vs = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if vs == nil or vs.isReloadRunning then return end
    if not self.memoryLoaded then self:loadMemory() end
    -- palettes : pneus affichés selon leur état (nouvelle palette, chargement de partie...)
    for _, v in ipairs(self:allRacks()) do
        local n = self:getRackCount(v)
        if v.__asShown ~= n then pcall(self.setRackCount, self, v, n) end
    end
    if next(self.jobs) == nil or not g_currentMission:getIsServer() then return end
    local now = gameMinutes()
    for id, j in pairs(self.jobs) do
        local v = j.vehicle
        if v == nil or v.isDeleted then
            v = vs.vehicleByUniqueId ~= nil and vs.vehicleByUniqueId[id] or nil
            j.vehicle = v
        end
        if v ~= nil and not v.isDeleted then
            self:installLock(v)
            -- verrou : le joueur ne peut pas rester dans le tracteur
            if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() == v then
                pcall(g_localPlayer.leaveVehicle, g_localPlayer)
                notify("err", string.format(L("as_dual_locked"), clockText(j.endMin)))
            end
            local items = AS_DualRack.getWheelItems(v)
            local cur = items ~= nil and v.configurations ~= nil and items[v.configurations.wheel] or nil
            local allRacks = true
            for _, r in ipairs(j.racks or {}) do
                if self:findRackById(r.id) == nil then allRacks = false end
            end
            local total = jobTotal(j)
            if cur == nil or cur.saveId ~= j.curSid then
                -- la configuration ne correspond plus (partie non sauvegardée...) : chantier abandonné
                self.jobs[id] = nil
                self:setJobRacks(j.racks, j.toDual, "start")
                pcall(self.setTwinVisible, self, v, nil)
            elseif v:getLastSpeed() > self.MAX_SPEED or not allRacks or #(j.racks or {}) == 0 then
                self:cancelJob(j, v, items)
                return
            elseif now < j.endMin then
                -- un pneu de plus / de moins toutes les 15 min de jeu (palette + tracteur)
                local step = math.floor((now - (j.startMin or now)) / self.MIN_PER_TIRE)
                step = math.max(0, math.min(total - 1, step))
                self:setJobRacks(j.racks, j.toDual, step)
                local nNodes = #self:getTwinNodes(v)
                local moved = math.floor(step * nNodes / total + 0.5)
                -- palettes remplies / vidées dans l'ordre AV puis AR = jumelées avant d'abord
                j.visMode = j.toDual and "show" or "hide"
                j.visCount = moved
                self:applyTwinState(j, v)
            else
                if j.toDual then
                    -- montage terminé : toutes les jumelées visibles, palettes vides
                    self.jobs[id] = nil
                    j.visMode = nil
                    self:setTwinVisible(v, nil)
                    self:setJobRacks(j.racks, true, "end")
                    notify("ok", L("as_dual_done_on"))
                else
                    -- démontage terminé : retour aux roues simples
                    local newIdx = nil
                    for i, it in ipairs(items) do if it.saveId == j.toSid then newIdx = i break end end
                    self.jobs[id] = nil
                    local ok, res = false, false
                    j.visMode, j.visCount = "hide", math.huge
                    pcall(self.setTwinHiddenFirst, self, v, math.huge)
                    self:setJobRacks(j.racks, false, "end")
                    if newIdx ~= nil then
                        ok, res = pcall(self.doSwap, self, { vehicle = v, newIdx = newIdx, mode = "unmountEnd", job = j })
                        if not ok then print("[AS_DualRack] ERREUR : " .. tostring(res)) end
                    end
                    if not ok or not res then
                        pcall(self.setTwinVisible, self, v, nil)
                        self:setJobRacks(j.racks, false, "start")
                        notify("err", L("as_dual_failed"))
                    end
                end
                return -- un seul changement à la fois
            end
        end
    end
end

function AS_DualRack:loadMap()
    self:loadMemory()
end

function AS_DualRack:deleteMap()
    for rack, _ in pairs(self.markers) do pcall(self.removeMarker, self, rack) end
    self.markers = {}
    self.jobs = {}
    self.rackTires = {}
    self.memoryLoaded = false
    self.actionEventId = nil
    self.helpVisible = nil
end

-- (v2.5) touche enregistrée dans le contexte du joueur À PIED
if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents ~= nil then
    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, function(self)
        if self.player == nil or not self.player.isOwner or InputAction == nil or InputAction.AS_DUAL_SWITCH == nil then return end
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        if AS_DualRack.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(AS_DualRack.actionEventId)
            AS_DualRack.actionEventId = nil
        end
        local _, id = g_inputBinding:registerActionEvent(InputAction.AS_DUAL_SWITCH, AS_DualRack, AS_DualRack.onAction, false, true, false, true)
        if id ~= nil then
            AS_DualRack.actionEventId = id
            AS_DualRack.helpVisible = false
            g_inputBinding:setActionEventText(id, L("input_AS_DUAL_SWITCH"))
            g_inputBinding:setActionEventTextVisibility(id, false)
        end
        g_inputBinding:endActionEventsModification()
    end)
end

-- (v3.3.1) au début d'un montage, les roues jumelées du tracteur rechargé sont cachées
-- dès leur création (avant le premier affichage) : plus d'apparition furtive
if Wheel ~= nil and Wheel.loadFromXML ~= nil then
    Wheel.loadFromXML = Utils.overwrittenFunction(Wheel.loadFromXML, function(self, superFunc, ...)
        local r = superFunc(self, ...)
        local cfg = AS_DualRack.hideTwinsFor
        if cfg ~= nil and self.vehicle ~= nil and self.vehicle.configFileName == cfg and self.visualWheels ~= nil then
            for k = 2, #self.visualWheels do
                local n = self.visualWheels[k].node
                if n ~= nil and n ~= 0 then setVisibility(n, false) end
            end
        end
        return r
    end)
end

-- (v2.5) pendant le changement, l'ancien tracteur (retiré de la physique) n'est plus mis à jour :
-- évite les erreurs "Wheel shape not found" dans le log
if Vehicle ~= nil then
    for _, fn in ipairs({"update", "updateTick", "updateEnd"}) do
        if Vehicle[fn] ~= nil then
            Vehicle[fn] = Utils.overwrittenFunction(Vehicle[fn], function(self, superFunc, ...)
                if self.__asSwapping then return end
                return superFunc(self, ...)
            end)
        end
    end
end

-- écriture au moment où le jeu sauvegarde la partie
if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_DualRack.saveMemory, AS_DualRack)
        if not ok then print("[AS_DualRack] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

addModEventListener(AS_DualRack)
