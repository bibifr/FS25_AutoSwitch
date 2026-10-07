-- AutoSwitch : arbitrage entre les mods (reprend les règles de ModMixer)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo = AS.vtpInfo

-------------------------------------------------------------------------------
-- v1.0.0.07 : AutoSwitch reprend les arbitrages que ModMixer faisait pour Fabien,
--   pour pouvoir retirer ModMixer. Aucun mod n'est désactivé : seul le crochet
--   choisi est écarté sur la fonction concernée, le reste du mod fonctionne.
--   - blocages : le crochet d'un mod sur une fonction n'est pas installé ;
--   - ordre : sur une fonction, les crochets sont empilés dans l'ordre voulu ;
--   - garde-fou remorque : une remorque sans côté de bennage ne fait plus
--     planter la boucle de jeu (correctif repris de ModMixer).
--   AutoSwitch est chargé avant les mods concernés : il voit passer leurs crochets
--   (Utils.overwrittenFunction / appendedFunction / prependedFunction).
--   Si ModMixer est encore installé, AutoSwitch le laisse faire et ne fait rien ici.
-------------------------------------------------------------------------------
AS_Arbiter = {}
AS_Arbiter.active = false

-- Crochets écartés : [fonction] = { [mod] = true }
AS_Arbiter.VETOES = {
    ["WheelsUtil.updateWheelsPhysics"]  = { MoreRealistic = true },
    ["WheelPhysics.updateTireFriction"] = { MoreRealistic = true, FS25_useYourTyres = true },
    ["WheelPhysics.serverUpdate"]       = { MoreRealistic = true, FS25_DynamicDrivePro = true },
    ["Drivable.updateVehiclePhysics"]   = { pdlc_highlandsFishingPack = true },
}

-- Ordre des crochets, du plus intérieur au plus extérieur
AS_Arbiter.ORDERS = {
    ["WheelsUtil.getSmoothedAcceleratorAndBrakePedals"] = { "FS25_RecoveryWinch", "FS25_EnhancedVehicle" },
}

AS_Arbiter.vetoCount = {}   -- ["mod -> fonction"] = nombre de crochets écartés

function AS_Arbiter:isVetoed(mod, target)
    local v = self.VETOES[target]
    return self.active and v ~= nil and v[mod] == true
end

local function getGlobal(name)
    local ok, v = pcall(function() return rawget(_G, name) or _G[name] end)
    if ok then return v end
    return nil
end

-------------------------------------------------------------------------------
-- Quel mod installe ce crochet ? Chaque mod a son propre environnement (_G[nomDuMod]) :
-- getfenv(fonction) le retrouve, même quand le crochet est posé après le chargement.
-- À défaut : g_currentModName (le mod en cours de chargement).
-------------------------------------------------------------------------------
local envToMod = {}
local function rebuildEnvMap()
    if g_modManager == nil or type(g_modManager.mods) ~= "table" then return end
    for _, m in ipairs(g_modManager.mods) do
        local mn = type(m) == "table" and m.modName or nil
        if type(mn) == "string" and mn ~= "" then
            local env = getGlobal(mn)
            if type(env) == "table" then envToMod[env] = mn end
        end
    end
end

local function modOf(fn)
    if type(getfenv) == "function" and type(fn) == "function" then
        local ok, env = pcall(getfenv, fn)
        if ok and type(env) == "table" then
            local name = envToMod[env]
            if name == nil then
                -- les environnements apparaissent au fil du chargement des mods
                rebuildEnvMap()
                name = envToMod[env]
            end
            if name ~= nil then return name end
        end
    end
    if g_currentModName ~= nil and g_currentModName ~= "" then return g_currentModName end
    return nil
end

-------------------------------------------------------------------------------
-- Interception des crochets
-------------------------------------------------------------------------------
local names = setmetatable({}, { __mode = "k" })   -- [fonction] = "Classe.fonction"
local orderState = {}                               -- [cible] = { seen = {}, held = {} }

local function nameTarget(target)
    local class, method = string.match(target, "^([^.]+)%.(.+)$")
    local C = class ~= nil and getGlobal(class) or nil
    if type(C) == "table" and type(C[method]) == "function" then
        names[C[method]] = target
    end
end

local function setTarget(target, fn)
    local class, method = string.match(target, "^([^.]+)%.(.+)$")
    local C = class ~= nil and getGlobal(class) or nil
    if type(C) == "table" then C[method] = fn end
end

local function indexIn(list, mod)
    for i, m in ipairs(list) do if m == mod then return i end end
    return nil
end

-- Un crochet ordonné attend que les crochets qui doivent être en dessous soient posés
local function canInstall(target, mod)
    local order, st = AS_Arbiter.ORDERS[target], orderState[target]
    local idx = indexIn(order, mod)
    for i = 1, idx - 1 do
        if not st.seen[order[i]] and not st.released then return false end
    end
    return true
end

local function installHeld(target, chain)
    local st = orderState[target]
    local again = true
    while again do
        again = false
        for i, h in ipairs(st.held) do
            if st.released or canInstall(target, h.mod) then
                table.remove(st.held, i)
                local ok, res = pcall(h.orig, chain, h.fn)
                if ok and type(res) == "function" then
                    chain = res
                    names[chain] = target
                end
                st.seen[h.mod] = true
                vtpInfo(string.format("[AS_Arbiter] ordre : %s posé sur %s", h.mod, target))
                again = true
                break
            end
        end
    end
    return chain
end

local function intercept(orig, existingFn, newFn)
    local target = names[existingFn]
    if target == nil then return orig(existingFn, newFn) end

    local mod = modOf(newFn)
    if mod ~= nil and AS_Arbiter:isVetoed(mod, target) then
        local key = mod .. " -> " .. target
        if AS_Arbiter.vetoCount[key] == nil then
            vtpInfo(string.format("[AS_Arbiter] bloqué : %s", key))
        end
        AS_Arbiter.vetoCount[key] = (AS_Arbiter.vetoCount[key] or 0) + 1
        return existingFn
    end

    local order = AS_Arbiter.ORDERS[target]
    if order ~= nil and mod ~= nil and indexIn(order, mod) ~= nil then
        local st = orderState[target]
        if not canInstall(target, mod) then
            table.insert(st.held, { mod = mod, fn = newFn, orig = orig })
            return existingFn
        end
        local result = orig(existingFn, newFn)
        if type(result) == "function" then names[result] = target end
        st.seen[mod] = true
        return installHeld(target, result)
    end

    local result = orig(existingFn, newFn)
    if type(result) == "function" then names[result] = target end
    return result
end

-------------------------------------------------------------------------------
-- Garde-fou remorque (repris de ModMixer) : une remorque dont la configuration n'a
-- aucun côté de bennage (plateau, porte-engin...) faisait une erreur à chaque image
-- sur les versions du jeu sans ce contrôle : le jeu se figeait.
-------------------------------------------------------------------------------
local function installTrailerGuard()
    if type(SpecializationUtil) ~= "table" or type(SpecializationUtil.registerEventListener) ~= "function" then return end
    local origReg = SpecializationUtil.registerEventListener
    local done = false
    SpecializationUtil.registerEventListener = function(vehicleType, eventName, specTable)
        if not done and eventName == "onUpdate" and type(specTable) == "table"
            and type(specTable.onUpdate) == "function"
            and type(specTable.loadTipSide) == "function"
            and type(specTable.startTipping) == "function" then
            done = true
            local orig = specTable.onUpdate
            local warned = {}
            specTable.onUpdate = function(self, ...)
                local spec = self.spec_trailer
                if spec ~= nil and (spec.tipSideCount == nil or spec.tipSideCount == 0) then
                    local ok = pcall(orig, self, ...)
                    if not ok then
                        local key = self.configFileName or "?"
                        if not warned[key] then
                            warned[key] = true
                            vtpInfo("[AS_Arbiter] remorque sans côté de bennage, erreur évitée : " .. tostring(key))
                        end
                    end
                    return
                end
                return orig(self, ...)
            end
        end
        return origReg(vehicleType, eventName, specTable)
    end
end

-------------------------------------------------------------------------------
-- Mise en place (au chargement d'AutoSwitch, avant les mods concernés)
-------------------------------------------------------------------------------
local function modMixerPresent()
    return type(Utils) == "table" and (rawget(Utils, "__ms_registry") ~= nil or rawget(Utils, "__ms_fnNames") ~= nil)
end

function AS_Arbiter:install()
    if modMixerPresent() then
        print("[AS_Arbiter] ModMixer est installé : il garde l'arbitrage, AutoSwitch n'intervient pas")
        return
    end
    if type(Utils) ~= "table" or type(Utils.overwrittenFunction) ~= "function" then return end

    for target in pairs(self.VETOES) do nameTarget(target) end
    for target in pairs(self.ORDERS) do
        nameTarget(target)
        orderState[target] = { seen = {}, held = {} }
    end

    local origOver = Utils.overwrittenFunction
    local origApp = Utils.appendedFunction
    local origPre = Utils.prependedFunction
    Utils.overwrittenFunction = function(existingFn, newFn) return intercept(origOver, existingFn, newFn) end
    if type(origApp) == "function" then
        Utils.appendedFunction = function(existingFn, newFn) return intercept(origApp, existingFn, newFn) end
    end
    if type(origPre) == "function" then
        Utils.prependedFunction = function(existingFn, newFn) return intercept(origPre, existingFn, newFn) end
    end
    installTrailerGuard()
    self.active = true
    print("[AS_Arbiter] arbitrage des mods actif (blocages, ordre des crochets, garde-fou remorque)")
end

-- Un crochet ordonné encore en attente (l'autre mod n'est pas installé) est posé
-- par-dessus au premier passage dans la boucle de jeu : il n'est jamais perdu.
function AS_Arbiter:update(dt)
    if self.flushed then return end
    self.flushed = true
    for target, st in pairs(orderState) do
        if #st.held > 0 then
            st.released = true
            local class, method = string.match(target, "^([^.]+)%.(.+)$")
            local C = getGlobal(class)
            if type(C) == "table" and type(C[method]) == "function" then
                setTarget(target, installHeld(target, C[method]))
            end
        end
    end
end

AS_Arbiter:install()
addModEventListener(AS_Arbiter)
