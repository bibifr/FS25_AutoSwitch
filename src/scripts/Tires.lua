-- AutoSwitch : gonflage / dégonflage automatique (Variable Tire Pressure)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-- AS_Tires.lua  (script COMPAGNON, v1.32 : usure Use Your Tyres conservée dans l'adhérence)
-- Ne modifie pas VariableTirePressure.lua : il appelle seulement son callback de touche.
--   Courseplay démarre                      -> pression CHAMP (dégonflage)
--   AutoDrive actif et véhicule dans champ  -> pression CHAMP (dégonflage)
--   AutoDrive actif et véhicule hors champ  -> pression ROUTE (gonflage)
-- Les changements ne sont appliqués qu'à chaque changement de zone (entrée/sortie de champ),
-- donc la touche K manuelle reste utilisable entre deux.

AS_Tires = {}
AS_Tires.RETRY_MS        = 1000   -- délai entre deux essais de bascule
AS_Tires.ZONE_CHECK_MS   = 500    -- fréquence du test "dans un champ ?"
AS_Tires.ZONE_CONFIRM_MS = 1500   -- durée de stabilité avant de confirmer un changement de zone
AS_Tires.DEBUG = false
AS_Tires.NOTIFY = true     -- notification à l'écran à chaque gonflage / dégonflage
AS_Tires.USER_AUTO = false  -- conduite manuelle : true = pneus automatiques, false = manuel (touche VTP)
                                  -- (avec AutoDrive / Courseplay, c'est toujours automatique)
AS_Tires.MIN_SWITCH_MS = 4000  -- délai minimum entre deux changements de pression (0 = aucun)
AS_Tires.lastSwitch = {}       -- [vehicle] = g_time de la dernière bascule envoyée
AS_Tires.awaiting = {}     -- [vehicle] = true (route) / false (champ) : bascule envoyée, en attente de confirmation
AS_Tires.state = {}
AS_Tires.loggedMissing = false
AS_Tires.loggedMethod = false

local function log(fmt, ...)
    if AS_Tires.DEBUG then
        print(string.format("[AS_Tires] " .. fmt, ...))
    end
end









-- Notification à l'écran indiquant quel véhicule gonfle / dégonfle ses pneus.
local function notifyTire(vehicle, toRoad)
    if not AS_Tires.NOTIFY or g_currentMission == nil then return end

    local name = vehicle:getName()
    if vehicle.getFullName ~= nil then
        name = vehicle:getFullName() or name
    end

    local text = string.format(L(toRoad and "vtpas_notif_tiresInflated" or "vtpas_notif_tiresDeflated"), name)
    showTimedNotification("tires", FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_INFO or nil, text)
end

-- true = terminé (ou inutile), false = réessayer plus tard
local function tryApply(vehicle, wantRoad)
    local spec = vehicle.spec_variableTirePressure
    if spec == nil or spec.isConfigEnabled ~= true then
        return true
    end
    if (spec.isRoadMode == true) == wantRoad then
        if AS_Tires.awaiting[vehicle] == wantRoad then
            AS_Tires.awaiting[vehicle] = nil
            notifyTire(vehicle, wantRoad)
        end
        return true
    end

    local vtp = getVtpClass()
    if vtp == nil or vtp.actionEventTogglePressure == nil then
        if not AS_Tires.loggedMissing then
            AS_Tires.loggedMissing = true
            log("ERREUR : classe VariableTirePressure introuvable depuis ce mod")
        end
        return true
    end

    log("%s : bascule vers %s", vehicle:getName(), wantRoad and "ROUTE" or "CHAMP")
    vtp.actionEventTogglePressure(vehicle, "VTP_SET_TIRE_PRESSURE", 1, InputAction.CALLBACK_STATE_START, false)
    AS_Tires.awaiting[vehicle] = wantRoad
    AS_Tires.lastSwitch[vehicle] = g_time
    return false
end

function AS_Tires:loadMap()
    log("chargé v1.2. Classe VTP trouvée : %s", tostring(getVtpClass() ~= nil))
end

-- Vrai si un nouveau changement de pression doit encore attendre (anti allers-retours rapides).
-- Une bascule déjà envoyée dans le même sens n'est jamais retardée : on laisse la confirmation se faire.
local function isSwitchDelayed(vehicle, wantRoad)
    local last = AS_Tires.lastSwitch[vehicle]
    if last == nil or AS_Tires.MIN_SWITCH_MS <= 0 then return false end
    if AS_Tires.awaiting[vehicle] == wantRoad then return false end
    return (g_time - last) < AS_Tires.MIN_SWITCH_MS
end

function AS_Tires:update(dt)
    if g_currentMission == nil or g_server == nil then
        return
    end

    for _, vehicle in pairs(getVehicles()) do
        if vehicle.spec_variableTirePressure ~= nil then
            local st = self.state[vehicle]
            if st == nil then
                st = {
                    ad = false, cp = false,
                    pending = nil, lastTry = -10000, tries = 0,
                    zone = nil,            -- dernière zone confirmée (true = champ)
                    candidate = nil, candidateSince = 0, lastZoneCheck = -10000,
                }
                self.state[vehicle] = st
            end

            local ad = isAutoDriveActive(vehicle)
            local cp = isCourseplayActive(vehicle)

            -- Courseplay : toujours pression champ au démarrage
            if cp and not st.cp then
                log("%s : Courseplay démarre -> CHAMP", vehicle:getName())
                st.pending, st.tries = false, 0
            end

            -- Qui pilote le suivi de zone ? AutoDrive (toujours automatique) ou le joueur
            -- lui-même si son mode "conduite manuelle" est réglé sur Automatique.
            local source = nil
            if ad then
                source = "AutoDrive"
            elseif not cp and self.USER_AUTO and vehicle.getIsControlled ~= nil and vehicle:getIsControlled() then
                source = "Joueur"
            end

            if source ~= nil then
                if (g_time - st.lastZoneCheck) >= self.ZONE_CHECK_MS then
                    st.lastZoneCheck = g_time
                    local inField = isVehicleInField(vehicle)
                    if inField ~= nil then
                        if not st.tracking then
                            -- le suivi vient de démarrer : on applique tout de suite selon la zone actuelle
                            st.zone, st.candidate = inField, inField
                            log("%s : %s démarre (%s)", vehicle:getName(), source, inField and "dans un champ" or "hors champ")
                            st.pending, st.tries = (not inField), 0
                        elseif inField ~= st.zone then
                            -- changement de zone : on le confirme après un court délai (anti-rebond)
                            if st.candidate ~= inField then
                                st.candidate, st.candidateSince = inField, g_time
                            elseif (g_time - st.candidateSince) >= self.ZONE_CONFIRM_MS then
                                st.zone = inField
                                log("%s : %s %s", vehicle:getName(), source, inField and "entre dans un champ" or "quitte le champ")
                                st.pending, st.tries = (not inField), 0
                            end
                        else
                            st.candidate = st.zone
                        end
                    end
                end
            else
                st.zone, st.candidate = nil, nil
            end

            st.ad, st.cp = ad, cp
            st.tracking = (source ~= nil)

            if st.pending ~= nil and (g_time - st.lastTry) >= self.RETRY_MS
               and not isSwitchDelayed(vehicle, st.pending) then
                st.lastTry = g_time
                st.tries = st.tries + 1
                if tryApply(vehicle, st.pending) or st.tries >= 10 then
                    if st.tries >= 10 then log("%s : abandon après 10 essais", vehicle:getName()) AS_Tires.awaiting[vehicle] = nil end
                    st.pending = nil
                end
            end
        end
    end
end

function AS_Tires:delete()
    self.state = {}
end

addModEventListener(AS_Tires)
