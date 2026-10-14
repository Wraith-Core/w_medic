local prevPos = nil
onPainKillers = false
local painkillerAmount = 0
local IfaksDict = "mini_games@story@mob4@heal_jules@bandage@arthur"
local IfaksAnim = "bandage_start"
local BandageDict = "mini_games@story@mob4@heal_jules@bandage@arthur"
local BandageAnim = "bandage_fast"
local PainkillersDict = "mini_games@story@mob4@heal_jules@bandage@arthur"
local PainkillersAnim = "bandage_start"

-- Functions
local function DoBleedAlert()
    if not isDead and tonumber(isBleeding) > 0 then
        WCore.Functions.Notify(locale('info.bleed_alert', locale(Config.BleedingStates[tonumber(isBleeding)].label)), 'error')
    end
end

local function RemoveBleed(level)
    if isBleeding ~= 0 then
        if isBleeding - level < 0 then
            isBleeding = 0
        else
            isBleeding = isBleeding - level
        end
        DoBleedAlert()
    end
end

local function ApplyBleed(level)
    if Config.Injuries == false then return end -- no bleeding on this server
    if isBleeding ~= 4 then
        if isBleeding + level > 4 then
            isBleeding = 4
        else
            isBleeding = isBleeding + level
        end
        DoBleedAlert()
    end
end

-- Events

RegisterNetEvent('hospital:client:UseIfaks', function(itemName)
    local ped = PlayerPedId()
    WCore.Functions.Progressbar("use_bandage", locale('progress.ifaks'), 3000, false, true, {
        disableMovement = false,
		disableMouse = false,
		disableCombat = true,
    }, {
		animDict = IfaksDict,
		anim = IfaksAnim,
		flags = 1,
    }, {}, {}, function() -- Done
        StopAnimTask(ped, IfaksDict, IfaksAnim, 1.0)
        SetEntityHealth(ped, GetEntityHealth(ped) + 10)
        onPainKillers = true
        if painkillerAmount < 3 then
            painkillerAmount = painkillerAmount + 1
        end
        if math.random(1, 100) < 50 then
            RemoveBleed(1)
        end
    end, function() -- Cancel
        StopAnimTask(ped, IfaksDict, IfaksAnim, 1.0)
        WCore.Functions.Notify(locale('error.canceled'), 'error')
    end)
end)

RegisterNetEvent('hospital:client:UseBandage', function(itemName)
    local ped = PlayerPedId()
    WCore.Functions.Progressbar("use_bandage", locale('progress.bandage'), 4000, false, true, {
        disableMovement = false,
		disableMouse = false,
		disableCombat = true,
    }, {
		animDict = BandageDict,
		anim = BandageAnim,
		flags = 1,
    }, {}, {}, function() -- Done
        StopAnimTask(ped, BandageDict, BandageAnim, 1.0)
		-- health adjust
		Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, 100) -- SetAttributeCoreValue (health)
		-- end health adjust
        -- A dressed wound stops bleeding: every bandage takes one bleeding level off. On a coin
        -- flip, half the bandages used to leave the player bleeding exactly as before.
        RemoveBleed(1)
        if math.random(1, 100) < 7 then
            ResetPartial()
        end
    end, function() -- Cancel
        StopAnimTask(ped, BandageDict, BandageAnim, 1.0)
        WCore.Functions.Notify(locale('error.canceled'), 'error')
    end)
end)

RegisterNetEvent('hospital:client:UsePainkillers', function(itemName)
    local ped = PlayerPedId()
    WCore.Functions.Progressbar("use_bandage", locale('progress.painkillers'), 3000, false, true, {
        disableMovement = false,
		disableMouse = false,
		disableCombat = true,
    }, {
		animDict = PainkillersDict,
		anim = PainkillersAnim,
		flags = 1,
    }, {}, {}, function() -- Done
        StopAnimTask(ped, PainkillersDict, PainkillersAnim, 1.0)
        onPainKillers = true
        if painkillerAmount < 3 then
            painkillerAmount = painkillerAmount + 1
        end
    end, function() -- Cancel
        StopAnimTask(ped, PainkillersDict, PainkillersAnim, 1.0)
        WCore.Functions.Notify(locale('error.canceled'), 'error')
    end)
end)

-- w_hud's medicines (health cure, restoratives, health serum: `heal = true` in its consumables)
-- announce themselves with this local event once the server has charged the bottle. Nothing
-- listened, so a medicine refilled the health bar and left the wounds and the bleeding it is
-- sold against as they were. It treats like the hospital's partial care: light wounds close,
-- light bleeding stops, and heavy bleeding eases one level (a doctor still has to see it).
-- ! ResetPartial first: easing first took 'bleeding a lot' (3) down to 2, which ResetPartial
--   then stopped outright - a bottle did more for a gunshot than a bandage does (one level).
AddEventHandler('w_hud:client:healed', function()
    if isDead or InLaststand then return end
    ResetPartial()
    if (tonumber(isBleeding) or 0) > 2 then
        RemoveBleed(1)
        -- ResetPartial synced the level before the easing; a medic's status check reads this copy
        TriggerServerEvent('hospital:server:SyncInjuries', { limbs = BodyParts, isBleeding = tonumber(isBleeding) })
    end
end)

-- Threads

CreateThread(function()
    while true do
        Wait(1)
        if onPainKillers then
            painkillerAmount = painkillerAmount - 1
            Wait(Config.PainkillerInterval * 1000)
            if painkillerAmount <= 0 then
                painkillerAmount = 0
                onPainKillers = false
            end
        else
            Wait(3000)
        end
    end
end)

CreateThread(function()
	while true do
		if #injured > 0 and Config.Injuries ~= false then
			local level = 0
			for k, v in pairs(injured) do
				if v.severity > level then
					level = v.severity
				end
			end
			SetPedMoveRateOverride(PlayerPedId(), Config.MovementRate[level])
			Wait(5)
		else
			Wait(1000)
		end
	end
end)

CreateThread(function()
    Wait(2500)
    prevPos = GetEntityCoords(PlayerPedId(), true)
    while true do
        Wait(1000)
        if isBleeding > 0 and not onPainKillers then
            local player = PlayerPedId()
            if bleedTickTimer >= Config.BleedTickRate and not isInHospitalBed then
                if not isDead and not InLaststand then
                    if isBleeding > 0 then
                        if fadeOutTimer + 1 == Config.FadeOutTimer then
                            if blackoutTimer + 1 == Config.BlackoutTimer then
                                DoScreenFadeOut(500)
                                while not IsScreenFadedOut() do
                                    Wait(0)
                                end

                                if not IsPedRagdoll(player) and IsPedOnFoot(player) and not IsPedSwimming(player) then
                                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', Config.ShakeGameplayCam) -- change this float to increase/decrease camera shake
                                    SetPedToRagdollWithFall(player, 7500, 9000, 1, GetEntityForwardVector(player), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                                end

                                Wait(1500)
                                DoScreenFadeIn(1000)
                                blackoutTimer = 0
                            else
                                DoScreenFadeOut(500)
                                while not IsScreenFadedOut() do
                                    Wait(0)
                                end
                                DoScreenFadeIn(500)

                                if isBleeding > 3 then
                                    blackoutTimer = blackoutTimer + 2
                                else
                                    blackoutTimer = blackoutTimer + 1
                                end
                            end

                            fadeOutTimer = 0
                        else
                            fadeOutTimer = fadeOutTimer + 1
                        end

                        local bleedDamage = tonumber(isBleeding) * Config.BleedTickDamage
                        ApplyDamageToPed(player, bleedDamage, false)
                        DoBleedAlert()
                        playerHealth = playerHealth - bleedDamage
                        -- (the QBCore blood drop for an evidence resource is gone: none runs here)

                        if advanceBleedTimer >= Config.AdvanceBleedTimer then
                            ApplyBleed(1)
                            advanceBleedTimer = 0
                        else
                            advanceBleedTimer = advanceBleedTimer + 1
                        end
                    end
                end
                bleedTickTimer = 0
            else
                if math.floor(bleedTickTimer % (Config.BleedTickRate / 10)) == 0 then
                    local currPos = GetEntityCoords(player, true)
                    local moving = #(vector2(prevPos.x, prevPos.y) - vector2(currPos.x, currPos.y))
                    if (moving > 1 and not IsPedInAnyVehicle(player)) and isBleeding > 2 then
                        advanceBleedTimer = advanceBleedTimer + Config.BleedMovementAdvance
                        bleedTickTimer = bleedTickTimer + Config.BleedMovementTick
                        prevPos = currPos
                    else
                        bleedTickTimer = bleedTickTimer + 1
                    end
                end
                bleedTickTimer = bleedTickTimer + 1
            end
        end
    end
end)
