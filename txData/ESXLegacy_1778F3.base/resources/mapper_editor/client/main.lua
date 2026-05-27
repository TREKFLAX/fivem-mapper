local editor = {
    enabled = false,
    model = Config.DefaultModel,
    heading = 0.0,
    pitch = 0.0,
    roll = 0.0,
    heightOffset = Config.DefaultHeightOffset,
    fineOffset = vector3(0.0, 0.0, 0.0),
    preview = 0,
    lastHit = nil,
    lastNormal = nil,
    lockedPlacement = false,
    placedCooldown = false,
    lastPlaceAt = 0,
    selectedId = nil,
    showHelp = true
}

local serverPlacements = {}

local function notify(msg)
    print(('[Mapper] %s'):format(msg))
    TriggerEvent('chat:addMessage', {
        args = { 'Mapper', msg }
    })
end

local function keyboardInput(title, defaultText, maxLength)
    AddTextEntry('MAPPER_MODEL_INPUT', title)
    DisplayOnscreenKeyboard(1, 'MAPPER_MODEL_INPUT', '', defaultText or '', '', '', '', maxLength or 64)

    local status = UpdateOnscreenKeyboard()
    while status == 0 do
        DisableAllControlActions(0)
        Wait(0)
        status = UpdateOnscreenKeyboard()
    end

    if status ~= 1 then
        return nil
    end

    local result = GetOnscreenKeyboardResult()
    if not result or result == '' then
        return nil
    end

    return result
end

RegisterNetEvent('mapper:client:notify', function(msg)
    notify(msg)
end)

RegisterNetEvent('mapper:client:syncAll', function(placements)
    if type(placements) ~= 'table' then return end
    serverPlacements = placements
end)

local function ensureModel(model)
    local modelHash = type(model) == 'number' and model or joaat(model)

print('[Mapper] Checking model:', model, modelHash)

if not IsModelInCdimage(modelHash) then
    print('[Mapper] NOT IN CD IMAGE')
    return false
end

if not IsModelValid(modelHash) then
    print('[Mapper] NOT VALID')
    return false
end

    RequestModel(modelHash)

    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(modelHash) do
        Wait(0)

        if GetGameTimer() > timeout then
            return false
        end
    end

    return modelHash
end

local function deletePreview()
    if editor.preview ~= 0 and DoesEntityExist(editor.preview) then
        DeleteEntity(editor.preview)
    end
    editor.preview = 0
end

local function createPreview()
    deletePreview()

local modelHash = ensureModel(editor.model)

if not modelHash then
        notify(('Modelo inválido: %s'):format(editor.model))
        return false
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    editor.preview = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, false, false, false)

    if editor.preview == 0 or not DoesEntityExist(editor.preview) then
        notify('No se pudo crear el preview')
        return false
    end

    SetEntityAlpha(editor.preview, Config.PreviewAlpha, false)
    SetEntityCollision(editor.preview, false, false)
    SetEntityCompletelyDisableCollision(editor.preview, true, true)
    SetEntityInvincible(editor.preview, true)
    FreezeEntityPosition(editor.preview, true)
    SetModelAsNoLongerNeeded(modelHash)
    return true
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCamera(distance)
    local camRot = GetGameplayCamRot(2)
    local camCoord = GetGameplayCamCoord()
    local direction = rotationToDirection(camRot)
    local destination = camCoord + (direction * distance)

    local ray = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        destination.x, destination.y, destination.z,
        -1, PlayerPedId(), 0
    )

    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
    return hit == 1, endCoords, surfaceNormal, entityHit
end

local function drawText(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.35, scale or 0.35)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(false)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawHelp()
    if not editor.showHelp then return end

    drawText(0.015, 0.02, ('^3Mapper^7 | Modelo: ^2%s^7 | Heading: ^2%.1f^7 | Z offset: ^2%.2f^7'):format(editor.model, editor.heading, editor.heightOffset), 0.35)
    drawText(0.015, 0.045, '/mapper = activar/desactivar | /mmodel [modelo] | /mrot [heading] [pitch] [roll]', 0.32)
    drawText(0.015, 0.065, '/mplace = colocar | /mdelete = borrar lo que miras | /mup /mdown = subir/bajar', 0.32)
    drawText(0.015, 0.085, '/mleft /mright /mforward /mback = ajuste fino | /mexport = exportar | /mdedupe = limpiar', 0.32)
end

local function applyPreviewTransform(coords)
    if editor.preview == 0 or not DoesEntityExist(editor.preview) then return end

    local finalCoords = vector3(
        coords.x + editor.fineOffset.x,
        coords.y + editor.fineOffset.y,
        coords.z + editor.heightOffset + editor.fineOffset.z
    )

    SetEntityCoordsNoOffset(editor.preview, finalCoords.x, finalCoords.y, finalCoords.z, false, false, false)
    SetEntityRotation(editor.preview, editor.pitch, editor.roll, editor.heading, 2, true)
    FreezeEntityPosition(editor.preview, true)
end

local function findTargetPlacementId()
    local hit, _, _, entityHit = raycastFromCamera(Config.RaycastDistance)
    if not hit or entityHit == 0 or not DoesEntityExist(entityHit) then
        return nil
    end

    local state = Entity(entityHit).state
    if state and state.mapperId then
        return tonumber(state.mapperId)
    end

    return nil
end

local function placeCurrent()
    if not editor.enabled then return end

    local hit, coords = raycastFromCamera(Config.RaycastDistance)
    if not hit then
        notify('No hay superficie delante')
        return
    end

    local now = GetGameTimer()
    if now - editor.lastPlaceAt < 750 then
        return
    end
    editor.lastPlaceAt = now

    TriggerServerEvent('mapper:server:place', {
        model = editor.model,
        x = coords.x + editor.fineOffset.x,
        y = coords.y + editor.fineOffset.y,
        z = coords.z + editor.heightOffset + editor.fineOffset.z,
        rx = editor.pitch,
        ry = editor.roll,
        rz = editor.heading,
        heading = editor.heading,
        bucket = 0
    })
end

local function deleteTargeted()
    local id = findTargetPlacementId()
    if not id then
        notify('No estás apuntando a un mapeo válido')
        return
    end

    TriggerServerEvent('mapper:server:delete', id)
end

local function enableEditor(model)
    editor.model = model or editor.model
    editor.enabled = true
    editor.fineOffset = vector3(0.0, 0.0, 0.0)
    editor.lockedPlacement = false

    if not createPreview() then
        editor.enabled = false
        deletePreview()
        return false
    end

    notify(('Editor activado: %s'):format(editor.model))
    TriggerServerEvent('mapper:server:requestSync')
    return true
end

local function disableEditor()
    editor.enabled = false
    notify('Editor desactivado')
    deletePreview()
end

RegisterCommand('mapper', function(_, args)
    if editor.enabled then
        disableEditor()
        return
    end

    local model = args[1] or keyboardInput('Escribe el modelo del prop', editor.model or Config.DefaultModel, 64)
    if not model then
        notify('Mapeo cancelado')
        return
    end

    enableEditor(model)
end, false)

RegisterCommand('mmodel', function(_, args)
    local model = args[1]
    if not model or model == '' then
        notify(('Uso: /mmodel %s'):format(Config.DefaultModel))
        return
    end

    if editor.enabled then
        enableEditor(model)
    else
        editor.model = model
    end
    notify(('Modelo cambiado a %s'):format(model))
end, false)

RegisterCommand('mrot', function(_, args)
    editor.heading = tonumber(args[1]) or editor.heading
    editor.pitch = tonumber(args[2]) or editor.pitch
    editor.roll = tonumber(args[3]) or editor.roll
    notify(('Rotación: heading %.1f / pitch %.1f / roll %.1f'):format(editor.heading, editor.pitch, editor.roll))
end, false)

RegisterCommand('mup', function(_, args)
    editor.heightOffset = editor.heightOffset + (tonumber(args[1]) or Config.MoveStep)
    notify(('Altura: %.2f'):format(editor.heightOffset))
end, false)

RegisterCommand('mdown', function(_, args)
    editor.heightOffset = editor.heightOffset - (tonumber(args[1]) or Config.MoveStep)
    notify(('Altura: %.2f'):format(editor.heightOffset))
end, false)

RegisterCommand('mleft', function(_, args)
    editor.fineOffset = vector3(editor.fineOffset.x - (tonumber(args[1]) or Config.MoveStep), editor.fineOffset.y, editor.fineOffset.z)
    notify(('Offset X: %.2f'):format(editor.fineOffset.x))
end, false)

RegisterCommand('mright', function(_, args)
    editor.fineOffset = vector3(editor.fineOffset.x + (tonumber(args[1]) or Config.MoveStep), editor.fineOffset.y, editor.fineOffset.z)
    notify(('Offset X: %.2f'):format(editor.fineOffset.x))
end, false)

RegisterCommand('mforward', function(_, args)
    editor.fineOffset = vector3(editor.fineOffset.x, editor.fineOffset.y + (tonumber(args[1]) or Config.MoveStep), editor.fineOffset.z)
    notify(('Offset Y: %.2f'):format(editor.fineOffset.y))
end, false)

RegisterCommand('mback', function(_, args)
    editor.fineOffset = vector3(editor.fineOffset.x, editor.fineOffset.y - (tonumber(args[1]) or Config.MoveStep), editor.fineOffset.z)
    notify(('Offset Y: %.2f'):format(editor.fineOffset.y))
end, false)

RegisterCommand('mplace', function()
    placeCurrent()
end, false)

RegisterCommand('mdelete', function()
    deleteTargeted()
end, false)

RegisterCommand('mexport', function()
    TriggerServerEvent('mapper:server:export')
end, false)

RegisterCommand('mreload', function()
    TriggerServerEvent('mapper:server:reload')
end, false)

RegisterCommand('mdedupe', function()
    TriggerServerEvent('mapper:server:dedupe')
end, false)

RegisterCommand('mhelp', function()
    editor.showHelp = not editor.showHelp
    notify(('Ayuda %s'):format(editor.showHelp and 'activada' or 'desactivada'))
end, false)

RegisterKeyMapping('mapper', 'Abrir/cerrar editor de mapeo', 'keyboard', 'F7')

CreateThread(function()
    while true do
        if not editor.enabled then
            Wait(250)
        else
            Wait(0)

            if editor.preview == 0 or not DoesEntityExist(editor.preview) then
                createPreview()
            end

            local hit, coords, normal = raycastFromCamera(Config.RaycastDistance)

            if hit and not editor.lockedPlacement then
                editor.lastHit = coords
                editor.lastNormal = normal
                applyPreviewTransform(coords + (normal * 0.01))
            end

            drawHelp()

            if IsControlJustPressed(0, 175) then -- RIGHT ARROW
                editor.heading = (editor.heading + Config.RotateStep) % 360.0
            end
            if IsControlJustPressed(0, 174) then -- LEFT ARROW
                editor.heading = (editor.heading - Config.RotateStep) % 360.0
            end
            if IsControlJustPressed(0, 172) then -- UP ARROW
                editor.heightOffset = editor.heightOffset + Config.MoveStep
            end
            if IsControlJustPressed(0, 173) then -- DOWN ARROW
                editor.heightOffset = editor.heightOffset - Config.MoveStep
            end

            if IsControlJustPressed(0, 38) and not editor.placedCooldown then
                editor.lockedPlacement = true
                editor.placedCooldown = true

                placeCurrent()

                CreateThread(function()
                    Wait(300)

                    editor.lockedPlacement = false
                    editor.placedCooldown = false
                end)
            end
            if IsControlJustPressed(0, 177) then -- BACKSPACE
                deleteTargeted()
            end
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('mapper:server:requestSync')
end)
