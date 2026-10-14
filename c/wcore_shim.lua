-- ════════════════════════════════════════════════════════════════════════════
-- w_medic · c/wcore_shim.lua -- the Wraith Core client API, on VORP / RSG / QBR, through w_lib
--
-- The job was written for the Wraith Core (w_core). Without it, this file gives the client files
-- the same calls: WCore.Functions.GetPlayerData / TriggerCallback / Notify / Progressbar /
-- HasItem / SpawnVehicle / DeleteVehicle, WCore.Shared.GetWeapon, and the events
-- WCore:Client:OnPlayerLoaded / OnJobUpdate / SetDuty. On a server that runs the real w_core it
-- does nothing. Loaded before the job's own client files (fxmanifest.lua).
--
-- ★ 2026-10-14: rewritten. Under the previous version, on VORP:
--     * the player's job was never known: the sync was only asked on 'playerSpawned' (before a
--       character is chosen) and OnPlayerLoaded never fired - no station prompt worked, and no
--       doctor was ever a doctor on his own client
--     * GetPlayerData(cb) ignored the callback (the login state was never read)
--     * Progressbar read a w_lib export that does not exist and threw: a doctor who bandaged or
--       revived somebody stayed frozen for good, and no medical item did anything
--     * Notify handed its text to the export proxy's `self`: every notice showed only its type
--     * HasItem asked vorp_inventory a server-only export: "no syringe" / "no bandage" always
--     * SpawnVehicle refused the model name the wagon menu passes: no wagon ever came
--     * a callback's packed answer was handed on still packed
-- ════════════════════════════════════════════════════════════════════════════

if GetResourceState('w_core') == 'started' and WCore and WCore.Functions
    and WCore.Functions.TriggerCallback and WCore.Functions.GetPlayerData then
    return -- the real Wraith Core
end

WCore = { Functions = {}, Shared = {} }

-- ── the local player, as the server last described him ──────────────────────
local function blankPlayer()
    return {
        source   = GetPlayerServerId(PlayerId()),
        job      = { name = 'unemployed', label = '', grade = { level = 0 }, onduty = false },
        metadata = {},
        charinfo = {},
    }
end

local cached = blankPlayer()
local loaded = false -- OnPlayerLoaded fired for the character in play

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == 'table' and copy(v) or v end
    return out
end

function WCore.Functions.GetPlayerData(cb)
    local data = copy(cached)
    if type(cb) == 'function' then return cb(data) end
    return data
end

RegisterNetEvent('w_medic:client:playerSync', function(data)
    if type(data) ~= 'table' or not data.citizenid then return end
    data.job = type(data.job) == 'table' and data.job or { name = tostring(data.job or 'unemployed'), grade = { level = 0 } }
    data.job.grade = type(data.job.grade) == 'table' and data.job.grade or { level = tonumber(data.job.grade) or 0 }
    data.metadata = type(data.metadata) == 'table' and data.metadata or {}
    cached = data
    if not loaded then
        loaded = true
        TriggerEvent('WCore:Client:OnPlayerLoaded')
    end
end)

local function requestSync()
    TriggerServerEvent('w_medic:server:requestPlayerSync')
end

-- A character chosen (VORP): a new character is loaded again from his own record
RegisterNetEvent('vorp:SelectedCharacter', function()
    loaded = false
    cached = blankPlayer()
    SetTimeout(1500, requestSync)
end)

-- RSG / QBR announce the loaded player themselves
RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function() loaded = false SetTimeout(1000, requestSync) end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() loaded = false SetTimeout(1000, requestSync) end)

-- Resource (re)start with the character already in play: ask until the server knows him
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    for _ = 1, 30 do
        if loaded then return end
        requestSync()
        Wait(5000)
    end
end)

-- A metadata change on the server (server/wcore_shim.lua SetMetaData). VORP's own dead flag
-- (vorp:ImDead) can only be set by this client, so the downed state is passed on to it here.
RegisterNetEvent('w_medic:client:meta', function(key, value, down)
    if type(key) ~= 'string' then return end
    cached.metadata[key] = value
    if (key == 'isdead' or key == 'inlaststand') and GetResourceState('vorp_core') == 'started' then
        TriggerServerEvent('vorp:ImDead', down == true)
    end
end)

-- ── callbacks: one net event per name, answered on w_medic:client:cb ──────────
local pending, seq = {}, 0

function WCore.Functions.TriggerCallback(name, cb, ...)
    if type(name) ~= 'string' or type(cb) ~= 'function' then return end
    seq = seq + 1
    local reqId = seq
    pending[reqId] = cb
    SetTimeout(10000, function()
        local fn = pending[reqId]
        if fn then
            pending[reqId] = nil
            fn(nil)
        end
    end)
    TriggerServerEvent('w_medic:server:cb:' .. name, reqId, ...)
end

RegisterNetEvent('w_medic:client:cb', function(name, reqId, result)
    local fn = pending[reqId]
    if not fn then return end
    pending[reqId] = nil
    if type(result) == 'table' and result.n then
        fn(table.unpack(result, 1, result.n))
    else
        fn(result)
    end
end)

-- ── notices: w_lib's notify; a string, or { text = title, caption = body } ─────────
local NOTIFY_TYPES = { primary = 'inform', info = 'inform', inform = 'inform', success = 'success', error = 'error', warning = 'warning' }

function WCore.Functions.Notify(text, nType, duration)
    local data = { type = NOTIFY_TYPES[nType or 'inform'] or 'inform', duration = tonumber(duration) or nil }
    if type(text) == 'table' then
        if text.caption then
            data.title, data.description = text.text, text.caption
        else
            data.description = text.text or text.description
        end
    else
        data.description = tostring(text or '')
    end
    pcall(w.notify, data)
end

-- ── the progress bar: the QB-style call (…, onFinish, onCancel) on w.progressBar ─────
-- Progressbar(name, label, duration, useWhileDead, canCancel, disableControls, animation, prop,
-- propTwo, onFinish, onCancel) -- returns at once, like the original; the bar runs in a thread
function WCore.Functions.Progressbar(_, label, duration, useWhileDead, canCancel, disable, animation, _, _, onFinish, onCancel)
    disable = type(disable) == 'table' and disable or {}
    animation = type(animation) == 'table' and animation or {}
    local anim
    if animation.animDict and animation.anim then
        anim = { dict = animation.animDict, clip = animation.anim, flag = animation.flags or 49 }
    elseif animation.task then
        anim = { scenario = animation.task }
    end
    CreateThread(function()
        local ok, done = pcall(w.progressBar, {
            label = label,
            duration = tonumber(duration) or 3000,
            position = 'bottom',
            useWhileDead = useWhileDead == true,
            canCancel = canCancel == true,
            disable = {
                move = disable.disableMovement == true,
                car = disable.disableCarMovement == true or disable.disableVehicleMovement == true,
                mouse = disable.disableMouse == true,
                combat = disable.disableCombat == true,
            },
            anim = anim,
        })
        if ok and done then
            if type(onFinish) == 'function' then onFinish() end
        elseif type(onCancel) == 'function' then
            onCancel()
        end
    end)
end

-- ── the bag: counted by the server (vorp_inventory has no client count) ───────
function WCore.Functions.HasItem(item, count)
    if type(item) ~= 'string' then return false end
    local ok, has = pcall(w.callback.await, 'w_medic:hasItem', false, item, tonumber(count) or 1)
    return ok and has == true
end

-- ── the wagon: spawned here, networked, then handed to the callback ───────────
function WCore.Functions.SpawnVehicle(model, cb, coords, networked)
    if type(model) == 'table' then model = model.model end
    local hash = type(model) == 'number' and model or joaat(tostring(model or 'chuckwagon000x'))
    local ped = PlayerPedId()
    coords = coords or GetEntityCoords(ped)
    local heading = coords.w or GetEntityHeading(ped)
    CreateThread(function()
        if not IsModelInCdimage(hash) then
            if type(cb) == 'function' then cb(nil) end
            return
        end
        RequestModel(hash)
        local deadline = GetGameTimer() + 10000
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
        if not HasModelLoaded(hash) then
            if type(cb) == 'function' then cb(nil) end
            return
        end
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, networked ~= false, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if veh and veh ~= 0 then
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
        end
        if type(cb) == 'function' then cb(veh ~= 0 and veh or nil) end
    end)
end

function WCore.Functions.DeleteVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

-- ── the killer's weapon, for the death log ─────────────────────────────────
-- by hash (what NetworkGetEntityKillerOfPlayer answers): the label is the item's own when the bag
-- knows it, the weapon name otherwise
local WEAPON_NAMES = {
    'weapon_revolver_cattleman', 'weapon_revolver_schofield', 'weapon_revolver_doubleaction', 'weapon_revolver_lemat',
    'weapon_revolver_navy', 'weapon_pistol_mauser', 'weapon_pistol_volcanic', 'weapon_pistol_semiauto', 'weapon_pistol_m1899',
    'weapon_rifle_boltaction', 'weapon_rifle_springfield', 'weapon_rifle_varmint', 'weapon_rifle_elephant',
    'weapon_repeater_carbine', 'weapon_repeater_henry', 'weapon_repeater_evans', 'weapon_repeater_winchester',
    'weapon_shotgun_doublebarrel', 'weapon_shotgun_pump', 'weapon_shotgun_repeating', 'weapon_shotgun_semiauto', 'weapon_shotgun_sawedoff',
    'weapon_sniperrifle_rollingblock', 'weapon_sniperrifle_carcano', 'weapon_bow', 'weapon_bow_improved',
    'weapon_melee_knife', 'weapon_melee_hatchet', 'weapon_melee_machete', 'weapon_melee_torch', 'weapon_melee_lantern',
    'weapon_lasso', 'weapon_thrown_tomahawk', 'weapon_thrown_dynamite', 'weapon_thrown_molotov',
    'weapon_thrown_throwing_knives', 'weapon_unarmed',
}
local byHash = {}
for _, name in ipairs(WEAPON_NAMES) do byHash[joaat(name)] = name end

function WCore.Shared.GetWeapon(weapon)
    if not weapon then return nil end
    local name = type(weapon) == 'number' and byHash[weapon] or (type(weapon) == 'string' and weapon:lower()) or nil
    if not name then return nil end
    local ok, label = pcall(function() return exports.w_lib:InvItemLabel(name) end)
    return { name = name, label = (ok and type(label) == 'string' and label ~= '' and label) or name }
end
