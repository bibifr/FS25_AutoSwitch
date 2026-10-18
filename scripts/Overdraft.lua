-- AutoSwitch : découvert bancaire (achat / location avec le compte dans le rouge, agios)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.67 : le jeu laisse le compte passer sous zéro (salaires, entretien...)
--   mais refuse tout achat ou location dont le prix dépasse le solde.
--   Ici, pendant les contrôles d'achat du jeu (boutique, location, bâtiments,
--   terrains), le solde lu par le jeu est augmenté du plafond de découvert :
--   l'achat passe tant que le solde après achat reste au-dessus de -plafond.
--   Plafond = PERCENT % de la valeur de revente de ce que la ferme possède :
--   matériel acheté (pas la location), terres et bâtiments.
--   Agios : chaque jour de jeu, solde négatif x RATE % / an, au prorata du
--   nombre de jours de l'année (12 mois x jours par mois de la partie).
--   Ligne « Agios » dans Finances. Le jeu affiche toujours le vrai solde.
--   PERCENT = 0 : découvert coupé (jeu de base), plus d'agios.
-------------------------------------------------------------------------------
AS_Overdraft = {}
AS_Overdraft.PERCENT  = 20     -- plafond : % de la valeur de revente des biens
AS_Overdraft.RATE     = 10     -- agios : taux annuel en %
AS_Overdraft.CACHE_MS = 2000   -- valeur des biens recalculée au plus toutes les 2 s
AS_Overdraft.depth    = 0      -- > 0 pendant un contrôle d'achat du jeu
AS_Overdraft.cache    = {}     -- farmId -> { time, value }
AS_Overdraft.lastDay  = nil
AS_Overdraft.logged   = {}     -- fonction -> true (journal : une ligne par fonction)

local STAT_NAME = "asOverdraftInterest"

-- Ligne « Agios » dans Finances (texte finance_asOverdraftInterest)
if FinanceStats ~= nil and FinanceStats.statNames ~= nil and FinanceStats.statNameToIndex ~= nil
    and FinanceStats.statNameToIndex[STAT_NAME] == nil then
    table.insert(FinanceStats.statNames, STAT_NAME)
    FinanceStats.statNameToIndex[STAT_NAME] = #FinanceStats.statNames
end

-- v1.0.0.72 : le menu Finances du jeu lit le texte sans le nom du mod et affichait
-- « Missing 'finance_asOverdraftInterest' » : ce texte est cherché dans les fichiers d'AutoSwitch.
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
    if AS_Overdraft.moneyType == nil and MoneyType ~= nil and MoneyType.register ~= nil then
        local ok, mt = pcall(MoneyType.register, STAT_NAME, "finance_" .. STAT_NAME)
        if ok and mt ~= nil then AS_Overdraft.moneyType = mt end
    end
    return AS_Overdraft.moneyType or (MoneyType ~= nil and MoneyType.OTHER) or nil
end

local function now()
    return (g_currentMission ~= nil and g_currentMission.time) or 0
end

-- Valeur de revente de ce que la ferme possède (matériel acheté, terres, bâtiments)
function AS_Overdraft:getAssetValue(farmId)
    local total = 0
    local mission = g_currentMission
    local vs = mission.vehicleSystem
    if vs ~= nil and vs.vehicles ~= nil then
        for _, v in pairs(vs.vehicles) do
            if v.ownerFarmId == farmId and v.getSellPrice ~= nil and not v.isDeleted
                and (VehiclePropertyState == nil or v.propertyState == VehiclePropertyState.OWNED) then
                local ok, p = pcall(v.getSellPrice, v)
                if ok and type(p) == "number" and p > 0 then total = total + p end
            end
        end
    end
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlands ~= nil then
        for _, fl in pairs(g_farmlandManager:getFarmlands()) do
            if g_farmlandManager:getFarmlandOwner(fl.id) == farmId and type(fl.price) == "number" then
                total = total + fl.price
            end
        end
    end
    local ps = mission.placeableSystem
    if ps ~= nil and ps.placeables ~= nil then
        for _, p in pairs(ps.placeables) do
            if p.ownerFarmId == farmId and p.getSellPrice ~= nil then
                local ok, sp = pcall(p.getSellPrice, p)
                if ok and type(sp) == "number" and sp > 0 then total = total + sp end
            end
        end
    end
    return total
end

-- Plafond du découvert de la ferme (en €, positif)
function AS_Overdraft:getLimit(farmId)
    if self.PERCENT <= 0 or farmId == nil or g_currentMission == nil then return 0 end
    if FarmManager ~= nil and farmId == FarmManager.SPECTATOR_FARM_ID then return 0 end
    local c = self.cache[farmId]
    local t = now()
    if c == nil or t - c.time > self.CACHE_MS or t < c.time then
        local ok, v = pcall(self.getAssetValue, self, farmId)
        c = { time = t, value = (ok and v) or 0 }
        self.cache[farmId] = c
    end
    return c.value * self.PERCENT / 100
end

local function currentFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local ok, id = pcall(g_currentMission.getFarmId, g_currentMission)
        if ok then return id end
    end
    return nil
end

-- v1.0.0.68 : la 1.0.0.67 augmentait seulement getMoney / getBalance, mais le jeu lit
-- aussi farm.money directement : l'achat restait refusé. Désormais, pendant un
-- contrôle d'achat, le champ farm.money lui-même est augmenté du plafond, puis remis.
-- Tout mouvement d'argent pendant ce temps (Farm.changeBalance) se fait sur le vrai
-- solde : l'affichage et la sauvegarde ne voient jamais le solde augmenté.
AS_Overdraft.boostFarm = nil   -- ferme dont farm.money est augmenté
AS_Overdraft.boost     = 0     -- montant ajouté

local function getFarm(farmId)
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and farmId ~= nil then
        local ok, farm = pcall(g_farmManager.getFarmById, g_farmManager, farmId)
        if ok then return farm end
    end
    return nil
end

-- v1.0.0.76 : financement Trade In choisi (ou en cours) -> pas de découvert pour cet achat.
-- Trade In calculait le montant à financer avec le solde augmenté, puis revérifiait
-- avec le vrai solde : achat refusé alors que le crédit était déjà versé.
-- Sans le découvert, Trade In finance toute la somme manquante, comme sans AutoSwitch.
local function isTradeInFinancing()
    local mod = g_currentMission ~= nil and g_currentMission.tradeInMod or nil
    local finance = type(mod) == "table" and mod.finance or nil
    if type(finance) ~= "table" then return false end
    return finance.pending ~= nil or finance.purchaseInProgress == true
end

function AS_Overdraft:applyBoost()
    if isTradeInFinancing() then return end
    local farm = getFarm(currentFarmId())
    if farm == nil or type(farm.money) ~= "number" then return end
    local limit = self:getLimit(farm.farmId)
    if limit <= 0 then return end
    self.boostFarm, self.boost = farm, limit
    farm.money = farm.money + limit
end

function AS_Overdraft:removeBoost()
    local farm = self.boostFarm
    if farm ~= nil and type(farm.money) == "number" then
        farm.money = farm.money - self.boost
        -- les affichages du solde (magasin, HUD) reprennent le vrai solde
        if g_messageCenter ~= nil and MessageType ~= nil and MessageType.MONEY_CHANGED ~= nil then
            pcall(g_messageCenter.publish, g_messageCenter, MessageType.MONEY_CHANGED, farm.farmId, farm.money)
        end
    end
    self.boostFarm, self.boost = nil, 0
end

if Farm ~= nil and Farm.changeBalance ~= nil then
    Farm.changeBalance = Utils.overwrittenFunction(Farm.changeBalance, function(farm, superFunc, ...)
        if farm ~= nil and farm == AS_Overdraft.boostFarm then
            local boost = AS_Overdraft.boost
            farm.money = farm.money - boost
            superFunc(farm, ...)
            farm.money = farm.money + boost
            return
        end
        return superFunc(farm, ...)
    end)
end

-- Diagnostic : si le jeu affiche « pas assez d'argent », log.txt dit d'où vient le refus
local NO_MONEY_KEYS = { "shop_messageNotEnoughMoneyToBuy", "shop_messageNotEnoughMoneyToLease",
    "shop_messageNotEnoughMoney", "ui_notEnoughMoney", "warning_notEnoughMoney" }
local function isNoMoneyText(text)
    if type(text) ~= "string" or g_i18n == nil then return false end
    for _, k in ipairs(NO_MONEY_KEYS) do
        if g_i18n.hasText ~= nil and g_i18n:hasText(k) and g_i18n:getText(k) == text then return true end
    end
    local low = string.lower(text)
    return string.find(low, "argent", 1, true) ~= nil or string.find(low, "money", 1, true) ~= nil
end
local function traceNoMoney(where, text)
    if isNoMoneyText(text) and debug ~= nil and debug.traceback ~= nil then
        print(string.format("[AutoSwitch] Découvert DIAG : refus « %s » (%s), depth=%d, boost=%d",
            tostring(text), where, AS_Overdraft.depth, math.floor(AS_Overdraft.boost or 0)))
        print(debug.traceback())
    end
end
if InfoDialog ~= nil and InfoDialog.show ~= nil then
    InfoDialog.show = Utils.prependedFunction(InfoDialog.show, function(text, ...)
        traceNoMoney("InfoDialog.show", text)
    end)
end
if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
    YesNoDialog.show = Utils.prependedFunction(YesNoDialog.show, function(callback, target, text, ...)
        traceNoMoney("YesNoDialog.show", text)
    end)
end
if Gui ~= nil and Gui.showInfoDialog ~= nil then
    Gui.showInfoDialog = Utils.prependedFunction(Gui.showInfoDialog, function(gui, args, ...)
        traceNoMoney("Gui.showInfoDialog", type(args) == "table" and args.text or args)
    end)
end

-- Fonctions du jeu qui contrôlent le solde avant un achat : le découvert y est compté.
-- Les classes absentes ou les fonctions qui n'existent pas sont ignorées.
-- v1.0.0.70 : seulement les fonctions qui décident de l'achat (clic, confirmation,
-- événement) ; plus celles qui affichent le solde (updateButtons, listes du magasin...)
-- sinon le magasin affichait le solde + le découvert.
local SCOPES = {
    -- classe, motif du nom de fonction (en minuscules)
    { "ShopConfigScreen",           { "^onclickbuy", "^onclicklease", "^onyesnobuy", "^onyesnolease", "purchase" } },
    { "ShopMenu",                   { "^buyitem", "^onclickbuy", "^onclicklease" } },
    { "ShopItemsFrame",             { "^onclickbuy", "^onclicklease" } },
    { "ShopController",             { "^buy", "^lease", "finalizebuy" } },
    { "BuyVehicleData",             { "^buy$", "isvalid" } },
    { "BuyVehicleEvent",            { "^run$" } },
    { "BuyHandToolEvent",           { "^run$" } },
    { "BuyObjectEvent",             { "^run$" } },
    { "ConstructionBrushPlaceable", { "verifyplacement", "onbuttonprimary" } },
    { "BuyPlaceableEvent",          { "^run$" } },
    { "BuyExistingPlaceableEvent",  { "^run$" } },
    { "InGameMenuMapFrame",         { "^onclickbuy", "^buyfarmland", "^onyesnobuy" } },
    { "FarmlandStateEvent",         { "^run$" } },
    { "BuyFarmlandEvent",           { "^run$" } },
    -- v1.0.0.71 (provisoire) : entretien de Realistic Mechanical Systems ; ignoré si RMS absent.
    -- RMS est chargé après AutoSwitch, dans son propre environnement : enrobé au chargement de la carte.
    { "RMS_MaintenanceTwoOptionsDialog",   { "^onclickstartservice$" }, "FS25_RealisticMechanicalSystems" },
    { "RMS_MaintenanceThreeOptionsDialog", { "^onclickstartservice$" }, "FS25_RealisticMechanicalSystems" },
    { "RMS_FluidWorkshop",                 { "^trystartservice$" },     "FS25_RealisticMechanicalSystems" },
}

local function matches(name, patterns)
    local low = string.lower(name)
    for _, p in ipairs(patterns) do
        if string.find(low, p) then return true end
    end
    return false
end

local function leave(...)
    AS_Overdraft.depth = math.max(0, AS_Overdraft.depth - 1)
    if AS_Overdraft.depth == 0 then AS_Overdraft:removeBoost() end
    return ...
end

local wrapped = {}   -- fonction d'AutoSwitch -> true (pas de double enrobage)
local origToWrap = {} -- fonction du jeu -> fonction d'AutoSwitch

local function wrapScope(className, class, funcName)
    local orig = class[funcName]
    if wrapped[orig] then return false end
    local label = className .. "." .. funcName
    local f = function(...)
        if AS_Overdraft.PERCENT <= 0 then return orig(...) end
        AS_Overdraft.depth = AS_Overdraft.depth + 1
        if AS_Overdraft.depth == 1 then AS_Overdraft:applyBoost() end
        if not AS_Overdraft.logged[label] then
            AS_Overdraft.logged[label] = true
            print("[AutoSwitch] Découvert compté dans " .. label)
        end
        -- pas de pcall : une erreur garde sa trace d'origine ; depth est remis à 0 à chaque image
        return leave(orig(...))
    end
    wrapped[f] = true
    origToWrap[orig] = f
    class[funcName] = f
    return true
end

function AS_Overdraft:installScopes()
    local count = 0
    for _, s in ipairs(SCOPES) do
        local class
        if s[3] ~= nil then
            class = AS.modGlobal(s[3], s[1])
        else
            class = _G[s[1]]
        end
        if type(class) == "table" then
            local names = {}
            for k, v in pairs(class) do
                if type(k) == "string" and type(v) == "function" and matches(k, s[2]) then
                    names[#names + 1] = k
                end
            end
            for _, k in ipairs(names) do
                if wrapScope(s[1], class, k) then count = count + 1 end
            end
        end
    end
    return count
end

-- v1.0.0.69 : les boutons des écrans (Acheter, Louer...) gardent la fonction du jeu
-- qu'ils ont lue au démarrage : la 1.0.0.68 n'était jamais appelée au clic sur Acheter.
-- Les écrans et leurs éléments sont parcourus une fois, et chaque fonction du jeu
-- enrobée est remplacée par la version d'AutoSwitch.
function AS_Overdraft:rebindCallbacks()
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
    local roots = { g_gui, g_shopConfigScreen, g_shopMenu, g_inGameMenu, g_constructionScreen }
    for _, r in pairs(roots) do
        local ok, err = pcall(walk, r, 0)
        if not ok then print("[AutoSwitch] Découvert : parcours des écrans : " .. tostring(err)) end
    end
    return count
end

-- Dès le chargement du fichier (avant que les écrans du jeu ne lient leurs boutons),
-- puis au chargement de la carte pour les classes créées entre-temps
AS_Overdraft.scopeCount = AS_Overdraft:installScopes()

-- Agios : un prélèvement par jour de jeu passé (plusieurs si on a dormi plusieurs jours)
function AS_Overdraft:chargeInterest(days)
    if self.RATE <= 0 or self.PERCENT <= 0 or days <= 0 then return end
    local env = g_currentMission.environment
    local perPeriod = (env ~= nil and env.daysPerPeriod) or 1
    local daysPerYear = 12 * math.max(1, perPeriod)
    if g_farmManager == nil or g_farmManager.getFarms == nil then return end
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        local money = farm.money
        if farmId ~= nil and type(money) == "number" and money < 0
            and (FarmManager == nil or farmId ~= FarmManager.SPECTATOR_FARM_ID) then
            local agios = math.floor(-money * self.RATE / 100 * days / daysPerYear + 0.5)
            if agios > 0 then
                g_currentMission:addMoney(-agios, farmId, getMoneyType(), true, true)
                print(string.format("[AutoSwitch] Agios ferme %d : -%d (solde %d, %d %% / an, %d jour(s))",
                    farmId, agios, math.floor(money), self.RATE, days))
            end
        end
    end
end

function AS_Overdraft:loadMap()
    getMoneyType()
    self.scopeCount = self.scopeCount + self:installScopes()
    local rebound = self:rebindCallbacks()
    print(string.format("[AutoSwitch] Découvert : %d contrôles d'achat du jeu suivis, %d boutons reliés", self.scopeCount, rebound))
end

function AS_Overdraft:update(dt)
    -- sécurité : une erreur dans un contrôle d'achat a pu laisser le solde augmenté
    if self.depth > 0 or self.boostFarm ~= nil then
        self.depth = 0
        self:removeBoost()
    end
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then return end
    local env = mission.environment
    local day = env ~= nil and env.currentDay or nil
    if type(day) ~= "number" then return end
    if self.lastDay == nil or day < self.lastDay then
        self.lastDay = day
        return
    end
    if day > self.lastDay then
        local days = math.min(day - self.lastDay, 365)
        self.lastDay = day
        local ok, err = pcall(self.chargeInterest, self, days)
        if not ok then print("[AutoSwitch] ERREUR agios : " .. tostring(err)) end
    end
end

function AS_Overdraft:deleteMap()
    self.cache = {}
    self.lastDay = nil
    self.depth = 0
    self.boostFarm, self.boost = nil, 0
end

addModEventListener(AS_Overdraft)
