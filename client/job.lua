isHealingPerson = false
healAnimDict = "mini_games@story@mob4@heal_jules@bandage@arthur"
healAnim = "bandage_fast"

local statusCheckPed = nil
local PlayerJob = {}
local onDuty = false
local currentYard = 1
local stationPrompts = {}   -- { rec = w.prompt.at record, relabel = fun() } per location
local patientRec = nil      -- w.prompt.atEntity record following the closest player
local patientId = nil       -- player index the patient record was built for

-- Functions
-- Spawns the chosen wagon at the yard and seats the doctor on the driver's bench
function TakeOutVehicle(vehicleInfo)
    local coords = Config.Locations["vehicle"][currentYard]
    WCore.Functions.SpawnVehicle(vehicleInfo, function(veh)
        SetEntityHeading(veh, coords.w)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end, coords, true)
end

function MenuWagons()
    local vehicleMenu = {}

    -- the wagons of his grade, or of the closest grade below that has a list (grades 5-6 have none)
    local job = WCore.Functions.GetPlayerData().job or {}
    local grade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0
    local authorizedVehicles = {}
    for g = grade, 0, -1 do
        if Config.AuthorizedVehicles[g] then authorizedVehicles = Config.AuthorizedVehicles[g] break end
    end
    for veh, label in pairs(authorizedVehicles) do
        vehicleMenu[#vehicleMenu+1] = {
            title = locale(label),
            event = "ambulance:client:TakeOutVehicle",
            args = { vehicle = veh }
        }
    end

    w.registerContext({
        id = 'doctor_vehicles',
        title = locale('menu.amb_vehicles'),
        options = vehicleMenu
    })
    w.showContext('doctor_vehicles')
end

-- ── station prompts (library proximity prompts) ─────────────────────────────────────
local function isDoctor()
    return PlayerJob.name == 'doctor'
end

-- A prompt is pointless while the player is dead, bleeding out or lying in a bed: the death
-- and bed prompt groups own the screen then.
local function isUpright()
    return not isDead and not InLaststand and not isInHospitalBed
end

local function doctorUpright()
    return isDoctor() and isUpright()
end

-- Station actions (the job check is the prompt's canInteract: a civilian never sees them)
local function openArmory(city)
    -- The cabinet has three shapes, and which one is running is the server's answer, not ours
    -- (server/main.lua setupPharmacy and the takeSupplies callback):
    --   w_store running -> the pharmacy IS a shop shelf, so this asks w_store to open its page
    --   w_inventory     -> the bag's own registered shop
    --   anything else   -> the server hands the supplies over by hand
    -- (w.callback.await's second argument is its delay: the city goes after it)
    local res = w.callback.await('w_medic:takeSupplies', false, city)

    -- The server already opened the page in the w_store case (it answered its own callback with
    -- the payload and the client opened it there). Nothing to do on this side.
    if type(res) ~= 'table' then
        return w.notify({ description = 'error.pharmacy_down', type = 'error' })
    end
    if res.ok ~= true then
        -- the reason is a key of this resource's own dictionary, so it reads in his language
        return w.notify({ description = 'error.' .. tostring(res.error or 'pharmacy_down'), type = 'error' })
    end
end

local function toggleDuty()
    onDuty = not onDuty
    exports.w_lib:FwToggleDuty()
end

-- In a wagon the key stores it, on foot it opens the wagon menu of this yard
local function wagonYard(k)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        WCore.Functions.DeleteVehicle(GetVehiclePedIsIn(ped))
    else
        currentYard = k
        MenuWagons()
    end
end

-- ! 2026-10-14: was the QBCore event 'inventory:server:OpenInventory', which no VORP script answers -
--   the locker never opened. The server opens it through w_lib's bag bridge (InvOpenStash).
local function openStash()
    TriggerServerEvent('w_medic:server:openStash')
end

---One location: a library proximity prompt on Config.PromptKey with a dictionary title and label.
---@param coords vector3
---@param titleKey string dictionary key of the group title
---@param label fun(): string the prompt label, built from the dictionary
---@param onComplete fun()
---@param canInteract? fun(): boolean
local function addStationPrompt(coords, titleKey, label, onComplete, canInteract)
    local rec = w.prompt.at({
        coords = coords,
        distance = Config.PromptDistance,
        title = locale(titleKey),
        prompts = {
            { key = Config.PromptKey, label = label(), hold = false, onComplete = onComplete },
        },
        canInteract = canInteract or isUpright,
    })
    stationPrompts[#stationPrompts + 1] = {
        rec = rec,
        relabel = function()
            rec.setTitle(locale(titleKey))
            rec.setLabel(Config.PromptKey, label())
        end,
    }
end

-- ── cosmetic surgery (performed by w_creators) ─────────────────────────────────────────
-- The prompt only asks this resource's server; the server opens the clinic through the
-- w_creators server export, which re-validates everything and charges the player.
-- w_creators publishes the clinics that can be opened now (its surgery service on, the clinic
-- enabled and inside its opening hours) as GlobalState[CLINICS_KEY] = { [clinicId] = true }.
-- A clinic missing from it has no prompt; while nothing is published (an older w_creators) the
-- prompt shows and the server's answer decides.
local CLINICS_KEY = 'w_creators:clinics'
-- Where the clinics are: w_creators publishes the clinics its board (/servicesadmin) places as
-- GlobalState[CLINIC_POINTS_KEY] = { [clinicId] = { x, y, z } }. While nothing is published (an older
-- w_creators) Config.CosmeticSurgery.clinics is the list. A change rebuilds the surgery prompts.
local CLINIC_POINTS_KEY = 'w_creators:clinicPoints'

local function clinicOpen(clinicId)
    local ok, published = pcall(function() return GlobalState[CLINICS_KEY] end)
    if not ok or type(published) ~= 'table' then return true end
    return published[clinicId] == true
end

local function surgeryAvailable(clinicId)
    return isUpright() and GetResourceState('w_creators') == 'started' and clinicOpen(clinicId)
end

--- The clinics: the published points (`points`, or GlobalState's), else the config list.
local function surgeryClinics(cfg, points)
    if points == nil then
        local ok, published = pcall(function() return GlobalState[CLINIC_POINTS_KEY] end)
        points = ok and published or nil
    end
    if type(points) ~= 'table' then return type(cfg.clinics) == 'table' and cfg.clinics or {} end
    local list = {}
    for clinicId, c in pairs(points) do
        if type(clinicId) == 'string' and type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
            list[#list + 1] = { clinicId = clinicId, coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) }
        end
    end
    table.sort(list, function(a, b) return a.clinicId < b.clinicId end)
    return list
end

local function addSurgeryPrompts(points)
    local cfg = Config.CosmeticSurgery
    if type(cfg) ~= 'table' or not cfg.enabled then return end
    local key = cfg.key or Config.PromptKey
    for _, clinic in ipairs(surgeryClinics(cfg, points)) do
        local clinicId, c = clinic.clinicId, clinic.coords
        if type(clinicId) == 'string' and c then
            local rec = w.prompt.at({
                coords = vector3(c.x, c.y, c.z),
                distance = Config.PromptDistance,
                title = locale('text.surgery'),
                prompts = {
                    { key = key, label = locale('prompt.cosmetic_surgery'), hold = false,
                        onComplete = function()
                            TriggerServerEvent('hospital:server:requestCosmeticSurgery', clinicId)
                        end },
                },
                canInteract = function() return surgeryAvailable(clinicId) end,
            })
            stationPrompts[#stationPrompts + 1] = {
                rec = rec,
                surgery = true,
                relabel = function()
                    rec.setTitle(locale('text.surgery'))
                    rec.setLabel(key, locale('prompt.cosmetic_surgery'))
                end,
            }
        end
    end
end

local function removeSurgeryPrompts()
    local kept = {}
    for _, entry in ipairs(stationPrompts) do
        if entry.surgery then entry.rec.remove() else kept[#kept + 1] = entry end
    end
    stationPrompts = kept
end

-- The staff moved, added or removed a clinic on w_creators' board: the surgery prompts follow. Before
-- the station prompts are built nothing is done (createAmbuPrompts reads the list then).
AddStateBagChangeHandler(CLINIC_POINTS_KEY, 'global', function(_, _, value)
    if #stationPrompts == 0 then return end
    removeSurgeryPrompts()
    addSurgeryPrompts(type(value) == 'table' and value or false)
end)

function createAmbuPrompts()
    if #stationPrompts > 0 then return end
    -- ★ 2026-10-14: with the w_store pharmacy (Config.Pharmacy.useStore) its clerk - gw-medic's desk
    --   doctor - is the door, with w_store's own prompt on him; a second prompt of ours on the same
    --   spot only fought his over the screen. The armory prompt stays for the other two shapes.
    local armoryPrompts = not (Config.Pharmacy and Config.Pharmacy.enabled and Config.Pharmacy.useStore and GetResourceState('w_store') == 'started')
    for _, v in pairs(armoryPrompts and Config.Locations['armory'] or {}) do
        local city = v.city
        local c = v.coords or v   -- v.coords is the named form; v alone keeps the old table working
        addStationPrompt(vector3(c.x, c.y, c.z), 'text.armory',
            function() return locale('prompt.open_armory') end,
            function() openArmory(city) end, doctorUpright)
    end
    for _, v in pairs(Config.Locations['duty']) do
        addStationPrompt(vector3(v.x, v.y, v.z), 'text.duty',
            function() return locale('prompt.toggle_duty') end, toggleDuty, doctorUpright)
    end
    for k, v in pairs(Config.Locations['vehicle']) do
        addStationPrompt(vector3(v.x, v.y, v.z), 'text.wagons',
            function() return locale('prompt.wagons') end, function() wagonYard(k) end, doctorUpright)
    end
    for _, v in pairs(Config.Locations['stash']) do
        addStationPrompt(vector3(v.x, v.y, v.z), 'text.pstash',
            function() return locale('prompt.open_stash') end, openStash, doctorUpright)
    end
    for _, v in pairs(Config.Locations['checking']) do
        addStationPrompt(vector3(v.x, v.y, v.z), 'text.check_in',
            function() return locale('prompt.check_in') end, function() CheckIn() end)
    end
    for _, v in pairs(Config.Locations['beds']) do
        addStationPrompt(vector3(v.coords.x, v.coords.y, v.coords.z), 'text.bed',
            function() return locale('prompt.lie_bed', Config.BillCost) end, function() LieInBed() end)
    end
    addSurgeryPrompts()
end

local function removeAmbuPrompts()
    for i = 1, #stationPrompts do
        stationPrompts[i].rec.remove()
    end
    stationPrompts = {}
end

-- ── doctor next to a player (library prompt following the closest player) ────────────
local function dropPatientPrompt()
    if patientRec then patientRec.remove() end
    patientRec, patientId = nil, nil
end

-- forward declarations: the actions live with their events below
local CheckStatus, TreatWounds, RevivePlayer

local function attachPatientPrompt(playerId, ped)
    dropPatientPrompt()
    patientId = playerId
    patientRec = w.prompt.atEntity(ped, {
        distance = Config.PatientDistance,
        title = locale('text.patient'),
        prompts = {
            { key = Config.PatientKeys.status, label = locale('prompt.check_status'), hold = false,
                onComplete = function() CheckStatus(playerId, ped) end },
            { key = Config.PatientKeys.treat, label = locale('prompt.treat_wounds'), hold = 1000,
                onComplete = function() TreatWounds(playerId) end },
            { key = Config.PatientKeys.revive, label = locale('prompt.revive'), hold = 1500,
                onComplete = function() RevivePlayer(playerId) end },
        },
        canInteract = function() return doctorUpright() and not isHealingPerson end,
    })
end

local function relabelPatientPrompt()
    if not patientRec then return end
    patientRec.setTitle(locale('text.patient'))
    patientRec.setLabel(Config.PatientKeys.status, locale('prompt.check_status'))
    patientRec.setLabel(Config.PatientKeys.treat, locale('prompt.treat_wounds'))
    patientRec.setLabel(Config.PatientKeys.revive, locale('prompt.revive'))
end

-- Keeps the patient prompt on the closest player while the local player is a doctor; the
-- search radius is a little wider than the prompt distance so the record exists before the
-- doctor steps into range (the library measures the distance itself).
CreateThread(function()
    while true do
        local sleep = 1000
        if isDoctor() then
            sleep = 500
            local id, ped = w.getClosestPlayer(GetEntityCoords(PlayerPedId()), Config.PatientDistance + 1.0)
            if id ~= patientId or (patientRec and patientRec.entity ~= ped) then
                if id then attachPatientPrompt(id, ped) else dropPatientPrompt() end
            end
        elseif patientRec then
            dropPatientPrompt()
        end
        Wait(sleep)
    end
end)

-- Live language switch: reload the dictionary, then relabel what was built from it
AddEventHandler('w_lib:setLocale', function(key)
    w.locale(key)
    RebuildStationBlips()
    for i = 1, #stationPrompts do stationPrompts[i].relabel() end
    relabelPatientPrompt()
    RelabelBedPrompt()
    RelabelDeathPrompt()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removeAmbuPrompts()
    dropPatientPrompt()
end)

-- Events
RegisterNetEvent('ambulance:client:TakeOutVehicle', function(data)
    local vehicle = data.vehicle
    TakeOutVehicle(vehicle)
end)

exports.w_lib:FwOnJobUpdate(function(JobInfo)
    PlayerJob = JobInfo or {}
    TriggerServerEvent("hospital:server:SetDoctor")
end)

exports.w_lib:FwOnCharacterLoaded(function()
    exports.spawnmanager:setAutoSpawn(false)
    local ped = PlayerPedId()
    local player = PlayerId()
    TriggerServerEvent("hospital:server:SetDoctor")
    CreateThread(function()
        Wait(5000)
        -- Character loading may replace the ped while this thread waits.
        ped = PlayerPedId()
        if ped == 0 or not DoesEntityExist(ped) then return end
        if Config.MaxHp and Config.MaxHp > 0 then
            SetEntityMaxHealth(ped, Config.MaxHp)
            if not isDead and not InLaststand and not IsEntityDead(ped) then w.player.heal() end
        end
        SetPlayerHealthRechargeMultiplier(player, Config.RegenRate)
    end)

    CreateThread(function()
        Wait(1000)
        WCore.Functions.GetPlayerData(function(PlayerData)
            PlayerJob = PlayerData.job or {}
            onDuty = PlayerJob.onduty == true
            local meta = PlayerData.metadata or {}
            if meta.isdead or meta.inlaststand then
                -- He logged out down, and comes back down. The framework may lay the ped down itself
                -- (VORP's CombatLogDeath, some 15 s after the spawn); otherwise it is done here. The
                -- death watcher (dead.lua) then starts the last stand from the dead ped, the one way
                -- down whatever the cause. (It used to set the dead state over a living ped: the
                -- controls went off for good on a player standing up.)
                CreateThread(function()
                    local deadline = GetGameTimer() + 20000
                    while GetGameTimer() < deadline and not IsEntityDead(PlayerPedId()) do Wait(500) end
                    local now = WCore.Functions.GetPlayerData().metadata or {}
                    if not IsEntityDead(PlayerPedId()) and (now.isdead or now.inlaststand)
                        and not isDead and not InLaststand then
                        SetEntityHealth(PlayerPedId(), 0, 0)
                    end
                end)
            else
                TriggerServerEvent("hospital:server:SetDeathStatus", false)
                TriggerServerEvent("hospital:server:SetLaststandStatus", false)
            end
            createAmbuPrompts()
        end)
    end)
end)

-- Resource restart with the player already in game: the loaded event will not fire again
CreateThread(function()
    Wait(1000)
    local PlayerData = WCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.citizenid then return end
    PlayerJob = PlayerData.job or {}
    onDuty = PlayerJob.onduty or false
    createAmbuPrompts()
end)

exports.w_lib:FwOnDutyChange(function(duty)
    onDuty = duty == true
    TriggerServerEvent("hospital:server:SetDoctor")
end)

-- The three doctor actions take the patient (player index + ped). The patient prompt passes
-- the player it follows; the /status, /treat and /revivep commands pass the closest player.
local function closestPatient()
    local player, playerPed = w.getClosestPlayer(GetEntityCoords(PlayerPedId()), 5.0)
    if not player then
        WCore.Functions.Notify(locale('error.no_player'), 'error')
    end
    return player, playerPed
end

CheckStatus = function(player, playerPed)
    local playerId = GetPlayerServerId(player)
    statusCheckPed = playerPed
    WCore.Functions.TriggerCallback('hospital:GetPlayerStatus', function(result)
        if not result then return end
        local found = false
        -- limb labels and wound states are dictionary keys: translated here, in the doctor's language
        for k, v in pairs(result) do
            if k ~= "BLEED" and k ~= "WEAPONWOUNDS" then
                found = true
                statusChecks[#statusChecks+1] = {
                    bone = Config.BoneIndexes[k],
                    label = ('%s (%s)'):format(locale(v.label), locale(Config.WoundStates[v.severity] or ''))
                }
            end
        end
        -- weapon wounds and bleeding are reported as notifications (no chat resource on this server)
        for _, weapon in pairs(result["WEAPONWOUNDS"] or {}) do
            found = true
            WCore.Functions.Notify({ text = locale('info.status'), caption = locale(WeaponDamageList[weapon] or 'damage.placeholder') }, 'error')
        end
        if result["BLEED"] and result["BLEED"] > 0 then
            found = true
            WCore.Functions.Notify({ text = locale('info.status'), caption = locale('info.is_status', locale(Config.BleedingStates[result["BLEED"]].label)) }, 'error')
        end
        if not found then
            WCore.Functions.Notify(locale('success.healthy_player'), 'success')
        end
        isStatusChecking = true
        statusCheckTime = Config.CheckTime
    end, playerId)
end

-- Bandage / first aid on a player: the progress bar runs while the heal thread below plays
-- the bandage animation (isHealingPerson), then the server consumes the item.
local function treatPatient(player, progressKey, serverEvent)
    if isHealingPerson then return end
    local playerId = GetPlayerServerId(player)
    isHealingPerson = true
    FreezeEntityPosition(PlayerPedId(), true)
    WCore.Functions.Progressbar('reviving', locale(progressKey), 5000, false, true, {
        disableMovement = true,
        disableVehicleMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        ClearPedTasks(PlayerPedId())
        TriggerServerEvent(serverEvent, playerId)
        FreezeEntityPosition(PlayerPedId(), false)
        isHealingPerson = false
    end, function()
        -- cancelled (or interrupted): the doctor is let go, and nothing is used
        ClearPedTasks(PlayerPedId())
        FreezeEntityPosition(PlayerPedId(), false)
        isHealingPerson = false
    end)
end

RevivePlayer = function(player)
    if not WCore.Functions.HasItem(Config.ItemNames.revive, 1) then
        WCore.Functions.Notify(locale('error.no_firstaid'), 'error')
        return
    end
    treatPatient(player, 'progress.revive', 'hospital:server:RevivePlayer')
end

TreatWounds = function(player)
    if not WCore.Functions.HasItem(Config.ItemNames.bandage, 1) then
        WCore.Functions.Notify(locale('error.no_bandage'), 'error')
        return
    end
    treatPatient(player, 'progress.healing', 'hospital:server:TreatWounds')
end

-- the /status, /treat and /revivep commands (server side job check) act on the closest player
RegisterNetEvent('hospital:client:CheckStatus', function()
    local player, playerPed = closestPatient()
    if player then CheckStatus(player, playerPed) end
end)

RegisterNetEvent('hospital:client:RevivePlayer', function()
    local player = closestPatient()
    if player then RevivePlayer(player) end
end)

RegisterNetEvent('hospital:client:TreatWounds', function()
    local player = closestPatient()
    if player then TreatWounds(player) end
end)

-- Threads: the status labels over the patient's limbs (informational floating text, not a
-- key hint) and the bandage animation while a treatment runs; the thread idles otherwise
CreateThread(function()
    while true do
        Wait((isStatusChecking or isHealingPerson) and 10 or 250)
        if isStatusChecking then
            for k, v in pairs(statusChecks) do
                local x, y, z = table.unpack(GetPedBoneCoords(statusCheckPed, v.bone))
                w.drawText3D(x, y, z, v.label, 'ambu-status-' .. k)
            end
        end
        if isHealingPerson then
            local ped = PlayerPedId()
            if not IsEntityPlayingAnim(ped, healAnimDict, healAnim, 1) then
                w.requestAnimDict(healAnimDict)
                TaskPlayAnim(ped, healAnimDict, healAnim, 3.0, 3.0, -1, 49, 0, 0, 0, 0)
            end
        end
    end
end)
