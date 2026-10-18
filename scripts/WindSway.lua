-- AutoSwitch : vent visible sur les arbres, les cultures et l'herbe
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.73 : le jeu envoie au feuillage une seule « force du vent » (paramètre
--   de shader partagé Shader.PARAM_SHARED_WIND_SPEED), posée à chaque image par
--   WindUpdater:setSharedShaderParameterValues. Elle vaut vitesse / MAX_SPEED
--   (environ 150 km/h) : à 57 km/h le feuillage ne reçoit que 0,38 et bouge
--   comme sous une brise (relevé en jeu le 18/10).
--   Ici cette valeur est multipliée par FACTOR (x2,2 par défaut, réglable) et
--   plafonnée à MAX (1 = mouvement maximum du jeu de base). La vitesse du vent
--   elle-même (météo, nuages, pluie, éoliennes) n'est pas touchée.
--   Effet seulement à l'affichage (chaque joueur pour lui-même).
-------------------------------------------------------------------------------
AS_WindSway = {}
AS_WindSway.FACTOR = 2.2     -- 1 = jeu de base
AS_WindSway.MAX = 1.0

-- table des globales du jeu (les mods tournent dans leur propre environnement)
local function gameGlobals()
    local mt = getmetatable(_G)
    if mt ~= nil and type(mt.__index) == "table" then return mt.__index end
    return _G
end

function AS_WindSway:install()
    if self.installed then return end
    local G = gameGlobals()
    local orig = G.setSharedShaderParameter
    local id = G.Shader ~= nil and G.Shader.PARAM_SHARED_WIND_SPEED or nil
    if type(orig) ~= "function" or id == nil then
        print("[AutoSwitch] vent : paramètre du feuillage introuvable, module inactif")
        return
    end
    self.installed = true
    G.setSharedShaderParameter = function(param, value, ...)
        if param == id and type(value) == "number" and AS_WindSway.FACTOR ~= 1 then
            value = math.min(value * AS_WindSway.FACTOR, math.max(value, AS_WindSway.MAX))
        end
        return orig(param, value, ...)
    end
end

function AS_WindSway:setFactor(f)
    self.FACTOR = f or 1
end

function AS_WindSway:loadMap()
    self:install()
end

addModEventListener(AS_WindSway)
