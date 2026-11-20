--- Money without a central bank (MajestyRP runs no w_centralbank): straight from / into the player's
--- cash through w_lib's framework bridge (VORP: currency 0 = cash). VORP's removeCurrency subtracts
--- without looking, so the balance is read first and nothing is taken that is not there.
local function bankUp()
    return exports.w_lib:EconName() == 'w_centralbank' and exports.w_lib:EconIsReady()
end
local function cashOf(src)
    local ok, money = pcall(function() return exports.w_lib:FwGetMoney(src) end)
    return ok and tonumber(money) or 0
end
local function takeCash(src, amount)
    amount = math.floor((tonumber(amount) or 0) * 100 + 0.5) / 100
    if amount <= 0 then return 0 end
    amount = math.min(amount, math.floor(cashOf(src) * 100) / 100)
    if amount <= 0 then return 0 end
    local ok, done = pcall(function() return exports.w_lib:FwRemoveCurrency(src, 0, amount) end)
    return (ok and done == true) and amount or 0
end
local function giveCash(src, amount)
    amount = math.floor((tonumber(amount) or 0) * 100 + 0.5) / 100
    if amount <= 0 then return false end
    local ok, done = pcall(function() return exports.w_lib:FwAddCurrency(src, 0, amount) end)
    return ok and done == true
end

--- The hospital bill (Config.BillCost), on every respawn and every bed stay. With a central bank it
--- goes from the patient's bank to the doctors' society; without one it comes out of his cash, as
--- much of it as he carries (nobody is left lying dead for want of $25).
local function payHospital(player)
    if not player then return false end
    if bankUp() then
        if not exports.w_lib:EconEnsureAccount('society:doctor', 'doctor', 'society') then return false end
        return exports.w_lib:EconTransfer('player:' .. player.PlayerData.citizenid .. ':bank', 'society:doctor', Config.BillCost, 'hospital-bill')
    end
    local paid = takeCash(player.PlayerData.source, Config.BillCost)
    if paid > 0 then
        w.notify(player.PlayerData.source, { description = 'info.bill_paid', type = 'inform', values = { paid } })
    end
    return paid > 0
end

--- The doctor's fee for a job actually done: a wound dressed, a man brought back. With a central bank
--- it is paid out of the society account the bills fill; without one it is minted into his cash.
---
--- It is called AFTER every check that can refuse the work, never before: on duty, same routing
--- bucket, within reach, and the bandage or the kit already taken off the medic. The idempotency key
--- carries who, to whom and when, so the same press cannot be paid twice, while two medics on the
--- same patient in the same second are two real jobs and both get paid.
--- ! 2026-10-14: it used to pay the PATIENT (the transfer named the patient's account).
---
---@param src integer the medic
---@param patientId integer the player treated
---@param kind string 'treat' | 'revive'
local function payDoctor(src, patientId, kind)
    if not Config.Pay.enabled then return false end
    local Doctor = WCore.Functions.GetPlayer(src)
    local Patient = WCore.Functions.GetPlayer(tonumber(patientId))
    if not Doctor or not Patient then return false end
    local amount = kind == 'revive' and Config.Pay.revive or Config.Pay.treat
    if not amount or amount <= 0 then return false end
    local ok
    if bankUp() then
        if not exports.w_lib:EconEnsureAccount('society:doctor', 'doctor', 'society') then return false end
        ok = exports.w_lib:EconTransfer('society:doctor', 'player:' .. Doctor.PlayerData.citizenid .. ':bank', amount,
            ('doctor-%s:%s:%s:%s'):format(kind, Patient.PlayerData.citizenid, src, GetGameTimer())) == true
    else
        ok = giveCash(src, amount)
    end
    if ok then
        w.notify(src, { description = 'info.received_payment', type = 'success', values = { amount } })
    end
    return ok
end

--- The salary of every doctor on duty (Config.DoctorRanks[grade].salary, ported from gw-medic), every
--- Config.Pay.paycheckInterval minutes. Off duty earns nothing; a grade with no row earns nothing.
CreateThread(function()
    local minutes = tonumber(Config.Pay and Config.Pay.paycheckInterval) or 0
    if minutes <= 0 then return end
    while true do
        Wait(minutes * 60 * 1000)
        for _, Player in pairs(WCore.Functions.GetWPlayers()) do
            local job = Player.PlayerData.job or {}
            if job.name == 'doctor' and job.onduty then
                local grade = tonumber(job.grade and job.grade.level) or 0
                local rank = Config.DoctorRanks and Config.DoctorRanks[grade]
                local salary = rank and tonumber(rank.salary) or 0
                if salary > 0 and giveCash(Player.PlayerData.source, salary) then
                    w.notify(Player.PlayerData.source, { description = 'info.paycheck', type = 'success', values = { salary } })
                end
            end
        end
    end
end)
-- ── a server that ran w_ambulancejob before this job ─────────────────────────────────
-- Its doctors' account was society:ambulance; this job's is society:doctor. What is left in the old
-- one moves over once, through the ledger (the request key makes every later start a no-op), so the
-- bills patients paid under w_ambulancejob still pay these doctors. A server without that account
-- skips it.
CreateThread(function()
    local n = 0
    while not bankUp() and n < 60 do Wait(1000) n = n + 1 end
    if not bankUp() then return end
    local ok, balance = pcall(function() return exports.w_lib:EconGetBalance('society:ambulance') end)
    balance = ok and tonumber(balance) or 0
    if balance <= 0 then return end
    if not exports.w_lib:EconEnsureAccount('society:doctor', 'doctor', 'society') then return end
    local moved, err = exports.w_lib:EconTransfer('society:ambulance', 'society:doctor', balance,
        'w_ambulancejob account -> w_medic', 'w_medic:migrate:society:ambulance')
    print(('[w_medic] society:ambulance -> society:doctor: %s %.2f%s'):format(
        moved and 'moved' or 'not moved', balance, moved and '' or (' (' .. tostring(err) .. ')')))
end)

local PlayerInjuries = {}
local PlayerWeaponWounds = {}

-- ── the pharmacy cabinet ───────────────────────────────────────────────────────────
--
-- The cabinet used to be a shop table the CLIENT built on every prompt, which is why it never ran
-- out. It is now the server's, in whichever shape the running server can hold, in this order:
--
--   w_store          -> a real government store row. The pharmacy then IS a shelf in the shop
--                       system: its prices, stock, cashier ped and blip belong to w_store, an
--                       admin restocks it from w_store's own panel, and the shop's distance and
--                       cash checks apply. This is the default and the one to use.
--   w_inventory      -> a real shop registered through its own RegisterShop export. The bag then
--                       owns the stock (refuses an empty slot, takes one off per purchase) and the
--                       job check (Shops[...].groups) -- neither of which a client-side table could
--                       ever enforce. Re-registering is a restock.
--   vorp_inventory   -> no runtime shop API exists: VORP keeps its shops in its own files, so a
--   rsg-inventory      foreign resource cannot add one. The cabinet becomes a server handout below.
--   qbr-inventory      The handout is not a downgrade: the server decides who gets what and how
--                       often, which is the same authority the shop had.
--
-- The bag is whatever w_lib's bridge says it is (w_lib:InvName honours the w_lib:inventory convar
-- and prefers w_inventory when started), so this follows the server's choice instead of second
-- guessing it.

-- ── w_store: the pharmacy as a real shop shelf ───────────────────────────────────────
--
-- Config.Pharmacy.useStore makes the cabinet a w_store government shelf instead of anything
-- the bag builds. One shelf per armory, so the three hospitals keep their own stock, their own
-- logs and their own blip, and every price and every restock belongs to w_store. This file
-- only owns the door: who may open it, and from where.
--
-- The shelf is a row in w_store's own tables, so it is created here the first time and never
-- again: a server that already has its pharmacy keeps it, and an admin who renames it in the
-- w_store panel is not fought by this resource (the shelf is matched on its name).

local function storeUp()
    return GetResourceState('w_store') == 'started'
end

--- w_store's own read helpers, through its public exports (server/main.lua of that resource).
local function listStores()
    if not storeUp() then return {} end
    local ok, res = pcall(function() return exports.w_store:GetStores() end)
    return (ok and type(res) == 'table') and res or {}
end

--- The pharmacy shelf of this armory, by name, or nil when w_store does not hold it.
local function storeByName(name)
    for _, s in ipairs(listStores()) do
        if s and s.name == name then return s end
    end
    return nil
end

--- Make w_store re-read its rows so a shelf written from here becomes openable (w_store fills its
--- cache only on its own boot). Through its Reload export: a global of another resource (WS) is
--- never reachable from here, which is why the old call here could only fail.
local function reloadStore()
    if not storeUp() then return false end
    local ok, done = pcall(function() return exports.w_store:Reload() end)
    if not ok or done ~= true then
        print(('[w_medic] the pharmacy shelves could not be reloaded (%s): restart w_store once'):format(tostring(done)))
        return false
    end
    return true
end

--- The clerk of a hospital's pharmacy: gw-medic's desk doctor (Config.MDTDesk) when the armory is
--- his desk, else the configured clerk standing at the armory. The shape w_store keeps for a spot.
local function clerkSpot(armory)
    local c = armory.coords or armory
    local desk = Config.MDTDesk
    local atDesk = desk and desk.coords and #(vector3(c.x, c.y, c.z) - vector3(desk.coords.x, desk.coords.y, desk.coords.z)) < 1.0
    local clerk = Config.Pharmacy.cashier or {}
    return {
        x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0,
        heading = atDesk and (desk.coords.w + 0.0) or 0.0,
        model = atDesk and desk.model or clerk.model or 'u_m_m_sdcustomvendor_01',
        scenario = atDesk and desk.scenario or clerk.scenario or 'WORLD_HUMAN_CLIPBOARD',
    }
end

-- the names the first version of this job shelved; this server never had either item
local LEGACY_ITEMS = { painkillers = true, firstaid = true }

--- One hospital's shelf, created when it is missing and repaired when it is ours (settings.pharmacy):
--- the clerk standing at the desk, doctors only, every configured item on the shelf at a price above
--- 0 (w_store refuses to sell at 0), the legacy item rows gone. A shelf an admin made by hand (no
--- marker) is never touched.
---@return boolean changed
local function ensureShelf(armory)
    local name = ('%s Pharmacy'):format(armory.city or 'Hospital')
    local cfg = Config.Pharmacy
    local row = MySQL.single.await('SELECT `id`, `cashier`, `settings` FROM `w_store_stores` WHERE `name` = ? LIMIT 1', { name })
    local changed = false

    if not row then
        local id = tonumber(MySQL.insert.await([[
            INSERT INTO `w_store_stores`
                (`name`, `kind`, `category`, `ownable`, `for_sale`, `price`,
                 `is_open`, `enabled`, `balance`, `cashier`, `supplier`, `wagon`, `settings`)
            VALUES (?, 'gov', 'items', 0, 0, 0, 1, 1, 0, ?, NULL, NULL, ?)
        ]], { name, json.encode(clerkSpot(armory)), json.encode({
            blip       = cfg.blip ~= false,
            blipSprite = cfg.blipSprite or 'blip_shop_doctor',
            blipColor  = cfg.blipColor or 'BLIP_MODIFIER_MP_COLOR_2',
            pharmacy   = true,        -- our marker, so the row is recognisable as ours
            jobs       = { 'doctor' }, -- only the doctors open it (w_store Config.Access)
        }) }))
        if not id then print(('[w_medic] the pharmacy %s could not be created'):format(name)) return false end
        row = { id = id }
        changed = true
        print(('^2[w_medic]^7 created the pharmacy shelf: %s (#%d)'):format(name, id))
    else
        local settings = (type(row.settings) == 'string' and json.decode(row.settings)) or {}
        if type(settings) ~= 'table' or settings.pharmacy ~= true then return false end -- not ours
        local cashier = type(row.cashier) == 'string' and json.decode(row.cashier) or nil
        if type(cashier) ~= 'table' or not tonumber(cashier.x) then
            MySQL.update.await('UPDATE `w_store_stores` SET `cashier` = ? WHERE `id` = ?', { json.encode(clerkSpot(armory)), row.id })
            changed = true
        end
        if type(settings.jobs) ~= 'table' or #settings.jobs == 0 then
            settings.jobs = { 'doctor' }
            MySQL.update.await('UPDATE `w_store_stores` SET `settings` = ? WHERE `id` = ?', { json.encode(settings), row.id })
            changed = true
        end
    end

    local have = {}
    for _, it in ipairs(MySQL.query.await('SELECT `item`, `sell_price` FROM `w_store_items` WHERE `store_id` = ?', { row.id }) or {}) do
        have[it.item] = tonumber(it.sell_price) or 0
    end
    for item in pairs(LEGACY_ITEMS) do
        if have[item] and not (cfg.storePrices or {})[item] then
            MySQL.update.await('DELETE FROM `w_store_items` WHERE `store_id` = ? AND `item` = ?', { row.id, item })
            changed = true
        end
    end
    for item, price in pairs(cfg.storePrices or {}) do
        price = math.max(tonumber(price) or 0, 0.01)
        if have[item] == nil then
            local n = math.max(tonumber((cfg.stock or {})[item]) or 0, 1)
            MySQL.insert.await([[
                INSERT INTO `w_store_items`
                    (`store_id`, `item`, `stock`, `max_stock`, `base_price`, `sell_price`, `supply_price`,
                     `buy_price`, `base_buy_price`, `sell_xp`, `enabled`, `sort_order`)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 1, 1)
            ]], { row.id, item, n, n, price, price, price })
            changed = true
        elseif have[item] <= 0 then
            MySQL.update.await('UPDATE `w_store_items` SET `base_price` = ?, `sell_price` = ?, `enabled` = 1 WHERE `store_id` = ? AND `item` = ?',
                { price, price, row.id, item })
            changed = true
        end
    end
    return changed
end

--- Every hospital's shelf, then w_store reloads when anything was written.
local function ensureStoreShelves()
    local ok, err = pcall(function()
        local changed = false
        for _, armory in ipairs(Config.Locations['armory'] or {}) do
            if ensureShelf(armory) then changed = true end
        end
        if changed then reloadStore() end
    end)
    if not ok then print(('[w_medic] the pharmacy shelves failed: %s'):format(tostring(err))) end
end

--- Once w_store is up and has filled its cache.
CreateThread(function()
    local cfg = Config.Pharmacy
    if not cfg.enabled or not cfg.useStore then return end
    local n = 0
    while not storeUp() and n < 120 do Wait(1000) n = n + 1 end
    if not storeUp() then return end
    -- w_store boots after MySQL and broadcasts; wait until it answers before writing rows
    n = 0
    while #listStores() == 0 and n < 30 do Wait(1000) n = n + 1 end
    ensureStoreShelves()
end)

--- The armory prompt's door when w_store is the shelf: only a doctor on duty standing at THIS
--- hospital may open THIS hospital's pharmacy. Every refusal carries its real reason, so the
--- client can show it in the doctor's own language.
---@return table|nil pharmacy, string|nil reason
local function storeDoor(src)
    local Player = WCore.Functions.GetPlayer(src)
    if not Player then return nil, 'no_player' end
    local job = Player.PlayerData.job or {}
    if job.name ~= 'doctor' then return nil, 'not_ems' end
    if not job.onduty then return nil, 'not_on_duty' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'no_ped' end
    local pos = GetEntityCoords(ped)

    local at = nil
    for _, v in ipairs(Config.Locations['armory'] or {}) do
        local c = v.coords or v   -- v.coords is the named form; v alone keeps the old table working
        local d = #(pos - vector3(c.x, c.y, c.z))
        if d <= (tonumber(Config.Pharmacy.openDistance) or 6.0) then at = v break end
    end
    if not at then return nil, 'too_far' end

    if not storeUp() then return nil, 'store_down' end

    local name = ('%s Pharmacy'):format(at.city or 'Hospital')
    local shelf = storeByName(name)
    if not shelf or not shelf.id then return nil, 'store_unknown' end

    return { at = at, name = name, id = tonumber(shelf.id) }
end

local function activeBag()
    local ok, name = pcall(function() return exports.w_lib:InvName() end)
    if ok and type(name) == 'string' and name ~= '' then return name end
    -- w_lib not up yet: fall back to the same order the bridge uses
    for _, n in ipairs({ 'w_inventory', 'rsg-inventory', 'qbr-inventory', 'vorp_inventory' }) do
        if GetResourceState(n) == 'started' then return n end
    end
    return nil
end

local shelfStock = {}   -- [item] = how many are left, for the handout path
local shelfTaken = {}   -- [src] = { first = ms, count = n }, for the per-medic limit

local function refillShelf()
    for name, n in pairs(Config.Pharmacy.stock or {}) do
        shelfStock[name] = tonumber(n) or 0
    end
end

--- Register with the bag when it has a runtime shop API; otherwise only top the shelf up.
---@return boolean registered, string mode 'shop' | 'handout'
local function setupPharmacy()
    local cfg = Config.Pharmacy
    if not cfg.enabled then return false, 'off' end
    refillShelf()
    if cfg.useStore and storeUp() then
        -- the shelf is w_store's row: nothing to register here, it was seeded on start
        return false, 'store'
    end
    local bag = activeBag()
    if bag ~= 'w_inventory' or not exports.w_lib:InvReady() then
        if bag then print(('[w_medic] pharmacy: %s has no runtime shop API, serving the cabinet by hand'):format(bag)) end
        return false, 'handout'
    end
    local shelf = {}
    for _, item in ipairs(Config.Items.items or {}) do
        shelf[#shelf + 1] = {
            name = item.name,
            count = tonumber(cfg.stock and cfg.stock[item.name]) or tonumber(item.amount) or 0,
            price = tonumber(item.price) or 0,
            info = item.info or {},
        }
    end
    if #shelf == 0 then return false, 'empty' end
    local ok, err = pcall(function()
        return exports.w_lib:InvRegisterShop(cfg.shopId, {
            label = Config.Items.label,
            groups = cfg.groups,
            inventory = shelf,
        })
    end)
    if not ok or err == false then
        print(('[w_medic] the pharmacy could not be registered: %s'):format(tostring(err)))
        return false, 'handout'
    end
    return true, 'shop'
end

--- The handout, for the bags with no runtime shop API. Everything is decided here: the job, the
--- duty, what is left on the shelf, how often this medic has come, and whether he can carry it.
--- The client only asks.
---
--- The distance is measured here too: the client checked it before pressing, but the client's
--- word is worth nothing to the server, and without this check a modified client could draw the
--- cabinet's stock from anywhere on the map. (This is the same hole the w_store path closes with
--- storeDoor above.)
---@return boolean ok, string reason
local function takeSupplies(src)
    local cfg = Config.Pharmacy
    local Player = WCore.Functions.GetPlayer(src)
    if not Player then return false, 'no_player' end
    local job = Player.PlayerData.job or {}
    if job.name ~= 'doctor' then return false, 'not_ems' end
    if not job.onduty then return false, 'not_on_duty' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'no_ped' end
    local pos = GetEntityCoords(ped)
    local atCabinet = false
    for _, v in ipairs(Config.Locations['armory'] or {}) do
        local c = v.coords or v   -- v.coords is the named form; v alone keeps the old table working
        if #(pos - vector3(c.x, c.y, c.z)) <= (tonumber(cfg.openDistance) or 6.0) then atCabinet = true break end
    end
    if not atCabinet then return false, 'too_far' end

    local window = (tonumber(cfg.windowMinutes) or 60) * 60 * 1000
    local seen = shelfTaken[src]
    if seen and GetGameTimer() - seen.first < window and seen.count >= (tonumber(cfg.maxPerWindow) or 3) then
        return false, 'limit'
    end

    local gave, names = 0, {}
    for name in pairs(cfg.stock or {}) do
        if gave >= (tonumber(cfg.maxPerVisit) or 1) then break end
        local want = tonumber(cfg.perVisit and cfg.perVisit[name]) or 1
        local left = tonumber(shelfStock[name]) or 0
        local n = math.min(want, left)
        if n > 0 and exports.w_lib:InvCanCarry(src, name, n) then
            if exports.w_lib:InvAddItem(src, name, n, {}) then
                shelfStock[name] = left - n
                gave = gave + 1
                names[#names + 1] = name
            end
        end
    end
    if gave == 0 then return false, 'no_stock' end

    shelfTaken[src] = seen and (GetGameTimer() - seen.first < window)
        and { first = seen.first, count = seen.count + 1 }
        or { first = GetGameTimer(), count = 1 }
    TriggerClientEvent('hospital:client:PharmacyHandout', src, names)
    return true, 'given'
end

--- The armory prompt. Which shelf it opens depends on the cabinet:
---   w_store running  -> the pharmacy is w_store's own shelf, so this opens w_store's page
---   w_inventory      -> the bag's own registered shop
---   anything else    -> the handout below
w.callback.register('w_medic:takeSupplies', function(src, city)
    local cfg = Config.Pharmacy

    if cfg.useStore and storeUp() then
        local door, reason = storeDoor(src)
        if not door then return { ok = false, error = reason } end
        -- the key the client claims is checked against the one measured here: a doctor at
        -- Valentine may not ask for Saint Denis' shelf from there
        if type(city) == 'string' and city ~= '' and city ~= (door.at.city or 'Hospital') then
            return { ok = false, error = 'too_far' }
        end
        -- ★ 2026-10-14: w_store's page opens from w_store's own prompt on its pharmacist (the
        --   armory prompt is not even built in this mode, client/job.lua). The old call here,
        --   w.callback.await('w_store:server:open', door.id, ...), asked a CLIENT callback of the
        --   player whose server id equals the store id: the cabinet never opened.
        return { ok = false, error = 'use_clerk' }
    end

    local ok, reason = takeSupplies(src)
    return { ok = ok, error = reason }
end)

AddEventHandler('playerDropped', function()
    shelfTaken[source] = nil
    -- The injuries and the weapon wounds are the player's too, and they are held under the
    -- server id. Without this they outlive the character, and because the id is handed to the
    -- next player who connects, the next doctor to open him reads the last one's wounds.
    PlayerInjuries[source] = nil
    PlayerWeaponWounds[source] = nil
end)

CreateThread(function()
    while not activeBag() do Wait(1000) end
    local minutes = tonumber(Config.Pharmacy.restockMinutes) or 60
    while minutes > 0 do
        setupPharmacy()
        Wait(minutes * 60 * 1000)
    end
end)

-- /pharmacy list  -- the three cabinets and which one w_store actually holds
-- /pharmacy seed  -- create only the shelves that are missing, then reload w_store
WCore.Commands.Add('pharmacy', 'the pharmacy cabinet', {
    { name = 'sub', help = 'list | seed' },
}, false, function(src, args)
    local sub = (args[1] or 'list'):lower()

    if sub == 'seed' then
        if not Config.Pharmacy.enabled then return w.notify(src, { description = 'error.pharmacy_down', type = 'error' }) end
        ensureStoreShelves()
        w.notify(src, { description = 'success.pharmacy_seeded', type = 'success' })

    else
        local lines = {}
        for _, v in ipairs(Config.Locations['armory'] or {}) do
            local name = ('%s Pharmacy'):format(v.city or 'Hospital')
            local s = storeByName(name)
            lines[#lines + 1] = ('%s: %s'):format(name, s and ('ready (#' .. tostring(s.id) .. ')') or 'MISSING')
        end
        w.notify(src, { description = 'info.pharmacy_list', type = 'inform', values = lines })
    end
end, 'admin')
-- The bed each player occupies (src -> bed id), from SendToBed / RespawnAtHospital until his client
-- leaves it (hospital:server:LeaveBed), his character logs out or he drops: the IsDead export
-- counts a bed stay, so w_creators refuses a character switch meanwhile.
local bedBySrc = {}

local function validBed(id)
	return type(id) == 'number' and Config.Locations["beds"][id] ~= nil
end

-- metres, measured on the server: the bed prompt stands at the bed and the check-in desk ~10 m from
-- the beds it hands out; the server's positions trail the clients' a little
local BED_REACH = 25.0

--- The player stands at that bed's hospital: next to the bed (the lie-in prompt) or at a check-in
--- desk that hands it out (CheckIn picks a free bed within 500 m of the player). SendToBed is a net
--- event and a bed stay heals and refills the needs (scheduleBedHeal): without this, any client
--- teleported itself into a bed from across the map and was fed there.
---@param src integer
---@param bedId integer a valid bed
---@return boolean
local function atHospital(src, bedId)
	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then return false end
	local pos = GetEntityCoords(ped)
	local c = Config.Locations["beds"][bedId].coords
	local bed = vector3(c.x, c.y, c.z)
	if #(pos - bed) <= BED_REACH then return true end
	for _, desk in pairs(Config.Locations["checking"] or {}) do
		local d = vector3(desk.x, desk.y, desk.z)
		if #(pos - d) <= BED_REACH and #(d - bed) < 500.0 then return true end
	end
	return false
end

local function occupyBed(src, id)
	local previous = bedBySrc[src]
	if previous and previous ~= id then
		TriggerClientEvent('hospital:client:SetBed', -1, previous, false)
	end
	bedBySrc[src] = id
	TriggerClientEvent('hospital:client:SetBed', -1, id, true)
end

local function releaseBed(src)
	local id = bedBySrc[src]
	if not id then return end
	bedBySrc[src] = nil
	TriggerClientEvent('hospital:client:SetBed', -1, id, false)
end

-- Hunger and thirst after a heal. The patient's client used to refill them itself
-- (WCore:Server:SetMetaData 'hunger' / 'thirst' 100), and that net event let any client fill its own
-- needs whenever it liked, around w_hud's food rules; w_core refuses it now. So every heal this
-- server grants (a revive or /aheal, the medic's treatment, the bed stay, the admin exports, the
-- txAdmin heal) refills them here, on the server. w_hud owns the needs and mirrors them into the
-- core metadata; without it the core metadata is written as w_core did before.
---@param src integer
local function refillNeeds(src)
	src = tonumber(src)
	if not src or src <= 0 then return end
	if GetResourceState('w_hud') == 'started' then
		-- an export that throws (w_hud restarting) must not break the heal that called it
		pcall(function()
			exports.w_hud:SetNeed(src, 'hunger', 100)
			exports.w_hud:SetNeed(src, 'thirst', 100)
		end)
		return
	end
	local Player = WCore.Functions.GetPlayer(src)
	if not Player then return end
	Player.Functions.SetMetaData('hunger', 100)
	Player.Functions.SetMetaData('thirst', 100)
	TriggerClientEvent('hud:client:UpdateNeeds', src, 100, 100, 100)
end

-- The hospital's own heal of a bed stay (check-in, lie-in, respawn): the patient's client heals him
-- Config.AIHealTimer seconds after he lies down (hospital:client:SendToBed). His needs are refilled
-- on the server at the same time, and only while he still holds the bed this timer was set for: a
-- stay that ended meanwhile (he left the bed, logged out or dropped) gets nothing.
local bedHealStay = {} -- [src] = the stay (a unique table) the pending refill belongs to

---@param src integer
---@param bedId integer
local function scheduleBedHeal(src, bedId)
	local stay = {}
	bedHealStay[src] = stay
	SetTimeout((tonumber(Config.AIHealTimer) or 0) * 1000, function()
		if bedHealStay[src] ~= stay then return end -- a newer stay owns the refill now
		bedHealStay[src] = nil
		if bedBySrc[src] ~= bedId then return end
		refillNeeds(src)
	end)
end
-- Events

-- Compatibility with txAdmin Menu's heal options.
-- This is an admin only server side event that will pass the target player id or -1.
AddEventHandler('txAdmin:events:healedPlayer', function(eventData)
	if GetInvokingResource() ~= "monitor" or type(eventData) ~= "table" or type(eventData.id) ~= "number" then
		return
	end

	TriggerClientEvent('hospital:client:Revive', eventData.id)
	TriggerClientEvent("hospital:client:HealInjuries", eventData.id, "full")
	-- -1 heals everybody: every player in the game gets his needs refilled with it
	if eventData.id == -1 then
		for _, id in ipairs(WCore.Functions.GetPlayers()) do refillNeeds(id) end
	else
		refillNeeds(eventData.id)
	end
end)

RegisterNetEvent('hospital:server:SendToBed', function(bedId, isRevive)
	local src = source
	if not validBed(bedId) or not atHospital(src, bedId) then return end

	-- The desk treatment, closed on the SERVER as well. CheckIn and LieInBed both stop at the
	-- client now (Config.OnlyTouchedByDoctors), but a client is not a promise: a modified one can
	-- send this event with isRevive and be put in a bed and healed by the hospital with no medic
	-- and no one paying. isRevive is the flag that means "heal this man after the timer", so that
	-- is what is refused here. The old bed stay (a patient lying down to be treated by a medic who
	-- arrives) still works, because it is the medic's own event, not this one.
	if Config.OnlyTouchedByDoctors ~= false and isRevive == true then
		local job = (WCore.Functions.GetPlayer(src) or {}).PlayerData
		job = job and job.job or {}
		local doctorOnDuty = job.name == 'doctor' and job.onduty == true
		if not doctorOnDuty then return end
	end

	local Player = WCore.Functions.GetPlayer(src)
	-- A patient is already in a bed: a second check-in would bill him a second time and would
	-- let the same request be spammed. bedBySrc is set here and cleared when he leaves.
	if isRevive == true and Player and bedBySrc[src] then return end

	TriggerClientEvent('hospital:client:SendToBed', src, bedId, Config.Locations["beds"][bedId], isRevive)
	occupyBed(src, bedId)
	-- isRevive: the client heals him after Config.AIHealTimer (check-in and lie-in always ask for it)
	if isRevive then scheduleBedHeal(src, bedId) end
	payHospital(Player)
end)

--- The respawn point nearest to where the player lies (Config.RespawnPoints), measured on the server
--- from his ped, never taken from his client.
---@return table|nil point, integer|nil index
local function nearestRespawnPoint(src)
	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then return nil end
	local pos = GetEntityCoords(ped)
	local best, bestDist
	for i, point in ipairs(Config.RespawnPoints or {}) do
		local d = #(pos - vector3(point.coords.x, point.coords.y, point.coords.z))
		if not bestDist or d < bestDist then best, bestDist = i, d end
	end
	if not best then return nil end
	return Config.RespawnPoints[best], best
end

--- 1.0.2: XP through w_level's activity table (w_level/config/xp_rules.lua decides the amount and the caps;
--- we only say what happened). Never yields, never throws.
local function levelXp(src, activity, ctx, key)
	if not src or GetResourceState('w_level') ~= 'started' then return end
	pcall(function() exports.w_level:Award(src, activity, ctx, key) end)
end

-- ★ The death is the man's own client's word (the server reads health 0 for a living ped on this
--   build, so it cannot check it). What the server CAN keep is the clock: when it first heard him
--   down (last stand, then dead once he bled out). His death screen opens the respawn only after
--   Config.TimeTillRespawn seconds of bleeding out, so a respawn sooner than that is not a dead
--   man's: it gets the bed and the bill, not the heal, the food or a teleport, and w_policejob does
--   not let it drop the cuffs (RespawnedDead below). Without it "dead" -> RespawnAtHospital ->
--   "uncuffed" -> "alive" walked a cuffed man out for the price of a bed.
local downSince = {}      -- [src] = GetGameTimer() when he first went down (last stand or dead)
local liftedAt = {}       -- [src] = GetGameTimer() when his last stand ended (a revive, or the bleed-out)
local respawnedDown = {}  -- [src] = GetGameTimer() of his last respawn as a man down long enough
local LIFT_GRACE_MS = 5000 -- the bleed-out reports "last stand over" a moment before "dead"

--- He stood up between two reports (a revive): the old clock no longer counts.
local function liftedFor(src)
	local at = liftedAt[src]
	return at ~= nil and GetGameTimer() - at > LIFT_GRACE_MS
end

local function markDown(src)
	if liftedFor(src) then downSince[src] = nil end
	liftedAt[src] = nil
	downSince[src] = downSince[src] or GetGameTimer()
end

local function downLongEnough(src)
	local since = downSince[src]
	if since == nil or liftedFor(src) then return false end
	return GetGameTimer() - since >= math.max(0, (tonumber(Config.TimeTillRespawn) or 60) - 15) * 1000
end

RegisterNetEvent('hospital:server:RespawnAtHospital', function(closestBed)
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if not Player then return end
	-- The respawn of a dead man (the death screen): his needs are refilled with the hospital's heal.
	-- The event is his client's, sent from wherever he lies, so only a man the server knows dead,
	-- and dead the whole bleed-out his death screen makes him wait, gets the heal, the refill and the
	-- teleport; a living sender still gets the bed and the bill, not the food.
	local meta = Player and Player.PlayerData.metadata or {}
	local down = meta.isdead == true and downLongEnough(src)
	if down then respawnedDown[src] = GetGameTimer() end
	-- 1.0.2: a death that ends at the hospital costs XP (w_level's table: never a level). A doctor's revive
	-- instead costs nothing. Once per downing (the server's own clock of when he went down).
	if down then levelXp(src, 'death', nil, ('death:%s:%s'):format(tostring(Player.PlayerData.citizenid), tostring(downSince[src] or os.time()))) end

	-- ★ 2026-10-14: the nearest of the five towns (Config.RespawnPoints). Valentine has the beds; in the
	--   other four he wakes up standing at the point, healed. That one is a teleport, so only a man
	--   the server knows down may take it - a living sender is refused, and his client is told so
	--   (else his respawn key would stay locked).
	local point, index = nearestRespawnPoint(src)
	if point and not point.beds then
		if not down then return TriggerClientEvent('hospital:client:RespawnRefused', src) end
		if Config.WipeInventoryOnRespawn then
			Player.Functions.ClearInventory()
			w.notify(src, { description = 'error.possessions_taken', type = 'error' })
		end
		TriggerClientEvent('hospital:client:WakeAt', src, index)
		refillNeeds(src)
		payHospital(Player)
		return
	end
	-- Check if Bed is taken else send to Bed 1
	if validBed(closestBed) and not Config.Locations["beds"][closestBed].taken then
		TriggerClientEvent('hospital:client:SendToBed', src, closestBed, Config.Locations["beds"][closestBed], true)
		occupyBed(src, closestBed)
		if down then scheduleBedHeal(src, closestBed) end
		if Config.WipeInventoryOnRespawn then
			Player.Functions.ClearInventory()
			w.notify(src, { description = 'error.possessions_taken', type = 'error' })
		end
		payHospital(Player)
	else
		--print("All beds were full, placing in first bed as fallback")
		TriggerClientEvent('hospital:client:SendToBed', src, 1, Config.Locations["beds"][1], true)
		occupyBed(src, 1)
		if down then scheduleBedHeal(src, 1) end
		if Config.WipeInventoryOnRespawn then
			Player.Functions.ClearInventory()
			w.notify(src, { description = 'error.possessions_taken', type = 'error' })
		end
		payHospital(Player)
	end
end)

-- Dispatch accepts a short sentence or a localized key with a small list of scalar arguments.
local dispatchAt, dispatchWindow = {}, { at = 0, count = 0 }
local function dispatchText(value)
    if type(value) == 'string' then
        if #value < 1 or #value > 500 or not utf8.len(value) then return nil end
        local clean = value:gsub('%c', ' '):match('^%s*(.-)%s*$')
        return clean ~= '' and clean or nil
    end
    if type(value) ~= 'table' or type(value.key) ~= 'string' or #value.key > 80
        or not value.key:match('^[%w_%.]+$') then return nil end
    local args, clean = value.args or {}, {}
    if type(args) ~= 'table' or #args > 8 then return nil end
    for i = 1, #args do if args[i] == nil then return nil end end
    for k, arg in pairs(args) do
        if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 or k > #args then return nil end
        if type(arg) == 'string' then
            if #arg > 120 or not utf8.len(arg) then return nil end
            clean[k] = arg:gsub('%c', ' ')
        elseif type(arg) == 'number' and arg == arg and math.abs(arg) <= 1e9 then clean[k] = arg
        else return nil end
    end
    local ok, rendered = pcall(locale, value.key, table.unpack(clean))
    if not ok or rendered == value.key then return nil end
    return { key = value.key, args = clean }
end
local function dispatchAllowed(src)
    local now = GetGameTimer()
    if dispatchAt[src] and now - dispatchAt[src] < 3000 then return false end
    if now - dispatchWindow.at >= 1000 then dispatchWindow = { at = now, count = 0 } end
    if dispatchWindow.count >= 10 then return false end
    dispatchAt[src], dispatchWindow.count = now, dispatchWindow.count + 1
    return true
end
AddEventHandler('playerDropped', function() dispatchAt[source] = nil end)

RegisterNetEvent('hospital:server:ambulanceAlert', function(text)
    local src = source
    local ped = GetPlayerPed(src)
    local clean = dispatchText(text)
    if not ped or ped == 0 or not clean or not dispatchAllowed(src) then return end
    local coords, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(src)
    for _, player in pairs(WCore.Functions.GetWPlayers()) do
        local data = player and player.PlayerData
        local job = data and data.job
        if job and job.name == 'doctor' and job.onduty and GetPlayerRoutingBucket(data.source) == bucket then
            TriggerClientEvent('hospital:client:ambulanceAlert', data.source, coords, clean)
        end
    end
end)

RegisterNetEvent('hospital:server:LeaveBed', function(id)
    local src = source
    if bedBySrc[src] ~= nil then
        releaseBed(src)
    elseif validBed(id) then
        -- a bed this player no longer holds: free it only when nobody else is lying in it
        for _, taken in pairs(bedBySrc) do
            if taken == id then return end
        end
        TriggerClientEvent('hospital:client:SetBed', -1, id, false)
    end
end)

-- A character logging out (w_core's Logout, also a w_creators character switch) or a player
-- dropping leaves his bed.
exports.w_lib:FwOnCharacterUnloaded(function(src)
    releaseBed(tonumber(src) or src)
end)

-- The client reports its own injuries; labels and structural limits belong to the server.
local injuryParts = {
    HEAD = 'body.head', NECK = 'body.neck', SPINE = 'body.spine', UPPER_BODY = 'body.upper_body',
    LOWER_BODY = 'body.lower_body', LARM = 'body.left_arm', LHAND = 'body.left_hand', LFINGER = 'body.left_fingers',
    LLEG = 'body.left_leg', LFOOT = 'body.left_foot', RARM = 'body.right_arm', RHAND = 'body.right_hand',
    RFINGER = 'body.right_fingers', RLEG = 'body.right_leg', RFOOT = 'body.right_foot',
}
local injuryAt, weaponAt = {}, {}
local function injuryLevel(value)
    return type(value) == 'number' and value == value and value % 1 == 0 and value >= 0 and value <= 4
end
RegisterNetEvent('hospital:server:SyncInjuries', function(data)
    local src, now = source, GetGameTimer()
    if type(data) ~= 'table' or not injuryLevel(data.isBleeding) or type(data.limbs) ~= 'table' then return end
    if injuryAt[src] and now - injuryAt[src] < 200 then return end
    local limbs, count = {}, 0
    for key, part in pairs(data.limbs) do
        count = count + 1
        if count > 15 or not injuryParts[key] or type(part) ~= 'table'
            or type(part.isDamaged) ~= 'boolean' or not injuryLevel(part.severity) then return end
        limbs[key] = { label = injuryParts[key], isDamaged = part.isDamaged, severity = part.severity }
    end
    injuryAt[src], PlayerInjuries[src] = now, { isBleeding = data.isBleeding, limbs = limbs }
end)
RegisterNetEvent('hospital:server:SetWeaponDamage', function(data)
    local src, now = source, GetGameTimer()
    if type(data) ~= 'table' or #data > 64 or (weaponAt[src] and now - weaponAt[src] < 200) then return end
    if not WCore.Functions.GetPlayer(src) then return end
    local clean = {}
    for i = 1, #data do
        local name = data[i]
        if type(name) ~= 'string' or #name > 80 or not name:match('^WEAPON_[A-Z0-9_]+$') then return end
        clean[i] = name
    end
    for key in pairs(data) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #data then return end
    end
    weaponAt[src], PlayerWeaponWounds[src] = now, clean
end)
AddEventHandler('playerDropped', function() injuryAt[source], weaponAt[source] = nil, nil end)

RegisterNetEvent('hospital:server:RestoreWeaponDamage', function()
	PlayerWeaponWounds[source] = nil
end)

RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
	local src = source
	if type(isDead) ~= 'boolean' then return end
	local Player = WCore.Functions.GetPlayer(src)
	if Player then
		Player.Functions.SetMetaData("isdead", isDead)
		if isDead then markDown(src) else downSince[src], liftedAt[src] = nil, nil end
	end
end)

RegisterNetEvent('hospital:server:SetLaststandStatus', function(bool)
	local src = source
	if type(bool) ~= 'boolean' then return end
	local Player = WCore.Functions.GetPlayer(src)
	if Player then
		Player.Functions.SetMetaData("inlaststand", bool)
		if bool then markDown(src) else liftedAt[src] = GetGameTimer() end
	end
end)

--- Did this man respawn at the hospital, within the last minute, after lying down the full bleed-out?
--- (w_policejob: only such a respawn drops the cuffs.)
exports('RespawnedDead', function(playerId)
	local at = respawnedDown[tonumber(playerId)]
	return at ~= nil and GetGameTimer() - at < 60000
end)

AddEventHandler('playerDropped', function()
	downSince[source], liftedAt[source], respawnedDown[source] = nil, nil, nil
end)

-- The medic's treatment (the patient prompt, or /heal on the closest player). The medic's client
-- picks the patient and sends his server id, and a modified client can send any id: heal a friend
-- across the map or in another routing bucket, off duty, without a bandage, with a full belly and
-- full water on top (refillNeeds). So the server checks what it knows itself: the medic has the job
-- and is on duty, the patient is another player in the game, in the same routing bucket and within
-- reach, and a bandage is used up (no bandage, no treatment).
-- metres, measured on the server: the prompt shows within Config.PatientDistance and /heal picks
-- within 5 m (a kit from the bag: 1.5 m), the patient may step away during the 5 s treatment, and
-- the server's positions trail the clients' a little. The kit revive (below) uses it too.
local TREAT_REACH = 10.0

--- Both players in the same routing bucket and within `reach` metres of each other (server side).
---@param a integer
---@param b integer
---@param reach number
---@return boolean
local function withinReach(a, b, reach)
	if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
	local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
	if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
	return #(GetEntityCoords(pedA) - GetEntityCoords(pedB)) <= reach
end

RegisterNetEvent('hospital:server:TreatWounds', function(playerId)
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if not Player then return end
	-- a number only: WCore.Functions.GetPlayer reads a string as a license / identifier
	local id = tonumber(playerId)
	local Patient = id and id ~= src and WCore.Functions.GetPlayer(id) or nil
	local job = Player.PlayerData.job or {}
	if job.name ~= 'doctor' then
		return w.notify(src, { description = 'error.not_ems', type = 'error' })
	end
	if not job.onduty then
		return w.notify(src, { description = 'error.not_on_duty', type = 'error' })
	end
	if not Patient or not withinReach(src, id, TREAT_REACH) then
		return w.notify(src, { description = 'error.no_player', type = 'error' })
	end
	if not Player.Functions.RemoveItem(Config.ItemNames.bandage, 1) then
		return w.notify(src, { description = 'error.no_bandage', type = 'error' })
	end
	TriggerClientEvent("hospital:client:HealInjuries", Patient.PlayerData.source, "full")
	refillNeeds(Patient.PlayerData.source)
	-- every check above has passed and the bandage is spent: the work is done, so it is paid
	payDoctor(src, id, 'treat')
	levelXp(src, 'doctor_treat', { target = id }) -- 1.0.2: the level (w_level's table: the same patient counts once in a while)
end)

RegisterNetEvent('hospital:server:SetDoctor', function()
	local amount = 0
    local players = WCore.Functions.GetWPlayers()
    for k,v in pairs(players) do
        if v.PlayerData.job.name == 'doctor' and v.PlayerData.job.onduty then
            amount = amount + 1
        end
	end
	TriggerClientEvent("hospital:client:SetDoctorCount", -1, amount)
end)

-- A revive by a medic or by anybody with a kit. The helper's client picks the patient and sends
-- his server id: a modified client could revive (and refill) anybody across the map. So, as for
-- the treatment, the patient is another player in the game, in the same routing bucket and within
-- reach (the helper kneels next to him for the whole progress bar). The patient's hunger and
-- thirst are refilled here, on the server, when the server knows him dead or in last stand: w_hud
-- no longer takes his client's word for the refill after a revive while this resource runs.
RegisterNetEvent('hospital:server:RevivePlayer', function(playerId)
    local src = source
    local Player = WCore.Functions.GetPlayer(src)
    -- a number only: WCore.Functions.GetPlayer reads a string as a license / identifier
    local id = tonumber(playerId)
    local Patient = id and id ~= src and WCore.Functions.GetPlayer(id) or nil
    if not Player then return end
    -- ★ 2026-10-14 (owner): only a doctor on duty revives - a kit in anybody else's bag does nothing
    local job = Player.PlayerData.job or {}
    if job.name ~= 'doctor' then return w.notify(src, { description = 'error.not_ems', type = 'error' }) end
    if not job.onduty then return w.notify(src, { description = 'error.not_on_duty', type = 'error' }) end
    if not Patient or not withinReach(src, id, TREAT_REACH) then
        return w.notify(src, { description = 'error.no_player', type = 'error' })
    end
    local meta = Patient.PlayerData.metadata or {}
    local down = meta.isdead == true or meta.inlaststand == true
    -- The kit is charged here, once, when the revive is done - by a medic (job menu) or by anyone
    -- who used a kit from the bag on a downed player. No kit left, no revive.
    if Player.Functions.RemoveItem(Config.ItemNames.revive, 1) then
        TriggerClientEvent('hospital:client:Revive', Patient.PlayerData.source)
        if down then refillNeeds(Patient.PlayerData.source) end
        -- reach checked, kit spent, man standing: the revive happened, so it is paid
        payDoctor(src, id, 'revive')
        -- 1.0.2: the level (w_level's table), for a man who was really down: the doctor, and the patient a little
        -- (he was spared the hospital's loss). Once per downing.
        if down then
            local k = ('revive:%s:%s'):format(tostring(Patient.PlayerData.citizenid), tostring(downSince[id] or os.time()))
            levelXp(src, 'doctor_revive', { target = id }, k)
            levelXp(id, 'revived_by_doctor', nil, k)
        end
    end
end)

RegisterNetEvent('hospital:server:SendDoctorAlert', function()
    local players = WCore.Functions.GetWPlayers()
    for k,v in pairs(players) do
        if v.PlayerData.job.name == 'doctor' and v.PlayerData.job.onduty then
			w.notify(v.PlayerData.source, { description = 'info.dr_needed', type = 'inform' })
		end
	end
end)

RegisterNetEvent('hospital:server:UseFirstAid', function(targetId)
	local src = source
	local Helper = WCore.Functions.GetPlayer(src)
	local job = Helper and Helper.PlayerData.job or {}
	if job.name ~= 'doctor' then return w.notify(src, { description = 'error.not_ems', type = 'error' }) end
	if not job.onduty then return w.notify(src, { description = 'error.not_on_duty', type = 'error' }) end
	local Target = WCore.Functions.GetPlayer(targetId)
	if Target then
		TriggerClientEvent('hospital:client:CanHelp', targetId, src)
	else
		w.notify(src, { description = 'error.no_player', type = 'error' })
	end
end)

-- 1.0.7: why first aid does not apply, from the patient's client (a closed list: nothing else is shown)
local CANT_HELP = { dead = 'error.cant_help_dead', not_down = 'error.cant_help_not_down' }

RegisterNetEvent('hospital:server:CanHelp', function(helperId, canHelp, why)
	local src = source
	if canHelp then
		TriggerClientEvent('hospital:client:HelpPerson', helperId, src)
	else
		w.notify(helperId, { description = CANT_HELP[why] or 'error.cant_help', type = 'error' })
	end
end)

-- The doctor's own locker at the hospital (Config.Locations.stash): one per character, opened through
-- w_lib's bag bridge, only for a doctor standing at a locker.
local STASH_REACH = 4.0
local stashReady = {}
RegisterNetEvent('w_medic:server:openStash', function()
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if not Player or (Player.PlayerData.job or {}).name ~= 'doctor' then return end
	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then return end
	local pos, near = GetEntityCoords(ped), false
	for _, v in pairs(Config.Locations['stash'] or {}) do
		if #(pos - vector3(v.x, v.y, v.z)) <= STASH_REACH then near = true break end
	end
	if not near then return end
	local id = 'ambulancestash_' .. tostring(Player.PlayerData.citizenid)
	if not stashReady[id] then
		local ok, done = pcall(function() return exports.w_lib:InvRegisterStash(id, locale('text.pstash'), 30, 100) end)
		stashReady[id] = ok and done ~= false
	end
	pcall(function() exports.w_lib:InvOpenStash(src, id) end)
end)

-- Cosmetic surgery: performed by w_creators. The station prompt asks here; w_creators gives the
-- player a one-use grant for the clinic and opens it, re-validating the service, the clinic, the
-- distance and the price (clinics without their own prompt open only through this export).
local surgeryRequests = {} -- [src] = GetGameTimer() of the last request

local function surgeryClinic(clinicId)
	local cfg = Config.CosmeticSurgery
	if type(cfg) ~= 'table' or not cfg.enabled or type(clinicId) ~= 'string' then return nil end
	-- the clinics w_creators' board places (client/job.lua shows their prompts); else the config list
	local ok, points = pcall(function() return GlobalState['w_creators:clinicPoints'] end)
	if ok and type(points) == 'table' then return points[clinicId] end
	for _, clinic in ipairs(cfg.clinics or {}) do
		if clinic.clinicId == clinicId then return clinic end
	end
	return nil
end

RegisterNetEvent('hospital:server:requestCosmeticSurgery', function(clinicId)
	local src = source
	local cfg = Config.CosmeticSurgery or {}
	local now = GetGameTimer()
	local last = surgeryRequests[src]
	if last and now - last < (tonumber(cfg.cooldown) or 3) * 1000 then return end
	surgeryRequests[src] = now
	if not surgeryClinic(clinicId) then return end
	local Player = WCore.Functions.GetPlayer(src)
	local meta = Player and Player.PlayerData.metadata or {}
	local down = meta.isdead == true or meta.inlaststand == true
	local result
	if Player and not down and GetResourceState('w_creators') == 'started' then
		local ok, answer = pcall(function()
			return exports.w_creators:OpenCosmeticSurgery({ source = src, clinicId = clinicId })
		end)
		result = ok and answer or nil
	end
	if type(result) ~= 'table' or result.ok ~= true then
		-- w_creators' message keys belong to its own dictionary: this resource shows its own
		w.notify(src, { description = 'error.surgery_unavailable', type = 'error' })
	end
end)

AddEventHandler('playerDropped', function()
	surgeryRequests[source] = nil
	releaseBed(source)
end)

-- Callbacks

WCore.Functions.CreateCallback('hospital:GetDoctors', function(source, cb)
	local amount = 0
    local players = WCore.Functions.GetWPlayers()
    for k,v in pairs(players) do
        if v.PlayerData.job.name == 'doctor' and v.PlayerData.job.onduty then
			amount = amount + 1
		end
	end
	cb(amount)
end)

WCore.Functions.CreateCallback('hospital:GetPlayerStatus', function(source, cb, playerId)
	local Player = WCore.Functions.GetPlayer(playerId)
	local injuries = {}
	injuries["WEAPONWOUNDS"] = {}
	if Player then
		if PlayerInjuries[Player.PlayerData.source] then
			if (tonumber(PlayerInjuries[Player.PlayerData.source].isBleeding) or 0) > 0 then
				injuries["BLEED"] = PlayerInjuries[Player.PlayerData.source].isBleeding
			end
			for k, v in pairs(type(PlayerInjuries[Player.PlayerData.source].limbs) == 'table' and PlayerInjuries[Player.PlayerData.source].limbs or {}) do
				if type(v) == 'table' and v.isDamaged then
					injuries[k] = PlayerInjuries[Player.PlayerData.source].limbs[k]
				end
			end
		end
		if PlayerWeaponWounds[Player.PlayerData.source] then
			for k, v in pairs(PlayerWeaponWounds[Player.PlayerData.source]) do
				injuries["WEAPONWOUNDS"][k] = v
			end
		end
	end
    cb(injuries)
end)

WCore.Functions.CreateCallback('hospital:GetPlayerBleeding', function(source, cb)
	local src = source
	if PlayerInjuries[src] and PlayerInjuries[src].isBleeding then
		cb(PlayerInjuries[src].isBleeding)
	else
		cb(nil)
	end
end)

-- Commands

-- (only with Config.EmsCallCommand: a downed player calls with G, a standing one walks in)
if Config.EmsCallCommand then WCore.Commands.Add('911e', locale('info.ems_report'), {{name = 'message', help = locale('info.message_sent')}}, false, function(source, args)
	-- free text is shown as is; without text the key is sent and translated by each doctor's client
	local message = args[1] and table.concat(args, " ") or 'info.civ_call'
    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local players = WCore.Functions.GetWPlayers()
    for k,v in pairs(players) do
        if v.PlayerData.job.name == 'doctor' and v.PlayerData.job.onduty then
            TriggerClientEvent('hospital:client:ambulanceAlert', v.PlayerData.source, coords, message)
        end
    end
end) end

WCore.Commands.Add("status", locale('info.check_health'), {}, false, function(source, args)
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if Player and Player.PlayerData.job.name == 'doctor' then
		TriggerClientEvent("hospital:client:CheckStatus", src)
	else
		w.notify(src, { description = 'error.not_ems', type = 'error' })
	end
end)

-- ★ 2026-10-14: /treat and /medrevive, not /heal and /revive: vorp_core owns those two names (the
--   admin heal / revive by server id), and a second RegisterCommand of a name silently replaces the
--   first - the admins' commands would have changed meaning under them.
WCore.Commands.Add("treat", locale('info.heal_player'), {}, false, function(source, args)
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if Player and Player.PlayerData.job.name == 'doctor' then
		TriggerClientEvent("hospital:client:TreatWounds", src)
	else
		w.notify(src, { description = 'error.not_ems', type = 'error' })
	end
end)

WCore.Commands.Add("revivep", locale('info.revive_player'), {}, false, function(source, args)
	local src = source
	local Player = WCore.Functions.GetPlayer(src)
	if Player and Player.PlayerData.job.name == 'doctor' then
		TriggerClientEvent("hospital:client:RevivePlayer", src)
	else
		w.notify(src, { description = 'error.not_ems', type = 'error' })
	end
end)

-- The admin commands on a player (/revive, /setpain, /kill, /aheal) name him by his citizen id
-- (players.citizenid: '12', a vanity '777', an old 'OMG95204'), the one id that never changes;
-- '#5' still means server id 5 on purpose, and no id (or 'me') is the admin himself. A server id
-- changes on every connection and, since the citizen id is plain digits, the two collided:
-- "/revive 12" revived whoever held server id 12, or answered "not online". w.citizen says who
-- the id is and whether he is in the game (then his server id comes with the answer).

--- A notice for the admin (his client translates a dictionary key), or the console.
---@param src integer
---@param data { title?: string, description: string, type: string }
local function tellAdmin(src, data)
	if src and src > 0 then return w.notify(src, data) end
	print(('[w_medic] %s%s'):format(data.title and (data.title .. ': ') or '', locale(data.description)))
end

--- Tell the admin why the id names nobody he can act on; `offline` (a target) names the man.
---@param src integer
---@param reason string|nil 'invalid_id' | 'not_found' | 'offline'
---@param offline table|nil
local function refuseTarget(src, reason, offline)
	tellAdmin(src, {
		title = offline and w.citizen.label(offline) or nil,
		description = w.citizen.reasonText(reason, src > 0 and src or nil),
		type = 'error',
	})
end

--- A character who is not in the game: w_core's own offline player (his saved row), the same
--- SetMetaData as in play, then saved, so what is set here is on his file when he logs in.
---@param citizenid string
---@param values table<string, any>
---@return boolean
local function setOfflineMetadata(citizenid, values)
	local ok, player = pcall(function() return WCore.Functions.GetOfflinePlayerByCitizenId(citizenid) end)
	if not ok or type(player) ~= 'table' or type(player.Functions) ~= 'table' then return false end
	-- the Functions are funcrefs into w_core: a failed call is a "could not" for the admin, not
	-- an error that leaves him with no answer
	return (pcall(function()
		for key, value in pairs(values) do player.Functions.SetMetaData(key, value) end
		player.Functions.Save()
	end))
end

--- Fire a client event on the player a command names: no id is the admin himself (as before);
--- these act on the live ped, so a character who is not in the game is refused by name.
---@param src integer
---@param arg string|nil the id as typed
---@param event string
---@return integer|nil target the server id the event went to (nil when refused)
local function onNamedPlayer(src, arg, event)
	if arg == nil or arg == '' then
		TriggerClientEvent(event, src)
		return src
	end
	local target, reason, offline = w.citizen.requireOnline(arg, { self = src })
	if not target then
		refuseTarget(src, reason, offline)
		return nil
	end
	TriggerClientEvent(event, target.source)
	return target.source
end

--- The admin revive of a player in the game: his client revives and heals the ped, the server
--- refills his needs (refillNeeds; the client's own refill is refused by w_core).
---@param id integer
local function reviveInGame(id)
	TriggerClientEvent('hospital:client:Revive', id)
	refillNeeds(id)
end

-- (registered only with Config.AdminRevive: on this server only a doctor revives)
if Config.AdminRevive then WCore.Commands.Add("medrevive", locale('info.revive_player_a'), {{name = "id", help = locale('info.player_id')}}, false, function(source, args)
	local src = source
	if args[1] == nil or args[1] == '' then return reviveInGame(src) end
	local target, reason = w.citizen.resolve(args[1], { self = src })
	if not target then return refuseTarget(src, reason) end
	if target.online then return reviveInGame(target.source) end
	-- not in the game: a character who logged out dead logs in dead (client/job.lua reads isdead
	-- and inlaststand at login), so clearing both on his file brings him back alive
	if setOfflineMetadata(target.citizenid, { isdead = false, inlaststand = false }) then
		tellAdmin(src, { title = w.citizen.label(target), description = 'success.revived_offline', type = 'success' })
	else
		tellAdmin(src, { title = w.citizen.label(target), description = 'error.record_failed', type = 'error' })
	end
end, "admin") end

WCore.Commands.Add("setpain", locale('info.pain_level'), {{name = "id", help = locale('info.player_id')}}, false, function(source, args)
	onNamedPlayer(source, args[1], 'hospital:client:SetPain')
end, "admin")

WCore.Commands.Add("kill", locale('info.kill'), {{name = "id", help = locale('info.player_id')}}, false, function(source, args)
	onNamedPlayer(source, args[1], 'hospital:client:KillPlayer')
end, "admin")

WCore.Commands.Add('aheal', locale('info.heal_player_a'), {{name = 'id', help = locale('info.player_id')}}, false, function(source, args)
	-- the client heals the ped; the needs are the server's to refill
	local healed = onNamedPlayer(source, args[1], 'hospital:client:adminHeal')
	if healed then refillNeeds(healed) end
end, 'admin')

-- Items

WCore.Functions.CreateUseableItem(Config.ItemNames.ifak, function(source, item)
    local Player = WCore.Functions.GetPlayer(source)
	if Player and Player.Functions.RemoveItem(item.name, 1, item.slot) then
		TriggerClientEvent("hospital:client:UseIfaks", source, item.name)
    end
end)

WCore.Functions.CreateUseableItem(Config.ItemNames.bandage, function(source, item)
    local Player = WCore.Functions.GetPlayer(source)
	if Player and Player.Functions.RemoveItem(item.name, 1, item.slot) then
		TriggerClientEvent("hospital:client:UseBandage", source, item.name)
	end
end)

WCore.Functions.CreateUseableItem(Config.ItemNames.painkiller, function(source, item)
    local Player = WCore.Functions.GetPlayer(source)
	if Player and Player.Functions.RemoveItem(item.name, 1, item.slot) then
		TriggerClientEvent("hospital:client:UsePainkillers", source, item.name)
	end
end)

-- ! Not charged on use: the revive it leads to (hospital:server:RevivePlayer) charges the kit.
--   Taking one here as well cost two kits per revive, and a kit used with nobody downed within
--   reach (or a cancelled revive) was simply lost.
WCore.Functions.CreateUseableItem(Config.ItemNames.revive, function(source, item)
	local Player = WCore.Functions.GetPlayer(source)
	local job = Player and Player.PlayerData.job or {}
	if job.name ~= 'doctor' then return w.notify(source, { description = 'error.not_ems', type = 'error' }) end
	if not job.onduty then return w.notify(source, { description = 'error.not_on_duty', type = 'error' }) end
	TriggerClientEvent("hospital:client:UseFirstAid", source, item.name)
end)

-- ── the doctor's job label follows his grade ───────────────────────────────────────────
-- ★ 2026-10-14 (owner: "the VORP doctor job and grades as in GW"): Config.DoctorRanks are
--   gw-medic's ranks, and vorp_core registers the doctor job with exactly those grades
--   (vorp_core config/jobs.lua). The label a character carried was whatever its giver typed
--   (/setjob) or picked (/jobs): a grade 3 doctor read "المارشال", a grade 1 one "طبيب متدرب"
--   (grade 0's name). Each doctor's label is set from his grade when he logs in and a moment after
--   any change of job or grade (VORP announces those before it stores them).

--- The rank name of a grade (Config.DoctorRanks, without its padding), or nil (no such rank: 4).
---@return string|nil
local function rankLabel(grade)
	local rank = Config.DoctorRanks and Config.DoctorRanks[tonumber(grade) or -1]
	if not rank or type(rank.label) ~= 'string' then return nil end
	local label = rank.label:gsub('^%s+', ''):gsub('%s+$', '')
	return label ~= '' and label or nil
end

local function fixDoctorLabel(src)
	src = tonumber(src)
	if not src or not GetPlayerName(src) then return end
	local ok, job, grade, have = pcall(function()
		return exports.w_lib:FwGetJob(src), exports.w_lib:FwGetJobGrade(src), exports.w_lib:FwGetJobLabel(src)
	end)
	if not ok or job ~= 'doctor' then return end
	local want = rankLabel(grade)
	if want and have ~= want then
		pcall(function() exports.w_lib:FwSetJobLabel(src, want) end)
	end
end

-- ── the jobs centre: gw-medic's recruitment terminal, at gw-medic's desk ─────────────────
-- ★ 2026-10-14 (owner: "where do the head of the doctors or an admin give the job - like GW, same
--   place"): the health minister and his deputy (Config.DoctorRanks[grade].canAccessAdmin, as
--   gw-medic had it) and the admins hire doctors, change their rank and dismiss them, standing at
--   gw-medic's desk (Config.MDTDesk - the Valentine pharmacist; the key sits on his prompt through
--   w_store, client/jobs_center.lua). Rules, all checked here: nobody touches his own rank; a
--   manager gives only ranks below his own and touches only doctors below him; an admin may do
--   anything. A doctor who is not in the game is changed on his saved character.
local JOBS_DESK_REACH = 6.0

local function fwc(name, ...)
	local ok, value = pcall(function(...) return exports.w_lib['Fw' .. name](nil, ...) end, ...)
	if ok then return value end
	return nil
end

local function isAdminSrc(src)
	local ok, admin = pcall(function() return exports.w_lib:IsAdmin(src) end)
	if ok and admin == true then return true end
	return IsPlayerAceAllowed(src, 'w_medic.admin') == true
end

--- nil, or what he may do: { admin = bool, grade = his doctor grade or nil, charId }
local function jobsAccess(src)
	src = tonumber(src)
	if not src or not GetPlayerName(src) then return nil end
	local charId = tonumber(fwc('GetCharacterIdentifier', src))
	if not charId then return nil end
	local grade = fwc('GetJob', src) == 'doctor' and tonumber(fwc('GetJobGrade', src)) or nil
	local rank = grade and Config.DoctorRanks[grade]
	local admin = isAdminSrc(src)
	if admin or (rank and rank.canAccessAdmin) then
		return { admin = admin, grade = grade, charId = charId }
	end
	return nil
end

-- ★ 2026-10-14 (owner): "the admin gives the job to the head, and the head is responsible for
--   the doctors and their promotions". The head is the highest rank (6, the health minister). An
--   admin appoints him (hires a player or promotes a doctor to it) and may dismiss him - nothing
--   else; the ranks below are the head's (and his deputy's) to give. An admin who is also a doctor
--   manager keeps what his rank gives him.
local HEAD_GRADE = nil
for grade in pairs(Config.DoctorRanks) do
	if not HEAD_GRADE or grade > HEAD_GRADE then HEAD_GRADE = grade end
end

--- May he give this rank to a player who is not a doctor yet (hire)?
local function mayGive(access, grade)
	grade = tonumber(grade)
	if not grade or not Config.DoctorRanks[grade] then return false end
	if access.grade ~= nil and grade < access.grade then return true end
	return access.admin and grade == HEAD_GRADE
end

--- May he set this doctor (now at targetGrade) to rank `grade`?
local function maySet(access, targetGrade, grade)
	targetGrade, grade = tonumber(targetGrade) or 0, tonumber(grade)
	if not grade or not Config.DoctorRanks[grade] then return false end
	if access.grade ~= nil and targetGrade < access.grade and grade < access.grade then return true end
	return access.admin and grade == HEAD_GRADE and targetGrade ~= HEAD_GRADE
end

--- May he dismiss this doctor?
local function mayFire(access, targetGrade)
	targetGrade = tonumber(targetGrade) or 0
	if access.grade ~= nil and targetGrade < access.grade then return true end
	return access.admin and targetGrade == HEAD_GRADE
end

local function atJobsDesk(src)
	local desk = Config.MDTDesk and Config.MDTDesk.coords
	if not desk then return true end
	local ped = GetPlayerPed(src)
	if not ped or ped == 0 then return false end
	return #(GetEntityCoords(ped) - vector3(desk.x, desk.y, desk.z)) <= JOBS_DESK_REACH
end

--- The server id of a character in the game, or nil
local function onlineByCharId(charId)
	for _, id in ipairs(GetPlayers()) do
		if tonumber(fwc('GetCharacterIdentifier', id)) == tonumber(charId) then return tonumber(id) end
	end
	return nil
end

--- The job set on a player in the game. w_lib's FwSetJob is silent on VORP (no change events),
--- so the change is announced here: the label rule above, the duty, the client and w_logs hear it.
local function setJobOnline(src, job, grade, label)
	if fwc('SetJob', src, job, grade) ~= true then return false end
	fwc('SetJobLabel', src, label)
	return true
end

local function jobsFail(reason) return { ok = false, error = reason } end

local function jobsGate(src)
	local access = jobsAccess(src)
	if not access then return nil, jobsFail('no_access') end
	if not atJobsDesk(src) then return nil, jobsFail('too_far') end
	return access
end

--- The ranks (high to low) and every doctor, in the game or not
w.callback.register('w_medic:jobs:list', function(src)
	local access, err = jobsGate(src)
	if not access then return err end

	local ranks = {}
	for grade in pairs(Config.DoctorRanks) do
		ranks[#ranks + 1] = { grade = grade, label = rankLabel(grade) or tostring(grade), give = mayGive(access, grade) }
	end
	table.sort(ranks, function(a, b) return a.grade > b.grade end)

	local doctors, seen = {}, {}
	local function add(charId, name, grade, online)
		charId = tonumber(charId)
		if not charId or seen[charId] then return end
		seen[charId] = true
		grade = tonumber(grade) or 0
		local mine = charId == access.charId
		local setTo = {}
		if not mine then
			for _, r in ipairs(ranks) do
				if r.grade ~= grade and maySet(access, grade, r.grade) then setTo[#setTo + 1] = r.grade end
			end
		end
		local fire = not mine and mayFire(access, grade)
		doctors[#doctors + 1] = {
			charId = charId, name = name, grade = grade, online = online,
			label = rankLabel(grade) or tostring(grade),
			ranks = setTo, fire = fire, touch = fire or #setTo > 0,
		}
	end
	for _, id in ipairs(GetPlayers()) do
		if fwc('GetJob', id) == 'doctor' then
			add(fwc('GetCharacterIdentifier', id), ('%s %s'):format(fwc('GetFirstName', id) or '', fwc('GetLastName', id) or ''), fwc('GetJobGrade', id), true)
		end
	end
	if fwc('Name') == 'vorp' then
		local rows = fwc('CharacterRows', 'job', 'doctor') or {}
		for _, r in ipairs(rows) do add(r.charidentifier, ('%s %s'):format(r.firstname or '', r.lastname or ''), r.jobgrade, false) end
	end
	table.sort(doctors, function(a, b)
		if a.grade ~= b.grade then return a.grade > b.grade end
		return a.name < b.name
	end)
	return { ok = true, admin = access.admin, grade = access.grade, ranks = ranks, doctors = doctors }
end)

--- A player in the game becomes a doctor of the chosen rank
-- A named citizen preview prevents a connection id from being mistaken for a citizen id.
local function hireTarget(src, input, grade)
    local access, err = jobsGate(src)
    if not access then return nil, err end
    grade = tonumber(grade)
    if not grade or grade % 1 ~= 0 or not mayGive(access, grade) then return nil, jobsFail('rank_too_high') end
    local who = w.citizen.requireOnline(input)
    if not who or not fwc('GetCharacterIdentifier', who.source) then return nil, jobsFail('no_player') end
    if who.source == tonumber(src) then return nil, jobsFail('self') end
    if fwc('GetJob', who.source) == 'doctor' then return nil, jobsFail('already_doctor') end
    return { source = who.source, citizenid = who.citizenid, name = w.citizen.label(who), grade = grade, label = rankLabel(grade) }
end
w.callback.register('w_medic:jobs:previewHire', function(src, input, grade)
    local target, err = hireTarget(src, input, grade)
    if not target then return err end
    return { ok = true, citizenid = target.citizenid, name = target.name, label = target.label }
end)
w.callback.register('w_medic:jobs:hire', function(src, input, grade, expectedCitizenId)
    if type(expectedCitizenId) ~= 'string' then return jobsFail('changed') end
    local target, err = hireTarget(src, input, grade)
    if not target then return err end
    if target.citizenid ~= expectedCitizenId then return jobsFail('changed') end
    if not setJobOnline(target.source, 'doctor', target.grade, target.label) then return jobsFail('failed') end
    w.notify(target.source, { description = 'jobs.you_hired', type = 'success', values = { target.label } })
    print(('[w_medic] jobs: %s hired %s as %s (%d)'):format(GetPlayerName(src), GetPlayerName(target.source), target.label, target.grade))
    return { ok = true }
end)

--- A doctor (in the game or not) and his current grade, or the reason he may not be touched
local function jobsTarget(access, charId)
	charId = tonumber(charId)
	if not charId then return nil, 'no_player' end
	if charId == access.charId then return nil, 'self' end
	local online = onlineByCharId(charId)
	local job, grade, identifier
	if online then
		job, grade = fwc('GetJob', online), tonumber(fwc('GetJobGrade', online)) or 0
	elseif fwc('Name') == 'vorp' then
		local rows = fwc('CharacterRows', 'citizenid', charId) or {}
		local row = rows[1]
		if not row then return nil, 'no_player' end
		job, grade, identifier = row.job, tonumber(row.jobgrade) or 0, row.identifier
	else
		return nil, 'no_player'
	end
	if job ~= 'doctor' then return nil, 'not_doctor' end
	return { charId = charId, online = online, grade = grade, identifier = identifier }
end

w.callback.register('w_medic:jobs:setRank', function(src, charId, grade)
	local access, err = jobsGate(src)
	if not access then return err end
	grade = tonumber(grade)
	local target, why = jobsTarget(access, charId)
	if not target then return jobsFail(why) end
	if not maySet(access, target.grade, grade) then
		return jobsFail((access.admin and not access.grade) and 'admin_head_only' or 'target_too_high')
	end
	local label = rankLabel(grade)
	if target.online then
		if not setJobOnline(target.online, 'doctor', grade, label) then return jobsFail('failed') end
		w.notify(target.online, { description = 'jobs.you_rank', type = 'inform', values = { label } })
	elseif not fwc('SetPlayerJobOffline', target.identifier, target.charId, 'doctor', grade, label) then
		return jobsFail('failed')
	end
	print(('[w_medic] jobs: %s set character %d to %s (%d)'):format(GetPlayerName(src), target.charId, label, grade))
	return { ok = true }
end)

w.callback.register('w_medic:jobs:fire', function(src, charId)
	local access, err = jobsGate(src)
	if not access then return err end
	local target, why = jobsTarget(access, charId)
	if not target then return jobsFail(why) end
	if not mayFire(access, target.grade) then
		return jobsFail((access.admin and not access.grade) and 'admin_head_only' or 'target_too_high')
	end
	if target.online then
		if not setJobOnline(target.online, 'unemployed', 0, 'Unemployed') then return jobsFail('failed') end
		w.notify(target.online, { description = 'jobs.you_fired', type = 'error' })
	elseif not fwc('RemoveJobOffline', target.charId) then
		return jobsFail('failed')
	end
	print(('[w_medic] jobs: %s dismissed character %d'):format(GetPlayerName(src), target.charId))
	return { ok = true }
end)

--- Who sees the jobs centre key on the desk (the client's LocalPlayer.state, read by w_store)
local function refreshJobsFlag(src)
	src = tonumber(src)
	if not src or not GetPlayerName(src) then return end
	local allowed = jobsAccess(src) ~= nil
	local state = Player(src).state
	if state['w_medic:jobsCenter'] ~= allowed then state:set('w_medic:jobsCenter', allowed, true) end
end

local function fixDoctorLabelSoon(src)
	SetTimeout(1000, function()
		fixDoctorLabel(src)
		refreshJobsFlag(src)
	end)
end

exports.w_lib:FwOnCharacterLoaded(function(src) fixDoctorLabelSoon(src) end)
exports.w_lib:FwOnJobUpdate(function(src) fixDoctorLabelSoon(src) end)
-- an admin rank given or taken (w_core's staff ranks) opens or closes the jobs centre for him
AddEventHandler('w_core:ranks:changed', function()
	SetTimeout(1500, function()
		for _, id in ipairs(GetPlayers()) do refreshJobsFlag(id) end
	end)
end)

-- the doctors (and admins) already in the game when this resource starts
CreateThread(function()
	Wait(5000)
	for _, id in ipairs(GetPlayers()) do
		fixDoctorLabel(id)
		refreshJobsFlag(id)
	end
end)

-- Exports for the admin console (w_admin backend)
--
-- Server-side wrappers over the paths the /revive and /aheal commands already use. The
-- client handlers decide what to do with the state: 'hospital:client:Revive' resurrects
-- only when the ped is dead or in last stand and always restores health / wounds, and
-- 'hospital:client:adminHeal' fills health. The caller checks the admin's permission.

--- Is the player dead or in last stand (from the core metadata this resource maintains)?
---@param playerId number
---@return boolean dead, boolean laststand
local function isDownState(playerId)
	local Player = WCore.Functions.GetPlayer(tonumber(playerId))
	if not Player then return false, false end
	local meta = Player.PlayerData.metadata or {}
	return meta.isdead == true, meta.inlaststand == true
end

--- Revive a connected player (same as the admin /revive <id> command).
---@param playerId number
---@return boolean ok, string result  'success' | 'player_offline'
local function RevivePlayer(playerId)
	local Player = WCore.Functions.GetPlayer(tonumber(playerId))
	if not Player then return false, 'player_offline' end
	reviveInGame(Player.PlayerData.source)
	return true, 'success'
end

--- Heal a connected player (same as the admin /aheal <id> command). A dead / last-stand
--- player is revived instead: filling health on a dead ped would leave them dead.
---@param playerId number
---@return boolean ok, string result  'success' | 'revived' | 'player_offline'
local function HealPlayer(playerId)
	local Player = WCore.Functions.GetPlayer(tonumber(playerId))
	if not Player then return false, 'player_offline' end
	local dead, laststand = isDownState(playerId)
	if dead or laststand then
		reviveInGame(Player.PlayerData.source)
		return true, 'revived'
	end
	TriggerClientEvent('hospital:client:adminHeal', Player.PlayerData.source)
	TriggerClientEvent('hospital:client:HealInjuries', Player.PlayerData.source, 'full')
	refillNeeds(Player.PlayerData.source)
	return true, 'success'
end

exports('RevivePlayer', RevivePlayer)
exports('HealPlayer', HealPlayer)
--- Is this player still in his bed? A stay ends when his client leaves the bed (LeaveBed), but a player
--- revived by an admin, teleported or flying out never sends it: a bed far behind him is released here, or
--- the stay never ended -- IsDead stayed true, so heists said "not in this state" and w_creators refused a
--- character switch until he logged out (2026-10-23).
local BED_LEFT = 40.0 -- beyond the check-in desk's reach (BED_REACH 25 m): only someone who really left
local function inBed(src)
	src = tonumber(src)
	local id = src and bedBySrc[src]
	if not id then return false end
	local ped = GetPlayerPed(src)
	if ped and ped ~= 0 and Config.Locations["beds"][id] then
		local c = Config.Locations["beds"][id].coords
		if #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > BED_LEFT then
			releaseBed(src)
			return false
		end
	end
	return true
end

-- dead, in last stand, or in a hospital bed (w_creators refuses a character switch meanwhile)
exports('IsDead', function(playerId)
	local dead, laststand = isDownState(playerId)
	return dead or laststand or inBed(playerId)
end)

exports('InHospitalBed', function(playerId)
	return inBed(playerId)
end)
