-- AutoSwitch : paramètres conseillés Mud System Physics / Tractor Terrain Dynamics
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.12 : au premier chargement de chaque sauvegarde, on demande s'il faut appliquer
--   les paramètres conseillés (réalistes et équilibrés) à Mud System Physics.
--   Oui : paramètres conseillés par AutoSwitch (profils de sol, frein de roue...).
--   Non : paramètres d'origine de Mud System Physics (sa remise à zéro complète).
--   Le choix est mémorisé par sauvegarde (modSettings/FS25_AutoSwitch/settings.xml)
--   et peut être changé ensuite dans le menu Paramètres.
--   Les valeurs passent par l'API de Mud System Physics : aucun de ses fichiers n'est modifié.
-------------------------------------------------------------------------------
AS_MudPreset = {}
AS_MudPreset.ASK_DELAY_MS = 6000
AS_MudPreset.timer = 0
AS_MudPreset.done = false
AS_MudPreset.queued = false

-- Version des paramètres conseillés : si elle augmente, les sauvegardes réglées sur
-- "conseillés" sont mises à jour automatiquement au chargement.
-- v2 (v1.17) : difficulté +20 % (enfoncement, frein de roue, charge moteur, profondeur d'ornière, perte d'adhérence)
-- v3 (v1.18) : + Tractor Terrain Dynamics en difficulté "Difficile" (c'est TTD qui gère le patinage des tracteurs)
AS_MudPreset.RECOMMENDED_VERSION = 3
AS_MudPreset.TTD_RECOMMENDED = "hard"
AS_MudPreset.TTD_ORIGINAL = "medium"

AS_MudPreset.RECOMMENDED = {
    mp_permaStuckEnable = true,
    mp_permaStuckChanceOnStruggle = 0.0016,
    mp_sinkInSpeed = 1.242,
    mp_wheelBrakeBase = 1.218,
    mp_wheelBrakeFromSink = 2.788,
    mp_wheelBrakeFromSlip = 1.926,
    mp_useDIRTBrushes = false,
    mp_mudVarStrength = 0.65,
    fg_permaStuckEnable = true,
    fg_radiusSinkInSpeed = 0.069,
    fg_slipMinMul = 0.828,
    fg_slipMaxMul = 1.0536,
    fg_wheelBrakeBase = 1.636,
    fg_wheelBrakeFromSink = 3.202,
    fg_wheelBrakeFromSlip = 1.566,
    fgp01_mud = 0.403,
    fgp01_wetMul = 0.836,
    fgp01_sinkMul = 3.521,
    fgp01_brakeMul = 2.436,
    fgp01_motorMul = 0.703,
    fgp01_radiusMinFactor = 0.803,
    fgp01_slip = 0.998,
    fgp01_permaStuck = false,
    fgp02_mud = 0.413,
    fgp02_wetMul = 0.914,
    fgp02_sinkMul = 3.721,
    fgp02_brakeMul = 2.588,
    fgp02_motorMul = 0.754,
    fgp02_radiusMinFactor = 0.795,
    fgp02_slip = 0.986,
    fgp02_permaStuck = true,
    fgp03_mud = 0.404,
    fgp03_wetMul = 0.836,
    fgp03_sinkMul = 3.572,
    fgp03_brakeMul = 2.473,
    fgp03_motorMul = 0.718,
    fgp03_radiusMinFactor = 0.798,
    fgp03_slip = 0.998,
    fgp03_permaStuck = false,
    fgp04_mud = 0.462,
    fgp04_wetMul = 1.019,
    fgp04_sinkMul = 4.477,
    fgp04_brakeMul = 3.01,
    fgp04_motorMul = 0.895,
    fgp04_radiusMinFactor = 0.778,
    fgp04_slip = 0.993,
    fgp04_permaStuck = true,
    fgp05_mud = 0.41,
    fgp05_wetMul = 0.796,
    fgp05_sinkMul = 3.311,
    fgp05_brakeMul = 2.286,
    fgp05_motorMul = 0.632,
    fgp05_radiusMinFactor = 0.827,
    fgp05_slip = 1.023,
    fgp05_permaStuck = false,
    fgp06_mud = 0.413,
    fgp06_wetMul = 0.892,
    fgp06_sinkMul = 3.742,
    fgp06_brakeMul = 2.572,
    fgp06_motorMul = 0.757,
    fgp06_radiusMinFactor = 0.788,
    fgp06_slip = 1.002,
    fgp06_permaStuck = true,
    fgp07_mud = 0.414,
    fgp07_wetMul = 0.813,
    fgp07_sinkMul = 3.414,
    fgp07_brakeMul = 2.359,
    fgp07_motorMul = 0.646,
    fgp07_radiusMinFactor = 0.797,
    fgp07_slip = 1.023,
    fgp07_permaStuck = false,
    fgp08_mud = 0.398,
    fgp08_wetMul = 0.779,
    fgp08_sinkMul = 3.146,
    fgp08_brakeMul = 2.16,
    fgp08_motorMul = 0.594,
    fgp08_radiusMinFactor = 0.84,
    fgp08_slip = 1.028,
    fgp08_permaStuck = false,
    fgp09_mud = 0.406,
    fgp09_wetMul = 0.822,
    fgp09_sinkMul = 3.496,
    fgp09_brakeMul = 2.411,
    fgp09_motorMul = 0.68,
    fgp09_radiusMinFactor = 0.81,
    fgp09_slip = 1.023,
    fgp09_permaStuck = false,
    fgp10_mud = 0.415,
    fgp10_wetMul = 0.853,
    fgp10_sinkMul = 3.644,
    fgp10_brakeMul = 2.527,
    fgp10_motorMul = 0.728,
    fgp10_radiusMinFactor = 0.794,
    fgp10_slip = 1.014,
    fgp10_permaStuck = true,
    fgp11_mud = 0.411,
    fgp11_wetMul = 0.792,
    fgp11_sinkMul = 3.173,
    fgp11_brakeMul = 2.189,
    fgp11_motorMul = 0.582,
    fgp11_radiusMinFactor = 0.822,
    fgp11_slip = 1.029,
    fgp11_permaStuck = false,
    fgp12_mud = 0.384,
    fgp12_wetMul = 0.788,
    fgp12_sinkMul = 3.239,
    fgp12_brakeMul = 2.214,
    fgp12_motorMul = 0.626,
    fgp12_radiusMinFactor = 0.828,
    fgp12_slip = 1.018,
    fgp12_permaStuck = false,
    fgp13_mud = 0.408,
    fgp13_wetMul = 0.788,
    fgp13_sinkMul = 3.239,
    fgp13_brakeMul = 2.214,
    fgp13_motorMul = 0.618,
    fgp13_radiusMinFactor = 0.832,
    fgp13_slip = 1.021,
    fgp13_permaStuck = false,
    fgp14_mud = 0.063,
    fgp14_wetMul = 0.711,
    fgp14_sinkMul = 2.719,
    fgp14_brakeMul = 1.853,
    fgp14_motorMul = 0.526,
    fgp14_radiusMinFactor = 0.917,
    fgp14_slip = 0.966,
    fgp14_permaStuck = false,
    fgp15_mud = 0.063,
    fgp15_wetMul = 0.711,
    fgp15_sinkMul = 2.719,
    fgp15_brakeMul = 1.853,
    fgp15_motorMul = 0.526,
    fgp15_radiusMinFactor = 0.917,
    fgp15_slip = 0.966,
    fgp15_permaStuck = false,
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

-- choice = "recommended" ou "original"
function AS_MudPreset:apply(choice)
    local mss = self:getSettings()
    if mss == nil then
        print("[AS_MudPreset] Mud System Physics introuvable : rien appliqué")
        return false
    end
    if choice == "recommended" then
        local n = 0
        for id, value in pairs(self.RECOMMENDED) do
            local item = mss:_getItemById(id)
            if item ~= nil then
                local ok = pcall(mss.applyOneItemValue, mss, item, value, false)
                if ok then n = n + 1 end
            end
        end
        mpFinish(mss)
        vtpInfo(string.format("[AS_MudPreset] paramètres conseillés appliqués à Mud System Physics (%d valeurs)", n))
        self:setTTDDifficulty(self.TTD_RECOMMENDED)
    else
        if mss.resetToDefaults ~= nil then
            pcall(mss.resetToDefaults, mss)
        end
        mpFinish(mss)
        vtpInfo("[AS_MudPreset] paramètres d'origine de Mud System Physics rétablis")
        self:setTTDDifficulty(self.TTD_ORIGINAL)
    end
    return true
end

function AS_MudPreset:remember(choice)
    local key = self:getSavegameKey()
    if key ~= nil and AS_Settings ~= nil then
        AS_Settings.mudChoices = AS_Settings.mudChoices or {}
        AS_Settings.mudChoices[key] = choice
        AS_Settings.mudVersions = AS_Settings.mudVersions or {}
        AS_Settings.mudVersions[key] = (choice == "recommended") and self.RECOMMENDED_VERSION or nil
        AS_Settings:save()
        if AS_Settings.refreshStates ~= nil then AS_Settings:refreshStates() end
    end
end

function AS_MudPreset:getChoice()
    local key = self:getSavegameKey()
    if key == nil or AS_Settings == nil or AS_Settings.mudChoices == nil then return nil end
    return AS_Settings.mudChoices[key]
end

function AS_MudPreset:onAnswer(yes)
    local choice = yes and "recommended" or "original"
    self:apply(choice)
    self:remember(choice)
end

function AS_MudPreset:showDialog(onComplete)
    local title = L("vtpas_mudPreset_title")
    local text  = L("vtpas_mudPreset_text")
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(function(yes)
            AS_MudPreset:onAnswer(yes == true)
            if onComplete ~= nil then onComplete() end
        end, nil, text, title, L("vtpas_mudPreset_yes"), L("vtpas_mudPreset_no"))
        return true
    elseif g_gui ~= nil and g_gui.showYesNoDialog ~= nil then
        g_gui:showYesNoDialog({ title = title, text = text, callback = function(_, yes)
            AS_MudPreset:onAnswer(yes == true)
            if onComplete ~= nil then onComplete() end
        end })
        return true
    end
    print("[AS_MudPreset] boîte de dialogue indisponible")
    return false
end

function AS_MudPreset:update(dt)
    if self.done or self.queued or g_currentMission == nil then return end
    -- seul l'hôte (ou le jeu solo) décide des réglages ; il faut une interface
    if g_server == nil or g_gui == nil or g_dedicatedServer ~= nil then
        self.done = true
        return
    end
    if self:getSavegameKey() == nil or self:getSettings() == nil then return end
    -- on attend quelques secondes : sauvegarde, véhicules et réglages des autres mods
    -- (dont la difficulté de Tractor Terrain Dynamics) doivent être chargés avant
    self.timer = self.timer + (dt or 0)
    if self.timer < self.ASK_DELAY_MS then return end
    local choice = self:getChoice()
    if choice ~= nil then
        -- paramètres conseillés d'une ancienne version : mise à jour automatique
        if choice == "recommended" then
            local key = self:getSavegameKey()
            local versions = AS_Settings.mudVersions or {}
            if (versions[key] or 1) < self.RECOMMENDED_VERSION then
                vtpInfo(string.format("[AS_MudPreset] mise à jour des paramètres conseillés (v%d -> v%d)",
                    versions[key] or 1, self.RECOMMENDED_VERSION))
                self:apply("recommended")
                self:remember("recommended")
            end
        end
        self.done = true
        return
    end
    if g_gui.getIsDialogVisible ~= nil and g_gui:getIsDialogVisible() then return end

    self.queued = true
    local queue = getMudClass("MudSystemDialogQueue")
    if queue ~= nil and queue.enqueue ~= nil then
        queue:enqueue("vtpasMudPreset", 50, function(onComplete)
            return AS_MudPreset:showDialog(onComplete)
        end)
    else
        self:showDialog(nil)
    end
end

function AS_MudPreset:deleteMap()
    self.done, self.queued, self.timer = false, false, 0
end

function AS_MudPreset:consoleCommand(arg)
    if arg == "conseille" or arg == "recommended" then
        self:apply("recommended"); self:remember("recommended")
        return "Paramètres conseillés appliqués à Mud System Physics"
    elseif arg == "origine" or arg == "original" then
        self:apply("original"); self:remember("original")
        return "Paramètres d'origine de Mud System Physics rétablis"
    elseif arg == "demander" or arg == "ask" then
        local key = self:getSavegameKey()
        if key ~= nil and AS_Settings.mudChoices ~= nil then
            AS_Settings.mudChoices[key] = nil
            AS_Settings:save()
        end
        self.done, self.queued, self.timer = false, false, 0
        return "La question sera reposée dans quelques secondes"
    end
    return "Usage : vtpMudPreset conseille | origine | demander"
end

function AS_MudPreset:loadMap()
    addConsoleCommand("vtpMudPreset", "Mud System Physics : conseille | origine | demander", "consoleCommand", self)
end

function AS_MudPreset:delete()
    removeConsoleCommand("vtpMudPreset")
end

addModEventListener(AS_MudPreset)
