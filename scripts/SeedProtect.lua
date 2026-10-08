-- AutoSwitch : protection du semis (Mud System Physics)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.10 : protection du semis contre la destruction de culture de Mud System Physics.
--   Mud System Physics efface la culture sous les roues dans la boue en passant par
--   FieldGroundMudPhysics:getWheelDestructionParallelogram(wheel). On l'enveloppe :
--   pas de zone (donc rien d'effacé) si le véhicule recule ou si la roue appartient
--   à un semoir / une planteuse. Sinon, la fonction d'origine est appelée.
--   Aucun fichier de Mud System Physics n'est modifié.
-------------------------------------------------------------------------------
AS_SeedProtect = {}
AS_SeedProtect.ENABLED = true
AS_SeedProtect.installed = false

local function spGetFgClass()
    return getMudClass("FieldGroundMudPhysics")
end

local function spIsReversing(vehicle)
    local root = vehicle
    if vehicle.getRootVehicle ~= nil then
        root = vehicle:getRootVehicle() or vehicle
    elseif vehicle.rootVehicle ~= nil then
        root = vehicle.rootVehicle
    end
    if root.movingDirection ~= nil and root.movingDirection < 0 then
        return true
    end
    if root.getLastSpeed ~= nil and root.lastSignedSpeed ~= nil then
        return root.lastSignedSpeed < -0.0001
    end
    return false
end

local function spIsSeeder(vehicle)
    return vehicle.spec_sowingMachine ~= nil or vehicle.spec_treePlanter ~= nil
end

function AS_SeedProtect:shouldProtect(wheel)
    if not self.ENABLED or wheel == nil then return false end
    local vehicle = wheel.vehicle
    if vehicle == nil then return false end
    if spIsSeeder(vehicle) then return true end
    return spIsReversing(vehicle)
end

function AS_SeedProtect:install()
    if self.installed then return end
    local ok, fg = pcall(spGetFgClass)
    if not ok then fg = nil end
    if fg == nil or type(fg.getWheelDestructionParallelogram) ~= "function" then
        if not self.quiet then
            print("[AS_SeedProtect] Mud System Physics introuvable : protection du semis inactive")
        end
        return
    end
    local original = fg.getWheelDestructionParallelogram
    fg.getWheelDestructionParallelogram = function(fgSelf, wheel, ...)
        local ok, protect = pcall(AS_SeedProtect.shouldProtect, AS_SeedProtect, wheel)
        if ok and protect then
            return nil
        end
        return original(fgSelf, wheel, ...)
    end
    self.installed = true
    vtpInfo("[AS_SeedProtect] protection du semis installée (marche arrière / roues du semoir)")
end

function AS_SeedProtect:loadMap()
    self:install()
end

function AS_SeedProtect:update(dt)
    -- nouvel essai pendant ~10 s si Mud System Physics n'était pas prêt au chargement
    if not self.installed and (self.retries or 0) < 20 then
        self.retryTimer = (self.retryTimer or 0) + (dt or 0)
        if self.retryTimer >= 500 then
            self.retryTimer = 0
            self.retries = (self.retries or 0) + 1
            self.quiet = self.retries < 20
            self:install()
        end
    end
end

addModEventListener(AS_SeedProtect)
