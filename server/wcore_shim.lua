-- ════════════════════════════════════════════════════════════════════════════
-- w_medic · server/wcore_shim.lua -- the Wraith Core server API, on VORP / RSG / QBR, through w_lib
--
-- The job was written for the Wraith Core (w_core). Without it, this file gives server/main.lua the
-- same calls: WCore.Functions.GetPlayer / GetPlayers / GetWPlayers / CreateCallback /
-- CreateUseableItem / GetOfflinePlayerByCitizenId and WCore.Commands.Add. On a server that runs the
-- real w_core it does nothing.
--
-- ★ 2026-10-14: replaces the block that stood inline in config.lua, under which nothing of the job
--   worked on VORP:
--     * getUsedCharacter is a TABLE on VORP's API; it was called, so every GetPlayer threw
--     * job was the bare string ('doctor'): every `job.name == 'doctor'` check was false
--     * nothing kept a duty: 'WCore:ToggleDuty' had no handler, so no doctor was ever on duty
--     * no SetMetaData / ClearInventory: the death-status events threw
--     * its net events were AddEventHandler, which a client cannot reach: the player sync, every
--       callback and the wagon request were never answered
--     * the 6th argument of Commands.Add (the permission) was read from the 4th: /revive /kill
--       /aheal /setpain were open to every player
--     * the usable items were handed VORP's single `data` table where they expect (source, item)
--     * RemoveItem answered pcall's true: a revive or a treatment never cost its item
--     * GetPlayers walked VORP's users, keyed by steam id: every doctor count / alert threw
--     * a player was cached forever: a job change was never seen, and a new player who got a
--       disconnected player's server id inherited his record
-- ════════════════════════════════════════════════════════════════════════════

if GetResourceState('w_core') == 'started' and WCore and WCore.Commands and WCore.Functions
    and WCore.Functions.CreateCallback then
    return -- the real Wraith Core
end

local VORP = nil
local function vorpCore()
    if VORP == nil then
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        VORP = ok and core or false
    end
    return VORP or nil
end

-- exports.w_lib:Fw<name>(...) -- the export lookup itself throws when it is missing, so it sits in the pcall
local function fw(name, ...)
    local ok, value = pcall(function(...) return exports.w_lib['Fw' .. name](nil, ...) end, ...)
    if ok then return value end
    return nil
end

-- What the framework keeps no record of: the duty, and the downed state the job writes
local Duty = {}   -- [src] = true while on duty
local Meta = {}   -- [src] = { isdead = bool, inlaststand = bool }

--- The VORP character table of a player (getUsedCharacter is a field, not a function), or nil.
local function vorpCharacter(src)
    local core = vorpCore()
    if not core then return nil end
    local ok, char = pcall(function()
        local user = core.getUser(src)
        return user and user.getUsedCharacter or nil
    end)
    return ok and type(char) == 'table' and char or nil
end

local function metaOf(src)
    local m = Meta[src]
    if not m then
        -- a character logged out dead logs in dead: VORP keeps `isdead` on the character
        local char = vorpCharacter(src)
        m = { isdead = char and (char.isdead == true or char.isdead == 1) or false, inlaststand = false }
        Meta[src] = m
    end
    return m
end

--- The Wraith-shaped player, read fresh on every call (nothing cached but the duty and the downed state).
---@return table|nil
local function getPlayer(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return nil end
    local charId = fw('GetCharacterIdentifier', src)
    if not charId then return nil end -- no character selected yet

    local jobName = tostring(fw('GetJob', src) or 'unemployed')
    local grade = tonumber(fw('GetJobGrade', src)) or 0
    local meta = metaOf(src)

    local Functions = {}
    Functions.RemoveItem = function(name, count, slot)
        local ok, done = pcall(function() return exports.w_lib:InvRemoveItem(src, name, count or 1, nil, slot) end)
        return ok and done == true
    end
    Functions.AddItem = function(name, count, _, info)
        local ok, done = pcall(function() return exports.w_lib:InvAddItem(src, name, count or 1, info) end)
        return ok and done == true
    end
    Functions.ClearInventory = function()
        return fw('ClearInventory', src) == true
    end
    Functions.SetMetaData = function(key, value)
        meta[key] = value
        -- His client keeps its copy. For the downed state it also sets VORP's own `isdead` (other
        -- scripts read it, it is saved, and a character who logs out down logs in down): the API
        -- character has no setter, only the player's own client can, through vorp:ImDead.
        TriggerClientEvent('w_medic:client:meta', src, key, value, meta.isdead == true or meta.inlaststand == true)
    end
    Functions.Save = function() end

    return {
        PlayerData = {
            source     = src,
            citizenid  = tostring(charId),
            charid     = charId,
            identifier = fw('GetIdentifier', src) or '',
            job        = {
                name   = jobName,
                label  = fw('GetJobLabel', src) or jobName,
                grade  = { level = grade },
                onduty = Duty[src] == true,
            },
            metadata   = meta,
            charinfo   = { firstname = fw('GetFirstName', src) or '', lastname = fw('GetLastName', src) or '' },
        },
        Functions = Functions,
    }
end

--- Every player with a character in play: an array of server ids.
local function getPlayers()
    local list = {}
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src and fw('GetCharacterIdentifier', src) then list[#list + 1] = src end
    end
    return list
end

--- The same, as { [src] = player }.
local function getWPlayers()
    local out = {}
    for _, src in ipairs(getPlayers()) do
        local p = getPlayer(src)
        if p then out[src] = p end
    end
    return out
end

-- ── what the client is told ─────────────────────────────────────────────────
local function syncPayload(src)
    local p = getPlayer(src)
    if not p then return nil end
    return p.PlayerData
end

local function pushSync(src, jobChanged)
    local data = syncPayload(src)
    if not data then return end
    TriggerClientEvent('w_medic:client:playerSync', src, data)
    if jobChanged then TriggerClientEvent('WCore:Client:OnJobUpdate', src, data.job) end
end

RegisterNetEvent('w_medic:server:requestPlayerSync', function()
    local src = source
    local data = syncPayload(src)
    if data then TriggerClientEvent('w_medic:client:playerSync', src, data) end
end)

-- ── the duty (the station prompt): a doctor only; any job change ends it ──────────
RegisterNetEvent('WCore:ToggleDuty', function()
    local src = source
    local p = getPlayer(src)
    if not p or p.PlayerData.job.name ~= 'doctor' then
        Duty[src] = nil
        TriggerClientEvent('WCore:Client:SetDuty', src, false)
        return
    end
    Duty[src] = not Duty[src] or nil
    TriggerClientEvent('WCore:Client:SetDuty', src, Duty[src] == true)
    w.notify(src, { description = Duty[src] and 'info.on_duty' or 'info.off_duty', type = 'inform' })
    pushSync(src, false)
end)

-- ⚠️ VORP fires both events BEFORE it stores the new value (character.lua Job / Jobgrade): read
--    inside the handler, the job is still the old one. The client is told a moment later.
AddEventHandler('vorp:playerJobChange', function(src, newJob, oldJob)
    src = tonumber(src)
    if not src then return end
    -- /jobs re-sets the same job when a doctor picks his rank again: that is no job change
    if tostring(newJob) ~= tostring(oldJob) then Duty[src] = nil end
    SetTimeout(250, function() pushSync(src, true) end)
end)

AddEventHandler('vorp:playerJobGradeChange', function(src)
    src = tonumber(src)
    if not src then return end
    SetTimeout(250, function() pushSync(src, true) end)
end)

-- a character switch: a new character starts off duty and with his own downed state
AddEventHandler('vorp:SelectedCharacter', function(src)
    src = tonumber(src)
    if not src then return end
    Duty[src] = nil
    Meta[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    Duty[src] = nil
    Meta[src] = nil
end)

-- ── callbacks: a net event per name, answered with the handler's values ──────────
local function createCallback(name, handler)
    if type(name) ~= 'string' or type(handler) ~= 'function' then return end
    RegisterNetEvent('w_medic:server:cb:' .. name, function(reqId, ...)
        local src = source
        local answered = false
        local ok, err = pcall(handler, src, function(...)
            answered = true
            TriggerClientEvent('w_medic:client:cb', src, name, reqId, table.pack(...))
        end, ...)
        if not ok then
            print(('[w_medic] callback %s: %s'):format(name, tostring(err)))
            if not answered then TriggerClientEvent('w_medic:client:cb', src, name, reqId, { n = 0 }) end
        end
    end)
end

-- ── usable items: through w_lib's bag bridge, handed (source, { name, slot, info }) ─
-- (the bridge answers every bag with (source, { metadata, slot, item }); on vorp the slot is the
-- item id, which InvRemoveItem takes back to remove that exact stack)
local function createUseableItem(name, handler)
    if type(name) ~= 'string' or type(handler) ~= 'function' then return end
    pcall(function()
        exports.w_lib:InvRegisterUsableItem(name, true, function(source, data)
            data = type(data) == 'table' and data or {}
            return handler(source, { name = name, slot = data.slot, info = data.metadata or {} })
        end)
    end)
end

-- The client's WCore.Functions.HasItem (a bag count is the server's to read on VORP)
w.callback.register('w_medic:hasItem', function(source, item, count)
    if type(item) ~= 'string' then return false end
    local ok, have = pcall(function() return exports.w_lib:InvGetItemCount(source, item) end)
    return ok and (tonumber(have) or 0) >= (tonumber(count) or 1)
end)

-- ── a character who is not in the game (the admin's /revive <citizen id>) ─────────
local function getOfflinePlayerByCitizenId(citizenid)
    local id = tonumber(citizenid)
    if not id then return nil end
    local row = MySQL.single.await('SELECT `charidentifier`, `identifier`, `firstname`, `lastname`, `job`, `jobgrade`, `isdead` FROM `characters` WHERE `charidentifier` = ? LIMIT 1', { id })
    if not row then return nil end
    local pending = {}
    return {
        PlayerData = {
            source = 0, citizenid = tostring(row.charidentifier), charid = row.charidentifier, identifier = row.identifier,
            job = { name = row.job or 'unemployed', grade = { level = tonumber(row.jobgrade) or 0 }, onduty = false },
            metadata = { isdead = row.isdead == 1 or row.isdead == true },
            charinfo = { firstname = row.firstname or '', lastname = row.lastname or '' },
        },
        Functions = {
            SetMetaData = function(key, value) pending[key] = value end,
            Save = function()
                if pending.isdead ~= nil or pending.inlaststand ~= nil then
                    local dead = pending.isdead == true or pending.inlaststand == true
                    MySQL.update.await('UPDATE `characters` SET `isdead` = ? WHERE `charidentifier` = ?', { dead and 1 or 0, id })
                end
            end,
            RemoveItem = function() return false end,
        },
    }
end

-- ── commands: the 6th argument is the permission ('admin' = a framework admin) ───────
local function isAdmin(src)
    if src == 0 then return true end
    local ok, admin = pcall(function() return exports.w_lib:IsAdmin(src) end)
    if ok and admin then return true end
    return IsPlayerAceAllowed(src, 'w_medic.admin')
end

local function addCommand(name, help, params, argsRequired, handler, permission)
    if type(name) ~= 'string' or type(handler) ~= 'function' then return end
    RegisterCommand(name, function(source, args)
        if permission and permission ~= 'user' and not isAdmin(source) then return end
        handler(source, args or {})
    end, false)
end

WCore = {
    Functions = {
        GetPlayer                   = getPlayer,
        GetPlayers                  = getPlayers,
        GetWPlayers                 = getWPlayers,
        CreateCallback              = createCallback,
        CreateUseableItem           = createUseableItem,
        GetOfflinePlayerByCitizenId = getOfflinePlayerByCitizenId,
    },
    Commands = { Add = addCommand },
    Shared = {},
}

print('[w_medic] ^2WCore bridge ready^0 (w_lib framework bridge)')
