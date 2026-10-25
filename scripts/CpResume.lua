-- AutoSwitch : Courseplay relancé au chargement de la partie
-- Fichier chargé par AutoSwitch.lua (après Common.lua, avant Settings.lua).

-------------------------------------------------------------------------------
-- v1.0.3.0 : Courseplay garde la course et le dernier point de chaque véhicule
--   dans la partie, mais empêche exprès le jeu de relancer l'ouvrier au
--   chargement (AIFieldWorker.saveToXMLFile met isActive à false).
--   Ce module note, quand le jeu sauvegarde, les véhicules où Courseplay roulait
--   (savegameX/autoSwitchCpResume.xml) : type de travail et, pour le travail au
--   champ, le point de la course où il en était. Au chargement, START_DELAY après
--   l'arrivée en jeu, il relance chacun d'eux :
--   - travail au champ : au point exact de la course où il roulait à la sauvegarde
--     (sinon au point le plus proche) ;
--   - déchargeur, ramasseur de balles, silo : avec les réglages gardés par CP.
--   Les véhicules pilotés par AutoDrive ne sont pas notés (AutoDrive les gère).
--   Un véhicule déjà relancé à la main est laissé tel quel.
--   Serveur seulement (les ouvriers tournent sur le serveur).
-- v1.0.3.0 (2) : toujours le point le plus proche (Fabien : le « dernier point » de CP
--   le faisait repartir en arrière). Lignes [AS_CpResume] toujours écrites dans log.txt.
-- v1.0.3.0 (3) : le plus proche prenait la mauvaise ligne là où les lignes se croisent.
--   On note le point exact de la course (sans le recul de 10 m que CP ajoute) et on
--   repart de ce point-là.
-------------------------------------------------------------------------------
AS_CpResume = {}
AS_CpResume.ENABLED      = true
AS_CpResume.FILE_NAME    = "autoSwitchCpResume.xml"
AS_CpResume.START_DELAY  = 10000   -- ms après l'arrivée en jeu
AS_CpResume.OTHERS_DELAY = 3000    -- ms de plus pour les déchargeurs (moissonneuses d'abord)
AS_CpResume.RETRY_MS     = 2000
AS_CpResume.GIVE_UP_MS   = 60000   -- abandon si le véhicule n'est toujours pas prêt
AS_CpResume.RESTORE_MS   = 5000    -- remise du point de départ choisi dans le HUD CP

-- valeurs de CpFieldWorkJobParameters (config/jobParameters/FieldWorkJobParameterSetup.xml)
AS_CpResume.START_AT_NEAREST = 1
AS_CpResume.START_AT_LAST    = 3

-- nom du travail CP -> spécialisation qui porte le job de démarrage (spec.cpJob)
AS_CpResume.JOBS = {
    FIELDWORK_CP        = "spec_cpAIFieldWorker",
    COMBINE_UNLOADER_CP = "spec_cpAICombineUnloader",
    BALE_FINDER_CP      = "spec_cpAIBaleFinder",
    BUNKER_SILO_CP      = "spec_cpAIBunkerSiloWorker",
    SILO_LOADER_CP      = "spec_cpAISiloLoaderWorker",
}

AS_CpResume.pending = nil   -- nil = fichier pas encore lu ; liste { id, job, wp }
AS_CpResume.timer = 0
AS_CpResume.restores = {}

local function log(fmt, ...)
    local p = AS.rawPrint or print
    p("[AS_CpResume] " .. string.format(fmt, ...))
end

local function savegamePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local dir = mi ~= nil and mi.savegameDirectory or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "/" .. AS_CpResume.FILE_NAME
end

local function vehicleList()
    local vs = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    return vs ~= nil and vs.vehicles or {}
end

local function vehicleName(v)
    local ok, n = pcall(v.getFullName, v)
    return ok and tostring(n) or tostring(v.configFileName)
end

-- travail au champ : point exact de la course où l'ouvrier en est (dernier point passé,
-- sinon point visé), sans le recul de CP (getBestWaypointToContinueFieldWork)
local function currentFieldWorkWp(v)
    local strategy = v.getCpDriveStrategy ~= nil and v:getCpDriveStrategy() or nil
    local course = strategy ~= nil and strategy.fieldWorkCourse or nil
    if course ~= nil then
        local ok, ix = pcall(function()
            return course:getLastPassedWaypointIx() or course:getCurrentWaypointIx()
        end)
        if ok and type(ix) == "number" and ix >= 1 then return ix end
    end
    return nil
end

function AS_CpResume:save()
    if g_server == nil then return end
    local path = savegamePath()
    if path == nil then return end
    local xml = createXMLFile("asCpResume", path, "cpResume")
    if xml == nil or xml == 0 then return end
    setXMLInt(xml, "cpResume#version", 2)
    local i = 0
    if self.ENABLED then
        for _, v in ipairs(vehicleList()) do
            if v.getIsCpActive ~= nil and v:getIsCpActive() and v.uniqueId ~= nil
                    and not AS.isAutoDriveActive(v) then
                local job = v.getJob ~= nil and v:getJob() or nil
                local name = job ~= nil and job.name or nil
                if name ~= nil and self.JOBS[name] ~= nil then
                    local key = string.format("cpResume.vehicle(%d)", i)
                    setXMLString(xml, key .. "#id", v.uniqueId)
                    setXMLString(xml, key .. "#job", name)
                    local wp = nil
                    if name == "FIELDWORK_CP" then
                        wp = currentFieldWorkWp(v)
                        if wp ~= nil then setXMLInt(xml, key .. "#wp", wp) end
                    end
                    log("noté : %s (%s%s)", vehicleName(v), name, wp and (", point " .. wp) or "")
                    i = i + 1
                end
            end
        end
    end
    saveXMLFile(xml)
    delete(xml)
    log("%d véhicule(s) Courseplay notés pour la relance", i)
end

function AS_CpResume:load()
    local list = {}
    local path = savegamePath()
    if path == nil or not fileExists(path) then return list end
    local xml = loadXMLFile("asCpResume", path)
    if xml == nil or xml == 0 then return list end
    local i = 0
    while true do
        local key = string.format("cpResume.vehicle(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local id, job = getXMLString(xml, key .. "#id"), getXMLString(xml, key .. "#job")
        if id ~= nil and job ~= nil and self.JOBS[job] ~= nil then
            -- version 1 : point reculé par CP, pas fiable -> point le plus proche
            local wp = (getXMLInt(xml, "cpResume#version") or 1) >= 2 and getXMLInt(xml, key .. "#wp") or nil
            list[#list + 1] = { id = id, job = job, wp = wp, tries = 0 }
        end
        i = i + 1
    end
    delete(xml)
    return list
end

local function findVehicle(id)
    for _, v in ipairs(vehicleList()) do
        if v.uniqueId == id then return v end
    end
    return nil
end

-- renvoie "ok", "wait" (pas encore prêt) ou un texte de refus
function AS_CpResume:tryStart(e)
    local v = findVehicle(e.id)
    if v == nil then return "véhicule introuvable" end
    e.name = vehicleName(v)
    if v.getIsAIActive ~= nil and v:getIsAIActive() then return "déjà en route" end
    if AS.isAutoDriveActive(v) then return "piloté par AutoDrive" end
    local spec = v[self.JOBS[e.job]]
    local job = spec ~= nil and spec.cpJob or nil
    if job == nil then return "travail Courseplay absent sur ce véhicule" end
    if v.updateAIFieldWorkerImplementData ~= nil then v:updateAIFieldWorkerImplementData() end

    local setting, oldStart
    if e.job == "FIELDWORK_CP" then
        if v.hasCpCourse == nil or not v:hasCpCourse() then return "wait" end
        if v.getCanStartCpFieldWork ~= nil and not v:getCanStartCpFieldWork() then return "wait" end
        setting = v.getCpStartingPointSetting ~= nil and v:getCpStartingPointSetting() or nil
        if setting ~= nil then
            oldStart = setting:getValue()
            if e.wp ~= nil and v.rememberCpLastWaypointIx ~= nil then
                v:rememberCpLastWaypointIx(e.wp)
                setting:setValue(self.START_AT_LAST)
                e.how = "au point " .. e.wp .. " noté à la sauvegarde"
            else
                setting:setValue(self.START_AT_NEAREST)
                e.how = "au point le plus proche"
            end
        end
    elseif v.getCanStartCp ~= nil and not v:getCanStartCp() then
        return "wait"
    end

    local farmId = v:getOwnerFarmId()
    job:applyCurrentState(v, g_currentMission, farmId, true, true)
    job:setValues()
    local ok, msg = job:validate(false)
    if not ok then
        if setting ~= nil and oldStart ~= nil then setting:setValue(oldStart) end
        e.lastMsg = msg
        return "wait"
    end
    g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(job, farmId))
    if setting ~= nil and oldStart ~= nil and oldStart ~= setting:getValue() then
        table.insert(self.restores, { setting = setting, value = oldStart, t = self.RESTORE_MS })
    end
    return "ok"
end

function AS_CpResume:step(dt)
    local others = self.timer >= self.START_DELAY + self.OTHERS_DELAY
    local left = {}
    for _, e in ipairs(self.pending) do
        if e.job ~= "FIELDWORK_CP" and not others then
            left[#left + 1] = e
        else
            e.wait = (e.wait or 0) - dt
            if e.wait > 0 then
                left[#left + 1] = e
            else
                local ok, res = pcall(self.tryStart, self, e)
                if not ok then
                    log("ERREUR relance %s : %s", tostring(e.name or e.id), tostring(res))
                elseif res == "ok" then
                    log("relancé : %s (%s%s)", tostring(e.name), e.job, e.how and (", " .. e.how) or "")
                elseif res == "wait" then
                    e.tries = e.tries + self.RETRY_MS
                    if e.tries >= self.GIVE_UP_MS then
                        log("pas relancé : %s (%s) : pas prêt après %d s%s", tostring(e.name or e.id), e.job,
                            self.GIVE_UP_MS / 1000, e.lastMsg and (" : " .. tostring(e.lastMsg)) or "")
                    else
                        e.wait = self.RETRY_MS
                        left[#left + 1] = e
                    end
                else
                    log("pas relancé : %s (%s) : %s", tostring(e.name or e.id), e.job, res)
                end
            end
        end
    end
    self.pending = left
end

function AS_CpResume:update(dt)
    for i = #self.restores, 1, -1 do
        local r = self.restores[i]
        r.t = r.t - dt
        if r.t <= 0 then
            pcall(r.setting.setValue, r.setting, r.value)
            table.remove(self.restores, i)
        end
    end
    if g_server == nil or g_currentMission == nil then return end
    if self.pending == nil then
        if not g_currentMission.isMissionStarted then return end
        local ok, list = pcall(self.load, self)
        self.pending = ok and list or {}
        if not ok then log("ERREUR lecture : %s", tostring(list)) end
        log("actif : %d véhicule(s) Courseplay à relancer%s", #self.pending,
            self.ENABLED and "" or " (désactivé dans l'onglet AUTOSWITCH)")
        if not self.ENABLED then self.pending = {} end
        return
    end
    if #self.pending == 0 then return end
    self.timer = self.timer + (dt or 0)
    if self.timer < self.START_DELAY then return end
    self:step(dt or 0)
end

function AS_CpResume:deleteMap()
    self.pending, self.timer, self.restores = nil, 0, {}
end

-- écriture au moment où le jeu sauvegarde la partie
if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(AS_CpResume.save, AS_CpResume)
        if not ok then log("ERREUR sauvegarde : %s", tostring(err)) end
    end)
end

addModEventListener(AS_CpResume)
log("module chargé : relance de Courseplay au chargement de la partie")
