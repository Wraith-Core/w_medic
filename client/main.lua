local getOutDict = 'script_re@campfire_massacre'
local getOutAnim = 'cry_getup_man'
local walkHealthDict = 'arthur_healthy'
local walkHealthAnim = 'default'
local canLeaveBed = true
local bedOccupying = nil
local bedObject = nil
local bedOccupyingData = nil
-- One per bed stay (SendToBed, LeaveBed, the logout reset): a yielding bed thread (SetBedCam, the
-- AI heal timer, LeaveBed's get-up animation) that finds another value has been overtaken and stops,
-- so it never acts on the next bed stay or the next character.
local bedGeneration = 0
local closestBed = nil
local doctorCount = 0
local CurrentDamageList = {}
inBedDict = "script_common@dead@male"
inBedAnim = "faceup_01"
isInHospitalBed = false
isBleeding = 0
bleedTickTimer, advanceBleedTimer = 0, 0
fadeOutTimer, blackoutTimer = 0, 0
legCount = 0
armcount = 0
headCount = 0
playerHealth = nil
isDead = false
isReviving = false  -- a resurrect is in progress (see resurrect below)
isStatusChecking = false
statusChecks = {}
statusCheckTime = 0
isHealingPerson = false
injured = {}

-- label = dictionary key (also sent to the server and shown to the doctor in his own language)
BodyParts = {
    ['HEAD'] =          { label = 'body.head',          causeLimp = false, isDamaged = false, severity = 0 },
    ['NECK'] =          { label = 'body.neck',          causeLimp = false, isDamaged = false, severity = 0 },
    ['SPINE'] =         { label = 'body.spine',         causeLimp = true, isDamaged = false, severity = 0 },
    ['UPPER_BODY'] =    { label = 'body.upper_body',    causeLimp = false, isDamaged = false, severity = 0 },
    ['LOWER_BODY'] =    { label = 'body.lower_body',    causeLimp = true, isDamaged = false, severity = 0 },
    ['LARM'] =          { label = 'body.left_arm',      causeLimp = false, isDamaged = false, severity = 0 },
    ['LHAND'] =         { label = 'body.left_hand',     causeLimp = false, isDamaged = false, severity = 0 },
    ['LFINGER'] =       { label = 'body.left_fingers',  causeLimp = false, isDamaged = false, severity = 0 },
    ['LLEG'] =          { label = 'body.left_leg',      causeLimp = true, isDamaged = false, severity = 0 },
    ['LFOOT'] =         { label = 'body.left_foot',     causeLimp = true, isDamaged = false, severity = 0 },
    ['RARM'] =          { label = 'body.right_arm',     causeLimp = false, isDamaged = false, severity = 0 },
    ['RHAND'] =         { label = 'body.right_hand',    causeLimp = false, isDamaged = false, severity = 0 },
    ['RFINGER'] =       { label = 'body.right_fingers', causeLimp = false, isDamaged = false, severity = 0 },
    ['RLEG'] =          { label = 'body.right_leg',     causeLimp = true, isDamaged = false, severity = 0 },
    ['RFOOT'] =         { label = 'body.right_foot',    causeLimp = true, isDamaged = false, severity = 0 },
}

-- damage reason keys, translated with locale() where shown
WeaponDamageList = {
	['WEAPON_UNARMED'] = 'damage.unarmed',
	['WEAPON_ANIMAL'] = 'damage.animal',
	['WEAPON_COUGAR'] = 'damage.animal',
    ['WEAPON_REVOLVER_CATTLEMAN'] = 'damage.revolver',
	['WEAPON_REVOLVER_CATTLEMAN_MEXICAN'] = 'damage.revolver',
	['WEAPON_REVOLVER_DOUBLEACTION_GAMBLER'] = 'damage.revolver',
	['WEAPON_REVOLVER_SCHOFIELD'] = 'damage.revolver',
	['WEAPON_REVOLVER_LEMAT'] = 'damage.revolver',
	['WEAPON_REVOLVER_NAVY'] = 'damage.revolver',
	['WEAPON_PISTOL_VOLCANIC'] = 'damage.pistol',
	['WEAPON_PISTOL_M1899'] = 'damage.pistol',
	['WEAPON_PISTOL_MAUSER'] = 'damage.pistol',
	['WEAPON_PISTOL_SEMIAUTO'] = 'damage.pistol',
	['WEAPON_REPEATER_CARBINE'] = 'damage.rifle',
	['WEAPON_REPEATER_WINCHESTER'] = 'damage.rifle',
	['WEAPON_REPEATER_HENRY'] = 'damage.rifle',
	['WEAPON_REPEATER_EVANS'] = 'damage.rifle',
	['WEAPON_RIFLE_VARMINT'] = 'damage.rifle',
	['WEAPON_RIFLE_SPRINGFIELD'] = 'damage.rifle',
	['WEAPON_RIFLE_BOLTACTION'] = 'damage.rifle',
	['WEAPON_RIFLE_ELEPHANT'] = 'damage.rifle',
	['WEAPON_SHOTGUN_DOUBLEBARREL'] = 'damage.shotgun',
	['WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC'] = 'damage.shotgun',
	['WEAPON_SHOTGUN_SAWEDOFF'] = 'damage.shotgun',
	['WEAPON_SHOTGUN_SEMIAUTO'] = 'damage.shotgun',
	['WEAPON_SNIPERRIFLE_ROLLINGBLOCK'] = 'damage.sniper',
	['WEAPON_SNIPERRIFLE_ROLLINGBLOCK_EXOTIC'] = 'damage.sniper',
	['WEAPON_SNIPERRIFLE_CARCANO'] = 'damage.sniper',
	['WEAPON_BOW'] = 'damage.bow',
	['WEAPON_BOW_IMPROVED'] = 'damage.bow',
	['WEAPON_LASSO'] = 'damage.placeholder',
    ['WEAPON_LASSO_REINFORCED'] = 'damage.placeholder',
	['WEAPON_MELEE_KNIFE'] = 'damage.stab',
	['WEAPON_MELEE_KNIFE_JAWBONE']  = 'damage.stab',
	['WEAPON_MELEE_HAMMER'] = 'damage.placeholder',
	['WEAPON_THROWN_DYNAMITE'] = 'damage.placeholder',
	['WEAPON_THROWN_MOLOTOV'] = 'damage.placeholder',
	['WEAPON_THROWN_THROWING_KNIVES'] = 'damage.stab',
	['WEAPON_THROWN_TOMAHAWK'] = 'damage.stab',
	['WEAPON_THROWN_TOMAHAWK_ANCIENT'] = 'damage.stab',
	['WEAPON_THROWN_BOLAS'] = 'damage.placeholder',
	['WEAPON_MELEE_CLEAVER'] = 'damage.placeholder',
	['WEAPON_MELEE_LANTERN'] = 'damage.hburns',
	['WEAPON_MELEE_DAVY_LANTERN'] = 'damage.hburns',
	['WEAPON_MELEE_TORCH'] = 'damage.hburns',
	['WEAPON_MELEE_HATCHET'] = 'damage.stab',
	['WEAPON_MELEE_MACHETE'] = 'damage.stab',
	-- the names below are the game's own damage sources (falls, fire, wagon collisions...)
	['WEAPON_DROWNING'] = 'damage.drowned',
	['WEAPON_DROWNING_IN_VEHICLE'] = 'damage.drowned',
	['WEAPON_BLEEDING'] = 'damage.blood',
	['WEAPON_EXPLOSION'] = 'damage.burns',
	['WEAPON_FALL'] = 'damage.bones',
	['WEAPON_EXHAUSTION'] = 'damage.exhaustion',
	['WEAPON_RAMMED_BY_CAR'] = 'damage.cart',
	['WEAPON_RUN_OVER_BY_CAR'] = 'damage.veh',
	['WEAPON_FIRE'] = 'damage.mburns',
}

-- Functions

-- The longest a caller waits for exports.w_creators:Resurrect (ms). Its own waits are bounded
-- (a render in flight 15 s, the new ped Config.Respawn.resurrectTimeoutMs, then the appearance
-- restore); past this bound a player still down is resurrected with the native.
local RESURRECT_WAIT_MS = 45000
local reviving = 0 -- resurrects in progress (isReviving mirrors it: > 0)

local function playerDown()
    local ped = PlayerPedId()
    return IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
end

-- Resurrect the local player through w_creators' respawn service (it re-applies the saved
-- appearance afterwards); the plain native while w_creators is not running. Yields until the
-- player is resurrected. While it runs isReviving is set: the death watcher, the last stand
-- countdown and the respawn prompt stand still (the downed state is cleared by the caller after).
-- The export yields (a __cfx_async_retval awaited with no timeout): it runs in its own thread so a
-- w_creators stop or restart mid-call can never leave this caller (SetBedCam, the revive) hanging.
--- The character's own look after a native resurrect. A resurrected ped can come back with parts of
--- his body missing; vorp_character's reload after death (what VORP's own revive and /rc do) puts
--- the skin back, and its server signal (vorpcharacter:reloadedskinlistener) has murphy_clothing
--- put the outfit back and murphy_barber the hair and beard. It touches neither the ped's tasks nor
--- its position, so a patient laid in a bed right after keeps his pose.
--- ★ 2026-10-14 (owner): "a revive reloads the skin, so his limbs come back whole".
local function reloadAppearance()
    if GetResourceState('vorp_character') ~= 'started' then return end
    Wait(200) -- as VORP's own revive: the resurrected ped settles first
    TriggerEvent('vorpcharacter:reloadafterdeath')
end

local function resurrect(pos, heading)
    reviving = reviving + 1
    isReviving = true
    local useNative = GetResourceState('w_creators') ~= 'started'
    if not useNative then
        local done, called, result = false, false, nil
        CreateThread(function()
            called, result = pcall(function() return exports.w_creators:Resurrect(pos, heading, 'hospital') end)
            done = true
        end)
        local deadline = GetGameTimer() + RESURRECT_WAIT_MS
        while not done and GetResourceState('w_creators') == 'started' and GetGameTimer() < deadline do
            Wait(50)
        end
        if done and not called then
            useNative = true            -- the export is missing / threw before resurrecting anything
        elseif not done then
            -- w_creators stopped mid-call or never answered: its resurrect is gone
            useNative = playerDown()
        end
        -- done with false: refused (another resurrect in flight finishes the job) or already
        -- tried and failed inside w_creators; resurrecting over it would race that restore
    end
    if useNative then
        NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading, true, false)
        reloadAppearance() -- (w_creators' own resurrect re-applies the saved appearance itself)
    end
    reviving = reviving - 1
    isReviving = reviving > 0
end

local function GetAvailableBed(bedId)
    local pos = GetEntityCoords(PlayerPedId())
    local retval = nil
    if bedId == nil then
        for k, v in pairs(Config.Locations['beds']) do
            if not Config.Locations['beds'][k].taken then
                if #(pos - vector3(Config.Locations['beds'][k].coords.x, Config.Locations['beds'][k].coords.y, Config.Locations['beds'][k].coords.z)) < 500 then
                        retval = k
                end
            end
        end
    else
        if not Config.Locations['beds'][bedId].taken then
            if #(pos - vector3(Config.Locations['beds'][bedId].coords.x, Config.Locations['beds'][bedId].coords.y, Config.Locations['beds'][bedId].coords.z))  < 500 then
                retval = bedId
            end
        end
    end
    return retval
end

local function GetDamagingWeapon(ped)
    for k, v in pairs(Config.Weapons) do
        if Citizen.InvokeNative(0xDCF06D0CDFF68424, ped, k, 0) then -- _HAS_ENTITY_BEEN_DAMAGED_BY_WEAPON
            return v
        end
    end

    return nil
end

local function IsDamagingEvent(damageDone, weapon)
    local luck = math.random(100)
    local multi = damageDone / Config.HealthDamage

    return luck < (Config.HealthDamage * multi) or (damageDone >= Config.ForceInjury or multi > Config.MaxInjuryChanceMulti or Config.ForceInjuryWeapons[weapon])
end

local function DoLimbAlert()
    if not isDead and not InLaststand then
        if #injured > 0 then
            local limbDamageMsg = ''
            if #injured <= Config.AlertShowInfo then
                for k, v in pairs(injured) do
                    limbDamageMsg = limbDamageMsg .. locale('info.pain_message', locale(v.label), locale(Config.WoundStates[v.severity] or ''))
                    if k < #injured then
                        limbDamageMsg = limbDamageMsg .. " | "
                    end
                end
            else
                limbDamageMsg = locale('info.many_places')
            end
            WCore.Functions.Notify(limbDamageMsg, 'primary')
        end
    end
end

local function DoBleedAlert()
    if not isDead and tonumber(isBleeding) > 0 then
        WCore.Functions.Notify(locale('info.bleed_alert', locale(Config.BleedingStates[tonumber(isBleeding)].label)), 'primary')
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

local function SetClosestBed()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    for k, v in pairs(Config.Locations['beds']) do
        local dist2 = #(pos - vector3(Config.Locations['beds'][k].coords.x, Config.Locations['beds'][k].coords.y, Config.Locations['beds'][k].coords.z))
        if current then
            if dist2 < dist then
                current = k
                dist = dist2
            end
        else
            dist = dist2
            current = k
        end
    end
    if current ~= closestBed and not isInHospitalBed then
        closestBed = current
    end
end

local function IsInjuryCausingLimp()
    for k, v in pairs(BodyParts) do
        if v.causeLimp and v.isDamaged then
            return true
        end
    end
    return false
end

local function ProcessRunStuff(ped, bone)
    -- no wounds: the walk style is never touched (it used to be reset to arthur_healthy after
    -- every heal and revive, over whatever style the player had chosen)
    if Config.Injuries == false then return end
    if bone ~= nil then
        if IsInjuryCausingLimp() then
            if Config.Bones[bone] == "RLEG" then
                w.print.debug('Injured RLEG Walkstyle')
                Citizen.InvokeNative(0x923583741DC87BCE, ped, 'default')
                Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_right_leg')
            elseif Config.Bones[bone] == "LLEG" then
                w.print.debug('Injured LLEG Walkstyle')
                Citizen.InvokeNative(0x923583741DC87BCE, ped, 'default')
                Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_left_leg')
            elseif Config.Bones[bone] == "RARM" then
                w.print.debug('Injured RARM Walkstyle')
                Citizen.InvokeNative(0x923583741DC87BCE, ped, 'default')
                Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_right_arm')
            elseif Config.Bones[bone] == "LARM" then
                w.print.debug('Injured LARM Walkstyle')
                Citizen.InvokeNative(0x923583741DC87BCE, ped, 'default')
                Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_left_arm')
            else
                w.print.debug('Injured Walkstyle')
                Citizen.InvokeNative(0x923583741DC87BCE, ped, 'default')
                Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_general')
            end
        end
    else
        w.print.debug('Normal Walkstyle')
		Citizen.InvokeNative(0x923583741DC87BCE, ped, "arthur_healthy")
		Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, "normal")
    end
end

function ResetPartial()
    for k, v in pairs(BodyParts) do
        if v.isDamaged and v.severity <= 2 then
            v.isDamaged = false
            v.severity = 0
        end
    end

    for k, v in pairs(injured) do
        if v.severity <= 2 then
            v.severity = 0
            table.remove(injured, k)
        end
    end

    if isBleeding <= 2 then
        isBleeding = 0
        bleedTickTimer = 0
        advanceBleedTimer = 0
        fadeOutTimer = 0
        blackoutTimer = 0
    end

    TriggerServerEvent('hospital:server:SyncInjuries', {
        limbs = BodyParts,
        isBleeding = tonumber(isBleeding)
    })

    ProcessRunStuff(PlayerPedId(), nil)
    DoLimbAlert()
    DoBleedAlert()

    TriggerServerEvent('hospital:server:SyncInjuries', {
        limbs = BodyParts,
        isBleeding = tonumber(isBleeding)
    })
end

local function ResetAll()
    isBleeding = 0
    bleedTickTimer = 0
    advanceBleedTimer = 0
    fadeOutTimer = 0
    blackoutTimer = 0
    injured = {}

    for k, v in pairs(BodyParts) do
        v.isDamaged = false
        v.severity = 0
    end

    TriggerServerEvent('hospital:server:SyncInjuries', {
        limbs = BodyParts,
        isBleeding = tonumber(isBleeding)
    })

    CurrentDamageList = {}
    TriggerServerEvent('hospital:server:SetWeaponDamage', CurrentDamageList)

    ProcessRunStuff(PlayerPedId(), nil)
    DoLimbAlert()
    DoBleedAlert()

    TriggerServerEvent('hospital:server:SyncInjuries', {
        limbs = BodyParts,
        isBleeding = tonumber(isBleeding)
    })
    local ped = PlayerPedId()
    local playerId = PlayerId()
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, 100) -- Health Core
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, 100) -- Stamina Core
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 2, 100) -- Dead Eye Core
    Citizen.InvokeNative(0x675680D089BFA21F, ped, 100.0)  -- RestorePedStamina
    if playerId and playerId ~= -1 then
        pcall(RestorePlayerStamina, playerId, 1.0)
        pcall(Citizen.InvokeNative, 0xC41F4B6E23FE6A4A, playerId, 1.0) -- RestorePlayerStamina (1.0 = 100%)
    end
    LocalPlayer.state:set('stamina', 100, true)
    -- Hunger and thirst are not refilled from here any more: a client's own refill
    -- (WCore:Server:SetMetaData) is refused by w_core, and the server refills them with the heal
    -- that led here (server/main.lua refillNeeds: a revive, the treatment, the bed, the admin heals).
end

local function SetBedCam(gen)
    isInHospitalBed = true
    canLeaveBed = false
    local player = PlayerPedId()

    DoScreenFadeOut(1000)

    while not IsScreenFadedOut() do
        Wait(100)
        if gen ~= bedGeneration then DoScreenFadeIn(500) return end
    end

	if IsPedDeadOrDying(player) then
		local pos = GetEntityCoords(player, true)
		resurrect(pos, GetEntityHeading(player))
		player = PlayerPedId() -- the appearance restore may have replaced the ped
    end
    if gen ~= bedGeneration then DoScreenFadeIn(500) return end

    bedObject = GetClosestObjectOfType(bedOccupyingData.coords.x, bedOccupyingData.coords.y, bedOccupyingData.coords.z, 1.0, bedOccupyingData.model, false, false, false)
    FreezeEntityPosition(bedObject, true)

    SetEntityCoords(player, bedOccupyingData.coords.x, bedOccupyingData.coords.y, bedOccupyingData.coords.z + 0.07)
    SetEntityInvincible(PlayerPedId(), true)
    Wait(500)
    if gen ~= bedGeneration then DoScreenFadeIn(500) return end
    FreezeEntityPosition(player, true)

    w.requestAnimDict(inBedDict)

    TaskPlayAnim(player, inBedDict , inBedAnim, 8.0, 1.0, -1, 1, 0, 0, 0, 0 )
    SetEntityHeading(player, bedOccupyingData.coords.w)

    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", 1)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 1, true, true)
    AttachCamToPedBone(cam, player, Config.BoneIndexes['HEAD'], 0, 1.0, 1.0 , true)
    SetCamFov(cam, 90.0)
    local heading = GetEntityHeading(player)
    heading = (heading > 180) and heading - 180 or heading + 180
    SetCamRot(cam, -45.0, 0.0, heading, 2)

    DoScreenFadeIn(1000)

    Wait(1000)
    if gen ~= bedGeneration then return end
    FreezeEntityPosition(player, true)
end

-- Drop the bed camera (only stops the script-camera rendering when it is still the one on screen:
-- another script's camera, such as w_creators' character selection, is left alone).
local function destroyBedCam()
    if cam and DoesCamExist(cam) then
        if IsCamRendering(cam) then RenderScriptCams(false, false, 0, true, true) end
        DestroyCam(cam, false)
    end
    cam = nil
end

-- Forget the bed stay at once (the character is logging out): the pending AI heal and a get-up in
-- progress are cancelled, the bed is handed back and the ped is no longer held by the bed.
local function ResetBedState()
    local wasInBed = isInHospitalBed or bedOccupying ~= nil
    bedGeneration = bedGeneration + 1
    if bedOccupying then
        TriggerServerEvent("hospital:server:LeaveBed", bedOccupying)
    end
    if wasInBed then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        ClearPedTasks(ped)
        destroyBedCam()
    end
    bedOccupying = nil
    bedObject = nil
    bedOccupyingData = nil
    isInHospitalBed = false
    canLeaveBed = true
end

local function LeaveBed()
    local player = PlayerPedId()
    local gen = bedGeneration
    if not bedOccupyingData then return end

    w.requestAnimDict(getOutDict)

    FreezeEntityPosition(player, false)
    SetEntityInvincible(player, false)
    SetEntityHeading(player, bedOccupyingData.coords.w - 90)
    TaskPlayAnim(player, getOutDict , getOutAnim, 100.0, 1.0, -1, 8, -1, 0, 0, 0)
    Wait(4000)
    if gen ~= bedGeneration then return end -- the logout reset already handed the bed back
    bedGeneration = bedGeneration + 1
    ClearPedTasks(player)
    TriggerServerEvent('hospital:server:LeaveBed', bedOccupying)
    FreezeEntityPosition(bedObject, true)
    RenderScriptCams(0, true, 200, true, true)
    DestroyCam(cam, false)
    cam = nil

    bedOccupying = nil
    bedObject = nil
    bedOccupyingData = nil
    isInHospitalBed = false
end

local function IsInDamageList(damage)
    local retval = false
    if CurrentDamageList then
        for k, v in pairs(CurrentDamageList) do
            if CurrentDamageList[k] == damage then
                retval = true
            end
        end
    end
    return retval
end

local function CheckWeaponDamage(ped)
    local detected = false
    for k, v in pairs(WeaponDamageList) do
        if Citizen.InvokeNative(0xDCF06D0CDFF68424, ped, GetHashKey(k), 0) then -- _HAS_ENTITY_BEEN_DAMAGED_BY_WEAPON
            detected = true
            if not IsInDamageList(k) then
                WCore.Functions.Notify(locale('info.status') .. ': ' .. locale(v), 'primary')
                CurrentDamageList[#CurrentDamageList+1] = k
            end
        end
    end
    if detected then
        TriggerServerEvent("hospital:server:SetWeaponDamage", CurrentDamageList)
    end
    ClearEntityLastDamageEntity(ped)
end

local function ApplyImmediateEffects(ped, bone, weapon, damageDone)
    local area = Config.Bones[bone]
    if Config.MinorInjurWeapons[weapon] and damageDone < Config.DamageMinorToMajor then
        if Config.CriticalAreas[area] then
            ApplyBleed(1)
        end

        if Config.StaggerAreas[area] then
            if math.random(100) <= math.ceil(Config.StaggerAreas[area].minor) then
                SetPedToRagdoll(ped, 1500, 2000, 3, true, true, false)
            end
        end
    elseif Config.MajorInjurWeapons[weapon] or (Config.MinorInjurWeapons[weapon] and damageDone >= Config.DamageMinorToMajor) then
        if Config.CriticalAreas[area] then
            ApplyBleed(1)
        elseif math.random(100) < Config.MajorBleedChance then
            ApplyBleed(1)
        end

        if Config.StaggerAreas[area] then
            if math.random(100) <= math.ceil(Config.StaggerAreas[area].major) then
                SetPedToRagdoll(ped, 1500, 2000, 3, true, true, false)
            end
        end
    end
end

local function CheckDamage(ped, bone, weapon, damageDone)
    if weapon == nil then return end

    if Config.Bones[bone] and not isDead and not InLaststand then
        ApplyImmediateEffects(ped, bone, weapon, damageDone)

        if not BodyParts[Config.Bones[bone]].isDamaged then
            BodyParts[Config.Bones[bone]].isDamaged = true
            BodyParts[Config.Bones[bone]].severity = math.random(1, 3)
            injured[#injured+1] = {
                part = Config.Bones[bone],
                label = BodyParts[Config.Bones[bone]].label,
                severity = BodyParts[Config.Bones[bone]].severity
            }
        else
            if BodyParts[Config.Bones[bone]].severity < 4 then
                BodyParts[Config.Bones[bone]].severity = BodyParts[Config.Bones[bone]].severity + 1

                for k, v in pairs(injured) do
                    if v.part == Config.Bones[bone] then
                        v.severity = BodyParts[Config.Bones[bone]].severity
                    end
                end
            end
        end

        TriggerServerEvent('hospital:server:SyncInjuries', {
            limbs = BodyParts,
            isBleeding = tonumber(isBleeding)
        })

        ProcessRunStuff(ped, bone)
    end
end

local function ProcessDamage(ped)
    if not isDead and not InLaststand and not onPainKillers then
        for k, v in pairs(injured) do
            if (v.part == 'LLEG' and v.severity > 1) or (v.part == 'RLEG' and v.severity > 1) or (v.part == 'LFOOT' and v.severity > 2) or (v.part == 'RFOOT' and v.severity > 2) then
                if legCount >= Config.LegInjuryTimer then
                    if not IsPedRagdoll(ped) and IsPedOnFoot(ped) then
                        local chance = math.random(100)
                        if (IsPedRunning(ped) or IsPedSprinting(ped)) then
                            if chance <= Config.LegInjuryChance.Running then
                                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', Config.ShakeGameplayCam) -- change this float to increase/decrease camera shake
                                SetPedToRagdollWithFall(ped, 1500, 2000, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                            end
                        else
                            if chance <= Config.LegInjuryChance.Walking then
                                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', Config.ShakeGameplayCam) -- change this float to increase/decrease camera shake
                                SetPedToRagdollWithFall(ped, 1500, 2000, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                            end
                        end
                    end
                    legCount = 0
                else
                    legCount = legCount + 1
                end
            elseif (v.part == 'LARM' and v.severity > 1) or (v.part == 'LHAND' and v.severity > 1) or (v.part == 'LFINGER' and v.severity > 2) or (v.part == 'RARM' and v.severity > 1) or (v.part == 'RHAND' and v.severity > 1) or (v.part == 'RFINGER' and v.severity > 2) then
                if armcount >= Config.ArmInjuryTimer then
                    -- a wounded arm or hand makes the gun drop for a moment
                    local isDisabled = 15
                    CreateThread(function()
                        while isDisabled > 0 do
                            if IsPlayerFreeAiming(PlayerId()) then
                                DisablePlayerFiring(PlayerId(), true) -- Disable weapon firing
                            end

                            isDisabled = isDisabled - 1
                            Wait(1)
                        end
                    end)

                    armcount = 0
                else
                    armcount = armcount + 1
                end
            elseif (v.part == 'HEAD' and v.severity > 2) then
                if headCount >= Config.HeadInjuryTimer then
                    local chance = math.random(100)

                    if chance <= Config.HeadInjuryChance then
                        DoScreenFadeOut(100)
                        while not IsScreenFadedOut() do
                            Wait(0)
                        end

                        if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', Config.ShakeGameplayCam) -- change this float to increase/decrease camera shake
                            SetPedToRagdoll(ped, 5000, 1, 2)
                        end

                        Wait(5000)
                        DoScreenFadeIn(250)
                    end
                    headCount = 0
                else
                    headCount = headCount + 1
                end
            end
        end
    end
end

RegisterNetEvent('ambulance:client:HealPlayer', function()
    local player = PlayerPedId()
    local playerId = PlayerId()
    local maxHealth = GetEntityMaxHealth(player)
    if not maxHealth or maxHealth < 100 then maxHealth = 100 end
    SetEntityHealth(player, maxHealth)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 0, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 1, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 2, 100)
    Citizen.InvokeNative(0x675680D089BFA21F, player, 100.0)
    if playerId and playerId ~= -1 then
        pcall(RestorePlayerStamina, playerId, 1.0)
        pcall(Citizen.InvokeNative, 0xC41F4B6E23FE6A4A, playerId, 1.0)
    end
    LocalPlayer.state:set('stamina', 100, true)
    ClearPedBloodDamage(player)
end)

-- Station actions run from the check-in / bed prompts (client/job.lua)
--
-- Check-in used to heal the patient with no medic in the room: the desk looked at
-- Config.MinimalDoctors, and below that number it dropped the patient into a free bed and let
-- the hospital treat him (SendToBed -> scheduleBedHeal). That was the desk treatment: a player
-- walked in, pressed the button and was fixed, with no fee and nobody involved.
--
-- Now the desk only calls a medic. Config.OnlyTouchedByDoctors (default true) is the switch:
--     true  -> the patient is paged and waits for a doctor; nobody is healed by the desk
--     false -> the old behaviour, so it can be switched back without a rewrite
function CheckIn()
    if Config.OnlyTouchedByDoctors ~= false then
        -- No medic treats the patient here any more: the desk pages the doctors and stops. The
        -- patient is not put in a bed, because a bed is what used to do the treating.
        if doctorCount <= 0 then
            WCore.Functions.Notify(locale('error.doctors_only'), 'error')
        end
        TriggerServerEvent("hospital:server:SendDoctorAlert")
        return
    end

    if doctorCount >= Config.MinimalDoctors then
        TriggerServerEvent("hospital:server:SendDoctorAlert")
    else
        WCore.Functions.Progressbar("hospital_checkin", locale('progress.checking_in'), 2000, false, true, {
            disableMovement = true,
            disableVehicleMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() -- Done
            local bedId = GetAvailableBed()
            if bedId then

                TriggerServerEvent("hospital:server:SendToBed", bedId, true)
            else
				WCore.Functions.Notify(locale('error.beds_taken'), 'error')
            end
        end, function() -- Cancel
            WCore.Functions.Notify(locale('error.canceled'), 'error')
        end)
    end
end

-- Lie in the closest bed (paid, healed by the hospital)
--
-- This is the second way in, and the desk check alone would not close it: the bed prompt is a
-- separate button in the same room, and it reaches the same self-treatment. With
-- Config.OnlyTouchedByDoctors on, the bed is not a treatment either: the patient is paged and
-- the room is left empty. What the bed IS still good for is lying down to be treated by a
-- medic who comes, which is why only the self-heal is removed and not the bed itself.
function LieInBed()
    if Config.OnlyTouchedByDoctors ~= false then
        if doctorCount <= 0 then
            WCore.Functions.Notify(locale('error.doctors_only'), 'error')
        end
        TriggerServerEvent("hospital:server:SendDoctorAlert")
        return
    end

    if GetAvailableBed(closestBed) then
        TriggerServerEvent("hospital:server:SendToBed", closestBed, true)
    else
        WCore.Functions.Notify(locale('error.beds_taken'), 'error')
    end
end

-- Events

RegisterNetEvent('hospital:client:ambulanceAlert', function(coords, text)
    -- `text` is a dictionary key (info.civ_down) or free text from /911e: locale() returns
    -- unknown strings unchanged, so the doctor reads the alert in his own language.
    text = locale(text)
    -- One notice (title + description) instead of two back-to-back toasts; 'ambulance' was
    -- never a notify variant, so the alert uses 'inform' and gets the library's default styling.
    WCore.Functions.Notify({ text = locale('text.alert'), caption = text }, 'inform')
    local transG = 250
    local blip = w.blip.create(vector3(coords.x, coords.y, coords.z), locale('info.ems_alert', text), 960467426, nil, nil, 0.2)
    while transG ~= 0 do
        Wait(Config.DispatchTimer * 4)
        transG = transG - 1
        if transG == 0 then
            RemoveBlip(blip)
            return
        end
    end
end)

--- The cabinet handed something over. Sent by the server after it has already decided (job, duty,
--- stock, this medic's window, carrying space) -- the page only says what arrived. On the bags
--- with a runtime shop API (w_inventory) the shop UI does this instead and never sends the event.
RegisterNetEvent('hospital:client:PharmacyHandout', function(names)
    if type(names) ~= 'table' or #names == 0 then return end
    local labels = {}
    for i, name in ipairs(names) do
        local ok, label = pcall(function() return exports.w_lib:InvItemLabel(name) end)
        labels[i] = (ok and label) or name
    end
    WCore.Functions.Notify({ text = table.concat(labels, ', '), caption = locale('info.pharmacy_given') }, 'inform')
end)

--- Stamina full again once a revive has settled. The resurrect, and vorp_character's skin reload
--- right after it (reloadAppearance), re-initialise the ped on their own frames: the fill made at
--- once lands first and is wiped, and the player stood up with an empty stamina ring. VORP's own
--- revive fills it ~2.7 s after its resurrect for the same reason. Three passes (about 1, 2.5 and
--- 5 s) cover a slow skin load; each one only tops up a ped that is alive.
--- ★ 2026-10-14 (owner): "a revive at the doctor leaves the stamina at zero".
local staminaRefill = 0
local function refillStaminaSoon()
    staminaRefill = staminaRefill + 1
    local mine = staminaRefill
    CreateThread(function()
        for _, delay in ipairs({ 1000, 1500, 2500 }) do
            Wait(delay)
            if mine ~= staminaRefill then return end -- a newer revive runs its own passes
            local ped = PlayerPedId()
            if ped ~= 0 and not IsEntityDead(ped) then
                local max = tonumber(GetPedMaxStamina(ped)) or 0
                RestorePedStamina(ped, max > 0 and max + 0.0 or 100.0)
                SetAttributeCoreValue(ped, 1, 100)
            end
        end
    end)
end

RegisterNetEvent('hospital:client:Revive', function()
    local player = PlayerPedId()
    local playerId = PlayerId()

    -- ★ 2026-10-15: also a dead ped this resource has not flagged yet (the watcher polls every 250 ms,
    --   and skips while another resurrect runs): healing a dead body without resurrecting it left
    --   the player dead with full health and the death camera on screen
    if isDead or InLaststand or IsEntityDead(player) then
        local pos = GetEntityCoords(player, true)
        resurrect(pos, GetEntityHeading(player))
        player = PlayerPedId() -- the appearance restore may have replaced the ped
        isDead = false
        SetEntityInvincible(player, false)
        SetLaststand(false)
    end

    if isInHospitalBed then
        w.requestAnimDict(inBedDict)
        TaskPlayAnim(player, inBedDict , inBedAnim, 8.0, 1.0, -1, 1, 0, 0, 0, 0 )
        SetEntityInvincible(player, true)
        canLeaveBed = true
    end

    TriggerServerEvent("hospital:server:RestoreWeaponDamage")
    local maxHealth = GetEntityMaxHealth(player)
    if not maxHealth or maxHealth < 100 then maxHealth = 100 end
    SetEntityHealth(player, maxHealth)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 0, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 1, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, player, 2, 100)
    Citizen.InvokeNative(0x675680D089BFA21F, player, 100.0)
    if playerId and playerId ~= -1 then
        pcall(RestorePlayerStamina, playerId, 1.0)
        pcall(Citizen.InvokeNative, 0xC41F4B6E23FE6A4A, playerId, 1.0)
    end
    LocalPlayer.state:set('stamina', 100, true)
    refillStaminaSoon()
    ClearPedBloodDamage(player)
    ResetAll()
    TriggerServerEvent("hospital:server:SetDeathStatus", false)
    TriggerServerEvent("hospital:server:SetLaststandStatus", false)
    emsNotified = false
    WCore.Functions.Notify(locale('info.healthy'), 'primary')
end)

-- w_creators fires this local event after every resurrect it performs. One this resource did not
-- ask for (reason ~= 'hospital': an admin respawn, another death system) leaves the player alive,
-- so the downed state is cleared here without resurrecting again.
AddEventHandler('w_creators:client:resurrected', function(reason)
    if reason == 'hospital' then return end
    if not isDead and not InLaststand then return end
    isDead = false
    deathTime = 0
    emsNotified = false
    SetEntityInvincible(PlayerPedId(), false)
    if InLaststand then SetLaststand(false) end
    TriggerServerEvent("hospital:server:SetDeathStatus", false)
    TriggerServerEvent("hospital:server:SetLaststandStatus", false)
end)

RegisterNetEvent('hospital:client:SetPain', function()
    if Config.Injuries == false then return end -- no wounds on this server (Config.Injuries)
    ApplyBleed(math.random(1,4))
    if not BodyParts[Config.Bones[14410]].isDamaged then
        BodyParts[Config.Bones[14410]].isDamaged = true
        BodyParts[Config.Bones[14410]].severity = math.random(1, 4)
        injured[#injured+1] = {
            part = Config.Bones[14410],
            label = BodyParts[Config.Bones[14410]].label,
            severity = BodyParts[Config.Bones[14410]].severity
        }
    end

    if not BodyParts[Config.Bones[54187]].isDamaged then
        BodyParts[Config.Bones[54187]].isDamaged = true
        BodyParts[Config.Bones[54187]].severity = math.random(1, 4)
        injured[#injured+1] = {
            part = Config.Bones[54187],
            label = BodyParts[Config.Bones[54187]].label,
            severity = BodyParts[Config.Bones[54187]].severity
        }
    end

    TriggerServerEvent('hospital:server:SyncInjuries', {
        limbs = BodyParts,
        isBleeding = tonumber(isBleeding)
    })
end)


RegisterNetEvent('hospital:client:KillPlayer', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('hospital:client:HealInjuries', function(type)
    if type == "full" then

        ResetAll()
    else
        ResetPartial()
    end
    TriggerServerEvent("hospital:server:RestoreWeaponDamage")
    WCore.Functions.Notify(locale('success.wounds_healed'), 'success')
end)

RegisterNetEvent('hospital:client:SendToBed', function(id, data, isRevive)
    bedGeneration = bedGeneration + 1
    local gen = bedGeneration
    bedOccupying = id
    bedOccupyingData = data
    SetBedCam(gen)
    if gen ~= bedGeneration then return end
    CreateThread(function ()
        Wait(5)
        if gen ~= bedGeneration then return end
        if isRevive then
            WCore.Functions.Notify(locale('success.being_helped'), 'success')
            Wait(Config.AIHealTimer * 1000)
            -- the bed stay ended meanwhile (a logout / character switch): never heal the next one
            if gen ~= bedGeneration or not isInHospitalBed then return end
            TriggerEvent("hospital:client:Revive")
        else
            canLeaveBed = true
        end
    end)
end)

RegisterNetEvent('hospital:client:SetBed', function(id, isTaken)
    Config.Locations['beds'][id].taken = isTaken
end)

RegisterNetEvent('hospital:client:RespawnAtHospital', function()
    TriggerServerEvent("hospital:server:RespawnAtHospital", closestBed)
    -- ! w_policejob is not on every server (MajestyRP has none): calling an export of a missing
    --   resource throws, which used to error on every respawn
    if GetResourceState('w_policejob') == 'started' then
        local ok, cuffed = pcall(function() return exports['w_policejob']:IsHandcuffed() end)
        if ok and cuffed then
            TriggerEvent("police:client:GetCuffed", -1)
        end
    end
    TriggerEvent("police:client:DeEscort")
end)

--- A respawn in a town with no beds (Config.RespawnPoints): the server chose the point; the player
--- wakes up standing there behind a fade, then gets the hospital's full heal (the Revive below).
RegisterNetEvent('hospital:client:WakeAt', function(index)
    local point = Config.RespawnPoints and Config.RespawnPoints[tonumber(index)]
    if not point then return end
    local c = point.coords
    DoScreenFadeOut(800)
    local deadline = GetGameTimer() + 3000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(50) end
    resurrect(vector3(c.x, c.y, c.z), c.w)
    local ped = PlayerPedId()
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, c.w)
    -- up already: the Revive below must not resurrect a second time, only heal
    isDead = false
    if InLaststand then SetLaststand(false) end
    TriggerEvent('hospital:client:Revive')
    Wait(500)
    DoScreenFadeIn(800)
end)

RegisterNetEvent('hospital:client:SetDoctorCount', function(amount)
    doctorCount = amount
end)

RegisterNetEvent('hospital:client:adminHeal', function()
    local ped = PlayerPedId()
    local playerId = PlayerId()
    local maxHealth = GetEntityMaxHealth(ped)
    if not maxHealth or maxHealth < 100 then maxHealth = 100 end
    SetEntityHealth(ped, maxHealth)
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, 100)
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 2, 100)
    Citizen.InvokeNative(0x675680D089BFA21F, ped, 100.0)
    if playerId and playerId ~= -1 then
        pcall(RestorePlayerStamina, playerId, 1.0)
        pcall(Citizen.InvokeNative, 0xC41F4B6E23FE6A4A, playerId, 1.0)
    end
    LocalPlayer.state:set('stamina', 100, true)
    ClearPedBloodDamage(ped)
    ResetAll() -- the needs: refilled by the server with /aheal and the HealPlayer export
end)

RegisterNetEvent('WCore:Client:OnPlayerUnload', function()
    local ped = PlayerPedId()

    TriggerServerEvent("hospital:server:SetDeathStatus", false)
    TriggerServerEvent('hospital:server:SetLaststandStatus', false)
    -- the bed stay belongs to the character logging out (its bed, camera, invincibility, AI heal)
    ResetBedState()
    isDead = false
    deathTime = 0
    SetEntityInvincible(ped, false)
    ResetAll()
end)

-- Station blips (rebuilt on a language switch so the map names follow the dictionary)
local stationBlips = {}

function RebuildStationBlips()
    for i = 1, #stationBlips do
        if DoesBlipExist(stationBlips[i]) then RemoveBlip(stationBlips[i]) end
    end
    stationBlips = {}
    for _, v in pairs(Config.Locations['stations']) do
        local blip = w.blip.create(vector3(v.coords.x, v.coords.y, v.coords.z), locale(v.label), 3599598875, nil, nil, 0.2)
        if blip then stationBlips[#stationBlips + 1] = blip end
    end
end

-- Threads
CreateThread(RebuildStationBlips)

-- Leaving the bed: a library prompt group shown while the patient is allowed to get up
-- (the player is frozen in the bed, so this is a state prompt rather than a proximity one)
local bedGroup = nil
local leavingBed = false

local function showBedPrompt()
    if bedGroup then return end
    bedGroup = w.prompt.createGroup(locale('text.bed'), 'bottom-right')
    bedGroup.addPrompt('E', locale('prompt.leave_bed'), false)
    bedGroup.display()
end

local function hideBedPrompt()
    if not bedGroup then return end
    bedGroup.hide()
    bedGroup.delete()
    bedGroup = nil
end

function RelabelBedPrompt()
    if not bedGroup then return end
    bedGroup.setTitle(locale('text.bed'))
    bedGroup.setLabel('E', locale('prompt.leave_bed'))
end

AddEventHandler('w_lib:promptCompleted', function(id, key)
    if not bedGroup or id ~= bedGroup.id or key ~= 'E' or leavingBed then return end
    if not (isInHospitalBed and canLeaveBed) then return end
    leavingBed = true
    hideBedPrompt()
    CreateThread(function()
        LeaveBed()
        leavingBed = false
    end)
end)

CreateThread(function()
    while true do
        local wanted = isInHospitalBed and canLeaveBed and not leavingBed
        if wanted and not bedGroup then
            showBedPrompt()
        elseif not wanted and bedGroup then
            hideBedPrompt()
        end
        Wait(250)
    end
end)

CreateThread(function()
    while true do
        Wait((1000 * Config.MessageTimer))
        DoLimbAlert()
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        SetClosestBed()
        if isStatusChecking then
            statusCheckTime = statusCheckTime - 1
            if statusCheckTime <= 0 then
                statusChecks = {}
                isStatusChecking = false
            end
        end
    end
end)

-- Damage watch: compares the health every tick and turns a drop into wounds
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped)

        if not playerHealth then
            playerHealth = health
        end

        local healthDamaged = (playerHealth ~= health) -- Players health was damaged

        local damageDone = (playerHealth - health)

        -- no wounds (Config.Injuries = false): a hit only takes health
        if healthDamaged and Config.Injuries ~= false then
            local hit, bone = GetPedLastDamageBone(ped)
            local bodypart = Config.Bones[bone]
            local weapon = GetDamagingWeapon(ped)

            if hit and bodypart ~= 'NONE' then
                if damageDone >= Config.HealthDamage then
                    if weapon and weapon ~= Config.WeaponClasses['NOTHING'] then
                        if IsDamagingEvent(damageDone, weapon) then
                            CheckDamage(ped, bone, weapon, damageDone)
                        end
                    end
                elseif Config.AlwaysBleedChanceWeapons[weapon] and weapon ~= Config.WeaponClasses['NOTHING'] then
                    if math.random(100) < Config.AlwaysBleedChance then
                        ApplyBleed(1)
                    end
                end
            end

            CheckWeaponDamage(ped)
        end

        playerHealth = health

        if not isInHospitalBed and Config.Injuries ~= false then
            ProcessDamage(ped)
        end
        Wait(100)
    end
end)


-- Client-side Exports
-- They heal the ped only: hunger and thirst are the server's to refill (the server exports
-- HealPlayer / RevivePlayer do both).
exports('HealPlayer', function()
    TriggerEvent('hospital:client:adminHeal')
    TriggerEvent('hospital:client:HealInjuries', 'full')
    return true
end)

exports('RevivePlayer', function()
    TriggerEvent('hospital:client:Revive')
    return true
end)

-- The death system's own down state (dead or in last stand), also while the ped is alive (the
-- hospital bed heal timer, a dead character logging in), and any hospital bed stay (a living
-- check-in / lie-in: the bed holds the ped, its camera and the pending AI heal): w_creators reads
-- it (WCSpawn.DEATH_OWNER.isDead) and refuses a character switch meanwhile.
exports('IsDead', function()
    return (isDead or InLaststand or isInHospitalBed) and true or false
end)

-- Is the player in a hospital bed (checked in, lying in, or respawned there)?
exports('InHospitalBed', function()
    return isInHospitalBed == true
end)

-- End the bed stay now (another resource moves the player away: w_creators' admin / death world
-- respawn): the bed is handed back, the pending AI heal and a get-up in progress are cancelled, the
-- lying animation, the bed camera, the freeze and the invincibility are dropped. The bed prompt
-- hides on its own (isInHospitalBed is false). Returns whether a stay was ended.
exports('EndBedStay', function()
    local wasInBed = isInHospitalBed or bedOccupying ~= nil
    ResetBedState()
    return wasInBed == true
end)
