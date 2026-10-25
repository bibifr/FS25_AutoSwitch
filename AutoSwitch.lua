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
--   TireLife      usure des pneus et des chenilles (sans Use Your Tyres) : adhérence, rayon, atelier
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
--   TireWear      Real Physics - Tire Wear (Reifenverschleiß) désactivé et bloqué
--   DeletedVehicles icône de carte d'un véhicule supprimé retirée
--   TireDirtKeep  la saleté des pneus part moins vite en roulant
--   SleepPlus     menu Dormir : avancer de X heures ou de X jours
--   LightRange    lumières des véhicules visibles de plus loin
--   GrassTrample  herbe piétinée : recul de pousse au lieu du fauchage de Mud System Physics
--   WindSway      vent visible : arbres, cultures et herbe bougent selon la force du vent (x2,2)
--   Puddles       flaques : type de sol Precision Farming -> Mud System Physics, flaques visibles
--   Weather       fenêtre Météo (Ctrl droit + M) : prévisions du jeu lisibles
--   Fields        fenêtre Champs (Ctrl droit + C ou icône) : culture, stade, semis, engrais, herbicide, récolte
--   Overdraft     découvert : achat / location jusqu'à un plafond, agios chaque jour
--   CoopPay       coopératives payées en fin de mois (ventes « À payer » dans le registre)
--   Register      registre des pesées (AutoDrive Addon) et des ventes (Ctrl droit + R)
--   OpeningHours  horaires d'ouverture du magasin et des points de vente
--   HudDedup      affichages en double des autres mods masqués (Enhanced Vehicle...)
--   NoOvertake    les voitures du trafic ne doublent plus les tracteurs
--   TrafficSensor capteur des voitures du trafic réduit à 80 % (elles ne freinent plus en croisant un tracteur)
--   Settings      menu Paramètres et sauvegarde des réglages (toujours en dernier)
--
-- v1.0.0.29 : contrôle des versions. Chaque mod requis doit être au moins à la
-- version utilisée pour régler AutoSwitch ; sinon AutoSwitch ne démarre pas
-- (aucun module chargé) et un message l'indique en jeu et dans log.txt.
-- v1.0.0.30 : la 1.0.0.29 déclarait « introuvables » les mods requis chargés
-- après AutoSwitch ; seule la version déclarée par le gestionnaire de mods compte.
-- v1.0.0.45 : Use Your Tyres n'est plus requis, Reifenverschleiß le remplace.
-- Son nom de mod change à chaque version : il est cherché par le début du nom.
-- v1.0.0.49 : un mod requis installé mais pas activé dans la partie est signalé
-- en jeu au chargement (AutoSwitch démarre quand même). Vu avec Reifenverschleiß,
-- décoché dans la sauvegarde : AutoSwitch ne le disait que dans log.txt.
-- v1.0.0.94 : usure des pneus avec Use Your Tyres OU Reifenverschleiß (entrée anyOf
-- de REQUIRED) ; si les deux sont activés, Use Your Tyres gagne et TireWear.lua bloque
-- Reifenverschleiß (adhérence, antidémarrage, limite AutoDrive, neige).
-- v1.0.1.2 : usure des pneus facultative : sans Use Your Tyres ni Reifenverschleiß,
-- rien n'est signalé, l'onglet affiche « Facultatif (Use Your Tyres recommandé) ».
-- v1.0.2.0 : Real Physics - Tire Wear retiré des mods d'usure : Use Your Tyres seul
-- (facultatif, recommandé). Si Reifenverschleiß est activé, TireWear.lua le désactive
-- et le bloque, et l'onglet AUTOSWITCH l'affiche en rouge « Bloqué par AutoSwitch ».
-- v1.0.3.0 : usure des pneus écrite pour AutoSwitch (TireLife.lua). Use Your Tyres reste
-- facultatif : s'il est activé, il garde l'usure et TireLife.lua se coupe.
-- v1.0.0.46 : Crop Destruction Overhaul n'est plus requis.
-- v1.0.0.47 : herbe piétinée corrigée (setParallelogramWorldCoords), stade le plus bas coupé.
-- v1.0.0.48 : herbe piétinée plus douce (sec dès 11 km/h, humide dès 7 km/h, un stade).
-- v1.0.0.58 : TTD accepté sous son nom ModHub (FS25_TractorTerrainDynamics) ou sous
-- le nom de la bêta KingMods (FS25_TTD_v3_7_BETA...). Retiré des dépendances du
-- modDesc : le jeu réclamait la version ModHub 1.0.0.0 en plus de la bêta.
-- Si les deux sont installés, la version la plus récente est retenue.
-- v1.0.0.87 : un mod requis absent, pas activé ou trop ancien n'empêche plus AutoSwitch
-- de démarrer : seuls les modules qui en dépendent (liste « cuts » de REQUIRED) ne
-- sont pas chargés, et un cadre en bas à gauche de l'écran liste les mods manquants
-- (v1.0.0.92 : cadre retiré, log.txt et liste en bas de l'onglet AUTOSWITCH).
-- Mods retirés des dépendances du modDesc (sinon le jeu refuse de charger AutoSwitch).
-- =============================================================================

local modDir = g_currentModDirectory or ""

local FILES = {
    "scripts/Common.lua",
    "scripts/Transmission.lua",
    "scripts/Arbiter.lua",
    "scripts/Tires.lua",
    "scripts/Diff.lua",
    "scripts/SteerLimit.lua",
    "scripts/SlipAlert.lua",
    "scripts/SpeedHint.lua",
    "scripts/SeedProtect.lua",
    "scripts/SeedCoverFill.lua",
    "scripts/WetGrip.lua",
    "scripts/TireLife.lua",
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
    "scripts/TireWear.lua",
    "scripts/DeletedVehicles.lua",
    "scripts/TireDirtKeep.lua",
    "scripts/SleepPlus.lua",
    "scripts/LightRange.lua",
    "scripts/WindSway.lua",
    "scripts/GrassTrample.lua",
    "scripts/Puddles.lua",
    "scripts/Weather.lua",
    "scripts/Fields.lua",
    "scripts/Overdraft.lua",
    "scripts/CoopPay.lua",
    "scripts/Register.lua",
    "scripts/OpeningHours.lua",
    "scripts/HudDedup.lua",
    "scripts/TrafficSensor.lua",
    "scripts/NoOvertake.lua",
    "scripts/ForageReach.lua",
    "scripts/Help.lua",
    "scripts/Settings.lua",
}

-- Versions minimales des mods requis (versions utilisées pour régler AutoSwitch).
-- cuts : modules non chargés si le mod manque (v1.0.0.87)
local MSP_CUTS = { "scripts/SeedProtect.lua", "scripts/DirectResow.lua", "scripts/Duals.lua",
    "scripts/GrassTrample.lua", "scripts/MudPreset.lua", "scripts/MudWheelDrag.lua",
    "scripts/ImplementStabilizer.lua", "scripts/TireDirtKeep.lua", "scripts/TtdBridge.lua",
    "scripts/Puddles.lua" }
local MR_CUTS = { "scripts/WetGrip.lua", "scripts/MudWheelDrag.lua", "scripts/ImplementStabilizer.lua" }
local REQUIRED = {
    { "FS25_VariableTirePressure",    "1.0.0.13", "Variable Tire Pressure", cuts = { "scripts/Tires.lua", "scripts/VtpFix.lua" } },
    { "FS25_AutoDrive",               "3.0.1.4",  "AutoDrive", cuts = { "scripts/ForageReach.lua" } },
    { "FS25_Courseplay",              "8.1.0.3",  "Courseplay" },
    { "FS25_EnhancedVehicle",         "1.1.7.1",  "Enhanced Vehicle", cuts = { "scripts/Diff.lua", "scripts/SteerLimit.lua", "scripts/HudDedup.lua" } },
    { "FS25_MudSystemPhysics",        "1.3.6.0",  "Mud System Physics", cuts = MSP_CUTS },
    { "FS25_DynamicDrivePro",         "1.0.1.0",  "DynamicDrive Pro" },
    { { "FS25_TractorTerrainDynamics", "FS25_TTD*" }, "1.0.3.7", "Tractor Terrain Dynamics", cuts = { "scripts/TtdBridge.lua" } },
    { "MoreRealistic",                "0.26.09.13", "MoreRealistic", cuts = MR_CUTS },
    { "moreRealisticXmlDatabank",     "1.0.0.1",  "MoreRealistic XML Databank", cuts = MR_CUTS },
    { "FS25_RealisticHarvesting",     "1.6.0.0",  "Realistic Harvesting" },
    { "FS25_MoistureSystem",          "2.0.0.8",  "Moisture System" },
    -- usure des pneus (v1.0.1.2 facultatif ; v1.0.2.0 Real Physics - Tire Wear retiré)
    { anyOf = {
        { "FS25_useYourTyres",       "1.1.0.0",  "Use Your Tyres" },
    }, title = "Use Your Tyres", optional = true },
}

-- (v1.0.2.0) mods désactivés et bloqués par AutoSwitch s'ils sont activés (TireWear.lua)
local BLOCKED = {
    { "FS25_Reifenverschleiss*", "", "Real Physics - Tire Wear" },
}

-- Modules coupés : table vide à leur place, pour les autres modules qui lisent leurs réglages
local STUB_NAMES = { ["scripts/SteerLimit.lua"] = "AS_Steer" }
local STUB_FIELDS = {
    AS_Diff = { MIN_WHEEL_SPEED = 1.0 },
    AS_HudDedup = { setEnabled = function() end },
}

-- mod chargé dont le nom commence par prefix (nom avec numéro de version)
local function findModByPrefix(prefix)
    if g_modManager == nil or type(g_modManager.mods) ~= "table" then return nil end
    for _, mod in pairs(g_modManager.mods) do
        if type(mod) == "table" and type(mod.modName) == "string"
            and string.sub(mod.modName, 1, #prefix) == prefix then
            return mod
        end
    end
    return nil
end

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

-- mod requis correspondant à req[1] : un nom, un début de nom (« * ») ou une liste
-- de noms ; dans une liste, la version la plus récente l'emporte (v1.0.0.58)
local function findRequired(req)
    local names = type(req[1]) == "table" and req[1] or { req[1] }
    local best
    for _, name in ipairs(names) do
        local ok, mod
        if string.sub(name, -1) == "*" then
            ok, mod = pcall(findModByPrefix, string.sub(name, 1, -2))
        elseif g_modManager ~= nil and g_modManager.getModByName ~= nil then
            ok, mod = pcall(g_modManager.getModByName, g_modManager, name)
        end
        if ok and type(mod) == "table" then
            if best == nil or (compareVersions(mod.version, best.version) or 0) > 0 then
                best = mod
            end
        end
    end
    return best, req[3] or names[1]
end

local function text(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback
end

-- Nom du mod TTD réellement installé, pour les modules qui lisent son environnement
AS_TTD_MOD_NAME = "FS25_TractorTerrainDynamics"
do
    local ok, ttdMod = pcall(findRequired, { { "FS25_TractorTerrainDynamics", "FS25_TTD*" } })
    if ok and ttdMod ~= nil and type(ttdMod.modName) == "string" then
        AS_TTD_MOD_NAME = ttdMod.modName
    end
end

-- Mod activé dans la partie ? true / false, nil si on ne peut pas encore le savoir
-- (les mods dont le nom vient après FS25_AutoSwitch sont chargés après lui).
local function isModActive(modName)
    if g_modIsLoaded ~= nil and g_modIsLoaded[modName] == true then return true end
    local mi = g_currentMission ~= nil and g_currentMission.missionDynamicInfo or nil
    if mi ~= nil and type(mi.mods) == "table" and next(mi.mods) ~= nil then
        for _, m in pairs(mi.mods) do
            local n = type(m) == "table" and m.modName or m
            if n == modName then return true end
        end
        return false
    end
    return nil
end

-- État d'un mod requis : nil si tout va bien, sinon { title, status = "absent" / "old" / "inactive", found, required }
local function checkRequired(req, final)
    local mod, name = findRequired(req)
    if mod == nil then
        return { title = name, status = "absent", required = req[2] }
    end
    local cmp = compareVersions(mod.version, req[2])
    if cmp ~= nil and cmp < 0 then
        return { title = name, status = "old", found = mod.version, required = req[2] }
    end
    local active
    if final then
        active = g_modIsLoaded ~= nil and g_modIsLoaded[mod.modName] == true
    else
        active = isModActive(mod.modName)
    end
    if active == false then
        return { title = name, status = "inactive", modName = mod.modName }
    end
    return nil
end

-- (v1.0.0.94) entrée « l'un ou l'autre » : la première possibilité en règle gagne ;
-- sinon on signale celle qui est installée (trop ancienne / pas activée), ou l'absence
local function checkAnyOf(req, final)
    local firstBad
    for i, alt in ipairs(req.anyOf) do
        local ok, bad = pcall(checkRequired, alt, final)
        if ok and bad == nil then return nil, i end
        if ok and bad ~= nil and bad.status ~= "absent" and firstBad == nil then firstBad = bad end
    end
    if firstBad ~= nil then return firstBad end
    -- (v1.0.1.2) entrée facultative : aucun des mods installé = rien à signaler
    if req.optional then return nil, nil, true end
    local versions = {}
    for _, alt in ipairs(req.anyOf) do versions[#versions + 1] = alt[2] end
    return { title = req.title, status = "absent", required = table.concat(versions, " / ") }
end

local function checkEntry(req, final)
    if req.anyOf ~= nil then return checkAnyOf(req, final) end
    return checkRequired(req, final)
end

local function logBad(m)
    if m.status == "old" then
        print(string.format("[AutoSwitch] ATTENTION : %s version %s trouvée, %s minimum requise : fonctions liées coupées", m.title, tostring(m.found), m.required))
    elseif m.status == "absent" then
        print(string.format("[AutoSwitch] ATTENTION : %s introuvable (%s minimum requise) : fonctions liées coupées", m.title, m.required))
    else
        print(string.format("[AutoSwitch] ATTENTION : %s (%s) n'est pas activé dans cette partie", m.title, tostring(m.modName)))
    end
end

-- (v1.0.0.87) modules coupés selon les mods requis manquants
local skip = {}
local logged = {}
for _, req in ipairs(REQUIRED) do
    local ok, bad = pcall(checkEntry, req, false)
    if ok and bad ~= nil then
        logBad(bad)
        logged[bad.title] = bad.status
        for _, file in ipairs(req.cuts or {}) do skip[file] = true end
    end
end

for _, file in ipairs(FILES) do
    if skip[file] then
        local global = STUB_NAMES[file] or ("AS_" .. string.match(file, "([%w_]+)%.lua$"))
        local stub = { disabled = true, ENABLED = false }
        for k, v in pairs(STUB_FIELDS[global] or {}) do stub[k] = v end
        _G[global] = stub
        print("[AutoSwitch] module coupé (mod requis manquant) : " .. file)
    else
        local path = Utils.getFilename(file, modDir)
        if fileExists(path) then
            source(path)
        else
            print("[AutoSwitch] ERREUR : fichier introuvable : " .. tostring(path))
        end
    end
end

-------------------------------------------------------------------------------
-- (v1.0.0.87) mods requis manquants : liste refaite au premier update de la partie,
-- quand tous les mods sont chargés. (v1.0.0.92) plus de cadre à l'écran : log.txt,
-- et la liste complète (coche verte / croix rouge) en bas de l'onglet AUTOSWITCH.
-------------------------------------------------------------------------------
AS_ModCheck = { done = false, bad = {}, all = {} }

function AS_ModCheck:update(dt)
    if self.done then return end
    if g_currentMission == nil or g_modIsLoaded == nil then return end
    self.done = true
    for _, req in ipairs(REQUIRED) do
        local ok, bad, altIndex, none = pcall(checkEntry, req, true)
        local entry
        if req.anyOf ~= nil then
            if ok and none == true then
                entry = { title = req.title, required = "", status = "optional" }
                print(string.format("[AutoSwitch] %s : aucun installé (facultatif), usure des pneus gérée par AutoSwitch", req.title))
            elseif altIndex ~= nil then
                local alt = req.anyOf[altIndex]
                local mod, name = findRequired(alt)
                entry = { title = name, required = alt[2], found = mod ~= nil and mod.version or nil }
            else
                entry = { title = req.title, required = ok and bad ~= nil and bad.required or "",
                    found = ok and bad ~= nil and bad.found or nil }
            end
        else
            local mod, name = findRequired(req)
            entry = { title = name, required = req[2], found = mod ~= nil and mod.version or nil }
        end
        if ok and bad ~= nil then
            if logged[bad.title] ~= bad.status then logBad(bad) end
            self.bad[#self.bad + 1] = bad
            entry.status = bad.status
        end
        self.all[#self.all + 1] = entry
    end
    -- (v1.0.2.0) mods bloqués, en rouge dans l'onglet s'ils sont activés
    for _, b in ipairs(BLOCKED) do
        local mod, name = findRequired(b)
        if mod ~= nil and g_modIsLoaded[mod.modName] == true then
            self.all[#self.all + 1] = { title = name, required = "", found = mod.version, status = "blocked",
                tip = text("vtpas_rvBlockedNotif", "Désactivé et bloqué par AutoSwitch") }
        end
    end
end

-- texte d'état d'un mod requis pour le menu
function AS_ModCheck:statusText(m)
    if m.status == "old" then
        return string.format(text("vtpas_reqOld", "Version %s (%s requise)"), tostring(m.found), m.required)
    elseif m.status == "absent" then
        return text("vtpas_reqAbsent", "Absent")
    elseif m.status == "inactive" then
        return text("vtpas_reqInactive", "Pas activé")
    elseif m.status == "blocked" then
        return text("vtpas_reqBlockedMod", "X  Bloqué par AutoSwitch")
    elseif m.status == "optional" then
        return text("vtpas_reqOptional", "Facultatif (Use Your Tyres recommandé)")
    end
    return string.format(text("vtpas_reqOk", "OK (%s)"), tostring(m.found))
end

addModEventListener(AS_ModCheck)
