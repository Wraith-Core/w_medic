Config = {}

--- Who is allowed to heal a patient, and who is not.
---
--- This replaces the old desk treatment. Check-in used to run this:
---     if doctorCount >= Config.MinimalDoctors then
---         TriggerServerEvent("hospital:server:SendDoctorAlert")   -- page a doctor
---     else
---         <the bed takes the patient and the hospital heals him>  -- self-treatment
---     end
--- So a player who walked in, pressed the desk and got into a free bed was healed by the
--- hospital itself, with no medic and no fee. That is the bot treatment that is gone.
---
--- OnlyTouchedByDoctors = true
---     A medic treats every patient, and nobody else is treated by the desk. A patient with
---     no medic on duty is paged as usual but never healed by the machine: the prompt says so
---     and nobody is put in a bed.
---
--- OnlyTouchedByDoctors = false
---     The old behaviour, kept only so it can be switched back for one run if it is ever wanted.
Config.OnlyTouchedByDoctors = false

--- How many medics must be on duty before the desk pages them instead of taking the patient.
--- Read only when OnlyTouchedByDoctors is false; with it true this no longer changes anything.
Config.MinimalDoctors = 2
Config.WipeInventoryOnRespawn = false
Config.DispatchTimer = 180 --DispatchTimer*4
-- Library prompts (w.prompt.at / w.prompt.atEntity): key names come from the w_lib rawKeys
-- vocabulary (upper-case). PromptKey opens the station prompts (armory, duty, wagons, stash,
-- check-in, beds); PromptDistance is how close the player must stand, in metres.
Config.PromptKey = 'R'
Config.PromptDistance = 1.5
-- Doctor next to a player: a prompt group follows the closest player within PatientDistance
Config.PatientDistance = 2.0
Config.PatientKeys = {
    status = 'E',   -- check the patient's wounds
    treat = 'G',    -- treat the wounds (bandage, held key)
    revive = 'F',   -- revive (first aid kit, held key)
}
Config.BillCost = 25

--- The items the job uses, by their name in the `items` table (db_tools/w_medic_items.sql adds the
--- missing ones; pictures in vorp_inventory/html/img/items/<name>.png).
--- ! 2026-10-14: the code asked for 'painkillers' and 'firstaid', which this server never had, so a
---    painkiller could not be used and no doctor could revive anybody. The revive item is the
---    syringe, as under gw-medic; the painkiller is the server's existing one.
-- ★ Red River (Wraith Core, 2026-10-14): the items w_inventory defines (data/items.lua) are
--   bandage, painkillers and firstaid -- the ones w_ambulancejob used. 'painkiller' and 'syringe'
--   do not exist in this bag, so the revive is the first aid kit, as it was here before.
Config.ItemNames = {
    bandage    = 'bandage',     -- dresses a wound: the doctor's treatment, or the player himself
    painkiller = 'painkillers', -- pain relief
    revive     = 'firstaid',    -- brings a downed player back: the doctor's revive, or anybody's
    ifak       = 'ifaks',       -- a first-aid pouch: heals over time
}

-- What the medic is paid for the job. Money comes out of society:doctor -- the same account the
-- patient's hospital bill (Config.BillCost above) fills -- so the job pays itself. It is handed over
-- only after every check in TreatWounds / RevivePlayer has passed and the bandage or the kit is
-- already spent, so no client can ask for it without doing the work.
Config.Pay = {
    enabled  = true,
    treat    = 20,   -- a wound dressed (matches gw-medic's MaxTaxAmount)
    revive   = 20,   -- a man brought back
    -- ! 2026-10-13: prices, salaries and ranks ported from gw-medic/config.lua
    -- (Config.MaxTaxAmount, Config.Ranks, Config.PaycheckInterval) so w_medic
    -- picks up where gw-medic left off, without losing the per-city locations,
    -- the pharmacy shelf, the cosmetic surgery prompt or the bed system that
    -- gw-medic never had. The job is "doctor" (set via /setjob 1 doctor <grade>).
    -- ★ Red River: 0 -- w_core pays the doctor's salary like every other job's (its grades carry
    --   Config.DoctorRanks' salaries, w_core/shared/jobs.lua), through the central bank's ledger.
    --   This resource paying too would pay every doctor twice.
    paycheckInterval = 0,   -- minutes between salary deposits (was gw-medic: 15)
}

-- The ranks from gw-medic. canAccessAdmin is what gw-medic itself used: the deputy and the
-- minister get the recruiting terminal. ★ Red River: numbered 0-5 with no gap (gw-medic had
-- 0-3, 5, 6 -- a hole at 4 that w_core's grade lists cannot carry); w_core/shared/jobs.lua
-- 'doctor' holds the same grades, names and salaries (w_core pays them).
Config.DoctorRanks = {
    [0] = { label = "  طـبـيـب مـتـدرب",   salary = 10.0,  canAccessAdmin = false },
    [1] = { label = "طـبـيـب مـتـمـرس", salary = 25.0,  canAccessAdmin = false },
    [2] = { label = " طـبـيـب امـتـيـاز", salary = 35.0,  canAccessAdmin = false },
    [3] = { label = " دكتور",          salary = 50.0,  canAccessAdmin = false },
    [4] = { label = " نائب وزير الصحة ", salary = 100.0, canAccessAdmin = true  },
    [5] = { label = "وزيـر الـصـحـة",   salary = 100.0, canAccessAdmin = true  },
}

-- Timings from gw-medic (ms)
Config.DoctorTiming = {
    healCooldownMs  = 5000,
    reviveTimeMs    = 5000,
    healTimeMs      = 3000,
    afkTimeoutMin   = 10,    -- auto clock-out if idle this long
}

-- gw-medic's desk NPC (the doctor behind the Valentine clinic's counter), at gw-medic's exact
-- coordinates. ★ 2026-10-14: he is the pharmacy's clerk - w_store places him as the cashier of the
-- Valentine pharmacy shop (Config.Pharmacy), so the doctors buy their supplies from him as they did
-- under gw-medic. The duty, check-in and stash prompts stay at their own spots in the same office,
-- each at least 3 m from him: two prompt groups at one spot fight over the screen.
Config.MDTDesk = {
    model = "cs_sddoctor_01",
    coords = vector4(-288.5232, 804.4839, 119.3859, 294.4160),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
}

-- Where a dead player wakes up: the nearest of these five (the respawn points players knew under
-- gw-death-screen, which used VORP's own hospital list). Valentine is the full hospital: a player
-- who wakes there is put in a free bed (Config.Locations.beds) and healed; at the other four he
-- wakes up standing at the point, healed. Both pay the hospital bill (Config.BillCost).
Config.RespawnPoints = {
    { name = 'Valentine',   coords = vector4(-283.83, 806.4, 119.38, 321.76), beds = true },
    { name = 'Saint Denis', coords = vector4(2721.4562, -1446.0975, 46.2303, 321.76) },
    { name = 'Armadillo',   coords = vector4(-3742.5, -2600.9, -13.23, 321.76) },
    { name = 'Blackwater',  coords = vector4(-723.9527, -1242.8358, 44.7341, 321.76) },
    { name = 'Rhodes',      coords = vector4(1229.0, -1306.1, 76.9, 321.76) },
}
Config.DeathTime = 60 -- (no longer read: the respawn key opens when the bleed-out below ends)
Config.CheckTime = 10
Config.PainkillerInterval = 60
Config.ShakeGameplayCam = 0.08 -- change this float to increase/decrease camera shake (0.00 to disable)
-- seconds of bleeding out before the respawn key (E, wake up at the doctor) opens
-- (2026-10-14, owner: 60, was 300)
Config.TimeTillRespawn = 60
-- the call-a-doctor key (G) opens once the bleed-out countdown is at or under this. Equal to
-- TimeTillRespawn = from the first second, as under GW (2026-10-14; was 180 = after two minutes).
-- Keep it equal to TimeTillRespawn when that one changes.
Config.MinimumRevive = 60

-- Wounds: bleeding, broken bones (the limbs), limping, the leg / arm / head effects (falls,
-- blackouts, the gun dropping from a hurt arm), their alerts, and the walk style they change.
-- false = none of it: a hit only takes health, and dying, the last stand, the revive, the beds and
-- the doctors' treatment work as before. (2026-10-14, owner: "no bleeding, no broken bones, none
-- of that". true brings the whole system back.)
Config.Injuries = false

-- Who revives: only a doctor on duty (his menu, or a syringe from his bag); nobody else, admins
-- included (2026-10-14, owner: "only the doctor revives, not even the admin"). AdminRevive = true
-- brings back /medrevive (an admin's revive by citizen id).
Config.AdminRevive = false

-- /911e [message]: an alert to the doctors on duty, from anybody. false = no such command: a downed
-- player calls a doctor with G on his death screen, and a standing one walks to the hospital
-- (2026-10-14, owner).
Config.EmsCallCommand = false

-- ★ 2026-10-14: Valentine only. The Saint Denis and Armadillo spots stood on custom buildings
--   (/stream/SaintDenis.ymap, /stream/Armadillo.ymap of the original job) that this server has never
--   streamed: their beds, desks and stashes were in the open street. The respawn reaches all five
--   towns through Config.RespawnPoints above.
Config.Locations = {
    ["checking"] = {
	    -- 2026-10-14: 1 m toward the door (was -286.28, 804.77): 2.2 m from the pharmacy clerk it sat
	    -- inside his prompt range, and two prompt groups at one spot fight over the screen
	    [1] = vector3(-285.28, 804.90, 119.3), -- Valentine
    },
    ["duty"] = {
        [1] = vector3(-284.49, 807.49, 119.38), -- Valentine
    },
    -- wagon yards: where the doctor's wagon is spawned
    ["vehicle"] = {
        [1] = vector4(-387.12, 775.3, 115.79, 189.93), -- Valentine Stable
    },
    -- Each armory carries its city name: the w_store pharmacy shelf is one row per hospital,
    -- so the server needs a name to match the shelf to and the doctor to stand at.
    -- ★ The Valentine pharmacy is gw-medic's desk: with Config.Pharmacy.useStore its clerk is the
    --   gw-medic doctor NPC (Config.MDTDesk), placed there by w_store.
    ["armory"] = {
        { coords = vector3(-288.5232, 804.4839, 119.3859), city = 'Valentine' },
    },
    ["stash"] = {
        [1] = vector3(-288.79, 808.83, 119.38), -- Valentine
    },
    ["beds"] = {
        [1] = {coords = vector4(-282.19, 814.46, 118.9, 96.10), taken = false, model = -2121768533}, -- Valentine 1
        [2] = {coords = vector4(-284.01, 813.39, 118.9, 5.67), taken = false, model = -2121768533}, -- Valentine 2
    },
    -- label = dictionary key, translated with locale() where it is shown
    ["stations"] = {
        [1] = {label = 'info.v_hospital', coords = vector4(-284.49, 807.49, 119.38, 104.89)}, -- Valentine
    }
}

-- Cosmetic surgery at the hospital stations (performed by w_creators). The station prompt asks
-- this resource's server, which opens the clinic through exports.w_creators:OpenCosmeticSurgery;
-- w_creators re-validates the service, the clinic, the distance and the price, and charges the
-- player. clinicId = the id of a w_creators location of type 'surgery' (w_creators
-- config/locations.lua); coords = where the prompt is shown (the w_creators clinic coords are the
-- proximity anchor, so keep them within a few metres). enabled = false removes the prompts.
-- Keep each prompt away from the station prompts (duty, check-in, stash, beds…): w_lib shows only
-- the closest walk-up prompt and a tie goes to the one created first (the station prompts), so a
-- clinic prompt on the same spot as the duty prompt is never shown to a doctor. The Valentine
-- prompt therefore stands ~2.7 m from the duty desk (and 2.7 m from its w_creators anchor, inside
-- the server's interactionRadius + 3 once PromptDistance is added).
Config.CosmeticSurgery = {
    -- ★ Red River: true -- w_creators runs here and performs it (its valentine / saintdenis /
    --   armadillo surgery locations). On a server without w_creators set it false: every press
    --   would end in "surgery unavailable".
    enabled = true,
    key = Config.PromptKey,
    cooldown = 3, -- seconds between two requests of one player
    clinics = {
        { clinicId = 'valentine_surgery', coords = vector3(-282.49, 809.29, 119.38) },    -- Valentine
        { clinicId = 'saintdenis_surgery', coords = vector3(2387.306, -1369.280, 46.541) }, -- Saint Denis
        { clinicId = 'armadillo_surgery', coords = vector3(-3651.82, -2649.4, -13.45) },  -- Armadillo
    },
}

-- model = dictionary key of the wagon name, translated with locale() when the wagon menu opens
-- Models are RDR2 wagon hashes (CHUCKWAGON000X is the covered supply wagon)
Config.AuthorizedVehicles = {
	-- Grade 0
	[0] = {
		["CHUCKWAGON000X"] = "vehicles.chuckwagon",
	},
	-- Grade 1
	[1] = {
		["CHUCKWAGON000X"] = "vehicles.chuckwagon",

	},
	-- Grade 2
	[2] = {
		["CHUCKWAGON000X"] = "vehicles.chuckwagon",
	},
	-- Grade 3
	[3] = {
		["CHUCKWAGON000X"] = "vehicles.chuckwagon",
	},
	-- Grade 4
	[4] = {
		["CHUCKWAGON000X"] = "vehicles.chuckwagon",
	}
}

-- The pharmacy cabinet (the armory prompt). It has three shapes and takes the first one that
-- is available:
--   w_store       -> a real government shelf per hospital. The prices, the stock, the cashier
--                     ped and the blip are w_store's own, and an admin restocks it from the
--                     w_store panel. The rows are created on the first start (never again: an
--                     existing shelf is matched by name and left alone) and refreshed after.
--   w_inventory   -> a real server-side shop, so the bag owns the stock: it refuses an empty
--                     slot (w_inventory/modules/shops/server.lua:293) and takes one off the
--                     shelf on every purchase (:404).
--   other bags    -> a server handout, for the bags with no runtime shop API.
-- It used to be a shop table built fresh by the CLIENT on every prompt, which meant the cabinet
-- never ran out.
Config.Pharmacy = {
    enabled        = true,

    -- the w_store shelf (the default). Set false to go back to the bag's own shop or the handout.
    -- ★ Red River: false -- this server's w_store has no job-locked shelf (settings.jobs), so a
    --   doctors' shelf there would sell to anyone. w_inventory's shop checks the job itself.
    useStore       = false,
    -- how close the doctor must stand to the cabinet, in metres. The client prompts at
    -- Config.PromptDistance; this is the server's own wider gate for the same door.
    openDistance   = 6.0,
    -- the clerk who stands behind the counter; w_store spawns this model as the cashier ped
    cashier        = { model = 'u_m_m_sdcustomvendor_01', scenario = 'WORLD_HUMAN_CLIPBOARD' },
    blip           = true,   -- draw the shop's marker on the map
    blipSprite     = 'blip_shop_doctor',
    blipColor      = 'BLIP_MODIFIER_MP_COLOR_2',
    -- the price of each item on the w_store shelf (gw-medic's: bandage 5, syringe 15).
    -- ! Never 0: w_store refuses to sell a product priced 0 ('not_for_sale'), so the shelves seeded
    --    at 0 could hand out nothing (fixed 2026-10-14; existing shelves are corrected at start).
    storePrices    = { bandage = 5, painkillers = 8, firstaid = 15 },

    shopId         = 'hospital_pharmacy',
    -- who may open it at all: the bag checks the group itself, a prompt the client made does not.
    -- ! A map (job = lowest grade): w_inventory's hasGroup reads pairs(name, grade), so a list
    --   ({ 'doctor' }) matched nobody, the doctors included.
    groups = { doctor = 0 },
    restockMinutes = 60,   -- the cabinet is refilled on this cycle; a restart also refills it
    stock          = {     -- how many of each are on the shelf at the start of a cycle
        bandage     = 20,
        painkillers = 10,
        firstaid    = 10,
    },

    -- The handout path, used on the bags with no runtime shop API (vorp_inventory, rsg-inventory,
    -- qbr-inventory): one press at the cabinet prompt hands over what is listed here, and the
    -- server checks the job, the duty, the shelf, this medic's own window and his carrying space.
    -- windowMinutes / maxPerWindow cap how often ONE medic may be served; maxPerVisit and
    -- perVisit cap how much that one press gives. The shelf above is the whole hospital's stock.
    windowMinutes  = 60,
    maxPerWindow   = 3,
    maxPerVisit    = 2,
    perVisit       = { bandage = 1, painkillers = 1, firstaid = 1 },
}

-- label = dictionary key, translated with locale() when the shop opens
Config.Items = {
    label = 'info.safe',
    slots = 10,
    items = {
        [1] = {
            name = "bandage",
            price = 0,
            amount = 20,
            info = {},
            type = "item",
            slot = 1,
        },
        [2] = {
            name = "painkillers",
            price = 0,
            amount = 10,
            info = {},
            type = "item",
            slot = 2,
        },
        [3] = {
            name = "firstaid",
            price = 0,
            amount = 10,
            info = {},
            type = "item",
            slot = 3,
        },
    }
}

--[[
    GENERAL SETTINGS | THESE WILL AFFECT YOUR ENTIRE SERVER SO BE SURE TO SET THESE CORRECTLY
    MaxHp : Maximum HP Allowed, set to -1 to leave the max health untouched
        NOTE: Anything under 100 and you are dead
    RegenRate : health regeneration multiplier (0.0 = none)
]]
Config.MaxHp = 100
Config.RegenRate = 0.0

--[[
    HealthDamage : How Much Damage To Direct HP Must Be Applied Before Checks For Damage Happens
]]
Config.HealthDamage = 5

--[[
    MaxInjuryChanceMulti : How many times the HealthDamage value above can divide into damage taken before damage is forced to be applied
    ForceInjury : Maximum amount of damage a player can take before limb damage & effects are forced to occur
]]
Config.MaxInjuryChanceMulti = 3
Config.ForceInjury = 35
Config.AlwaysBleedChance = 70

--[[
    Message Timer : How long it will take to display limb/bleed message
]]
Config.MessageTimer = 12

--[[
    AIHealTimer : How long it will take to be healed after checking in, in seconds
]]
Config.AIHealTimer = 20

--[[
    BleedTickRate : How much time, in seconds, between bleed ticks
]]
Config.BleedTickRate = 30

--[[
    BleedMovementTick : How many seconds is taken away from the bleed tick rate if the player is walking, jogging, or sprinting
    BleedMovementAdvance : How Much Time Moving While Bleeding Adds (This Adds This Value To The Tick Count, Meaing The Above BleedTickRate Will Be Reached Faster)
]]
Config.BleedMovementTick = 10
Config.BleedMovementAdvance = 3

--[[
    The Base Damage That Is Multiplied By Bleed Level Every Time A Bleed Tick Occurs
]]
Config.BleedTickDamage = 8

--[[
    FadeOutTimer : How many bleed ticks occur before fadeout happens
    BlackoutTimer : How many bleed ticks occur before blacking out
    AdvanceBleedTimer : How many bleed ticks occur before bleed level increases
]]
Config.FadeOutTimer = 2
Config.BlackoutTimer = 10
Config.AdvanceBleedTimer = 10

--[[
    HeadInjuryTimer : How much time, in seconds, do head injury effects chance occur
    ArmInjuryTimer : How much time, in seconds, do arm injury effects chance occur
    LegInjuryTimer : How much time, in seconds, do leg injury effects chance occur
]]
Config.HeadInjuryTimer = 30
Config.ArmInjuryTimer = 30
Config.LegInjuryTimer = 15

--[[
    The Chance, In Percent, That Certain Injury Side-Effects Get Applied
]]
Config.HeadInjuryChance = 25
Config.ArmInjuryChance = 25
Config.LegInjuryChance = {
    Running = 50,
    Walking = 15
}

--[[
    MajorBleedChance : The % Chance Someone Gets A Bleed Effect Applied When Taking Major Damage Outside A Critical Area
    (critical areas always bleed on major damage)
]]
Config.MajorBleedChance = 90

--[[
    DamgeMinorToMajor : How much damage would have to be applied for a minor weapon to be considered a major damage event. Put this at 100 if you want to disable it
]]
Config.DamageMinorToMajor = 35

--[[
    AlertShowInfo :
]]
Config.AlertShowInfo = 2

--[[
    The following lists use the Config.WeaponClasses indexes above.

    MinorInjurWeapons : Damage From These Weapons Will Apply Only Minor Injuries
    MajorInjurWeapons : Damage From These Weapons Will Apply Only Major Injuries
    AlwaysBleedChanceWeapons : Weapons that're in the included weapon classes will roll for a chance to apply a bleed effect if the damage wasn't enough to trigger an injury chance
    CriticalAreas : Body areas where any injuring hit starts a bleed
    StaggerAreas : These are the body areas that would cause a stagger if hit by firearms,
        Table Values: Major = % Chance You Get Staggered By Major Damage, Minor = % Chance You Get Staggered By Minor Damage
]]

Config.WeaponClasses = {
    ['SMALL_CALIBER'] = 1,
    ['MEDIUM_CALIBER'] = 2,
    ['HIGH_CALIBER'] = 3,
    ['SHOTGUN'] = 4,
    ['CUTTING'] = 5,
    ['LIGHT_IMPACT'] = 6,
    ['HEAVY_IMPACT'] = 7,
    ['EXPLOSIVE'] = 8,
    ['FIRE'] = 9,
    ['SUFFOCATING'] = 10,
    ['OTHER'] = 11,
    ['WILDLIFE'] = 12,
    ['NOTHING'] = 13
}

Config.MinorInjurWeapons = {
    [Config.WeaponClasses['SMALL_CALIBER']] = true,
    [Config.WeaponClasses['MEDIUM_CALIBER']] = true,
    [Config.WeaponClasses['CUTTING']] = true,
    [Config.WeaponClasses['WILDLIFE']] = true,
    [Config.WeaponClasses['OTHER']] = true,
    [Config.WeaponClasses['LIGHT_IMPACT']] = true,
}

Config.MajorInjurWeapons = {
    [Config.WeaponClasses['HIGH_CALIBER']] = true,
    [Config.WeaponClasses['HEAVY_IMPACT']] = true,
    [Config.WeaponClasses['SHOTGUN']] = true,
    [Config.WeaponClasses['EXPLOSIVE']] = true,
}

Config.AlwaysBleedChanceWeapons = {
    [Config.WeaponClasses['SMALL_CALIBER']] = true,
    [Config.WeaponClasses['MEDIUM_CALIBER']] = true,
    [Config.WeaponClasses['CUTTING']] = true,
    [Config.WeaponClasses['WILDLIFE']] = false,
}

Config.ForceInjuryWeapons = {
    [Config.WeaponClasses['HIGH_CALIBER']] = true,
    [Config.WeaponClasses['HEAVY_IMPACT']] = true,
    [Config.WeaponClasses['EXPLOSIVE']] = true,
}

Config.CriticalAreas = {
    ['UPPER_BODY'] = true,
    ['LOWER_BODY'] = true,
    ['SPINE'] = true,
}

Config.StaggerAreas = {
    ['SPINE'] = { major = 60, minor = 30 },
    ['UPPER_BODY'] = { major = 60, minor = 30 },
    ['LLEG'] = { major = 100, minor = 85 },
    ['RLEG'] = { major = 100, minor = 85 },
    ['LFOOT'] = { major = 100, minor = 100 },
    ['RFOOT'] = { major = 100, minor = 100 },
}

-- dictionary keys, translated with locale() where they are shown
Config.WoundStates = {
    'states.irritated',
    'states.quite_painful',
    'states.painful',
    'states.really_painful',
}

-- label = dictionary key, translated with locale() where it is shown
Config.BleedingStates = {
    [1] = {label = 'states.little_bleed', damage = 10, chance = 50},
    [2] = {label = 'states.bleed', damage = 15, chance = 65},
    [3] = {label = 'states.lot_bleed', damage = 20, chance = 65},
    [4] = {label = 'states.big_bleed', damage = 25, chance = 75},
}

Config.MovementRate = {
    0.98,
    0.96,
    0.94,
    0.92,
}

Config.Bones = {
    [0]     = 'NONE',
    -- HEAD
    [27981] = 'HEAD',
    [57278] = 'HEAD',
    [54890] = 'HEAD',
    [21030] = 'HEAD',
    -- NECK
    [24015] = 'NECK',
    [52596] = 'NECK',
    [32630] = 'NECK',
	[32631] = 'NECK',
	[32632] = 'NECK',
    [14283] = 'NECK',
	[14284] = 'NECK',
	[14285] = 'NECK',
    -- SPINE
    [14410] = 'SPINE',
    [14411] = 'SPINE',
	[14412] = 'SPINE',
	[14413] = 'SPINE',
	[14414] = 'SPINE',
    --UPPER_BODY
    [30226] = 'UPPER_BODY',
    -- LOWER_BODY
    [56200] = 'LOWER_BODY',
    -- LARM
    [43700] = 'LARM',
    [24238] = 'LARM',
    [55540] = 'LARM',
    [53562] = 'LARM',
    [53675] = 'LARM',
    -- LHAND
    [34606] = 'LHAND',
    -- LFINGER
    [41403] = 'LFINGER',
    [41404] = 'LFINGER',
    [41405] = 'LFINGER',
    [41323] = 'LFINGER',
    [41324] = 'LFINGER',
    [41325] = 'LFINGER',
    [41326] = 'LFINGER',
    [41307] = 'LFINGER',
    [41308] = 'LFINGER',
    [41309] = 'LFINGER',
    [41310] = 'LFINGER',
    [41355] = 'LFINGER',
    [41356] = 'LFINGER',
    [41357] = 'LFINGER',
    [41358] = 'LFINGER',
    [41339] = 'LFINGER',
    [41340] = 'LFINGER',
    [41341] = 'LFINGER',
    [41342] = 'LFINGER',
    [35940] = 'LFINGER',
	[43154] = 'LFINGER',
	[60440] = 'LFINGER',
	[35924] = 'LFINGER',
	[35908] = 'LFINGER',
	[35892] = 'LFINGER',
	[35876] = 'LFINGER',
	[55214] = 'LFINGER',
	[55198] = 'LFINGER',
	[55246] = 'LFINGER',
	[55230] = 'LFINGER',
    -- LLEG
    [40091] = 'LLEG',
    [52390] = 'LLEG',
	[65480] = 'LLEG',
	[21174] = 'LLEG',
	[49844] = 'LLEG',
	[38229] = 'LLEG',
	[51618] = 'LLEG',
	[17816] = 'LLEG',
    [21124] = 'LLEG',
	[12785] = 'LLEG',
	[881] = 'LLEG',
	[65034] = 'LLEG',
	[62433] = 'LLEG',
	[8936] = 'LLEG',
	[2474] = 'LLEG',
	[8980] = 'LLEG',
    [55253] = 'LLEG',
	[15681] = 'LLEG',
    [12865] = 'LLEG',
    [3003] = 'LLEG',
    [65478] = 'LLEG',
    [55120] = 'LLEG',
    -- LFOOT
    [45454] = 'LFOOT',
    -- RARM
    [54187] = 'RARM',
    [46065] = 'RARM',
    [46260] = 'RARM',
    [65198] = 'RARM',
    [31186] = 'RARM',
    -- RHAND
    [22798] = 'RHAND',
    -- RFINGER
    [16827] = 'RFINGER',
	[16828] = 'RFINGER',
	[16829] = 'RFINGER',
	[16747] = 'RFINGER',
	[16748] = 'RFINGER',
	[16749] = 'RFINGER',
	[16750] = 'RFINGER',
	[16731] = 'RFINGER',
	[16732] = 'RFINGER',
	[16733] = 'RFINGER',
	[16734] = 'RFINGER',
	[16779] = 'RFINGER',
	[16780] = 'RFINGER',
	[16781] = 'RFINGER',
	[16782] = 'RFINGER',
	[16763] = 'RFINGER',
	[16764] = 'RFINGER',
	[16765] = 'RFINGER',
	[16766] = 'RFINGER',
    [11364] = 'RFINGER',
	[41618] = 'RFINGER',
	[14992] = 'RFINGER',
	[11348] = 'RFINGER',
	[11332] = 'RFINGER',
	[11316] = 'RFINGER',
	[11300] = 'RFINGER',
	[61341] = 'RFINGER',
	[61325] = 'RFINGER',
	[61373] = 'RFINGER',
	[61357] = 'RFINGER',
	[36407] = 'RFINGER',
    -- RLEG
    [64298] = 'RLEG',
	[27814] = 'RLEG',
	[65384] = 'RLEG',
	[19638] = 'RLEG',
	[6170] = 'RLEG',
	[17720] = 'RLEG',
    [22660] = 'RLEG',
	[10571] = 'RLEG',
	[64874] = 'RLEG',
	[30131] = 'RLEG',
	[46712] = 'RLEG',
	[53296] = 'RLEG',
	[14866] = 'RLEG',
    [31046] = 'RLEG',
	[11991] = 'RLEG',
    [10651] = 'RLEG',
    [5217] = 'RLEG',
    [6884] = 'RLEG',
    -- RFOOT
    [33646] = 'RFOOT',
}

Config.BoneIndexes = {
    ['NONE'] = 0,
    ['HEAD'] = 21030, -- SKEL_HEAD
    ['NECK'] = 14284, -- SKEL_NECK1
    ['SPINE'] = 14413, -- SKEL_SPINE3
    ['UPPER_BODY'] = 30226, --SKEL_L_Clavicle
    ['LOWER_BODY'] = 56200, --SKEL_Pelvis
    ['LARM'] = 53675, --skel_l_forearm
    ['LHAND'] = 34606, --skel_l_hand
    ['LFINGER'] = 41339, --SKEL_L_Finger40
    ['LLEG'] = 55120, --SKEL_L_Calf
    ['LFOOT'] = 45454, --SKEL_L_Foot
    ['RARM'] = 54187, --skel_r_forearm
    ['RHAND'] = 22798, --skel_r_hand
    ['RFINGER'] = 16733, --SKEL_R_Finger22
    ['RLEG'] = 6884, --SKEL_R_Thigh
    ['RFOOT'] = 33646, --SKEL_R_Foot
}

Config.Weapons = {
    --[[ Small Caliber ]]--
    [`WEAPON_REVOLVER_CATTLEMAN`] = Config.WeaponClasses['SMALL_CALIBER'],
    [`WEAPON_REVOLVER_CATTLEMAN_MEXICAN`] = Config.WeaponClasses['SMALL_CALIBER'],
    [`WEAPON_REVOLVER_DOUBLEACTION_GAMBLER`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_REVOLVER_SCHOFIELD`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_REVOLVER_LEMAT`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_REVOLVER_NAVY`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_PISTOL_VOLCANIC`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_PISTOL_M1899`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_PISTOL_MAUSER`] = Config.WeaponClasses['SMALL_CALIBER'],
	[`WEAPON_PISTOL_SEMIAUTO`] = Config.WeaponClasses['SMALL_CALIBER'],
    --[[ MEDIUM_CALIBER ]]--
    [`WEAPON_REPEATER_CARBINE`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_REPEATER_WINCHESTER`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_REPEATER_HENRY`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_REPEATER_EVANS`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_RIFLE_VARMINT`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_RIFLE_SPRINGFIELD`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_RIFLE_BOLTACTION`] = Config.WeaponClasses['MEDIUM_CALIBER'],
	[`WEAPON_RIFLE_ELEPHANT`] = Config.WeaponClasses['MEDIUM_CALIBER'],
    --[[ 'HIGH_CALIBER' ]]--
    [`WEAPON_SNIPERRIFLE_ROLLINGBLOCK`] = Config.WeaponClasses['HIGH_CALIBER'],
	[`WEAPON_SNIPERRIFLE_ROLLINGBLOCK_EXOTIC`] = Config.WeaponClasses['HIGH_CALIBER'],
	[`WEAPON_SNIPERRIFLE_CARCANO`] = Config.WeaponClasses['HIGH_CALIBER'],
    --[[ 'SHOTGUN' ]]--
    [`WEAPON_SHOTGUN_DOUBLEBARREL`] = Config.WeaponClasses['SHOTGUN'],
	[`WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC`] = Config.WeaponClasses['SHOTGUN'],
	[`WEAPON_SHOTGUN_SAWEDOFF`] = Config.WeaponClasses['SHOTGUN'],
	[`WEAPON_SHOTGUN_SEMIAUTO`] = Config.WeaponClasses['SHOTGUN'],
    --[[ 'CUTTING' ]]--
    [`WEAPON_BOW`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_BOW_IMPROVED`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_LASSO`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_LASSO_REINFORCED`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_KNIFE`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_KNIFE_JAWBONE`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_HAMMER`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_DYNAMITE`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_MOLOTOV`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_THROWING_KNIVES`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_TOMAHAWK`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_TOMAHAWK_ANCIENT`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_THROWN_BOLAS`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_CLEAVER`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_LANTERN`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_DAVY_LANTERN`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_TORCH`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_HATCHET`] = Config.WeaponClasses['CUTTING'],
	[`WEAPON_MELEE_MACHETE`] = Config.WeaponClasses['CUTTING'],
    --[[ 'LIGHT_IMPACT' ]]--
    --[[ 'HEAVY_IMPACT' ]]--
    --[[ 'EXPLOSIVE' ]]--
    --[[ 'FIRE' ]]--
    --[[ 'SUFFOCATING' ]]--
    --[[ 'OTHER' ]]--
    --[[ 'WILDLIFE' ]]--
    --[[ 'NOTHING' ]]--
}

---------------------------------------------

-- The core object: the Wraith Core's when w_core runs. On VORP / RSG / QBR the job's calls
-- (WCore.Functions.*, WCore.Commands.Add) are served by server/wcore_shim.lua and
-- c/wcore_shim.lua through w_lib, which load right after this file.
-- ★ 2026-10-14: the bridge used to stand inline here, and nothing of the job worked under it on
--   VORP (see the header of server/wcore_shim.lua).
WCore = w.framework:getCoreObject()
