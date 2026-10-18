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

-- Solde lu par le jeu : + plafond seulement pendant un contrôle d'achat
if FSBaseMission ~= nil and FSBaseMission.getMoney ~= nil then
    FSBaseMission.getMoney = Utils.overwrittenFunction(FSBaseMission.getMoney, function(mission, superFunc, farmId, ...)
        local money = superFunc(mission, farmId, ...)
        if AS_Overdraft.depth > 0 and type(money) == "number" then
            return money + AS_Overdraft:getLimit(farmId or currentFarmId())
        end
        return money
    end)
end
if Farm ~= nil and Farm.getBalance ~= nil then
    Farm.getBalance = Utils.overwrittenFunction(Farm.getBalance, function(farm, superFunc, ...)
        local money = superFunc(farm, ...)
        if AS_Overdraft.depth > 0 and type(money) == "number" then
            return money + AS_Overdraft:getLimit(farm.farmId)
        end
        return money
    end)
end

-- Fonctions du jeu qui contrôlent le solde avant un achat : le découvert y est compté.
-- Les classes absentes ou les fonctions qui n'existent pas sont ignorées.
local SCOPES = {
    -- classe, motif du nom de fonction (en minuscules)
    { "ShopConfigScreen",           { "buy", "lease", "purchase", "onclickok", "onyesno", "button" } },
    { "ShopMenu",                   { "buy", "lease", "purchase" } },
    { "ShopItemsFrame",             { "buy", "lease", "purchase" } },
    { "ShopController",             { "buy", "lease", "purchase" } },
    { "BuyVehicleData",             { "^buy$", "isvalid", "check" } },
    { "BuyVehicleEvent",            { "^run$" } },
    { "BuyHandToolEvent",           { "^run$" } },
    { "BuyObjectEvent",             { "^run$" } },
    { "ConstructionBrushPlaceable", { "verifyplacement", "onbuttonprimary", "buy" } },
    { "ConstructionScreen",         { "buy" } },
    { "BuyPlaceableEvent",          { "^run$" } },
    { "BuyExistingPlaceableEvent",  { "^run$" } },
    { "InGameMenuMapFrame",         { "buy" } },
    { "FarmlandStateEvent",         { "^run$" } },
    { "BuyFarmlandEvent",           { "^run$" } },
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
    return ...
end

local wrapped = {}   -- fonction d'AutoSwitch -> true (pas de double enrobage)

local function wrapScope(className, class, funcName)
    local orig = class[funcName]
    if wrapped[orig] then return false end
    local label = className .. "." .. funcName
    local f = function(...)
        if AS_Overdraft.PERCENT <= 0 then return orig(...) end
        AS_Overdraft.depth = AS_Overdraft.depth + 1
        if not AS_Overdraft.logged[label] then
            AS_Overdraft.logged[label] = true
            if AS_VERBOSE then print("[AutoSwitch] Découvert compté dans " .. label) end
        end
        -- pas de pcall : une erreur garde sa trace d'origine ; depth est remis à 0 à chaque image
        return leave(orig(...))
    end
    wrapped[f] = true
    class[funcName] = f
    return true
end

function AS_Overdraft:installScopes()
    local count = 0
    for _, s in ipairs(SCOPES) do
        local class = _G[s[1]]
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
    print(string.format("[AutoSwitch] Découvert : %d contrôles d'achat du jeu suivis", self.scopeCount))
end

function AS_Overdraft:update(dt)
    self.depth = 0
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
end

addModEventListener(AS_Overdraft)
