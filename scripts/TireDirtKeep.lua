-- AutoSwitch : la saleté des pneus part moins vite en roulant
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getVehicles = AS.getVehicles

-------------------------------------------------------------------------------
-- v1.0.0.14 : Mud System Physics (WheelDirtAddon) fait suivre la saleté des pneus
--   au terrain du moment : dès qu'une roue passe sur un sol moins boueux, le pneu
--   se nettoie en 12 à 26 secondes. Un tracteur sorti de la boue arrivait donc à
--   la ferme avec des pneus presque propres (10 à 30 % dans la sauvegarde, pour
--   une carrosserie à 100 %), et on les retrouvait propres au chargement.
--   Ici, ce nettoyage en roulant est gardé mais CLEAN_SCALE fois moins rapide
--   (v1.0.0.16 : 0.006, soit 35 à 70 minutes de route, environ 1 h, au lieu
--   de 12 à 26 secondes).
--   Nettoyage normal pour :
--     - roue dans l'eau ;
--     - pluie (quand le véhicule accepte d'être lavé par la pluie) ;
--     - lavage (nettoyeur haute pression, station de lavage) : il ne passe pas
--       par ce calcul, il marche toujours.
--   Les paquets de boue (mudAmount) gardent leur comportement : ils tombent.
--   Aucun fichier de Mud System Physics n'est modifié.
-------------------------------------------------------------------------------
AS_TireDirtKeep = {}
AS_TireDirtKeep.ENABLED   = true
AS_TireDirtKeep.CLEAN_SCALE = 0.006 -- part du nettoyage en roulant gardée (1 = Mud System Physics d'origine)
AS_TireDirtKeep.RAIN_MIN  = 0.10   -- pluie à partir de laquelle les pneus peuvent se laver
AS_TireDirtKeep.SCAN_MS   = 2000   -- recherche des nouveaux véhicules
AS_TireDirtKeep.timer     = AS_TireDirtKeep.SCAN_MS

local function isInWater(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return false end
    if physics.hasWaterContact == true then return true end
    if physics.netInfo ~= nil and physics.netInfo.hasWaterContact == true then return true end
    local st = wheel.__mudSystemWheelDirtState
    return st ~= nil and st.inWater == true
end

-- Pneu (et pas paquet de boue) : le jeu lui donne une fonction de chargement de la neige
local function isTireNode(nodeData)
    return nodeData ~= nil and nodeData.wheel ~= nil and nodeData.loadFromSavegameFunc ~= nil
end

local function wrapNode(nodeData)
    if nodeData.__asDirtKeep == true or type(nodeData.updateFunc) ~= "function" then return end
    local orig = nodeData.updateFunc
    nodeData.updateFunc = function(vehicle, nd, dt, allowsWashingByRain, rainScale, timeSinceLastRain, temperature, ...)
        local changeDirt, changeWetness = orig(vehicle, nd, dt, allowsWashingByRain, rainScale, timeSinceLastRain, temperature, ...)
        if AS_TireDirtKeep.ENABLED and type(changeDirt) == "number" and changeDirt < 0 then
            local washedByRain = allowsWashingByRain and (rainScale or 0) > AS_TireDirtKeep.RAIN_MIN
            if not washedByRain and not isInWater(nd.wheel) then
                changeDirt = changeDirt * AS_TireDirtKeep.CLEAN_SCALE
            end
        end
        return changeDirt, changeWetness
    end
    nodeData.__asDirtKeep = true
end

function AS_TireDirtKeep:scan()
    for _, vehicle in pairs(getVehicles()) do
        local spec = vehicle.spec_washable
        if spec ~= nil and spec.washableNodes ~= nil and not vehicle.isDeleted then
            for _, nodeData in ipairs(spec.washableNodes) do
                if isTireNode(nodeData) then
                    wrapNode(nodeData)
                end
            end
        end
    end
end

function AS_TireDirtKeep:update(dt)
    if g_currentMission == nil or g_server == nil then return end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.SCAN_MS then return end
    self.timer = 0
    pcall(self.scan, self)
end

function AS_TireDirtKeep:deleteMap()
    self.timer = self.SCAN_MS
end

addModEventListener(AS_TireDirtKeep)
