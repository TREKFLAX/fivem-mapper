local RESOURCE = GetCurrentResourceName()
local DATA_FILE = Config.DataFile
local EXPORT_LUA_FILE = Config.ExportLuaFile
local EXPORT_JSON_FILE = Config.ExportJsonFile

local placements = {}
local spawnedEntities = {}

local function cloneTable(input)
    local out = {}
    for k, v in pairs(input) do
        if type(v) == 'table' then
            out[k] = cloneTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function sanitizeEntry(entry)
    return {
        id = safeNumber(entry.id, 0),
        model = tostring(entry.model or Config.DefaultModel),
        x = safeNumber(entry.x, 0.0),
        y = safeNumber(entry.y, 0.0),
        z = safeNumber(entry.z, 0.0),
        rx = safeNumber(entry.rx, 0.0),
        ry = safeNumber(entry.ry, 0.0),
        rz = safeNumber(entry.rz, 0.0),
        heading = safeNumber(entry.heading, safeNumber(entry.rz, 0.0)),
        bucket = safeNumber(entry.bucket, 0)
    }
end

local function getNextId()
    local maxId = 0
    for _, entry in ipairs(placements) do
        local id = safeNumber(entry.id, 0)
        if id > maxId then
            maxId = id
        end
    end
    return maxId + 1
end

local function savePlacements()
    SaveResourceFile(RESOURCE, DATA_FILE, json.encode(placements), -1)
end

local function saveExports()
    local jsonData = json.encode(placements)
    SaveResourceFile(RESOURCE, EXPORT_JSON_FILE, jsonData, -1)

    local luaLines = {
        'return {',
    }

    for _, entry in ipairs(placements) do
        luaLines[#luaLines + 1] = string.format(
            '  { id = %d, model = %q, x = %.4f, y = %.4f, z = %.4f, rx = %.4f, ry = %.4f, rz = %.4f, heading = %.4f, bucket = %d },',
            safeNumber(entry.id, 0),
            tostring(entry.model),
            safeNumber(entry.x, 0.0),
            safeNumber(entry.y, 0.0),
            safeNumber(entry.z, 0.0),
            safeNumber(entry.rx, 0.0),
            safeNumber(entry.ry, 0.0),
            safeNumber(entry.rz, 0.0),
            safeNumber(entry.heading, 0.0),
            safeNumber(entry.bucket, 0)
        )
    end

    luaLines[#luaLines + 1] = '}'
    SaveResourceFile(RESOURCE, EXPORT_LUA_FILE, table.concat(luaLines, '\n'), -1)
end

local function loadPlacements()
    local raw = LoadResourceFile(RESOURCE, DATA_FILE)
    if not raw or raw == '' then
        placements = {}
        return
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        print(('[%s] No se pudo leer %s, se crea vacío.'):format(RESOURCE, DATA_FILE))
        placements = {}
        return
    end

    placements = {}
    for _, entry in ipairs(decoded) do
        placements[#placements + 1] = sanitizeEntry(entry)
    end
end

local function deleteSpawnedEntity(id)
    local ent = spawnedEntities[id]
    if ent and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    spawnedEntities[id] = nil
end

local function spawnPlacement(entry)
    local model = joaat(entry.model)
    local obj = CreateObjectNoOffset(model, entry.x, entry.y, entry.z, true, true, false)

    if not obj or obj == 0 or not DoesEntityExist(obj) then
        print(('[%s] No se pudo crear el objeto %s (id %s)'):format(RESOURCE, entry.model, entry.id))
        return nil
    end

    SetEntityAsMissionEntity(obj, true, true)
    SetEntityOrphanMode(obj, 2)
    FreezeEntityPosition(obj, true)
    SetEntityRotation(obj, entry.rx, entry.ry, entry.rz, 2, true)
    SetEntityHeading(obj, entry.heading or entry.rz or 0.0)

    if entry.bucket and entry.bucket > 0 then
        SetEntityRoutingBucket(obj, entry.bucket)
    end

    Entity(obj).state.mapperId = entry.id
    Entity(obj).state.mapperModel = entry.model
    Entity(obj).state.mapperHeading = entry.heading or entry.rz or 0.0

    spawnedEntities[entry.id] = obj
    return obj
end

local function respawnAll()
    for id, _ in pairs(spawnedEntities) do
        deleteSpawnedEntity(id)
    end

    spawnedEntities = {}

    for _, entry in ipairs(placements) do
        spawnPlacement(entry)
    end
end

local function isAllowed(source)
    if source == 0 then
        return true
    end

    return IsPlayerAceAllowed(source, Config.AcePermission)
end

local function findPlacementIndexById(id)
    for i, entry in ipairs(placements) do
        if safeNumber(entry.id, -1) == id then
            return i
        end
    end
    return nil
end

local function broadcastPlacements(target)
    TriggerClientEvent('mapper:client:syncAll', target or -1, cloneTable(placements))
end

RegisterNetEvent('mapper:server:requestSync', function()
    local src = source
    broadcastPlacements(src)
end)

RegisterNetEvent('mapper:server:place', function(payload)
    local src = source
    if not isAllowed(src) then
        print(('[%s] %s intentó colocar sin permiso.'):format(RESOURCE, GetPlayerName(src) or src))
        return
    end

    if type(payload) ~= 'table' then return end

    local entry = sanitizeEntry(payload)
    entry.id = getNextId()

    placements[#placements + 1] = entry
    savePlacements()
    saveExports()

    spawnPlacement(entry)
    broadcastPlacements(-1)

    TriggerClientEvent('mapper:client:notify', src, ('Colocado ID %d'):format(entry.id))
end)

RegisterNetEvent('mapper:server:delete', function(id)
    local src = source
    if not isAllowed(src) then
        print(('[%s] %s intentó borrar sin permiso.'):format(RESOURCE, GetPlayerName(src) or src))
        return
    end

    id = safeNumber(id, -1)
    if id < 0 then return end

    local index = findPlacementIndexById(id)
    if not index then return end

    deleteSpawnedEntity(id)
    table.remove(placements, index)
    savePlacements()
    saveExports()
    broadcastPlacements(-1)

    TriggerClientEvent('mapper:client:notify', src, ('Eliminado ID %d'):format(id))
end)

RegisterNetEvent('mapper:server:reload', function()
    local src = source
    if not isAllowed(src) then return end

    loadPlacements()
    respawnAll()
    saveExports()
    broadcastPlacements(-1)

    if src ~= 0 then
        TriggerClientEvent('mapper:client:notify', src, 'Mapeo recargado')
    else
        print(('[%s] Mapeo recargado desde consola.'):format(RESOURCE))
    end
end)

RegisterNetEvent('mapper:server:export', function()
    local src = source
    if not isAllowed(src) then return end

    saveExports()
    if src ~= 0 then
        TriggerClientEvent('mapper:client:notify', src, ('Exportado a %s y %s'):format(EXPORT_JSON_FILE, EXPORT_LUA_FILE))
    end
end)

RegisterCommand('mapreload', function(source)
    if source ~= 0 and not isAllowed(source) then return end
    loadPlacements()
    respawnAll()
    saveExports()
    broadcastPlacements(-1)
end, true)

RegisterCommand('mapexport', function(source)
    if source ~= 0 and not isAllowed(source) then return end
    saveExports()
    if source ~= 0 then
        TriggerClientEvent('mapper:client:notify', source, ('Exportado a %s y %s'):format(EXPORT_JSON_FILE, EXPORT_LUA_FILE))
    else
        print(('[%s] Exportado correctamente.'):format(RESOURCE))
    end
end, true)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    loadPlacements()
    respawnAll()
    saveExports()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    for id, _ in pairs(spawnedEntities) do
        deleteSpawnedEntity(id)
    end
end)

exports('GetPlacements', function()
    return cloneTable(placements)
end)

exports('ReloadPlacements', function()
    loadPlacements()
    respawnAll()
    saveExports()
    broadcastPlacements(-1)
end)
