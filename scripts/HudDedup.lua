-- AutoSwitch : affichages en double des autres mods masqués
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.78 : certains mods affichent des infos qu'AutoSwitch ou le jeu montrent
--   déjà (ex. Enhanced Vehicle : blocs « Usure | Peinture » et « Carburant »).
--   AutoSwitch les coupe en jeu, sans toucher aux fichiers ni aux réglages
--   enregistrés de ces mods. Réglage « Masquer les affichages en double »
--   (Oui par défaut) ; sur Non, les valeurs du mod reviennent.
--   Pour ajouter un cas : une ligne dans AS_HudDedup.LIST.
--     mod      nom du mod (dossier / zip)
--     global   table du mod (lue avec AS.modGlobal)
--     path     chemin vers la table qui contient les réglages, depuis global
--     keys     { clé = valeur imposée }
-------------------------------------------------------------------------------
AS_HudDedup = {}
AS_HudDedup.ENABLED = true
AS_HudDedup.LIST = {
    { mod = "FS25_EnhancedVehicle", global = "FS25_EnhancedVehicle", path = { "hud", "dmg" },  keys = { enabled = false } },
    { mod = "FS25_EnhancedVehicle", global = "FS25_EnhancedVehicle", path = { "hud", "fuel" }, keys = { enabled = false } },
}
AS_HudDedup.saved = {}   -- [entrée] = { tbl = table modifiée, values = valeurs d'origine }
AS_HudDedup.logged = {}

local function findTable(entry)
    if g_modIsLoaded ~= nil and g_modIsLoaded[entry.mod] ~= true then return nil end
    local t = AS.modGlobal(entry.mod, entry.global)
    -- Enhanced Vehicle : la classe est rangée dans une table du même nom
    if type(t) == "table" and type(t[entry.global]) == "table" and t.hud == nil then
        t = t[entry.global]
    end
    for _, k in ipairs(entry.path) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) ~= "table" then return nil end
    return t
end

-- Le mod peut recréer ses tables (menu de réglages rechargé) : contrôle régulier.
-- (v1.0.0.83) toutes les 0,5 s au lieu de chaque image
AS_HudDedup.CHECK_MS = 500
AS_HudDedup.timer = 0
function AS_HudDedup:update(dt)
    self.timer = self.timer + (dt or 0)
    if self.timer < self.CHECK_MS then return end
    self.timer = 0
    for i, entry in ipairs(self.LIST) do
        local tbl = findTable(entry)
        local s = self.saved[i]
        if tbl ~= nil then
            if self.ENABLED then
                if s == nil or s.tbl ~= tbl then
                    s = { tbl = tbl, values = {} }
                    for k, _ in pairs(entry.keys) do s.values[k] = tbl[k] end
                    self.saved[i] = s
                    if not self.logged[i] then
                        self.logged[i] = true
                        print(string.format("[AutoSwitch] affichage en double masqué : %s %s", entry.mod, table.concat(entry.path, ".")))
                    end
                end
                for k, v in pairs(entry.keys) do
                    if tbl[k] ~= v then tbl[k] = v end
                end
            elseif s ~= nil then
                if s.tbl == tbl then
                    for k, v in pairs(s.values) do tbl[k] = v end
                end
                self.saved[i] = nil
            end
        end
    end
end

function AS_HudDedup:setEnabled(on)
    self.ENABLED = on == true
end

addModEventListener(AS_HudDedup)
