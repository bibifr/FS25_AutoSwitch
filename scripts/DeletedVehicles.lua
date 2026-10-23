-- AutoSwitch : véhicules supprimés oubliés par les autres mods
-- Fichier chargé par AutoSwitch.lua.
-------------------------------------------------------------------------------
-- v1.0.0.88 : quand un véhicule est supprimé (changement de roues par la palette,
--   vente, réinitialisation), deux références restaient vers lui :
--   - Reifenverschleiß garde le dernier véhicule conduit (currentVehicle) et
--     recalcule l'usure de ses roues disparues à chaque image (« Unknown entity id »
--     dans getWorldTranslation / getWheelShapeContactPointVector) ;
--   - la carte garde l'icône d'ouvrier (AIHotspot) du véhicule et plante à
--     chaque image dans IngameMap.drawHotspot (« entityExists ... Nil »).
--   AutoSwitch efface la référence de Reifenverschleiß et retire l'icône de la
--   carte. Rien n'est modifié dans les fichiers des autres mods ni du jeu.
-- v1.0.2.0 : Reifenverschleiß est bloqué (TireWear.lua), seule l'icône de la carte reste.
-------------------------------------------------------------------------------

AS_DeletedVehicles = {}

local function isGone(vehicle)
    if type(vehicle) ~= "table" then return false end
    if vehicle.isDeleted == true or vehicle.isDeleting == true or vehicle.rootNode == nil then
        return true
    end
    return entityExists ~= nil and not entityExists(vehicle.rootNode)
end

if IngameMap ~= nil and IngameMap.drawHotspot ~= nil then
    IngameMap.drawHotspot = Utils.overwrittenFunction(IngameMap.drawHotspot, function(self, superFunc, hotspot, ...)
        if type(hotspot) == "table" and hotspot.vehicle ~= nil and isGone(hotspot.vehicle) then
            if g_currentMission ~= nil and g_currentMission.removeMapHotspot ~= nil then
                pcall(g_currentMission.removeMapHotspot, g_currentMission, hotspot)
            end
            hotspot.vehicle = nil
            if not AS_DeletedVehicles.loggedHotspot then
                AS_DeletedVehicles.loggedHotspot = true
                print("[AutoSwitch] carte : icône d'un véhicule supprimé retirée")
            end
            return
        end
        return superFunc(self, hotspot, ...)
    end)
end
