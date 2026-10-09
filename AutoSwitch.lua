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
--   TireDirtKeep  la saleté des pneus part moins vite en roulant
--   Settings      menu Paramètres et sauvegarde des réglages (toujours en dernier)
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
    "scripts/TireDirtKeep.lua",
    "scripts/Settings.lua",
}

for _, file in ipairs(FILES) do
    local path = Utils.getFilename(file, modDir)
    if fileExists(path) then
        source(path)
    else
        print("[AutoSwitch] ERREUR : fichier introuvable : " .. tostring(path))
    end
end
