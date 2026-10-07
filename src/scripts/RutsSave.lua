-- AutoSwitch : ornières de DynamicDrivePro gardées avec la sauvegarde
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo = AS.vtpInfo

-------------------------------------------------------------------------------
-- v1.0.0.08 : les ornières (terrain creusé par les roues) viennent de DynamicDrivePro
--   (DDP_terrainDepth.lua) : chaque point creusé est noté, puis relu au chargement
--   depuis savegameX/reaTerrainDepth.xml. Mais DDP écrit ce fichier dans
--   saveToXMLFile de son écouteur, que le jeu n'appelle jamais pour un mod : le
--   fichier n'existe pas et les ornières disparaissent au redémarrage.
--   Ici, AutoSwitch demande à DDP d'écrire son fichier à chaque sauvegarde de la
--   partie. Au chargement, DDP le relit lui-même et recreuse le terrain.
--   Aucun fichier de DynamicDrivePro n'est modifié.
-------------------------------------------------------------------------------
AS_RutsSave = {}

function AS_RutsSave:getDepth()
    local t = rawget(_G, "g_reaTerrainDepth")
    if t == nil then
        local env = rawget(_G, "FS25_DynamicDrivePro")
        if type(env) == "table" then
            t = rawget(env, "g_reaTerrainDepth")
        end
    end
    if type(t) == "table" and type(t.saveToOwnXMLFile) == "function" then return t end
    return nil
end

function AS_RutsSave:save()
    if g_server == nil then return end
    local depth = self:getDepth()
    if depth == nil then return end
    local ok, err = pcall(depth.saveToOwnXMLFile, depth)
    if ok then
        vtpInfo(string.format("[AS_RutsSave] %d points d'ornières sauvegardés", #(depth.tracks or {})))
    else
        print("[AS_RutsSave] sauvegarde des ornières impossible : " .. tostring(err))
    end
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        AS_RutsSave:save()
    end)
end
