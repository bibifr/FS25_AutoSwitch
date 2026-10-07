-- AutoSwitch : outils stables à l'arrêt (Mud System Physics + MoreRealistic)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, isAutoDriveActive = AS.vtpInfo, AS.isAutoDriveActive

-------------------------------------------------------------------------------
-- v1.0.0.04 : Mud System Physics fait varier le rayon des roues (enfoncement dans
--   la boue et au champ, pression, crevaisons, Use Your Tyres, TTD), tout passe par
--   _G.__MudRadiusCombiner.apply. Sur un outil à l'arrêt, chaque changement de rayon
--   relance la physique (MoreRealistic réécrit aussi la physique des roues) : l'outil
--   se soulève, bouge, son petit mouvement relance l'enfoncement... et il sautille.
--   Ici, le rayon des roues d'un outil est figé tant qu'il ne peut pas rouler :
--     - outil dételé : toujours figé (il ne peut pas avancer seul) ;
--     - outil attelé : figé quand l'attelage est à l'arrêt et que personne ne
--       l'entraîne (pas d'accélérateur, pas de régulateur, ni AutoDrive ni ouvrier).
--   Le rayon reprend ses variations dès que l'attelage repart. Les tracteurs ne
--   sont pas concernés. Aucun fichier de Mud System Physics n'est modifié.
-------------------------------------------------------------------------------
AS_ImplementStabilizer = {}
AS_ImplementStabilizer.STOP_KPH     = 1.5    -- en dessous : attelage considéré à l'arrêt
AS_ImplementStabilizer.SETTLE_MS    = 1500   -- temps d'arrêt avant de figer un outil attelé
AS_ImplementStabilizer.wrapped = nil         -- fonction apply d'origine
AS_ImplementStabilizer.wrapper = nil
AS_ImplementStabilizer.cache = {}            -- [vehicle] = { t = g_time, frozen = bool }
AS_ImplementStabilizer.stillSince = {}       -- [rootVehicle] = g_time du début de l'arrêt

-- L'attelage est-il entraîné (conducteur, régulateur, AutoDrive, ouvrier) ?
local function isDriven(root)
    if root == nil then return false end
    if root.getIsAIActive ~= nil and root:getIsAIActive() then return true end
    if isAutoDriveActive ~= nil and isAutoDriveActive(root) then return true end
    local dr = root.spec_drivable
    if dr ~= nil then
        if math.abs(dr.axisForward or 0) > 0.01 then return true end
        if dr.cruiseControl ~= nil and (dr.cruiseControl.state or 0) ~= 0 then return true end
    end
    return false
end

function AS_ImplementStabilizer:isFrozen(vehicle)
    if vehicle == nil or vehicle.spec_motorized ~= nil then return false end
    local now = g_time or 0
    local c = self.cache[vehicle]
    if c ~= nil and c.t == now then return c.frozen end

    local frozen = false
    local attacher = vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() or nil
    if attacher == nil then
        -- outil dételé : ne peut pas avancer seul
        frozen = true
    else
        local root = vehicle.rootVehicle or attacher
        local speed = root.getLastSpeed ~= nil and root:getLastSpeed() or 0
        if speed < self.STOP_KPH and not isDriven(root) then
            local since = self.stillSince[root]
            if since == nil then
                self.stillSince[root] = now
            elseif now - since >= self.SETTLE_MS then
                frozen = true
            end
        else
            self.stillSince[root] = nil
        end
    end
    self.cache[vehicle] = { t = now, frozen = frozen }
    return frozen
end

function AS_ImplementStabilizer:wrap()
    local comb = rawget(_G, "__MudRadiusCombiner")
    if comb == nil or type(comb.apply) ~= "function" or comb.apply == self.wrapper then return end
    local orig = comb.apply
    self.wrapped = orig
    local mod = self
    self.wrapper = function(wp, eps, ...)
        if wp ~= nil and wp.vehicle ~= nil then
            local ok, frozen = pcall(mod.isFrozen, mod, wp.vehicle)
            if ok and frozen then return end
        end
        return orig(wp, eps, ...)
    end
    comb.apply = self.wrapper
    vtpInfo("[AS_ImplementStabilizer] rayon des roues figé pour les outils à l'arrêt")
end

function AS_ImplementStabilizer:update(dt)
    -- Mud System Physics peut être chargé après AutoSwitch : on vérifie à chaque image
    self:wrap()
    -- nettoyage léger des caches
    if (g_time or 0) % 10000 < (dt or 0) then
        self.cache = {}
        for root in pairs(self.stillSince) do
            if root.isDeleted or root.isDeleting then self.stillSince[root] = nil end
        end
    end
end

function AS_ImplementStabilizer:deleteMap()
    self.cache, self.stillSince = {}, {}
end

addModEventListener(AS_ImplementStabilizer)
