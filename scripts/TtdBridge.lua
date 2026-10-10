-- AutoSwitch : pont Mud System Physics -> Tractor Terrain Dynamics
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.27 : Mud System Physics 1.3.6 a retiré sa compatibilité avec TTD
--   (TractorTerrainDynamicsCompatibility.lua). En 1.3.4, quand TTD gérait un
--   véhicule au champ :
--     - TTD recevait l'humidité locale de MSP (sol gelé = 0) au lieu de la sienne ;
--     - MSP retirait son frein de boue, sa perte d'adhérence et sa charge moteur,
--       pour ne pas appliquer la résistance deux fois.
--   Ce module refait les deux, par-dessus MSP 1.3.6 et TTD 3.7 :
--     - TTD_MoistureSystem.getVehicleMoisture renvoie l'humidité de MSP ;
--     - pendant les appels de MSP (updatePhysics, updateTireFriction,
--       applyMotorLoad), ses effets sont neutralisés pour un véhicule que TTD
--       gère au champ, puis remis aussitôt.
--   Rien n'est modifié dans les fichiers de MSP ni de TTD.
-- v1.0.0.28 :
--   - chemins (terre, herbe, sable, gravier) : TTD 3.7 y remplace l'adhérence par
--     une valeur fixe, que le préréglage « Dur » multiplie encore par 0,55 à 0,7 en
--     sol mouillé (terre mouillée : 0,60 x 0,6 = 0,36, presque du verglas). On
--     retire ce multiplicateur « Dur » sur sol mouillé (en mémoire seulement) :
--     la valeur de base de TTD reste (terre 0,60, herbe 0,70, gravier 0,75, sable 0,50).
--   - calibrateur de TTD bloqué : Ctrl+C et le clic molette prenaient les
--     commandes du véhicule (contexte de saisie du calibrateur).
-------------------------------------------------------------------------------

AS_TtdBridge = {}
AS_TtdBridge.installed = false
AS_TtdBridge.wetnessHooked = false
AS_TtdBridge.dynamicsHooked = false

local function msp(name)
    return AS.modGlobal("FS25_MudSystemPhysics", name)
end

local function ttd(name)
    return AS.modGlobal("FS25_TractorTerrainDynamics", name)
end

local function clamp01(v)
    v = tonumber(v) or 0
    if v ~= v then return 0 end
    return math.max(0, math.min(1, v))
end

-- Véhicule dont TTD gère la dynamique au champ (même test que MSP 1.3.4)
function AS_TtdBridge.isHandledByTTD(vehicle)
    if vehicle == nil or vehicle.isDeleting == true or vehicle.isDeleted == true then return false end
    local spec = vehicle.spec_tractorTerrainDynamics
    if spec == nil or spec.isActive ~= true or spec.currentTTDState ~= "field" then return false end
    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    return wheels ~= nil and next(wheels) ~= nil
end

-- Humidité du sol sous le véhicule vue par MSP (même calcul que MSP 1.3.4 pour TTD)
function AS_TtdBridge.getMspWetness(vehicle)
    local wetness = 0
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local weather = env ~= nil and env.weather or nil
    if weather ~= nil and weather.getGroundWetness ~= nil then
        local ok, value = pcall(weather.getGroundWetness, weather)
        if ok then wetness = clamp01(value) end
    end
    local mp = msp("MudPhysics")
    if mp ~= nil and mp.isHardWinterFrozen ~= nil then
        local ok, frozen = pcall(mp.isHardWinterFrozen, mp)
        if ok and frozen then return 0 end
    end
    local flw = msp("FieldLocalWetness")
    if flw ~= nil and flw.enabled == true and flw.getVehicleWetness ~= nil and vehicle ~= nil then
        local ok, value = pcall(flw.getVehicleWetness, flw, vehicle, wetness, 0)
        if ok and value ~= nil then wetness = value end
    end
    return clamp01(wetness)
end

function AS_TtdBridge:hookWetness()
    local ms = ttd("TTD_MoistureSystem") or ttd("g_TTD_MoistureSystem")
    if ms == nil or type(ms.getVehicleMoisture) ~= "function" then
        print("[AS_TtdBridge] TTD_MoistureSystem introuvable : humidité de MSP non transmise à TTD")
        return
    end
    if msp("FieldLocalWetness") == nil then
        print("[AS_TtdBridge] Mud System Physics introuvable : humidité de MSP non transmise à TTD")
        return
    end
    local shared = ttd("g_TTD_Shared")
    local orig = ms.getVehicleMoisture
    ms.getVehicleMoisture = function(vehicle, environment, currentTime)
        local ttdValue = orig(vehicle, environment, currentTime)
        if vehicle == nil then return ttdValue end
        local ok, wet = pcall(AS_TtdBridge.getMspWetness, vehicle)
        if not ok or wet == nil then return ttdValue end
        local maxWet = 1
        if shared ~= nil and shared.getVehicleConfig ~= nil then
            local okMax, m = pcall(shared.getVehicleConfig, vehicle, "MOISTURE_MAX")
            if okMax and type(m) == "number" then maxWet = m end
        end
        return math.min(wet, maxWet)
    end
    self.wetnessHooked = true
    print("[AS_TtdBridge] humidité locale de Mud System Physics transmise à TTD")
end

-- WheelPhysics.updatePhysics : pas de frein de boue MSP sur un véhicule géré par TTD
local function updatePhysics(self, superFunc, brakeForce, torque)
    if self ~= nil and AS_TtdBridge.isHandledByTTD(self.vehicle) then
        local mpExtra, fgExtra = self.__mpMudBrakeExtra, self.__fgMudBrakeExtra
        self.__mpMudBrakeExtra, self.__fgMudBrakeExtra = 0, 0
        local ok, err = pcall(superFunc, self, brakeForce, torque)
        self.__mpMudBrakeExtra, self.__fgMudBrakeExtra = mpExtra, fgExtra
        if not ok then error(err) end
        return
    end
    return superFunc(self, brakeForce, torque)
end

-- WheelPhysics.updateTireFriction : pas de perte d'adhérence MSP sur un véhicule géré par TTD
local function updateTireFriction(self, superFunc, dt)
    if self ~= nil and AS_TtdBridge.isHandledByTTD(self.vehicle) then
        local mp = msp("MudPhysics")
        local gripMul = self.__fgGripMul
        local mpEnabled = mp ~= nil and mp.enabled or nil
        self.__fgGripMul = nil
        if mp ~= nil then mp.enabled = false end
        local ok, err = pcall(superFunc, self, dt)
        self.__fgGripMul = gripMul
        if mp ~= nil then mp.enabled = mpEnabled end
        if not ok then error(err) end
        return
    end
    return superFunc(self, dt)
end

-- applyMotorLoad de MSP : pas de charge moteur MSP sur un véhicule géré par TTD
local function wrapMotorLoad(class, label)
    if class == nil or type(class.applyMotorLoad) ~= "function" then return false end
    local orig = class.applyMotorLoad
    class.applyMotorLoad = function(self, vehicle, ...)
        if AS_TtdBridge.isHandledByTTD(vehicle) then
            local enabled = self.motorLoadEnable
            self.motorLoadEnable = false
            local ok, err = pcall(orig, self, vehicle, ...)
            self.motorLoadEnable = enabled
            if not ok then error(err) end
            return
        end
        return orig(self, vehicle, ...)
    end
    return true
end

function AS_TtdBridge:hookDynamics()
    local mp, fg = msp("MudPhysics"), msp("FieldGroundMudPhysics")
    if mp == nil and fg == nil then
        print("[AS_TtdBridge] Mud System Physics introuvable : rien à arbitrer avec TTD")
        return
    end
    if WheelPhysics ~= nil and WheelPhysics.updatePhysics ~= nil then
        WheelPhysics.updatePhysics = Utils.overwrittenFunction(WheelPhysics.updatePhysics, updatePhysics)
    end
    if WheelPhysics ~= nil and WheelPhysics.updateTireFriction ~= nil then
        WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, updateTireFriction)
    end
    local a = wrapMotorLoad(mp, "MudPhysics")
    local b = wrapMotorLoad(fg, "FieldGroundMudPhysics")
    self.dynamicsHooked = true
    print(string.format("[AS_TtdBridge] au champ, TTD gère la résistance : frein de boue, adhérence et charge moteur de MSP coupés (charge moteur : boue=%s champ=%s)",
        tostring(a), tostring(b)))
end

-- Adhérence des chemins mouillés : multiplicateur du préréglage « Dur » ramené à 1
AS_TtdBridge.NATURAL_WET_HARD = {
    NATURAL_GRASS_WET = 1.0,
    NATURAL_DIRT_WET = 1.0,
    NATURAL_SAND_WET = 1.0,
    NATURAL_GRAVEL_WET = 1.0,
}

function AS_TtdBridge:patchNaturalGrip()
    local shared = ttd("g_TTD_Shared")
    local presets = shared ~= nil and shared.CONFIG ~= nil and shared.CONFIG.DIFFICULTY_PRESETS or nil
    local hard = presets ~= nil and presets.hard or nil
    if hard == nil then
        print("[AS_TtdBridge] préréglage « Dur » de TTD introuvable : adhérence des chemins inchangée")
        return
    end
    local n = 0
    for key, value in pairs(self.NATURAL_WET_HARD) do
        if hard[key] ~= nil then
            hard[key] = value
            n = n + 1
        end
    end
    print(string.format("[AS_TtdBridge] chemins mouillés : pénalité du préréglage « Dur » de TTD retirée (%d valeurs)", n))
end

-- Calibrateur de TTD : Ctrl+C et clic molette ne font plus rien
function AS_TtdBridge:blockCalibrator()
    local cal = ttd("TTD_Calibration") or ttd("g_TTD_Calibration")
    if cal == nil or type(cal.toggle) ~= "function" then return end
    if cal.visible == true and type(cal.forceClose) == "function" then
        pcall(cal.forceClose, cal)
    end
    cal.toggle = function(self)
        if self.visible == true and type(self.forceClose) == "function" then self:forceClose() end
    end
    cal.toggleInteractive = function(self)
        if self.visible == true and type(self.forceClose) == "function" then self:forceClose() end
    end
    print("[AS_TtdBridge] calibrateur de TTD bloqué (Ctrl+C et clic molette sans effet)")
end

function AS_TtdBridge:update(dt)
    -- au premier update, après MSP, TTD et AS_MudWheelDrag : nos fonctions passent par-dessus
    if self.installed then return end
    self.installed = true
    if ttd("g_TTD_Shared") == nil then
        print("[AS_TtdBridge] Tractor Terrain Dynamics introuvable : pont inactif")
        return
    end
    self:hookWetness()
    self:hookDynamics()
    self:patchNaturalGrip()
    self:blockCalibrator()
end

addModEventListener(AS_TtdBridge)
