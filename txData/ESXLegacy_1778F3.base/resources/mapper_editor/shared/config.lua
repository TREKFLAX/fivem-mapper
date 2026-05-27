Config = {}

-- Permiso ACE para crear, borrar, guardar y exportar.
Config.RequireAcePermission = false
Config.AcePermission = 'mapper.admin'

-- Archivo principal donde se guarda el mapeo.
Config.DataFile = 'data/spawns.json'

-- Archivo de exportación extra si quieres copiar el mapeo a otro recurso.
Config.ExportLuaFile = 'data/export.lua'
Config.ExportJsonFile = 'data/export.json'

-- Recurso limpio para el servidor oficial. El editor actualiza este archivo al guardar/exportar.
Config.WriteOfficialExport = true
Config.OfficialResourceName = 'mapper_official_map'
Config.OfficialDataFile = 'data/placements.lua'

-- Modelo por defecto para el preview.
Config.DefaultModel = 'prop_roadcone02a'

-- Distancias y ajustes.
Config.RaycastDistance = 20.0
Config.RotateStep = 5.0
Config.MoveStep = 0.05
Config.DefaultHeightOffset = 0.0

-- Preview.
Config.PreviewAlpha = 130
Config.PreviewScale = 1.0

-- Control fino.
Config.NudgeControls = {
    left  = 34, -- A
    right = 35, -- D
    up    = 32, -- W
    down  = 33, -- S
}
