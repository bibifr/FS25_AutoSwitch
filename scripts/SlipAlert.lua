-- AutoSwitch : alerte rouge de patinage
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.8 : alerte rouge quand un véhicule patine trop longtemps.
--   Patinage >= ALERT_PERCENT pendant ALERT_SECONDS -> message ROUGE.
--   Tant que le patinage continue, l'alerte est répétée toutes les REPEAT_MS.
--   ALERT_PERCENT = 0 désactive l'alerte. Réglable dans le menu Paramètres.
-------------------------------------------------------------------------------
AS_SlipAlert = {}
AS_SlipAlert.ENABLED       = true
AS_SlipAlert.ALERT_PERCENT = 80
AS_SlipAlert.ALERT_SECONDS = 5
AS_SlipAlert.REPEAT_MS     = 10000
AS_SlipAlert.CHECK_MS      = 200
AS_SlipAlert.state = {}

local function notifySlipAlert(vehicle, slip, seconds)
    if g_currentMission == nil then return end

    local name = vehicle:getName()
    if vehicle.getFullName ~= nil then
        name = vehicle:getFullName() or name
    end
    local text = string.format(L("vtpas_alert_slip"), name, slip, seconds)

    -- Notification de type "critique" (rouge) ; repli : avertissement clignotant (rouge aussi)
    showTimedNotification("alert", FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or nil, text)
end

function AS_SlipAlert:update(dt)
    if not self.ENABLED or self.ALERT_PERCENT <= 0
       or g_currentMission == nil or g_server == nil then
        return
    end

    for _, vehicle in pairs(getVehicles()) do
        if vehicle.spec_wheels ~= nil
           and vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then

            local st = self.state[vehicle]
            if st == nil then
                st = { since = nil, lastAlert = nil, lastCheck = -10000 }
                self.state[vehicle] = st
            end

            if (g_time - st.lastCheck) >= self.CHECK_MS then
                st.lastCheck = g_time
                local slip = getMaxSlipPercent(vehicle)

                if slip ~= nil and slip >= self.ALERT_PERCENT then
                    st.since = st.since or g_time
                    if (g_time - st.since) >= self.ALERT_SECONDS * 1000
                       and (st.lastAlert == nil or (g_time - st.lastAlert) >= self.REPEAT_MS) then
                        st.lastAlert = g_time
                        vtpInfo(string.format("[AS_SlipAlert] %s : patinage %.0f%% depuis %d s", vehicle:getName(), slip, self.ALERT_SECONDS))
                        notifySlipAlert(vehicle, slip, self.ALERT_SECONDS)
                    end
                else
                    st.since, st.lastAlert = nil, nil
                end
            end
        end
    end
end

function AS_SlipAlert:delete()
    self.state = {}
end

addModEventListener(AS_SlipAlert)
