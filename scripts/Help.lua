-- AutoSwitch : aide dans le menu du jeu (Échap > Aide)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).
-------------------------------------------------------------------------------
-- v1.0.1.6 : catégorie « AutoSwitch » ajoutée à l'aide du jeu, au même format que
--   l'aide de base : help/helpLine.xml lu par g_helpLineManager:loadFromXML
--   (comme Courseplay). Le jeu range la catégorie sous le nom du mod (sélecteur
--   en haut de la page Aide). Textes : clés as_help_* des fichiers l10n.
--   Icônes de la liste de gauche : help/as_help_icons.dds, une par page, posées
--   seulement sur les pages de notre catégorie (page.iconSliceId).
--   Chargée une fois par partie, seulement quand il y a un joueur (pas sur un
--   serveur dédié). Rien n'est modifié dans l'aide du jeu ni des autres mods.
-------------------------------------------------------------------------------
AS_Help = {}
AS_Help.MOD_DIR = g_currentModDirectory or ""
AS_Help.MOD_NAME = g_currentModName or "FS25_AutoSwitch"
AS_Help.ICON_PREFIX = "asHelp"
AS_Help.ICONS = { "intro", "diff", "tires", "ground", "hud", "weather", "fields",
    "register", "money", "hours", "road", "files" }
AS_Help.loaded = false

local function log(fmt, ...)
    print("[AS_Help] " .. string.format(fmt, ...))
end

-- notre catégorie dans le gestionnaire d'aide (titre = clé de texte du fichier)
function AS_Help:findCategory(hm)
    if hm.getCustomEnvironmentNames == nil or hm.getCategories == nil then return nil end
    for _, env in ipairs(hm:getCustomEnvironmentNames() or {}) do
        for _, cat in ipairs(hm:getCategories(env) or {}) do
            if type(cat) == "table" and cat.title == "$l10n_as_help_title" and type(cat.pages) == "table" then
                return cat
            end
        end
    end
    return nil
end

function AS_Help:setIcons(hm)
    if g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil then return end
    local configs = g_overlayManager.textureConfigs
    if configs == nil or configs[self.ICON_PREFIX] == nil then
        g_overlayManager:addTextureConfigFile(Utils.getFilename("help/as_help_icons.xml", self.MOD_DIR), self.ICON_PREFIX)
    end
    local cat = self:findCategory(hm)
    if cat == nil then
        log("icônes : catégorie introuvable")
        return
    end
    for i, page in ipairs(cat.pages) do
        local id = self.ICONS[i]
        if type(page) == "table" and id ~= nil and page.iconSliceId == nil then
            page.iconSliceId = self.ICON_PREFIX .. "." .. id
        end
    end
end

function AS_Help:load()
    if self.loaded then return end
    self.loaded = true
    local hm = g_helpLineManager
    if hm == nil or hm.loadFromXML == nil then
        log("ERREUR : aide du jeu introuvable, aide AutoSwitch non chargée")
        return
    end
    if self:findCategory(hm) ~= nil then return end   -- déjà chargée
    local path = Utils.getFilename("help/helpLine.xml", self.MOD_DIR)
    local ok, err = pcall(hm.loadFromXML, hm, path)
    if not ok then
        log("ERREUR au chargement de l'aide : %s", tostring(err))
        return
    end
    local ok2, err2 = pcall(self.setIcons, self, hm)
    if not ok2 then log("ERREUR icônes de l'aide : %s", tostring(err2)) end
    log("aide chargée (Échap > Aide > %s)", self.MOD_NAME)
end

function AS_Help:loadMap()
    if g_client == nil then return end   -- serveur dédié : pas de menu
    self:load()
end

addModEventListener(AS_Help)
