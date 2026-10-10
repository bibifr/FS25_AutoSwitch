-- AutoSwitch : menu Dormir (avancer de X heures ou de X jours)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local L = AS.L

-------------------------------------------------------------------------------
-- v1.0.0.32 : la fenêtre Dormir du jeu propose une heure de réveil (00:00 à
--   23:30), donc 24 h de sommeil au plus. Sa liste est remplacée par :
--     +1 h ... +23 h, puis 1 jour ... 7 jours.
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
AS_SleepPlus.DEFAULT   = 8        -- choix proposé à l'ouverture : +8 h
AS_SleepPlus.DAY_MS    = 24 * 60 * 60 * 1000

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

-- Durées et textes de la liste
local function buildChoices()
    local durations, texts = {}, {}
    local hourFmt = L("vtpas_sleepHours")
    if hourFmt == "vtpas_sleepHours" then hourFmt = "+%d h" end
    for h = 1, AS_SleepPlus.MAX_HOURS do
        durations[#durations + 1] = h * 3600000
        texts[#texts + 1] = string.format(hourFmt, h)
    end
    for d = 1, AS_SleepPlus.MAX_DAYS do
        local key = d == 1 and "vtpas_sleepDay" or "vtpas_sleepDays"
        local f = L(key)
        if f == key then f = d == 1 and "%d jour" or "%d jours" end
        durations[#durations + 1] = d * AS_SleepPlus.DAY_MS
        texts[#texts + 1] = string.format(f, d)
    end
    return durations, texts
end

function AS_SleepPlus:onDialogOpen(dlg)
    local el = dlg.targetTimeElement
    if el == nil or el.setTexts == nil then
        print(TAG .. "liste de la fenêtre Dormir introuvable : fenêtre d'origine gardée")
        return
    end
    self.choiceMs = nil
    self.durations, self.texts = buildChoices()
    el:setTexts(self.texts)
    el:setState(self.DEFAULT, true)
    self.listApplied = true
end

function AS_SleepPlus:onDialogClose(dlg)
    if not self.listApplied then return end
    self.listApplied = false
    local el = dlg.targetTimeElement
    local state = el ~= nil and el.getState ~= nil and el:getState() or nil
    self.choiceMs = state ~= nil and self.durations[state] or nil
    self.choiceText = state ~= nil and self.texts[state] or "?"
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
    print(string.format("%sdébut du sommeil : %s (réveil du jeu %s remplacé)", TAG, self.choiceText, tostring(self.gameWakeUpTime)))
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
    local env = g_currentMission.environment
    print(string.format("%sréveil : jour %s, %.2f h", TAG, tostring(env.currentDay), (env.dayTime or 0) / 3600000))
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
