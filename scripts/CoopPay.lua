-- AutoSwitch : coopératives payées en fin de mois
-- Fichier chargé par AutoSwitch.lua (après Common.lua, avant Register.lua).

-------------------------------------------------------------------------------
-- v1.0.0.81 : une vente à une coopérative se fait comme d'habitude (le produit part),
--   mais l'argent n'est pas versé tout de suite : il est noté « À payer » dans le
--   registre (onglet Ventes) et le total du mois est versé au changement de mois
--   (dernier jour du mois à minuit), ligne « Coopératives » dans Finances.
--   Coopérative = point de vente dont le nom contient « coop » (coopérative, cooperative,
--   co-op) ou « genossenschaft ». Chaque point de vente est noté dans
--   modSettings/FS25_AutoSwitch/cooperatives.xml : coop="true" / "false" pour corriger.
--   Ce qui reste dû est gardé avec la partie (AutoSwitch_coop.xml dans la sauvegarde).
-- v1.0.0.86 : plus de lignes [AS_CoopPay] dans le log, sauf les erreurs.
-- v1.0.1.0 : lignes [AS_CoopPay] remises dans le log (points de vente, sommes dues, versement du mois).
-------------------------------------------------------------------------------
AS_CoopPay = {}
AS_CoopPay.ENABLED   = true
AS_CoopPay.FILE_NAME = "AutoSwitch_coop.xml"
AS_CoopPay.KEYWORDS  = { "coop", "co-op", "genossenschaft" }
AS_CoopPay.stations  = {}   -- nom -> true / false (coopérative ou non)
AS_CoopPay.order     = {}   -- ordre d'inscription (fichier lisible)
AS_CoopPay.owed      = {}   -- farmId -> { money, key } (key = année * 100 + mois de la vente)
AS_CoopPay.listLoaded = false
AS_CoopPay.active    = nil  -- vente en cours : { farmId, withheld }

local STAT_NAME = "asCoopPayment"

-- Ligne « Coopératives » dans Finances (texte finance_asCoopPayment)
if FinanceStats ~= nil and FinanceStats.statNames ~= nil and FinanceStats.statNameToIndex ~= nil
    and FinanceStats.statNameToIndex[STAT_NAME] == nil then
    table.insert(FinanceStats.statNames, STAT_NAME)
    FinanceStats.statNameToIndex[STAT_NAME] = #FinanceStats.statNames
end

-- le menu Finances lit le texte sans le nom du mod (même correctif que les agios, v1.0.0.72)
local MOD_NAME = g_currentModName or "FS25_AutoSwitch"
if I18N ~= nil and I18N.getText ~= nil then
    I18N.getText = Utils.overwrittenFunction(I18N.getText, function(i18n, superFunc, text, modEnv, ...)
        if modEnv == nil and text == "finance_" .. STAT_NAME then
            return superFunc(i18n, text, MOD_NAME, ...)
        end
        return superFunc(i18n, text, modEnv, ...)
    end)
end

local function getMoneyType()
    if AS_CoopPay.moneyType == nil and MoneyType ~= nil and MoneyType.register ~= nil then
        local ok, mt = pcall(MoneyType.register, STAT_NAME, "finance_" .. STAT_NAME)
        if ok and mt ~= nil then AS_CoopPay.moneyType = mt end
    end
    return AS_CoopPay.moneyType or (MoneyType ~= nil and MoneyType.OTHER) or nil
end

local function monthKey()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return nil end
    return (env.currentYear or 0) * 100 + (env.currentPeriod or 0)
end

-------------------------------------------------------------------------------
-- Liste des points de vente (modSettings/FS25_AutoSwitch/cooperatives.xml)
-------------------------------------------------------------------------------

local function listPath()
    local dir = (AS_Settings ~= nil and AS_Settings.MOD_DIR_NAME) or g_currentModName or "FS25_AutoSwitch"
    return getUserProfileAppPath() .. "modSettings/" .. dir .. "/", "cooperatives.xml"
end

function AS_CoopPay:loadList()
    if self.listLoaded then return end
    self.listLoaded = true
    local dir, name = listPath()
    if not fileExists(dir .. name) then return end
    local xml = loadXMLFile("asCooperatives", dir .. name)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("cooperatives.station(%d)", i)
        local n = getXMLString(xml, key .. "#name")
        if n == nil then break end
        if self.stations[n] == nil then
            self.stations[n] = getXMLBool(xml, key .. "#coop") == true
            table.insert(self.order, n)
        end
        i = i + 1
    end
    delete(xml)
end

function AS_CoopPay:saveList()
    local dir, name = listPath()
    local ok, err = pcall(function()
        createFolder(getUserProfileAppPath() .. "modSettings/")
        createFolder(dir)
        local xml = createXMLFile("asCooperatives", dir .. name, "cooperatives")
        if xml == nil or xml == 0 then return end
        setXMLString(xml, "cooperatives#info", "coop = true : paye en fin de mois / false : paye tout de suite")
        for i, n in ipairs(self.order) do
            local key = string.format("cooperatives.station(%d)", i - 1)
            setXMLString(xml, key .. "#name", n)
            setXMLBool(xml, key .. "#coop", self.stations[n] == true)
        end
        saveXMLFile(xml)
        delete(xml)
    end)
    if not ok then print("[AS_CoopPay] enregistrement de cooperatives.xml impossible : " .. tostring(err)) end
end

local function guessCoop(name)
    local low = string.lower(name)
    for _, k in ipairs(AS_CoopPay.KEYWORDS) do
        if string.find(low, k, 1, true) then return true end
    end
    return false
end

-- point de vente inscrit dans la liste (nouveau : deviné d'après son nom) ; true si coopérative
function AS_CoopPay:isCoop(name)
    if type(name) ~= "string" or name == "" or name == "?" then return false end
    self:loadList()
    local v = self.stations[name]
    if v == nil then
        v = guessCoop(name)
        self.stations[name] = v
        table.insert(self.order, name)
        self:saveList()
        print(string.format("[AS_CoopPay] point de vente « %s » : %s", name, v and "coopérative (fin de mois)" or "payé tout de suite"))
    end
    return v
end

-- au chargement de la carte : tous les points de vente sont inscrits dans la liste
function AS_CoopPay:scanStations(nameOf)
    local ss = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if ss == nil or ss.getUnloadingStations == nil then return end
    local ok, stations = pcall(ss.getUnloadingStations, ss)
    if not ok or type(stations) ~= "table" then return end
    for _, st in pairs(stations) do
        if type(st) == "table" and (SellingStation == nil or st.isa == nil or st:isa(SellingStation)) then
            self:isCoop(nameOf(st))
        end
    end
end

-------------------------------------------------------------------------------
-- Vente : appelé par le registre autour de SellingStation:sellFillType
-------------------------------------------------------------------------------

-- avant la vente : si coopérative, l'argent versé par le jeu pendant la vente est retenu
function AS_CoopPay:beginSale(farmId, name)
    self.active = nil
    if not self.ENABLED or g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if not self:isCoop(name) then return end
    local mission = g_currentMission
    local prev = rawget(mission, "addMoney")
    local cur = { farmId = farmId, withheld = 0, prev = prev }
    local orig = mission.addMoney
    mission.addMoney = function(m, amount, fId, ...)
        if fId == cur.farmId and type(amount) == "number" and amount > 0 then
            cur.withheld = cur.withheld + amount
            return
        end
        return orig(m, amount, fId, ...)
    end
    self.active = cur
end

-- après la vente : somme retenue (0 si pas une coopérative)
-- received = argent arrivé quand même sur le compte (vente payée sans passer par addMoney)
function AS_CoopPay:endSale(received)
    local cur = self.active
    self.active = nil
    if cur == nil then return 0 end
    g_currentMission.addMoney = cur.prev   -- nil : la fonction de la classe revient
    if type(received) == "number" and received > 0 then
        g_currentMission:addMoney(-received, cur.farmId, MoneyType ~= nil and MoneyType.SOLD_PRODUCTS or nil, true, false)
        cur.withheld = cur.withheld + received
    end
    if cur.withheld > 0 then
        self:addOwed(cur.farmId, cur.withheld)
    end
    return cur.withheld
end

function AS_CoopPay:addOwed(farmId, money)
    local key = monthKey() or 0
    local o = self.owed[farmId]
    if o ~= nil and o.key < key then
        self:pay(farmId)   -- reste d'un mois passé (sécurité)
        o = nil
    end
    if o == nil then
        o = { money = 0, key = key }
        self.owed[farmId] = o
    end
    o.money = o.money + money
end

function AS_CoopPay:getOwed(farmId)
    local o = self.owed[farmId]
    return o ~= nil and o.money or 0
end

-- versement du mois : argent sur le compte, lignes du registre marquées « Payé »
function AS_CoopPay:pay(farmId)
    local o = self.owed[farmId]
    self.owed[farmId] = nil
    if o == nil or o.money <= 0 then return end
    local money = math.floor(o.money + 0.5)
    g_currentMission:addMoney(money, farmId, getMoneyType(), true, true)
    if AS_Register ~= nil and AS_Register.markPaid ~= nil then
        pcall(AS_Register.markPaid, AS_Register, farmId)
    end
    print(string.format("[AS_CoopPay] ferme %d : %d versés par les coopératives (mois %d)", farmId, money, o.key))
    local isLocalFarm = g_currentMission.getFarmId == nil or g_currentMission:getFarmId() == farmId
    if isLocalFarm and AS.showTimedNotification ~= nil and FSBaseMission ~= nil then
        local s = g_i18n ~= nil and g_i18n.formatMoney ~= nil and g_i18n:formatMoney(money, 0, true, true) or tostring(money)
        AS.showTimedNotification("alert", FSBaseMission.INGAME_NOTIFICATION_OK, string.format(AS.L("vtpas_coopPay_paid"), s))
    end
end

-------------------------------------------------------------------------------
-- Sauvegarde / chargement de ce qui reste dû
-------------------------------------------------------------------------------

local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_CoopPay.FILE_NAME
end

function AS_CoopPay:save()
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asCoop", path, "coop")
    if xml == nil or xml == 0 then return end
    local i = 0
    for farmId, o in pairs(self.owed) do
        local key = string.format("coop.owed(%d)", i)
        setXMLInt(xml, key .. "#farmId", farmId)
        setXMLFloat(xml, key .. "#money", o.money)
        setXMLInt(xml, key .. "#month", o.key)
        i = i + 1
    end
    saveXMLFile(xml)
    delete(xml)
end

function AS_CoopPay:load()
    self.owed = {}
    local path = savegamePath()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("asCoop", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("coop.owed(%d)", i)
        local farmId = getXMLInt(xml, key .. "#farmId")
        if farmId == nil then break end
        local money = getXMLFloat(xml, key .. "#money") or 0
        if money > 0 then
            self.owed[farmId] = { money = money, key = getXMLInt(xml, key .. "#month") or 0 }
            print(string.format("[AS_CoopPay] ferme %d : %d à recevoir des coopératives", farmId, math.floor(money)))
        end
        i = i + 1
    end
    delete(xml)
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_CoopPay.save, AS_CoopPay)
        if not ok then print("[AS_CoopPay] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

function AS_CoopPay:loadMap()
    getMoneyType()
    local ok, err = pcall(self.load, self)
    if not ok then print("[AS_CoopPay] ERREUR chargement : " .. tostring(err)) end
    self.scanned = false
end

-- changement de mois : tout ce qui a été vendu le mois d'avant est versé
function AS_CoopPay:update(dt)
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then return end
    -- sécurité : une erreur pendant une vente a pu laisser addMoney détourné
    if self.active ~= nil then
        local cur = self.active
        self.active = nil
        mission.addMoney = cur.prev
        if cur.withheld > 0 then self:addOwed(cur.farmId, cur.withheld) end
    end
    if not self.scanned and AS_Register ~= nil and AS_Register.stationName ~= nil then
        self.scanned = true
        local ok, err = pcall(self.scanStations, self, AS_Register.stationName)
        if not ok then print("[AS_CoopPay] liste des points de vente : " .. tostring(err)) end
    end
    if next(self.owed) == nil then return end
    local key = monthKey()
    if key == nil then return end
    for farmId, o in pairs(self.owed) do
        if o.key < key then
            local ok, err = pcall(self.pay, self, farmId)
            if not ok then print("[AS_CoopPay] ERREUR versement : " .. tostring(err)) end
        end
    end
end

function AS_CoopPay:deleteMap()
    self.owed = {}
    self.active = nil
    self.scanned = false
end

addModEventListener(AS_CoopPay)
