-- AutoSwitch : verrou d'atelier orphelin (Advanced Damage System / Realistic Mechanical Systems)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).
-------------------------------------------------------------------------------
-- v1.0.3.2 : pendant un entretien, ADS comme RMS garent l'engin : il sort de la liste
--   Tab (enterable#isTabbable="false" dans vehicles.xml) jusqu'à la fin des travaux.
--   Si on passe de RMS à ADS pendant un entretien, la fin de l'entretien de RMS n'arrive
--   jamais : l'engin reste hors de la liste Tab pour toujours (MF 7S, Fendt 700 de Fabien).
--   Au chargement de la partie, AutoSwitch rend la liste Tab à un engin quand :
--     - son fichier de véhicule le met dans la liste Tab (valeur d'origine) ;
--     - la sauvegarde l'en a sorti ;
--     - ADS le suit et ne l'a pas en entretien, et RMS ne le suit pas.
--   Un engin réellement à l'atelier d'ADS garde son verrou.
-------------------------------------------------------------------------------

AS_WorkshopLock = {}
AS_WorkshopLock.pending = setmetatable({}, { __mode = "k" })   -- [véhicule] = true : à contrôler

-- valeur d'origine (fichier du véhicule) avant que la sauvegarde ne s'applique
if Enterable ~= nil and Enterable.onPostLoad ~= nil then
    Enterable.onPostLoad = Utils.prependedFunction(Enterable.onPostLoad, function(self, savegame)
        local spec = self.spec_enterable
        if spec ~= nil and savegame ~= nil and not savegame.resetVehicles then
            self.__asTabbableDefault = spec.isTabbable == true
            AS_WorkshopLock.pending[self] = true
        end
    end)
end

local function isAdsLoaded()
    return g_modIsLoaded ~= nil and g_modIsLoaded["FS25_AdvancedDamageSystem"] == true
end

function AS_WorkshopLock:check(vehicle)
    if vehicle.__asTabbableDefault ~= true or vehicle.getIsTabbable == nil or vehicle:getIsTabbable() then return end
    if vehicle.spec_AdvancedDamageSystem == nil or vehicle.spec_RealisticMechanicalSystems ~= nil then return end
    if vehicle.isUnderService == nil then return end
    local ok, busy = pcall(vehicle.isUnderService, vehicle)
    if not ok or busy then return end
    vehicle:setIsTabbable(true)
    -- toujours écrit dans log.txt : la seule trace d'un changement fait dans la partie
    local raw = AS.rawPrint or print
    raw(string.format("[AutoSwitch] %s : verrou d'atelier orphelin retiré (de nouveau dans la liste Tab)",
        vehicle.getName ~= nil and vehicle:getName() or tostring(vehicle.configFileName)))
end

function AS_WorkshopLock:update(dt)
    if next(self.pending) == nil then return end
    if g_currentMission == nil or g_server == nil or not isAdsLoaded() then
        self.pending = setmetatable({}, { __mode = "k" })
        return
    end
    -- contrôle quand l'engin a fini de charger (ADS lit son état après la liste Tab)
    for vehicle in pairs(self.pending) do
        if vehicle.isDeleted then
            self.pending[vehicle] = nil
        elseif vehicle.finishedLoading == true then
            self.pending[vehicle] = nil
            pcall(self.check, self, vehicle)
        end
    end
end

addModEventListener(AS_WorkshopLock)
