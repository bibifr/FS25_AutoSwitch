-- AutoSwitch : paramètres conseillés Mud System Physics / Tractor Terrain Dynamics
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.12 : paramètres conseillés par AutoSwitch pour Mud System Physics (profils de sol,
--   frein de roue...) et Tractor Terrain Dynamics en difficulté "Difficile".
--   Ils sont appliqués automatiquement à chaque chargement de partie et ne sont pas
--   réglables dans le menu : ce sont les réglages du mod.
--   Les valeurs passent par l'API de Mud System Physics : aucun de ses fichiers n'est modifié.
-------------------------------------------------------------------------------
AS_MudPreset = {}
AS_MudPreset.ASK_DELAY_MS = 6000
AS_MudPreset.timer = 0
AS_MudPreset.done = false

-- Version des paramètres conseillés (historique) :
-- v2 (v1.17) : difficulté +20 % (enfoncement, frein de roue, charge moteur, profondeur d'ornière, perte d'adhérence)
-- v3 (v1.18) : + Tractor Terrain Dynamics en difficulté "Difficile" (c'est TTD qui gère le patinage des tracteurs)
AS_MudPreset.RECOMMENDED_VERSION = 4
AS_MudPreset.TTD_RECOMMENDED = "hard"

-- v4 (1.0.0.0) : tous les réglages de Mud System Physics (profils de sol compris), dans l'ordre :
-- le préréglage de difficulté d'abord, car il réécrit une partie des valeurs.
-- 1.0.0.11 : valeurs reprises de la partie de Fabien avant la 1.0.0.01 (sauvegarde du
--   07/10 17:10) : avec l'humidité locale des champs coupée (flw_enabled), les pneus
--   ne se salissaient plus.
AS_MudPreset.RECOMMENDED = {
    { "mudsys_difficultyPreset", 2 },
    { "fg_eraseFruitEnable", true },
    { "fg_eraseFoliageOnlyFields", false },
    { "tp_enabled", false },
    { "tp_lowPressureMudGrip", 1.45 },
    { "tp_highPressureMudGrip", 0.88 },
    { "tp_lowPressureSinkMul", 0.55 },
    { "tp_highPressureSinkMul", 1.14 },
    { "tp_lowPressureMudBrakeMul", 0.58 },
    { "tp_highPressureMudBrakeMul", 1.18 },
    { "tp_lowPressureRadiusSinkMul", 0.38 },
    { "tp_highPressureRadiusSinkMul", 1.18 },
    { "tp_lowPressureSinkOutMul", 1.28 },
    { "tp_highPressureSinkOutMul", 0.92 },
    { "tp_lowPressureMudSpeedLimitMul", 1.16 },
    { "tp_highPressureMudSpeedLimitMul", 0.94 },
    { "tp_lowPressureMotorLoadMul", 0.72 },
    { "tp_highPressureMotorLoadMul", 1.12 },
    { "puncture_enabled", true },
    { "puncture_roadGarbageEnabled", true },
    { "puncture_roadGarbagePointCount", 20 },
    { "puncture_chancePerKm", 0.02 },
    { "puncture_chanceDistanceKm", 1 },
    { "puncture_requireJack", true },
    { "puncture_showCarriedWheel", true },
    { "puncture_highlightWheel", true },
    { "puncture_aiPunctures", true },
    { "puncture_aiAutoRepair", true },
    { "flw_enabled", true },
    { "sdt_enabled", true },
    { "sdt_dryDurationMul", 4 },
    { "sdt_wetDurationMul", 4 },
    { "sdt_enableDynamic", true },
    { "sdt_coldTemp", 2 },
    { "sdt_warmTemp", 18 },
    { "sdt_coldDryExtraMul", 2.5 },
    { "sdt_cloudyFrom", 0.35 },
    { "sdt_cloudyTo", 0.9 },
    { "sdt_cloudDryExtraMul", 2 },
    { "sdt_maxTotalExtraMul", 8 },
    { "sdt_dynamicWetnessThreshold", 0.01 },
    { "mp_enabled", true },
    { "mp_useDIRTBrushes", false },
    { "mp_freezeMudByTempEnable", true },
    { "mp_freezeAllLayersInWinterEnable", true },
    { "mp_freezeAllLayersTempC", -1 },
    { "mp_extraWheelSinkEnable", true },
    { "mp_winterSlipEnable", true },
    { "mp_winterSlipTempC", -3 },
    { "mp_winterSlipMul", 1.5 },
    { "mp_normalSlipEnable", true },
    { "mp_normalSlipMul", 1 },
    { "mp_rainSlipEnable", true },
    { "mp_rainSlipWetnessMin", 0.35 },
    { "mp_rainSlipMul", 0.85 },
    { "mp_rainSlipMaxMul", 0.69 },
    { "mp_permaStuckEnable", true },
    { "mp_permaStuckChanceOnStruggle", 0.0016 },
    { "mp_motorLoadEnable", true },
    { "mp_particlesEnable", true },
    { "mp_extraParticlesEnable", true },
    { "mp_extraParticlesPreset", 4 },
    { "mp_mudVarStrength", 0.65 },
    { "mp_mudVarCell", 10 },
    { "mp_mudBobAmp", 0.15 },
    { "mp_extraParticleOnlyWetMud", true },
    { "mp_extraParticleOffsetY", -0.19 },
    { "mp_wheelBrakeEnable", true },
    { "mp_sinkInSpeed", 1.242 },
    { "mp_sinkOutSpeed", 1.75 },
    { "mp_radiusMinFactor", 0.52 },
    { "mp_emitMultWetMud", 22.5 },
    { "mp_sizeMultWetMud", 2.1 },
    { "mp_speedMultWetMud", 2.15 },
    { "mp_wheelBrakeBase", 1.218 },
    { "mp_wheelBrakeFromSink", 2.788 },
    { "mp_wheelBrakeFromSlip", 1.926 },
    { "mp_widthBonusEnable", true },
    { "mp_widthBonusRefWidth", 0.45 },
    { "mp_widthBonusStrength", 1.45 },
    { "mp_widthBonusMax", 0.5 },
    { "fg_enabled", true },
    { "fg_permaStuckEnable", true },
    { "fg_freezeAllLayersInWinterEnable", true },
    { "fg_freezeAllLayersTempC", -2 },
    { "fg_motorLoadEnable", true },
    { "fg_wheelBrakeEnable", true },
    { "fg_radiusSinkEnable", true },
    { "fg_radiusMinFactor", 0.57 },
    { "fg_radiusSinkInSpeed", 0.069 },
    { "fg_radiusSinkOutSpeed", 0.228 },
    { "fg_slipMinMul", 0.828 },
    { "fg_slipMaxMul", 1.0536 },
    { "fg_extraParticlesEnable", true },
    { "fg_extraParticlesPreset", 4 },
    { "fg_wheelBrakeBase", 1.636 },
    { "fg_wheelBrakeFromSink", 3.202 },
    { "fg_wheelBrakeFromSlip", 1.566 },
    { "fg_widthBonusEnable", true },
    { "fg_widthBonusRefWidth", 0.5 },
    { "fg_widthBonusStrength", 1.85 },
    { "fg_widthBonusMax", 0.8 },
    { "fgp01_mud", 0.403 },
    { "fgp01_wetMul", 0.836 },
    { "fgp01_sinkMul", 3.521 },
    { "fgp01_brakeMul", 2.436 },
    { "fgp01_motorMul", 0.703 },
    { "fgp01_radiusMinFactor", 0.803 },
    { "fgp01_dirtMul", 0.48 },
    { "fgp01_slip", 0.998 },
    { "fgp01_fxExtra", true },
    { "fgp01_permaStuck", false },
    { "fgp02_mud", 0.413 },
    { "fgp02_wetMul", 0.914 },
    { "fgp02_sinkMul", 3.721 },
    { "fgp02_brakeMul", 2.588 },
    { "fgp02_motorMul", 0.754 },
    { "fgp02_radiusMinFactor", 0.795 },
    { "fgp02_dirtMul", 0.55 },
    { "fgp02_slip", 0.986 },
    { "fgp02_fxExtra", true },
    { "fgp02_permaStuck", true },
    { "fgp03_mud", 0.404 },
    { "fgp03_wetMul", 0.836 },
    { "fgp03_sinkMul", 3.572 },
    { "fgp03_brakeMul", 2.473 },
    { "fgp03_motorMul", 0.718 },
    { "fgp03_radiusMinFactor", 0.798 },
    { "fgp03_dirtMul", 0.47 },
    { "fgp03_slip", 0.998 },
    { "fgp03_fxExtra", true },
    { "fgp03_permaStuck", false },
    { "fgp04_mud", 0.462 },
    { "fgp04_wetMul", 1.019 },
    { "fgp04_sinkMul", 4.477 },
    { "fgp04_brakeMul", 3.01 },
    { "fgp04_motorMul", 0.895 },
    { "fgp04_radiusMinFactor", 0.778 },
    { "fgp04_dirtMul", 0.66 },
    { "fgp04_slip", 0.993 },
    { "fgp04_fxExtra", true },
    { "fgp04_permaStuck", true },
    { "fgp05_mud", 0.41 },
    { "fgp05_wetMul", 0.796 },
    { "fgp05_sinkMul", 3.311 },
    { "fgp05_brakeMul", 2.286 },
    { "fgp05_motorMul", 0.632 },
    { "fgp05_radiusMinFactor", 0.827 },
    { "fgp05_dirtMul", 0.36 },
    { "fgp05_slip", 1.023 },
    { "fgp05_fxExtra", true },
    { "fgp05_permaStuck", false },
    { "fgp06_mud", 0.413 },
    { "fgp06_wetMul", 0.892 },
    { "fgp06_sinkMul", 3.742 },
    { "fgp06_brakeMul", 2.572 },
    { "fgp06_motorMul", 0.757 },
    { "fgp06_radiusMinFactor", 0.788 },
    { "fgp06_dirtMul", 0.51 },
    { "fgp06_slip", 1.002 },
    { "fgp06_fxExtra", true },
    { "fgp06_permaStuck", true },
    { "fgp07_mud", 0.414 },
    { "fgp07_wetMul", 0.813 },
    { "fgp07_sinkMul", 3.414 },
    { "fgp07_brakeMul", 2.359 },
    { "fgp07_motorMul", 0.646 },
    { "fgp07_radiusMinFactor", 0.797 },
    { "fgp07_dirtMul", 0.32 },
    { "fgp07_slip", 1.023 },
    { "fgp07_fxExtra", true },
    { "fgp07_permaStuck", false },
    { "fgp08_mud", 0.398 },
    { "fgp08_wetMul", 0.779 },
    { "fgp08_sinkMul", 3.146 },
    { "fgp08_brakeMul", 2.16 },
    { "fgp08_motorMul", 0.594 },
    { "fgp08_radiusMinFactor", 0.84 },
    { "fgp08_dirtMul", 0.35 },
    { "fgp08_slip", 1.028 },
    { "fgp08_fxExtra", true },
    { "fgp08_permaStuck", false },
    { "fgp09_mud", 0.406 },
    { "fgp09_wetMul", 0.822 },
    { "fgp09_sinkMul", 3.496 },
    { "fgp09_brakeMul", 2.411 },
    { "fgp09_motorMul", 0.68 },
    { "fgp09_radiusMinFactor", 0.81 },
    { "fgp09_dirtMul", 0.41 },
    { "fgp09_slip", 1.023 },
    { "fgp09_fxExtra", true },
    { "fgp09_permaStuck", false },
    { "fgp10_mud", 0.415 },
    { "fgp10_wetMul", 0.853 },
    { "fgp10_sinkMul", 3.644 },
    { "fgp10_brakeMul", 2.527 },
    { "fgp10_motorMul", 0.728 },
    { "fgp10_radiusMinFactor", 0.794 },
    { "fgp10_dirtMul", 0.42 },
    { "fgp10_slip", 1.014 },
    { "fgp10_fxExtra", true },
    { "fgp10_permaStuck", true },
    { "fgp11_mud", 0.411 },
    { "fgp11_wetMul", 0.792 },
    { "fgp11_sinkMul", 3.173 },
    { "fgp11_brakeMul", 2.189 },
    { "fgp11_motorMul", 0.582 },
    { "fgp11_radiusMinFactor", 0.822 },
    { "fgp11_dirtMul", 0.25 },
    { "fgp11_slip", 1.029 },
    { "fgp11_fxExtra", true },
    { "fgp11_permaStuck", false },
    { "fgp12_mud", 0.384 },
    { "fgp12_wetMul", 0.788 },
    { "fgp12_sinkMul", 3.239 },
    { "fgp12_brakeMul", 2.214 },
    { "fgp12_motorMul", 0.626 },
    { "fgp12_radiusMinFactor", 0.828 },
    { "fgp12_dirtMul", 0.8 },
    { "fgp12_slip", 1.018 },
    { "fgp12_fxExtra", true },
    { "fgp12_permaStuck", false },
    { "fgp13_mud", 0.408 },
    { "fgp13_wetMul", 0.788 },
    { "fgp13_sinkMul", 3.239 },
    { "fgp13_brakeMul", 2.214 },
    { "fgp13_motorMul", 0.618 },
    { "fgp13_radiusMinFactor", 0.832 },
    { "fgp13_dirtMul", 0.78 },
    { "fgp13_slip", 1.021 },
    { "fgp13_fxExtra", true },
    { "fgp13_permaStuck", false },
    { "fgp14_mud", 0.063 },
    { "fgp14_wetMul", 0.711 },
    { "fgp14_sinkMul", 2.719 },
    { "fgp14_brakeMul", 1.853 },
    { "fgp14_motorMul", 0.526 },
    { "fgp14_radiusMinFactor", 0.917 },
    { "fgp14_dirtMul", 0.74 },
    { "fgp14_slip", 0.966 },
    { "fgp14_fxExtra", true },
    { "fgp14_permaStuck", false },
    { "fgp15_mud", 0.063 },
    { "fgp15_wetMul", 0.711 },
    { "fgp15_sinkMul", 2.719 },
    { "fgp15_brakeMul", 1.853 },
    { "fgp15_motorMul", 0.526 },
    { "fgp15_radiusMinFactor", 0.917 },
    { "fgp15_dirtMul", 0.74 },
    { "fgp15_slip", 0.966 },
    { "fgp15_fxExtra", true },
    { "fgp15_permaStuck", false },
}


function AS_MudPreset:getSavegameKey()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi == nil or mi.savegameIndex == nil then return nil end
    return "sg" .. tostring(mi.savegameIndex)
end

function AS_MudPreset:getSettings()
    local mss = getMudClass("MudSystemSettings")
    if mss == nil or mss._getItemById == nil or mss.applyOneItemValue == nil then return nil end
    return mss
end

local function mpFinish(mss)
    pcall(mss.applyDerivedTargetsAfterLoad, mss)
    pcall(mss.writeSettings, mss)
    pcall(mss.refreshMenuStates, mss)
    local ev = getMudClass("MudSystemSettingsSyncEvent")
    if ev ~= nil and ev.sendSnapshot ~= nil and mss.collectSnapshot ~= nil then
        pcall(function() ev.sendSnapshot(mss:collectSnapshot()) end)
    end
end

-- Accès aux objets de Tractor Terrain Dynamics (chaque mod a son propre environnement)
local function ttdGet(name)
    local v = _G[name]
    if v ~= nil then return v end
    local env = FS25_TractorTerrainDynamics
    if type(env) == "table" then return env[name] end
    return nil
end

-- Règle la difficulté de TTD comme le fait son propre menu (et la synchronise en multijoueur)
function AS_MudPreset:setTTDDifficulty(difficulty)
    local shared = ttdGet("g_TTD_Shared")
    if shared == nil or shared.CONFIG == nil then
        return false
    end
    if shared.CONFIG.DIFFICULTY == difficulty then
        return true
    end
    shared.CONFIG.DIFFICULTY = difficulty
    local ev = ttdGet("TTDGroundDataEvent")
    if ev ~= nil and ev.new ~= nil then
        pcall(function()
            local event = ev.new(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, difficulty)
            if g_server ~= nil then
                g_server:broadcastEvent(event)
            elseif g_client ~= nil then
                g_client:getServerConnection():sendEvent(event)
            end
        end)
    end
    local settings = ttdGet("TTD_Settings")
    if settings ~= nil and settings.updateSettings ~= nil then
        pcall(settings.updateSettings, settings)
    end
    vtpInfo(string.format("[AS_MudPreset] Tractor Terrain Dynamics : difficulté réglée sur \"%s\"", difficulty))
    return true
end

function AS_MudPreset:apply()
    local mss = self:getSettings()
    if mss == nil then
        print("[AS_MudPreset] Mud System Physics introuvable : rien appliqué")
        return false
    end
    local n = 0
    for _, entry in ipairs(self.RECOMMENDED) do
        local id, value = entry[1], entry[2]
        local item = mss:_getItemById(id)
        if item ~= nil then
            local ok = pcall(mss.applyOneItemValue, mss, item, value, false)
            if ok then n = n + 1 end
        end
    end
    mpFinish(mss)
    vtpInfo(string.format("[AS_MudPreset] paramètres conseillés appliqués à Mud System Physics (%d valeurs)", n))
    self:setTTDDifficulty(self.TTD_RECOMMENDED)
    return true
end

function AS_MudPreset:update(dt)
    if self.done or g_currentMission == nil then return end
    -- seul l'hôte (ou le jeu solo) applique les réglages
    if g_server == nil then
        self.done = true
        return
    end
    if self:getSavegameKey() == nil or self:getSettings() == nil then return end
    -- on attend quelques secondes : sauvegarde, véhicules et réglages des autres mods
    -- (dont la difficulté de Tractor Terrain Dynamics) doivent être chargés avant
    self.timer = self.timer + (dt or 0)
    if self.timer < self.ASK_DELAY_MS then return end
    self:apply()
    self.done = true
end

function AS_MudPreset:deleteMap()
    self.done, self.timer = false, 0
end

addModEventListener(AS_MudPreset)
