-- AutoSwitch : menu Dormir (avancer de X heures ou de X jours)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local L = AS.L

-------------------------------------------------------------------------------
-- v1.0.0.32 : la fenêtre Dormir du jeu propose une heure de réveil (00:00 à
--   23:30), donc 24 h de sommeil au plus. Sa liste est remplacée par :
--     +1 h ... +23 h, puis 1 jour ... 7 jours.
-- v1.0.0.33 : deux listes avec un titre chacune (« Temps en heures » /
--   « Temps en jours »), fenêtre agrandie, +0 h et +1 jour par défaut, Heures (+0 à +23 h) et Jours (0 à 7, copie de la
--   liste du jeu posée dessous). Durée = jours + heures (0 + 0 = 1 h).
--   Relevés dans log.txt (10/10/2026) :
--     - g_gui.guis.SleepDialog.target.targetTimeElement = la liste (48 choix) ;
--     - pendant le sommeil g_sleepManager.isSleeping = true, le temps passe à
--       ×5000, et le jeu réveille quand son compteur atteint wakeUpTime ;
--     - les jours passent normalement (currentMonotonicDay +1 à minuit), donc
--       cultures, ventes et salaires se calculent comme d'habitude.
--   Ici, au début du sommeil, wakeUpTime est mis hors d'atteinte et AutoSwitch
--   réveille lui-même (stopSleep) quand la durée choisie est écoulée.
-------------------------------------------------------------------------------
AS_SleepPlus = {}
AS_SleepPlus.MAX_HOURS = 23
AS_SleepPlus.MAX_DAYS  = 7
AS_SleepPlus.DEFAULT_HOURS = 0    -- choix proposés à l'ouverture (Fabien) : +0 h et +1 jour
AS_SleepPlus.DEFAULT_DAYS  = 1
AS_SleepPlus.DAY_MS    = 24 * 60 * 60 * 1000
-- Mise en page (hauteur d'écran, depuis le bas du contenu) : titre Heures,
-- curseur Heures, titre Jours, curseur Jours ; fenêtre agrandie de EXTRA_H
AS_SleepPlus.EXTRA_H     = 0.08
AS_SleepPlus.DAYS_Y      = 0.037   -- curseur Jours = place d'origine du curseur du jeu
AS_SleepPlus.LABEL_DY    = 0.050   -- titre au-dessus de son curseur (0.032 le chevauchait)
AS_SleepPlus.BLOCK_DY    = 0.075   -- curseur Heures au-dessus du curseur Jours
AS_SleepPlus.LABEL_H     = 0.022

AS_SleepPlus.wasOpen      = false
AS_SleepPlus.wasSleeping  = false
AS_SleepPlus.choiceMs     = nil   -- durée choisie dans la fenêtre
AS_SleepPlus.targetAbsMs  = nil   -- fin du sommeil (jour * 24 h + heure, en ms)

local TAG = "[AutoSwitch SleepPlus] "

local function getDialog()
    local gui = g_gui ~= nil and g_gui.guis ~= nil and g_gui.guis.SleepDialog or nil
    return gui ~= nil and (gui.target or gui) or nil
end

-- Temps de jeu absolu : jours écoulés depuis le début de la partie + heure du jour
local function nowAbsMs()
    local env = g_currentMission.environment
    return (env.currentMonotonicDay or 0) * AS_SleepPlus.DAY_MS + (env.dayTime or 0)
end

-- Textes des deux listes : heures 0 à 23, jours 0 à 7
local function fmtText(key, fallback, n)
    local f = L(key)
    if f == key then f = fallback end
    return string.format(f, n)
end

local function buildTexts()
    local hours, days = {}, {}
    for h = 0, AS_SleepPlus.MAX_HOURS do
        hours[#hours + 1] = fmtText("vtpas_sleepHours", "+%d h", h)
    end
    for d = 0, AS_SleepPlus.MAX_DAYS do
        days[#days + 1] = d <= 1 and fmtText("vtpas_sleepDay", "+%d jour", d) or fmtText("vtpas_sleepDays", "+%d jours", d)
    end
    return hours, days
end

-- 2e liste (Jours) : copie de la liste du jeu, posée sous elle (une seule fois)
function AS_SleepPlus:createDaysList(dlg, el)
    if self.daysEl ~= nil or self.cloneFailed then return end
    local parent = el.parent
    local ok, clone = pcall(el.clone, el, parent, false, true)
    if not ok or clone == nil then
        self.cloneFailed = true
        print(TAG .. "copie de la liste impossible (" .. tostring(clone) .. ")")
        return
    end
    clone.id = "asSleepDaysElement"
    clone.onClickCallback = nil   -- ne doit pas toucher l'heure de réveil du jeu
    clone.target = nil
    -- v1.0.0.33 : la copie posée sous la liste débordait sur les boutons (capture
    -- de Fabien) ; il voulait aussi un titre au-dessus de chaque curseur.
    -- Deux titres copiés du texte de la fenêtre, puis tout est replacé.
    local x = el.position ~= nil and el.position[1] or 0
    local daysY = self.DAYS_Y
    local hoursY = daysY + self.BLOCK_DY
    clone:setPosition(x, daysY)
    el:setPosition(x, hoursY)
    local src = dlg.dialogTextElement
    if src ~= nil and src.clone ~= nil then
        local function makeLabel(key, fallback, y)
            local okL, lab = pcall(src.clone, src, parent, false, true)
            if not okL or lab == nil then return nil end
            lab.id = nil
            local t = L(key)
            if t == key then t = fallback end
            if lab.setSize ~= nil and src.size ~= nil then lab:setSize(src.size[1], self.LABEL_H) end
            -- texte du jeu accroché en haut du contenu : y compté depuis le haut
            local yy = y + self.LABEL_DY
            local an = src.anchors
            if an ~= nil and (an[3] or 0) >= 0.99 and parent ~= nil and parent.size ~= nil then
                yy = yy - parent.size[2]
            end
            lab:setPosition(src.position ~= nil and src.position[1] or 0, yy)
            lab:setText(t)
            return lab
        end
        self.hoursLabel = makeLabel("vtpas_sleepHoursTitle", "Temps en heures", hoursY)
        self.daysLabel  = makeLabel("vtpas_sleepDaysTitle", "Temps en jours", daysY)
    end
    self.daysEl = clone
end

-- Agrandit la fenêtre et son contenu (le jeu peut recalculer la hauteur à chaque ouverture)
function AS_SleepPlus:growDialog(dlg, content)
    for _, e in ipairs({ dlg.dialogElement, content }) do
        if e ~= nil and e.size ~= nil and e.setSize ~= nil and e.size[2] ~= e.__asGrownH then
            e:setSize(e.size[1], e.size[2] + self.EXTRA_H)
            e.__asGrownH = e.size[2]
        end
    end
end

function AS_SleepPlus:onDialogOpen(dlg)
    local el = dlg.targetTimeElement
    if el == nil or el.setTexts == nil then
        print(TAG .. "liste de la fenêtre Dormir introuvable : fenêtre d'origine gardée")
        return
    end
    self.choiceMs = nil
    self:growDialog(dlg, el.parent)
    self:createDaysList(dlg, el)
    local hours, days = buildTexts()
    self.hourTexts, self.dayTexts = hours, days
    el:setTexts(hours)
    el:setState(self.DEFAULT_HOURS + 1, true)
    if self.daysEl ~= nil then
        self.daysEl:setTexts(days)
        self.daysEl:setState(self.DEFAULT_DAYS + 1)
        if self.daysEl.setVisible ~= nil then self.daysEl:setVisible(true) end
    end
    -- texte : « combien de temps dormir », la ligne « Heure actuelle » du jeu est gardée
    local txt = dlg.dialogTextElement
    if txt ~= nil and txt.setText ~= nil and txt.text ~= nil then
        local key = "vtpas_sleepText"
        local head = L(key)
        if head == key then head = "Choisissez combien de temps dormir : heures et jours." end
        local rest = tostring(txt.text):match("\n(.*)$")
        txt:setText(rest ~= nil and (head .. "\n" .. rest) or head)
    end
    self.listApplied = true
end

function AS_SleepPlus:onDialogClose(dlg)
    if not self.listApplied then return end
    self.listApplied = false
    local el = dlg.targetTimeElement
    local h = (el ~= nil and el.getState ~= nil and el:getState() or 1) - 1
    local d = (self.daysEl ~= nil and self.daysEl:getState() or 1) - 1
    if h + d == 0 then h = 1 end                 -- 0 h et 0 jour : 1 h
    self.choiceMs = d * self.DAY_MS + h * 3600000
    self.choiceText = string.format("%d jour(s) + %d h", d, h)
    self.choiceAt = nowAbsMs()
    -- remettre la liste d'origine (heures de réveil) pour le jeu
    if el ~= nil and type(dlg.targetTimes) == "table" then
        el:setTexts(dlg.targetTimes)
    end
end

function AS_SleepPlus:onSleepStart()
    if self.choiceMs == nil then return end
    self.targetAbsMs = (self.choiceAt or nowAbsMs()) + self.choiceMs
    self.gameWakeUpTime = g_sleepManager.wakeUpTime
    g_sleepManager.wakeUpTime = 1e15  -- hors d'atteinte (nombre fini, au cas où le jeu calcule avec)
    self.choiceMs = nil
end

function AS_SleepPlus:wakeUp()
    self.targetAbsMs = nil
    local ok, err = pcall(g_sleepManager.stopSleep, g_sleepManager)
    if not ok then
        -- secours : laisser le jeu réveiller lui-même
        print(TAG .. "stopSleep a échoué (" .. tostring(err) .. "), réveil rendu au jeu")
        g_sleepManager.wakeUpTime = 0
    end
end

function AS_SleepPlus:update(dt)
    if g_currentMission == nil or g_sleepManager == nil or g_currentMission.environment == nil then return end
    if g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer() then return end

    local dlg = getDialog()
    local open = dlg ~= nil and dlg.isOpen == true
    if open ~= self.wasOpen then
        self.wasOpen = open
        if open then self:onDialogOpen(dlg) else self:onDialogClose(dlg) end
    end

    local sleeping = g_sleepManager.isSleeping == true
    if sleeping ~= self.wasSleeping then
        self.wasSleeping = sleeping
        if sleeping then
            self:onSleepStart()
        else
            self.targetAbsMs = nil
        end
    end

    if sleeping and self.targetAbsMs ~= nil and nowAbsMs() >= self.targetAbsMs then
        self:wakeUp()
    end
end

addModEventListener(AS_SleepPlus)
