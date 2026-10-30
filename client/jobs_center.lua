-- ════════════════════════════════════════════════════════════════════════════
-- w_medic · client/jobs_center.lua -- the jobs centre (gw-medic's recruitment terminal)
--
-- ★ 2026-10-14 (owner): at gw-medic's desk (Config.MDTDesk, the Valentine pharmacist), the health
--   minister, his deputy and the admins press J: hire a player as a doctor, change a doctor's
--   rank, dismiss him. The key is put on the pharmacist's own prompt through w_store
--   (exports.w_store:SetCashierAction): the bridge shows one prompt group at a time, and a second
--   group on the same ped could only fight the shop's over the screen. Only a player the server
--   flagged (LocalPlayer.state['w_medic:jobsCenter']) sees it; the server checks every action again
--   (server/main.lua, "the jobs centre").
-- ════════════════════════════════════════════════════════════════════════════

local KEY = 'J'
local STATE = 'w_medic:jobsCenter'
local EVENT = 'w_medic:client:jobsCenter'

-- the pharmacies whose pharmacist hosts the jobs centre: the shelf of each armory (server/main.lua
-- names them '<city> Pharmacy')
local function pharmacyNames()
    local names = {}
    for _, v in ipairs(Config.Locations['armory'] or {}) do
        names[#names + 1] = ('%s Pharmacy'):format(v.city or 'Hospital')
    end
    return names
end

local function registerWithStore()
    if GetResourceState('w_store') ~= 'started' then return false end
    local done = false
    for _, name in ipairs(pharmacyNames()) do
        local ok, res = pcall(function()
            return exports.w_store:SetCashierAction(name, { key = KEY, label = locale('jobs.prompt'), state = STATE, event = EVENT })
        end)
        done = done or (ok and res == true)
    end
    return done
end

-- ── the menus ────────────────────────────────────────────────────────────────
local openCenter

local function tell(res, okKey)
    if type(res) == 'table' and res.ok then
        w.notify({ description = locale(okKey), type = 'success' })
    else
        w.notify({ description = locale('jobs.err_' .. tostring(type(res) == 'table' and res.error or 'failed')), type = 'error' })
    end
end

local function rankOptions(ranks)
    local options = {}
    for _, r in ipairs(ranks or {}) do
        if r.give then options[#options + 1] = { value = tostring(r.grade), label = r.label } end
    end
    return options
end

local function hireDialog(data)
    local options = rankOptions(data.ranks)
    if #options == 0 then return w.notify({ description = locale('jobs.err_rank_too_high'), type = 'error' }) end
    local input = w.inputDialog(locale('jobs.hire'), {
        { type = 'input', label = locale('jobs.citizen_id'), required = true },
        { type = 'select', label = locale('jobs.rank'), options = options, required = true },
    })
    if not input then return openCenter() end
    local preview = w.callback.await('w_medic:jobs:previewHire', false, input[1], tonumber(input[2]))
    if type(preview) ~= 'table' or not preview.ok then tell(preview, 'jobs.done_hire'); return openCenter() end
    local answer = w.alertDialog({ header = locale('jobs.hire'), content = locale('jobs.confirm_hire', preview.name, preview.label), cancel = true })
    if answer ~= 'confirm' then return openCenter() end
    tell(w.callback.await('w_medic:jobs:hire', false, preview.citizenid, tonumber(input[2]), preview.citizenid), 'jobs.done_hire')
    openCenter()
end

-- the ranks this doctor may be set to (the server worked them out: d.ranks), as select options
local function targetRankOptions(data, d)
    local labels, options = {}, {}
    for _, r in ipairs(data.ranks or {}) do labels[r.grade] = r.label end
    for _, grade in ipairs(d.ranks or {}) do
        options[#options + 1] = { value = tostring(grade), label = labels[grade] or tostring(grade) }
    end
    return options
end

-- ★ The rows carry event names, not functions (2026-10-16): the context menu lives in w_lib, and
--   only names cross the export boundary (the library's contract; a function reference dies with a
--   restart of this resource). The handlers are local client events at the end of this section;
--   they act on `current`, the list the menus were built from, and the server checks everything again.
local UI = 'w_medic:jobs:ui:'
local current = nil

local function doctorMenu(data, index)
    local d = data.doctors[index]
    local options = {}
    if #targetRankOptions(data, d) > 0 then
        options[#options + 1] = { title = locale('jobs.change_rank'), description = d.label, event = UI .. 'rank', args = index }
    end
    if d.fire then
        options[#options + 1] = { title = locale('jobs.fire'), event = UI .. 'fire', args = index }
    end
    w.registerContext({ id = 'w_medic_jobs_doctor', title = d.name, menu = 'w_medic_jobs', options = options })
    w.showContext('w_medic_jobs_doctor')
end

openCenter = function()
    local data = w.callback.await('w_medic:jobs:list', false)
    if type(data) ~= 'table' or not data.ok then return tell(data) end
    current = data
    local options = {
        { title = locale('jobs.hire'), description = locale('jobs.hire_desc'), event = UI .. 'hire' },
    }
    for i, d in ipairs(data.doctors or {}) do
        options[#options + 1] = {
            title = d.name,
            description = ('%s · %s'):format(d.label, locale(d.online and 'jobs.online' or 'jobs.offline')),
            arrow = d.touch,
            disabled = not d.touch,
            event = UI .. 'doctor',
            args = i,
        }
    end
    w.registerContext({ id = 'w_medic_jobs', title = locale('jobs.title'), options = options })
    w.showContext('w_medic_jobs')
end

--- the doctor a row named (by its place in `current`), only while this player may use the centre
local function picked(index)
    if LocalPlayer.state[STATE] ~= true or type(current) ~= 'table' then return nil end
    return (current.doctors or {})[tonumber(index)]
end

AddEventHandler(UI .. 'hire', function()
    if LocalPlayer.state[STATE] ~= true or type(current) ~= 'table' then return end
    hireDialog(current)
end)

AddEventHandler(UI .. 'doctor', function(index)
    local d = picked(index)
    if d and d.touch then doctorMenu(current, tonumber(index)) end
end)

AddEventHandler(UI .. 'rank', function(index)
    local d = picked(index)
    if not d then return end
    local ranks = targetRankOptions(current, d)
    if #ranks == 0 then return end
    local input = w.inputDialog(d.name, {
        { type = 'select', label = locale('jobs.rank'), options = ranks, required = true },
    })
    if not input then return openCenter() end
    tell(w.callback.await('w_medic:jobs:setRank', false, d.charId, tonumber(input[1])), 'jobs.done_rank')
    openCenter()
end)

AddEventHandler(UI .. 'fire', function(index)
    local d = picked(index)
    if not (d and d.fire) then return end
    local answer = w.alertDialog({
        header = locale('jobs.fire'),
        content = locale('jobs.fire_confirm', d.name),
        centered = true,
        cancel = true,
    })
    if answer ~= 'confirm' then return openCenter() end
    tell(w.callback.await('w_medic:jobs:fire', false, d.charId), 'jobs.done_fire')
    openCenter()
end)

-- w_store fires it when the key is pressed at the pharmacist (TriggerEvent, with the store id)
AddEventHandler(EVENT, function()
    if LocalPlayer.state[STATE] ~= true then return end
    openCenter()
end)

-- ── where the key lives ──────────────────────────────────────────────────────
-- On the pharmacist's prompt while w_store runs; a prompt of our own at the same desk otherwise.
local ownPrompt = nil
local function ensureOwnPrompt()
    if ownPrompt or not (Config.MDTDesk and Config.MDTDesk.coords) then return end
    local c = Config.MDTDesk.coords
    ownPrompt = w.prompt.at({
        coords = vector3(c.x, c.y, c.z),
        distance = Config.PromptDistance,
        title = locale('jobs.title'),
        prompts = { { key = KEY, label = locale('jobs.prompt'), hold = false, onComplete = function() TriggerEvent(EVENT) end } },
        canInteract = function() return LocalPlayer.state[STATE] == true and not isDead and not InLaststand end,
    })
end
local function dropOwnPrompt()
    if ownPrompt then pcall(ownPrompt.remove) ownPrompt = nil end
end

local function placeKey()
    if registerWithStore() then dropOwnPrompt() else ensureOwnPrompt() end
end

CreateThread(function()
    Wait(5000) -- w_store builds its groups and its store list first
    placeKey()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'w_store' then SetTimeout(3000, placeKey) end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'w_store' then ensureOwnPrompt() end
end)
