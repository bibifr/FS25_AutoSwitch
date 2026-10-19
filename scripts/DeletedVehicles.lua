-- AutoSwitch : véhicules supprimés oubliés par les autres mods
-- Fichier chargé par AutoSwitch.lua (après TireWear.lua).
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
-------------------------------------------------------------------------------

AS_DeletedVehicles = {}

local function isGone(vehicle)
    if type(vehicle) ~= "table" then return false end
    if vehicle.isDeleted == true or vehicle.isDeleting == true or vehicle.rootNode == nil then
        return true
    end
    return entityExists ~= nil and not entityExists(vehicle.rootNode)
end

function AS_DeletedVehicles:update(dt)
    local core = AS_TireWear ~= nil and AS_TireWear.core or nil
    if type(core) == "table" and core.currentVehicle ~= nil and isGone(core.currentVehicle) then
        core.currentVehicle = nil
        core.manifest = nil
        print("[AutoSwitch] Reifenverschleiß : véhicule supprimé oublié")
    end
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

addModEventListener(AS_DeletedVehicles)
