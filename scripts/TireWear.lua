-- AutoSwitch : Real Physics - Tire Wear (Reifenverschleiß) désactivé et bloqué
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.2.0 : Real Physics - Tire Wear n'est plus utilisé, Use Your Tyres est le seul
--   mod d'usure des pneus. S'il est activé dans la partie du joueur, AutoSwitch le
--   désactive et le bloque, sans toucher à ses fichiers :
--   - son propre interrupteur de conflit (rvCompatibilityBlocked, présent dans tous
--     ses fichiers depuis la 1.2.2.76) est déclenché dès le chargement d'AutoSwitch,
--     avant lui : plus d'usure, d'adhérence, d'antidémarrage, de limite AutoDrive,
--     de textures, de bouton atelier ni de sauvegarde ;
--   - filet pour les versions sans cet interrupteur : ses fonctions de conduite sont
--     neutralisées au premier update (adhérence, neige, chenilles, limite AutoDrive,
--     antidémarrage de 5 s, mise à jour de l'usure, HUD) ;
--   - la fenêtre « deux mods d'usure » de Mud System Physics est retirée.
--   Une notification en jeu et l'onglet AUTOSWITCH disent qu'il est bloqué.
-------------------------------------------------------------------------------

AS_TireWear = {}
AS_TireWear.installed = false
AS_TireWear.notified = false
AS_TireWear.mspSilenced = false
-- clé lue par l'interrupteur de Reifenverschleiß (tout nom contenant « realtirewear »)
AS_TireWear.KILL_KEY = "FS25_AutoSwitch_blocksRealTireWear"

-- nom du mod Reifenverschleiß installé (il change selon la version)
function AS_TireWear:findModName(activeOnly)
    if g_modManager == nil or type(g_modManager.mods) ~= "table" then return nil end
    for _, mod in pairs(g_modManager.mods) do
        local name = type(mod) == "table" and mod.modName or nil
        if type(name) == "string" and string.find(name, "^FS25_Reifenverschleiss") ~= nil
            and (not activeOnly or (g_modIsLoaded ~= nil and g_modIsLoaded[name] == true)) then
            return name
        end
    end
    return nil
end

-- dès le chargement d'AutoSwitch (Reifenverschleiß est chargé après lui)
if AS_TireWear:findModName(false) ~= nil and type(g_modIsLoaded) == "table" then
    g_modIsLoaded[AS_TireWear.KILL_KEY] = true
end

-- Mud System Physics : fenêtre « deux mods d'usure » retirée, AutoSwitch arbitre
function AS_TireWear:silenceMspWarning()
    if self.mspSilenced then return end
    local rvc = AS.modGlobal("FS25_MudSystemPhysics", "ReifenverschleissCompatibility")
    if type(rvc) ~= "table" or type(rvc.queueDualWearWarning) ~= "function" then return end
    self.mspSilenced = true
    rvc.queueDualWearWarning = function(r)
        if r._dualWearWarningQueued == true then return false end
        r._dualWearWarningQueued = true
        print("[AS_TireWear] avertissement « deux mods d'usure » de Mud System Physics retiré : Real Physics - Tire Wear est bloqué")
        return false
    end
    rvc.showDualWearWarning = function(r, onComplete)
        if onComplete ~= nil then onComplete() end
        return false
    end
end

function AS_TireWear:loadMap()
    if self:findModName(true) ~= nil then
        self:silenceMspWarning()
    end
end

local function noop() end
local function none() return nil, nil end

-- filet : fonctions de Reifenverschleiß qui agissent sur la conduite
function AS_TireWear:block(core, modName)
    for _, fn in ipairs({ "getWearAppliedTarget", "getRubberTrackRollerWear01ForSpeedMalus", "getOwnWear01ForHUD" }) do
        if type(core[fn]) == "function" then core[fn] = none end
    end
    for _, fn in ipairs({ "applySnowFriction", "update", "processAutomatedVehicleUpdate", "draw", "setVehicle" }) do
        if type(core[fn]) == "function" then core[fn] = noop end
    end
    core.currentVehicle = nil
    core.manifest = nil
    local wfs = AS.modGlobal(modName, "ReifenVerschleissWegfahrsperre")
    if type(wfs) == "table" then
        wfs.TIMER_DURATION = 0
        -- plus aucun véhicule verrouillé : les écritures de l'antidémarrage sont ignorées
        wfs.lockedVehicles = setmetatable({}, { __mode = "k", __newindex = noop })
    end
    print(string.format("[AS_TireWear] %s désactivé et bloqué par AutoSwitch (Use Your Tyres est le mod d'usure)", modName))
end

function AS_TireWear:notify()
    if self.notified or g_currentMission == nil or g_currentMission.addIngameNotification == nil then return end
    self.notified = true
    local text = "Real Physics - Tire Wear : désactivé et bloqué par AutoSwitch (Use Your Tyres est le mod d'usure)"
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText("vtpas_rvBlockedNotif") then
        text = g_i18n:getText("vtpas_rvBlockedNotif")
    end
    pcall(g_currentMission.addIngameNotification, g_currentMission, FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
end

function AS_TireWear:update(dt)
    if self.installed then
        if not self.notified and g_currentMission ~= nil and g_currentMission.hud ~= nil then self:notify() end
        return
    end
    local modName = self:findModName(true)
    if modName == nil then
        self.installed = true
        self.notified = true
        return
    end
    self.installed = true
    self:silenceMspWarning()
    local core = AS.modGlobal(modName, "ReifenVerschleissCore")
    if type(core) == "table" then
        self:block(core, modName)
    end
end

addModEventListener(AS_TireWear)
