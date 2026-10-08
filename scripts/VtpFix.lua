-- AutoSwitch : correctif Variable Tire Pressure pour les tracteurs à pneus "dynamiques"
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v2.2 : certains tracteurs moddés (Fendt 900 / 1000 Vario...) activent VTP sur certaines
-- configurations de roues (vtp="true"). Mais ces configurations sont démultipliées par le jeu
-- en variantes de marques de pneus (numDynamicConfigurations : Michelin, Trelleborg...).
-- VTP prend le numéro de configuration choisi comme position dans le fichier XML : avec les
-- variantes, ce numéro ne correspond plus à la bonne ligne, et VTP se croit désactivé.
-- Correctif : on retrouve la vraie configuration XML grâce à son identifiant (saveId,
-- ex. "BROAD_PTG_MICHELIN_axioBib2" -> "BROAD_PTG") et on relit son marqueur vtp.
-- Le mod Variable Tire Pressure n'est pas modifié.
-------------------------------------------------------------------------------
AS_VtpFix = {}
AS_VtpFix.DIAG = false  -- (v2.4.1) diagnostic retiré : correctif validé
AS_VtpFix.ALL_CONFIGS = true  -- VTP sur toutes les configs de roues d'un tracteur équipé VTP
AS_VtpFix.FN = "vtpIsEnabledForCurrentWheelConfig"
AS_VtpFix.wrapped = {}

local function normScope(v)
    if v == nil then return nil end
    local s = string.lower(tostring(v))
    if s == "true" or s == "1" or s == "yes" or s == "all" then return "all" end
    if s == "front" or s == "rear" then return s end
    return nil
end

-- renvoie scope, saveId, cléXML
function AS_VtpFix.resolveScope(vehicle)
    local xml = vehicle.xmlFile
    if xml == nil or vehicle.configurations == nil then return nil end
    local idx = vehicle.configurations.wheel or vehicle.configurations.wheels
    if idx == nil or g_storeManager == nil then return nil end
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local list = storeItem ~= nil and storeItem.configurations ~= nil
        and (storeItem.configurations.wheel or storeItem.configurations.wheels) or nil
    local item = list ~= nil and list[idx] or nil
    local saveId = item ~= nil and item.saveId or nil
    if type(saveId) ~= "string" or saveId == "" then return nil end

    local bestKey, bestLen = nil, 0
    xml:iterate("vehicle.wheels.wheelConfigurations.wheelConfiguration", function(_, key)
        local sid = xml:getValue(key .. "#saveId", nil)
        if type(sid) == "string" and sid ~= "" and #sid > bestLen
            and (saveId == sid or string.sub(saveId, 1, #sid + 1) == sid .. "_") then
            bestKey, bestLen = key, #sid
        end
        return true
    end)
    if bestKey == nil then return nil, saveId end

    local scope = normScope(xml:getValue(bestKey .. "#vtp", nil))
    if scope == nil then
        -- héritage baseConfig (comme VTP)
        local baseSaveId = xml:getValue(bestKey .. ".wheels#baseConfig", nil)
        if type(baseSaveId) == "string" and baseSaveId ~= "" then
            xml:iterate("vehicle.wheels.wheelConfigurations.wheelConfiguration", function(_, key)
                if xml:getValue(key .. "#saveId", nil) == baseSaveId then
                    scope = normScope(xml:getValue(key .. "#vtp", nil))
                    return false
                end
                return true
            end)
        end
    end
    -- (v2.3) tracteur équipé VTP (au moins une config marquée) : VTP aussi sur les autres
    -- configurations de roues (jumelées, pneus standard...)
    if scope == nil and AS_VtpFix.ALL_CONFIGS then
        local any = false
        xml:iterate("vehicle.wheels.wheelConfigurations.wheelConfiguration", function(_, key)
            if normScope(xml:getValue(key .. "#vtp", nil)) ~= nil then any = true; return false end
            return true
        end)
        if any then return "all", saveId, bestKey .. " (toutes configs)" end
    end
    return scope, saveId, bestKey
end

local function makeWrapper(orig)
    local w = function(self, ...)
        local res = orig(self, ...)
        if res then return res end
        local spec = self.spec_variableTirePressure
        if spec == nil or spec.hasVTPXml ~= true or spec.onlyForTaggedWheelConfigs ~= true then
            return res
        end
        if spec.__asFixScope == nil then
            local ok, scope, saveId, key = pcall(AS_VtpFix.resolveScope, self)
            spec.__asFixScope = (ok and scope) or false
            if AS_VtpFix.DIAG then
                print(string.format("[AS_VtpFix][diag] %s : VTP refusé pour la config pneus '%s' -> config XML %s vtp=%s => %s",
                    tostring(self.getName ~= nil and self:getName() or self.configFileName), tostring(saveId), tostring(key),
                    tostring(scope), (ok and scope) and "VTP ACTIVÉ" or (ok and "reste désactivé (pas de vtp sur cette config)" or ("ERREUR " .. tostring(scope)))))
            end
        end
        if spec.__asFixScope then
            spec.vtpAxleScope = spec.__asFixScope
            return true
        end
        return res
    end
    AS_VtpFix.wrapped[w] = true
    return w
end

function AS_VtpFix.wrapTypes()
    if g_vehicleTypeManager == nil or g_vehicleTypeManager.types == nil then return 0 end
    local n = 0
    for _, vt in pairs(g_vehicleTypeManager.types) do
        local f = vt.functions ~= nil and vt.functions[AS_VtpFix.FN] or nil
        if type(f) == "function" and not AS_VtpFix.wrapped[f] then
            vt.functions[AS_VtpFix.FN] = makeWrapper(f)
            n = n + 1
        end
    end
    return n
end

if TypeManager ~= nil and TypeManager.finalizeTypes ~= nil then
    TypeManager.finalizeTypes = Utils.appendedFunction(TypeManager.finalizeTypes, function()
        pcall(AS_VtpFix.wrapTypes)
    end)
end

function AS_VtpFix:loadMap()
    local ok, n = pcall(AS_VtpFix.wrapTypes)
    if not ok then print("[AS_VtpFix] ERREUR : " .. tostring(n)) end
end

-- (v3.5) désactivation complète du regonflage automatique de VTP lié à la vitesse
-- (VTP repasse en pression route dès 30 km/h). AutoSwitch gère seul le passage champ / route.
-- VTP lit spec.autoInflateSpeedKmh (30 par défaut) : on le met hors d'atteinte sur tous ses véhicules.
AS_VtpFix.NO_SPEED_INFLATE = true
function AS_VtpFix:update(dt)
    if not self.NO_SPEED_INFLATE or g_currentMission == nil or g_currentMission.vehicleSystem == nil then return end
    self.speedTimer = (self.speedTimer or 0) + (dt or 0)
    if self.speedTimer < 1000 then return end
    self.speedTimer = 0
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        local spec = v.spec_variableTirePressure
        if spec ~= nil and spec.autoInflateSpeedKmh ~= math.huge then
            spec.autoInflateSpeedKmh = math.huge
        end
    end
end

addModEventListener(AS_VtpFix)
