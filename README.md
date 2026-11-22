# w_medic

Doctor and hospital roleplay job (`doctor`, grades `0`–`5`) for **Wraith Framework RedM**.

## Key Features

- Wounding, bleeding, last-stand, death timer, hospital beds, treatment, and revives (integrated with `w_creators:Resurrect`).
- Built-in Hospital Pharmacy powered directly by `w_inventory:RegisterShop` (bandages, painkillers, first-aid kits with automatic restock cycles).
- On-site doctor hiring/ranking terminal at hospital desks.
- Emergency alert command (`/911e`) for on-duty doctors.

## Installation

1. Place `w_medic` in `resources/[wraith]/w_medic`.
2. Add `ensure w_medic` to `server.cfg` after `w_lib`, `w_core`, `w_inventory`, and `w_creators`.

## Commands & Exports

- **Commands:** `/911e`, `/treat`, `/status`, `/medrevive`, `/revivep`, `/aheal`, `/kill`, `/pharmacy`
- **Exports:** `IsDead()`, `InHospitalBed()`, `RevivePlayer(src)`, `HealPlayer(src)`, `EndBedStay()`

## Documentation & Links

- **Developer Docs:** https://wraith-core.github.io/docs/#/resources/economy-jobs
- **txAdmin Recipe:** https://github.com/Wraith-Core/txAdminRecipe

## License

GPL-3.0 — see [LICENSE](LICENSE).
