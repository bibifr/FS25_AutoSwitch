-- AutoSwitch : angle de braquage limité selon la transmission et les blocages
--              de différentiel (Enhanced Vehicle)
-- Fichier chargé par AutoSwitch.lua (après Diff.lua).
--
--   4x2                          braquage complet
--   4x4                          90 %  (v1.0.0.19, 80 % en 1.0.0.18)
--   blocage de diff arrière seul 50 %
--   blocage de diff avant seul   20 %
--   blocage des deux diffs       10 %
--
-- Le jeu (conduite manuelle comme AutoDrive / Courseplay) ne braque jamais au-delà de
-- vehicle.maxRotTime / vehicle.minRotTime ; on réduit ces deux bornes et on remet les
-- valeurs d'origine dès que le braquage complet est de nouveau permis.
-- Le déblocage en virage de Diff.lua s'enclenche aussi quand le volant est en butée
-- sur cette limite (voir AS_Steer.isAtLimit), et ne rebloque qu'une fois les roues revenues
-- dans l'angle permis avec les blocages (voir AS_Steer.fitsLocks).

local getVehicles, isLockedValue = AS.getVehicles, AS.isLockedValue

AS_Steer = {}
AS_Steer.ENABLED       = true
AS_Steer.FACTOR_4X2    = 1.00
AS_Steer.FACTOR_4X4    = 0.90
AS_Steer.FACTOR_REAR   = 0.50
AS_Steer.FACTOR_FRONT  = 0.20
AS_Steer.FACTOR_BOTH   = 0.10
AS_Steer.AT_LIMIT      = 0.95   -- volant en butée : au moins 95 % de l'angle permis
AS_Steer.DEBUG         = false
AS_Steer.state = setmetatable({}, { __mode = "k" })

local function dlog(fmt, ...)
    if AS_Steer.DEBUG then
        print(string.format("[AS_Steer] " .. fmt, ...))
    end
end

-- État réel Enhanced Vehicle (is), à défaut l'état demandé (want)
local function evValue(vd, i)
    if vd.is ~= nil and vd.is[i] ~= nil then return vd.is[i] end
    if vd.want ~= nil then return vd.want[i] end
    return nil
end

function AS_Steer.getFactor(vehicle)
    local vd = vehicle.vData
    if vd == nil then return 1 end
    local front = isLockedValue(evValue(vd, 1))
    local rear  = isLockedValue(evValue(vd, 2))
    if front and rear then return AS_Steer.FACTOR_BOTH end
    if front then return AS_Steer.FACTOR_FRONT end
    if rear then return AS_Steer.FACTOR_REAR end
    if evValue(vd, 3) == 1 then return AS_Steer.FACTOR_4X4 end
    return AS_Steer.FACTOR_4X2
end

-- Vrai quand le volant est en butée sur un braquage réduit par AutoSwitch
function AS_Steer.isAtLimit(vehicle)
    local st = AS_Steer.state[vehicle]
    if st == nil or st.factor == nil or st.factor >= 1 then return false end
    local rt = vehicle.rotatedTime or 0
    if rt > 0 then
        return st.maxSet ~= nil and st.maxSet > 0 and rt >= st.maxSet * AS_Steer.AT_LIMIT
    elseif rt < 0 then
        return st.minSet ~= nil and st.minSet < 0 and rt <= st.minSet * AS_Steer.AT_LIMIT
    end
    return false
end

-- (v1.0.0.19) Vrai si les roues sont déjà dans l'angle permis avec ces blocages :
-- AutoSwitch ne (re)bloque pas les diffs tant que les roues sont braquées au-delà.
function AS_Steer.fitsLocks(vehicle, front, rear)
    if not AS_Steer.ENABLED or type(vehicle.maxRotTime) ~= "number" or type(vehicle.minRotTime) ~= "number" then
        return true
    end
    local factor = AS_Steer.FACTOR_4X2
    if front and rear then factor = AS_Steer.FACTOR_BOTH
    elseif front then factor = AS_Steer.FACTOR_FRONT
    elseif rear then factor = AS_Steer.FACTOR_REAR end
    local st = AS_Steer.state[vehicle]
    local baseMax = (st ~= nil and st.baseMax) or vehicle.maxRotTime
    local baseMin = (st ~= nil and st.baseMin) or vehicle.minRotTime
    local rt = vehicle.rotatedTime or 0
    return rt <= baseMax * factor and rt >= baseMin * factor
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

function AS_Steer:update(dt)
    if g_currentMission == nil then return end

    for _, vehicle in pairs(getVehicles()) do
        if vehicle.vData ~= nil and type(vehicle.maxRotTime) == "number" and type(vehicle.minRotTime) == "number" then
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
    end
end

function AS_Steer:delete()
    self.state = setmetatable({}, { __mode = "k" })
end

addModEventListener(AS_Steer)
