-- AutoSwitch : capteur des voitures du trafic plus étroit
-- Le moteur lit la largeur de détection de chaque voiture dans son fichier
-- (vehicle.assets.collisionGeometry#width) au moment de createTrafficSystem.
-- On lui donne une copie du fichier de trafic dont les voitures ont une largeur
-- réduite (copies écrites dans modSettings/FS25_AutoSwitch/traffic).
-- Couvre le trafic de la carte et celui ajouté par Traffic Density Control.
-- Les fichiers du jeu ne sont pas modifiés.
AS_TrafficSensor = {}
AS_TrafficSensor.FACTOR = 0.8      -- 80 % de la largeur d'origine
AS_TrafficSensor.count  = 0

local TAG = "[AS_TrafficSensor] "
local function log(fmt, ...) print(TAG .. string.format(fmt, ...)) end

local function gameGlobals()
    local mt = getmetatable(_G)
    if mt ~= nil and type(mt.__index) == "table" then return mt.__index end
    return _G
end

local function outDir()
    local base = getUserProfileAppPath() .. "modSettings/"
    createFolder(base)
    base = base .. "FS25_AutoSwitch/"
    createFolder(base)
    base = base .. "traffic/"
    createFolder(base)
    return base
end

local function isAbsolute(path)
    return path:sub(1, 1) == "$" or path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" or path:match("^%a:") ~= nil
end

local function resolve(path, dir)
    if path == nil or path == "" or isAbsolute(path) then return path end
    return Utils.getFilename(path, dir)
end

function AS_TrafficSensor:prepareVehicle(vehicleFilename, index, dir)
    local xml = XMLFile.load("AS_TrafficSensorVehicle", vehicleFilename)
    if xml == nil then
        log("lecture impossible : %s", tostring(vehicleFilename))
        return nil
    end
    local width = xml:getFloat("vehicle.assets.collisionGeometry#width")
    if width == nil then
        xml:delete()
        return nil
    end
    local vdir = Utils.getDirectory(vehicleFilename)
    for _, key in ipairs({ "vehicle.assets#filename", "vehicle.assets#filenameParked",
                           "vehicle.assets.sounds.motor#filename", "vehicle.assets.sounds.honk#filename" }) do
        local p = xml:getString(key)
        if p ~= nil and p ~= "" then xml:setString(key, resolve(p, vdir)) end
    end
    local newWidth = width * self.FACTOR
    xml:setFloat("vehicle.assets.collisionGeometry#width", newWidth)
    local out = dir .. string.format("vehicle_%d_%02d.xml", self.count, index)
    local ok = xml:saveTo(out, false, true)
    xml:delete()
    if not ok then
        log("écriture impossible : %s", out)
        return nil
    end
    return out
end

function AS_TrafficSensor:prepare(xmlFilename)
    if type(xmlFilename) ~= "string" or xmlFilename == "" or self.FACTOR >= 0.999 then return xmlFilename end
    local xml = XMLFile.load("AS_TrafficSensorTraffic", xmlFilename)
    if xml == nil then
        log("lecture impossible : %s", tostring(xmlFilename))
        return xmlFilename
    end
    self.count = self.count + 1
    local dir = outDir()
    local tdir = Utils.getDirectory(xmlFilename)
    local lp = xml:getString("trafficSystem#licensePlates")
    if lp ~= nil and lp ~= "" then xml:setString("trafficSystem#licensePlates", resolve(lp, tdir)) end
    local n, changed = 0, 0
    for _, key in xml:iterator("trafficSystem.vehicles.vehicle") do
        n = n + 1
        local vf = xml:getString(key .. "#filename")
        if vf ~= nil and vf ~= "" then
            local out = self:prepareVehicle(isAbsolute(vf) and vf:sub(1, 1) ~= "$" and vf or Utils.getFilename(vf, tdir), n, dir)
            if out ~= nil then
                xml:setString(key .. "#filename", out)
                changed = changed + 1
            end
        end
    end
    local out = dir .. string.format("trafficSystem_%d.xml", self.count)
    local ok = xml:saveTo(out, false, true)
    xml:delete()
    if not ok then
        log("écriture impossible : %s", out)
        return xmlFilename
    end
    log("%s : %d/%d voitures à %d %% -> %s", xmlFilename, changed, n, math.floor(self.FACTOR * 100 + 0.5), out)
    return out
end

local G = gameGlobals()
local origCreate = G.createTrafficSystem
if type(origCreate) == "function" then
    rawset(G, "createTrafficSystem", function(xmlFilename, ...)
        local ok, newName = pcall(AS_TrafficSensor.prepare, AS_TrafficSensor, xmlFilename)
        if not ok then
            log("erreur : %s", tostring(newName))
            newName = xmlFilename
        end
        return origCreate(newName, ...)
    end)
    print("[AutoSwitch] capteur des voitures du trafic accroché")
else
    print("[AutoSwitch] capteur des voitures : createTrafficSystem absent")
end
