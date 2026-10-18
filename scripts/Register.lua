-- AutoSwitch : registre des pesées et des ventes (Ctrl droit + R)
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

-------------------------------------------------------------------------------
-- v1.0.0.79 : pesées : colonnes « Lieu » (nom du pont-bascule) et « Par » (AutoDrive ou le
--   joueur qui s'est arrêté lui-même sur le pont), envoyées par AutoDrive Addon.
--   Croix au bout de chaque pesée / vente pour la supprimer (2e clic pour confirmer).
-- v1.0.0.74 : registre gardé avec la partie (AutoSwitch_register.xml dans le dossier
--   de la sauvegarde).
--   Ventes : chaque vente du jeu (SellingStation:sellFillType), produit, quantité,
--   argent reçu (différence du solde de la ferme) et point de vente. Le déchargement
--   d'une benne arrive par petits morceaux : ils sont regroupés en une seule ligne
--   (même ferme, même point de vente, même produit, moins de 2 min d'écart).
--   Pesées : envoyées par AutoDrive Addon (pont-bascule) via AS_Register:addWeighing.
--   Fenêtre : onglets Pesées / Ventes / Totaux (par mois et par produit),
--   molette pour défiler, X pour fermer.
-------------------------------------------------------------------------------
AS_Register = {}
AS_Register.FILE_NAME   = "AutoSwitch_register.xml"
AS_Register.MAX_ENTRIES = 1000
AS_Register.MERGE_MS    = 120000
AS_Register.ROWS        = 15
AS_Register.CONFIRM_MS  = 3000   -- délai pour confirmer une suppression

AS_Register.weighings = {}
AS_Register.sales = {}
AS_Register.isOpen = false
AS_Register.tab = 1
AS_Register.scroll = 0
AS_Register.actionEventId = nil
AS_Register.loaded = false

-- Langue du jeu : plusieurs sources (g_languageShortName n'est pas toujours défini),
-- lue au moment de l'affichage puis gardée
local frenchCache = nil
local function isFrench()
    if frenchCache ~= nil then return frenchCache end
    local french, known = false, false
    if getLanguage ~= nil and getLanguageCode ~= nil then
        local ok, code = pcall(function() return getLanguageCode(getLanguage()) end)
        if ok and type(code) == "string" then
            known = true
            french = code:lower():sub(1, 2) == "fr"
        end
    end
    if not french and g_languageShortName ~= nil then
        known = true
        french = g_languageShortName == "fr"
    end
    if not french and g_i18n ~= nil and g_i18n.getText ~= nil then
        local ok, t = pcall(g_i18n.getText, g_i18n, "ui_yes")
        if ok and type(t) == "string" and not t:find("Missing") then
            known = true
            french = t == "Oui"
        end
    end
    if known and g_currentMission ~= nil then frenchCache = french end
    return french
end
local function T(fr, en)
    if isFrench() then return fr end
    return en
end

local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_Register.FILE_NAME
end

-- date du jeu au moment de l'enregistrement
local function gameDate()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return { day = 0, period = 0, year = 0, dayInPeriod = 0, minutes = 0 } end
    return {
        day = env.currentDay or 0,
        period = env.currentPeriod or 0,
        year = env.currentYear or 0,
        dayInPeriod = env.currentDayInPeriod or 0,
        minutes = math.floor((env.dayTime or 0) / 60000),
    }
end

local function fillTypeTitle(name)
    local ft = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByName(name) or nil
    if ft ~= nil and ft.title ~= nil then return ft.title end
    return tostring(name)
end

local function periodName(period)
    if g_i18n ~= nil and g_i18n.formatPeriod ~= nil then
        local ok, s = pcall(g_i18n.formatPeriod, g_i18n, period, false)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return T("Mois ", "Month ") .. tostring(period)
end

local function fmtDate(e)
    return string.format("%s%d %s %s%d  %02dh%02d", T("J", "D"), e.dayInPeriod or 0, periodName(e.period or 0),
        T("an ", "y"), e.year or 0, math.floor((e.minutes or 0) / 60), (e.minutes or 0) % 60)
end

local function fmtTons(kg)
    local s = string.format("%.1f t", (kg or 0) / 1000)
    if isFrench() then s = s:gsub("%.", ",") end
    return s
end

local function fmtLiters(l)
    local s = string.format("%d L", math.floor((l or 0) + 0.5))
    return s
end

local function fmtMoney(v)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local ok, s = pcall(g_i18n.formatMoney, g_i18n, v or 0, 0, true, true)
        if ok and type(s) == "string" then return s end
    end
    return string.format("%d €", math.floor((v or 0) + 0.5))
end

local function trim(list)
    while #list > AS_Register.MAX_ENTRIES do
        table.remove(list, 1)
    end
end

local function currentFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local ok, id = pcall(g_currentMission.getFarmId, g_currentMission)
        if ok and id ~= nil then return id end
    end
    return 1
end

-------------------------------------------------------------------------------
-- Enregistrement
-------------------------------------------------------------------------------

-- appelé par AutoDrive Addon : { vehicle, fillType (nom), load (kg), total (kg), farmId }
function AS_Register:addWeighing(info)
    if type(info) ~= "table" then return end
    local e = gameDate()
    e.vehicle = tostring(info.vehicle or "?")
    e.site = info.site ~= nil and tostring(info.site) or nil
    e.driver = info.driver ~= nil and tostring(info.driver) or nil
    e.fillType = info.fillType
    e.load = tonumber(info.load) or 0
    e.total = tonumber(info.total) or 0
    e.farmId = info.farmId or currentFarmId()
    table.insert(self.weighings, e)
    trim(self.weighings)
end

function AS_Register:addSale(farmId, fillTypeIndex, liters, money, station)
    if liters <= 0 then return end
    local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if ft == nil then return end
    local kg = liters * (ft.massPerLiter or 0) * 1000
    local last = self.sales[#self.sales]
    if last ~= nil and last.farmId == farmId and last.fillType == ft.name and last.station == station
        and last.realTime ~= nil and g_time - last.realTime < self.MERGE_MS then
        last.liters = last.liters + liters
        last.kg = last.kg + kg
        last.money = last.money + money
        last.realTime = g_time
        return
    end
    local e = gameDate()
    e.farmId = farmId
    e.fillType = ft.name
    e.liters = liters
    e.kg = kg
    e.money = money
    e.station = station
    e.realTime = g_time
    table.insert(self.sales, e)
    trim(self.sales)
end

local function stationName(station)
    local p = station.owningPlaceable
    if p ~= nil and p.getName ~= nil then
        local ok, n = pcall(p.getName, p)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return station.stationName or "?"
end

local function farmMoney(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    return farm ~= nil and farm.money or nil
end

if SellingStation ~= nil and SellingStation.sellFillType ~= nil then
    SellingStation.sellFillType = Utils.overwrittenFunction(SellingStation.sellFillType,
        function(self, superFunc, farmId, fillDelta, fillTypeIndex, ...)
            local before = farmMoney(farmId)
            local moved = superFunc(self, farmId, fillDelta, fillTypeIndex, ...)
            local ok, err = pcall(function()
                if g_currentMission == nil or not g_currentMission:getIsServer() then return end
                local liters = tonumber(moved) or 0
                local after = farmMoney(farmId)
                local money = (before ~= nil and after ~= nil) and (after - before) or 0
                AS_Register:addSale(farmId, fillTypeIndex, liters, money, stationName(self))
            end)
            if not ok and not AS_Register.loggedSaleError then
                AS_Register.loggedSaleError = true
                print("[AS_Register] erreur vente : " .. tostring(err))
            end
            return moved
        end)
else
    print("[AS_Register] SellingStation.sellFillType introuvable : ventes non enregistrées")
end

-------------------------------------------------------------------------------
-- Sauvegarde / chargement
-------------------------------------------------------------------------------

local function writeEntry(xml, key, e, fields)
    setXMLInt(xml, key .. "#day", e.day or 0)
    setXMLInt(xml, key .. "#period", e.period or 0)
    setXMLInt(xml, key .. "#year", e.year or 0)
    setXMLInt(xml, key .. "#dayInPeriod", e.dayInPeriod or 0)
    setXMLInt(xml, key .. "#minutes", e.minutes or 0)
    setXMLInt(xml, key .. "#farmId", e.farmId or 1)
    for name, kind in pairs(fields) do
        if e[name] ~= nil then
            if kind == "s" then setXMLString(xml, key .. "#" .. name, tostring(e[name]))
            else setXMLFloat(xml, key .. "#" .. name, e[name]) end
        end
    end
end

local function readEntry(xml, key, fields)
    local e = {
        day = getXMLInt(xml, key .. "#day") or 0,
        period = getXMLInt(xml, key .. "#period") or 0,
        year = getXMLInt(xml, key .. "#year") or 0,
        dayInPeriod = getXMLInt(xml, key .. "#dayInPeriod") or 0,
        minutes = getXMLInt(xml, key .. "#minutes") or 0,
        farmId = getXMLInt(xml, key .. "#farmId") or 1,
    }
    for name, kind in pairs(fields) do
        if kind == "s" then e[name] = getXMLString(xml, key .. "#" .. name)
        else e[name] = getXMLFloat(xml, key .. "#" .. name) end
    end
    return e
end

local WEIGH_FIELDS = { vehicle = "s", site = "s", driver = "s", fillType = "s", load = "f", total = "f" }
local SALE_FIELDS = { fillType = "s", station = "s", liters = "f", kg = "f", money = "f" }

function AS_Register:save()
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asRegister", path, "register")
    if xml == nil or xml == 0 then return end
    for i, e in ipairs(self.weighings) do
        writeEntry(xml, string.format("register.weighings.weighing(%d)", i - 1), e, WEIGH_FIELDS)
    end
    for i, e in ipairs(self.sales) do
        writeEntry(xml, string.format("register.sales.sale(%d)", i - 1), e, SALE_FIELDS)
    end
    saveXMLFile(xml)
    delete(xml)
end

function AS_Register:load()
    self.weighings, self.sales = {}, {}
    local path = savegamePath()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("asRegister", path)
    if xml == nil or xml == 0 then return end
    local i = 0
    while true do
        local key = string.format("register.weighings.weighing(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        table.insert(self.weighings, readEntry(xml, key, WEIGH_FIELDS))
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("register.sales.sale(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        table.insert(self.sales, readEntry(xml, key, SALE_FIELDS))
        i = i + 1
    end
    delete(xml)
    print(string.format("[AS_Register] registre chargé : %d pesées, %d ventes", #self.weighings, #self.sales))
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_Register.save, AS_Register)
        if not ok then print("[AS_Register] ERREUR sauvegarde : " .. tostring(err)) end
    end)
end

function AS_Register:loadMap()
    local ok, err = pcall(self.load, self)
    if not ok then print("[AS_Register] ERREUR chargement : " .. tostring(err)) end
end

function AS_Register:deleteMap()
    self.weighings, self.sales = {}, {}
    self.isOpen = false
end

-------------------------------------------------------------------------------
-- Fenêtre
-------------------------------------------------------------------------------

local C = {
    white = { 1, 1, 1, 1 },
    gray  = { 0.70, 0.73, 0.78, 1 },
    title = { 1.00, 0.80, 0.30, 1 },
    green = { 0.55, 0.90, 0.45, 1 },
}

local function uiScale()
    local s = 1
    if g_gameSettings ~= nil and g_gameSettings.getValue ~= nil then
        local ok, v = pcall(g_gameSettings.getValue, g_gameSettings, "uiScale")
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    return s
end

-- lignes de l'onglet : { colonnes... }, du plus récent au plus ancien
function AS_Register:getRows()
    local farmId = currentFarmId()
    local rows = {}
    if self.tab == 1 then
        for i = #self.weighings, 1, -1 do
            local e = self.weighings[i]
            if e.farmId == farmId then
                table.insert(rows, { fmtDate(e), (e.site ~= nil and e.site ~= "") and e.site or "-", e.driver or "AutoDrive", e.vehicle or "?", e.fillType ~= nil and fillTypeTitle(e.fillType) or "-",
                    fmtTons(e.load), fmtTons(e.total), entry = e, list = self.weighings })
            end
        end
    elseif self.tab == 2 then
        for i = #self.sales, 1, -1 do
            local e = self.sales[i]
            if e.farmId == farmId then
                table.insert(rows, { fmtDate(e), fillTypeTitle(e.fillType), fmtLiters(e.liters) .. "  (" .. fmtTons(e.kg) .. ")",
                    fmtMoney(e.money), e.station or "?", entry = e, list = self.sales })
            end
        end
    else
        -- totaux par mois (le plus récent d'abord) puis par produit
        local groups, order = {}, {}
        for _, e in ipairs(self.sales) do
            if e.farmId == farmId then
                local mk = (e.year or 0) * 100 + (e.period or 0)
                local g = groups[mk]
                if g == nil then
                    g = { year = e.year, period = e.period, products = {}, names = {}, kg = 0, money = 0 }
                    groups[mk] = g
                    table.insert(order, mk)
                end
                local p = g.products[e.fillType]
                if p == nil then
                    p = { liters = 0, kg = 0, money = 0 }
                    g.products[e.fillType] = p
                    table.insert(g.names, e.fillType)
                end
                p.liters, p.kg, p.money = p.liters + e.liters, p.kg + e.kg, p.money + e.money
                g.kg, g.money = g.kg + e.kg, g.money + e.money
            end
        end
        table.sort(order, function(a, b) return a > b end)
        for _, mk in ipairs(order) do
            local g = groups[mk]
            table.insert(rows, { periodName(g.period) .. " " .. T("an ", "y") .. tostring(g.year), T("Total", "Total"), "", fmtTons(g.kg), fmtMoney(g.money), bold = true })
            for _, name in ipairs(g.names) do
                local p = g.products[name]
                table.insert(rows, { "", fillTypeTitle(name), fmtLiters(p.liters), fmtTons(p.kg), fmtMoney(p.money) })
            end
        end
    end
    return rows
end

function AS_Register:draw()
    if not self.isOpen or g_currentMission == nil then return end
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then return end
    local ok, err = pcall(self.drawPanel, self)
    if not ok and not self.loggedDrawError then
        self.loggedDrawError = true
        print("[AS_Register] erreur d'affichage : " .. tostring(err))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

function AS_Register:drawPanel()
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

    local rowH = 26
    local W = pxw(1240)
    local H = py(44 + 40 + 30 + rowH * self.ROWS + 34)
    local x0, y0 = 0.5 - W * 0.5, 0.5 - H * 0.5
    local top = y0 + H
    local pad = pxw(18)

    drawFilledRect(x0, y0, W, H, 0.05, 0.07, 0.10, 0.90)
    drawFilledRect(x0, top - py(44), W, py(44), 0.10, 0.14, 0.20, 0.95)
    text(x0 + pad, top - py(31), 20, T("Registre", "Register"), C.title, nil, true)

    -- bouton X
    local bs, bw = py(30), pxw(30)
    local bx, by = x0 + W - pxw(8) - bw, top - py(7) - bs
    self.closeBox = { x = bx, y = by, w = bw, h = bs }
    drawFilledRect(bx, by, bw, bs, 0.75, 0.18, 0.15, self.hover == "close" and 1 or 0.85)
    text(bx + bw * 0.5, by + py(7), 18, "X", C.white, RenderText.ALIGN_CENTER, true)

    -- onglets
    local tabs = { T("Pesées", "Weighings"), T("Ventes", "Sales"), T("Totaux par mois", "Monthly totals") }
    self.tabBoxes = {}
    local tx = x0 + pad
    local ty = top - py(44) - py(36)
    for i, name in ipairs(tabs) do
        local tw = pxw(200)
        local active = i == self.tab
        -- (couleurs sombres : à l'écran le jeu les éclaircit beaucoup)
        local shade = active and 0.10 or (self.hover == i and 0.07 or 0.03)
        drawFilledRect(tx, ty, tw, py(30), shade, shade * 1.3, shade * 1.8, 0.95)
        if active then drawFilledRect(tx, ty, tw, py(3), 1.00, 0.80, 0.30, 1) end
        text(tx + tw * 0.5, ty + py(8), 16, name, active and C.title or C.gray, RenderText.ALIGN_CENTER, active)
        self.tabBoxes[i] = { x = tx, y = ty, w = tw, h = py(30) }
        tx = tx + tw + pxw(8)
    end

    -- colonnes
    local heads, cols
    if self.tab == 1 then
        heads = { T("Date", "Date"), T("Lieu", "Place"), T("Par", "By"), T("Véhicule", "Vehicle"), T("Produit", "Product"), T("Chargement", "Load"), T("Poids total", "Total weight") }
        cols = { 0, 210, 410, 540, 830, 970, 1090 }
    elseif self.tab == 2 then
        heads = { T("Date", "Date"), T("Produit", "Product"), T("Quantité", "Quantity"), T("Montant", "Amount"), T("Point de vente", "Selling point") }
        cols = { 0, 230, 380, 590, 700 }
    else
        heads = { T("Mois", "Month"), T("Produit", "Product"), T("Litres", "Liters"), T("Poids", "Weight"), T("Montant", "Amount") }
        cols = { 0, 230, 420, 580, 720 }
    end
    local y = ty - py(30)
    for i, h in ipairs(heads) do
        text(x0 + pad + pxw(cols[i]), y + py(6), 15, h, C.gray, nil, true)
    end
    drawFilledRect(x0 + pad, y + py(2), W - 2 * pad, py(1), 1, 1, 1, 0.2)

    local rows = self:getRows()
    local maxScroll = math.max(0, #rows - self.ROWS)
    self.scroll = math.max(0, math.min(self.scroll, maxScroll))
    if #rows == 0 then
        text(x0 + pad, y - py(rowH), 16, T("Rien d'enregistré pour le moment.", "Nothing recorded yet."), C.gray)
    end
    -- (v1.0.0.79) croix au bout de la ligne : 1er clic = « Supprimer ? », 2e clic = supprimée
    self.deleteBoxes = {}
    if self.armed ~= nil and g_time - self.armedTime > self.CONFIRM_MS then self.armed = nil end
    for r = 1, self.ROWS do
        local row = rows[r + self.scroll]
        if row == nil then break end
        y = y - py(rowH)
        if r % 2 == 0 then drawFilledRect(x0 + pad, y, W - 2 * pad, py(rowH), 1, 1, 1, 0.04) end
        local armed = row.entry ~= nil and row.entry == self.armed
        if armed then drawFilledRect(x0 + pad, y, W - 2 * pad, py(rowH), 0.75, 0.18, 0.15, 0.25) end
        for i, v in ipairs(row) do
            text(x0 + pad + pxw(cols[i]), y + py(6), 15, v, row.bold and C.title or C.white, nil, row.bold)
        end
        if row.entry ~= nil then
            local bw = armed and pxw(110) or pxw(24)
            local bx, by = x0 + W - pad - bw, y + py(2)
            local hover = self.hover == "del" .. r
            drawFilledRect(bx, by, bw, py(rowH - 4), 0.75, 0.18, 0.15, (armed or hover) and 1 or 0.55)
            text(bx + bw * 0.5, by + py(4), 14, armed and T("Supprimer ?", "Delete?") or "X", C.white, RenderText.ALIGN_CENTER, true)
            self.deleteBoxes[r] = { x = bx, y = by, w = bw, h = py(rowH - 4), entry = row.entry, list = row.list }
        end
    end

    -- bas : nombre de lignes / défilement
    local info = string.format("%d %s", #rows, T("lignes", "rows"))
    if maxScroll > 0 then info = info .. "  -  " .. T("molette pour défiler", "scroll with the mouse wheel") end
    text(x0 + W - pad, y0 + py(12), 14, info, C.gray, RenderText.ALIGN_RIGHT)
end

function AS_Register:setOpen(open)
    if open == self.isOpen then return end
    self.isOpen = open
    self.scroll = 0
    self.closeBox, self.tabBoxes, self.hover = nil, nil, nil
    if g_inputBinding == nil or g_inputBinding.setShowMouseCursor == nil then return end
    if open then
        if AS_Weather ~= nil and AS_Weather.isOpen then AS_Weather:setOpen(false) end
        self.cursorBefore = g_inputBinding.getShowMouseCursor ~= nil and g_inputBinding:getShowMouseCursor() == true
        if not self.cursorBefore then pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true) end
    elseif self.cursorBefore == false then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
    end
end

function AS_Register.onToggle()
    AS_Register:setOpen(not AS_Register.isOpen)
end

local function inBox(b, px, py_)
    return b ~= nil and px >= b.x and px <= b.x + b.w and py_ >= b.y and py_ <= b.y + b.h
end

function AS_Register:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isOpen then return end
    self.hover = nil
    if inBox(self.closeBox, posX, posY) then self.hover = "close" end
    for i, b in ipairs(self.tabBoxes or {}) do
        if inBox(b, posX, posY) then self.hover = i end
    end
    local delBox = nil
    for r, b in pairs(self.deleteBoxes or {}) do
        if inBox(b, posX, posY) then self.hover, delBox = "del" .. r, b end
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        if delBox ~= nil then
            if self.armed == delBox.entry then
                for i, e in ipairs(delBox.list) do
                    if e == delBox.entry then
                        table.remove(delBox.list, i)
                        break
                    end
                end
                self.armed = nil
            else
                self.armed, self.armedTime = delBox.entry, g_time
            end
        elseif self.hover == "close" then
            self:setOpen(false)
        elseif type(self.hover) == "number" then
            self.tab, self.scroll, self.armed = self.hover, 0, nil
        end
    elseif isDown and button == Input.MOUSE_BUTTON_WHEEL_UP then
        self.scroll = math.max(0, self.scroll - 3)
    elseif isDown and button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        self.scroll = self.scroll + 3
    end
end

local function registerToggle()
    if InputAction == nil or InputAction.AS_REGISTER == nil then return nil end
    local _, id = g_inputBinding:registerActionEvent(InputAction.AS_REGISTER, AS_Register, AS_Register.onToggle, false, true, false, true)
    if id ~= nil then
        g_inputBinding:setActionEventText(id, AS.L("input_AS_REGISTER"))
        g_inputBinding:setActionEventTextVisibility(id, false)
    end
    return id
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents ~= nil then
    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, function(self)
        if self.player == nil or not self.player.isOwner then return end
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        if AS_Register.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(AS_Register.actionEventId)
            AS_Register.actionEventId = nil
        end
        AS_Register.actionEventId = registerToggle()
        g_inputBinding:endActionEventsModification()
    end)
end

if Drivable ~= nil and Drivable.onRegisterActionEvents ~= nil then
    Drivable.onRegisterActionEvents = Utils.appendedFunction(Drivable.onRegisterActionEvents, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        if not self.isClient or not isActiveForInputIgnoreSelection then return end
        registerToggle()
    end)
end

function AS_Register:delete()
    self.isOpen = false
    self.actionEventId = nil
end

addModEventListener(AS_Register)
