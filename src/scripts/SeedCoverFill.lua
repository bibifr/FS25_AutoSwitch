-- AutoSwitch : remplissage du semoir couvercle fermé
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.16 : remplissage du semoir que le couvercle soit ouvert ou fermé.
--   Dans le jeu, Cover:getFillUnitSupportsToolType refuse le remplissage quand le
--   couvercle est fermé ET que l'outil de remplissage figure dans cover.blockedToolTypes.
--   Pour les semoirs / planteuses, on vide cette liste (sauvegardée pour pouvoir la
--   remettre si l'option est désactivée). Aucun fichier du jeu n'est modifié.
-------------------------------------------------------------------------------
AS_SeedCoverFill = {}
AS_SeedCoverFill.ENABLED = true
AS_SeedCoverFill.CHECK_MS = 2000
AS_SeedCoverFill.timer = 0
AS_SeedCoverFill.patched = {}   -- [vehicle] = { [cover] = blockedToolTypes d'origine }

local function scIsSeeder(vehicle)
    return vehicle.spec_sowingMachine ~= nil or vehicle.spec_treePlanter ~= nil
end

function AS_SeedCoverFill:patchVehicle(vehicle)
    local spec = vehicle.spec_cover
    if spec == nil or spec.hasCovers ~= true or spec.covers == nil then return end
    local saved = self.patched[vehicle]
    if saved == nil then
        saved = {}
        self.patched[vehicle] = saved
    end
    local n = 0
    for _, cover in ipairs(spec.covers) do
        if saved[cover] == nil and type(cover.blockedToolTypes) == "table" and next(cover.blockedToolTypes) ~= nil then
            saved[cover] = cover.blockedToolTypes
            cover.blockedToolTypes = {}
            n = n + 1
        end
    end
    if n > 0 then
        vtpInfo(string.format("[AS_SeedCoverFill] %s : remplissage autorisé couvercle fermé", vehicle:getName()))
    end
end

function AS_SeedCoverFill:restoreAll()
    for vehicle, saved in pairs(self.patched) do
        for cover, original in pairs(saved) do
            cover.blockedToolTypes = original
        end
    end
    self.patched = {}
end

function AS_SeedCoverFill:setEnabled(enabled)
    self.ENABLED = enabled == true
    if not self.ENABLED then
        self:restoreAll()
    else
        self.timer = self.CHECK_MS   -- applique tout de suite
    end
end

function AS_SeedCoverFill:update(dt)
    if not self.ENABLED or g_currentMission == nil then return end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.CHECK_MS then return end
    self.timer = 0
    for _, vehicle in pairs(getVehicles()) do
        if scIsSeeder(vehicle) and vehicle.spec_cover ~= nil then
            local ok, err = pcall(self.patchVehicle, self, vehicle)
            if not ok and not self.loggedError then
                self.loggedError = true
                print("[AS_SeedCoverFill] erreur : " .. tostring(err))
            end
        end
    end
    -- oublie les véhicules supprimés
    for vehicle in pairs(self.patched) do
        if vehicle.isDeleted == true then self.patched[vehicle] = nil end
    end
end

function AS_SeedCoverFill:deleteMap()
    self.patched = {}
    self.timer = 0
end

addModEventListener(AS_SeedCoverFill)
