-- AutoSwitch : plage de vitesse conseillée + icône de patinage
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle
local getWheelSlips = AS.getWheelSlips

-------------------------------------------------------------------------------
-- v1.4 : vitesse conseillée affichée au-dessus du compteur de vitesse.
--   Recalculée toutes les 0,5 s pour le véhicule que vous conduisez, selon :
--   - la zone (champ / route),
--   - la pression VTP (pneus champ : gonflage auto du mod VTP à 30 km/h),
--   - le sol sous les roues + l'humidité (modèle d'enfoncement de MudSystemPhysics) :
--       vitesse mini = vitesse en dessous de laquelle la jauge d'enfoncement monte,
--       vitesse maxi = limite douce de la boue / limite des pneus champ,
--   - le patinage mesuré (plus on patine, plus la vitesse mini monte).
-------------------------------------------------------------------------------
AS_SpeedHint = {}
AS_SpeedHint.ENABLED    = true
AS_SpeedHint.BOTTOM_CM  = 1.5     -- hauteur du bas de l'affichage au-dessus du bord bas de l'écran (cm)
AS_SpeedHint.SCREEN_HEIGHT_CM = 31.5  -- hauteur visible supposée de l'écran (≈ écran 24 à 27 pouces 16:9)
AS_SpeedHint.FIELD_MIN_KPH = 3   -- vitesse basse minimale affichée dans un champ
AS_SpeedHint.SLIP_ICON = true    -- icône de patinage affichée en permanence (v1.0.0.35 : tracteur vu de dessus, % par roue)
AS_SpeedHint.FIELD_MAX_KPH = 18  -- vitesse haute maximale en travail dans un champ
AS_SpeedHint.POS_X = nil         -- position déplacée à la souris (coin bas-gauche, 0..1) ; nil = position par défaut
AS_SpeedHint.POS_Y = nil
AS_SpeedHint.ICON_X = nil        -- (v1.0.0.36) position du tracteur, déplacé seul (nil = au-dessus de la plage)
AS_SpeedHint.ICON_Y = nil
AS_SpeedHint.dragging = false
AS_SpeedHint.box = nil           -- dernier cadre dessiné { x, y, w, h }
AS_SpeedHint.UPDATE_MS  = 500
AS_SpeedHint.WHEEL_UPDATE_MS = 250
AS_SpeedHint.MARGIN_KPH = 1       -- marge de sécurité ajoutée à la vitesse mini
AS_SpeedHint.state = { lastUpdate = -10000, slipPct = 0 }





-- Humidité du sol (0..1) telle que la voit MudSystemPhysics ; 2e valeur = sol gelé
local function shGetWetness(vehicle, fg)
    if fg ~= nil and fg.isHardWinterFrozen ~= nil then
        local ok, frozen = pcall(fg.isHardWinterFrozen, fg)
        if ok and frozen then return 0, true end
    end

    local base = nil
    if fg ~= nil and type(fg._wetnessCacheValue) == "number" then
        base = fg._wetnessCacheValue
    end
    if base == nil then
        local env = g_currentMission ~= nil and g_currentMission.environment or nil
        local weather = env ~= nil and env.weather or nil
        if weather ~= nil and weather.getGroundWetness ~= nil then
            local ok, w = pcall(weather.getGroundWetness, weather)
            if ok and type(w) == "number" then base = w end
        end
    end
    base = shClamp(base or 0, 0, 1)

    local flw = getMudClass("FieldLocalWetness")
    if flw ~= nil and flw.enabled == true and flw.getVehicleWetness ~= nil then
        local ok, w = pcall(flw.getVehicleWetness, flw, vehicle, base, 16)
        if ok and type(w) == "number" then return shClamp(w, 0, 1), false end
    end
    return base, false
end

-- Même courbe que wetnessStrength() de FieldGroundMudPhysics
local function shWetStrength(fg, w)
    local dz   = fg.wetnessDeadZone or 0.20
    local minS = fg.wetnessMinStrength or 0
    local powK = fg.wetnessCurvePow or 1.55
    if w <= dz then return shClamp(minS, 0, 0.1) end
    local t = shSmootherstep(dz, 1.0, w) ^ math.max(0.35, powK)
    return shClamp(minS + (1 - minS) * t, 0, 1)
end

-- Vitesse mini (km/h) pour que la jauge d'enfoncement ne monte pas, sur la roue la plus défavorable.
-- sinkIn  = effMud * sinkMul * (0.30 + patinage) * sinkInSpeed * charge
-- sinkOut = (1 - effMud) * vitesse * (legacyScale / 25) * sinkOutSpeed
local function shComputeMinSpeed(vehicle, fg, wet, slip01)
    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if wheels == nil or fg.getWheelGroundProfile == nil then return nil, nil, 0 end

    local wetK = shWetStrength(fg, wet)
    local load = 1.0
    local wls = getMudClass("WheelLoadSystem")
    if wls ~= nil and wls.getVehicleLoadFactor ~= nil then
        local ok, lf = pcall(wls.getVehicleLoadFactor, wls, vehicle)
        if ok and type(lf) == "number" then load = lf end
    end

    local best, bestProf, bestEff = nil, nil, 0
    for _, wheel in ipairs(wheels) do
        local ok, mud, _gt, prof = pcall(fg.getWheelGroundProfile, fg, wheel)
        if ok and prof ~= nil then
            bestProf = bestProf or prof
            local eff = shClamp((mud or prof.mud or 0) * (prof.wetMul or 1), 0, 1) * wetK
            if eff > 0.001 then
                local sinkIn = eff * (prof.sinkMul or 1) * (0.30 + slip01) * (fg.sinkInSpeed or 1) * load
                local perKph = (1 - eff) * ((fg.legacySpeedResponseScale or 3.6) / 25) * (fg.sinkOutSpeed or 0.35)
                local v = (perKph > 0.0001) and (sinkIn / perKph) or 999
                if best == nil or v > best then
                    best, bestProf, bestEff = v, prof, eff
                end
            end
        end
    end
    return best, bestProf, bestEff
end

local function shVehicleMaxKph(vehicle)
    if vehicle.getMotor ~= nil then
        local motor = vehicle:getMotor()
        if motor ~= nil and motor.getMaximumForwardSpeed ~= nil then
            local ok, ms = pcall(motor.getMaximumForwardSpeed, motor)
            if ok and type(ms) == "number" and ms > 0 then return ms * 3.6 end
        end
    end
    return nil
end

local function shGroundName(prof)
    if prof == nil or prof.name == nil then return nil end
    local key = "vtpas_gt_" .. tostring(prof.name)
    local txt = L(key)
    if txt == key then return tostring(prof.name) end
    return txt
end

function AS_SpeedHint:compute(vehicle)
    local st = self.state
    st.vehicle = vehicle

    -- patinage lissé (%)
    local slip = getMaxSlipPercent(vehicle) or 0
    st.slipPct = st.slipPct + (shClamp(slip, 0, 100) - st.slipPct) * 0.35
    local slip01 = shClamp(st.slipPct / 100, 0.05, 0.50)

    local inField = isVehicleInField(vehicle)

    -- v1.7 : affichage uniquement dans les champs (confirmé sur 2 mesures pour éviter le clignotement en bordure)
    if inField ~= st.lastZone then
        st.lastZone, st.zoneCount = inField, 1
    else
        st.zoneCount = (st.zoneCount or 0) + 1
    end
    if st.zoneCount >= 2 then st.shownZone = inField end
    if st.shownZone ~= true then
        st.line1, st.line2 = nil, nil
        return
    end

    local spec = vehicle.spec_variableTirePressure
    local hasVtp = spec ~= nil and spec.isConfigEnabled == true
    local fieldPressure = hasVtp and spec.isRoadMode ~= true
    local tireMax = fieldPressure and ((spec.autoInflateSpeedKmh or 30) - 1) or nil
    local vehMax = shVehicleMaxKph(vehicle)

    local fg = getMudClass("FieldGroundMudPhysics")
    local mudOn = fg ~= nil and fg.enabled == true

    local parts = {}
    local lower, upper = nil, tireMax
    local color = "green"

    if inField == true then
        table.insert(parts, L("vtpas_hint_field"))
        if mudOn then
            local wet, frozen = shGetWetness(vehicle, fg)
            local vmin, prof, eff = shComputeMinSpeed(vehicle, fg, wet, slip01)
            local gname = shGroundName(prof)
            if gname ~= nil then table.insert(parts, gname) end
            if frozen then
                table.insert(parts, L("vtpas_hint_frozen"))
            else
                table.insert(parts, string.format(L("vtpas_hint_soil"), math.floor(wet * 100 + 0.5)))
                if eff > 0.01 then
                    local mudCap = fg.maxSpeedMudKph or 23
                    upper = (upper ~= nil) and math.min(upper, mudCap) or mudCap
                    color = "yellow"
                    if vmin ~= nil and vmin >= 0.8 then
                        lower = math.ceil(vmin + self.MARGIN_KPH)
                    end
                end
            end
        end
    elseif inField == false then
        table.insert(parts, L("vtpas_hint_road"))
    end

    if hasVtp then
        table.insert(parts, L(fieldPressure and "vtpas_hint_tiresField" or "vtpas_hint_tiresRoad"))
    end

    -- limite de travail de l'outil attelé (charrue, semoir...) quand il travaille
    if vehicle.getSpeedLimit ~= nil then
        local ok, lim, doCheck = pcall(vehicle.getSpeedLimit, vehicle, true)
        if ok and doCheck ~= false and type(lim) == "number" and lim > 0 and lim < 200 then
            upper = (upper ~= nil) and math.min(upper, lim) or lim
        end
    end

    if upper == nil then upper = vehMax or 50 end
    -- v1.8 : un tracteur au travail dans un champ ne dépasse pas FIELD_MAX_KPH
    upper = math.min(upper, self.FIELD_MAX_KPH or 18)
    upper = math.floor(upper)

    -- plage toujours affichée : vitesse basse et vitesse haute
    if lower == nil then
        lower = (inField == true) and self.FIELD_MIN_KPH or 0
    end
    lower = math.max(lower, (inField == true) and self.FIELD_MIN_KPH or 0)

    local line1
    if lower >= upper then
        line1 = string.format(L("vtpas_hint_range"), lower, math.max(lower, upper))
        table.insert(parts, 1, L("vtpas_hint_riskShort"))
        color = "red"
    else
        line1 = string.format(L("vtpas_hint_range"), lower, upper)
    end

    -- patinage important : on le signale
    local alertPct = (AS_SlipAlert ~= nil and AS_SlipAlert.ALERT_PERCENT ~= nil and AS_SlipAlert.ALERT_PERCENT > 0)
        and AS_SlipAlert.ALERT_PERCENT or 80
    if st.slipPct >= 25 then
        table.insert(parts, string.format(L("vtpas_hint_slip"), math.floor(st.slipPct + 0.5)))
        if st.slipPct >= alertPct then color = "red"
        elseif color == "green" then color = "yellow" end
    end

    st.line1 = line1
    st.line2 = nil   -- v1.6 : ligne "Champ · pneus champ..." supprimée (seule la plage est affichée)
    st.color = color
end

function AS_SpeedHint:update(dt)
    if not (self.ENABLED or self.SLIP_ICON) or g_currentMission == nil then return end
    local vehicle = shGetControlledVehicle()
    if vehicle == nil or vehicle.spec_wheels == nil then
        self.state.vehicle, self.state.line1 = nil, nil
        return
    end
    if vehicle ~= self.state.vehicle then
        self.state.slipPct = 0
        self.state.lastUpdate = -10000
    end
    if (g_time - self.state.lastUpdate) >= self.UPDATE_MS then
        self.state.lastUpdate = g_time
        local ok, err = pcall(self.compute, self, vehicle)
        if not ok then
            self.state.line1 = nil
            if not self.loggedError then
                self.loggedError = true
                print("[AS_SpeedHint] erreur : " .. tostring(err))
            end
        end
    end
    -- (v1.0.0.35) patinage de chaque roue, lissé, pour l'icône du tracteur
    if (g_time - (self.state.lastWheelUpdate or -10000)) >= self.WHEEL_UPDATE_MS then
        self.state.lastWheelUpdate = g_time
        local ok, slips = pcall(getWheelSlips, vehicle)
        local ws = self.state.wheelSlip
        if ws == nil or self.state.wheelVehicle ~= vehicle then
            ws = {}
            self.state.wheelSlip, self.state.wheelVehicle = ws, vehicle
        end
        for _, k in ipairs({ "fl", "fr", "rl", "rr" }) do
            local v = ok and slips ~= nil and slips[k] or nil
            if v == nil then
                ws[k] = nil
            else
                ws[k] = (ws[k] or 0) + (shClamp(v, 0, 100) - (ws[k] or 0)) * 0.5
            end
        end
    end
end

local SH_COLORS = {
    green  = { 0.45, 0.90, 0.35, 1 },
    yellow = { 1.00, 0.78, 0.20, 1 },
    red    = { 1.00, 0.25, 0.20, 1 },
}

-- Couleur de l'icône selon le patinage : blanc < seuil diff. < orange < seuil d'alerte < rouge
local function shSlipColor(pct)
    local diffPct = (AS_Diff ~= nil and AS_Diff.SLIP_ON_PERCENT) or 30
    local alertPct = (AS_SlipAlert ~= nil and AS_SlipAlert.ALERT_PERCENT ~= nil and AS_SlipAlert.ALERT_PERCENT > 0)
        and AS_SlipAlert.ALERT_PERCENT or 80
    if pct >= alertPct then return 1.00, 0.25, 0.20 end
    if pct >= diffPct then return 1.00, 0.67, 0.16 end
    if pct >= 10 then return 1.00, 0.90, 0.45 end
    return 0.92, 0.92, 0.92
end

function AS_SpeedHint:getIconOverlay()
    if self.iconOverlay == nil and not self.iconFailed then
        local path = Utils.getFilename("hud/vtpas_slip.dds", AS_MOD_DIR)
        local ok, ov = pcall(createImageOverlay, path)
        if ok and ov ~= nil and ov ~= 0 then
            self.iconOverlay = ov
        else
            self.iconFailed = true
            print("[AS_SpeedHint] icône introuvable : " .. tostring(path))
        end
    end
    return self.iconOverlay
end

-- (v1.0.0.35) tracteur vu de dessus selon l'état Enhanced Vehicle :
-- 0 rien, 1 pont AV bloqué, 2 pont AR, 3 les deux, +4 en 4x4 (transmission en vert)
-- (v1.0.0.54) icône moissonneuse / ensileuse : hud/vtpas_combine0..7.dds
function AS_SpeedHint:getDriveOverlay(k, harvester)
    self.driveOverlays = self.driveOverlays or {}
    local key = harvester and (k + 8) or k
    local ov = self.driveOverlays[key]
    if ov == nil then
        local path = Utils.getFilename(string.format(harvester and "hud/vtpas_combine%d.dds" or "hud/vtpas_drive%d.dds", k), AS_MOD_DIR)
        local ok, o = pcall(createImageOverlay, path)
        if ok and o ~= nil and o ~= 0 then
            ov = o
        else
            ov = false
            print("[AS_SpeedHint] icône introuvable : " .. tostring(path))
        end
        self.driveOverlays[key] = ov
    end
    return ov or nil
end

-- état affiché : k (icône), pont avant / arrière bloqué, pont avant / arrière moteur
-- (v1.0.0.54) sans 4x4 : un seul pont moteur, son blocage est le différentiel 1 d'Enhanced
-- Vehicle ; (v1.0.0.56) pont moteur lu dans la transmission réelle (Transmission.lua)
local function shDriveState(vehicle)
    local vd = vehicle.vData
    local is = vd ~= nil and vd.is or nil
    if is == nil then return 0, false, false, false, true end
    if not AS.is4wd(vehicle) then
        local lock = isLockedValue(is[1])
        if AS.drivenAxle(vehicle) == "front" then
            return lock and 1 or 0, lock, false, true, false
        end
        return lock and 2 or 0, false, lock, false, true
    end
    local front, rear = isLockedValue(is[1]), isLockedValue(is[2])
    local k = (front and 1 or 0) + (rear and 2 or 0) + (is[3] == 1 and 4 or 0)
    return k, front, rear, is[3] ~= 0, true
end

-- texte de patinage centré en (cx, cy), sur fond sombre
local function shDrawPct(cx, cy, size, pct, padX, padY)
    local txt = tostring(math.floor(pct + 0.5)) .. " %"
    local r, g, b = shSlipColor(pct)
    setTextBold(true)
    local w = getTextWidth(size, txt)
    if drawFilledRect ~= nil then
        drawFilledRect(cx - w * 0.5 - padX, cy - size * 0.5 - padY, w + padX * 2, size + padY * 2, 0, 0, 0, 0.6)
    end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(r, g, b, 1)
    renderText(cx, cy - size * 0.35, size, txt)
end

function AS_SpeedHint:draw()
    self.box, self.iconBox = nil, nil
    if g_currentMission == nil then return end
    local showRange = self.ENABLED == true
    local showIcon = self.SLIP_ICON == true
    if not showRange and not showIcon then return end

    local st = self.state
    local vehicle = shGetControlledVehicle()
    if vehicle == nil or st.vehicle ~= vehicle then return end

    local hud = g_currentMission.hud
    if hud == nil or (hud.getIsVisible ~= nil and not hud:getIsVisible()) then return end
    local sm = hud.speedMeter
    if sm == nil or (sm.getVisible ~= nil and not sm:getVisible()) then return end

    local function py(px)
        if sm.scalePixelToScreenHeight ~= nil then return sm:scalePixelToScreenHeight(px) end
        return px / 1080
    end
    local function pxw(px)
        if sm.scalePixelToScreenWidth ~= nil then return sm:scalePixelToScreenWidth(px) end
        return px / 1920
    end

    -- cadre de la plage : largeur fixe (évite que l'ensemble bouge quand les chiffres changent)
    local size1 = py(15)
    local padY, padX = py(5), pxw(8)
    setTextBold(true)
    local boxW = getTextWidth(size1, string.format(L("vtpas_hint_range"), 88, 88)) + padX * 2
    local boxH = size1 + padY * 2

    -- position par défaut de la plage : à gauche du compteur
    local rightX
    local bg = sm.speedBg
    if bg ~= nil and bg.x ~= nil then
        rightX = bg.x
    elseif sm.getPosition ~= nil then
        rightX = sm:getPosition()
    else
        rightX = 0.80
    end
    local defX = rightX - pxw(10) - boxW
    local defY = (self.BOTTOM_CM or 1.5) / math.max(10, self.SCREEN_HEIGHT_CM or 31.5)

    -- (v1.0.0.36) plage de vitesse conseillée : bloc indépendant, déplaçable seul
    local x, y = defX, defY
    if self.POS_X ~= nil and self.POS_Y ~= nil then x, y = self.POS_X, self.POS_Y end
    x = shClamp(x, 0, math.max(0, 1 - boxW))
    y = shClamp(y, 0, math.max(0, 1 - boxH))
    self.box = showRange and { x = x, y = y, w = boxW, h = boxH } or nil
    if showRange and st.line1 ~= nil then
        if drawFilledRect ~= nil then
            drawFilledRect(x, y, boxW, boxH, 0, 0, 0, 0.6)
        end
        local c = SH_COLORS[st.color] or SH_COLORS.green
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(c[1], c[2], c[3], c[4])
        renderText(x + boxW * 0.5, y + padY + py(1), size1, st.line1)
    end

    -- (v1.0.0.35) tracteur vu de dessus (état Enhanced Vehicle) + patinage de chaque roue ;
    -- pont bloqué : un seul % centré sur le pont
    -- (v1.0.0.36) bloc indépendant de la plage, déplaçable seul ; par défaut au-dessus d'elle
    self.iconBox = nil
    if showIcon then
        local iconPx = 72
        local iconW, iconH = pxw(iconPx), py(iconPx)
        local pctSize = py(11)
        setTextBold(true)
        local labelW = getTextWidth(pctSize, "100 %") + pxw(6)
        local blockW = labelW * 2 + iconW
        local bx, by = defX + boxW - blockW, defY + boxH + py(8)
        if self.ICON_X ~= nil and self.ICON_Y ~= nil then bx, by = self.ICON_X, self.ICON_Y end
        bx = shClamp(bx, 0, math.max(0, 1 - blockW))
        -- (v1.0.0.50) mode AUTO / MANUEL écrit au-dessus du tracteur (compris dans le bloc déplaçable)
        local modeSize = py(12)
        local modeH = modeSize + py(4)
        by = shClamp(by, 0, math.max(0, 1 - iconH - modeH))
        self.iconBox = { x = bx, y = by, w = blockW, h = iconH + modeH }
        local manual = AS_Diff ~= nil and AS_Diff.isManual ~= nil and AS_Diff.isManual(vehicle)
        if drawFilledRect ~= nil then
            drawFilledRect(bx, by + iconH, blockW, modeH, 0, 0, 0, 0.6)
        end
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        if manual then setTextColor(1, 0.6, 0.1, 1) else setTextColor(0.3, 1, 0.3, 1) end
        renderText(bx + blockW * 0.5, by + iconH + py(2) + modeSize * 0.15, modeSize, L(manual and "vtpas_hud_manual" or "vtpas_hud_auto"))

        local k, frontLocked, rearLocked, frontDriven, rearDriven = shDriveState(vehicle)
        local harvester = AS.isHarvester(vehicle)
        local iconX = bx + labelW
        if drawFilledRect ~= nil then
            drawFilledRect(bx, by, blockW, iconH, 0, 0, 0, 0.35)
        end
        local ov = self:getDriveOverlay(k, harvester)
        if ov ~= nil then
            setOverlayColor(ov, 1, 1, 1, 1)
            renderOverlay(ov, iconX, by, iconW, iconH)
        end
        -- ponts dans l'image (256 px) : tracteur avant à 55 px du haut, arrière à 195 px ;
        -- moissonneuse avant à 73 px, arrière à 207 px
        local ws = st.wheelVehicle == vehicle and st.wheelSlip or nil
        if ws ~= nil then
            local lpX, lpY = pxw(3), py(1.5)
            local fy, ry = 55, 195
            if harvester then fy, ry = 73, 207 end
            -- (v1.0.0.42) roues libres (non motrices) : pas de patinage affiché
            local axles = {
                { y = by + iconH * (1 - fy / 256), l = frontDriven and ws.fl or nil, r = frontDriven and ws.fr or nil, locked = frontLocked and frontDriven },
                { y = by + iconH * (1 - ry / 256), l = rearDriven and ws.rl or nil, r = rearDriven and ws.rr or nil, locked = rearLocked and rearDriven },
            }
            for _, a in ipairs(axles) do
                if a.locked and (a.l ~= nil or a.r ~= nil) then
                    shDrawPct(iconX + iconW * 0.5, a.y, pctSize, math.max(a.l or 0, a.r or 0), lpX, lpY)
                else
                    if a.l ~= nil then shDrawPct(bx + labelW * 0.5, a.y, pctSize, a.l, lpX, lpY) end
                    if a.r ~= nil then shDrawPct(iconX + iconW + labelW * 0.5, a.y, pctSize, a.r, lpX, lpY) end
                end
            end
        end
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Déplacement à la souris
--   Il suffit que le curseur soit visible (clic droit de Courseplay, mode curseur
--   de Mud System Physics...) : clic gauche maintenu sur le cadre = déplacer.
-- ---------------------------------------------------------------------------
function AS_SpeedHint:getCanDrag()
    return (self.ENABLED or self.SLIP_ICON) and g_inputBinding ~= nil and g_inputBinding.getShowMouseCursor ~= nil
        and g_inputBinding:getShowMouseCursor() == true
end

local function shInBox(bx, px, py_)
    return bx ~= nil and px >= bx.x and px <= bx.x + bx.w and py_ >= bx.y and py_ <= bx.y + bx.h
end

function AS_SpeedHint:savePosition()
    if AS_Settings ~= nil then
        AS_Settings.hintPosX, AS_Settings.hintPosY = self.POS_X, self.POS_Y
        AS_Settings.iconPosX, AS_Settings.iconPosY = self.ICON_X, self.ICON_Y
        AS_Settings:save()
    end
end

-- (v1.0.0.36) deux blocs déplaçables séparément (tracteur, plage), sans surlignage
function AS_SpeedHint:mouseEvent(posX, posY, isDown, isUp, button)
    if not self:getCanDrag() then
        self.dragging = false
        return
    end

    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        local target, b = nil, nil
        if shInBox(self.iconBox, posX, posY) then
            target, b = "icon", self.iconBox
        elseif shInBox(self.box, posX, posY) then
            target, b = "range", self.box
        end
        if target ~= nil then
            self.dragging, self.dragTarget = true, target
            self.dragDX, self.dragDY = posX - b.x, posY - b.y
        end
        return
    end

    if self.dragging then
        local b = self.dragTarget == "icon" and self.iconBox or self.box
        local nx, ny = posX - (self.dragDX or 0), posY - (self.dragDY or 0)
        if b ~= nil then
            nx = shClamp(nx, 0, math.max(0, 1 - b.w))
            ny = shClamp(ny, 0, math.max(0, 1 - b.h))
        end
        if self.dragTarget == "icon" then
            self.ICON_X, self.ICON_Y = nx, ny
        else
            self.POS_X, self.POS_Y = nx, ny
        end
        if isUp then
            self.dragging = false
            self:savePosition()
        end
    end
end

function AS_SpeedHint:delete()
    self.state = { lastUpdate = -10000, slipPct = 0 }
    if self.iconOverlay ~= nil then
        delete(self.iconOverlay)
        self.iconOverlay = nil
    end
    for k, ov in pairs(self.driveOverlays or {}) do
        if ov then delete(ov) end
    end
    self.driveOverlays = nil
end

addModEventListener(AS_SpeedHint)
