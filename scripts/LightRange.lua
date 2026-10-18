-- AutoSwitch : phares des véhicules plus puissants
-- Fichier chargé par AutoSwitch.lua (après Common.lua).

local getVehicles = AS.getVehicles

-------------------------------------------------------------------------------
-- v1.0.0.75 : vrais faisceaux (sources de lumière des phares, phares de travail,
--   gyros) : portée multipliée par BEAM_RANGE et luminosité (couleur de la
--   lumière) par BEAM_GLOW, x2 par défaut, réglables. Tous les véhicules, le
--   véhicule conduit compris. Une couleur ou une portée nouvelle posée par le
--   jeu est reprise puis multipliée.
--   Les réglages de la 1.0.0.37 / 1.0.0.38 (distance et luminosité des halos)
--   sont retirés : sans effet visible en jeu.
-------------------------------------------------------------------------------
AS_LightRange = {}
AS_LightRange.BEAM_RANGE = 2     -- portée des vrais faisceaux (1 = jeu de base)
AS_LightRange.BEAM_GLOW  = 2     -- luminosité des vrais faisceaux (1 = jeu de base)
AS_LightRange.SCAN_MS = 2000     -- recherche des nouveaux véhicules
AS_LightRange.timer   = AS_LightRange.SCAN_MS
AS_LightRange.done    = {}       -- véhicule -> true quand ses lumières sont trouvées
AS_LightRange.beams   = {}       -- véhicule -> { { node, range, rangeW, r, g, b, rW, gW, bW } }

local function walk(node, beams)
    if getHasClassId(node, ClassIds.LIGHT_SOURCE) then
        beams[#beams + 1] = { node = node, range = 0, rangeW = -1, r = 0, g = 0, b = 0, rW = -1, gW = -1, bW = -1 }
    end
    for i = 0, getNumOfChildren(node) - 1 do
        walk(getChildAt(node, i), beams)
    end
end

function AS_LightRange:processVehicle(vehicle)
    if vehicle.spec_lights == nil or vehicle.components == nil then return end
    local beams = {}
    for _, comp in ipairs(vehicle.components) do
        if comp.node ~= nil and comp.node ~= 0 then
            walk(comp.node, beams)
        end
    end
    if #beams > 0 then self.beams[vehicle] = beams end
    self.done[vehicle] = true
end

function AS_LightRange:scan()
    for vehicle in pairs(self.done) do
        if vehicle.isDeleted then
            self.done[vehicle] = nil
            self.beams[vehicle] = nil
        end
    end
    for _, vehicle in pairs(getVehicles()) do
        if not vehicle.isDeleted and self.done[vehicle] == nil then
            pcall(self.processVehicle, self, vehicle)
        end
    end
end

local function differs(a, b)
    return math.abs(a - b) > 0.0001
end

-- Une valeur posée par le jeu (différente de la nôtre) devient la base,
-- puis on écrit base x facteur
function AS_LightRange:updateBeams()
    local kr, kg = self.BEAM_RANGE, self.BEAM_GLOW
    for vehicle, list in pairs(self.beams) do
        if vehicle.isDeleted then
            self.beams[vehicle] = nil
        else
            for _, l in ipairs(list) do
                local range = getLightRange(l.node)
                if range ~= nil and differs(range, l.rangeW) then
                    l.range = range
                    l.rangeW = range * kr
                    if kr ~= 1 then setLightRange(l.node, l.rangeW) end
                end
                local r, g, b = getLightColor(l.node)
                if r ~= nil and (differs(r, l.rW) or differs(g, l.gW) or differs(b, l.bW)) then
                    l.r, l.g, l.b = r, g, b
                    l.rW, l.gW, l.bW = r * kg, g * kg, b * kg
                    if kg ~= 1 then setLightColor(l.node, l.rW, l.gW, l.bW) end
                end
            end
        end
    end
end

-- Nouveaux facteurs (menu) : chaque faisceau reprend sa valeur du jeu x facteur
function AS_LightRange:setBeams(range, glow)
    range, glow = math.max(1, range or 1), math.max(1, glow or 1)
    if range == self.BEAM_RANGE and glow == self.BEAM_GLOW then return end
    self.BEAM_RANGE, self.BEAM_GLOW = range, glow
    for _, list in pairs(self.beams) do
        for _, l in ipairs(list) do
            if entityExists(l.node) and l.rangeW >= 0 then
                l.rangeW = l.range * range
                setLightRange(l.node, l.rangeW)
                l.rW, l.gW, l.bW = l.r * glow, l.g * glow, l.b * glow
                setLightColor(l.node, l.rW, l.gW, l.bW)
            end
        end
    end
end

function AS_LightRange:update(dt)
    if g_currentMission == nil or g_client == nil then return end
    pcall(self.updateBeams, self)
    self.timer = self.timer + (dt or 0)
    if self.timer < self.SCAN_MS then return end
    self.timer = 0
    pcall(self.scan, self)
end

function AS_LightRange:deleteMap()
    self.timer = self.SCAN_MS
    self.done, self.beams = {}, {}
end

addModEventListener(AS_LightRange)
