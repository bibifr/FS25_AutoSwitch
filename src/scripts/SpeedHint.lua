-- AutoSwitch : plage de vitesse conseillée + icône de patinage
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local vtpInfo, L, showTimedNotification, getVtpClass, isAutoDriveActive, isCourseplayActive, isVehicleInField, getVehicles, getEvClass, getMaxSlipPercent, getRearSlipPercent, asState, isLockedValue, shClamp, shSmootherstep, getMudClass, shGetControlledVehicle
    = AS.vtpInfo, AS.L, AS.showTimedNotification, AS.getVtpClass, AS.isAutoDriveActive, AS.isCourseplayActive, AS.isVehicleInField, AS.getVehicles, AS.getEvClass, AS.getMaxSlipPercent, AS.getRearSlipPercent, AS.asState, AS.isLockedValue, AS.shClamp, AS.shSmootherstep, AS.getMudClass, AS.shGetControlledVehicle

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
AS_SpeedHint.SLIP_ICON = true    -- icône de patinage (roue + flèches, % au centre) affichée en permanence
AS_SpeedHint.FIELD_MAX_KPH = 18  -- vitesse haute maximale en travail dans un champ (réglable dans le menu)
AS_SpeedHint.POS_X = nil         -- position déplacée à la souris (coin bas-gauche, 0..1) ; nil = position par défaut
AS_SpeedHint.POS_Y = nil
AS_SpeedHint.dragging = false
AS_SpeedHint.box = nil           -- dernier cadre dessiné { x, y, w, h }
AS_SpeedHint.UPDATE_MS  = 500
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

function AS_SpeedHint:draw()
    self.box = nil
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

    -- icône : carrée, un peu plus haute que le cadre, accolée à sa gauche
    local iconPx = 23
    local iconW, iconH = pxw(iconPx), py(iconPx)
    local gapI = pxw(4)
    local pctSize = py(12)                       -- % de patinage écrit sous l'icône
    local pctGap = py(2)
    local iconBlockH = iconH + pctGap + pctSize
    local groupW = iconW + gapI + boxW
    local groupH = math.max(boxH, iconBlockH)

    -- position du groupe (coin bas-gauche)
    local x, y
    if self.POS_X ~= nil and self.POS_Y ~= nil then
        x, y = self.POS_X, self.POS_Y
    else
        local rightX
        local bg = sm.speedBg
        if bg ~= nil and bg.x ~= nil then
            rightX = bg.x
        elseif sm.getPosition ~= nil then
            rightX = sm:getPosition()
        else
            rightX = 0.80
        end
        x = rightX - pxw(10) - groupW
        y = (self.BOTTOM_CM or 1.5) / math.max(10, self.SCREEN_HEIGHT_CM or 31.5)
    end
    x = shClamp(x, 0, math.max(0, 1 - groupW))
    y = shClamp(y, 0, math.max(0, 1 - groupH))
    self.box = { x = x, y = y, w = groupW, h = groupH }

    local boxX = x + iconW + gapI
    local iconY = y + groupH - iconH                 -- icône en haut du bloc, % en dessous
    local boxY = iconY + (iconH - boxH) * 0.5        -- plage centrée sur l'icône
    local hasRange = showRange and st.line1 ~= nil

    if drawFilledRect ~= nil and self:getCanDrag() then
        drawFilledRect(x - pxw(2), y - py(2), groupW + pxw(4), groupH + py(4), 1, 0.78, 0.2, self.dragging and 0.9 or 0.6)
    end

    -- icône de patinage + pourcentage en dessous (affichés en permanence)
    if showIcon then
        local pct = math.floor((st.slipPct or 0) + 0.5)
        local r, g, b = shSlipColor(pct)
        if drawFilledRect ~= nil then
            drawFilledRect(x, y, iconW, groupH, 0, 0, 0, 0.45)
        end
        local ov = self:getIconOverlay()
        if ov ~= nil then
            setOverlayColor(ov, r, g, b, 1)
            renderOverlay(ov, x, iconY, iconW, iconH)
        end
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(r, g, b, 1)
        renderText(x + iconW * 0.5, iconY - pctGap - pctSize * 0.85, pctSize, tostring(pct) .. " %")
    end

    -- plage de vitesse conseillée (dans les champs)
    if hasRange then
        if drawFilledRect ~= nil then
            drawFilledRect(boxX, boxY, boxW, boxH, 0, 0, 0, 0.6)
        end
        local c = SH_COLORS[st.color] or SH_COLORS.green
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(c[1], c[2], c[3], c[4])
        renderText(boxX + boxW * 0.5, boxY + padY + py(1), size1, st.line1)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Déplacement à la souris
--   Il suffit que le curseur soit visible (clic droit de Courseplay, mode curseur
--   de Mud System Physics...) : clic gauche maintenu sur le cadre = déplacer.
--   Retour à la position par défaut : réglage "hauteur depuis le bas" dans le menu.
-- ---------------------------------------------------------------------------
function AS_SpeedHint:getCanDrag()
    return (self.ENABLED or self.SLIP_ICON) and g_inputBinding ~= nil and g_inputBinding.getShowMouseCursor ~= nil
        and g_inputBinding:getShowMouseCursor() == true
end

function AS_SpeedHint:isOverBox(px, py_)
    local b = self.box
    return b ~= nil and px >= b.x and px <= b.x + b.w and py_ >= b.y and py_ <= b.y + b.h
end

function AS_SpeedHint:savePosition()
    if AS_Settings ~= nil then
        AS_Settings.hintPosX = self.POS_X
        AS_Settings.hintPosY = self.POS_Y
        AS_Settings:save()
    end
end

function AS_SpeedHint:mouseEvent(posX, posY, isDown, isUp, button)
    if not self:getCanDrag() then
        self.dragging = false
        return
    end

    if isDown and self:isOverBox(posX, posY) then
        if button == Input.MOUSE_BUTTON_LEFT then
            self.dragging = true
            self.dragDX, self.dragDY = posX - self.box.x, posY - self.box.y
        end
        return
    end

    if self.dragging then
        self.POS_X = posX - (self.dragDX or 0)
        self.POS_Y = posY - (self.dragDY or 0)
        if self.box ~= nil then
            self.POS_X = shClamp(self.POS_X, 0, math.max(0, 1 - self.box.w))
            self.POS_Y = shClamp(self.POS_Y, 0, math.max(0, 1 - self.box.h))
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
end

addModEventListener(AS_SpeedHint)
