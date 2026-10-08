-- AutoSwitch : semis direct sur zones effacées
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.20 : semis direct sur les zones où la culture a été effacée.
--   Quand Mud System Physics efface la culture sous une roue, le sol reste en type
--   "semé" (ou "semis direct") : le jeu croit la zone déjà semée et le semoir passe
--   sans rien faire (alors qu'un cultivateur, lui, permet de resemer).
--   Ici, juste avant qu'un semoir de SEMIS DIRECT travaille, on remet en "déchaumé"
--   les pixels de sa zone de travail qui sont en type semé MAIS sans aucune plante.
--   Les cultures existantes (même jeunes) ne sont jamais touchées.
-------------------------------------------------------------------------------
AS_DirectResow = {}
AS_DirectResow.ENABLED = true

local function drGroundValue(name, fallback)
    local fgs = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    local t = FieldGroundType ~= nil and FieldGroundType[name] or nil
    if fgs ~= nil and fgs.getFieldGroundValue ~= nil and t ~= nil then
        local ok, v = pcall(fgs.getFieldGroundValue, fgs, t)
        if ok and type(v) == "number" then return v end
    end
    return fallback
end

function AS_DirectResow:getTools()
    if self.tools ~= nil then return self.tools end
    local mission = g_currentMission
    if mission == nil or mission.fieldGroundSystem == nil or FieldDensityMap == nil
        or DensityMapModifier == nil or DensityMapFilter == nil or g_fruitTypeManager == nil then
        return nil
    end
    local mapId, first, num = mission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
    if mapId == nil then return nil end

    -- carte des cultures (FS25 : une seule carte partagée par toutes les cultures)
    local fruitDesc = nil
    for _, desc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if desc.terrainDataPlaneId ~= nil then fruitDesc = desc; break end
    end
    if fruitDesc == nil then return nil end

    local tools = {}
    tools.modifier = DensityMapModifier.new(mapId, first, num, g_terrainNode)
    tools.groundFilter = DensityMapFilter.new(mapId, first, num)
    tools.noFruitFilter = DensityMapFilter.new(fruitDesc.terrainDataPlaneId, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
    tools.noFruitFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)
    if tools.noFruitFilter.setTypeIndexCompareMode ~= nil and DensityTypeCompareType ~= nil then
        tools.noFruitFilter:setTypeIndexCompareMode(DensityTypeCompareType.ALWAYS)
    end
    -- (v1.23) "cultivé" : c'est l'état qui a permis de resemer lors de ton test au cultivateur
    tools.newValue = drGroundValue("CULTIVATED", 2)
    tools.sownValues = {
        drGroundValue("SOWN", 7),
        drGroundValue("DIRECT_SOWN", 8),
        drGroundValue("ROLLER_LINES", 11),
        drGroundValue("PLANTED", 9),      -- (v1.22) planteuses / semoirs monograines (ex. Valtra Momentum)
        drGroundValue("RIDGE_SOWN", 10),
    }
    self.tools = tools
    return tools
end

function AS_DirectResow:resetArea(sx, sz, wx, wz, hx, hz)
    local tools = self:getTools()
    if tools == nil then return 0 end
    tools.modifier:setParallelogramWorldCoords(sx, sz, wx, wz, hx, hz, DensityCoordType.POINT_POINT_POINT)
    local changed = 0
    local diag = {}
    for _, v in ipairs(tools.sownValues) do
        tools.groundFilter:setValueCompareParams(DensityValueCompareType.EQUAL, v)
        local r1, r2, r3 = tools.modifier:executeSet(tools.newValue, tools.groundFilter, tools.noFruitFilter)
        changed = changed + math.max(tonumber(r1) or 0, tonumber(r2) or 0)
        table.insert(diag, string.format("%s:%s/%s/%s", tostring(v), tostring(r1), tostring(r2), tostring(r3)))
    end
    -- diagnostic : quelques lignes seulement
    self.diagCount = (self.diagCount or 0) + 1
    if self.diagCount <= 5 or (self.diagCount % 200) == 0 then
        vtpInfo(string.format("[AS_DirectResow] diag #%d nouveau=%s zone (%.1f,%.1f) %s", self.diagCount,
            tostring(tools.newValue), sx, sz, table.concat(diag, " ")))
    end
    return changed
end

-- (v1.24) Le jeu n'appelle pas la fonction de semis du véhicule de façon interceptable.
-- On enveloppe donc FSDensityMapUtil.updateDirectSowingArea, la fonction du jeu qui pose
-- réellement les graines en SEMIS DIRECT (appelée uniquement par les semoirs de semis direct).
if FSDensityMapUtil ~= nil and FSDensityMapUtil.updateDirectSowingArea ~= nil then
    FSDensityMapUtil.updateDirectSowingArea = Utils.overwrittenFunction(FSDensityMapUtil.updateDirectSowingArea,
        function(fruitIndex, superFunc, sx, sz, wx, wz, hx, hz, ...)
            if AS_DirectResow.ENABLED and sx ~= nil and hz ~= nil then
                if not AS_DirectResow.calledLogged then
                    AS_DirectResow.calledLogged = true
                    vtpInfo("[AS_DirectResow] semis direct détecté : correction active")
                end
                local ok, changed = pcall(AS_DirectResow.resetArea, AS_DirectResow, sx, sz, wx, wz, hx, hz)
                if not ok then
                    if not AS_DirectResow.loggedError then
                        AS_DirectResow.loggedError = true
                        print("[AS_DirectResow] erreur : " .. tostring(changed))
                    end
                elseif (changed or 0) > 0 and not AS_DirectResow.changedLogged then
                    AS_DirectResow.changedLogged = true
                    vtpInfo(string.format("[AS_DirectResow] zone effacée remise en cultivé pour resemis (%d px)", changed))
                end
            end
            return superFunc(fruitIndex, sx, sz, wx, wz, hx, hz, ...)
        end)
    vtpInfo("[AS_DirectResow] branché sur FSDensityMapUtil.updateDirectSowingArea")
else
    print("[AS_DirectResow] FSDensityMapUtil.updateDirectSowingArea introuvable : resemis direct inactif")
end

function AS_DirectResow:deleteMap()
    self.tools = nil
end

addModEventListener(AS_DirectResow)
