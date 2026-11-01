Laststand = Laststand or {}
Laststand.ReviveInterval = Config.TimeTillRespawn
Laststand.MinimumRevive = Config.MinimumRevive
InLaststand = false
LaststandTime = 0
isEscorted = false
local isEscorting = false
local transition = 0

-- Functions
function SetLaststand(bool, spawn)
    transition = transition + 1
    local request = transition
    local ped = PlayerPedId()
    if bool then
        -- ★ 2026-10-14: never over a player already dead (he logged in dead, or bled out), and the
        --   countdown starts full. LaststandTime used to be left at 0, so the countdown ran negative
        --   for ever (and wrote itself into Config.DeathTime), the "call a doctor" key never came,
        --   and a bystander's kit was always refused.
        if isReviving or isDead then return end
        Wait(1000)
        if request ~= transition or isReviving or isDead then return end
        ped = PlayerPedId()
        if ped == 0 or not DoesEntityExist(ped) then return end
        -- RedM has no wounded-but-alive pose: the ped lies dead for the whole last stand. Only the
        -- death watcher starts one, on a dead ped; alive again a second later means a revive got
        -- there first (maj_revive's point, an admin, VORP) - there is no last stand to start.
        -- (★ 2026-10-14: it used to kill him here: a man revived in that second went straight back
        --  down, with every control off.)
        if not IsEntityDead(ped) then return end
        InLaststand = true
        LaststandTime = Laststand.ReviveInterval
        emsNotified = false
        -- the doctor's client translates the key in his own language
        TriggerServerEvent('hospital:server:ambulanceAlert', 'info.civ_down')
        CreateThread(function()
            while InLaststand and request == transition do
                -- a revive in progress holds the bleeding
                if not isReviving then
                    LaststandTime = LaststandTime - 1
                    if LaststandTime <= 0 then
                        WCore.Functions.Notify(locale('error.bled_out'), 'error')
                        SetLaststand(false)
                        LogDeath(PlayerId(), PlayerPedId())
                        deathTime = 0
                        OnDeath()
                        DeathTimer()
                        return
                    end
                end
                Wait(1000)
            end
        end)
    else
        InLaststand = false
        LaststandTime = 0
    end
    TriggerServerEvent("hospital:server:SetLaststandStatus", bool)
end

-- Events
RegisterNetEvent('hospital:client:SetEscortingState', function(bool)
    isEscorting = bool
end)

RegisterNetEvent('hospital:client:isEscorted', function(bool)
    isEscorted = bool
end)

RegisterNetEvent('hospital:client:UseFirstAid', function()
    if not isEscorting then
        local player = w.getClosestPlayer(GetEntityCoords(PlayerPedId()), 1.5)
        if player then
            local playerId = GetPlayerServerId(player)
            TriggerServerEvent('hospital:server:UseFirstAid', playerId)
        else
            WCore.Functions.Notify(locale('error.no_player'), 'error')
        end
    else
        WCore.Functions.Notify(locale('error.first_aid_escorting'), 'error')
    end
end)

-- 1.0.7: the helper is told why first aid does not apply ('dead' = he needs reviving, 'not_down' = not hurt)
RegisterNetEvent('hospital:client:CanHelp', function(helperId)
    if InLaststand then
        if LaststandTime <= 300 then
            TriggerServerEvent('hospital:server:CanHelp', helperId, true)
        else
            TriggerServerEvent('hospital:server:CanHelp', helperId, false)
        end
    else
        TriggerServerEvent('hospital:server:CanHelp', helperId, false, isDead and 'dead' or 'not_down')
    end
end)

RegisterNetEvent('hospital:client:HelpPerson', function(targetId)
    local ped = PlayerPedId()
    if w.progressBar({
        duration = math.random(30000, 60000),
        position = 'bottom',
        label = locale('progress.revive'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            combat = true,
            mouse = false,
        },
        anim = {
            dict = healAnimDict,
            clip = healAnim,
        },
    })
    then
        ClearPedTasks(ped)
        WCore.Functions.Notify(locale('success.revived'), 'success')
        TriggerServerEvent("hospital:server:RevivePlayer", targetId)
    else
        ClearPedTasks(ped)
        w.notify({ type = 'error', description = locale('error.canceled'), duration = 2500 })
    end
end)
