-- AutoSwitch : horaires d'ouverture du magasin et des points de vente
-- Fichier chargé par AutoSwitch.lua (après Overdraft.lua et Register.lua).

-------------------------------------------------------------------------------
-- v1.0.0.95 : deux horaires, réglables dans l'onglet AUTOSWITCH.
--   Magasin (8 h - 19 h par défaut) : la boutique et le mode construction restent
--   consultables, mais acheter, louer, vendre ou placer un bâtiment est refusé
--   hors horaires (fenêtre « Magasin fermé »).
--   Points de vente / industries (6 h - 22 h par défaut) : hors horaires, le point
--   de vente n'accepte plus rien (place libre à 0 pour les remorques, palettes
--   refusées) ; un camion AutoDrive attend sur place l'ouverture.
--   Chaque point de vente est noté dans modSettings/FS25_AutoSwitch/horaires.xml :
--   open / close = -1 : horaires du menu ; open="0" close="24" : ouvert 24 h/24 ;
--   autres valeurs : heures propres à ce point de vente.
--   Ouverture après la fermeture (ex. 22 h - 6 h) : ouvert la nuit.
-------------------------------------------------------------------------------
AS_Hours = {}
AS_Hours.ENABLED    = true
AS_Hours.SHOP_OPEN  = 8
AS_Hours.SHOP_CLOSE = 19
AS_Hours.SELL_OPEN  = 6
AS_Hours.SELL_CLOSE = 22
AS_Hours.NOTIFY_MS  = 60000   -- une notification par point de vente fermé et par minute
AS_Hours.stations   = {}      -- nom -> { open, close } (-1 = horaires du menu)
AS_Hours.order      = {}
AS_Hours.listLoaded = false
AS_Hours.notified   = {}      -- nom -> temps de la dernière notification

local function L(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback or key
end

-- heure du jeu (0 - 24, avec les minutes)
local function hourNow()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil or type(env.dayTime) ~= "number" then return nil end
    return (env.dayTime / 3600000) % 24
end

local function isOpenAt(open, close, h)
    if h == nil or open == close or (open <= 0 and close >= 24) then return true end
    if open < close then return h >= open and h < close end
    return h >= open or h < close
end

local function hourText(h)
    return string.format("%d h", math.floor(h) % 24)
end

local function now()
    return (g_currentMission ~= nil and g_currentMission.time) or 0
end

-------------------------------------------------------------------------------
-- Liste des points de vente (modSettings/FS25_AutoSwitch/horaires.xml)
-------------------------------------------------------------------------------

local function listPath()
    local dir = (AS_Settings ~= nil and AS_Settings.MOD_DIR_NAME) or g_currentModName or "FS25_AutoSwitch"
    return getUserProfileAppPath() .. "modSettings/" .. dir .. "/", "horaires.xml"
end

function AS_Hours:loadList()
    if self.listLoaded then return end
    self.listLoaded = true
    local dir, name = listPath()
    if not fileExists(dir .. name) then return end
    local xml = loadXMLFile("asHours", dir .. name)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("horaires.station(%d)", i)
        local n = getXMLString(xml, key .. "#name")
        if n == nil then break end
        if self.stations[n] == nil then
            self.stations[n] = { open = getXMLInt(xml, key .. "#open") or -1, close = getXMLInt(xml, key .. "#close") or -1 }
            table.insert(self.order, n)
        end
        i = i + 1
    end
    delete(xml)
end

function AS_Hours:saveList()
    local dir, name = listPath()
    local ok, err = pcall(function()
        createFolder(getUserProfileAppPath() .. "modSettings/")
        createFolder(dir)
        local xml = createXMLFile("asHours", dir .. name, "horaires")
        if xml == nil or xml == 0 then return end
        setXMLString(xml, "horaires#info", "open / close : heures (0-24). -1 = horaires du menu AUTOSWITCH. open=0 close=24 : ouvert 24 h/24")
        for i, n in ipairs(self.order) do
            local key = string.format("horaires.station(%d)", i - 1)
            local s = self.stations[n]
            setXMLString(xml, key .. "#name", n)
            setXMLInt(xml, key .. "#open", s.open)
            setXMLInt(xml, key .. "#close", s.close)
        end
        saveXMLFile(xml)
        delete(xml)
    end)
    if not ok then print("[AS_Hours] enregistrement de horaires.xml impossible : " .. tostring(err)) end
end

local function stationName(station)
    if AS_Register ~= nil and AS_Register.stationName ~= nil then
        local ok, n = pcall(AS_Register.stationName, station)
        if ok and type(n) == "string" then return n end
    end
    return station.stationName or "?"
end

-- horaires du point de vente (inscrit dans la liste s'il est nouveau)
function AS_Hours:getStationHours(name)
    self:loadList()
    local s = self.stations[name]
    if s == nil and name ~= "?" and name ~= "" then
        s = { open = -1, close = -1 }
        self.stations[name] = s
        table.insert(self.order, name)
        self:saveList()
    end
    if s ~= nil and s.open >= 0 and s.close >= 0 then
        return s.open, s.close
    end
    return self.SELL_OPEN, self.SELL_CLOSE
end

-- au chargement de la carte : tous les points de vente sont inscrits dans la liste
function AS_Hours:scanStations()
    local ss = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if ss == nil or ss.getUnloadingStations == nil then return end
    local ok, stations = pcall(ss.getUnloadingStations, ss)
    if not ok or type(stations) ~= "table" then return end
    for _, st in pairs(stations) do
        if type(st) == "table" and SellingStation ~= nil and st.isa ~= nil and st:isa(SellingStation) then
            self:getStationHours(stationName(st))
        end
    end
end

-------------------------------------------------------------------------------
-- Points de vente : rien n'est accepté hors horaires
-------------------------------------------------------------------------------

-- true si le point de vente est fermé (et notification au joueur, une par minute)
function AS_Hours:isStationClosed(station)
    if not self.ENABLED then return false end
    local h = hourNow()
    if h == nil then return false end
    local name = stationName(station)
    local open, close = self:getStationHours(name)
    if isOpenAt(open, close, h) then return false end
    local t = now()
    local last = self.notified[name]
    if last == nil or t - last > self.NOTIFY_MS or t < last then
        self.notified[name] = t
        if AS.showTimedNotification ~= nil and FSBaseMission ~= nil then
            AS.showTimedNotification("alert", FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format(L("vtpas_hours_stationClosed", "%s : fermé, ouvre à %s"), name, hourText(open)))
        end
    end
    return true
end

local function hookStation(funcName, closedValue)
    if SellingStation == nil or SellingStation[funcName] == nil then
        print("[AS_Hours] SellingStation." .. funcName .. " introuvable")
        return
    end
    SellingStation[funcName] = Utils.overwrittenFunction(SellingStation[funcName], function(station, superFunc, ...)
        local ok, closed = pcall(AS_Hours.isStationClosed, AS_Hours, station)
        if ok and closed then return closedValue end
        return superFunc(station, ...)
    end)
end

hookStation("getFreeCapacity", 0)
hookStation("addFillLevelFromTool", 0)
hookStation("getIsFillAllowedFromFarm", false)

-------------------------------------------------------------------------------
-- Magasin : achat, location, vente et construction refusés hors horaires
-------------------------------------------------------------------------------

function AS_Hours:isShopClosed()
    if not self.ENABLED then return false end
    return not isOpenAt(self.SHOP_OPEN, self.SHOP_CLOSE, hourNow())
end

function AS_Hours:showShopClosed()
    local text = string.format(L("vtpas_hours_shopClosed", "Le magasin est fermé. Ouvert de %s à %s."),
        hourText(self.SHOP_OPEN), hourText(self.SHOP_CLOSE))
    if InfoDialog ~= nil and InfoDialog.show ~= nil then
        local ok = pcall(InfoDialog.show, text, nil, nil, DialogElement ~= nil and DialogElement.TYPE_WARNING or nil)
        if ok then return end
    end
    if AS.showTimedNotification ~= nil and FSBaseMission ~= nil then
        AS.showTimedNotification("alert", FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
    end
end

-- classe, motifs des fonctions (en minuscules) qui achètent, louent ou vendent
local SHOP_SCOPES = {
    { "ShopConfigScreen",           { "^onclickbuy", "^onclicklease", "^onclicksell" } },
    { "ShopMenu",                   { "^onclickbuy", "^onclicklease", "^onclicksell" } },
    { "ShopItemsFrame",             { "^onclickbuy", "^onclicklease", "^onclicksell" } },
    { "WorkshopScreen",             { "^onclicksell" } },
    { "ConstructionBrushPlaceable", { "^onbuttonprimary$" } },
    { "ConstructionBrushSell",      { "^onbuttonprimary$" } },
}

local done = {}        -- « classe.fonction » déjà enrobée
local origToWrap = {}  -- fonction remplacée -> fonction d'AutoSwitch
AS_Hours.shopHooks = {}

local function matches(name, patterns)
    local low = string.lower(name)
    for _, p in ipairs(patterns) do
        if string.find(low, p) then return true end
    end
    return false
end

function AS_Hours:installShopScopes()
    for _, s in ipairs(SHOP_SCOPES) do
        local class = _G[s[1]]
        if type(class) == "table" then
            local names = {}
            for k, v in pairs(class) do
                if type(k) == "string" and type(v) == "function" and matches(k, s[2]) then
                    names[#names + 1] = k
                end
            end
            for _, k in ipairs(names) do
                local label = s[1] .. "." .. k
                if not done[label] then
                    done[label] = true
                    local orig = class[k]
                    local f = function(...)
                        if AS_Hours:isShopClosed() then
                            AS_Hours:showShopClosed()
                            return
                        end
                        return orig(...)
                    end
                    origToWrap[orig] = f
                    class[k] = f
                    table.insert(self.shopHooks, label)
                end
            end
        end
    end
end

-- les boutons des écrans gardent la fonction lue au démarrage (même correctif que le découvert)
function AS_Hours:rebindCallbacks()
    local seen, count = {}, 0
    local function walk(t, level)
        if type(t) ~= "table" or seen[t] or level > 8 then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "function" then
                local w = origToWrap[v]
                if w ~= nil then
                    t[k] = w
                    count = count + 1
                end
            elseif type(v) == "table" and k ~= "parent" then
                walk(v, level + 1)
            end
        end
    end
    local roots = { g_gui, g_shopConfigScreen, g_shopMenu, g_inGameMenu, g_constructionScreen, g_workshopScreen }
    for _, r in pairs(roots) do
        local ok, err = pcall(walk, r, 0)
        if not ok then print("[AS_Hours] parcours des écrans : " .. tostring(err)) end
    end
    return count
end

AS_Hours:installShopScopes()

-------------------------------------------------------------------------------

function AS_Hours:loadMap()
    self:installShopScopes()
    local rebound = self:rebindCallbacks()
    print(string.format("[AutoSwitch] Horaires : %d fonctions du magasin suivies (%s), %d boutons reliés",
        #self.shopHooks, table.concat(self.shopHooks, ", "), rebound))
    self.scanned = false
    self.notified = {}
end

function AS_Hours:update(dt)
    if not self.scanned and g_currentMission ~= nil then
        self.scanned = true
        local ok, err = pcall(self.scanStations, self)
        if not ok then print("[AS_Hours] liste des points de vente : " .. tostring(err)) end
    end
end

function AS_Hours:deleteMap()
    self.scanned = false
    self.notified = {}
end

addModEventListener(AS_Hours)
