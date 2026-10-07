-- AutoSwitch : résistance de boue sur les roues sans frein (Mud System Physics + MoreRealistic)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo = AS.vtpInfo

-------------------------------------------------------------------------------
-- v1.0.0.06 : Mud System Physics freine les roues dans la boue et au champ en
--   ajoutant sa résistance au freinage passé à WheelPhysics.updatePhysics
--   (__mpMudBrakeExtra et __fgMudBrakeExtra). MoreRealistic (comme le jeu de base)
--   n'applique ce freinage que sur les roues qui ont un frein (brakeFactor > 0) :
--   sur les roues sans frein, la plupart des outils et remorques, la boue ne
--   freinait plus rien.
--   Ici, pendant l'appel, une roue sans frein reçoit juste le brakeFactor qu'il
--   faut pour que seule la résistance de boue soit appliquée (jamais le frein du
--   tracteur). Le brakeFactor d'origine est remis aussitôt après. Les roues avec
--   frein ne changent pas. Aucun fichier des autres mods n'est modifié.
-------------------------------------------------------------------------------
AS_MudWheelDrag = {}
AS_MudWheelDrag.installed = false

-- Résistance de boue que Mud System Physics ajoute à cette roue (mêmes conditions que MSP)
local function mudExtra(wp)
    local vehicle = wp.vehicle
    if vehicle == nil then return 0 end
    local ttd = rawget(_G, "TractorTerrainDynamicsCompatibility")
    local ttdHandles = ttd ~= nil and ttd.isHandlingVehicleDynamics ~= nil
        and ttd:isHandlingVehicleDynamics(vehicle)
    local total = 0

    local mp = rawget(_G, "MudPhysics")
    if mp ~= nil and mp.enabled and mp.wheelBrakeEnable and not ttdHandles
        and not (mp.isVehicleResetting ~= nil and mp:isVehicleResetting(vehicle))
        and not (mp.isInShopPreview ~= nil and mp:isInShopPreview(vehicle)) then
        local extra = wp.__mpMudBrakeExtra or 0
        local deep = wp.__mpMudDeepFactor or 0
        if deep > 0 then extra = extra * (1.0 + deep * 0.95) end
        if (wp.__mpMudReliefT or 0) > 0 then extra = extra * (mp.reliefBrakeMult or 0.55) end
        total = total + extra
    end

    local fg = rawget(_G, "FieldGroundMudPhysics")
    if fg ~= nil and fg.enabled and fg.wheelBrakeEnable and not ttdHandles
        and not (fg.isVehicleResetting ~= nil and fg:isVehicleResetting(vehicle))
        and not (fg.isInShopPreview ~= nil and fg:isInShopPreview(vehicle)) then
        total = total + (wp.__fgMudBrakeExtra or 0)
    end
    return total
end

local function updatePhysics(self, superFunc, brakeForce, torque)
    local bf = self.brakeFactor
    if bf ~= nil and bf <= 0 then
        local ok, extra = pcall(mudExtra, self)
        if ok and extra ~= nil and extra > 0 then
            -- MSP passe (brakeForce + extra) plus loin : on ne laisse passer que extra
            self.brakeFactor = extra / ((brakeForce or 0) + extra)
            local okCall, err = pcall(superFunc, self, brakeForce, torque)
            self.brakeFactor = bf
            if not okCall then error(err) end
            return
        end
    end
    return superFunc(self, brakeForce, torque)
end

function AS_MudWheelDrag:update(dt)
    -- après les loadMap : Mud System Physics accroche ses fonctions au chargement de la
    -- carte, AutoSwitch doit être par-dessus pour lire brakeFactor avant lui
    if self.installed then return end
    self.installed = true
    if WheelPhysics == nil or WheelPhysics.updatePhysics == nil then return end
    if rawget(_G, "MudPhysics") == nil and rawget(_G, "FieldGroundMudPhysics") == nil then return end
    WheelPhysics.updatePhysics = Utils.overwrittenFunction(WheelPhysics.updatePhysics, updatePhysics)
    vtpInfo("[AS_MudWheelDrag] résistance de boue appliquée aussi aux roues sans frein")
end

addModEventListener(AS_MudWheelDrag)
