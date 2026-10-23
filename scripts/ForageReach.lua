-- AutoSwitch : portée de la goulotte des ensileuses
-- Fichier chargé par AutoSwitch.lua (après Common.lua), seulement si AutoDrive est présent
-- (liste « cuts » de REQUIRED).

local getVehicles, isForage = AS.getVehicles, AS.isForage

-------------------------------------------------------------------------------
-- v1.0.1.9 : avec AutoDrive, la goulotte des ensileuses remplit la benne de plus loin.
--   Chaque point de déchargement (spec_dischargeable.dischargeNodes) voit sa
--   distance maximale (maxDistance, rayon qui cherche la benne) allongée de EXTRA_M.
--   Aucune fonction du jeu n'est remplacée : la valeur est modifiée une fois par
--   ensileuse, à son apparition.
-------------------------------------------------------------------------------
AS_ForageReach = {}
AS_ForageReach.EXTRA_M = 5       -- mètres ajoutés à la portée
AS_ForageReach.SCAN_MS = 2000    -- recherche des nouvelles ensileuses
AS_ForageReach.timer   = AS_ForageReach.SCAN_MS
AS_ForageReach.done    = {}      -- véhicule -> true quand traité

local function log(fmt, ...)
    print("[AS_ForageReach] " .. string.format(fmt, ...))
end

function AS_ForageReach:processVehicle(vehicle)
    self.done[vehicle] = true
    if not isForage(vehicle) then return end
    local spec = vehicle.spec_dischargeable
    if spec == nil or spec.dischargeNodes == nil then return end
    for i, node in ipairs(spec.dischargeNodes) do
        if type(node.maxDistance) == "number" and node.asReachBase == nil then
            node.asReachBase = node.maxDistance
            node.maxDistance = node.maxDistance + self.EXTRA_M
            log("%s, goulotte %d : portée %.1f m -> %.1f m", tostring(vehicle:getName()), i, node.asReachBase, node.maxDistance)
        end
    end
end

function AS_ForageReach:scan()
    for vehicle in pairs(self.done) do
        if vehicle.isDeleted then self.done[vehicle] = nil end
    end
    for _, vehicle in pairs(getVehicles()) do
        if not vehicle.isDeleted and self.done[vehicle] == nil then
            pcall(self.processVehicle, self, vehicle)
        end
    end
end

function AS_ForageReach:update(dt)
    if g_currentMission == nil then return end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.SCAN_MS then return end
    self.timer = 0
    pcall(self.scan, self)
end

function AS_ForageReach:deleteMap()
    self.timer = self.SCAN_MS
    self.done = {}
end

addModEventListener(AS_ForageReach)
