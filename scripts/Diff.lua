-- AutoSwitch : différentiels, 4x4 / 4x2, déblocage en virage (Enhanced Vehicle)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.3 : verrouillage automatique des différentiels (Enhanced Vehicle)
--        selon le patinage des roues.
--   (v1.0.0.21) chaque diff a son seuil : arrière SLIP_ON_PERCENT, avant SLIP_ON_FRONT.
--   Patinage >= seuil pendant SLIP_ON_MS            -> ce différentiel verrouillé
--   Patinage <= moitié du seuil pendant SLIP_OFF_MS -> ce différentiel déverrouillé
-- Ne déverrouille que ce que le script a lui-même verrouillé.
-------------------------------------------------------------------------------
AS_Diff = {}
AS_Diff.ENABLED         = true
AS_Diff.SLIP_ON_PERCENT  = 15     -- seuil de verrouillage du diff ARRIÈRE (v1.0.0.21 : 15 %)
AS_Diff.SLIP_OFF_PERCENT = 7.5    -- déverrouillage arrière = moitié du seuil
AS_Diff.SLIP_ON_FRONT    = 30     -- (v1.0.0.21) seuil de verrouillage du diff AVANT
AS_Diff.SLIP_OFF_FRONT   = 15     -- déverrouillage avant = moitié du seuil
AS_Diff.SLIP_ON_MS       = 1500    -- patinage maintenu avant de verrouiller
AS_Diff.SLIP_OFF_MS      = 4000   -- adhérence retrouvée avant de déverrouiller (délais : à revoir plus tard)
AS_Diff.CHECK_MS         = 100
AS_Diff.MIN_WHEEL_SPEED  = 1.0    -- m/s : en dessous, mesure ignorée (bruit)
AS_Diff.LOCK_FRONT       = true
AS_Diff.LOCK_REAR        = true
AS_Diff.DEBUG            = false
AS_Diff.NOTIFY           = true   -- notification à l'écran à chaque verrouillage / déverrouillage
AS_Diff.HELPER_ONLY               = true   -- conduite manuelle : true = manuel, false = automatique
                                                -- (avec AutoDrive / Courseplay actif, c'est TOUJOURS automatique)
AS_Diff.RELEASE_WHEN_HELPER_STOPS = true   -- relâche les différentiels verrouillés par le script quand l'assistant s'arrête
AS_Diff.HELPER_RELEASE_DELAY_MS   = 3000   -- délai avant ce relâchement (évite les coupures brèves)
AS_Diff.TURN_UNLOCK      = true   -- (v1.30) déverrouillage obligatoire en virage
AS_Diff.TURN_ON_DEG      = 15     -- braquage au-delà duquel on considère un virage (sans SteerLimit.lua)
AS_Diff.TURN_OFF_DEG     = 8      -- braquage en dessous duquel le virage est terminé
AS_Diff.AUTO_4WD         = true   -- (v1.30) 4x4 dans les champs, 4x2 sur route (Enhanced Vehicle) ; v1.0.0.34 : 4x2 sur le dur seulement
AS_Diff.ZONE_CHECK_MS    = 1000
AS_Diff.state = {}

local function dlog(fmt, ...)
    if AS_Diff.DEBUG then
        print(string.format("[AS_Diff] " .. fmt, ...))
    end
end






-- Vrai si au moins un des différentiels concernés est déjà verrouillé (état réel EV).
local function anyDiffLocked(vehicle)
    local is = vehicle.vData.is
    if is == nil then return false end
    return (AS_Diff.LOCK_FRONT and isLockedValue(is[1]))
        or (AS_Diff.LOCK_REAR  and isLockedValue(is[2]))
end

local function setDiffs(vehicle, locked)
    local vd = vehicle.vData
    if vd == nil or vd.want == nil then return false end

    if AS_Diff.LOCK_FRONT then vd.want[1] = asState(vd.want[1], locked) end
    if AS_Diff.LOCK_REAR  then vd.want[2] = asState(vd.want[2], locked) end

    local ev = getEvClass()
    if ev ~= nil and ev.updateDiffs ~= nil then
        pcall(ev.updateDiffs, vehicle)
    end
    if vehicle.raiseDirtyFlags ~= nil and vehicle.vehicleDirtyFlag ~= nil then
        pcall(vehicle.raiseDirtyFlags, vehicle, vehicle.vehicleDirtyFlag)
    end
    return true
end

-- (v1.0.0.21) Verrouille / déverrouille un seul différentiel (1 = avant, 2 = arrière)
local function setAxle(vehicle, idx, locked)
    local vd = vehicle.vData
    if vd == nil or vd.want == nil then return false end
    vd.want[idx] = asState(vd.want[idx], locked)
    if vehicle.raiseDirtyFlags ~= nil and vehicle.vehicleDirtyFlag ~= nil then
        pcall(vehicle.raiseDirtyFlags, vehicle, vehicle.vehicleDirtyFlag)
    end
    return true
end

local function axleLocked(vehicle, idx)
    local is = vehicle.vData.is
    return is ~= nil and isLockedValue(is[idx])
end

-- (v1.30) Braquage maximal des roues (degrés)
local function getSteerDeg(vehicle)
    local ws = vehicle.spec_wheels
    if ws == nil or ws.wheels == nil then return 0 end
    local maxA = 0
    for _, wheel in ipairs(ws.wheels) do
        local a = (wheel.physics ~= nil and wheel.physics.steeringAngle) or wheel.steeringAngle
        if type(a) == "number" then
            a = math.abs(a)
            if a > maxA then maxA = a end
        end
    end
    return math.deg(maxA)
end

-- (v1.30) Mode de transmission Enhanced Vehicle : 0 = 4x2, 1 = 4x4
local function setDriveMode(vehicle, mode)
    local vd = vehicle.vData
    if vd == nil or vd.want == nil or vd.want[3] == nil then return false end
    if vd.want[3] == mode then return true end
    vd.want[3] = mode
    if vehicle.raiseDirtyFlags ~= nil and vehicle.vehicleDirtyFlag ~= nil then
        pcall(vehicle.raiseDirtyFlags, vehicle, vehicle.vehicleDirtyFlag)
    end
    return true
end

-- Notification à l'écran indiquant quel véhicule verrouille / déverrouille ses différentiels.
-- (v1.0.0.21) idx = 1 (avant) ou 2 (arrière) pour un seul différentiel, nil pour les deux
local function notifyDiff(vehicle, locked, slip, idx)
    if not AS_Diff.NOTIFY or g_currentMission == nil then return end

    local name = vehicle:getName()
    if vehicle.getFullName ~= nil then
        name = vehicle:getFullName() or name
    end

    local text
    local axle = idx == 1 and "Front" or (idx == 2 and "Rear" or "")
    if locked then
        text = string.format(L("vtpas_notif_diff" .. axle .. "Locked"), name, slip or 0)
    else
        text = string.format(L("vtpas_notif_diff" .. axle .. "Unlocked"), name)
    end

    local t = nil
    if FSBaseMission ~= nil then
        t = locked and FSBaseMission.INGAME_NOTIFICATION_INFO or FSBaseMission.INGAME_NOTIFICATION_OK
    end
    showTimedNotification("diffs", t, text)
end

function AS_Diff:loadMap()
    dlog("chargé. Enhanced Vehicle trouvé : %s", tostring(getEvClass() ~= nil))
end

-- (v2.1) Au démarrage du jeu, Enhanced Vehicle recharge l'état des différentiels depuis
-- la sauvegarde : ceux qui étaient bloqués le restaient. On les remet tous débloqués,
-- une seule fois par véhicule, quelques secondes après le chargement.
AS_Diff.RESET_DELAY_MS = 3000
AS_Diff.resetDone = {}
function AS_Diff:resetLoadedDiffs(dt)
    self.resetTimer = (self.resetTimer or 0) + (dt or 0)
    if self.resetTimer < self.RESET_DELAY_MS then return end
    for _, vehicle in pairs(getVehicles()) do
        if not self.resetDone[vehicle] then
            local vd = vehicle.vData
            if vd ~= nil and vd.want ~= nil then
                self.resetDone[vehicle] = true
                if isLockedValue(vd.want[1]) or isLockedValue(vd.want[2])
                    or (vd.is ~= nil and (isLockedValue(vd.is[1]) or isLockedValue(vd.is[2]))) then
                    -- on force les deux à "débloqué", même si un seul était enclenché
                    vd.want[1] = asState(vd.want[1], false)
                    vd.want[2] = asState(vd.want[2], false)
                    if vehicle.raiseDirtyFlags ~= nil and vehicle.vehicleDirtyFlag ~= nil then
                        pcall(vehicle.raiseDirtyFlags, vehicle, vehicle.vehicleDirtyFlag)
                    end
                    vtpInfo(string.format("[AS_Diff] %s : différentiels débloqués au démarrage", vehicle:getName()))
                end
            end
        end
    end
end

function AS_Diff:update(dt)
    if g_currentMission == nil or g_server == nil then
        return
    end
    self:resetLoadedDiffs(dt)
    if not self.ENABLED then
        return
    end

    for _, vehicle in pairs(getVehicles()) do
        local vd = vehicle.vData
        if vd ~= nil and vd.want ~= nil
           and vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then

            local st = self.state[vehicle]
            if st == nil then
                st = { engaged = false, eng = {}, engAt = {}, onSince = {}, offSince = {}, lastCheck = -10000 }
                self.state[vehicle] = st
                dlog("%s : Enhanced Vehicle détecté", vehicle:getName())
            end

            -- (v1.30) 4x4 dans les champs, 4x2 sur route : appliqué seulement au changement de zone
            -- (un changement manuel reste respecté jusqu'au prochain changement de zone)
            -- (v1.0.0.34) 4x2 seulement sur le dur (goudron, béton) : chemins de gravier, terre,
            -- herbe et sable en 4x4 comme les champs (même détection que la vitesse AutoDrive)
            if self.AUTO_4WD and vd.want[3] ~= nil and (g_time - (st.lastZoneCheck or -10000)) >= self.ZONE_CHECK_MS then
                st.lastZoneCheck = g_time
                local inField
                if AS_AdSpeed ~= nil and AS_AdSpeed.detectZone ~= nil then
                    local ok, zone = pcall(AS_AdSpeed.detectZone, AS_AdSpeed, vehicle)
                    if ok and zone ~= nil then inField = (zone ~= "road") end
                else
                    inField = isVehicleInField(vehicle)
                end
                if inField ~= nil then
                    if inField ~= st.zoneCandidate then
                        st.zoneCandidate, st.zoneCount = inField, 1
                    else
                        st.zoneCount = (st.zoneCount or 0) + 1
                    end
                    if st.zoneCount >= 2 and st.zone4wd ~= inField then
                        st.zone4wd = inField
                        st.slip4wd = false
                        setDriveMode(vehicle, inField and 1 or 0)
                    end
                end
            end

            if (g_time - st.lastCheck) >= self.CHECK_MS then
                st.lastCheck = g_time
                local slip = getMaxSlipPercent(vehicle)

                -- (v1.30) virage : déverrouillage obligatoire, pas de verrouillage pendant le virage
                if self.TURN_UNLOCK then
                    if AS_Steer ~= nil then
                        -- (v1.0.0.21) virage = braquage au-delà du seuil de coupure des blocages posés
                        -- par AutoSwitch (SteerLimit.lua : 50 % arrière seul, 10 % les deux) ;
                        -- sans blocage, au-delà du seuil du blocage arrière seul
                        local f, r = st.eng[1] == true, st.eng[2] == true
                        if not (f or r) then r = true end
                        st.turning = not AS_Steer.fitsLocks(vehicle, f, r)
                    else
                        local steer = getSteerDeg(vehicle)
                        if not st.turning and steer >= self.TURN_ON_DEG then
                            st.turning = true
                        elseif st.turning and steer <= self.TURN_OFF_DEG then
                            st.turning = false
                        end
                    end
                    if st.turning then
                        st.onSince, st.offSince = {}, {}
                        if st.engaged then
                            setDiffs(vehicle, false)
                            st.engaged, st.eng = false, {}
                            notifyDiff(vehicle, false)
                        end
                        slip = nil   -- aucune décision de verrouillage pendant le virage
                    end
                end

                -- (v1.30) en 4x2, si l'essieu arrière patine : passage en 4x4 d'abord
                -- (les différentiels ne se bloquent qu'une fois en 4x4)
                local in2wd = vd.want[3] ~= nil and vd.want[3] == 0
                if self.AUTO_4WD and in2wd and slip ~= nil then
                    local rear = getRearSlipPercent(vehicle) or slip
                    if rear >= self.SLIP_ON_PERCENT then
                        st.slip4wdSince = st.slip4wdSince or g_time
                        if (g_time - st.slip4wdSince) >= self.SLIP_ON_MS then
                            setDriveMode(vehicle, 1)
                            st.slip4wd = true          -- 4x4 enclenché par le patinage (hors champ)
                            st.slip4wdOffSince = nil
                            st.slip4wdSince = nil
                        end
                    else
                        st.slip4wdSince = nil
                    end
                    st.onSince = {}
                    slip = nil   -- pas de blocage des différentiels en 4x2
                elseif st.slip4wd and slip ~= nil and st.zone4wd ~= true then
                    -- hors champ : retour en 4x2 quand l'adhérence est revenue
                    if slip <= self.SLIP_OFF_PERCENT and not st.engaged then
                        st.slip4wdOffSince = st.slip4wdOffSince or g_time
                        if (g_time - st.slip4wdOffSince) >= self.SLIP_OFF_MS then
                            setDriveMode(vehicle, 0)
                            st.slip4wd = false
                            st.slip4wdOffSince = nil
                        end
                    else
                        st.slip4wdOffSince = nil
                    end
                end

                -- L'utilisateur a repris la main (déverrouillage manuel) ?
                for idx = 1, 2 do
                    if st.eng[idx] and (g_time - (st.engAt[idx] or 0)) > 2000 and not axleLocked(vehicle, idx) then
                        st.eng[idx] = nil
                        dlog("%s : déverrouillage manuel détecté (diff %d)", vehicle:getName(), idx)
                    end
                end
                st.engaged = st.eng[1] == true or st.eng[2] == true

                -- Mode manuel : le script n'agit que si AutoDrive ou Courseplay est actif sur ce véhicule
                local allowed = true
                if self.HELPER_ONLY then
                    if isAutoDriveActive(vehicle) or isCourseplayActive(vehicle) then
                        st.helperLostSince = nil
                    else
                        allowed = false
                        st.onSince = {}
                        st.helperLostSince = st.helperLostSince or g_time
                        if st.engaged and self.RELEASE_WHEN_HELPER_STOPS
                           and (g_time - st.helperLostSince) >= self.HELPER_RELEASE_DELAY_MS then
                            for idx = 1, 2 do
                                if st.eng[idx] and axleLocked(vehicle, idx) then
                                    setAxle(vehicle, idx, false)
                                    dlog("%s : assistant arrêté -> diff %d DÉVERROUILLÉ", vehicle:getName(), idx)
                                    notifyDiff(vehicle, false, nil, idx)
                                end
                            end
                            st.engaged, st.eng, st.offSince = false, {}, {}
                        end
                    end
                end

                -- (v1.0.0.21) chaque différentiel a son seuil : arrière d'abord, avant ensuite
                if allowed and slip ~= nil then
                    for _, ax in ipairs({
                        { idx = 2, use = self.LOCK_REAR,  on = self.SLIP_ON_PERCENT, off = self.SLIP_OFF_PERCENT },
                        { idx = 1, use = self.LOCK_FRONT, on = self.SLIP_ON_FRONT,   off = self.SLIP_OFF_FRONT },
                    }) do
                        local idx = ax.idx
                        if ax.use and ax.on > 0 and slip >= ax.on then
                            st.offSince[idx] = nil
                            if not st.eng[idx] and not axleLocked(vehicle, idx) then
                                st.onSince[idx] = st.onSince[idx] or g_time
                                -- roues braquées au-delà du seuil de coupure de ces blocages : on attend
                                local front = idx == 1 or axleLocked(vehicle, 1)
                                local rear  = idx == 2 or axleLocked(vehicle, 2)
                                local fits = AS_Steer == nil or AS_Steer.fitsLocks(vehicle, front, rear)
                                if fits and (g_time - st.onSince[idx]) >= self.SLIP_ON_MS then
                                    if setAxle(vehicle, idx, true) then
                                        st.eng[idx], st.engAt[idx] = true, g_time
                                        dlog("%s : patinage %.0f%% -> diff %d VERROUILLÉ", vehicle:getName(), slip, idx)
                                        notifyDiff(vehicle, true, slip, idx)
                                    end
                                    st.onSince[idx] = nil
                                end
                            end
                        else
                            st.onSince[idx] = nil
                            if st.eng[idx] then
                                if slip <= ax.off or not ax.use or ax.on <= 0 then
                                    st.offSince[idx] = st.offSince[idx] or g_time
                                    if (g_time - st.offSince[idx]) >= self.SLIP_OFF_MS then
                                        setAxle(vehicle, idx, false)
                                        st.eng[idx], st.offSince[idx] = nil, nil
                                        dlog("%s : adhérence retrouvée -> diff %d DÉVERROUILLÉ", vehicle:getName(), idx)
                                        notifyDiff(vehicle, false, nil, idx)
                                    end
                                else
                                    st.offSince[idx] = nil
                                end
                            end
                        end
                    end
                    st.engaged = st.eng[1] == true or st.eng[2] == true
                end
            end
        end
    end
end

function AS_Diff:delete()
    self.state = {}
    self.resetDone = {}
    self.resetTimer = 0
end

addModEventListener(AS_Diff)
