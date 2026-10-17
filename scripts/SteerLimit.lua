-- AutoSwitch : braquage selon la transmission et coupure des blocages de différentiel
--              selon le braquage (Enhanced Vehicle)
-- Fichier chargé par AutoSwitch.lua (après Diff.lua).
--
-- (v1.0.0.20) Braquage : seule la transmission le limite.
--   4x2   braquage complet
--   4x4   90 %
-- Le jeu (conduite manuelle comme AutoDrive / Courseplay) ne braque jamais au-delà de
-- vehicle.maxRotTime / vehicle.minRotTime ; on réduit ces deux bornes en 4x4 et on remet
-- les valeurs d'origine en 4x2.
--
-- (v1.0.0.20) Blocages : ils ne brident pas les roues, ils se coupent quand le braquage
-- dépasse un seuil (en % du braquage complet) :
--   blocage arrière seul  50 %
--   blocage avant seul    20 %
--   les deux              10 %
-- Vaut pour tous les blocages, y compris ceux posés à la main. Un blocage demandé roues
-- braquées au-delà de son seuil est refusé, avec une icône et un texte clignotants.
-- Diff.lua ne rebloque qu'une fois les roues revenues sous le seuil (AS_Steer.fitsLocks).
-- Toujours actif (v1.0.0.25 : ligne « Différentiels : déblocage en virage » retirée du menu).
-- (v1.0.0.50) En mode MANUEL (touche Ctrl droit + Flèche haut) : blocages jamais coupés ni
-- refusés, le braquage est bridé au seuil des blocages posés (50 / 20 / 10 %).
-- (v1.0.0.51) ce bridage ne vaut que pour la physique : les roues braquent à fond à l'écran
-- et le tracteur ripe (WheelPhysics.updatePhysics).

local getVehicles, isLockedValue, asState, L, showTimedNotification, shGetControlledVehicle
    = AS.getVehicles, AS.isLockedValue, AS.asState, AS.L, AS.showTimedNotification, AS.shGetControlledVehicle

AS_Steer = {}
AS_Steer.ENABLED       = true
AS_Steer.FACTOR_4X2    = 1.00
AS_Steer.FACTOR_4X4    = 0.90
AS_Steer.CUT_REAR      = 0.50
AS_Steer.CUT_FRONT     = 0.20
AS_Steer.CUT_BOTH      = 0.10
AS_Steer.ALERT_MIN_MS  = 3000    -- alerte affichée au moins 3 s
AS_Steer.ALERT_MAX_MS  = 10000   -- et au plus 10 s, même si les roues restent braquées
AS_Steer.BLINK_MS      = 400
AS_Steer.DEBUG         = false
AS_Steer.state = setmetatable({}, { __mode = "k" })   -- bornes de braquage modifiées
AS_Steer.locks = setmetatable({}, { __mode = "k" })   -- derniers blocages vus par véhicule
AS_Steer.alert = nil
AS_Steer.phys = setmetatable({}, { __mode = "k" })    -- (v1.0.0.51) réduction de l'angle physique

local function dlog(fmt, ...)
    if AS_Steer.DEBUG then
        print(string.format("[AS_Steer] " .. fmt, ...))
    end
end

-- État demandé Enhanced Vehicle (want), à défaut l'état réel (is)
local function evWant(vd, i)
    if vd.want ~= nil and vd.want[i] ~= nil then return vd.want[i] end
    if vd.is ~= nil then return vd.is[i] end
    return nil
end

local function cutEnabled()
    return AS_Steer.ENABLED and (AS_Diff == nil or AS_Diff.TURN_UNLOCK ~= false)
end

function AS_Steer.getFactor(vehicle)
    local vd = vehicle.vData
    if vd == nil or not AS.is4wd(vehicle) then return 1 end   -- (v1.0.0.53) vrais 4x4 seulement
    if evWant(vd, 3) == 1 then return AS_Steer.FACTOR_4X4 end
    return AS_Steer.FACTOR_4X2
end

-- (v1.0.0.51) mode manuel, blocage engagé : les roues braquent à fond à l'écran, mais la
-- physique ne reçoit que l'angle du seuil du blocage (le tracteur tourne large et ripe).
-- Part de l'angle à garder pour la physique, nil si rien à réduire.
local function physScale(vehicle)
    if AS_Diff == nil or AS_Diff.isManual == nil or not AS_Diff.isManual(vehicle) then return nil end
    local vd = vehicle.vData
    local cut = AS_Steer.getCut(isLockedValue(evWant(vd, 1)), isLockedValue(evWant(vd, 2)))
    if cut == nil then return nil end
    local st = AS_Steer.state[vehicle]
    local base = (st ~= nil and st.baseMax) or vehicle.maxRotTime
    local rt = vehicle.rotatedTime or 0
    if rt < 0 then base = (st ~= nil and st.baseMin) or vehicle.minRotTime end
    local limit = math.abs(base or 0) * cut
    if limit <= 0 or math.abs(rt) <= limit then return nil end
    return limit / math.abs(rt)
end

local function updatePhysics(self, superFunc, ...)
    local scale = AS_Steer.phys[self.vehicle]
    local sa = self.steeringAngle
    if scale == nil or type(sa) ~= "number" or sa == 0 then
        return superFunc(self, ...)
    end
    self.steeringAngle = sa * scale
    local ok, err = pcall(superFunc, self, ...)
    self.steeringAngle = sa   -- angle affiché inchangé
    if not ok then error(err) end
end

-- Seuil de coupure (part du braquage complet) pour ces blocages ; nil sans blocage
function AS_Steer.getCut(front, rear)
    if front and rear then return AS_Steer.CUT_BOTH end
    if front then return AS_Steer.CUT_FRONT end
    if rear then return AS_Steer.CUT_REAR end
    return nil
end

-- Vrai si les roues sont sous le seuil de coupure de ces blocages
-- (braquage mesuré par rapport au braquage complet, 4x2).
function AS_Steer.fitsLocks(vehicle, front, rear)
    local cut = AS_Steer.getCut(front, rear)
    if cut == nil or not cutEnabled()
       or type(vehicle.maxRotTime) ~= "number" or type(vehicle.minRotTime) ~= "number" then
        return true
    end
    local st = AS_Steer.state[vehicle]
    local baseMax = (st ~= nil and st.baseMax) or vehicle.maxRotTime
    local baseMin = (st ~= nil and st.baseMin) or vehicle.minRotTime
    local rt = vehicle.rotatedTime or 0
    return rt <= baseMax * cut and rt >= baseMin * cut
end

local function apply(vehicle, st, factor)
    -- une autre source a changé les bornes : elles deviennent les nouvelles valeurs d'origine
    if st.maxSet == nil or vehicle.maxRotTime ~= st.maxSet then st.baseMax = vehicle.maxRotTime end
    if st.minSet == nil or vehicle.minRotTime ~= st.minSet then st.baseMin = vehicle.minRotTime end

    local newMax = st.baseMax * factor
    local newMin = st.baseMin * factor
    if newMax ~= vehicle.maxRotTime or newMin ~= vehicle.minRotTime then
        vehicle.maxRotTime = newMax
        vehicle.minRotTime = newMin
        if factor ~= st.factor then
            dlog("%s : braquage %d %%", vehicle:getName(), math.floor(factor * 100 + 0.5))
        end
    end
    st.maxSet, st.minSet, st.factor = newMax, newMin, factor
end

local function updateSteer(self, vehicle)
    local st = self.state[vehicle]
    local factor = self.ENABLED and self.getFactor(vehicle) or 1
    if st == nil then
        if factor < 1 then
            st = {}
            self.state[vehicle] = st
            apply(vehicle, st, factor)
        end
    else
        apply(vehicle, st, factor)
        if factor >= 1 then
            self.state[vehicle] = nil   -- valeurs d'origine remises
        end
    end
end

local function releaseLocks(vehicle)
    local vd = vehicle.vData
    vd.want[1] = asState(vd.want[1], false)
    vd.want[2] = asState(vd.want[2], false)
    if vehicle.raiseDirtyFlags ~= nil and vehicle.vehicleDirtyFlag ~= nil then
        pcall(vehicle.raiseDirtyFlags, vehicle, vehicle.vehicleDirtyFlag)
    end
end

-- Coupure des blocages au-delà du seuil, refus d'un blocage demandé roues braquées
local function updateLocks(self, vehicle)
    local vd = vehicle.vData
    if vd.want == nil then return end
    local front = isLockedValue(evWant(vd, 1))
    local rear  = isLockedValue(evWant(vd, 2))
    local prev = self.locks[vehicle] or { front = false, rear = false }
    self.locks[vehicle] = { front = front, rear = rear }

    if not (front or rear) or not cutEnabled() or self.fitsLocks(vehicle, front, rear) then
        return
    end
    -- (v1.0.0.50) mode manuel : ni coupure ni refus, angle physique bridé (physScale)
    if AS_Diff ~= nil and AS_Diff.isManual ~= nil and AS_Diff.isManual(vehicle) then
        return
    end

    local newLock = (front and not prev.front) or (rear and not prev.rear)
    releaseLocks(vehicle)
    self.locks[vehicle] = { front = false, rear = false }

    if newLock then
        -- blocage demandé roues braquées : refusé
        dlog("%s : blocage refusé, roues braquées", vehicle:getName())
        if vehicle == shGetControlledVehicle() then
            self.alert = { vehicle = vehicle, front = front, rear = rear, since = g_time }
        end
    else
        dlog("%s : braquage au-delà du seuil -> blocages coupés", vehicle:getName())
        -- les blocages posés par AutoSwitch ont leur propre notification (Diff.lua)
        if AS_Diff == nil or AS_Diff.state[vehicle] == nil or not AS_Diff.state[vehicle].engaged then
            local name = vehicle.getFullName ~= nil and vehicle:getFullName() or vehicle:getName()
            showTimedNotification("diffs", FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK or nil,
                string.format(L("vtpas_notif_diffUnlocked"), name))
        end
    end
end

function AS_Steer:update(dt)
    if g_currentMission == nil then return end

    -- (v1.0.0.51) après les loadMap : par-dessus MoreRealistic, MSP et TTD
    -- (v1.0.0.52) posé seulement en MANUEL, retiré en AUTO (gel en montant dans un tracteur sous Courseplay)
    local manual = AS_Diff ~= nil and AS_Diff.MANUAL == true
    if WheelPhysics ~= nil and WheelPhysics.updatePhysics ~= nil then
        if manual and self.physOrig == nil then
            self.physOrig = WheelPhysics.updatePhysics
            self.physHook = Utils.overwrittenFunction(self.physOrig, updatePhysics)
            WheelPhysics.updatePhysics = self.physHook
        elseif not manual and self.physOrig ~= nil and WheelPhysics.updatePhysics == self.physHook then
            WheelPhysics.updatePhysics = self.physOrig
            self.physOrig, self.physHook = nil, nil
        end
    end
    local controlled = shGetControlledVehicle()

    for _, vehicle in pairs(getVehicles()) do
        if vehicle.vData ~= nil and type(vehicle.maxRotTime) == "number" and type(vehicle.minRotTime) == "number" then
            updateSteer(self, vehicle)
            local four = AS.is4wd(vehicle)   -- (v1.0.0.53) moissonneuses et 4x2 laissés tels quels
            -- (v1.0.0.52) angle physique réduit seulement pour le véhicule conduit
            self.phys[vehicle] = (four and manual and vehicle == controlled) and physScale(vehicle) or nil
            if four and g_server ~= nil then
                updateLocks(self, vehicle)
            end
        end
    end

    -- fin de l'alerte : roues redressées (après au moins 3 s), ou 10 s écoulées, ou autre véhicule
    local a = self.alert
    if a ~= nil then
        local elapsed = g_time - a.since
        if a.vehicle ~= shGetControlledVehicle() or elapsed >= self.ALERT_MAX_MS
           or (elapsed >= self.ALERT_MIN_MS and self.fitsLocks(a.vehicle, a.front, a.rear)) then
            self.alert = nil
        end
    end
end

function AS_Steer:getAlertOverlay()
    if self.alertOverlay == nil and not self.alertFailed then
        local path = Utils.getFilename("hud/vtpas_diffSteer.dds", AS_MOD_DIR)
        local ok, ov = pcall(createImageOverlay, path)
        if ok and ov ~= nil and ov ~= 0 then
            self.alertOverlay = ov
        else
            self.alertFailed = true
            print("[AS_Steer] icône introuvable : " .. tostring(path))
        end
    end
    return self.alertOverlay
end

-- Icône rouge clignotante au centre de l'écran, texte « Redressez les roues » dessous
function AS_Steer:draw()
    local a = self.alert
    if a == nil or g_currentMission == nil then return end
    if math.floor((g_time - a.since) / self.BLINK_MS) % 2 == 1 then return end

    local iconH = 0.11
    local iconW = iconH / (g_screenAspectRatio or (16 / 9))
    local cx, iconY = 0.5, 0.58
    local ov = self:getAlertOverlay()
    if ov ~= nil then
        setOverlayColor(ov, 1, 0.15, 0.1, 1)
        renderOverlay(ov, cx - iconW * 0.5, iconY, iconW, iconH)
    end
    local size = 0.026
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(0, 0, 0, 0.8)
    renderText(cx + 0.0012, iconY - size * 1.2 - 0.002, size, L("vtpas_alert_diffSteer"))
    setTextColor(1, 0.15, 0.1, 1)
    renderText(cx, iconY - size * 1.2, size, L("vtpas_alert_diffSteer"))
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

function AS_Steer:delete()
    if self.alertOverlay ~= nil then
        delete(self.alertOverlay)
        self.alertOverlay = nil
    end
    self.state = setmetatable({}, { __mode = "k" })
    self.locks = setmetatable({}, { __mode = "k" })
    self.phys = setmetatable({}, { __mode = "k" })
    self.alert = nil
end

addModEventListener(AS_Steer)
print("[AutoSwitch] SteerLimit chargé : braquage 4x4 90 %, coupure des blocages 50 / 20 / 10 %")
