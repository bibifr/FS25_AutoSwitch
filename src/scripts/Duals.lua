-- AutoSwitch : roues jumelées (largeur réelle pour Mud System Physics + adhérence en sol humide)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v2.2 : Mud System Physics ne lit que la largeur du pneu intérieur (wp.width) pour son
-- bonus "pneu large" (moins d'enfoncement). Avec des jumelées, la largeur réelle est la
-- somme des pneus : MoreRealistic la calcule déjà (wp.mrTotalWidth).
-- On donne à Mud la largeur totale UNIQUEMENT pendant ses propres calculs, puis on remet
-- la largeur d'origine : le jeu de base et les autres mods ne voient aucun changement.
-- Bonus d'adhérence en sol humide : la perte calculée par AS_WetGrip est réduite.
-------------------------------------------------------------------------------
AS_Duals = {}
AS_Duals.ENABLED = true
AS_Duals.MIN_RATIO = 1.5            -- largeur totale >= 1,5 x pneu seul => roue jumelée
AS_Duals.WET_LOSS_REDUCTION = 0.20  -- jumelées : perte d'adhérence en sol humide réduite de 20 %
AS_Duals.installed = false

-- largeur totale si la roue est jumelée, sinon nil
function AS_Duals.getDualWidth(wp)
    if wp == nil then return nil end
    local base = wp.__asBaseWidth or wp.width
    local total = tonumber(wp.mrTotalWidth)
    if type(base) ~= "number" or base <= 0 or total == nil then return nil end
    if total >= base * AS_Duals.MIN_RATIO then return total end
    return nil
end

local function swapIn(wp)
    if wp == nil or wp.__asBaseWidth ~= nil then return end
    local total = AS_Duals.getDualWidth(wp)
    if total == nil then return end
    wp.__asBaseWidth = wp.width
    wp.width = total
end

local function swapOut(wp)
    if wp ~= nil and wp.__asBaseWidth ~= nil then
        wp.width = wp.__asBaseWidth
        wp.__asBaseWidth = nil
    end
end

function AS_Duals:install()
    if self.installed then return end
    self.installed = true
    local fg = getMudClass("FieldGroundMudPhysics")
    if fg == nil or WheelPhysics == nil or WheelPhysics.serverUpdate == nil then
        print("[AS_Duals] ERREUR : Mud System Physics introuvable, bonus jumelées inactif")
        return
    end

    -- 1) calcul par roue : Mud appelle getWheelGroundProfile juste avant de lire la largeur.
    --    On ne remplace la largeur que pendant serverUpdate (après le calcul du jeu de base).
    WheelPhysics.serverUpdate = Utils.overwrittenFunction(WheelPhysics.serverUpdate, function(wp, superFunc, ...)
        wp.__asInServerUpdate = true
        local ok, err = pcall(superFunc, wp, ...)
        wp.__asInServerUpdate = nil
        swapOut(wp)
        if not ok then error(err, 0) end
    end)
    local origProfile = fg.getWheelGroundProfile
    fg.getWheelGroundProfile = function(selfFg, wheel, ...)
        if AS_Duals.ENABLED and wheel ~= nil and wheel.physics ~= nil and wheel.physics.__asInServerUpdate then
            swapIn(wheel.physics)
        end
        return origProfile(selfFg, wheel, ...)
    end

    -- 2) calcul du véhicule entier (enfoncement / vitesse maxi dans la boue)
    local origApply = fg.applyFieldPhysics
    fg.applyFieldPhysics = function(selfFg, vehicle, ...)
        local swapped = nil
        if AS_Duals.ENABLED and vehicle ~= nil and vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil then
            swapped = {}
            for _, w in ipairs(vehicle.spec_wheels.wheels) do
                local wp = w.physics
                if wp ~= nil and wp.__asBaseWidth == nil and AS_Duals.getDualWidth(wp) ~= nil then
                    swapIn(wp)
                    table.insert(swapped, wp)
                end
            end
        end
        local res = {pcall(origApply, selfFg, vehicle, ...)}
        if swapped ~= nil then
            for _, wp in ipairs(swapped) do swapOut(wp) end
        end
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2)
    end
end

function AS_Duals:update(dt)
    if g_currentMission == nil or g_server == nil then return end
    if not self.installed then self:install() end
end

addModEventListener(AS_Duals)
