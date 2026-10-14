deathTime = 0
emsNotified = false
local respawnRequested = false

-- Functions
function OnDeath()
    if not isDead then
        isDead = true
        respawnRequested = false
        TriggerServerEvent("hospital:server:SetDeathStatus", true)
        local player = PlayerPedId()

        while GetEntitySpeed(player) > 0.5 or IsPedRagdoll(player) do
            Wait(10)
        end
    end
end

-- Counts the respawn timer down while dead; the respawn key is the prompt group below
function DeathTimer()
    while isDead do
        Wait(1000)
        deathTime = deathTime - 1
    end
end

local function logDeath(player, playerPed)
    local killer_2, killerWeapon = NetworkGetEntityKillerOfPlayer(player)
    local killer = GetPedSourceOfDeath(playerPed)

    if killer_2 ~= 0 and killer_2 ~= -1 then
        killer = killer_2
    end

    local killerId = NetworkGetPlayerIndexFromPed(killer)
    local killerName = killerId ~= -1 and GetPlayerName(killerId) .. " " .. "("..GetPlayerServerId(killerId)..")" or locale('info.self_death')
    local weaponLabel = locale('info.wep_unknown')
    local weaponName = locale('info.wep_unknown')
    local weaponItem = WCore.Shared.GetWeapon(killerWeapon)
    if weaponItem then
        weaponLabel = weaponItem.label
        weaponName = weaponItem.name
    end
    TriggerServerEvent("w_log:server:CreateLog", "death",
        locale('logs.death_log_title', GetPlayerName(-1), GetPlayerServerId(player)), "red",
        locale('logs.death_log_message', killerName, GetPlayerName(player), weaponLabel, weaponName))
end
LogDeath = logDeath

-- ── death / last stand screen prompt ─────────────────────────────────────────────────
-- One library prompt group carries the countdown as its title and the two keys: E respawns
-- at the hospital once the timer ran out, G calls a doctor while help is still possible.
-- The library reads the raw keys itself, so the group works while the game controls are off.
local deathGroup = nil
local deathState = nil      -- last title / row state pushed to the group

local function ensureDeathGroup()
    if deathGroup then return end
    deathGroup = w.prompt.createGroup(false, 'bottom-right')
    deathGroup.addPrompt('E', locale('prompt.respawn', Config.BillCost), false)
    deathGroup.addPrompt('G', locale('prompt.request_help'), false)
    deathGroup.display()
end

local function deleteDeathGroup()
    if not deathGroup then return end
    deathGroup.hide()
    deathGroup.delete()
    deathGroup = nil
    deathState = nil
end

-- Pushes the title and the rows only when something changed (called every 250 ms)
local function updateDeathGroup()
    local dead = isDead and not isInHospitalBed
    local lastStand = InLaststand and not isDead
    if not dead and not lastStand then
        deleteDeathGroup()
        return
    end
    ensureDeathGroup()

    -- ★ 2026-10-14 (owner: "like GW"): both keys from the first second. G calls a doctor at once,
    --   and again is refused only once he has been called; E (wake up at the doctor) shows its
    --   countdown from the start and opens when the bleeding out is over. It used to show nothing
    --   for the first two minutes (G waited for MinimumRevive, E for the end of the last stand).
    local state
    if dead then
        local seconds = math.max(math.ceil(deathTime), 0)
        -- a resurrect in progress (a doctor's revive) keeps the key off until it has finished
        state = ('dead:%d:%s:%s'):format(seconds, tostring(emsNotified), tostring(isReviving == true))
        if state ~= deathState then
            deathGroup.setTitle(seconds > 0 and locale('info.respawn_txt', seconds) or locale('info.respawn_ready'))
            deathGroup.setVisible('E', true)
            deathGroup.setEnabled('E', seconds <= 0 and not respawnRequested and not isReviving)
            -- a doctor can still revive a dead man (the server takes dead or bleeding out)
            deathGroup.setVisible('G', true)
            deathGroup.setEnabled('G', not emsNotified and not isReviving)
            deathGroup.setLabel('G', emsNotified and locale('info.help_requested') or locale('prompt.request_help'))
        end
    else
        local seconds = math.max(math.ceil(LaststandTime), 0)
        local canAsk = LaststandTime <= Laststand.MinimumRevive
        state = ('laststand:%d:%s:%s:%s'):format(seconds, tostring(canAsk), tostring(emsNotified), tostring(isReviving == true))
        if state ~= deathState then
            deathGroup.setTitle(canAsk and locale('info.bleed_out_help', seconds) or locale('info.bleed_out', seconds))
            -- the respawn opens once the bleeding out is over: shown, locked, with the countdown above
            deathGroup.setVisible('E', true)
            deathGroup.setEnabled('E', false)
            deathGroup.setVisible('G', true)
            deathGroup.setEnabled('G', canAsk and not emsNotified and not isReviving)
            deathGroup.setLabel('G', emsNotified and locale('info.help_requested') or locale('prompt.request_help'))
        end
    end
    deathState = state

    -- another group may have taken the screen for a moment: this one owns it while dead
    if not deathGroup.isVisible() then deathGroup.display() end
end

-- A language switch: the fixed label is replaced, the rest is re-pushed by the next update
function RelabelDeathPrompt()
    if not deathGroup then return end
    deathGroup.setLabel('E', locale('prompt.respawn', Config.BillCost))
    deathState = nil
end

AddEventHandler('w_lib:promptCompleted', function(id, key)
    if not deathGroup or id ~= deathGroup.id then return end
    if isReviving then return end -- being resurrected: the downed state ends with it
    if key == 'E' then
        if respawnRequested or not isDead or deathTime > 0 or isInHospitalBed then return end
        respawnRequested = true
        deathState = nil
        TriggerEvent('hospital:client:RespawnAtHospital')
    elseif key == 'G' then
        if emsNotified or not (InLaststand or isDead) then return end
        if InLaststand and LaststandTime > Laststand.MinimumRevive then return end
        -- the doctor's client translates the key in his own language
        TriggerServerEvent('hospital:server:ambulanceAlert', 'info.civ_down')
        emsNotified = true
    end
end)

-- The server refused the respawn (it does not know him down yet): the key opens again
RegisterNetEvent('hospital:client:RespawnRefused', function()
    respawnRequested = false
    deathState = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deleteDeathGroup()
end)

-- Threads

CreateThread(function()
    while true do
        updateDeathGroup()
        Wait(deathGroup and 250 or 1000)
    end
end)

--- Back up by something other than this resource (VORP's /revive, a txAdmin heal, an admin
--- menu): the downed state is dropped, or the controls stay off over a living player.
function ClearDownState()
    isDead = false
    deathTime = 0
    emsNotified = false
    respawnRequested = false
    SetEntityInvincible(PlayerPedId(), false)
    if InLaststand then SetLaststand(false) end
    TriggerServerEvent("hospital:server:SetDeathStatus", false)
    TriggerServerEvent("hospital:server:SetLaststandStatus", false)
end

-- The death watcher. A fresh death (a dead ped, neither downed state yet) starts the last stand;
-- bleeding out is the last stand's own countdown (laststand.lua), which ends in OnDeath.
-- ★ 2026-10-14: in RedM the ped stays dead for the whole last stand, so "dead while in last stand"
--   is the last stand itself. The old second branch here took it for a second death: every last
--   stand became death one second in (no "call a doctor", no bystander's kit), and the dead player
--   then re-entered last stand on the next tick - a doctor alert every two seconds.
CreateThread(function()
    local upSince = nil
	while true do
		Wait(250)
		local player = PlayerId()
		if NetworkIsPlayerActive(player) and not isReviving then
            local playerPed = PlayerPedId()
            local pedDead = IsEntityDead(playerPed)
            if pedDead and not InLaststand and not isDead then
                upSince = nil
                SetLaststand(true)
            elseif (isDead or InLaststand) and not pedDead and not isInHospitalBed then
                -- alive again although nothing here revived him: three seconds of it are no glitch
                upSince = upSince or GetGameTimer()
                if GetGameTimer() - upSince > 3000 then
                    upSince = nil
                    ClearDownState()
                end
            else
                upSince = nil
            end
		end
	end
end)

-- Game controls stay off while dead / in last stand (the prompt keys are raw keys, unaffected)
CreateThread(function()
	while true do
        local sleep = 1000
		if isDead or InLaststand then
            sleep = 5
            DisableAllControlActions(0)
			EnableControlAction(0, 0x9720FCEE, true)   -- T (chat)

            if isDead then
                SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
            end
		end
        Wait(sleep)
	end
end)
