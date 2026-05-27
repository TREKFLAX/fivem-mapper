local RESOURCE = GetCurrentResourceName()
local DATA_FILE = 'data/placements.lua'

local placements = {}
local spawnedEntities = {}

local function safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function loadPlacements()
    local raw = LoadResourceFile(RESOURCE, DATA_FILE)
    if not raw or raw == '' then
        placements = {}
        return
    end

    local chunk, err = load(raw, ('@@%s/%s'):format(RESOURCE, DATA_FILE), 't', {})
    if not chunk then
        print(('[%s] No se pudo leer %s: %s'):format(RESOURCE, DATA_FILE, err or 'error desconocido'))
        placements = {}
        return
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        print(('[%s] %s no devolvio una tabla valida.'):format(RESOURCE, DATA_FILE))
        placements = {}
        return
    end

    placements = data
end

local function deleteSpawnedEntity(id)
    local ent = spawnedEntities[id]
    if ent and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    spawnedEntities[id] = nil
end

local function spawnPlacement(entry)
    local model = joaat(tostring(entry.model or ''))
    local obj = CreateObjectNoOffset(
        model,
        safeNumber(entry.x, 0.0),
        safeNumber(entry.y, 0.0),
        safeNumber(entry.z, 0.0),
        true,
        true,
        false
    )

    if not obj or obj == 0 or not DoesEntityExist(obj) then
        print(('[%s] No se pudo crear el objeto %s (id %s)'):format(RESOURCE, tostring(entry.model), tostring(entry.id)))
        return nil
    end

    SetEntityOrphanMode(obj, 2)
    FreezeEntityPosition(obj, true)
    SetEntityRotation(obj, safeNumber(entry.rx, 0.0), safeNumber(entry.ry, 0.0), safeNumber(entry.rz, 0.0), 2, true)
    SetEntityHeading(obj, safeNumber(entry.heading, safeNumber(entry.rz, 0.0)))

    local bucket = safeNumber(entry.bucket, 0)
    if bucket > 0 then
        SetEntityRoutingBucket(obj, bucket)
    end

    Entity(obj).state.mapperId = safeNumber(entry.id, 0)
    Entity(obj).state.mapperModel = tostring(entry.model or '')

    spawnedEntities[safeNumber(entry.id, 0)] = obj
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

local function reloadMap()
    loadPlacements()
    respawnAll()
    print(('[%s] Cargados %d objetos.'):format(RESOURCE, #placements))
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    reloadMap()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    for id, _ in pairs(spawnedEntities) do
        deleteSpawnedEntity(id)
    end
end)

RegisterCommand('officialmapreload', function(source)
    if source ~= 0 then return end
    reloadMap()
end, true)
