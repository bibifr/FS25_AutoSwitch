-- AutoSwitch : vitesse d'AutoDrive imposée selon le terrain (champ / chemin / route)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

-------------------------------------------------------------------------------
-- v1.0.0.0 : quand AutoDrive conduit, sa vitesse est fixée par le terrain sous le
--   tracteur, à la place des deux vitesses réglées dans AutoDrive :
--     champ  -> FIELD_KPH  (polygone de champ de la carte)
--     chemin -> PATH_KPH   (terrain : gravier, terre, herbe...)
--     route  -> ROAD_KPH   (route goudronnée / objet en dur sous les roues ; 0 = sans limite)
--   Les ralentissements d'AutoDrive (virages, arrivée, silo, chargement) restent
--   appliqués par-dessus.
--   Chemin ou route : type de sol vu par les roues (WheelsUtil.getGroundType),
--   à la majorité des roues au sol. Un changement de terrain n'est pris en compte
--   qu'après ZONE_CONFIRM_MS, pour ne pas changer de vitesse sur un raccord.
--   Les fonctions de vitesse d'AutoDrive sont remplacées véhicule par véhicule :
--   aucun fichier d'AutoDrive n'est modifié.
-------------------------------------------------------------------------------
AS_AdSpeed = {}
AS_AdSpeed.FIELD_KPH       = 20
AS_AdSpeed.PATH_KPH        = 30
AS_AdSpeed.ROAD_KPH        = 0      -- 0 = sans limite (vitesse maximale du tracteur)
AS_AdSpeed.CHECK_MS        = 250
AS_AdSpeed.ZONE_CONFIRM_MS = 1500
AS_AdSpeed.state = {}   -- [vehicle] = { zone, candidate, candidateMs }
AS_AdSpeed.timer = 0

-- "field", "path", "road" ou nil (aucune roue au sol)
function AS_AdSpeed:detectZone(vehicle)
    if isVehicleInField(vehicle) == true then
        return "field"
    end
    local ws = vehicle.spec_wheels
    if ws == nil or ws.wheels == nil or WheelsUtil == nil or WheelsUtil.getGroundType == nil then
        return nil
    end
    local road, path = 0, 0
    for _, wheel in ipairs(ws.wheels) do
        local p = wheel.physics or wheel
        if p.hasGroundContact == true then
            local isField = FieldGroundType ~= nil and p.densityType ~= nil and p.densityType ~= FieldGroundType.NONE
            local isRoad = WheelContactType ~= nil and p.contact ~= nil and p.contact ~= WheelContactType.GROUND
            local ok, gt = pcall(WheelsUtil.getGroundType, isField, isRoad, p.groundDepth or 0)
            if ok and gt == WheelsUtil.GROUND_ROAD then
                road = road + 1
            elseif ok then
                path = path + 1
            end
        end
    end
    if road + path == 0 then
        return nil
    end
    return (road >= path) and "road" or "path"
end

function AS_AdSpeed:getZoneSpeed(vehicle)
    local st = self.state[vehicle]
    local zone = st ~= nil and st.zone or nil
    if zone == "field" then return self.FIELD_KPH end
    if zone == "path" then return self.PATH_KPH end
    if zone == "road" then
        if (self.ROAD_KPH or 0) > 0 then return self.ROAD_KPH end
        -- sans limite : vitesse maximale du tracteur
        local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
        if motor ~= nil and motor.getMaximumForwardSpeed ~= nil then
            return math.min(motor:getMaximumForwardSpeed() * 3.6, 255)
        end
    end
    return nil
end

-- Remplace getSpeedLimit / getFieldSpeedLimit sur le module d'état de ce véhicule.
function AS_AdSpeed:hook(vehicle)
    local sm = vehicle.ad.stateModule
    if sm.__asSpeedHooked or sm.getSpeedLimit == nil or sm.getFieldSpeedLimit == nil then
        return
    end
    sm.__asSpeedHooked = true
    local origSpeed, origField = sm.getSpeedLimit, sm.getFieldSpeedLimit
    sm.getSpeedLimit = function(s)
        local kph = s.isActive ~= nil and s:isActive() == true and AS_AdSpeed:getZoneSpeed(vehicle) or nil
        return kph or origSpeed(s)
    end
    sm.getFieldSpeedLimit = function(s)
        local kph = s.isActive ~= nil and s:isActive() == true and AS_AdSpeed:getZoneSpeed(vehicle) or nil
        return kph or origField(s)
    end
    vtpInfo(string.format("[AS_AdSpeed] %s : vitesse AutoDrive pilotée par le terrain", vehicle:getName()))
end

function AS_AdSpeed:update(dt)
    -- AutoDrive conduit sur le serveur (ou en solo) : les roues n'y sont connues que là
    if g_currentMission == nil or g_server == nil then return end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.CHECK_MS then return end
    local step = self.timer
    self.timer = 0

    for _, vehicle in ipairs(getVehicles()) do
        if vehicle.rootNode ~= nil and isAutoDriveActive(vehicle) then
            self:hook(vehicle)
            local zone = self:detectZone(vehicle)
            local st = self.state[vehicle]
            if st == nil then
                st = { zone = zone }
                self.state[vehicle] = st
            elseif zone ~= nil and zone ~= st.zone then
                if zone ~= st.candidate then
                    st.candidate, st.candidateMs = zone, 0
                end
                st.candidateMs = st.candidateMs + step
                if st.zone == nil or st.candidateMs >= self.ZONE_CONFIRM_MS then
                    st.zone, st.candidate = zone, nil
                    vtpInfo(string.format("[AS_AdSpeed] %s : %s", vehicle:getName(), zone))
                end
            else
                st.candidate = nil
            end
        elseif self.state[vehicle] ~= nil then
            self.state[vehicle] = nil
        end
    end
end

function AS_AdSpeed:deleteMap()
    self.state = {}
    self.timer = 0
end

addModEventListener(AS_AdSpeed)
