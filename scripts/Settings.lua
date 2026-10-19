-- AutoSwitch : menu Paramètres et sauvegarde des réglages
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.5 : réglages dans le menu Paramètres du jeu (Paramètres > Général,
--        section "AutoSwitch") + sauvegarde :
--   - seuil de patinage pour le blocage des différentiels
--   - notifications des différentiels (Activé / Désactivé)
--   - notifications des pneus : gonflage / dégonflage (Activé / Désactivé)
-- Repli si le menu n'apparaît pas : commande console  vtpSlip <pourcentage>
-- (0 = verrouillage automatique désactivé).
-- Les réglages agissent sur la machine qui exécute la logique (solo ou hôte).
-------------------------------------------------------------------------------
AS_Settings = {}
AS_Settings.MOD_DIR_NAME = g_currentModName or "FS25_AutoSwitch"   -- = nom du dossier / zip du mod
AS_Settings.VALUES = { 0, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80 }  -- 0 = désactivé
AS_Settings.slip        = 15     -- (v1.0.0.21) seuil du diff ARRIÈRE
AS_Settings.slipFront   = 30     -- (v1.0.0.21) seuil du diff AVANT
AS_Settings.notifyDiff  = true
AS_Settings.notifyTires = true
AS_Settings.driveManual = false  -- (v1.0.0.50) différentiels et 4x2 / 4x4 : true = MANUEL, false = AUTO (touche Ctrl droit + Flèche haut)
AS_Settings.autoOnHelper = true  -- (v1.0.0.50) AutoDrive / Courseplay qui prend la main repasse en AUTO
AS_Settings.tiresUserAuto = false -- pneus, conduite manuelle : true = automatique, false = manuel
AS_Settings.built   = false
AS_Settings.options = {}
AS_Settings.alertPercent = 80    -- alerte rouge : seuil de patinage (0 = désactivée)
AS_Settings.alertSeconds = 5     -- alerte rouge : durée en secondes
AS_Settings.ALERT_PERCENTS = { 0, 30, 40, 50, 60, 70, 80, 90 }
AS_Settings.ALERT_SECONDS_LIST = { 1, 2, 3, 5, 8, 10, 15, 20, 30 }
AS_Settings.diffDelay = 1.5      -- différentiels : durée de patinage avant verrouillage (secondes)
AS_Settings.DIFF_DELAY_LIST = {}  -- 1.0 à 10.0 par pas de 0.5
for i = 2, 20 do
    table.insert(AS_Settings.DIFF_DELAY_LIST, i / 2)
end
AS_Settings.tireDelay = 4          -- pneus : délai minimum entre deux changements (secondes, 0 = aucun)
AS_Settings.TIRE_DELAY_LIST = { 0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30 }
AS_Settings.speedHint = true        -- affichage de la vitesse conseillée au-dessus du compteur
AS_Settings.adFieldKph = 20        -- vitesse AutoDrive au champ (km/h)
AS_Settings.adPathKph = 30         -- vitesse AutoDrive sur les chemins (km/h)
AS_Settings.adRoadKph = 0          -- vitesse AutoDrive sur la route (km/h, 0 = sans limite)
AS_Settings.AD_FIELD_LIST = { 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 }
AS_Settings.AD_PATH_LIST = { 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50 }
AS_Settings.AD_ROAD_LIST = { 0, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80 }
AS_Settings.durTires = 4   -- durée d'affichage des notifications (secondes)
AS_Settings.durDiffs = 4
AS_Settings.durAlert = 5
AS_Settings.DURATION_LIST = { 2, 3, 4, 5, 6, 8, 10, 15, 20 }
AS_Settings.protectSeed = true   -- protection du semis (Mud System Physics)
AS_Settings.slipIcon = true      -- icône de patinage permanente
AS_Settings.seedCoverFill = true  -- remplir le semoir couvercle fermé
AS_Settings.wetGrip = 3   -- (v1.0.0.21) adhérence sol humide : 1 Débutant, 2 Facile, 3 Normal, 4 Dur, 5 Extrême
AS_Settings.WETGRIP_LEVELS = { 0.45, 0.60, 0.75, 0.90, 1.05 }   -- Normal = ancienne « Très forte »
AS_Settings.WETGRIP_FROM_OLD = { 1, 1, 1, 2, 3 }   -- ancien réglage (désactivé, faible, moyenne, forte, très forte)
AS_Settings.auto4wd = true     -- 4x4 champ / 4x2 route
AS_Settings.hintPosX = nil          -- position déplacée à la souris (nil = par défaut)
AS_Settings.hintPosY = nil
AS_Settings.iconPosX = nil          -- (v1.0.0.36) position du tracteur (nil = par défaut)
AS_Settings.iconPosY = nil
AS_Settings.beamRange = 2          -- (v1.0.0.75) portée des vrais faisceaux (x1 = jeu de base)
AS_Settings.beamGlow = 2           -- (v1.0.0.75) luminosité de la zone éclairée (x1 = jeu de base)
AS_Settings.BEAM_LIST = { 1, 2, 3, 4 }
AS_Settings.beamEnabled = true     -- (v1.0.0.83) phares renforcés (Oui / Non)
AS_Settings.tracksMax = 60000      -- (v1.0.0.83) points de traces de pneus gardés
AS_Settings.TRACKS_MAX_LIST = { 10000, 20000, 30000, 40000, 60000, 80000, 100000 }
AS_Settings.windSway = 22          -- (v1.0.0.73) mouvement du feuillage au vent, en dixièmes (x2,2 ; 10 = jeu de base)
AS_Settings.WIND_SWAY_LIST = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 }
AS_Settings.hudDedup = true        -- (v1.0.0.78) affichages en double des autres mods masqués
AS_Settings.coopPay = true         -- (v1.0.0.81) coopératives payées en fin de mois
AS_Settings.noOvertake = true      -- (v1.0.0.84) les voitures du trafic ne doublent plus les tracteurs
AS_Settings.shopBlockTwins = true  -- (v1.0.0.89) roues jumelées retirées du magasin (montage par palette)
AS_Settings.weatherWidget = true   -- (v1.0.0.61) mini-météo à gauche de l'horloge
AS_Settings.weatherPosX = nil      -- position déplacée à la souris (nil = par défaut)
AS_Settings.weatherPosY = nil
AS_Settings.overdraftPercent = 20  -- (v1.0.0.67) découvert : plafond en % de la valeur de revente des biens (0 = jeu de base)
AS_Settings.OVERDRAFT_PERCENT_LIST = { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
AS_Settings.overdraftRate = 10     -- (v1.0.0.67) agios : taux annuel en %
AS_Settings.OVERDRAFT_RATE_LIST = { 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 }

local function sprint(fmt, ...)
    -- (v1.25) seules les erreurs sont écrites dans le journal
    local msg = string.format(fmt, ...)
    if AS_VERBOSE or msg:find("ERREUR", 1, true) or msg:find("échec", 1, true) then
        print("[AS_Settings] " .. msg)
    end
end

local function getSettingsDir()
    return getUserProfileAppPath() .. "modSettings/" .. AS_Settings.MOD_DIR_NAME .. "/"
end

function AS_Settings:save()
    local ok, err = pcall(function()
        createFolder(getUserProfileAppPath() .. "modSettings/")
        createFolder(getSettingsDir())
        local xml = createXMLFile("vtpAutoSwitchSettings", getSettingsDir() .. "settings.xml", "vtpAutoSwitch")
        if xml ~= nil and xml ~= 0 then
            setXMLInt(xml, "vtpAutoSwitch.diffLock#rearPercent", self.slip)
            setXMLInt(xml, "vtpAutoSwitch.diffLock#frontPercent", self.slipFront)
            setXMLBool(xml, "vtpAutoSwitch.notifications#diffs", self.notifyDiff)
            setXMLBool(xml, "vtpAutoSwitch.notifications#tires", self.notifyTires)
            setXMLBool(xml, "vtpAutoSwitch.diffMode#manual", self.driveManual)
            setXMLBool(xml, "vtpAutoSwitch.diffMode#autoOnHelper", self.autoOnHelper)
            setXMLBool(xml, "vtpAutoSwitch.tireMode#userAuto", self.tiresUserAuto)
            setXMLInt(xml, "vtpAutoSwitch.slipAlert#percent", self.alertPercent)
            setXMLInt(xml, "vtpAutoSwitch.slipAlert#seconds", self.alertSeconds)
            setXMLFloat(xml, "vtpAutoSwitch.diffLock#delaySeconds", self.diffDelay)
            setXMLInt(xml, "vtpAutoSwitch.tireMode#delaySeconds", self.tireDelay)
            setXMLInt(xml, "vtpAutoSwitch.adSpeed#fieldKph", self.adFieldKph)
            setXMLInt(xml, "vtpAutoSwitch.adSpeed#pathKph", self.adPathKph)
            setXMLInt(xml, "vtpAutoSwitch.adSpeed#roadKph", self.adRoadKph)
            setXMLBool(xml, "vtpAutoSwitch.speedHint#enabled", self.speedHint)
            setXMLInt(xml, "vtpAutoSwitch.notifDuration#tires", self.durTires)
            setXMLBool(xml, "vtpAutoSwitch.seedProtect#enabled", self.protectSeed)
            setXMLBool(xml, "vtpAutoSwitch.slipIcon#enabled", self.slipIcon)
            setXMLInt(xml, "vtpAutoSwitch.wetGrip#difficulty", self.wetGrip)
            setXMLBool(xml, "vtpAutoSwitch.drive#auto4wd", self.auto4wd)
            setXMLBool(xml, "vtpAutoSwitch.seedCoverFill#enabled", self.seedCoverFill)
            setXMLInt(xml, "vtpAutoSwitch.notifDuration#diffs", self.durDiffs)
            setXMLInt(xml, "vtpAutoSwitch.notifDuration#alert", self.durAlert)
            setXMLInt(xml, "vtpAutoSwitch.lightRange#beamRange", self.beamRange)
            setXMLInt(xml, "vtpAutoSwitch.lightRange#beamGlow", self.beamGlow)
            setXMLBool(xml, "vtpAutoSwitch.lightRange#enabled", self.beamEnabled)
            setXMLInt(xml, "vtpAutoSwitch.tireTracks#maxPoints", self.tracksMax)
            setXMLInt(xml, "vtpAutoSwitch.windSway#factor10", self.windSway)
            setXMLBool(xml, "vtpAutoSwitch.weatherWidget#enabled", self.weatherWidget)
            setXMLBool(xml, "vtpAutoSwitch.hudDedup#enabled", self.hudDedup)
            setXMLBool(xml, "vtpAutoSwitch.coopPay#enabled", self.coopPay)
            setXMLBool(xml, "vtpAutoSwitch.noOvertake#enabled", self.noOvertake)
            setXMLBool(xml, "vtpAutoSwitch.shopTwins#blocked", self.shopBlockTwins)
            setXMLInt(xml, "vtpAutoSwitch.overdraft#percent", self.overdraftPercent)
            setXMLInt(xml, "vtpAutoSwitch.overdraft#rate", self.overdraftRate)
            if self.weatherPosX ~= nil and self.weatherPosY ~= nil then
                setXMLFloat(xml, "vtpAutoSwitch.weatherWidget#x", self.weatherPosX)
                setXMLFloat(xml, "vtpAutoSwitch.weatherWidget#y", self.weatherPosY)
            end
            if self.hintPosX ~= nil and self.hintPosY ~= nil then
                setXMLFloat(xml, "vtpAutoSwitch.speedHint#posX", self.hintPosX)
                setXMLFloat(xml, "vtpAutoSwitch.speedHint#posY", self.hintPosY)
            end
            if self.iconPosX ~= nil and self.iconPosY ~= nil then
                setXMLFloat(xml, "vtpAutoSwitch.slipIcon#posX", self.iconPosX)
                setXMLFloat(xml, "vtpAutoSwitch.slipIcon#posY", self.iconPosY)
            end
            saveXMLFile(xml)
            delete(xml)
        end
    end)
    if not ok then sprint("échec de la sauvegarde : %s", tostring(err)) end
end

function AS_Settings:load()
    local ok, err = pcall(function()
        local path = getSettingsDir() .. "settings.xml"
        if fileExists(path) then
            local xml = loadXMLFile("vtpAutoSwitchSettings", path)
            if xml ~= nil and xml ~= 0 then
                -- (v1.0.0.21) seuils séparés ; l'ancien seuil commun (slip#percent) est abandonné
                local v = getXMLInt(xml, "vtpAutoSwitch.diffLock#rearPercent")
                if v ~= nil then self.slip = math.max(0, math.min(100, v)) end
                local vf = getXMLInt(xml, "vtpAutoSwitch.diffLock#frontPercent")
                if vf ~= nil then self.slipFront = math.max(0, math.min(100, vf)) end
                local nd = getXMLBool(xml, "vtpAutoSwitch.notifications#diffs")
                if nd ~= nil then self.notifyDiff = nd end
                local nt = getXMLBool(xml, "vtpAutoSwitch.notifications#tires")
                if nt ~= nil then self.notifyTires = nt end
                local dm = getXMLBool(xml, "vtpAutoSwitch.diffMode#manual")
                if dm ~= nil then self.driveManual = dm end
                local ah = getXMLBool(xml, "vtpAutoSwitch.diffMode#autoOnHelper")
                if ah ~= nil then self.autoOnHelper = ah end
                local tu = getXMLBool(xml, "vtpAutoSwitch.tireMode#userAuto")
                if tu ~= nil then self.tiresUserAuto = tu end
                local ap = getXMLInt(xml, "vtpAutoSwitch.slipAlert#percent")
                if ap ~= nil then self.alertPercent = math.max(0, math.min(100, ap)) end
                local as = getXMLInt(xml, "vtpAutoSwitch.slipAlert#seconds")
                if as ~= nil then self.alertSeconds = math.max(1, math.min(120, as)) end
                local dd = getXMLFloat(xml, "vtpAutoSwitch.diffLock#delaySeconds")
                if dd ~= nil then self.diffDelay = math.max(1, math.min(10, dd)) end
                local td = getXMLInt(xml, "vtpAutoSwitch.tireMode#delaySeconds")
                if td ~= nil then self.tireDelay = math.max(0, math.min(60, td)) end
                local af = getXMLInt(xml, "vtpAutoSwitch.adSpeed#fieldKph")
                if af ~= nil then self.adFieldKph = math.max(4, math.min(30, af)) end
                local ap2 = getXMLInt(xml, "vtpAutoSwitch.adSpeed#pathKph")
                if ap2 ~= nil then self.adPathKph = math.max(10, math.min(50, ap2)) end
                local ar = getXMLInt(xml, "vtpAutoSwitch.adSpeed#roadKph")
                if ar ~= nil then self.adRoadKph = math.max(0, math.min(80, ar)) end
                local sh = getXMLBool(xml, "vtpAutoSwitch.speedHint#enabled")
                if sh ~= nil then self.speedHint = sh end
                local scf = getXMLBool(xml, "vtpAutoSwitch.seedCoverFill#enabled")
                if scf ~= nil then self.seedCoverFill = scf end
                local a4 = getXMLBool(xml, "vtpAutoSwitch.drive#auto4wd")
                if a4 ~= nil then self.auto4wd = a4 end
                local wg = getXMLInt(xml, "vtpAutoSwitch.wetGrip#difficulty")
                if wg ~= nil then
                    self.wetGrip = math.max(1, math.min(5, wg))
                else
                    -- (v1.0.0.21) ancien réglage : même perte, nouveau nom (Très forte -> Normal)
                    local old = getXMLInt(xml, "vtpAutoSwitch.wetGrip#level")
                    if old ~= nil then self.wetGrip = self.WETGRIP_FROM_OLD[math.max(1, math.min(5, old))] end
                end
                local si = getXMLBool(xml, "vtpAutoSwitch.slipIcon#enabled")
                if si ~= nil then self.slipIcon = si end
                local ps = getXMLBool(xml, "vtpAutoSwitch.seedProtect#enabled")
                if ps ~= nil then self.protectSeed = ps end
                local d1 = getXMLInt(xml, "vtpAutoSwitch.notifDuration#tires")
                if d1 ~= nil then self.durTires = math.max(1, math.min(60, d1)) end
                local d2 = getXMLInt(xml, "vtpAutoSwitch.notifDuration#diffs")
                if d2 ~= nil then self.durDiffs = math.max(1, math.min(60, d2)) end
                local d3 = getXMLInt(xml, "vtpAutoSwitch.notifDuration#alert")
                if d3 ~= nil then self.durAlert = math.max(1, math.min(60, d3)) end
                local br = getXMLInt(xml, "vtpAutoSwitch.lightRange#beamRange")
                if br ~= nil then self.beamRange = math.max(1, math.min(4, br)) end
                local bg = getXMLInt(xml, "vtpAutoSwitch.lightRange#beamGlow")
                if bg ~= nil then self.beamGlow = math.max(1, math.min(4, bg)) end
                local be = getXMLBool(xml, "vtpAutoSwitch.lightRange#enabled")
                if be ~= nil then self.beamEnabled = be end
                local tm = getXMLInt(xml, "vtpAutoSwitch.tireTracks#maxPoints")
                if tm ~= nil then self.tracksMax = math.max(10000, math.min(100000, tm)) end
                local hd = getXMLBool(xml, "vtpAutoSwitch.hudDedup#enabled")
                if hd ~= nil then self.hudDedup = hd end
                local cp = getXMLBool(xml, "vtpAutoSwitch.coopPay#enabled")
                if cp ~= nil then self.coopPay = cp end
                local no = getXMLBool(xml, "vtpAutoSwitch.noOvertake#enabled")
                if no ~= nil then self.noOvertake = no end
                local sb = getXMLBool(xml, "vtpAutoSwitch.shopTwins#blocked")
                if sb ~= nil then self.shopBlockTwins = sb end
                local ws = getXMLInt(xml, "vtpAutoSwitch.windSway#factor10")
                if ws ~= nil then self.windSway = math.max(10, math.min(30, ws)) end
                local hx = getXMLFloat(xml, "vtpAutoSwitch.speedHint#posX")
                local hy = getXMLFloat(xml, "vtpAutoSwitch.speedHint#posY")
                if hx ~= nil and hy ~= nil then
                    self.hintPosX, self.hintPosY = math.max(0, math.min(1, hx)), math.max(0, math.min(1, hy))
                end
                local odp = getXMLInt(xml, "vtpAutoSwitch.overdraft#percent")
                if odp ~= nil then self.overdraftPercent = math.max(0, math.min(100, odp)) end
                local odr = getXMLInt(xml, "vtpAutoSwitch.overdraft#rate")
                if odr ~= nil then self.overdraftRate = math.max(0, math.min(20, odr)) end
                local ww = getXMLBool(xml, "vtpAutoSwitch.weatherWidget#enabled")
                if ww ~= nil then self.weatherWidget = ww end
                local wx = getXMLFloat(xml, "vtpAutoSwitch.weatherWidget#x")
                local wy = getXMLFloat(xml, "vtpAutoSwitch.weatherWidget#y")
                if wx ~= nil and wy ~= nil then
                    self.weatherPosX, self.weatherPosY = math.max(0, math.min(1, wx)), math.max(0, math.min(1, wy))
                end
                local ix = getXMLFloat(xml, "vtpAutoSwitch.slipIcon#posX")
                local iy = getXMLFloat(xml, "vtpAutoSwitch.slipIcon#posY")
                if ix ~= nil and iy ~= nil then
                    self.iconPosX, self.iconPosY = math.max(0, math.min(1, ix)), math.max(0, math.min(1, iy))
                end
                delete(xml)
            end
        end
    end)
    if not ok then sprint("échec du chargement : %s", tostring(err)) end
end

-- Applique les réglages aux modules pneus et différentiels.
function AS_Settings:apply()
    -- (v1.0.0.21) un seuil par différentiel, déblocage à la moitié du seuil ; 0 = jamais
    local v, vf = self.slip, self.slipFront
    AS_Diff.ENABLED = v > 0 or vf > 0
    AS_Diff.SLIP_ON_PERCENT  = v
    AS_Diff.SLIP_OFF_PERCENT = math.max(3, v * 0.5)
    AS_Diff.SLIP_ON_FRONT    = vf
    AS_Diff.SLIP_OFF_FRONT   = math.max(3, vf * 0.5)
    AS_Diff.NOTIFY   = self.notifyDiff
    AS_Tires.NOTIFY = self.notifyTires
    AS_Diff.MANUAL = self.driveManual
    AS_Diff.AUTO_ON_HELPER = self.autoOnHelper
    AS_Tires.USER_AUTO = self.tiresUserAuto
    AS_SlipAlert.ENABLED       = self.alertPercent > 0
    AS_SlipAlert.ALERT_PERCENT = self.alertPercent
    AS_SlipAlert.ALERT_SECONDS = self.alertSeconds
    AS_Diff.SLIP_ON_MS     = math.floor(self.diffDelay * 1000)
    AS_Tires.MIN_SWITCH_MS = math.floor(self.tireDelay * 1000)
    AS_AdSpeed.FIELD_KPH   = self.adFieldKph
    AS_AdSpeed.PATH_KPH    = self.adPathKph
    AS_AdSpeed.ROAD_KPH    = self.adRoadKph
    AS_SpeedHint.ENABLED   = self.speedHint
    AS_NotifyDuration.tires = self.durTires * 1000
    AS_SeedProtect.ENABLED = self.protectSeed
    AS_SpeedHint.SLIP_ICON = self.slipIcon
    AS_WetGrip.LEVEL = self.WETGRIP_LEVELS[self.wetGrip] or 0.75
    AS_Diff.AUTO_4WD = self.auto4wd
    AS_Diff.TURN_UNLOCK = true   -- (v1.0.0.25) toujours actif, ligne retirée du menu
    if AS_SeedCoverFill.ENABLED ~= self.seedCoverFill then AS_SeedCoverFill:setEnabled(self.seedCoverFill) end
    AS_NotifyDuration.diffs = self.durDiffs * 1000
    AS_NotifyDuration.alert = self.durAlert * 1000
    AS_SpeedHint.POS_X, AS_SpeedHint.POS_Y = self.hintPosX, self.hintPosY
    AS_SpeedHint.ICON_X, AS_SpeedHint.ICON_Y = self.iconPosX, self.iconPosY
    AS_LightRange:setBeams(self.beamRange, self.beamGlow)
    AS_LightRange:setEnabled(self.beamEnabled)
    if AS_TireTracksSave ~= nil then AS_TireTracksSave:setMaxPoints(self.tracksMax) end
    if AS_WindSway ~= nil then AS_WindSway:setFactor(self.windSway / 10) end
    if AS_HudDedup ~= nil then AS_HudDedup:setEnabled(self.hudDedup) end
    if AS_CoopPay ~= nil then AS_CoopPay.ENABLED = self.coopPay end
    if AS_NoOvertake ~= nil then AS_NoOvertake:setEnabled(self.noOvertake) end
    if AS_DualRack ~= nil then AS_DualRack.shopBlockTwins = self.shopBlockTwins end
    if AS_Overdraft ~= nil then
        AS_Overdraft.PERCENT = self.overdraftPercent
        AS_Overdraft.RATE = self.overdraftRate
    end
    if AS_Weather ~= nil then
        AS_Weather.WIDGET = self.weatherWidget
        AS_Weather.WIDGET_X, AS_Weather.WIDGET_Y = self.weatherPosX, self.weatherPosY
    end
end

function AS_Settings:getStateForValue(v)
    local best, bestDiff = 1, math.huge
    for i, val in ipairs(self.VALUES) do
        local d = math.abs(val - v)
        if d < bestDiff then best, bestDiff = i, d end
    end
    return best
end

-- Callbacks des options : (self = AS_Settings, state, element)
function AS_Settings:onSlipChanged(state, element)
    local v = self.VALUES[state]
    if v ~= nil then
        self.slip = v
        self:apply()
        self:save()
        sprint("seuil de patinage du diff arrière réglé sur %s", v == 0 and "désactivé" or (v .. " %"))
    end
end

function AS_Settings:onSlipFrontChanged(state, element)
    local v = self.VALUES[state]
    if v ~= nil then
        self.slipFront = v
        self:apply()
        self:save()
        sprint("seuil de patinage du diff avant réglé sur %s", v == 0 and "désactivé" or (v .. " %"))
    end
end

function AS_Settings:onDiffModeChanged(state, element)
    self.driveManual = (state == 2)
    self:apply()
    self:save()
    sprint("différentiels et transmission : %s", self.driveManual and "manuel" or "automatique")
end

-- (v1.0.0.50) bascule par la touche AUTO / MANUEL (Diff.lua)
function AS_Settings:setDriveManual(manual)
    self.driveManual = manual == true
    self:apply()
    self:save()
    local o = self.options
    if o.diffMode ~= nil then pcall(o.diffMode.setState, o.diffMode, self.driveManual and 2 or 1) end
end

function AS_Settings:onAutoOnHelperChanged(state, element)
    self.autoOnHelper = (state == 2)
    self:apply()
    self:save()
end

function AS_Settings:onTireModeChanged(state, element)
    self.tiresUserAuto = (state == 1)
    self:apply()
    self:save()
    sprint("pneus, conduite manuelle : %s", self.tiresUserAuto and "automatique" or "manuel")
end

-- Index de la valeur la plus proche dans une liste
function AS_Settings:getIndex(list, v)
    local best, bestDiff = 1, math.huge
    for i, val in ipairs(list) do
        local d = math.abs(val - v)
        if d < bestDiff then best, bestDiff = i, d end
    end
    return best
end

function AS_Settings:onAdFieldChanged(state, element)
    local v = self.AD_FIELD_LIST[state]
    if v ~= nil then
        self.adFieldKph = v
        self:apply()
        self:save()
        sprint("AutoDrive : %d km/h au champ", v)
    end
end

function AS_Settings:onAdPathChanged(state, element)
    local v = self.AD_PATH_LIST[state]
    if v ~= nil then
        self.adPathKph = v
        self:apply()
        self:save()
        sprint("AutoDrive : %d km/h sur les chemins", v)
    end
end

function AS_Settings:onAdRoadChanged(state, element)
    local v = self.AD_ROAD_LIST[state]
    if v ~= nil then
        self.adRoadKph = v
        self:apply()
        self:save()
        sprint("AutoDrive : route %s", v == 0 and "sans limite" or (v .. " km/h"))
    end
end

function AS_Settings:onTireDelayChanged(state, element)
    local v = self.TIRE_DELAY_LIST[state]
    if v ~= nil then
        self.tireDelay = v
        self:apply()
        self:save()
        sprint("pneus : délai entre deux changements %s", v == 0 and "désactivé" or (v .. " s"))
    end
end

function AS_Settings:onDiffDelayChanged(state, element)
    local v = self.DIFF_DELAY_LIST[state]
    if v ~= nil then
        self.diffDelay = v
        self:apply()
        self:save()
        sprint("différentiels : délai de patinage avant verrouillage %.1f s", v)
    end
end

function AS_Settings:onAlertPercentChanged(state, element)
    local v = self.ALERT_PERCENTS[state]
    if v ~= nil then
        self.alertPercent = v
        self:apply()
        self:save()
        sprint("alerte de patinage : seuil %s", v == 0 and "désactivé" or (v .. " %"))
    end
end

function AS_Settings:onAlertSecondsChanged(state, element)
    local v = self.ALERT_SECONDS_LIST[state]
    if v ~= nil then
        self.alertSeconds = v
        self:apply()
        self:save()
        sprint("alerte de patinage : durée %d s", v)
    end
end

function AS_Settings:onNotifyDiffChanged(state, element)
    self.notifyDiff = (state == 2)
    self:apply()
    self:save()
    sprint("notifications différentiels : %s", self.notifyDiff and "activées" or "désactivées")
end

function AS_Settings:onNotifyTiresChanged(state, element)
    self.notifyTires = (state == 2)
    self:apply()
    self:save()
    sprint("notifications pneus : %s", self.notifyTires and "activées" or "désactivées")
end

function AS_Settings:onSpeedHintChanged(state, element)
    self.speedHint = (state == 2)
    self:apply()
    self:save()
    sprint("vitesse conseillée : %s", self.speedHint and "affichée" or "masquée")
end

function AS_Settings:setDuration(field, state, what)
    local v = self.DURATION_LIST[state]
    if v ~= nil then
        self[field] = v
        self:apply()
        self:save()
        sprint("durée d'affichage %s : %d s", what, v)
    end
end
function AS_Settings:onDurTiresChanged(state, element) self:setDuration("durTires", state, "pneus") end
function AS_Settings:onDurDiffsChanged(state, element) self:setDuration("durDiffs", state, "différentiels") end
function AS_Settings:onDurAlertChanged(state, element) self:setDuration("durAlert", state, "alerte de patinage") end

function AS_Settings:onSeedCoverFillChanged(state, element)
    self.seedCoverFill = (state == 2)
    self:apply()
    self:save()
    sprint("remplissage semoir couvercle fermé : %s", self.seedCoverFill and "autorisé" or "bloqué (jeu de base)")
end

function AS_Settings:onAuto4wdChanged(state, element)
    self.auto4wd = (state == 2)
    self:apply()
    self:save()
end

function AS_Settings:onWetGripChanged(state, element)
    self.wetGrip = math.max(1, math.min(5, state))
    self:apply()
    self:save()
    sprint("adhérence sol humide : niveau %d", self.wetGrip)
end

function AS_Settings:onSlipIconChanged(state, element)
    self.slipIcon = (state == 2)
    self:apply()
    self:save()
    sprint("icône de patinage : %s", self.slipIcon and "affichée" or "masquée")
end

function AS_Settings:onWeatherWidgetChanged(state, element)
    self.weatherWidget = (state == 2)
    self:apply()
    self:save()
    sprint("mini-météo : %s", self.weatherWidget and "affichée" or "masquée")
end

function AS_Settings:onOverdraftPercentChanged(state, element)
    local v = self.OVERDRAFT_PERCENT_LIST[state]
    if v ~= nil then
        self.overdraftPercent = v
        self:apply()
        self:save()
        sprint("découvert : %d %% des biens", v)
    end
end

function AS_Settings:onOverdraftRateChanged(state, element)
    local v = self.OVERDRAFT_RATE_LIST[state]
    if v ~= nil then
        self.overdraftRate = v
        self:apply()
        self:save()
        sprint("agios : %d %% par an", v)
    end
end

function AS_Settings:onHudDedupChanged(state, element)
    self.hudDedup = (state == 2)
    self:apply()
    self:save()
    sprint("affichages en double masqués : %s", tostring(self.hudDedup))
end

function AS_Settings:onCoopPayChanged(state, element)
    self.coopPay = (state == 2)
    self:apply()
    self:save()
    sprint("coopératives payées en fin de mois : %s", tostring(self.coopPay))
end

function AS_Settings:onNoOvertakeChanged(state, element)
    self.noOvertake = (state == 2)
    self:apply()
    self:save()
    sprint("voitures sans dépassement des tracteurs : %s", tostring(self.noOvertake))
end

function AS_Settings:onShopBlockTwinsChanged(state, element)
    self.shopBlockTwins = (state == 2)
    self:apply()
    self:save()
    sprint("roues jumelées retirées du magasin : %s", tostring(self.shopBlockTwins))
end

function AS_Settings:onWindSwayChanged(state, element)
    local v = self.WIND_SWAY_LIST[state]
    if v ~= nil then
        self.windSway = v
        self:apply()
        self:save()
        sprint("mouvement du vent : x%.1f", v / 10)
    end
end

function AS_Settings:onBeamEnabledChanged(state, element)
    self.beamEnabled = (state == 2)
    self:apply()
    self:save()
    sprint("phares renforcés : %s", tostring(self.beamEnabled))
end

function AS_Settings:onTracksMaxChanged(state, element)
    local v = self.TRACKS_MAX_LIST[state]
    if v ~= nil then
        self.tracksMax = v
        self:apply()
        self:save()
        sprint("traces de pneus gardées : %d points", v)
    end
end

function AS_Settings:onBeamRangeChanged(state, element)
    local v = self.BEAM_LIST[state]
    if v ~= nil then
        self.beamRange = v
        self:apply()
        self:save()
    end
end

function AS_Settings:onBeamGlowChanged(state, element)
    local v = self.BEAM_LIST[state]
    if v ~= nil then
        self.beamGlow = v
        self:apply()
        self:save()
    end
end

function AS_Settings:onProtectSeedChanged(state, element)
    self.protectSeed = (state == 2)
    self:apply()
    self:save()
    sprint("protection du semis : %s", self.protectSeed and "activée" or "désactivée")
end

local function findFirst(el, pred)
    if el == nil or el.elements == nil then return nil end
    for _, c in ipairs(el.elements) do
        if pred(c) then return c end
        local r = findFirst(c, pred)
        if r ~= nil then return r end
    end
    return nil
end

local function isMultiText(c)
    return c.isa ~= nil and c:isa(MultiTextOptionElement)
end

local function profileContains(c, word)
    return c.profile ~= nil and string.find(string.lower(tostring(c.profile)), word, 1, true) ~= nil
end

-- Vraie option à choix multiples : on exclut les options binaires (oui/non, 2 états seulement).
local function isRealMultiText(c)
    if not isMultiText(c) then return false end
    if BinaryOptionElement ~= nil and c:isa(BinaryOptionElement) then return false end
    if profileContains(c, "binary") then return false end
    return true
end

-- Clone une ligne du menu et la configure : def = { label, tip, texts, state, callback }
function AS_Settings:addRow(layout, template, def)
    local row = template:clone(layout)
    local option = findFirst(row, isRealMultiText)
    if option == nil then
        sprint("ERREUR : option introuvable dans la ligne clonée")
        return nil
    end

    for _, c in ipairs(row.elements) do
        if c.isa ~= nil and c:isa(TextElement) then
            c:setText(def.label)
            break
        end
    end

    local tip = findFirst(row, function(c)
        return c.isa ~= nil and c:isa(TextElement) and profileContains(c, "tooltip")
    end)
    if tip ~= nil then tip:setText(def.tip) end

    option:setTexts(def.texts)
    option:setState(def.state)
    option.target = self
    option.onClickCallback = def.callback
    return option
end

function AS_Settings:buildUI(frame)
    local layout = frame.generalSettingsLayout or frame.gameSettingsLayout
    if layout == nil or layout.elements == nil then
        sprint("ERREUR : mise en page des paramètres introuvable (utilise la commande console vtpSlip)")
        return
    end

    -- Modèle : une ligne existante contenant une vraie option à choix multiples
    local template
    for _, row in ipairs(layout.elements) do
        if not isMultiText(row) and findFirst(row, isRealMultiText) ~= nil then
            template = row
            break
        end
    end
    if template == nil then
        sprint("ERREUR : aucun modèle d'option trouvé (utilise la commande console vtpSlip)")
        return
    end

    -- Modèle d'en-tête de section (facultatif)
    local headerTemplate
    for _, row in ipairs(layout.elements) do
        if row.isa ~= nil and row:isa(TextElement) and profileContains(row, "header") then
            headerTemplate = row
            break
        end
    end
    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header:setText("AutoSwitch")
    end

    local slipTexts = {}
    for i, v in ipairs(self.VALUES) do
        slipTexts[i] = (v == 0) and L("vtpas_off") or (v .. " %")
    end
    local onOff      = { L("vtpas_off"), L("vtpas_on") }
    local autoManual = { L("vtpas_auto"), L("vtpas_manual") }

    self.options.slip = self:addRow(layout, template, {
        label = L("vtpas_slip_label"),
        tip = L("vtpas_slip_tip"),
        texts = slipTexts,
        state = self:getStateForValue(self.slip),
        callback = AS_Settings.onSlipChanged,
    })
    if self.options.slip == nil then return end

    self.options.slipFront = self:addRow(layout, template, {
        label = L("vtpas_slipFront_label"),
        tip = L("vtpas_slipFront_tip"),
        texts = slipTexts,
        state = self:getStateForValue(self.slipFront),
        callback = AS_Settings.onSlipFrontChanged,
    })

    local sep = L("vtpas_decimal")
    if #sep ~= 1 then sep = "." end
    local delayTexts = {}
    for i, v in ipairs(self.DIFF_DELAY_LIST) do
        delayTexts[i] = (string.format("%.1f", v):gsub("%.", sep)) .. " s"
    end

    self.options.diffDelay = self:addRow(layout, template, {
        label = L("vtpas_diffdelay_label"),
        tip = L("vtpas_diffdelay_tip"),
        texts = delayTexts,
        state = self:getIndex(self.DIFF_DELAY_LIST, self.diffDelay),
        callback = AS_Settings.onDiffDelayChanged,
    })

    self.options.auto4wd = self:addRow(layout, template, {
        label = L("vtpas_auto4wd_label"),
        tip = L("vtpas_auto4wd_tip"),
        texts = onOff,
        state = self.auto4wd and 2 or 1,
        callback = AS_Settings.onAuto4wdChanged,
    })

    self.options.diffMode = self:addRow(layout, template, {
        label = L("vtpas_diff_label"),
        tip = L("vtpas_diff_tip"),
        texts = autoManual,
        state = self.driveManual and 2 or 1,
        callback = AS_Settings.onDiffModeChanged,
    })

    self.options.autoOnHelper = self:addRow(layout, template, {
        label = L("vtpas_autoOnHelper_label"),
        tip = L("vtpas_autoOnHelper_tip"),
        texts = onOff,
        state = self.autoOnHelper and 2 or 1,
        callback = AS_Settings.onAutoOnHelperChanged,
    })

    self.options.tireMode = self:addRow(layout, template, {
        label = L("vtpas_tire_label"),
        tip = L("vtpas_tire_tip"),
        texts = autoManual,
        state = self.tiresUserAuto and 1 or 2,
        callback = AS_Settings.onTireModeChanged,
    })

    local tireDelayTexts = {}
    for i, v in ipairs(self.TIRE_DELAY_LIST) do
        tireDelayTexts[i] = (v == 0) and L("vtpas_off") or (v .. " s")
    end

    self.options.tireDelay = self:addRow(layout, template, {
        label = L("vtpas_tiredelay_label"),
        tip = L("vtpas_tiredelay_tip"),
        texts = tireDelayTexts,
        state = self:getIndex(self.TIRE_DELAY_LIST, self.tireDelay),
        callback = AS_Settings.onTireDelayChanged,
    })

    self.options.notifyDiff = self:addRow(layout, template, {
        label = L("vtpas_notifDiff_label"),
        tip = L("vtpas_notifDiff_tip"),
        texts = onOff,
        state = self.notifyDiff and 2 or 1,
        callback = AS_Settings.onNotifyDiffChanged,
    })

    self.options.notifyTires = self:addRow(layout, template, {
        label = L("vtpas_notifTires_label"),
        tip = L("vtpas_notifTires_tip"),
        texts = onOff,
        state = self.notifyTires and 2 or 1,
        callback = AS_Settings.onNotifyTiresChanged,
    })

    local durTexts = {}
    for i, v in ipairs(self.DURATION_LIST) do
        durTexts[i] = v .. " s"
    end
    self.options.durDiffs = self:addRow(layout, template, {
        label = L("vtpas_durDiffs_label"), tip = L("vtpas_dur_tip"), texts = durTexts,
        state = self:getIndex(self.DURATION_LIST, self.durDiffs),
        callback = AS_Settings.onDurDiffsChanged,
    })
    self.options.durTires = self:addRow(layout, template, {
        label = L("vtpas_durTires_label"), tip = L("vtpas_dur_tip"), texts = durTexts,
        state = self:getIndex(self.DURATION_LIST, self.durTires),
        callback = AS_Settings.onDurTiresChanged,
    })

    local alertPctTexts, alertSecTexts = {}, {}
    for i, v in ipairs(self.ALERT_PERCENTS) do
        alertPctTexts[i] = (v == 0) and L("vtpas_off") or (v .. " %")
    end
    for i, v in ipairs(self.ALERT_SECONDS_LIST) do
        alertSecTexts[i] = v .. " s"
    end

    self.options.alertPercent = self:addRow(layout, template, {
        label = L("vtpas_alert_pct_label"),
        tip = L("vtpas_alert_pct_tip"),
        texts = alertPctTexts,
        state = self:getIndex(self.ALERT_PERCENTS, self.alertPercent),
        callback = AS_Settings.onAlertPercentChanged,
    })

    self.options.alertSeconds = self:addRow(layout, template, {
        label = L("vtpas_alert_sec_label"),
        tip = L("vtpas_alert_sec_tip"),
        texts = alertSecTexts,
        state = self:getIndex(self.ALERT_SECONDS_LIST, self.alertSeconds),
        callback = AS_Settings.onAlertSecondsChanged,
    })

    self.options.durAlert = self:addRow(layout, template, {
        label = L("vtpas_durAlert_label"), tip = L("vtpas_dur_tip"), texts = durTexts,
        state = self:getIndex(self.DURATION_LIST, self.durAlert),
        callback = AS_Settings.onDurAlertChanged,
    })

    local function kphTexts(list)
        local t = {}
        for i, v in ipairs(list) do
            t[i] = (v == 0) and L("vtpas_adNoLimit") or (v .. " km/h")
        end
        return t
    end
    self.options.adField = self:addRow(layout, template, {
        label = L("vtpas_adField_label"),
        tip = L("vtpas_adField_tip"),
        texts = kphTexts(self.AD_FIELD_LIST),
        state = self:getIndex(self.AD_FIELD_LIST, self.adFieldKph),
        callback = AS_Settings.onAdFieldChanged,
    })
    self.options.adPath = self:addRow(layout, template, {
        label = L("vtpas_adPath_label"),
        tip = L("vtpas_adPath_tip"),
        texts = kphTexts(self.AD_PATH_LIST),
        state = self:getIndex(self.AD_PATH_LIST, self.adPathKph),
        callback = AS_Settings.onAdPathChanged,
    })
    self.options.adRoad = self:addRow(layout, template, {
        label = L("vtpas_adRoad_label"),
        tip = L("vtpas_adRoad_tip"),
        texts = kphTexts(self.AD_ROAD_LIST),
        state = self:getIndex(self.AD_ROAD_LIST, self.adRoadKph),
        callback = AS_Settings.onAdRoadChanged,
    })

    self.options.speedHint = self:addRow(layout, template, {
        label = L("vtpas_hintShow_label"),
        tip = L("vtpas_hintShow_tip"),
        texts = onOff,
        state = self.speedHint and 2 or 1,
        callback = AS_Settings.onSpeedHintChanged,
    })

    self.options.slipIcon = self:addRow(layout, template, {
        label = L("vtpas_slipIcon_label"),
        tip = L("vtpas_slipIcon_tip"),
        texts = onOff,
        state = self.slipIcon and 2 or 1,
        callback = AS_Settings.onSlipIconChanged,
    })

    self.options.wetGrip = self:addRow(layout, template, {
        label = L("vtpas_wetGrip_label"),
        tip = L("vtpas_wetGrip_tip"),
        texts = { L("vtpas_wetGrip_beginner"), L("vtpas_wetGrip_easy"), L("vtpas_wetGrip_normal"), L("vtpas_wetGrip_hard"), L("vtpas_wetGrip_extreme") },
        state = self.wetGrip,
        callback = AS_Settings.onWetGripChanged,
    })

    self.options.seedCoverFill = self:addRow(layout, template, {
        label = L("vtpas_seedCoverFill_label"),
        tip = L("vtpas_seedCoverFill_tip"),
        texts = onOff,
        state = self.seedCoverFill and 2 or 1,
        callback = AS_Settings.onSeedCoverFillChanged,
    })

    self.options.protectSeed = self:addRow(layout, template, {
        label = L("vtpas_protectSeed_label"),
        tip = L("vtpas_protectSeed_tip"),
        texts = onOff,
        state = self.protectSeed and 2 or 1,
        callback = AS_Settings.onProtectSeedChanged,
    })

    local beamTexts = {}
    for i, v in ipairs(self.BEAM_LIST) do
        beamTexts[i] = (v == 1) and L("vtpas_lightRange_base") or ("x" .. v)
    end
    self.options.beamEnabled = self:addRow(layout, template, {
        label = L("vtpas_beamEnabled_label"),
        tip = L("vtpas_beamEnabled_tip"),
        texts = onOff,
        state = self.beamEnabled and 2 or 1,
        callback = AS_Settings.onBeamEnabledChanged,
    })
    self.options.beamRange = self:addRow(layout, template, {
        label = L("vtpas_beamRange_label"),
        tip = L("vtpas_beamRange_tip"),
        texts = beamTexts,
        state = self:getIndex(self.BEAM_LIST, self.beamRange),
        callback = AS_Settings.onBeamRangeChanged,
    })
    self.options.beamGlow = self:addRow(layout, template, {
        label = L("vtpas_beamGlow_label"),
        tip = L("vtpas_beamGlow_tip"),
        texts = beamTexts,
        state = self:getIndex(self.BEAM_LIST, self.beamGlow),
        callback = AS_Settings.onBeamGlowChanged,
    })
    local windTexts = {}
    for i, v in ipairs(self.WIND_SWAY_LIST) do
        windTexts[i] = (v == 10) and L("vtpas_lightRange_base") or string.format("x%.1f", v / 10)
    end
    self.options.windSway = self:addRow(layout, template, {
        label = L("vtpas_windSway_label"),
        tip = L("vtpas_windSway_tip"),
        texts = windTexts,
        state = self:getIndex(self.WIND_SWAY_LIST, self.windSway),
        callback = AS_Settings.onWindSwayChanged,
    })

    local tracksTexts = {}
    for i, v in ipairs(self.TRACKS_MAX_LIST) do
        tracksTexts[i] = string.format("%d 000", math.floor(v / 1000))
    end
    self.options.tracksMax = self:addRow(layout, template, {
        label = L("vtpas_tracksMax_label"),
        tip = L("vtpas_tracksMax_tip"),
        texts = tracksTexts,
        state = self:getIndex(self.TRACKS_MAX_LIST, self.tracksMax),
        callback = AS_Settings.onTracksMaxChanged,
    })

    self.options.weatherWidget = self:addRow(layout, template, {
        label = L("vtpas_weatherWidget_label"),
        tip = L("vtpas_weatherWidget_tip"),
        texts = onOff,
        state = self.weatherWidget and 2 or 1,
        callback = AS_Settings.onWeatherWidgetChanged,
    })

    self.options.hudDedup = self:addRow(layout, template, {
        label = L("vtpas_hudDedup_label"),
        tip = L("vtpas_hudDedup_tip"),
        texts = onOff,
        state = self.hudDedup and 2 or 1,
        callback = AS_Settings.onHudDedupChanged,
    })

    local odTexts = {}
    for i, v in ipairs(self.OVERDRAFT_PERCENT_LIST) do
        odTexts[i] = (v == 0) and L("vtpas_overdraft_off") or (v .. " %")
    end
    self.options.overdraftPercent = self:addRow(layout, template, {
        label = L("vtpas_overdraft_label"),
        tip = L("vtpas_overdraft_tip"),
        texts = odTexts,
        state = self:getIndex(self.OVERDRAFT_PERCENT_LIST, self.overdraftPercent),
        callback = AS_Settings.onOverdraftPercentChanged,
    })
    local rateTexts = {}
    for i, v in ipairs(self.OVERDRAFT_RATE_LIST) do
        rateTexts[i] = (v == 0) and L("vtpas_overdraftRate_none") or (v .. " %")
    end
    self.options.overdraftRate = self:addRow(layout, template, {
        label = L("vtpas_overdraftRate_label"),
        tip = L("vtpas_overdraftRate_tip"),
        texts = rateTexts,
        state = self:getIndex(self.OVERDRAFT_RATE_LIST, self.overdraftRate),
        callback = AS_Settings.onOverdraftRateChanged,
    })

    self.options.coopPay = self:addRow(layout, template, {
        label = L("vtpas_coopPay_label"),
        tip = L("vtpas_coopPay_tip"),
        texts = onOff,
        state = self.coopPay and 2 or 1,
        callback = AS_Settings.onCoopPayChanged,
    })

    self.options.noOvertake = self:addRow(layout, template, {
        label = L("vtpas_noOvertake_label"),
        tip = L("vtpas_noOvertake_tip"),
        texts = onOff,
        state = self.noOvertake and 2 or 1,
        callback = AS_Settings.onNoOvertakeChanged,
    })

    self.options.shopBlockTwins = self:addRow(layout, template, {
        label = L("vtpas_shopBlockTwins_label"),
        tip = L("vtpas_shopBlockTwins_tip"),
        texts = onOff,
        state = self.shopBlockTwins and 2 or 1,
        callback = AS_Settings.onShopBlockTwinsChanged,
    })

    self.built = true
    layout:invalidateLayout()
    sprint("options ajoutées au menu Paramètres")
end

function AS_Settings:refreshStates()
    local o = self.options
    if o.slip ~= nil then o.slip:setState(self:getStateForValue(self.slip)) end
    if o.slipFront ~= nil then o.slipFront:setState(self:getStateForValue(self.slipFront)) end
    if o.diffDelay ~= nil then o.diffDelay:setState(self:getIndex(self.DIFF_DELAY_LIST, self.diffDelay)) end
    if o.diffMode ~= nil then o.diffMode:setState(self.driveManual and 2 or 1) end
    if o.autoOnHelper ~= nil then o.autoOnHelper:setState(self.autoOnHelper and 2 or 1) end
    if o.tireMode ~= nil then o.tireMode:setState(self.tiresUserAuto and 1 or 2) end
    if o.tireDelay ~= nil then o.tireDelay:setState(self:getIndex(self.TIRE_DELAY_LIST, self.tireDelay)) end
    if o.adField ~= nil then o.adField:setState(self:getIndex(self.AD_FIELD_LIST, self.adFieldKph)) end
    if o.adPath ~= nil then o.adPath:setState(self:getIndex(self.AD_PATH_LIST, self.adPathKph)) end
    if o.adRoad ~= nil then o.adRoad:setState(self:getIndex(self.AD_ROAD_LIST, self.adRoadKph)) end
    if o.notifyDiff ~= nil then o.notifyDiff:setState(self.notifyDiff and 2 or 1) end
    if o.notifyTires ~= nil then o.notifyTires:setState(self.notifyTires and 2 or 1) end
    if o.alertPercent ~= nil then o.alertPercent:setState(self:getIndex(self.ALERT_PERCENTS, self.alertPercent)) end
    if o.alertSeconds ~= nil then o.alertSeconds:setState(self:getIndex(self.ALERT_SECONDS_LIST, self.alertSeconds)) end
    if o.auto4wd ~= nil then o.auto4wd:setState(self.auto4wd and 2 or 1) end
    if o.wetGrip ~= nil then o.wetGrip:setState(self.wetGrip) end
    if o.seedCoverFill ~= nil then o.seedCoverFill:setState(self.seedCoverFill and 2 or 1) end
    if o.slipIcon ~= nil then o.slipIcon:setState(self.slipIcon and 2 or 1) end
    if o.protectSeed ~= nil then o.protectSeed:setState(self.protectSeed and 2 or 1) end
    if o.durTires ~= nil then o.durTires:setState(self:getIndex(self.DURATION_LIST, self.durTires)) end
    if o.durDiffs ~= nil then o.durDiffs:setState(self:getIndex(self.DURATION_LIST, self.durDiffs)) end
    if o.durAlert ~= nil then o.durAlert:setState(self:getIndex(self.DURATION_LIST, self.durAlert)) end
    if o.speedHint ~= nil then o.speedHint:setState(self.speedHint and 2 or 1) end
    if o.beamEnabled ~= nil then o.beamEnabled:setState(self.beamEnabled and 2 or 1) end
    if o.tracksMax ~= nil then o.tracksMax:setState(self:getIndex(self.TRACKS_MAX_LIST, self.tracksMax)) end
    if o.beamRange ~= nil then o.beamRange:setState(self:getIndex(self.BEAM_LIST, self.beamRange)) end
    if o.beamGlow ~= nil then o.beamGlow:setState(self:getIndex(self.BEAM_LIST, self.beamGlow)) end
    if o.windSway ~= nil then o.windSway:setState(self:getIndex(self.WIND_SWAY_LIST, self.windSway)) end
    if o.weatherWidget ~= nil then o.weatherWidget:setState(self.weatherWidget and 2 or 1) end
    if o.hudDedup ~= nil then o.hudDedup:setState(self.hudDedup and 2 or 1) end
    if o.coopPay ~= nil then o.coopPay:setState(self.coopPay and 2 or 1) end
    if o.noOvertake ~= nil then o.noOvertake:setState(self.noOvertake and 2 or 1) end
    if o.shopBlockTwins ~= nil then o.shopBlockTwins:setState(self.shopBlockTwins and 2 or 1) end
    if o.overdraftPercent ~= nil then o.overdraftPercent:setState(self:getIndex(self.OVERDRAFT_PERCENT_LIST, self.overdraftPercent)) end
    if o.overdraftRate ~= nil then o.overdraftRate:setState(self:getIndex(self.OVERDRAFT_RATE_LIST, self.overdraftRate)) end
end

function AS_Settings:onSettingsFrameOpen(frame)
    if not self.built then
        local ok, err = pcall(self.buildUI, self, frame)
        if not ok then sprint("ERREUR menu : %s", tostring(err)) end
    else
        self:refreshStates()
    end
end

-- Commande console de repli : vtpSlip <0-100>
function AS_Settings:consoleSetSlip(value)
    local v = tonumber(value)
    if v == nil then
        return string.format("Seuil actuel : %d %% (usage : vtpSlip <0-100>, 0 = désactivé)", self.slip)
    end
    self.slip = math.max(0, math.min(100, math.floor(v)))
    self:apply()
    self:save()
    self:refreshStates()
    return string.format("Seuil de patinage réglé sur %d %%", self.slip)
end

function AS_Settings:loadMap()
    self:load()
    self:apply()
    addConsoleCommand("vtpSlip", "Seuil de patinage (%) du blocage auto des différentiels, 0 = désactivé",
                      "consoleSetSlip", self)
    sprint("réglages chargés : patinage %d %%, conduite manuelle : différentiels %s, pneus %s ; notif. différentiels %s, notif. pneus %s",
           self.slip, self.driveManual and "manuel" or "auto", self.tiresUserAuto and "auto" or "manuel",
           tostring(self.notifyDiff), tostring(self.notifyTires))
end

function AS_Settings:delete()
    removeConsoleCommand("vtpSlip")
end

if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.onFrameOpen ~= nil then
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function(frame)
        AS_Settings:onSettingsFrameOpen(frame)
    end)
else
    print("[AS_Settings] InGameMenuSettingsFrame introuvable : menu non disponible, utilise vtpSlip")
end

addModEventListener(AS_Settings)
