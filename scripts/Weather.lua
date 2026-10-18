-- AutoSwitch : fenêtre Météo (Ctrl droit + M)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local L = AS.L

-------------------------------------------------------------------------------
-- v1.0.0.63 : mini-météo à la place de la météo du jeu (cachée) dans la barre de
--   l'horloge, ligne du dessous : vent, direction, « Clique-moi ».
-- v1.0.0.62 : mini-météo posée par défaut à gauche de la barre de l'horloge.
-- v1.0.0.61 : mini-météo à gauche de l'horloge (actuel + prochain changement),
--   déplaçable à la souris, un clic ouvre la fenêtre ; option dans le menu.
-- v1.0.0.60 : heures arrondies au quart d'heure, colonne des valeurs décalée,
--   jours des changements écrits J+1, J+2..., bouton X pour fermer (curseur affiché).
-- v1.0.0.59 : bulletin météo lisible, ouvert / fermé par une touche.
--   Les prévisions sont celles du jeu (environment.weather.forecastItems) :
--   chaque épisode a un début (startDay, startDayTime), une durée, un type
--   (weatherType de l'objet météo) et une variante (températures mini / maxi,
--   intensité de pluie, neige, grêle, vent). C'est ce qui arrivera vraiment.
--   Les valeurs actuelles (température, vent, humidité du sol) sont lues par
--   les fonctions du jeu, donc avec les modifications de Climate Profiles
--   ou d'autres mods s'ils sont installés.
--   Le jeu ne donne pas de millimètres, seulement une intensité (0 à 1) :
--   les mm sont estimés avec MM_PER_HOUR à intensité 1.
--   Quatre parties : maintenant, prochaines 24 h (tranches de 3 h),
--   événements à venir, jours suivants.
-------------------------------------------------------------------------------
AS_Weather = {}
AS_Weather.DAY_MS       = 24 * 60 * 60 * 1000
AS_Weather.HOUR_MS      = 60 * 60 * 1000
AS_Weather.MM_PER_HOUR  = 6       -- mm de pluie par heure à intensité 1 (estimation)
AS_Weather.CM_PER_HOUR  = 4       -- cm de neige par heure à intensité 1 (estimation)
AS_Weather.PRECIP_MIN   = 0.01    -- intensité en dessous de laquelle il ne tombe rien
AS_Weather.SLOT_HOURS   = 3       -- tranches de la partie « 24 h »
AS_Weather.SLOTS        = 8
AS_Weather.MAX_EVENTS   = 6
AS_Weather.MAX_DAYS     = 7
AS_Weather.REFRESH_MS   = 1000    -- données recalculées une fois par seconde, fenêtre ouverte
AS_Weather.WIDGET_REFRESH_MS = 5000 -- (v1.0.0.61) mini-météo seule : toutes les 5 s
AS_Weather.WIDGET   = true        -- mini-météo à gauche de l'horloge (menu AutoSwitch)
AS_Weather.WIDGET_X = nil         -- position déplacée à la souris (nil = à gauche de l'horloge)
AS_Weather.WIDGET_Y = nil

AS_Weather.isOpen  = false
AS_Weather.data    = nil
AS_Weather.lastCompute = -100000
AS_Weather.overlays = {}
AS_Weather.actionEventId = nil

-- type météo du jeu -> icône et texte
local function typeInfo(wt)
    local T = WeatherType or {}
    if wt ~= nil then
        if wt == T.SUN then return "sun", "vtpas_wx_sun" end
        if wt == T.PARTIALLY_CLOUDY then return "partly", "vtpas_wx_partly" end
        if wt == T.CLOUDY then return "cloudy", "vtpas_wx_cloudy" end
        if wt == T.RAIN then return "rain", "vtpas_wx_rain" end
        if wt == T.SNOW then return "snow", "vtpas_wx_snow" end
        if wt == T.HAIL then return "hail", "vtpas_wx_hail" end
        if wt == T.THUNDER then return "thunder", "vtpas_wx_thunder" end
        if wt == T.TWISTER then return "wind", "vtpas_wx_twister" end
    end
    return "cloudy", "vtpas_wx_unknown"
end

local function isPrecipType(wt)
    local T = WeatherType or {}
    return wt ~= nil and (wt == T.RAIN or wt == T.SNOW or wt == T.HAIL or wt == T.THUNDER)
end

local function num(v, default)
    v = tonumber(v)
    if v == nil or v ~= v then return default end
    return v
end

local function getEnv()
    if g_currentMission == nil or g_currentMission.environment == nil then return nil, nil end
    local env = g_currentMission.environment
    return env, env.weather
end

local function call(obj, name, ...)
    if obj == nil or obj[name] == nil then return nil end
    local ok, a, b, c = pcall(obj[name], obj, ...)
    if ok then return a, b, c end
    return nil
end

-------------------------------------------------------------------------------
-- Lecture des prévisions du jeu
-------------------------------------------------------------------------------

-- liste des épisodes { s, e (ms absolues), wt, rain, snow, hail, tmin, tmax, wind (m/s) }
function AS_Weather:readItems(weather)
    local items = {}
    if weather == nil or type(weather.forecastItems) ~= "table" then return items end
    for _, it in ipairs(weather.forecastItems) do
        if type(it) == "table" and it.startDay ~= nil and it.startDayTime ~= nil and it.duration ~= nil then
            local s = num(it.startDay, 0) * self.DAY_MS + num(it.startDayTime, 0)
            local e = s + num(it.duration, 0)
            local obj = call(weather, "getWeatherObjectByIndex", it.season, it.objectIndex)
            local var = call(weather, "getForecastInstanceVariation", it)
            local item = { s = s, e = e, wt = obj ~= nil and obj.weatherType or nil,
                rain = 0, snow = 0, hail = 0, tmin = nil, tmax = nil, wind = nil }
            if type(var) == "table" then
                if type(var.rain) == "table" then
                    item.rain = num(var.rain.rainfallScale, 0)
                    item.snow = num(var.rain.snowfallScale, 0)
                    item.hail = num(var.rain.hailfallScale, 0)
                end
                item.tmin = num(var.minTemperature, nil)
                item.tmax = num(var.maxTemperature, item.tmin)
                if item.tmin == nil then item.tmin = item.tmax end
                if type(var.wind) == "table" then item.wind = num(var.wind.windVelocity, nil) end
            end
            if e > s then items[#items + 1] = item end
        end
    end
    table.sort(items, function(a, b) return a.s < b.s end)
    return items
end

local function itemAt(items, t)
    for _, it in ipairs(items) do
        if t >= it.s and t < it.e then return it end
    end
    return nil
end

-- température d'un épisode à l'instant t (courbe de la journée, comme Mud System Physics)
local function tempAt(item, t, dayMs)
    if item == nil or item.tmin == nil then return nil end
    local half = 0.5 * (item.tmax - item.tmin)
    local frac = (t % dayMs) / dayMs
    return half * math.sin(2 * math.pi * frac - 2.5) + item.tmin + half
end

-- cumul entre a et b : mm de pluie, cm de neige, heures de pluie / neige / grêle,
-- temps passé par type, mini / maxi des températures des épisodes
function AS_Weather:sumRange(items, a, b)
    local r = { mm = 0, cm = 0, wetH = 0, hailH = 0, byType = {}, tmin = nil, tmax = nil, wind = nil }
    for _, it in ipairs(items) do
        local s, e = math.max(a, it.s), math.min(b, it.e)
        if e > s then
            local h = (e - s) / self.HOUR_MS
            if it.rain > self.PRECIP_MIN then r.mm = r.mm + h * it.rain * self.MM_PER_HOUR end
            if it.snow > self.PRECIP_MIN then r.cm = r.cm + h * it.snow * self.CM_PER_HOUR end
            if it.rain > self.PRECIP_MIN or it.snow > self.PRECIP_MIN or it.hail > self.PRECIP_MIN then r.wetH = r.wetH + h end
            if it.hail > self.PRECIP_MIN then r.hailH = r.hailH + h end
            if it.wt ~= nil then r.byType[it.wt] = (r.byType[it.wt] or 0) + h end
            if it.tmin ~= nil then
                r.tmin = r.tmin == nil and it.tmin or math.min(r.tmin, it.tmin)
                r.tmax = r.tmax == nil and it.tmax or math.max(r.tmax, it.tmax)
            end
            if it.wind ~= nil then r.wind = math.max(r.wind or 0, it.wind) end
        end
    end
    return r
end

-- type affiché pour une période : la pluie / neige / orage s'il en tombe au moins minWetH,
-- sinon le type le plus long
local function dominantType(r, minWetH)
    local best, bestH, bestWet, bestWetH = nil, -1, nil, -1
    for wt, h in pairs(r.byType) do
        if h > bestH then best, bestH = wt, h end
        if isPrecipType(wt) and h > bestWetH then bestWet, bestWetH = wt, h end
    end
    if bestWet ~= nil and bestWetH >= minWetH then return bestWet end
    return best
end

-- vent : vitesse (m/s) et cap vers lequel il souffle (radians, 0 = nord, sens horaire)
local function readWind(weather)
    local dx, dz, speed
    if weather ~= nil and weather.windUpdater ~= nil then
        dx, dz, speed = call(weather.windUpdater, "getCurrentValues")
    end
    if type(speed) ~= "number" then speed = call(weather, "getWindSpeed") end
    local heading
    if type(dx) == "number" and type(dz) == "number" and (dx ~= 0 or dz ~= 0) then
        heading = math.atan2(dx, -dz)   -- nord = -Z sur la carte
    end
    return num(speed, nil), heading
end

function AS_Weather:compute()
    local env, weather = getEnv()
    if env == nil or weather == nil then return nil end
    local DAY, HOUR = self.DAY_MS, self.HOUR_MS
    local today = num(env.currentMonotonicDay, 0)
    local now = today * DAY + num(env.dayTime, 0)
    local items = self:readItems(weather)
    local d = { now = now, today = today, items = items }

    -- 1. maintenant
    local cur = itemAt(items, now)
    d.curType = call(weather, "getCurrentWeatherType") or (cur ~= nil and cur.wt or nil)
    d.temp = call(weather, "getCurrentTemperature") or call(weather, "getTemperature") or tempAt(cur, now, DAY)
    d.windSpeed, d.windHeading = readWind(weather)
    d.rainScale = num(call(weather, "getRainFallScale"), 0)
    d.snowScale = num(call(weather, "getSnowFallScale"), 0)
    d.hailScale = num(call(weather, "getHailFallScale"), 0)
    d.ground = call(weather, "getGroundWetness")
    local todaySum = self:sumRange(items, today * DAY, (today + 1) * DAY)
    d.todayMin, d.todayMax = todaySum.tmin, todaySum.tmax

    -- épisodes regroupés quand le type ne change pas (à partir de maintenant)
    local groups = {}
    for _, it in ipairs(items) do
        if it.e > now then
            local g = groups[#groups]
            if g ~= nil and g.wt == it.wt and math.abs(g.e - it.s) < 60000 then
                g.e = it.e
            else
                groups[#groups + 1] = { s = math.max(it.s, now), rawS = it.s, e = it.e, wt = it.wt }
            end
        end
    end
    for _, g in ipairs(groups) do
        g.sum = self:sumRange(items, g.s, g.e)
    end
    d.groups = groups
    -- fin de l'épisode en cours et prochain changement
    local g1 = groups[1]
    if g1 ~= nil and g1.rawS <= now then
        d.curEnd = g1.e
        d.next = groups[2]
    else
        d.next = g1
    end

    -- 2. prochaines 24 h, tranches de 3 h alignées sur l'heure
    local step = self.SLOT_HOURS * HOUR
    local start = now - (now % step)
    d.slots = {}
    for i = 1, self.SLOTS do
        local a = start + (i - 1) * step
        local b = a + step
        local r = self:sumRange(items, math.max(a, now), b)
        local mid = math.max(now, a + step * 0.5)
        local it = itemAt(items, mid)
        local slot = { t = a, mm = r.mm, cm = r.cm,
            wt = dominantType(r, 0.5) or (it ~= nil and it.wt or nil),
            temp = (i == 1 and d.temp) or tempAt(it, mid, DAY),
            wind = it ~= nil and it.wind or nil, known = it ~= nil }
        if i == 1 then slot.wind = d.windSpeed or slot.wind end
        d.slots[i] = slot
    end

    -- 4. jours suivants (aussi loin que le jeu prévoit)
    d.days = {}
    local lastEnd = now
    for _, it in ipairs(items) do lastEnd = math.max(lastEnd, it.e) end
    for k = 0, self.MAX_DAYS - 1 do
        local a, b = (today + k) * DAY, (today + k + 1) * DAY
        if a >= lastEnd then break end
        local r = self:sumRange(items, math.max(a, k == 0 and now or a), b)
        local full = self:sumRange(items, a, b)
        d.days[#d.days + 1] = { offset = k, wt = dominantType(r, 1) or d.curType, mm = r.mm, cm = r.cm,
            wetH = r.wetH, tmin = full.tmin, tmax = full.tmax, wind = full.wind, partial = b > lastEnd }
    end
    d.horizonH = math.max(0, lastEnd - now) / HOUR
    return d
end

-------------------------------------------------------------------------------
-- Textes
-------------------------------------------------------------------------------

-- quarter = arrondi au quart d'heure (les épisodes du jeu commencent à 13h01, 15h01...)
local function fmtClock(t, dayMs, quarter)
    local m = math.floor((t % dayMs) / 60000)
    if quarter then m = math.floor(m / 15 + 0.5) * 15 end
    return string.format("%02dh%02d", math.floor(m / 60) % 24, m % 60)
end

local function dayName(offset)
    if offset <= 0 then return L("vtpas_wx_today") end
    if offset == 1 then return L("vtpas_wx_tomorrow") end
    if offset == 2 then return L("vtpas_wx_afterTomorrow") end
    return string.format(L("vtpas_wx_inDays"), offset)
end

-- « 14h00 » aujourd'hui, sinon « J+1 14h00 » (v1.0.0.60, demande de Fabien)
function AS_Weather:fmtWhen(t, today)
    t = math.floor(t / 900000 + 0.5) * 900000
    local off = math.floor(t / self.DAY_MS) - today
    if off <= 0 then return fmtClock(t, self.DAY_MS, true) end
    return string.format(L("vtpas_wx_dayPlus"), off) .. " " .. fmtClock(t, self.DAY_MS, true)
end

local function fmtDuration(ms)
    local m = math.floor(ms / 60000 + 0.5)
    local h = math.floor(m / 60)
    m = m % 60
    if h >= 24 then
        return string.format(L("vtpas_wx_durDays"), math.floor(h / 24), h % 24)
    end
    if h == 0 then return string.format("%d min", m) end
    if m == 0 then return string.format("%d h", h) end
    return string.format("%d h %02d", h, m)
end

local function fmtTemp(t)
    if t == nil then return "--" end
    return string.format("%d°C", math.floor(t + 0.5))
end

local function fmtKmh(ms)
    if ms == nil then return "--" end
    return string.format("%d km/h", math.floor(ms * 3.6 + 0.5))
end

local function fmtPrecip(mm, cm)
    if (cm or 0) >= 0.5 then return string.format("%.0f cm", cm) end
    if (mm or 0) < 0.1 then return nil end
    if mm < 10 then return string.format("%.1f mm", mm) end
    return string.format("%.0f mm", mm)
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compassFrom(heading)
    if heading == nil then return nil end
    local fromDeg = (math.deg(heading) + 180) % 360
    return L("vtpas_wx_dir_" .. COMPASS[(math.floor((fromDeg + 22.5) / 45) % 8) + 1])
end

local function intensityKey(scale)
    if scale < 0.25 then return "vtpas_wx_light" end
    if scale < 0.6 then return "vtpas_wx_moderate" end
    return "vtpas_wx_heavy"
end

-------------------------------------------------------------------------------
-- Dessin
-------------------------------------------------------------------------------

function AS_Weather:getOverlay(key)
    local ov = self.overlays[key]
    if ov == nil then
        local path = Utils.getFilename("hud/vtpas_wx_" .. key .. ".dds", AS_MOD_DIR)
        local ok, o = pcall(createImageOverlay, path)
        if ok and o ~= nil and o ~= 0 then
            ov = o
        else
            ov = false
            print("[AS_Weather] icône introuvable : " .. tostring(path))
        end
        self.overlays[key] = ov
    end
    return ov or nil
end

local C = {
    white = { 1, 1, 1, 1 },
    gray  = { 0.70, 0.73, 0.78, 1 },
    title = { 1.00, 0.80, 0.30, 1 },
    blue  = { 0.45, 0.72, 1.00, 1 },
    cold  = { 0.55, 0.80, 1.00, 1 },
    warm  = { 1.00, 0.62, 0.35, 1 },
}

local function uiScale()
    local s = 1
    if g_gameSettings ~= nil and g_gameSettings.getValue ~= nil then
        local ok, v = pcall(g_gameSettings.getValue, g_gameSettings, "uiScale")
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    return s
end

function AS_Weather:draw()
    self.widgetBox = nil
    if g_currentMission == nil or not (self.isOpen or self.WIDGET) then return end
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then return end
    local hud = g_currentMission.hud
    if not self.isOpen and hud ~= nil and hud.getIsVisible ~= nil and not hud:getIsVisible() then return end
    local refresh = self.isOpen and self.REFRESH_MS or self.WIDGET_REFRESH_MS
    if g_time - self.lastCompute >= refresh or self.data == nil then
        self.lastCompute = g_time
        local ok, d = pcall(self.compute, self)
        if ok then
            self.data = d
        elseif not self.loggedError then
            self.loggedError = true
            print("[AS_Weather] erreur : " .. tostring(d))
        end
    end
    local d = self.data
    if d == nil then return end
    local ok, err = pcall(self.isOpen and self.drawPanel or self.drawWidget, self, d)
    if not ok and not self.loggedDrawError then
        self.loggedDrawError = true
        print("[AS_Weather] erreur d'affichage : " .. tostring(err))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

function AS_Weather:drawPanel(d)
    local DAY = self.DAY_MS
    local sc = uiScale()
    local aspect = (g_screenWidth or 1920) / math.max(1, g_screenHeight or 1080)
    local function py(px) return px * sc / 1080 end
    local function pxw(px) return py(px) / aspect end

    local W = pxw(860)
    local pad = pxw(18)
    local nowH, slotH = 120, 104
    local evRowH, dayRowH = 26, 26
    local nEv = math.min(#d.groups, self.MAX_EVENTS)
    local nDays = #d.days
    local secTitle = 30
    local Hpx = 44 + secTitle + nowH + secTitle + slotH + secTitle + math.max(1, nEv) * evRowH
        + secTitle + math.max(1, nDays) * dayRowH + 40
    local H = py(Hpx)
    local x0 = 0.5 - W * 0.5
    local y0 = 0.5 - H * 0.5
    local top = y0 + H
    local cw = W - 2 * pad

    local function text(x, y, size, s, col, align, bold)
        setTextAlignment(align or RenderText.ALIGN_LEFT)
        setTextBold(bold == true)
        local c = col or C.white
        setTextColor(c[1], c[2], c[3], c[4])
        renderText(x, y, py(size), tostring(s))
    end
    local function icon(key, x, y, sizePx, rot)
        local ov = self:getOverlay(key)
        if ov == nil then return end
        local w, h = pxw(sizePx), py(sizePx)
        setOverlayColor(ov, 1, 1, 1, 1)
        if setOverlayRotation ~= nil then setOverlayRotation(ov, rot or 0, w * 0.5, h * 0.5) end
        renderOverlay(ov, x, y, w, h)
    end
    local function tempCol(t)
        if t == nil then return C.white end
        if t <= 0 then return C.cold end
        if t >= 25 then return C.warm end
        return C.white
    end

    drawFilledRect(x0, y0, W, H, 0.05, 0.07, 0.10, 0.88)
    drawFilledRect(x0, top - py(44), W, py(44), 0.10, 0.14, 0.20, 0.95)
    text(x0 + pad, top - py(31), 20, L("vtpas_wx_title"), C.title, nil, true)
    -- (v1.0.0.60) bouton X de fermeture en haut à droite
    local bs = py(30)
    local bw = pxw(30)
    local bx, by = x0 + W - pxw(8) - bw, top - py(7) - bs
    self.closeBox = { x = bx, y = by, w = bw, h = bs }
    drawFilledRect(bx, by, bw, bs, 0.75, 0.18, 0.15, self.closeHover and 1 or 0.85)
    text(bx + bw * 0.5, by + py(7), 18, "X", C.white, RenderText.ALIGN_CENTER, true)
    text(bx - pxw(12), top - py(30), 15, dayName(0) .. "  " .. fmtClock(d.now, DAY), C.gray, RenderText.ALIGN_RIGHT)

    local y = top - py(44)
    local function section(key)
        y = y - py(secTitle)
        text(x0 + pad, y + py(8), 15, L(key), C.title, nil, true)
        drawFilledRect(x0 + pad, y + py(4), cw, py(1), 1, 1, 1, 0.15)
    end

    -- 1. maintenant
    section("vtpas_wx_now")
    y = y - py(nowH)
    local iconKey, typeKey = typeInfo(d.curType)
    icon(iconKey, x0 + pad, y + py(14), 92)
    text(x0 + pad + pxw(104), y + py(64), 40, fmtTemp(d.temp), tempCol(d.temp), nil, true)
    text(x0 + pad + pxw(104), y + py(38), 17, L(typeKey), C.white)
    if d.todayMin ~= nil then
        text(x0 + pad + pxw(104), y + py(16), 14, string.format(L("vtpas_wx_minMax"), fmtTemp(d.todayMin), fmtTemp(d.todayMax)), C.gray)
    end
    local cx = x0 + pad + pxw(310)
    local lineY = { 92, 66, 40, 14 }
    -- vent
    local windTxt = fmtKmh(d.windSpeed)
    local from = compassFrom(d.windHeading)
    if from ~= nil then windTxt = windTxt .. "  " .. string.format(L("vtpas_wx_from"), from) end
    text(cx, y + py(lineY[1]), 16, L("vtpas_wx_wind"), C.gray)
    text(cx + pxw(185), y + py(lineY[1]), 16, windTxt, C.white)
    if d.windHeading ~= nil then
        icon("arrow", cx + pxw(185) + getTextWidth(py(16), windTxt) + pxw(8), y + py(lineY[1] - 3), 20, -d.windHeading)
    end
    -- précipitations
    local precipTxt = L("vtpas_wx_none")
    local precipCol = C.white
    if d.snowScale > self.PRECIP_MIN then
        precipTxt = string.format("%s (%s)", L("vtpas_wx_snow"), L(intensityKey(d.snowScale)))
        precipCol = C.blue
    elseif d.hailScale > self.PRECIP_MIN then
        precipTxt = string.format("%s (%s)", L("vtpas_wx_hail"), L(intensityKey(d.hailScale)))
        precipCol = C.blue
    elseif d.rainScale > self.PRECIP_MIN then
        precipTxt = string.format("%s, %s", L(intensityKey(d.rainScale)),
            string.format(L("vtpas_wx_mmPerHour"), d.rainScale * self.MM_PER_HOUR))
        precipCol = C.blue
    end
    text(cx, y + py(lineY[2]), 16, L("vtpas_wx_precip"), C.gray)
    text(cx + pxw(185), y + py(lineY[2]), 16, precipTxt, precipCol)
    -- sol
    text(cx, y + py(lineY[3]), 16, L("vtpas_wx_ground"), C.gray)
    text(cx + pxw(185), y + py(lineY[3]), 16, d.ground ~= nil and string.format("%d %%", math.floor(num(d.ground, 0) * 100 + 0.5)) or "--", C.white)
    -- fin de l'épisode / prochain changement
    local changeTxt
    if d.next ~= nil then
        local _, nk = typeInfo(d.next.wt)
        changeTxt = string.format(L("vtpas_wx_nextChange"), L(nk), self:fmtWhen(d.next.s, d.today), fmtDuration(d.next.s - d.now))
    elseif d.curEnd ~= nil then
        changeTxt = string.format(L("vtpas_wx_endAt"), self:fmtWhen(d.curEnd, d.today))
    else
        changeTxt = L("vtpas_wx_noForecast")
    end
    text(cx, y + py(lineY[4]), 16, L("vtpas_wx_change"), C.gray)
    text(cx + pxw(185), y + py(lineY[4]), 16, changeTxt, C.white)

    -- 2. prochaines 24 h
    section("vtpas_wx_next24")
    y = y - py(slotH)
    local colW = cw / self.SLOTS
    for i, s in ipairs(d.slots) do
        local mx = x0 + pad + colW * (i - 0.5)
        if i % 2 == 0 then drawFilledRect(x0 + pad + colW * (i - 1), y, colW, py(slotH), 1, 1, 1, 0.04) end
        text(mx, y + py(slotH - 20), 15, i == 1 and L("vtpas_wx_nowShort") or fmtClock(s.t, DAY), C.gray, RenderText.ALIGN_CENTER, true)
        if s.known or i == 1 then
            local ik = typeInfo(s.wt)
            icon(ik, mx - pxw(20), y + py(40), 40)
            text(mx, y + py(22), 16, fmtTemp(s.temp), tempCol(s.temp), RenderText.ALIGN_CENTER, true)
            local p = fmtPrecip(s.mm, s.cm)
            text(mx, y + py(6), 13, p or fmtKmh(s.wind), p ~= nil and C.blue or C.gray, RenderText.ALIGN_CENTER)
        else
            text(mx, y + py(44), 15, "--", C.gray, RenderText.ALIGN_CENTER)
        end
    end

    -- 3. événements à venir
    section("vtpas_wx_events")
    if nEv == 0 then
        y = y - py(evRowH)
        text(x0 + pad, y + py(6), 15, L("vtpas_wx_noForecast"), C.gray)
    end
    for i = 1, nEv do
        local g = d.groups[i]
        y = y - py(evRowH)
        local ik, tk = typeInfo(g.wt)
        icon(ik, x0 + pad, y + py(1), 24)
        text(x0 + pad + pxw(34), y + py(6), 15, L(tk), C.white, nil, true)
        local span
        if g.rawS <= d.now then
            span = string.format(L("vtpas_wx_until"), self:fmtWhen(g.e, d.today))
        else
            span = string.format(L("vtpas_wx_fromTo"), self:fmtWhen(g.s, d.today), self:fmtWhen(g.e, d.today))
        end
        text(x0 + pad + pxw(190), y + py(6), 15, span, C.white)
        text(x0 + pad + pxw(560), y + py(6), 15, fmtDuration(g.e - g.s), C.gray)
        local p = fmtPrecip(g.sum.mm, g.sum.cm)
        if p ~= nil then
            text(x0 + W - pad, y + py(6), 15, "~ " .. p, C.blue, RenderText.ALIGN_RIGHT, true)
        elseif g.sum.tmin ~= nil then
            text(x0 + W - pad, y + py(6), 15, fmtTemp(g.sum.tmin) .. " / " .. fmtTemp(g.sum.tmax), C.gray, RenderText.ALIGN_RIGHT)
        end
    end

    -- 4. jours suivants
    section("vtpas_wx_days")
    if nDays == 0 then
        y = y - py(dayRowH)
        text(x0 + pad, y + py(6), 15, L("vtpas_wx_noForecast"), C.gray)
    end
    for _, dd in ipairs(d.days) do
        y = y - py(dayRowH)
        local ik, tk = typeInfo(dd.wt)
        text(x0 + pad, y + py(6), 15, dayName(dd.offset) .. (dd.partial and " *" or ""), C.white, nil, true)
        icon(ik, x0 + pad + pxw(170), y + py(1), 24)
        text(x0 + pad + pxw(204), y + py(6), 15, L(tk), C.white)
        if dd.tmin ~= nil then
            text(x0 + pad + pxw(400), y + py(6), 15, fmtTemp(dd.tmin), tempCol(dd.tmin), RenderText.ALIGN_RIGHT)
            text(x0 + pad + pxw(410), y + py(6), 15, "/", C.gray)
            text(x0 + pad + pxw(424), y + py(6), 15, fmtTemp(dd.tmax), tempCol(dd.tmax), nil, true)
        end
        if dd.wind ~= nil then text(x0 + pad + pxw(530), y + py(6), 15, fmtKmh(dd.wind), C.gray) end
        local p = fmtPrecip(dd.mm, dd.cm)
        if p ~= nil then
            text(x0 + W - pad, y + py(6), 15, string.format(L("vtpas_wx_rainDay"), p, fmtDuration(dd.wetH * self.HOUR_MS)), C.blue, RenderText.ALIGN_RIGHT)
        else
            text(x0 + W - pad, y + py(6), 15, L("vtpas_wx_dry"), C.gray, RenderText.ALIGN_RIGHT)
        end
    end

    -- pied
    text(x0 + W * 0.5, y0 + py(14), 13, string.format(L("vtpas_wx_footer"), fmtDuration(d.horizonH * self.HOUR_MS)), C.gray, RenderText.ALIGN_CENTER)
end

-------------------------------------------------------------------------------
-- (v1.0.0.61) mini-météo à gauche de l'horloge du jeu :
--   [icône] 16°C / mini-maxi du jour | [icône] prochain changement, heure, pluie.
--   Déplaçable à la souris (curseur visible), un clic l'ouvre en grand.
-------------------------------------------------------------------------------

-- (v1.0.0.63) place de la mini-météo : à la place de la météo du jeu, dans la barre de
-- l'horloge (demande de Fabien). getPosition() de la barre = coin haut-droit (vu en jeu,
-- comme Enhanced Vehicle qui pose ses blocs sous baseY - infoBgScale.height).
-- Renvoie le bord droit, le haut et la hauteur du bloc, ou nil si la barre est introuvable.
local function gameInfo()
    return g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.gameInfoDisplay or nil
end

local function overlayX(o)
    if type(o) == "table" then
        if type(o.x) == "number" then return o.x end
        if o.getPosition ~= nil then
            local ok, x = pcall(o.getPosition, o)
            if ok and type(x) == "number" then return x end
        end
    end
    return nil
end

local function clockAnchor()
    local gid = gameInfo()
    if gid == nil then return nil end
    local ok, x, y = pcall(function()
        if gid.getPosition ~= nil then return gid:getPosition() end
        return gid.x, gid.y
    end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    local h = type(gid.infoBgScale) == "table" and tonumber(gid.infoBgScale.height) or nil
    if h == nil and gid.getHeight ~= nil then
        local okH, hh = pcall(gid.getHeight, gid)
        if okH and type(hh) == "number" and hh > 0 then h = hh end
    end
    -- bord droit = juste avant le calendrier (la météo du jeu est cachée à sa gauche)
    local right = overlayX(gid.calendarIcon)
    if right == nil or right <= 0 or right >= x then return nil end
    return right, y, h
end

-- (v1.0.0.63) météo du jeu cachée dans la barre de l'horloge quand la mini-météo est
-- affichée à sa place : icônes rendues transparentes le temps du dessin du jeu
-- (Colored Weather Icons et HUD+ les recolorent, d'où le passage à chaque image).
local GAME_WEATHER_OVERLAYS = { "weatherIcon", "weatherNextIcon" }
if GameInfoDisplay ~= nil and GameInfoDisplay.draw ~= nil then
    GameInfoDisplay.draw = Utils.overwrittenFunction(GameInfoDisplay.draw, function(self, superFunc, ...)
        if not (AS_Weather.WIDGET and AS_Weather.WIDGET_X == nil and AS_Weather.anchored) then
            return superFunc(self, ...)
        end
        local saved = {}
        for _, name in ipairs(GAME_WEATHER_OVERLAYS) do
            local o = self[name]
            if type(o) == "table" and o.setColor ~= nil then
                saved[name] = { o.r, o.g, o.b, o.a }
                pcall(o.setColor, o, o.r, o.g, o.b, 0)
            end
        end
        local r = { superFunc(self, ...) }
        for name, c in pairs(saved) do
            local o = self[name]
            pcall(o.setColor, o, c[1], c[2], c[3], c[4])
        end
        return unpack(r)
    end)
end

function AS_Weather:drawWidget(d)
    local sc = uiScale()
    local aspect = (g_screenWidth or 1920) / math.max(1, g_screenHeight or 1080)
    local function py(px) return px * sc / 1080 end
    local function pxw(px) return py(px) / aspect end
    local function text(x, y, size, s, col, align, bold)
        setTextAlignment(align or RenderText.ALIGN_LEFT)
        setTextBold(bold == true)
        local c = col or C.white
        setTextColor(c[1], c[2], c[3], c[4])
        renderText(x, y, py(size), tostring(s))
    end
    local function width(size, s, bold)
        setTextBold(bold == true)
        return getTextWidth(py(size), tostring(s))
    end
    local function icon(key, x, y, sizePx, rot)
        local ov = self:getOverlay(key)
        if ov == nil then return end
        local w, h = pxw(sizePx), py(sizePx)
        setOverlayColor(ov, 1, 1, 1, 1)
        if setOverlayRotation ~= nil then setOverlayRotation(ov, rot or 0, w * 0.5, h * 0.5) end
        renderOverlay(ov, x, y, w, h)
    end

    local anchorRight, anchorTop, barH = clockAnchor()
    self.anchored = anchorRight ~= nil
    local H = py(48)
    if self.WIDGET_X == nil and barH ~= nil and barH > py(30) and barH < py(120) then H = barH end
    local pad, gap, iconPx = pxw(10), pxw(10), 34
    local iconW = pxw(iconPx)
    -- textes
    local curIcon = typeInfo(d.curType)
    local tempTxt = fmtTemp(d.temp)
    local mmTxt = d.todayMin ~= nil and (fmtTemp(d.todayMin) .. " / " .. fmtTemp(d.todayMax)) or ""
    local leftW = math.max(width(20, tempTxt, true), width(12, mmTxt))
    local nextIcon, nextName, nextLine
    if d.next ~= nil then
        local nk
        nextIcon, nk = typeInfo(d.next.wt)
        nextName = L(nk)
        nextLine = self:fmtWhen(d.next.s, d.today)
        local p = fmtPrecip(d.next.sum ~= nil and d.next.sum.mm or 0, d.next.sum ~= nil and d.next.sum.cm or 0)
        if p ~= nil then nextLine = nextLine .. "  ~ " .. p end
    end
    local rightW = 0
    if nextName ~= nil then
        rightW = gap + pxw(1) + gap + pxw(28) + pxw(6) + math.max(width(14, nextName, true), width(12, nextLine))
    end
    -- (v1.0.0.63) ligne du dessous : vent et direction, « Clique-moi »
    local windTxt = fmtKmh(d.windSpeed)
    local from = compassFrom(d.windHeading)
    if from ~= nil then windTxt = windTxt .. "  " .. string.format(L("vtpas_wx_from"), from) end
    local hintTxt = L("vtpas_wx_clickMe")
    local row3H = py(22)
    local row3W = pxw(18) + pxw(6) + width(12, windTxt) + gap * 2 + width(12, hintTxt)
    local W = math.max(pad + iconW + pxw(6) + leftW + rightW + pad, pad + row3W + pad)

    local x, top
    if self.WIDGET_X ~= nil and self.WIDGET_Y ~= nil then
        x, top = self.WIDGET_X, self.WIDGET_Y + H + row3H
    elseif anchorRight ~= nil then
        x, top = anchorRight - pxw(14) - W, anchorTop
    else
        x, top = 1 - pxw(560) - W, 1 - py(20)
    end
    x = math.max(0, math.min(1 - W, x))
    local y = math.max(row3H, math.min(1 - H, top - H))
    local y3 = y - row3H
    self.widgetBox = { x = x, y = y3, w = W, h = H + row3H }

    drawFilledRect(x, y, W, H, 0, 0, 0, 0.6)
    drawFilledRect(x, y3, W, row3H, 0, 0, 0, 0.45)
    local cy = y + H * 0.5    -- milieu de la ligne principale
    local cx = x + pad
    icon(curIcon, cx, cy - py(iconPx) * 0.5, iconPx)
    cx = cx + iconW + pxw(6)
    local tc = C.white
    if d.temp ~= nil and d.temp <= 0 then tc = C.cold elseif d.temp ~= nil and d.temp >= 25 then tc = C.warm end
    text(cx, cy - py(2), 20, tempTxt, tc, nil, true)
    text(cx, cy - py(17), 12, mmTxt, C.gray)
    cx = cx + leftW
    if nextName ~= nil then
        cx = cx + gap
        drawFilledRect(cx, y + py(8), pxw(1), H - py(16), 1, 1, 1, 0.25)
        cx = cx + pxw(1) + gap
        icon(nextIcon, cx, cy - py(14), 28)
        cx = cx + pxw(28) + pxw(6)
        text(cx, cy + py(2), 14, nextName, C.white, nil, true)
        text(cx, cy - py(15), 12, nextLine, isPrecipType(d.next.wt) and C.blue or C.gray)
    end
    -- ligne du dessous
    local rx = x + pad
    if d.windHeading ~= nil then
        icon("arrow", rx, y3 + py(2), 18, -d.windHeading)
    end
    text(rx + pxw(24), y3 + py(6), 12, windTxt, C.white)
    text(x + W - pad, y3 + py(6), 12, hintTxt, C.title, RenderText.ALIGN_RIGHT, true)
end

-------------------------------------------------------------------------------
-- Touche (à pied et en véhicule)
-------------------------------------------------------------------------------

-- (v1.0.0.60) fenêtre ouverte : curseur de la souris affiché pour cliquer sur le X,
-- remis comme avant à la fermeture
function AS_Weather:setOpen(open)
    if open == self.isOpen then return end
    self.isOpen = open
    self.data = nil
    self.closeBox, self.closeHover = nil, false
    if g_inputBinding == nil or g_inputBinding.setShowMouseCursor == nil then return end
    if open then
        self.cursorBefore = g_inputBinding.getShowMouseCursor ~= nil and g_inputBinding:getShowMouseCursor() == true
        if not self.cursorBefore then pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true) end
    elseif self.cursorBefore == false then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
    end
end

function AS_Weather.onToggle()
    AS_Weather:setOpen(not AS_Weather.isOpen)
end

local function inBox(b, px, py_)
    return b ~= nil and px >= b.x and px <= b.x + b.w and py_ >= b.y and py_ <= b.y + b.h
end

function AS_Weather:mouseEvent(posX, posY, isDown, isUp, button)
    if self.isOpen then
        self.dragging = false
        local b = self.closeBox
        if b == nil then return end
        self.closeHover = inBox(b, posX, posY)
        if self.closeHover and isDown and button == Input.MOUSE_BUTTON_LEFT then
            self:setOpen(false)
        end
        return
    end
    -- (v1.0.0.61) mini-météo : glisser pour déplacer, simple clic pour ouvrir en grand
    if not self.WIDGET or g_inputBinding == nil or g_inputBinding.getShowMouseCursor == nil
        or g_inputBinding:getShowMouseCursor() ~= true then
        self.dragging = false
        return
    end
    local b = self.widgetBox
    if isDown and button == Input.MOUSE_BUTTON_LEFT and inBox(b, posX, posY) then
        self.dragging, self.dragMoved = true, false
        self.dragStartX, self.dragStartY = posX, posY
        self.dragDX, self.dragDY = posX - b.x, posY - b.y
        return
    end
    if self.dragging then
        if math.abs(posX - self.dragStartX) > 0.003 or math.abs(posY - self.dragStartY) > 0.005 then
            self.dragMoved = true
        end
        if self.dragMoved and b ~= nil then
            self.WIDGET_X = math.max(0, math.min(1 - b.w, posX - self.dragDX))
            self.WIDGET_Y = math.max(0, math.min(1 - b.h, posY - self.dragDY))
        end
        if isUp then
            self.dragging = false
            if self.dragMoved then
                if AS_Settings ~= nil then
                    AS_Settings.weatherPosX, AS_Settings.weatherPosY = self.WIDGET_X, self.WIDGET_Y
                    AS_Settings:save()
                end
            else
                self:setOpen(true)
            end
        end
    end
end

local function registerToggle()
    if InputAction == nil or InputAction.AS_WEATHER == nil then return nil end
    local _, id = g_inputBinding:registerActionEvent(InputAction.AS_WEATHER, AS_Weather, AS_Weather.onToggle, false, true, false, true)
    if id ~= nil then
        g_inputBinding:setActionEventText(id, L("input_AS_WEATHER"))
        g_inputBinding:setActionEventTextVisibility(id, false)
    end
    return id
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents ~= nil then
    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, function(self)
        if self.player == nil or not self.player.isOwner then return end
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        if AS_Weather.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(AS_Weather.actionEventId)
            AS_Weather.actionEventId = nil
        end
        AS_Weather.actionEventId = registerToggle()
        g_inputBinding:endActionEventsModification()
    end)
end

if Drivable ~= nil and Drivable.onRegisterActionEvents ~= nil then
    Drivable.onRegisterActionEvents = Utils.appendedFunction(Drivable.onRegisterActionEvents, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        if not self.isClient or not isActiveForInputIgnoreSelection then return end
        registerToggle()
    end)
end

function AS_Weather:delete()
    self.isOpen = false
    self.closeBox = nil
    self.data = nil
    self.actionEventId = nil
    for _, ov in pairs(self.overlays) do
        if ov then delete(ov) end
    end
    self.overlays = {}
end

addModEventListener(AS_Weather)
