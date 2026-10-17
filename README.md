# w_medic

Doctor job, wounds, bleeding, last stand and death handling for the Wraith Core server.

1.0.1: مفتاح فحص المريض والخروج من السرير والظهور في المستشفى بعد الموت صار J بدل E (لأن E يمسك اللاعب القريب).

## Dependencies
- w_lib (`[standalone]/w_lib`) — loaded first (`@w_lib/init.lua`), provides the dictionary, notifications, NUI prompts, on-screen text, blips, streaming helpers
- w_core — core object, callbacks, commands
- oxmysql

## Language
The library controls the language: `setr w_lib:locale "ar"` in server.cfg is the default and a player may switch in `/w_lib`.
The resource ships `locales/en.json` and `locales/ar.json` only; every player-facing string comes from them and the
client rebuilds prompt labels and station blips on `w_lib:setLocale`.

## Interaction
Every button is a library NUI prompt (w_lib):
- Stations (armory, duty, wagon yard, stash, check-in, beds) are `w.prompt.at` proximity prompts on `Config.PromptKey`
  within `Config.PromptDistance`; the doctor-only ones are hidden from other jobs (`canInteract`).
- A doctor standing next to a player gets a `w.prompt.atEntity` group on that player: `Config.PatientKeys`
  (check the patient, hold to treat the wounds with a bandage, hold to revive with a first aid kit).
- In a hospital bed a prompt group offers `J` to get out once the treatment is over.
- Dead / last stand: a prompt group carries the countdown as its title; `J` respawns at the hospital once the timer
  ran out, `G` calls a doctor while help is still possible.
The wagon yard spawns the wagons listed in `Config.AuthorizedVehicles` (RDR2 wagon models, per job grade).

## Wounds
Damage is classed by the weapon that caused it (`Config.Weapons`, RDR2 weapon hashes) and by the bone hit
(`Config.Bones`, RDR2 skeleton ids). Wounds cause limps, bleeding and blackouts; bandages, painkillers and
first aid kits treat them. There is no body armour in this game, so damage is always taken on health.

## Commands
- `/911e [message]` — alert the doctors on duty
- `/status`, `/treat`, `/revivep` — doctor tools
- `/medrevive [id]`, `/setpain [id]`, `/kill [id]`, `/aheal [id]` — admin
