-- =============================================================================
-- FS25_AutoSwitch  -  AutoSwitch.lua  (fichier général, v2.2)
-- Auteur : Fabien
--
-- Charge chaque partie du mod, dans l'ordre :
--   Common        fonctions communes (textes, champ, patinage, notifications...)
--   Arbiter       arbitrage entre les mods (blocages, ordre des crochets) à la place de ModMixer
--   Tires         gonflage / dégonflage automatique (Variable Tire Pressure)
--   Diff          différentiels, 4x4 / 4x2, déblocage en virage (Enhanced Vehicle)
--   SteerLimit    braquage 4x4 limité, blocages coupés / refusés roues braquées
--   SlipAlert     alerte rouge de patinage
--   SpeedHint     plage de vitesse conseillée + icône de patinage
--   SeedProtect   protection du semis (Mud System Physics)
--   SeedCoverFill remplissage du semoir couvercle fermé
--   WetGrip       adhérence en sol humide (MoreRealistic), bonus différentiels, usure
--   Duals         roues jumelées (largeur réelle pour Mud, adhérence)
--   VtpFix        correctif VTP pour pneus à variantes de marques
--   DualRack      palette de pneus : simple <-> jumelées (Ctrl droit + I)
--   DirectResow   semis direct sur zones effacées
--   MudPreset     paramètres conseillés Mud System Physics / Tractor Terrain Dynamics
--   AdSpeed       vitesse d'AutoDrive selon le terrain (champ / chemin / route)
--   TireTracksSave traces de pneus gardées avec la partie
--   ImplementStabilizer outils stables à l'arrêt (rayon des roues figé)
--   MudWheelDrag  résistance de boue sur les roues sans frein
--   TtdBridge     pont MSP -> TTD : humidité locale, pas de résistance en double
--   TireDirtKeep  la saleté des pneus part moins vite en roulant
--   SleepPlus     menu Dormir : avancer de X heures ou de X jours
--   Settings      menu Paramètres et sauvegarde des réglages (toujours en dernier)
--
-- v1.0.0.29 : contrôle des versions. Chaque mod requis doit être au moins à la
-- version utilisée pour régler AutoSwitch ; sinon AutoSwitch ne démarre pas
-- (aucun module chargé) et un message l'indique en jeu et dans log.txt.
-- v1.0.0.30 : la 1.0.0.29 déclarait « introuvables » les mods requis chargés
-- après AutoSwitch ; seule la version déclarée par le gestionnaire de mods compte.
-- =============================================================================

local modDir = g_currentModDirectory or ""

local FILES = {
    "scripts/Common.lua",
    "scripts/Arbiter.lua",
    "scripts/Tires.lua",
    "scripts/Diff.lua",
    "scripts/SteerLimit.lua",
    "scripts/SlipAlert.lua",
    "scripts/SpeedHint.lua",
    "scripts/SeedProtect.lua",
    "scripts/SeedCoverFill.lua",
    "scripts/WetGrip.lua",
    "scripts/Duals.lua",
    "scripts/VtpFix.lua",
    "scripts/DualRack.lua",
    "scripts/DirectResow.lua",
    "scripts/MudPreset.lua",
    "scripts/AdSpeed.lua",
    "scripts/TireTracksSave.lua",
    "scripts/ImplementStabilizer.lua",
    "scripts/MudWheelDrag.lua",
    "scripts/TtdBridge.lua",
    "scripts/TireDirtKeep.lua",
    "scripts/SleepPlus.lua",
    "scripts/Settings.lua",
}

-- Versions minimales des mods requis (versions utilisées pour régler AutoSwitch)
local REQUIRED = {
    { "FS25_VariableTirePressure",    "1.0.0.13" },
    { "FS25_AutoDrive",               "3.0.1.4" },
    { "FS25_Courseplay",              "8.1.0.3" },
    { "FS25_EnhancedVehicle",         "1.1.7.1" },
    { "FS25_MudSystemPhysics",        "1.3.6.0" },
    { "FS25_DynamicDrivePro",         "1.0.1.0" },
    { "FS25_TractorTerrainDynamics",  "1.0.3.7" },
    { "MoreRealistic",                "0.26.09.13" },
    { "moreRealisticXmlDatabank",     "1.0.0.1" },
    { "FS25_RealisticHarvesting",     "1.6.0.0" },
    { "FS25_CropDestructionOverhaul", "1.1.0.0" },
    { "FS25_MoistureSystem",          "2.0.0.8" },
    { "FS25_useYourTyres",            "1.1.0.0" },
}

-- -1 si a < b, 0 si égales, 1 si a > b ; nil si une version est illisible
local function compareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    if #pa == 0 or #pb == 0 then return nil end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end

-- Liste des mods trop anciens ou absents : { name, title, found, required }
local function checkVersions()
    local bad = {}
    if g_modManager == nil or g_modManager.getModByName == nil then
        print("[AutoSwitch] contrôle des versions impossible (gestionnaire de mods introuvable)")
        return bad
    end
    for _, req in ipairs(REQUIRED) do
        local name, minVersion = req[1], req[2]
        local ok, mod = pcall(g_modManager.getModByName, g_modManager, name)
        -- pas de g_modIsLoaded : les mods requis dont le nom vient après FS25_AutoSwitch
        -- ne sont pas encore chargés à ce moment-là (v1.0.0.30)
        if not ok or mod == nil then
            bad[#bad + 1] = { name = name, title = name, found = nil, required = minVersion }
        else
            local cmp = compareVersions(mod.version, minVersion)
            if cmp ~= nil and cmp < 0 then
                bad[#bad + 1] = { name = name, title = mod.title or name, found = mod.version, required = minVersion }
            end
        end
    end
    return bad
end

local function text(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback
end

local badMods = checkVersions()

if #badMods > 0 then
    for _, m in ipairs(badMods) do
        if m.found ~= nil then
            print(string.format("[AutoSwitch] ERREUR : %s version %s trouvée, %s minimum requise", m.name, tostring(m.found), m.required))
        else
            print(string.format("[AutoSwitch] ERREUR : %s introuvable, %s minimum requise", m.name, m.required))
        end
    end
    print("[AutoSwitch] AutoSwitch désactivé : mettre à jour les mods ci-dessus")

    -- Message en jeu au premier update de la partie
    AS_VersionCheck = { shown = false, badMods = badMods }
    function AS_VersionCheck:update(dt)
        if self.shown then return end
        if g_currentMission == nil or g_gui == nil then return end
        self.shown = true
        local lines = {}
        for _, m in ipairs(self.badMods) do
            if m.found ~= nil then
                lines[#lines + 1] = string.format(text("vtpas_versionLine", "%s : version %s, %s minimum requise"), tostring(m.title), tostring(m.found), m.required)
            else
                lines[#lines + 1] = string.format(text("vtpas_versionMissing", "%s : introuvable, %s minimum requise"), tostring(m.title), m.required)
            end
        end
        local msg = text("vtpas_versionDisabled", "AutoSwitch est désactivé : certains mods requis sont trop anciens.") .. "\n\n" .. table.concat(lines, "\n")
        local shown = false
        if InfoDialog ~= nil and InfoDialog.show ~= nil then
            shown = pcall(InfoDialog.show, msg, nil, nil, DialogElement ~= nil and DialogElement.TYPE_WARNING or nil)
        end
        if not shown and g_currentMission.showBlinkingWarning ~= nil then
            pcall(g_currentMission.showBlinkingWarning, g_currentMission, msg, 15000)
        end
    end
    addModEventListener(AS_VersionCheck)
    return
end

for _, file in ipairs(FILES) do
    local path = Utils.getFilename(file, modDir)
    if fileExists(path) then
        source(path)
    else
        print("[AutoSwitch] ERREUR : fichier introuvable : " .. tostring(path))
    end
end
